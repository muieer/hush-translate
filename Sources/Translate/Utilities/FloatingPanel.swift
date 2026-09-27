import AppKit
import SwiftUI

/// 自动展示不夺取焦点；用户点击后按普通应用窗口激活。
private final class ResultPanelWindow: NSWindow {
    var onUserActivation: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            performClose(nil)
            return
        }
        if event.type == .leftMouseDown {
            onUserActivation?()
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
    private var automaticallyPresented = false
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var applicationActivationObserver: NSObjectProtocol?
    private var presentationApplicationPID: pid_t?
    private let autosaveName: String?

    init(autosaveName: String? = "TranslationResultWindow") {
        self.autosaveName = autosaveName
        super.init()
    }

    deinit {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
        }
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
            window.title = L10n.tr("HushTranslate 翻译结果")
            // A reused result window must follow the desktop where the next selection occurs.
            window.collectionBehavior = [.managed, .fullScreenPrimary, .moveToActiveSpace]
            window.contentMinSize = NSSize(width: 440, height: 220)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.onUserActivation = { [weak self] in self?.finishAutomaticPresentation() }
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
        window.title = L10n.tr("HushTranslate 翻译结果")

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
        if bringToFront {
            automaticallyPresented = true
            presentationApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            monitorOutsideClicks()
            monitorApplicationActivation()
        }
        updateWindowLevel()
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
        finishAutomaticPresentation()
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func setPinned(_ on: Bool) {
        pinned = on
        updateWindowLevel()
    }

    private func finishAutomaticPresentation() {
        automaticallyPresented = false
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        localClickMonitor = nil
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
        }
        applicationActivationObserver = nil
        presentationApplicationPID = nil
        updateWindowLevel()
    }

    private func monitorApplicationActivation() {
        guard applicationActivationObserver == nil else { return }
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      application.processIdentifier != self.presentationApplicationPID else { return }
                // Clicking the result may activate this app before its mouse event arrives.
                // Do not place it behind another one of our windows in that interval.
                if application.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                    self.finishAutomaticPresentation()
                    return
                }
                self.handleOutsideClick(relativeTo: self.normalWindowNumber(
                    belongingTo: application.processIdentifier))
            }
        }
    }

    private func monitorOutsideClicks() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.handleOutsideClick(relativeTo: event.cgEvent.flatMap {
                        Self.clickedNormalWindowNumber(event: $0, windows: self.visibleWindowInfo())
                    })
                }
            }
        }
        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
                MainActor.assumeIsolated {
                    if let self, event.window !== self.panel {
                        self.handleOutsideClick(relativeTo: event.window?.level == .normal
                                                ? event.window?.windowNumber : nil)
                    }
                }
                return event
            }
        }
    }

    private func visibleWindowInfo() -> [[String: Any]] {
        // Window numbers, layers and bounds are available without reading window contents.
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                  kCGNullWindowID) as? [[String: Any]] ?? []
    }

    static func clickedNormalWindowNumber(event: CGEvent, windows: [[String: Any]]) -> Int? {
        let target = Int(event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent))
        guard target > 0,
              windows.contains(where: {
                  $0[kCGWindowNumber as String] as? Int == target &&
                  $0[kCGWindowLayer as String] as? Int == NSWindow.Level.normal.rawValue
              }) else { return nil }
        return target
    }

    private func normalWindowNumber(belongingTo pid: pid_t) -> Int? {
        for window in visibleWindowInfo() {
            guard let number = window[kCGWindowNumber as String] as? Int,
                  number != panel?.windowNumber,
                  window[kCGWindowLayer as String] as? Int == NSWindow.Level.normal.rawValue else { continue }
            if window[kCGWindowOwnerPID as String] as? Int != Int(pid) { continue }
            return number
        }
        return nil
    }

    func handleOutsideClick(relativeTo windowNumber: Int? = nil) {
        guard automaticallyPresented else { return }
        finishAutomaticPresentation()
        // The global event may arrive after the clicked window has already been raised.
        // Place the result just below that window, never at the back of the whole level.
        if !pinned, let windowNumber, windowNumber > 0 {
            panel?.order(.below, relativeTo: windowNumber)
        }
    }

    func windowWillClose(_ notification: Notification) {
        finishAutomaticPresentation()
    }

    func windowWillMiniaturize(_ notification: Notification) {
        finishAutomaticPresentation()
    }

    private func updateWindowLevel() {
        // Keep passive results above the source app without activating or taking key focus.
        // A click inside or outside restores normal behavior unless the user pinned it.
        panel?.level = (automaticallyPresented || pinned) ? .floating : .normal
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
