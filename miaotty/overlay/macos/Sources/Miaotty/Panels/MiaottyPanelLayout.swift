import AppKit
import SwiftUI

/// Lays out the terminal content between the optional left (tabs) and right
/// (details) side panels. Uses a plain `HStack` (not `HSplitView`) so there is
/// **no divider line** between the panels and the terminal — they share the
/// same background, like Otty. Resizing is done with an invisible drag handle.
struct MiaottyPanelLayout<Content: View, Left: View, Right: View>: View {
    let showTabs: Bool
    let showDetails: Bool
    private let left: () -> Left
    private let right: () -> Right
    private let content: () -> Content

    @State private var leftWidth: CGFloat = 220
    @State private var rightWidth: CGFloat = 320

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
        HStack(spacing: 0) {
            if showTabs {
                left()
                    .frame(width: leftWidth)
                MiaottyResizeHandle(width: $leftWidth, range: 160...420, sign: 1)
            }

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showDetails {
                MiaottyResizeHandle(width: $rightWidth, range: 220...640, sign: -1)
                right()
                    .frame(width: rightWidth)
            }
        }
    }
}

/// An invisible, draggable handle used to resize a side panel. Shows the
/// left-right resize cursor on hover; draws nothing (no divider line).
private struct MiaottyResizeHandle: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    /// +1 when the panel is to the left of the handle, -1 when to the right.
    let sign: CGFloat

    @State private var base: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = base ?? width
                        if base == nil { base = start }
                        let delta = sign * value.translation.width
                        width = min(max(range.lowerBound, start + delta), range.upperBound)
                    }
                    .onEnded { _ in base = nil }
            )
    }
}
