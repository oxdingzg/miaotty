import AppKit
import SwiftUI
import MiaottyKit

enum MiaottyDetailsTab: String, CaseIterable, Identifiable {
    case info
    case outline
    case git
    case files

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .info: return "info.circle"
        case .outline: return "list.bullet.indent"
        case .git: return "arrow.triangle.branch"
        case .files: return "folder"
        }
    }

    var title: String {
        switch self {
        case .info: return "Info"
        case .outline: return "Outline"
        case .git: return "Git"
        case .files: return "Files"
        }
    }
}

struct MiaottyDetailsPanel: View {
    let cwd: String?
    let paneID: String?
    let childPID: Int32?
    let onClose: () -> Void

    @State private var tab: MiaottyDetailsTab = .info
    @State private var history: [MiaottyHistoryEntry] = []

    init(cwd: String?, paneID: String?, childPID: Int32?, onClose: @escaping () -> Void) {
        self.cwd = cwd
        self.paneID = paneID
        self.childPID = childPID
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 220, idealWidth: 320, maxWidth: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadHistory() }
        .onChange(of: paneID) { _ in loadHistory() }
        .onReceive(NotificationCenter.default.publisher(for: .miaottyHistoryChanged)) { _ in
            loadHistory()
        }
    }

    /// Pull the per-pane command history from the MTP host registry (fed by the
    /// shell hook via `miaotty-cli history:add`).
    private func loadHistory() {
        guard let paneID, !paneID.isEmpty else {
            history = []
            return
        }
        let entries = MiaottyIntegration.shared.history.list(paneID: paneID).entries
        history = entries.map { entry in
            MiaottyHistoryEntry(
                id: UUID(),
                command: entry.command,
                cwd: entry.cwd,
                date: entry.ts.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date())
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(MiaottyDetailsTab.allCases) { item in
                tabButton(item)
            }

            Spacer(minLength: 0)

            MiaottyIconButton(systemImage: "sidebar.right", help: "Hide Details", action: onClose)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func tabButton(_ item: MiaottyDetailsTab) -> some View {
        let selected = tab == item
        return Button {
            tab = item
        } label: {
            HStack(spacing: 4) {
                Image(systemName: item.systemImage)
                if selected {
                    Text(item.title)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, selected ? 8 : 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected
                        ? Color(nsColor: .selectedContentBackgroundColor)
                        : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .info:
            MiaottyDetailsInfo(cwd: cwd, paneID: paneID, childPID: childPID)
        case .outline:
            MiaottyDetailsOutline(entries: history)
        case .git:
            MiaottyDetailsGit(cwd: cwd)
        case .files:
            MiaottyDetailsFiles(cwd: cwd)
        }
    }
}
