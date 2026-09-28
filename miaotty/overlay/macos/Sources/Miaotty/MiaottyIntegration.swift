import AppKit
import MiaottyKit
import GhosttyKit

// miaotty app integration (additive; compiled into the Ghostty target via the
// fileSystemSynchronized `Sources/` group). Binds Ghostty surfaces to the MTP
// host and renders agent-state badges.

extension Notification.Name {
    static let miaottyAgentStateChanged = Notification.Name("miaotty.agentStateChanged")
}

/// App-side glue: owns the MTP host and maps surfaces to panes.
final class MiaottyIntegration: PaneSource, @unchecked Sendable {
    static let shared = MiaottyIntegration()

    let registry = AgentRegistry()
    let extensions = ExtensionRegistry()
    private(set) var host: HostServer?
    private(set) var socketPath: String = ""

    private let lock = NSLock()
    private var paneByView: [ObjectIdentifier: String] = [:]
    private var surfaceByPane: [String: ghostty_surface_t] = [:]

    private init() {}

    /// Start the MTP host and export the socket to child processes. Called as
    /// early as possible so shells/agents inherit `MIAOTTY_*`.
    func start() {
        guard host == nil else { return }
        let socket = (NSTemporaryDirectory() as NSString).appendingPathComponent("miaotty.sock")
        socketPath = socket
        setenv("MIAOTTY_SOCKET", socket, 1)
        setenv("MIAOTTY_PROTO", "1", 1)

        // Coalesce registry changes onto one main-thread notification.
        registry.onChange = { rev in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .miaottyAgentStateChanged, object: nil, userInfo: ["revision": rev])
            }
        }

        let server = HostServer(socketPath: socket, registry: registry, extensions: extensions, panes: self)
        do {
            try server.start()
            host = server
            NSLog("miaotty: MTP host listening on \(socket)")
        } catch {
            NSLog("miaotty: failed to start MTP host: \(error)")
        }
    }

    /// Associate a surface with a fresh pane id and add its badge overlay.
    func attach(surface: ghostty_surface_t, to view: NSView) {
        let paneID = UUID().uuidString
        lock.lock()
        paneByView[ObjectIdentifier(view)] = paneID
        surfaceByPane[paneID] = surface
        lock.unlock()

        let badge = MiaottyBadgeView(paneID: paneID, integration: self)
        view.addSubview(badge)
    }

    func detach(view: NSView) {
        lock.lock()
        if let paneID = paneByView.removeValue(forKey: ObjectIdentifier(view)) {
            surfaceByPane[paneID] = nil
        }
        lock.unlock()
    }

    /// PID of the shell in a pane, via the miaotty C API patch point.
    func childPid(paneID: String) -> Int32 {
        lock.lock()
        let surface = surfaceByPane[paneID]
        lock.unlock()
        guard let surface else { return 0 }
        return ghostty_surface_child_pid(surface)
    }

    /// Aggregate badge state for a pane (nil if no agent state).
    func state(paneID: String) -> AgentState? {
        let snapshot = registry.snapshot()
        return AgentRegistry.badge(for: snapshot.states.filter { $0.paneId == paneID })
    }

    // MARK: - PaneSource (backed by live Ghostty surfaces)

    func panes() -> [PaneInfo] {
        lock.lock()
        let snapshot = surfaceByPane
        lock.unlock()
        return snapshot.map { (paneID, surface) in
            PaneInfo(id: paneID, childPid: ghostty_surface_child_pid(surface))
        }
    }

    func pane(id: String) -> PaneInfo? {
        lock.lock()
        let surface = surfaceByPane[id]
        lock.unlock()
        guard let surface else { return nil }
        return PaneInfo(id: id, childPid: ghostty_surface_child_pid(surface))
    }
}

/// A small pill showing the agent state for a pane. Positioned manually in the
/// bottom-right corner (no Auto Layout: frame updates must not happen while
/// drawing).
final class MiaottyBadgeView: NSView {
    private static let height: CGFloat = 22
    private static let margin: CGFloat = 12

    private let paneID: String
    private weak var integration: MiaottyIntegration?
    private var state: AgentState?
    private var textSize: NSSize = .zero

    init(paneID: String, integration: MiaottyIntegration) {
        self.paneID = paneID
        self.integration = integration
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.height))
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.masksToBounds = true
        isHidden = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: .miaottyAgentStateChanged, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func refresh() {
        state = integration?.state(paneID: paneID)
        NSLog("miaotty: badge pane=\(paneID) state=\(state.map { String(describing: $0) } ?? "none")")
        guard let state else {
            isHidden = true
            return
        }
        let text = Self.label(for: state) as NSString
        textSize = text.size(withAttributes: Self.attributes)
        let width = textSize.width + 20
        layer?.backgroundColor = Self.color(for: state).withAlphaComponent(0.85).cgColor
        if let superview {
            let x = max(Self.margin, superview.bounds.width - width - Self.margin)
            frame = NSRect(x: x, y: Self.margin, width: width, height: Self.height)
        } else {
            setFrameSize(NSSize(width: width, height: Self.height))
        }
        isHidden = false
        needsDisplay = true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        refresh()
    }

    private static var attributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
    }

    private static func color(for state: AgentState) -> NSColor {
        switch state {
        case .processing: return .systemBlue
        case .idle: return .systemGreen
        case .awaiting: return .systemOrange
        case .error: return .systemRed
        }
    }

    private static func label(for state: AgentState) -> String {
        switch state {
        case .processing: return "miao · working"
        case .idle: return "miao · idle"
        case .awaiting: return "miao · input?"
        case .error: return "miao · error"
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard state != nil else { return }
        let rect = NSRect(x: (bounds.width - textSize.width) / 2,
                          y: (bounds.height - textSize.height) / 2,
                          width: textSize.width, height: textSize.height)
        (Self.label(for: state ?? .idle) as NSString).draw(in: rect, withAttributes: Self.attributes)
    }
}
