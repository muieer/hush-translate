import AppKit
import SwiftUI

/// 自动展示不夺取焦点；用户点击后按普通应用窗口激活。
private final class ResultPanelWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            performClose(nil)
            return
        }
        if event.type == .leftMouseDown {
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }
}

@MainActor
final class FloatingPanelController<Content: View>: NSObject, NSWindowDelegate {
    private var panel: NSWindow?
    private var hosting: NSHostingController<Content>?
    private(set) var pinned = false
    private let autosaveName: String?

    init(autosaveName: String? = "TranslationResultWindow") {
        self.autosaveName = autosaveName
        super.init()
    }

    /// 只有明确的新请求才展示窗口；后台刷新不会撤销关闭或最小化。
    /// 已有窗口始终保留用户的位置和尺寸。
    func show(@ViewBuilder _ viewBuilder: @escaping () -> Content,
              size: NSSize = NSSize(width: 440, height: 360),
              maxSize: NSSize? = nil,
              pinned: Bool = false,
              keepPinned: Bool = false,
              bringToFront: Bool = true,
              anchor: NSPoint? = nil) {
        if !keepPinned { self.pinned = pinned }
        let previousFrame = panel?.frame
        if panel == nil {
            let window = ResultPanelWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "HushTranslate 翻译结果"
            window.collectionBehavior = [.managed, .fullScreenPrimary]
            window.contentMinSize = NSSize(width: 440, height: 220)
            window.isReleasedWhenClosed = false
            window.delegate = self
            if let autosaveName { window.setFrameAutosaveName(autosaveName) }
            panel = window

            if autosaveName.map({ window.setFrameUsingName($0) }) != true {
                let mouse = anchor ?? NSEvent.mouseLocation
                let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
                let contentSize = NSSize(width: size.width,
                                         height: min(max(size.height, 360), maxSize?.height ?? (screen?.visibleFrame.height ?? 800) * 0.7))
                window.setContentSize(contentSize)
                window.setFrameTopLeftPoint(anchor ?? NSPoint(x: mouse.x - window.frame.width / 2, y: mouse.y - 16))
            }
        }
        guard let window = panel else { return }

        let retainedFrame = previousFrame ?? window.frame
        if let hosting {
            hosting.rootView = viewBuilder()
        } else {
            let host = NSHostingController(rootView: viewBuilder())
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.state = .followsWindowActiveState
            effect.blendingMode = .behindWindow
            host.view.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: effect.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
            ])
            window.contentView = effect
            hosting = host
        }
        // SwiftUI 更新不能改变用户调整的窗口尺寸。
        if !window.styleMask.contains(.fullScreen) {
            window.setFrame(retainedFrame, display: true)
        }
        window.level = self.pinned ? .floating : .normal
        if bringToFront {
            if window.isMiniaturized { window.deminiaturize(nil) }
            if !window.styleMask.contains(.fullScreen) {
                let screen = window.screen ?? NSScreen.main
                if let screen { window.setFrame(Self.constrainedFrame(window.frame, to: screen.visibleFrame), display: true) }
            }
            // 新划词结果可以出现，但键盘继续留在来源 App。
            window.orderFrontRegardless()
        }
    }

    func activate() {
        guard let panel else { return }
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func setPinned(_ on: Bool) {
        pinned = on
        panel?.level = on ? .floating : .normal
    }

    func close() {
        panel?.performClose(nil)
    }

    func isVisible() -> Bool { panel?.isVisible ?? false }

    /// 兼容显示器移除或分辨率变化，确保标题栏和整个窗口可找回。
    static func constrainedFrame(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        return NSRect(x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
                      y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height),
                      width: width, height: height)
    }
}
