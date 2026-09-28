import AppKit
import SwiftUI

struct MiaottyDetailsGit: View {
    let cwd: String?

    @State private var loaded = false
    @State private var isRepo = true
    @State private var branch = ""
    @State private var remote = ""
    @State private var dirty = false
    @State private var ahead = 0
    @State private var behind = 0

    init(cwd: String?) {
        self.cwd = cwd
    }

    var body: some View {
        Group {
            if !loaded {
                Color.clear
            } else if !isRepo {
                Text("Not a git repository")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                repository
            }
        }
        .frame(minWidth: 220, idealWidth: 320, maxWidth: 640)
        .task(id: cwd) { reload() }
    }

    private var repository: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(branch)
                        .font(.system(.title3, design: .monospaced).bold())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(syncText)
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }

                if !remote.isEmpty {
                    Text(remote)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 8) {
                    Button("Commit") {
                    }
                    .disabled(true)

                    Button("VS Code") {
                        openInVSCode()
                    }
                    .disabled(cwd == nil)

                    Spacer(minLength: 0)
                }

                Text(dirty ? "working tree dirty" : "Working tree clean")
                    .font(.callout)
                    .foregroundStyle(dirty
                        ? Color(nsColor: .systemOrange)
                        : Color(nsColor: .secondaryLabelColor))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var syncText: String {
        if ahead == 0 && behind == 0 { return "up to date" }
        var parts: [String] = []
        if ahead > 0 { parts.append("\(ahead) ahead") }
        if behind > 0 { parts.append("\(behind) behind") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func reload() {
        let path = cwd
        DispatchQueue.global(qos: .userInitiated).async {
            guard let path, !path.isEmpty else {
                DispatchQueue.main.async {
                    self.loaded = true
                    self.isRepo = false
                }
                return
            }

            let quoted = Self.shellQuote(path)
            guard case .success(let branchOut) = MiaottyShell.run(
                "git -C \(quoted) rev-parse --abbrev-ref HEAD", cwd: nil),
                !branchOut.isEmpty else {
                DispatchQueue.main.async {
                    self.loaded = true
                    self.isRepo = false
                }
                return
            }

            var remoteOut = ""
            if case .success(let value) = MiaottyShell.run(
                "git -C \(quoted) remote get-url origin", cwd: nil) {
                remoteOut = value
            }

            var statusOut = ""
            if case .success(let value) = MiaottyShell.run(
                "git -C \(quoted) status --porcelain", cwd: nil) {
                statusOut = value
            }

            var aheadCount = 0
            var behindCount = 0
            if case .success(let counts) = MiaottyShell.run(
                "git -C \(quoted) rev-list --left-right --count '@{upstream}...HEAD'", cwd: nil) {
                let parts = counts.split(whereSeparator: { $0 == "\t" || $0 == " " })
                if parts.count >= 2 {
                    behindCount = Int(parts[0]) ?? 0
                    aheadCount = Int(parts[1]) ?? 0
                }
            }

            let isDirty = !statusOut.isEmpty
            DispatchQueue.main.async {
                self.branch = branchOut
                self.remote = remoteOut
                self.dirty = isDirty
                self.ahead = aheadCount
                self.behind = behindCount
                self.isRepo = true
                self.loaded = true
            }
        }
    }

    private func openInVSCode() {
        guard let cwd else { return }
        _ = MiaottyShell.run("open -a \"Visual Studio Code\" \(Self.shellQuote(cwd))", cwd: cwd)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
