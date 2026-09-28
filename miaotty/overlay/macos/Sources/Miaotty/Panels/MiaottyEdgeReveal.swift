import AppKit
import Combine

/// Native edge strips over the window content that reveal a show-panel button
/// on hover (like Otty). Implemented in AppKit so they sit **above** the
/// terminal's NSView (a SwiftUI overlay would be hidden underneath it).
enum MiaottyEdgeReveal {
    static func install(on window: NSWindow) {
        guard let controller = window.windowController as? BaseTerminalController else { return }

        guard let content = window.contentView else { return }
        let existing = content.subviews.compactMap { $0 as? MiaottyEdgeRevealView }
        if existing.contains(where: { $0.side == .left }), existing.contains(where: { $0.side == .right }) {
            return
        }
        for side in [MiaottyEdgeRevealView.Side.left, .right] where !existing.contains(where: { $0.side == side }) {
            let view = MiaottyEdgeRevealView(side: side, controller: controller)
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: content.topAnchor),
                view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                view.widthAnchor.constraint(equalToConstant: 26),
                side == .left
                    ? view.leadingAnchor.constraint(equalTo: content.leadingAnchor)
                    : view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ])
        }
    }
}

final class MiaottyEdgeRevealView: NSView {
    enum Side { case left, right }

    let side: Side
    private weak var controller: BaseTerminalController?
    private var button: NSButton?
    private var cancellables = Set<AnyCancellable>()

    init(side: Side, controller: BaseTerminalController) {
        self.side = side
        self.controller = controller
        super.init(frame: .zero)
        updateHidden()
        observePanel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    private var panelVisible: Bool {
        side == .left ? (controller?.miaottyShowTabsPanel ?? false)
                      : (controller?.miaottyShowDetailsPanel ?? false)
    }

    private func observePanel() {
        guard let controller else { return }
        let publisher = side == .left
            ? controller.$miaottyShowTabsPanel.eraseToAnyPublisher()
            : controller.$miaottyShowDetailsPanel.eraseToAnyPublisher()
        publisher.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.updateHidden()
        }.store(in: &cancellables)
    }

    private func updateHidden() {
        isHidden = panelVisible
        if panelVisible { removeButton() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard !panelVisible else { return }
        showButton()
    }

    override func mouseExited(with event: NSEvent) {
        removeButton()
    }

    private func showButton() {
        guard button == nil else { return }
        let symbol = side == .left ? "sidebar.left" : "sidebar.right"
        let b = NSButton()
        b.bezelStyle = .regularSquare
        b.isBordered = false
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Show Panel")
        b.image?.isTemplate = true
        b.contentTintColor = .secondaryLabelColor
        b.target = self
        b.action = #selector(toggle)
        b.toolTip = side == .left ? "Show Tabs Panel" : "Show Details Panel"
        b.translatesAutoresizingMaskIntoConstraints = false
        addSubview(b)
        NSLayoutConstraint.activate([
            b.centerYAnchor.constraint(equalTo: centerYAnchor),
            b.centerXAnchor.constraint(equalTo: centerXAnchor),
            b.widthAnchor.constraint(equalToConstant: 24),
            b.heightAnchor.constraint(equalToConstant: 24),
        ])
        button = b
    }

    private func removeButton() {
        button?.removeFromSuperview()
        button = nil
    }

    @objc private func toggle() {
        if side == .left {
            controller?.miaottyShowTabsPanel = true
        } else {
            controller?.miaottyShowDetailsPanel = true
        }
        removeButton()
    }
}
