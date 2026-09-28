import Foundation

/// One command executed in a pane, reported by the shell integration hook.
public struct HistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var paneId: String?
    public var command: String
    public var cwd: String?
    public var exitCode: Int?
    public var ts: Double?
    public var seq: Int?

    public init(
        id: String,
        paneId: String? = nil,
        command: String,
        cwd: String? = nil,
        exitCode: Int? = nil,
        ts: Double? = nil,
        seq: Int? = nil
    ) {
        self.id = id
        self.paneId = paneId
        self.command = command
        self.cwd = cwd
        self.exitCode = exitCode
        self.ts = ts
        self.seq = seq
    }

    enum CodingKeys: String, CodingKey {
        case id
        case paneId = "pane_id"
        case command
        case cwd
        case exitCode = "exit_code"
        case ts
        case seq
    }
}

public struct HistoryAddParams: Codable, Sendable {
    public var paneId: String?
    public var tty: String?
    public var command: String
    public var cwd: String?
    public var exitCode: Int?
    public var ts: Double?

    public init(paneId: String? = nil, tty: String? = nil, command: String, cwd: String? = nil, exitCode: Int? = nil, ts: Double? = nil) {
        self.paneId = paneId
        self.tty = tty
        self.command = command
        self.cwd = cwd
        self.exitCode = exitCode
        self.ts = ts
    }

    enum CodingKeys: String, CodingKey {
        case paneId = "pane_id"
        case tty
        case command
        case cwd
        case exitCode = "exit_code"
        case ts
    }
}

public struct HistoryListResult: Codable, Sendable {
    public var revision: Int
    public var entries: [HistoryEntry]

    public init(revision: Int, entries: [HistoryEntry]) {
        self.revision = revision
        self.entries = entries
    }
}

/// Per-pane command history, the data source for the details "Outline" tab.
/// Same LWW/append model as `AgentRegistry`: a lock, a revision counter, and
/// an `onChange` callback the UI coalesces onto the main thread.
public final class HistoryRegistry {
    public private(set) var revision: Int = 0
    private var seq: Int = 0
    private var entries: [String: [HistoryEntry]] = [:]

    /// Cap per pane so a long session cannot grow unbounded.
    public var maxEntriesPerPane: Int = 1000

    private let lock = NSLock()

    public var onChange: (@Sendable (Int) -> Void)?

    public init() {}

    public static func key(paneID: String?, tty: String?) -> String {
        if let paneID, !paneID.isEmpty { return "pane:\(paneID)" }
        if let tty, !tty.isEmpty { return "tty:\(tty)" }
        return "global"
    }

    @discardableResult
    public func add(_ params: HistoryAddParams) -> Int {
        lock.lock()
        revision += 1
        seq += 1
        let key = Self.key(paneID: params.paneId, tty: params.tty)
        let entry = HistoryEntry(
            id: "\(key)#\(seq)",
            paneId: params.paneId,
            command: params.command,
            cwd: params.cwd,
            exitCode: params.exitCode,
            ts: params.ts ?? (Date().timeIntervalSince1970 * 1000),
            seq: seq
        )
        var list = entries[key] ?? []
        list.append(entry)
        if list.count > maxEntriesPerPane {
            list.removeFirst(list.count - maxEntriesPerPane)
        }
        entries[key] = list
        let rev = revision
        lock.unlock()

        onChange?(rev)
        return rev
    }

    /// Newest-last list for a pane (ordered oldest → newest).
    public func list(paneID: String?, tty: String? = nil, limit: Int? = nil) -> (revision: Int, entries: [HistoryEntry]) {
        lock.lock()
        defer { lock.unlock() }
        var list = entries[Self.key(paneID: paneID, tty: tty)] ?? []
        if let limit, limit > 0, list.count > limit {
            list = Array(list.suffix(limit))
        }
        return (revision, list)
    }

    public var currentRevision: Int {
        lock.lock()
        defer { lock.unlock() }
        return revision
    }
}
