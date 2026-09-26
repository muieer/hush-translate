import AppKit

private final class SelectionActionWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SelectionActionButton: NSButton {
    // Keep the title black instead of letting the material tint it gray.
    override var allowsVibrancy: Bool { false }
}

/// A nonactivating confirmation keeps the source application's selection intact.
@MainActor
final class SelectionActionPanel {
    private var panel: NSPanel?
    private var action: (() -> Void)?

    func show(above selection: NSRect, action: @escaping () -> Void) {
        dismiss()
        self.action = action
        let size = NSSize(width: 52, height: 28)
        let window = SelectionActionWindow(contentRect: NSRect(origin: .zero, size: size),
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.appearance = NSAppearance(named: .aqua)
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        let button = SelectionActionButton(title: "翻译", target: self, action: #selector(confirm))
        button.frame = background.bounds
        button.isBordered = false
        button.font = .systemFont(ofSize: 14, weight: .medium)
        button.contentTintColor = .black
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        button.attributedTitle = NSAttributedString(string: "翻译", attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.black,
            .paragraphStyle: titleStyle
        ])
        button.setAccessibilityLabel("翻译所选文本")
        background.addSubview(button)
        window.contentView = background
        let screen = NSScreen.screens.first { $0.frame.intersects(selection) } ?? NSScreen.main
        window.setFrame(Self.frame(above: selection, size: size,
                                   visibleFrame: screen?.visibleFrame ?? selection.insetBy(dx: -100, dy: -100)), display: false)
        panel = window
        window.orderFrontRegardless()
    }

    func contains(_ window: NSWindow?) -> Bool {
        guard let panel, let window else { return false }
        return panel === window
    }

    @objc func confirm() {
        let callback = action
        dismiss()
        callback?()
    }

    func dismiss() {
        action = nil
        panel?.orderOut(nil)
        panel = nil
    }

    static func frame(above selection: NSRect, size: NSSize, visibleFrame: NSRect) -> NSRect {
        let desired = NSRect(x: selection.midX - size.width / 2, y: selection.maxY + 8,
                             width: size.width, height: size.height)
        return NSRect(x: min(max(desired.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
                      y: min(max(desired.minY, visibleFrame.minY), visibleFrame.maxY - size.height),
                      width: size.width, height: size.height)
    }
}
