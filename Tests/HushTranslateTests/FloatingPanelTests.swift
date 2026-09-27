import AppKit
import SwiftUI
import XCTest
@testable import HushTranslate

@MainActor
final class FloatingPanelTests: XCTestCase {
    private func makeWindow() throws -> (FloatingPanelController<AnyView>, NSWindow) {
        let existing = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let controller = FloatingPanelController<AnyView>(autosaveName: nil)
        controller.show({ AnyView(Text("翻译结果")) }, anchor: NSPoint(x: 200, y: 650))
        let window = try XCTUnwrap(NSApplication.shared.windows.first {
            !existing.contains(ObjectIdentifier($0))
        })
        return (controller, window)
    }

    func testResultParticipatesInNormalWindowManagementWhenPinnedOrUnpinned() throws {
        let (controller, window) = try makeWindow()
        defer { controller.close() }
        XCTAssertFalse(window is NSPanel)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
        XCTAssertTrue(window.styleMask.contains([.titled, .closable, .miniaturizable, .resizable]))
        XCTAssertFalse(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(window.collectionBehavior.contains(.managed))
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(window.collectionBehavior.contains(.stationary))
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertEqual(window.level, .floating)
        controller.activate()
        XCTAssertEqual(window.level, .normal)
        controller.setPinned(true)
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.canBecomeKey)
        controller.setPinned(false)
        XCTAssertEqual(window.level, .normal)
    }

    func testAutomaticPresentationStaysAboveNormalWindowsAcrossRefreshAndReuse() throws {
        let (controller, window) = try makeWindow()
        defer { controller.close() }
        XCTAssertEqual(window.level, .floating)

        controller.show({ AnyView(Text("翻译完成")) }, keepPinned: true, bringToFront: false)
        XCTAssertEqual(window.level, .floating)
        controller.setPinned(true)
        controller.setPinned(false)
        XCTAssertEqual(window.level, .floating)

        controller.activate()
        XCTAssertEqual(window.level, .normal)
        controller.show({ AnyView(Text("后台刷新")) }, keepPinned: true, bringToFront: false)
        XCTAssertEqual(window.level, .normal)

        controller.close()
        controller.show({ AnyView(Text("下一次翻译")) })
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.level, .floating)
        controller.setPinned(true)
        controller.activate()
        XCTAssertEqual(window.level, .floating)
    }

    func testAutomaticPresentationDoesNotChangeActivationOrKeyWindow() throws {
        let app = NSApplication.shared
        let wasActive = app.isActive
        let previousKeyWindow = app.keyWindow
        let (controller, window) = try makeWindow()
        defer { controller.close() }
        XCTAssertEqual(app.isActive, wasActive)
        XCTAssertTrue(app.keyWindow === previousKeyWindow)
        XCTAssertFalse(window.isKeyWindow)

        controller.close()
        controller.show({ AnyView(Text("再次展示")) })
        XCTAssertEqual(app.isActive, wasActive)
        XCTAssertTrue(app.keyWindow === previousKeyWindow)
        XCTAssertFalse(window.isKeyWindow)
    }

    func testOutsideClickYieldsUntilNextRequestWithoutClosingOrTakingFocus() throws {
        let (controller, window) = try makeWindow()
        defer { controller.close() }
        let app = NSApplication.shared
        let wasActive = app.isActive
        let previousKeyWindow = app.keyWindow

        controller.handleOutsideClick()
        XCTAssertEqual(window.level, .normal)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(app.isActive, wasActive)
        XCTAssertTrue(app.keyWindow === previousKeyWindow)

        controller.show({ AnyView(Text("翻译完成")) }, keepPinned: true, bringToFront: false)
        XCTAssertEqual(window.level, .normal)
        controller.show({ AnyView(Text("下一次翻译")) })
        XCTAssertEqual(window.level, .floating)
        controller.handleOutsideClick()
        XCTAssertEqual(window.level, .normal)
    }

    func testOutsideClickRespectsExplicitPin() throws {
        let (controller, window) = try makeWindow()
        defer { controller.close() }
        controller.setPinned(true)
        controller.handleOutsideClick()
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.isVisible)
        controller.setPinned(false)
        XCTAssertEqual(window.level, .normal)
    }

    func testOutsideClickDoesNotSendResultBehindUnrelatedWindow() throws {
        let background = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        let source = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 300, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        background.isReleasedWhenClosed = false
        source.isReleasedWhenClosed = false
        defer { source.close(); background.close() }
        background.orderFrontRegardless()
        source.orderFrontRegardless()
        let (controller, result) = try makeWindow()
        defer { controller.close() }

        // The global monitor can run after the source window has already been raised.
        source.orderFrontRegardless()
        controller.handleOutsideClick(relativeTo: source.windowNumber)
        let windows = NSApplication.shared.orderedWindows
        let sourceIndex = try XCTUnwrap(windows.firstIndex(of: source))
        let resultIndex = try XCTUnwrap(windows.firstIndex(of: result))
        let backgroundIndex = try XCTUnwrap(windows.firstIndex(of: background))
        XCTAssertLessThan(sourceIndex, resultIndex)
        XCTAssertLessThan(resultIndex, backgroundIndex)

        // A local monitor runs before AppKit raises the clicked window.
        controller.show({ AnyView(Text("新的翻译")) })
        controller.handleOutsideClick(relativeTo: source.windowNumber)
        source.orderFrontRegardless()
        let reordered = NSApplication.shared.orderedWindows
        XCTAssertLessThan(try XCTUnwrap(reordered.firstIndex(of: source)),
                          try XCTUnwrap(reordered.firstIndex(of: result)))
        XCTAssertLessThan(try XCTUnwrap(reordered.firstIndex(of: result)),
                          try XCTUnwrap(reordered.firstIndex(of: background)))

        controller.show({ AnyView(Text("置顶结果")) }, pinned: true)
        controller.handleOutsideClick(relativeTo: source.windowNumber)
        XCTAssertEqual(result.level, .floating)
        XCTAssertLessThan(try XCTUnwrap(NSApplication.shared.orderedWindows.firstIndex(of: result)),
                          try XCTUnwrap(NSApplication.shared.orderedWindows.firstIndex(of: source)))
    }

    func testClickTargetUsesEventWindowInsteadOfWindowBehindMenu() throws {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                         mouseCursorPosition: .zero, mouseButton: .left))
        let windows: [[String: Any]] = [
            [kCGWindowNumber as String: 101, kCGWindowLayer as String: NSWindow.Level.popUpMenu.rawValue],
            [kCGWindowNumber as String: 102, kCGWindowLayer as String: NSWindow.Level.normal.rawValue],
            [kCGWindowNumber as String: 103, kCGWindowLayer as String: NSWindow.Level.normal.rawValue]
        ]
        typealias Controller = FloatingPanelController<AnyView>
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 103)
        XCTAssertEqual(Controller.clickedNormalWindowNumber(event: event, windows: windows), 103)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 101)
        XCTAssertNil(Controller.clickedNormalWindowNumber(event: event, windows: windows))
        // A closed target or a click without a window must not fall back to an unrelated one.
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 104)
        XCTAssertNil(Controller.clickedNormalWindowNumber(event: event, windows: windows))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 0)
        XCTAssertNil(Controller.clickedNormalWindowNumber(event: event, windows: windows))
    }

    func testApplicationSwitchEndsTemporaryElevationAndRefreshDoesNotRestoreIt() throws {
        let source = try XCTUnwrap(NSWorkspace.shared.frontmostApplication)
        let other = try XCTUnwrap(NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != source.processIdentifier
        })
        let (controller, window) = try makeWindow()
        defer { controller.close() }
        let wasActive = NSApp.isActive
        let previousKeyWindow = NSApp.keyWindow
        func notifyActivation(_ application: NSRunningApplication) {
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.didActivateApplicationNotification, object: nil,
                userInfo: [NSWorkspace.applicationUserInfoKey: application])
        }

        notifyActivation(source)
        XCTAssertEqual(window.level, .floating)
        notifyActivation(other)
        XCTAssertEqual(window.level, .normal)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(NSApp.isActive, wasActive)
        XCTAssertTrue(NSApp.keyWindow === previousKeyWindow)
        controller.show({ AnyView(Text("后台完成")) }, keepPinned: true, bringToFront: false)
        XCTAssertEqual(window.level, .normal)

        controller.show({ AnyView(Text("下一次翻译")) })
        XCTAssertEqual(window.level, .floating)
        notifyActivation(other)
        XCTAssertEqual(window.level, .normal)

        controller.show({ AnyView(Text("置顶结果")) }, pinned: true)
        notifyActivation(other)
        XCTAssertEqual(window.level, .floating)
        controller.setPinned(false)
        XCTAssertEqual(window.level, .normal)
    }

    func testRefreshAndNewRequestPreserveUserFrame() throws {
        let (controller, window) = try makeWindow()
        defer { controller.close() }
        let visibleFrame = try XCTUnwrap(window.screen ?? NSScreen.main).visibleFrame
        let userFrame = FloatingPanelController<AnyView>.constrainedFrame(
            NSRect(x: visibleFrame.minX + 40, y: visibleFrame.minY + 40, width: 600, height: 400), to: visibleFrame)
        window.setFrame(userFrame, display: true)
        controller.show({ AnyView(Text("更长的翻译结果").frame(height: 600)) },
                        keepPinned: true, bringToFront: false)
        XCTAssertEqual(window.frame, userFrame)
        controller.show({ AnyView(Text("下一次翻译")) }, anchor: NSPoint(x: 900, y: 900))
        XCTAssertEqual(window.frame, userFrame)
    }

    func testClosingDuringTranslationStaysClosedUntilExplicitRequest() throws {
        let (controller, window) = try makeWindow()
        defer { controller.close() }
        // Native titlebar close and the footer both use the same close path.
        window.performClose(nil)
        XCTAssertFalse(controller.isVisible())
        controller.show({ AnyView(Text("请求完成或失败")) }, bringToFront: false)
        XCTAssertFalse(controller.isVisible())
        controller.show({ AnyView(Text("用户发起下一次翻译")) })
        XCTAssertTrue(controller.isVisible())
    }

    func testRefreshDoesNotRestoreMinimizedWindow() async throws {
        let (controller, window) = try makeWindow()
        defer { controller.close() }
        window.miniaturize(nil)
        for _ in 0..<100 where !window.isMiniaturized {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(window.isMiniaturized)
        controller.show({ AnyView(Text("翻译完成")) }, bringToFront: false)
        XCTAssertTrue(window.isMiniaturized)
        controller.show({ AnyView(Text("新的翻译")) })
        for _ in 0..<100 where window.isMiniaturized {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(window.isMiniaturized)
    }

    func testFrameClampsToDisplayIncludingNegativeCoordinates() {
        let screen = NSRect(x: -1440, y: 40, width: 1440, height: 860)
        let proposed = NSRect(x: -1700, y: -200, width: 600, height: 400)
        let frame = FloatingPanelController<AnyView>.constrainedFrame(proposed, to: screen)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertEqual(frame.size, proposed.size)
        let oversized = FloatingPanelController<AnyView>.constrainedFrame(
            NSRect(x: 100, y: 100, width: 3000, height: 2000), to: screen)
        XCTAssertEqual(oversized, screen)
    }
}
