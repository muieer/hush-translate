import AppKit
import SwiftUI
import XCTest
@testable import HushTranslate

@MainActor
final class FloatingPanelTests: XCTestCase {
    func testRefreshPreservesTopLeftWhileResizingAndNewRequestRepositions() async throws {
        let app = NSApplication.shared
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))
        let controller = FloatingPanelController<AnyView>()
        defer { controller.close() }
        let initial = NSPoint(x: 200, y: 650)
        controller.show({ AnyView(Text("翻译中…").frame(width: 420, height: 120)) }, size: NSSize(width: 440, height: 160),
                        pinned: true, anchor: initial)
        let panel = try XCTUnwrap(app.windows.first {
            $0 is NSPanel && !existingWindows.contains(ObjectIdentifier($0))
        })
        let before = panel.frame

        // A later location must not displace the current result, even when it grows.
        let later = NSPoint(x: 500, y: 500)
        controller.show({ AnyView(Text("翻译结果").frame(width: 420, height: 280)) }, size: NSSize(width: 440, height: 300),
                        pinned: true, keepPinned: true, keepPosition: true, anchor: later)
        XCTAssertEqual(panel.frame.minX, before.minX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, before.maxY, accuracy: 0.5)
        XCTAssertGreaterThan(panel.frame.height, before.height)

        // Preserve a user-dragged position too, including an error content refresh.
        panel.setFrameTopLeftPoint(NSPoint(x: 250, y: 600))
        controller.show({ AnyView(Text("翻译失败").frame(width: 420, height: 120)) }, size: NSSize(width: 440, height: 160),
                        pinned: true, keepPosition: true)
        XCTAssertEqual(panel.frame.minX, 250, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, 600, accuracy: 0.5)

        controller.show({ AnyView(Text("下一次翻译").frame(width: 420, height: 120)) }, pinned: true, anchor: later)
        XCTAssertEqual(panel.frame.minX, later.x, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, later.y, accuracy: 0.5)
    }
}
