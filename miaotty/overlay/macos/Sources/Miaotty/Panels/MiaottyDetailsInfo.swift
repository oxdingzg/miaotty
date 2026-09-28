import AppKit
import SwiftUI

struct MiaottyDetailsInfo: View {
    let cwd: String?
    let paneID: String?
    let childPID: Int32?

    @State private var processes: [MiaottyProcessRow] = []
    @State private var ports: [Int] = []
    @State private var refreshToken = 0

    init(cwd: String?, paneID: String?, childPID: Int32?) {
        self.cwd = cwd
        self.paneID = paneID
        self.childPID = childPID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                workingDirectory
                processSection
                portsSection
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 220, idealWidth: 320, maxWidth: 640)
        .task(id: reloadKey) { reload() }
    }

    private var reloadKey: String {
        "\(childPID ?? 0)-\(refreshToken)"
    }

    private var workingDirectory: some View {
        VStack(alignment: .leading, spacing: 6) {
            MiaottySectionHeader("Working Directory")

            Text(cwd ?? "\u{2014}")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            MiaottyActionRow(icon: "doc.on.doc", title: "Copy Path") {
                copyPath()
            }
            .disabled(cwd == nil)

            MiaottyActionRow(icon: "folder", title: "Reveal in Finder") {
                revealInFinder()
            }
            .disabled(cwd == nil)

            MiaottyActionRow(icon: "chevron.left.forwardslash.chevron.right", title: "Open in VS Code") {
                openInApp("Visual Studio Code")
            }
            .disabled(cwd == nil)

            MiaottyActionRow(icon: "hammer", title: "Open in Xcode") {
                openInApp("Xcode")
            }
            .disabled(cwd == nil)

            MiaottyActionRow(icon: "z.square", title: "Open in Zed") {
                openInApp("Zed")
            }
            .disabled(cwd == nil)
        }
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                MiaottySectionHeader("Process")
                Spacer(minLength: 0)
                Button {
                    refreshToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }

            if processes.isEmpty {
                Text("\u{2014}")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            } else {
                ForEach(processes) { row in
                    processRow(row)
                }
            }
        }
    }

    private func processRow(_ row: MiaottyProcessRow) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text(row.name)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(row.pid)")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Spacer(minLength: 4)
            Text(row.elapsed)
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
    }

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            MiaottySectionHeader("Ports")

            if ports.isEmpty {
                Text("No listening ports")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            } else {
                ForEach(ports, id: \.self) { port in
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                            .frame(width: 16)
                        Text(":\(port)")
                            .font(.system(.body, design: .monospaced))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        let pid = childPID ?? 0
        DispatchQueue.global(qos: .userInitiated).async {
            var rows: [MiaottyProcessRow] = []
            var listening: [Int] = []
            if pid > 0 {
                rows = MiaottyProcesses.descendants(of: pid)
                listening = MiaottyPorts.listening(matching: Set(rows.map(\.pid)))
            }
            DispatchQueue.main.async {
                self.processes = rows
                self.ports = listening
            }
        }
    }

    private func copyPath() {
        guard let cwd else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cwd, forType: .string)
    }

    private func revealInFinder() {
        guard let cwd else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }

    private func openInApp(_ app: String) {
        guard let cwd else { return }
        _ = MiaottyShell.run("open -a \"\(app)\" \(Self.shellQuote(cwd))", cwd: cwd)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
