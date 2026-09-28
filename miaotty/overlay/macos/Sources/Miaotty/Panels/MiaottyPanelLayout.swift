import SwiftUI

/// Lays out the terminal content between the optional left (tabs) and right
/// (details) side panels. The panels are resizable via the native split view
/// divider; the terminal area always takes the remaining space.
///
/// The hover-to-reveal strips for hidden panels are native AppKit views added
/// above the terminal by `MiaottyEdgeReveal` (a SwiftUI overlay would sit under
/// the terminal's NSView).
struct MiaottyPanelLayout<Content: View, Left: View, Right: View>: View {
    let showTabs: Bool
    let showDetails: Bool
    private let left: () -> Left
    private let right: () -> Right
    private let content: () -> Content

    init(
        showTabs: Bool,
        showDetails: Bool,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.showTabs = showTabs
        self.showDetails = showDetails
        self.left = left
        self.right = right
        self.content = content
    }

    var body: some View {
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
    }
}
