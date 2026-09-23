import AppKit
import Combine
import XCTest
@testable import HushTranslate

@MainActor
final class SelectionTranslationTests: XCTestCase {
    private final class Monitor: SelectionMonitoring {
        var captures: [(String) -> Void] = []
        var gates: [() -> Bool] = []
        var running = false

        func start(shouldCapture: @escaping () -> Bool, onCapture: @escaping (String) -> Void) {
            running = true
            gates.append(shouldCapture)
            captures.append(onCapture)
        }
        func stop() { running = false }
        func emit(_ text: String) { captures.last?(text) }
    }

    private final class Fixture {
        var now = Date(timeIntervalSince1970: 1_000)
        var preset: TranslationSessionConfiguration = .defaultPreset
        var translations: [String] = []
        var expiration: (@MainActor () -> Void)?
        @MainActor lazy var session = TranslationSessionStore(
            now: { [unowned self] in self.now },
            scheduleExpiration: { [unowned self] _, callback in
                self.expiration = callback
                return AnyCancellable {}
            }, wakeNotifications: NotificationCenter()
        )
        @MainActor lazy var monitor = Monitor()
        @MainActor lazy var controller = SelectionTranslationController(
            session: session, monitor: monitor,
            configuration: { [unowned self] in self.preset },
            translate: { [unowned self] in self.translations.append($0) }
        )
    }

    func testOffDoesNotStartCaptureOrTranslate() async {
        let f = Fixture()
        _ = f.controller
        XCTAssertFalse(f.monitor.running)
        XCTAssertTrue(f.monitor.captures.isEmpty)
        f.monitor.emit("selection")
        XCTAssertTrue(f.translations.isEmpty)
    }

    func testStartOnlyArmsFutureSelectionsAndRestartsDefaultCount() async throws {
        let f = Fixture()
        try f.controller.startDefaultSession()
        XCTAssertTrue(f.monitor.running)
        XCTAssertTrue(f.translations.isEmpty)
        f.monitor.emit("A")
        f.monitor.emit("B")
        XCTAssertEqual(f.session.state, .count(remaining: 1))
        try f.controller.startDefaultSession()
        XCTAssertEqual(f.session.state, .count(remaining: 3))
        XCTAssertEqual(f.translations, ["A", "B"])
    }

    func testAlwaysAcceptsDistinctEventsEvenWithSameText() async throws {
        let f = Fixture()
        f.preset = .always
        try f.controller.startDefaultSession()
        f.monitor.emit("same")
        f.monitor.emit("same")
        XCTAssertEqual(f.translations, ["same", "same"])
        XCTAssertEqual(f.session.state, .always)
    }

    func testCountFinalSelectionTranslatesAndStopsMonitoring() async throws {
        let f = Fixture()
        f.preset = .count(2)
        try f.controller.startDefaultSession()
        f.monitor.emit("A")
        XCTAssertEqual(f.session.state, .count(remaining: 1))
        f.monitor.emit("B")
        XCTAssertEqual(f.session.state, .off)
        XCTAssertFalse(f.monitor.running)
        f.monitor.emit("C")
        XCTAssertEqual(f.translations, ["A", "B"])
    }

    func testEmptyAndWhitespaceSelectionsDoNotConsume() async throws {
        let f = Fixture()
        try f.controller.startDefaultSession()
        f.monitor.emit("")
        f.monitor.emit(" \n\t ")
        XCTAssertEqual(f.session.state, .count(remaining: 3))
        XCTAssertTrue(f.translations.isEmpty)
        f.monitor.emit("  actual text\n")
        XCTAssertEqual(f.translations, ["  actual text\n"])
    }

    func testOldCaptureCannotEnterReplacementSession() async throws {
        let f = Fixture()
        try f.controller.startDefaultSession()
        let stale = try XCTUnwrap(f.monitor.captures.last)
        let staleGate = try XCTUnwrap(f.monitor.gates.last)
        f.preset = .always
        try f.controller.startDefaultSession()
        XCTAssertFalse(staleGate())
        stale("late text")
        XCTAssertTrue(f.translations.isEmpty)
        f.monitor.emit("new text")
        XCTAssertEqual(f.translations, ["new text"])
    }

    func testCountDoesNotConsumeSameCallbackTwice() async throws {
        let f = Fixture()
        try f.controller.startDefaultSession()
        let callback = try XCTUnwrap(f.monitor.captures.last)
        callback("A")
        callback("A")
        XCTAssertEqual(f.translations, ["A"])
        XCTAssertEqual(f.session.state, .count(remaining: 2))
    }

    func testCloseInvalidatesCaptureInFlight() async throws {
        let f = Fixture()
        try f.controller.startDefaultSession()
        let callback = try XCTUnwrap(f.monitor.captures.last)
        f.session.close()
        callback("late text")
        XCTAssertFalse(f.monitor.running)
        XCTAssertTrue(f.translations.isEmpty)
    }

    func testTimerExpiresBeforeCaptureEvenIfScheduledCallbackIsDelayed() async throws {
        let f = Fixture()
        f.preset = .timer(minutes: 1)
        try f.controller.startDefaultSession()
        XCTAssertTrue(try XCTUnwrap(f.monitor.gates.last)())
        f.monitor.emit("A")
        f.now += 60
        XCTAssertFalse(try XCTUnwrap(f.monitor.gates.last)())
        XCTAssertEqual(f.session.state, .off)
        XCTAssertFalse(f.monitor.running)
        f.monitor.emit("B")
        XCTAssertEqual(f.translations, ["A"])
    }

    func testTimerExpiresBetweenCopyAndDelivery() async throws {
        let f = Fixture()
        f.preset = .timer(minutes: 1)
        try f.controller.startDefaultSession()
        let callback = try XCTUnwrap(f.monitor.captures.last)
        f.now += 60
        callback("too late")
        XCTAssertEqual(f.session.state, .off)
        XCTAssertTrue(f.translations.isEmpty)
        XCTAssertFalse(f.monitor.running)
    }

    func testScheduledExpirationStopsMonitoringWithoutAnotherSelection() async throws {
        let f = Fixture()
        f.preset = .timer(minutes: 1)
        try f.controller.startDefaultSession()
        f.now += 60
        try XCTUnwrap(f.expiration)()
        XCTAssertFalse(f.monitor.running)
        XCTAssertEqual(f.session.state, .off)
    }

    func testPresetReadOnEveryStartAndInvalidPresetPreservesSession() async throws {
        let f = Fixture()
        try f.controller.startDefaultSession()
        f.preset = .timer(minutes: 5)
        try f.controller.startDefaultSession()
        XCTAssertEqual(f.session.state, .timer(expiresAt: f.now + 300))
        f.preset = .count(0)
        XCTAssertThrowsError(try f.controller.startDefaultSession())
        XCTAssertEqual(f.session.state, .timer(expiresAt: f.now + 300))
        XCTAssertTrue(f.monitor.running)
        XCTAssertTrue(f.translations.isEmpty)
    }

    func testOrdinaryAndRightClicksAreNotSelectionCandidates() async {
        var gestures = SelectionGestureTracker()
        XCTAssertFalse(gestures.accepts(.leftMouseDown, clickCount: 1, shift: false))
        XCTAssertFalse(gestures.accepts(.leftMouseUp, clickCount: 1, shift: false))
        XCTAssertFalse(gestures.accepts(.rightMouseUp, clickCount: 1, shift: false))
    }

    func testDragDoubleClickAndShiftClickAreSelectionCandidates() async {
        var gestures = SelectionGestureTracker()
        XCTAssertFalse(gestures.accepts(.leftMouseDown, clickCount: 1, shift: false))
        XCTAssertFalse(gestures.accepts(.leftMouseDragged, clickCount: 1, shift: false))
        XCTAssertTrue(gestures.accepts(.leftMouseUp, clickCount: 1, shift: false))
        XCTAssertFalse(gestures.accepts(.leftMouseUp, clickCount: 1, shift: false))
        XCTAssertTrue(gestures.accepts(.leftMouseUp, clickCount: 2, shift: false))
        XCTAssertTrue(gestures.accepts(.leftMouseUp, clickCount: 3, shift: false))
        XCTAssertTrue(gestures.accepts(.leftMouseUp, clickCount: 1, shift: true))
    }
}
