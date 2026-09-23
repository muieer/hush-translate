import Combine
import XCTest
@testable import HushTranslate

@MainActor
final class SessionSettingsTests: XCTestCase {
    func testPresetsPersistAcrossStoreRecreationWithoutPersistingActiveSession() async throws {
        let name = "HushTranslateTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.defaultTranslationSession, .count(3))
        XCTAssertEqual(settings.sessionMinutes, 10)
        XCTAssertTrue(settings.setSessionCount(5))
        XCTAssertTrue(settings.setSessionMinutes(17))
        for mode in SessionMode.allCases {
            settings.defaultSessionMode = mode
            let restored = SettingsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: name)))
            XCTAssertEqual(restored.defaultSessionMode, mode)
            XCTAssertEqual(restored.sessionCount, 5)
            XCTAssertEqual(restored.sessionMinutes, 17)
            XCTAssertEqual(restored.defaultTranslationSession, settings.defaultTranslationSession)
        }
        XCTAssertEqual(TranslationSessionStore().state, .off)
    }

    func testInvalidValuesNeverReplaceSavedSettings() async throws {
        let name = "HushTranslateTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.setSessionCount(5)
        settings.setSessionMinutes(12)
        for value in [0, -1, Int.min] {
            XCTAssertFalse(settings.setSessionCount(value))
            XCTAssertFalse(settings.setSessionMinutes(value))
        }
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.sessionCount, 5)
        XCTAssertEqual(restored.sessionMinutes, 12)
        for value: Any in [0, -3, 1.5, "invalid", true] {
            defaults.set(value, forKey: "session.count")
            defaults.set(value, forKey: "session.minutes")
            defaults.set("unknown", forKey: "session.mode")
            let recovered = SettingsStore(defaults: defaults)
            XCTAssertEqual(recovered.defaultTranslationSession, .count(3))
            XCTAssertEqual(recovered.sessionMinutes, 10)
        }
    }

    func testLatestPersistentDefaultDrivesShortcutSessionAndRestart() async throws {
        final class Monitor: SelectionMonitoring {
            func start(shouldCapture: @escaping () -> Bool, onCapture: @escaping (String) -> Void) {}
            func stop() {}
        }
        let name = "HushTranslateTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1000)
        let session = TranslationSessionStore(now: { now }, scheduleExpiration: { _, _ in AnyCancellable {} })
        let controller = SelectionTranslationController(session: session, monitor: Monitor(),
            configuration: { settings.defaultTranslationSession }, translate: { _ in XCTFail("Start must not translate") })
        settings.setSessionCount(5)
        try controller.startDefaultSession()
        session.consumeValidSelection()
        try controller.startDefaultSession()
        XCTAssertEqual(session.state, .count(remaining: 5))
        settings.defaultSessionMode = .timer
        settings.setSessionMinutes(10)
        XCTAssertEqual(session.state, .count(remaining: 5))
        try controller.startDefaultSession()
        XCTAssertEqual(session.state, .timer(expiresAt: now + 600))
    }

    func testPresentationObservesLifecycleWithoutOpeningMenu() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        var expire: (() -> Void)?
        let session = TranslationSessionStore(now: { now }, scheduleExpiration: { _, callback in
            expire = callback
            return AnyCancellable {}
        })
        let presentation = SessionPresentation(session: session, now: { now })
        XCTAssertEqual(presentation.status.title, "已关闭")
        try session.start(configuration: .always)
        XCTAssertEqual(presentation.status.title, "持续开启")
        XCTAssertEqual(presentation.status.badge, "∞")
        try session.start(configuration: .count(2))
        session.consumeValidSelection()
        XCTAssertEqual(presentation.status.title, "剩余 1 次")
        try session.start(configuration: .count(2))
        XCTAssertEqual(presentation.status.badge, "2")
        session.consumeValidSelection()
        session.consumeValidSelection()
        XCTAssertFalse(presentation.status.isActive)
        try session.start(configuration: .timer(minutes: 10))
        XCTAssertEqual(presentation.status.title, "约剩余 10 分钟")
        now += 60
        presentation.refresh()
        XCTAssertEqual(presentation.status.badge, "9m")
        now += 540
        expire?()
        XCTAssertFalse(presentation.status.isActive)
        try session.start(configuration: .always)
        session.close()
        XCTAssertEqual(presentation.status.title, "已关闭")
    }

    func testMinuteRoundingAndExpiredDisplay() async {
        let now = Date(timeIntervalSince1970: 1000)
        for (seconds, expected) in [(600.0, "10m"), (540.1, "10m"), (540, "9m"), (1, "1m"), (0, ""), (-1, "")] {
            let status = SessionStatus(state: .timer(expiresAt: now + seconds), now: now)
            XCTAssertEqual(status.badge, expected)
            XCTAssertEqual(status.isActive, seconds > 0)
        }
    }
}
