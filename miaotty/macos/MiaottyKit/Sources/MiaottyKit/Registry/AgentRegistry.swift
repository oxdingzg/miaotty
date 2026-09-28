import Foundation

/// Authoritative store for agent state. This is the single source of truth the
/// UI projects onto pane/tab badges (see design: state plane, LWW per key).
public final class AgentRegistry {
    public private(set) var revision: Int = 0
    private var seq: Int = 0
    private var states: [String: AgentStateInfo] = [:]

    private let lock = NSLock()

    /// Invoked (on the mutating thread) after a state change. The UI layer is
    /// expected to hop to the main thread and coalesce (see performance §6.1).
    public var onChange: (@Sendable (Int) -> Void)?

    public init() {}

    /// Stable identity for a state entry: pane > tty > (agent, session).
    public static func key(agent: String, sessionID: String?, paneID: String?, tty: String?) -> String {
        if let paneID { return "pane:\(paneID)" }
        if let tty { return "tty:\(tty)" }
        return "sess:\(agent):\(sessionID ?? "-")"
    }

    @discardableResult
    public func set(_ params: AgentStateSetParams) -> Int {
        lock.lock()
        revision += 1
        seq += 1
        let key = Self.key(agent: params.agent, sessionID: params.sessionId, paneID: params.paneId, tty: params.tty)
        states[key] = AgentStateInfo(
            agent: params.agent,
            sessionId: params.sessionId,
            paneId: params.paneId,
            state: params.state,
            cwd: params.cwd,
            bypass: params.bypass,
            errorKind: params.errorKind,
            title: params.title,
            ts: params.ts,
            seq: seq
        )
        let rev = revision
        lock.unlock()

        onChange?(rev)
        return rev
    }

    public func snapshot() -> (revision: Int, states: [AgentStateInfo]) {
        lock.lock()
        defer { lock.unlock() }
        return (revision, Array(states.values))
    }

    public var currentRevision: Int {
        lock.lock()
        defer { lock.unlock() }
        return revision
    }
}

public extension AgentRegistry {
    /// Highest-priority state across a set of panes, for tab badges.
    /// Priority: awaiting > error > processing > idle.
    static func badge(for states: [AgentStateInfo]) -> AgentState? {
        let order: [AgentState] = [.awaiting, .error, .processing, .idle]
        for candidate in order where states.contains(where: { $0.state == candidate }) {
            return candidate
        }
        return nil
    }
}
