import SwiftUI

/// Lays out the terminal content between the optional left (tabs) and right
/// (details) side panels. The panels are resizable via the native split view
/// divider; the terminal area always takes the remaining space.
///
/// When a panel is hidden, a thin strip is overlaid at that window edge; moving
/// the mouse over it reveals a button that shows the panel again (like Otty).
struct MiaottyPanelLayout<Content: View, Left: View, Right: View>: View {
    let showTabs: Bool
    let showDetails: Bool
    let onShowTabs: () -> Void
    let onShowDetails: () -> Void
    private let left: () -> Left
    private let right: () -> Right
    private let content: () -> Content

    init(
        showTabs: Bool,
        showDetails: Bool,
        onShowTabs: @escaping () -> Void,
        onShowDetails: @escaping () -> Void,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.showTabs = showTabs
        self.showDetails = showDetails
        self.onShowTabs = onShowTabs
        self.onShowDetails = onShowDetails
        self.left = left
        self.right = right
        self.content = content
    }

    var body: some View {
        ZStack {
            HSplitView {
                if showTabs {
                    left()
                        .frame(minWidth: 160, idealWidth: 220, maxWidth: 420)
                }

                content()
                    .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)

                if showDetails {
                    right()
                        .frame(minWidth: 220, idealWidth: 320, maxWidth: 640)
                }
            }

            HStack(spacing: 0) {
                if !showTabs {
                    MiaottyEdgeReveal(
                        systemImage: "sidebar.left",
                        help: "Show Tabs Panel",
                        action: onShowTabs)
                }
                Spacer(minLength: 0)
                if !showDetails {
                    MiaottyEdgeReveal(
                        systemImage: "sidebar.right",
                        help: "Show Details Panel",
                        action: onShowDetails)
                }
            }
        }
    }
}

/// A thin edge strip that reveals a show-panel button on hover.
private struct MiaottyEdgeReveal: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .opacity(hovering ? 1 : 0)
            .help(help)
            Spacer(minLength: 0)
        }
        .frame(width: 22)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
