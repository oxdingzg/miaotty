import Foundation
import Darwin

/// MTP host: a Unix-domain socket server that owns the authoritative
/// agent-state registry and the extension registry.
///
/// Concurrency (design: performance §5.3): accept happens on a dedicated
/// queue; each connection is served on a background queue; nothing here runs
/// on the main thread or on any terminal hot path.
public final class HostServer {
    public let socketPath: String
    public let registry: AgentRegistry
    public let extensions: ExtensionRegistry
    public let panes: PaneSource
    public let sessionID = UUID().uuidString

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let acceptQueue = DispatchQueue(label: "miaotty.host.accept")
    private let ioQueue = DispatchQueue(label: "miaotty.host.io", attributes: .concurrent)

    public init(
        socketPath: String,
        registry: AgentRegistry = AgentRegistry(),
        extensions: ExtensionRegistry = ExtensionRegistry(),
        panes: PaneSource = InMemoryPaneSource()
    ) {
        self.socketPath = socketPath
        self.registry = registry
        self.extensions = extensions
        self.panes = panes
    }

    // MARK: - lifecycle

    public func start() throws {
        signal(SIGPIPE, SIG_IGN)
        try bindListener()
        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: acceptQueue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { [weak self] in
            guard let self, self.listenFD >= 0 else { return }
            close(self.listenFD)
            self.listenFD = -1
        }
        source.resume()
        acceptSource = source
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        unlink(socketPath)
    }

    private func bindListener() throws {
        unlink(socketPath)
        try? FileManager.default.createDirectory(
            atPath: (socketPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENODEV) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &addr.sun_path.0) { dst in
            bytes.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                memcpy(dst, base, bytes.count)
            }
        }

        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let e = errno
            close(fd)
            throw POSIXError(POSIXError.Code(rawValue: e) ?? .EIO)
        }
        chmod(socketPath, 0o600)

        guard listen(fd, 128) == 0 else {
            close(fd)
            throw POSIXError(.EIO)
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        listenFD = fd
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { return }
            // Same-uid only (design: security §12).
            if !peerIsSameUser(client) {
                close(client)
                continue
            }
            ioQueue.async { [weak self] in
                self?.serve(client)
            }
        }
    }

    private func peerIsSameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { return false }
        return uid == getuid()
    }

    // MARK: - serving

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        // The listener is non-blocking; accepted sockets may inherit the flag
        // on Darwin, which would make read() return EAGAIN and look like EOF.
        // Clear it and serve this connection with blocking reads on the io queue.
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        var pending = Data()
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 {
                if errno == EINTR { continue }
                return
            }
            if n == 0 { return }
            pending.append(contentsOf: buffer[0..<n])
            while let idx = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<idx]
                pending.removeSubrange(pending.startIndex...idx)
                handleLine(Data(line), fd: fd)
            }
        }
    }

    private func handleLine(_ line: Data, fd: Int32) {
        let response: Response
        do {
            let request = try MTPCodec.decodeLine(Request.self, from: line)
            response = dispatch(request)
        } catch {
            response = MTPCodec.errorResponse(id: 0, revision: registry.currentRevision, code: "bad_request", message: "\(error)")
        }
        if let data = try? MTPCodec.encodeLine(response) {
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var written = 0
                while written < data.count {
                    let n = write(fd, base + written, data.count - written)
                    if n <= 0 { return }
                    written += n
                }
            }
        }
    }

    // MARK: - dispatch

    private func dispatch(_ req: Request) -> Response {
        switch (req.ns, req.method) {
        case ("core", "ping"):
            let result = PingResult(
                proto: MTPCodec.protoVersion,
                appVersion: "miaotty-host/0.0.1",
                pid: Int(getpid()),
                caps: MTPHostCaps.value
            )
            return (try? MTPCodec.response(id: req.id, revision: registry.currentRevision, result: result))
                ?? MTPCodec.errorResponse(id: req.id, revision: registry.currentRevision, code: "internal", message: "encode")

        case ("core", "health"):
            let result = HealthResult(
                ok: true,
                revision: registry.currentRevision,
                connections: 1,
                eventsPerSec: 0,
                droppedEvents: 0
            )
            return (try? MTPCodec.response(id: req.id, revision: registry.currentRevision, result: result))
                ?? MTPCodec.errorResponse(id: req.id, revision: registry.currentRevision, code: "internal", message: "encode")

        case ("core", "hello"):
            let result = WelcomeParams(
                proto: MTPCodec.protoVersion,
                session: sessionID,
                caps: MTPHostCaps.value,
                limits: Limits(maxMessageBytes: 1 << 20, ratePerSec: 500, idleTimeoutMs: 300_000),
                revision: registry.currentRevision
            )
            return (try? MTPCodec.response(id: req.id, revision: registry.currentRevision, result: result))
                ?? MTPCodec.errorResponse(id: req.id, revision: registry.currentRevision, code: "internal", message: "encode")

        case ("agent", "state.set"):
            guard let params = req.params, let p = try? params.decode(AgentStateSetParams.self) else {
                return MTPCodec.errorResponse(id: req.id, revision: registry.currentRevision, code: "bad_request", message: "invalid AgentStateSetParams")
            }
            let revision = registry.set(p)
            return (try? MTPCodec.response(id: req.id, revision: revision, result: ["revision": revision]))
                ?? MTPCodec.errorResponse(id: req.id, revision: revision, code: "internal", message: "encode")

        case ("agent", "state.list"):
            let snap = registry.snapshot()
            let result = AgentStateListResult(revision: snap.revision, states: snap.states)
            return (try? MTPCodec.response(id: req.id, revision: snap.revision, result: result))
                ?? MTPCodec.errorResponse(id: req.id, revision: snap.revision, code: "internal", message: "encode")

        default:
            return MTPCodec.errorResponse(
                id: req.id,
                revision: registry.currentRevision,
                code: "bad_request",
                message: "unknown method \(req.ns).\(req.method)"
            )
        }
    }
}

/// Capabilities advertised by the host in the scaffold.
public enum MTPHostCaps {
    public static let value: [Capability] = [.coreBasic, .agentStateRead, .agentStateWrite]
}
