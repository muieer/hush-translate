import AppKit
import SwiftUI
import XCTest
@testable import HushTranslate

@MainActor
final class AppLifecycleTests: XCTestCase {
    func testReopenDoesNotCreateOrRestoreWindows() throws {
        let app = NSApplication.shared
        let delegate = HushTranslateAppDelegate()
        let before = Set(app.windows.map(ObjectIdentifier.init))
        XCTAssertFalse(delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false))
        XCTAssertEqual(Set(app.windows.map(ObjectIdentifier.init)), before)

        let controller = FloatingPanelController<AnyView>(autosaveName: nil)
        defer { controller.close() }
        controller.show({ AnyView(Text("已有结果")) })
        let window = try XCTUnwrap(app.windows.first { !before.contains(ObjectIdentifier($0)) })
        let frame = window.frame
        let keyWindow = app.keyWindow
        XCTAssertFalse(delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true))
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.frame, frame)
        XCTAssertTrue(app.keyWindow === keyWindow)

        controller.close()
        XCTAssertFalse(delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false))
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(app))
    }
}
