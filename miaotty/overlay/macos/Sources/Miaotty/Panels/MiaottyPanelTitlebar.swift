import AppKit
import SwiftUI

/// Installs the tabs-panel controls (`+` new tab, collapse) as **leading
/// titlebar accessory** buttons, so they live in the titlebar row next to the
/// traffic lights (like Otty) instead of taking a row inside the panel.
struct MiaottyTitlebarControls: NSViewRepresentable {
    let onCreate: () -> Void
    let onCollapse: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        DispatchQueue.main.async {
            context.coordinator.install(create: onCreate, collapse: onCollapse)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.install(create: onCreate, collapse: onCollapse)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        weak var view: NSView?
        private var accessory: NSTitlebarAccessoryViewController?
        private weak var installedWindow: NSWindow?
        private var create: (() -> Void)?
        private var collapse: (() -> Void)?

        func install(create: @escaping () -> Void, collapse: @escaping () -> Void) {
            self.create = create
            self.collapse = collapse
            guard let window = view?.window else { return }
            if installedWindow === window, accessory != nil { return }
            uninstall()
            let acc = NSTitlebarAccessoryViewController(nibName: nil, bundle: nil)
            acc.layoutAttribute = .leading
            let host = NSHostingView(rootView: MiaottyTitlebarControlsView(
                onCreate: { [weak self] in self?.create?() },
                onCollapse: { [weak self] in self?.collapse?() }))
            host.frame = NSRect(x: 0, y: 0, width: 56, height: 28)
            acc.view = host
            window.addTitlebarAccessoryViewController(acc)
            accessory = acc
            installedWindow = window
        }

        func uninstall() {
            accessory?.removeFromParent()
            accessory = nil
            installedWindow = nil
        }
    }
}

struct MiaottyTitlebarControlsView: View {
    let onCreate: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onCreate) {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")

            Button(action: onCollapse) {
                Image(systemName: "sidebar.left")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide Tab List")
        }
        .frame(width: 56, height: 28)
    }
}
