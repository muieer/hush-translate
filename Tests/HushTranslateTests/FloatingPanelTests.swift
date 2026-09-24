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
        XCTAssertFalse(window.collectionBehavior.contains(.stationary))
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertEqual(window.level, .normal)
        controller.setPinned(true)
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.canBecomeKey)
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
