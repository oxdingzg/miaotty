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
}

// MARK: - View

struct MiaottyTabsPanel: View {
    let window: NSWindow?
    let ghostty: Ghostty.App
    let onClose: () -> Void

    @StateObject private var model = MiaottyTabsModel()

    init(window: NSWindow?, ghostty: Ghostty.App, onClose: @escaping () -> Void) {
        self.window = window
        self.ghostty = ghostty
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            header
            Divider()
            tabList
        }
        .frame(minWidth: 160, idealWidth: 220, maxWidth: 420)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { model.attach(window) }
        .onChange(of: window) { newWindow in model.attach(newWindow) }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button {
                model.newTab(ghostty: ghostty)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "sidebar.left")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide Tab List")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(spacing: 4) {
            MiaottySectionHeader("Tabs")
            Spacer(minLength: 0)
            Button {
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Filter Tabs")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var tabList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, info in
                    tabRow(index: index, info: info)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
    }

    private func tabRow(index: Int, info: MiaottyTabInfo) -> some View {
        Button {
            model.select(index: index)
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .opacity(info.selected ? 1 : 0)

                Text(info.title.isEmpty ? "Untitled" : info.title)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                if index < 9 {
                    Text("\u{2318}\(index + 1)")
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(info.selected
                        ? Color(nsColor: .selectedContentBackgroundColor)
                        : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
