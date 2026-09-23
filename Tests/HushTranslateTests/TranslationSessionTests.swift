import AppKit
import Combine
import XCTest
@testable import HushTranslate

@MainActor
final class TranslationSessionTests: XCTestCase {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_000)
        var deadlines: [Date] = []
        var callbacks: [@MainActor () -> Void] = []
        var cancelled: Set<Int> = []
        let notifications = NotificationCenter()

        @MainActor func store() -> TranslationSessionStore {
            TranslationSessionStore(now: { self.date }, scheduleExpiration: { deadline, callback in
                let index = self.callbacks.count
                self.deadlines.append(deadline)
                self.callbacks.append(callback)
                return AnyCancellable { self.cancelled.insert(index) }
            }, wakeNotifications: notifications)
        }
    }

    func testInitialOffAndDefaultPreset() async {
        let store = Clock().store()
        XCTAssertEqual(store.state, .off)
        XCTAssertFalse(store.consumeValidSelection())
        XCTAssertEqual(TranslationSessionConfiguration.defaultPreset, .count(3))
    }

    func testAlwaysDoesNotExpireOrConsume() async throws {
        let clock = Clock()
        let store = clock.store()
        try store.start(configuration: .always)
        clock.date += 1_000_000
        store.refreshExpiration()
        XCTAssertTrue(store.consumeValidSelection())
        XCTAssertEqual(store.state, .always)
        XCTAssertTrue(clock.callbacks.isEmpty)
    }

    func testCountConsumptionAndReadOnlyObservation() async throws {
        let store = Clock().store()
        try store.start(configuration: .count(3))
        XCTAssertEqual(store.state, .count(remaining: 3))
        store.refreshExpiration()
        XCTAssertEqual(store.state, .count(remaining: 3))
        for expected in [TranslationSessionState.count(remaining: 2), .count(remaining: 1), .off] {
            XCTAssertTrue(store.consumeValidSelection())
            XCTAssertEqual(store.state, expected)
        }
        XCTAssertFalse(store.consumeValidSelection())
    }

    func testCountRestart() async throws {
        let store = Clock().store()
        try store.start(configuration: .count(3))
        store.consumeValidSelection()
        store.consumeValidSelection()
        try store.start(configuration: .count(3))
        XCTAssertEqual(store.state, .count(remaining: 3))
    }

    func testEveryConfigurationReplacesEveryOtherConfiguration() async throws {
        let configurations: [TranslationSessionConfiguration] = [.always, .count(3), .timer(minutes: 10)]
        for original in configurations {
            for replacement in configurations {
                let clock = Clock()
                let store = clock.store()
                try store.start(configuration: original)
                store.consumeValidSelection()
                clock.date += 60
                try store.start(configuration: replacement)
                switch replacement {
                case .always: XCTAssertEqual(store.state, .always)
                case .count: XCTAssertEqual(store.state, .count(remaining: 3))
                case .timer: XCTAssertEqual(store.state, .timer(expiresAt: clock.date + 600))
                }
                if case .timer = original { XCTAssertTrue(clock.cancelled.contains(0)) }
            }
        }
    }

    func testTimerBoundaryCheckedBeforeConsumption() async throws {
        let clock = Clock()
        let store = clock.store()
        try store.start(configuration: .timer(minutes: 2))
        XCTAssertEqual(clock.deadlines, [clock.date + 120])
        XCTAssertEqual(store.state, .timer(expiresAt: clock.date + 120))
        clock.date += 119
        XCTAssertTrue(store.consumeValidSelection())
        clock.date += 1
        XCTAssertFalse(store.consumeValidSelection())
        XCTAssertEqual(store.state, .off)
    }

    func testAutomaticExpirationPublishesOff() async throws {
        let clock = Clock()
        let store = clock.store()
        var states: [TranslationSessionState] = []
        let observation = store.$state.sink { states.append($0) }
        try store.start(configuration: .timer(minutes: 1))
        clock.date += 60
        clock.callbacks[0]()
        XCTAssertEqual(states, [.off, .timer(expiresAt: clock.date), .off])
        withExtendedLifetime(observation) {}
    }

    func testCountChangesArePublished() async throws {
        let store = Clock().store()
        var states: [TranslationSessionState] = []
        let observation = store.$state.sink { states.append($0) }
        try store.start(configuration: .count(2))
        store.consumeValidSelection()
        store.consumeValidSelection()
        XCTAssertEqual(states, [.off, .count(remaining: 2), .count(remaining: 1), .off])
        withExtendedLifetime(observation) {}
    }

    func testTimerRestartIgnoresOldCallback() async throws {
        let clock = Clock()
        let store = clock.store()
        try store.start(configuration: .timer(minutes: 10))
        clock.date += 360
        try store.start(configuration: .timer(minutes: 10))
        let restarted = store.state
        clock.date += 240
        clock.callbacks[0]()
        XCTAssertEqual(store.state, restarted)
        XCTAssertTrue(clock.cancelled.contains(0))
        clock.date += 360
        clock.callbacks[1]()
        XCTAssertEqual(store.state, .off)
    }

    func testCancelledTimerCannotCloseReplacement() async throws {
        for replacement in [TranslationSessionConfiguration.always, .count(3)] {
            let clock = Clock()
            let store = clock.store()
            try store.start(configuration: .timer(minutes: 1))
            try store.start(configuration: replacement)
            let expected = store.state
            clock.date += 120
            clock.callbacks[0]()
            XCTAssertEqual(store.state, expected)
        }
    }

    func testCloseAllStatesIsIdempotent() async throws {
        for configuration in [TranslationSessionConfiguration.always, .count(3), .timer(minutes: 1)] {
            let clock = Clock()
            let store = clock.store()
            try store.start(configuration: configuration)
            store.close()
            store.close()
            clock.date += 120
            clock.callbacks.forEach { $0() }
            XCTAssertEqual(store.state, .off)
            XCTAssertFalse(store.consumeValidSelection())
            if case .timer = configuration { XCTAssertTrue(clock.cancelled.contains(0)) }
        }
    }

    func testInvalidParametersLeaveTimerIntact() async throws {
        let clock = Clock()
        let store = clock.store()
        try store.start(configuration: .timer(minutes: 1))
        let expected = store.state
        for value in [0, -1, Int.min] {
            XCTAssertThrowsError(try store.start(configuration: .count(value))) {
                XCTAssertEqual($0 as? TranslationSessionStore.ConfigurationError, .nonPositiveCount)
            }
            XCTAssertThrowsError(try store.start(configuration: .timer(minutes: value))) {
                XCTAssertEqual($0 as? TranslationSessionStore.ConfigurationError, .nonPositiveMinutes)
            }
            XCTAssertEqual(store.state, expected)
            XCTAssertTrue(clock.cancelled.isEmpty)
        }
        clock.date += 60
        clock.callbacks[0]()
        XCTAssertEqual(store.state, .off)
    }

    func testEarlyCallbackRearmsWithoutExpiring() async throws {
        let clock = Clock()
        let store = clock.store()
        try store.start(configuration: .timer(minutes: 1))
        clock.callbacks[0]()
        XCTAssertEqual(store.state, .timer(expiresAt: clock.date + 60))
        XCTAssertEqual(clock.deadlines.count, 2)
        clock.date += 60
        clock.callbacks[1]()
        XCTAssertEqual(store.state, .off)
    }

    func testWakeRefreshesExpiredTimer() async throws {
        let clock = Clock()
        let store = clock.store()
        try store.start(configuration: .timer(minutes: 1))
        clock.date += 120
        let changed = expectation(description: "Wake publishes OFF")
        let observation = store.$state.dropFirst().sink {
            if $0 == .off { changed.fulfill() }
        }
        clock.notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(store.state, .off)
        withExtendedLifetime(observation) {}
    }

    func testDeinitCancelsScheduledExpiration() async throws {
        let clock = Clock()
        var store: TranslationSessionStore? = clock.store()
        weak var reference = store
        try store?.start(configuration: .timer(minutes: 1))
        store = nil
        XCTAssertNil(reference)
        XCTAssertTrue(clock.cancelled.contains(0))
    }
}
