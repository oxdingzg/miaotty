import Foundation

/// Metadata for a terminal pane. In the real app this is projected from the
/// Ghostty core via `HostBridge`; the scaffold uses an in-memory source.
public struct PaneInfo: Sendable, Equatable {
    public var id: String
    public var tty: String?
    public var childPid: Int32?
    public var cwd: String?
    public var title: String?
    public var focused: Bool

    public init(id: String, tty: String? = nil, childPid: Int32? = nil, cwd: String? = nil, title: String? = nil, focused: Bool = false) {
        self.id = id
        self.tty = tty
        self.childPid = childPid
        self.cwd = cwd
        self.title = title
        self.focused = focused
    }
}

/// Source of pane metadata. The macOS app implements this over the core;
/// the scaffold provides a mutable in-memory implementation.
public protocol PaneSource: AnyObject {
    func panes() -> [PaneInfo]
    func pane(id: String) -> PaneInfo?
}

public final class InMemoryPaneSource: PaneSource {
    private let lock = NSLock()
    private var items: [String: PaneInfo] = [:]

    public init() {}

    public func upsert(_ pane: PaneInfo) {
        lock.lock(); defer { lock.unlock() }
        items[pane.id] = pane
    }

    public func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        items[id] = nil
    }

    public func panes() -> [PaneInfo] {
        lock.lock(); defer { lock.unlock() }
        return Array(items.values)
    }

    public func pane(id: String) -> PaneInfo? {
        lock.lock(); defer { lock.unlock() }
        return items[id]
    }
}

/// Environment injected into every pane's shell so agents can bind to their
/// pane in O(1) instead of walking the process tree (design: performance §5.4).
public enum PaneEnv {
    public static let socketKey = "MIAOTTY_SOCKET"
    public static let paneKey = "MIAOTTY_PANE_ID"
    public static let protoKey = "MIAOTTY_PROTO"

    public static func environment(socketPath: String, paneID: String) -> [String: String] {
        [
            socketKey: socketPath,
            paneKey: paneID,
            protoKey: String(MTPCodec.protoVersion),
        ]
    }
}
