import SwiftUI

/// A small toolbar-style icon button that shows a rounded hover highlight,
/// matching Otty's panel header controls.
struct MiaottyIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(hovering ? Color.primary.opacity(0.12) : Color.clear)
        )
        .onHover { hovering = $0 }
        .help(help)
    }
}
