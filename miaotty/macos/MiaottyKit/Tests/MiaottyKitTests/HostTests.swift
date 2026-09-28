import Foundation
import Darwin
import XCTest
@testable import MiaottyKit

final class HostTests: XCTestCase {

    // MARK: - registry

    func testRegistryLastWriteWins() {
        let reg = AgentRegistry()
        reg.set(AgentStateSetParams(agent: "miao", paneId: "pane_1", state: .processing))
        reg.set(AgentStateSetParams(agent: "miao", paneId: "pane_1", state: .idle))
        let snap = reg.snapshot()
        XCTAssertEqual(snap.states.count, 1)
        XCTAssertEqual(snap.states.first?.state, .idle)
        XCTAssertEqual(snap.revision, 2)
    }

    func testBadgePriority() {
        let states = [
            AgentStateInfo(agent: "a", state: .idle),
            AgentStateInfo(agent: "b", state: .processing),
            AgentStateInfo(agent: "c", state: .awaiting),
        ]
        XCTAssertEqual(AgentRegistry.badge(for: states), .awaiting)
        XCTAssertEqual(AgentRegistry.badge(for: [AgentStateInfo(agent: "a", state: .error), AgentStateInfo(agent: "b", state: .processing)]), .error)
        XCTAssertNil(AgentRegistry.badge(for: []))
    }

    // MARK: - server

    func testServerPingAndStateRoundtrip() throws {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("miaotty-test-\(UUID().uuidString).sock")
        let server = HostServer(socketPath: path)
        try server.start()
        defer { server.stop() }

        let client = try TestClient(path: path)

        let ping: Response = try client.call(Request(v: 1, id: 1, kind: "req", ns: "core", method: "ping", params: nil, role: .client))
        XCTAssertTrue(ping.ok)
        XCTAssertNotNil(ping.result)

        let set: Response = try client.call(
            Request(v: 1, id: 2, kind: "req", ns: "agent", method: "state.set",
                    params: try AnyCodable(encoding: AgentStateSetParams(agent: "miao", paneId: "pane_9", state: .processing)))
        )
        XCTAssertTrue(set.ok)
        XCTAssertEqual(set.revision, 1)

        let list: Response = try client.call(Request(v: 1, id: 3, kind: "req", ns: "agent", method: "state.list", params: nil))
        XCTAssertTrue(list.ok)
        let decoded = try list.result!.decode(AgentStateListResult.self)
        XCTAssertEqual(decoded.states.count, 1)
        XCTAssertEqual(decoded.states.first?.state, .processing)

        let unknown: Response = try client.call(Request(v: 1, id: 4, kind: "req", ns: "core", method: "nope", params: nil))
        XCTAssertFalse(unknown.ok)
        XCTAssertEqual(unknown.error?.code, "bad_request")

        client.close()
    }
}

/// Minimal blocking MTP client used only by tests.
final class TestClient {
    private let fd: Int32
    private var buffer = Data()

    init(path: String) throws {
        signal(SIGPIPE, SIG_IGN)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { dst in
            bytes.withUnsafeBufferPointer { src in
                memcpy(dst, src.baseAddress!, bytes.count)
            }
        }
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 { throw POSIXError(.ECONNREFUSED) }
    }

    func call(_ request: Request) throws -> Response {
        let data = try MTPCodec.encodeLine(request)
        data.withUnsafeBytes { raw in
            _ = write(fd, raw.baseAddress, data.count)
        }
        while true {
            if let idx = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<idx]
                buffer.removeSubrange(buffer.startIndex...idx)
                return try MTPCodec.decodeLine(Response.self, from: Data(line))
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { throw POSIXError(.ECONNRESET) }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    func close() { Darwin.close(fd) }
}
