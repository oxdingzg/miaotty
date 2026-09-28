import AppKit
import SwiftUI

// MARK: - Models

struct MiaottyHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let command: String
    let cwd: String?
    let date: Date
}

struct MiaottyProcessRow: Identifiable {
    let id: Int32
    let name: String
    let pid: Int32
    let elapsed: String
    let isRunning: Bool
}

// MARK: - Shell

enum MiaottyShellResult {
    case success(String)
    case failure(String)
}

enum MiaottyShell {
    /// Run a command through `/bin/zsh -lc` and return trimmed output. Safe to
    /// call from a background thread.
    static func run(_ command: String, cwd: String?) -> MiaottyShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        if let cwd, !cwd.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return .failure(error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        let trimmedOut = out.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedErr = err.trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus == 0 {
            return .success(trimmedOut)
        }
        return .failure(trimmedErr.isEmpty ? trimmedOut : trimmedErr)
    }
}

// MARK: - Processes

enum MiaottyProcesses {
    /// Return the process subtree rooted at `pid`: direct children first, then
    /// their descendants (level order). If `pid` has no children, a single row
    /// for `pid` itself is returned.
    static func descendants(of pid: Int32) -> [MiaottyProcessRow] {
        guard pid > 0 else { return [] }
        guard case .success(let output) = MiaottyShell.run(
            "/bin/ps -axo pid=,ppid=,etime=,comm=", cwd: nil) else {
            return []
        }

        var info: [Int32: (ppid: Int32, elapsed: String, comm: String)] = [:]
        var children: [Int32: [Int32]] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let procPID = Int32(parts[0]),
                  let parentPID = Int32(parts[1]) else { continue }
            let elapsed = String(parts[2])
            let comm = parts.dropFirst(3).joined(separator: " ")
            info[procPID] = (parentPID, elapsed, comm)
            children[parentPID, default: []].append(procPID)
        }

        let direct = children[pid] ?? []
        if direct.isEmpty {
            if let me = info[pid] {
                return [row(for: pid, info: me)]
            }
            return [MiaottyProcessRow(id: pid, name: "pid \(pid)", pid: pid, elapsed: "", isRunning: true)]
        }

        var result: [MiaottyProcessRow] = []
        var queue = direct.sorted()
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let me = info[current] {
                result.append(row(for: current, info: me))
            } else {
                result.append(MiaottyProcessRow(
                    id: current, name: "pid \(current)", pid: current, elapsed: "", isRunning: true))
            }
            queue.append(contentsOf: (children[current] ?? []).sorted())
        }
        return result
    }

    private static func row(
        for pid: Int32,
        info: (ppid: Int32, elapsed: String, comm: String)
    ) -> MiaottyProcessRow {
        MiaottyProcessRow(
            id: pid,
            name: (info.comm as NSString).lastPathComponent,
            pid: pid,
            elapsed: info.elapsed,
            isRunning: true)
    }
}

// MARK: - Ports

enum MiaottyPorts {
    /// Listening TCP ports owned by any of `pids`. Returns `[]` on any error.
    static func listening(matching pids: Set<Int32>) -> [Int] {
        guard !pids.isEmpty else { return [] }

        if case .success(let output) = MiaottyShell.run(
            "/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fpcn", cwd: nil) {
            return parseFields(output, pids: pids)
        }

        if case .success(let output) = MiaottyShell.run(
            "/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN", cwd: nil) {
            return parseTable(output, pids: pids)
        }

        return []
    }

    private static func parseFields(_ output: String, pids: Set<Int32>) -> [Int] {
        var ports = Set<Int>()
        var current: Int32?
        for line in output.split(separator: "\n") {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "p":
                current = Int32(value)
            case "n":
                guard let owner = current, pids.contains(owner) else { continue }
                if let port = port(from: value) { ports.insert(port) }
            default:
                break
            }
        }
        return ports.sorted()
    }

    private static func parseTable(_ output: String, pids: Set<Int32>) -> [Int] {
        var ports = Set<Int>()
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 2,
                  let owner = Int32(columns[1]),
                  pids.contains(owner),
                  let name = columns.last,
                  let port = port(from: String(name)) else { continue }
            ports.insert(port)
        }
        return ports.sorted()
    }

    private static func port(from name: String) -> Int? {
        let withoutSuffix = name.split(separator: " ").first.map(String.init) ?? name
        guard let colon = withoutSuffix.lastIndex(of: ":") else { return nil }
        return Int(withoutSuffix[withoutSuffix.index(after: colon)...])
    }
}

// MARK: - Shared Views

struct MiaottySectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.bold())
            .tracking(0.5)
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

struct MiaottyActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .foregroundStyle(isEnabled
                ? Color(nsColor: .labelColor)
                : Color(nsColor: .tertiaryLabelColor))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
