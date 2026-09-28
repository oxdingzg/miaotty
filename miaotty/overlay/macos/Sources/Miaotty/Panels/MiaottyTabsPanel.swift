import AppKit
import SwiftUI

// MARK: - Model

struct MiaottyTabInfo: Identifiable {
    let id: Int
    let title: String
    let selected: Bool
}

final class MiaottyTabsModel: ObservableObject {
    @Published var tabs: [MiaottyTabInfo] = []

    private weak var window: NSWindow?
    private var tabGroupObservation: NSKeyValueObservation?
    private var titleObservations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
            notificationTokens.append(token)
        }
    }

    deinit {
        tabGroupObservation?.invalidate()
        titleObservations.forEach { $0.invalidate() }
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func attach(_ window: NSWindow?) {
        self.window = window
        observeTabGroup()
        refresh()
    }

    private func observeTabGroup() {
        tabGroupObservation?.invalidate()
        tabGroupObservation = window?.tabGroup?.observe(\.windows, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }

        let windows: [NSWindow]
        if let group = window?.tabGroup, !group.windows.isEmpty {
            windows = group.windows
        } else if let window {
            windows = [window]
        } else {
            windows = []
        }

        titleObservations.forEach { $0.invalidate() }
        titleObservations = windows.map { tab in
            tab.observe(\.title, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        }

        tabs = windows.enumerated().map { index, tab in
            MiaottyTabInfo(id: index, title: tab.title, selected: tab.isKeyWindow)
        }
    }

    func select(index: Int) {
        guard let windows = window?.tabGroup?.windows, windows.indices.contains(index) else { return }
        windows[index].makeKeyAndOrderFront(nil)
    }

    func newTab(ghostty: Ghostty.App) {
        _ = TerminalController.newTab(ghostty, from: window)
    }

    private func tabWindow(index: Int) -> NSWindow? {
        guard let windows = window?.tabGroup?.windows, windows.indices.contains(index) else {
            return index == 0 ? window : nil
        }
        return windows[index]
    }

    func controller(index: Int) -> TerminalController? {
        tabWindow(index: index)?.windowController as? TerminalController
    }

    func workingDirectory(index: Int) -> URL? {
        tabWindow(index: index)?.representedURL
    }

    func rename(index: Int) {
        controller(index: index)?.promptTabTitle()
    }

    func closeTab(index: Int) {
        controller(index: index)?.closeTab(nil)
    }

    func closeOtherTabs(index: Int) {
        controller(index: index)?.closeOtherTabs(nil)
    }

    func closeTabsToTheRight(index: Int) {
        controller(index: index)?.closeTabsOnTheRight(nil)
    }

    func moveTabToNewWindow(index: Int) {
        tabWindow(index: index)?.moveTabToNewWindow(nil)
    }

    func copyPath(index: Int) {
        guard let url = workingDirectory(index: index) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
    }

    func revealInFinder(index: Int) {
        guard let url = workingDirectory(index: index) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - View

struct MiaottyTabsPanel: View {
    let window: NSWindow?
    let ghostty: Ghostty.App
    let onClose: () -> Void

    @StateObject private var model = MiaottyTabsModel()
    @State private var hovering = false

    init(window: NSWindow?, ghostty: Ghostty.App, onClose: @escaping () -> Void) {
        self.window = window
        self.ghostty = ghostty
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .opacity(hovering ? 1 : 0)
            header
            Divider()
            tabList
        }
        .frame(minWidth: 160, idealWidth: 220, maxWidth: 420)
        .background(ghostty.config.backgroundColor)
        .onHover { hovering = $0 }
        .onAppear { model.attach(window) }
        .onChange(of: window) { newWindow in model.attach(newWindow) }
    }

    /// `+` (new tab) and collapse, right-aligned, revealed on hover (Otty).
    private var toolbar: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            MiaottyIconButton(systemImage: "plus", help: "New Tab") {
                model.newTab(ghostty: ghostty)
            }
            MiaottyIconButton(systemImage: "sidebar.left", help: "Hide Tab List", action: onClose)
        }
        .frame(height: 24)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("TABS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            Spacer(minLength: 0)

            MiaottyIconButton(systemImage: "line.3.horizontal.decrease", help: "Filter Tabs") {
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var tabList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, info in
                    tabRow(index: index, info: info)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    private func tabRow(index: Int, info: MiaottyTabInfo) -> some View {
        Button {
            model.select(index: index)
        } label: {
            HStack(spacing: 8) {
                Text(info.title.isEmpty ? "Untitled" : info.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Color(nsColor: .labelColor))

                Spacer(minLength: 4)

                if index < 9 {
                    Text("\u{2318}\(index + 1)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(info.selected ? Color.primary.opacity(0.09) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                model.rename(index: index)
            } label: {
                Label("Rename Tab…", systemImage: "pencil.line")
            }

            Divider()

            if let url = model.workingDirectory(index: index) {
                Button {
                } label: {
                    Label(url.path, systemImage: "folder")
                }
                .disabled(true)

                Button {
                    model.copyPath(index: index)
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }

                Button {
                    model.revealInFinder(index: index)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Divider()
            }

            Button {
                model.closeTab(index: index)
            } label: {
                Label("Close Tab", systemImage: "xmark")
            }

            Button {
                model.closeOtherTabs(index: index)
            } label: {
                Label("Close Other Tabs", systemImage: "xmark")
            }

            Button {
                model.closeTabsToTheRight(index: index)
            } label: {
                Label("Close Tabs to the Right", systemImage: "xmark")
            }

            Divider()

            Button {
                model.moveTabToNewWindow(index: index)
            } label: {
                Label("Move Tab to New Window", systemImage: "macwindow")
            }
        }
    }
}
