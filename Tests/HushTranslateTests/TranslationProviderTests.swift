import XCTest
@testable import HushTranslate

@MainActor
final class TranslationProviderTests: XCTestCase {
    private func withStore(_ body: (SettingsStore, UserDefaults) throws -> Void) throws {
        let suite = "TranslationProviderTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(SettingsStore(defaults: defaults), defaults)
    }

    private func service(_ name: String = "火山云") -> LLMService {
        LLMService(name: name, apiBaseURL: "https://example.com/v1/", apiKey: "test-key", model: "model")
    }

    func testFreshInstallHasOnlyPermanentAppleAndPersistsSelection() throws {
        try withStore { settings, defaults in
            XCTAssertEqual(settings.provider, .apple)
            XCTAssertTrue(settings.services.isEmpty)
            XCTAssertEqual(settings.snapshot().displayName, "Apple 翻译")
            settings.deleteService(UUID())
            XCTAssertEqual(settings.provider, .apple)
            let first = service()
            let second = service("本地服务")
            XCTAssertTrue(settings.saveService(first))
            XCTAssertTrue(settings.saveService(second))
            settings.selectProvider(.llm(first.id))
            let reloaded = SettingsStore(defaults: defaults)
            XCTAssertEqual(reloaded.provider, .llm(first.id))
            XCTAssertEqual(reloaded.services.map(\.id), [first.id, second.id])
            XCTAssertEqual(reloaded.selectedService?.apiBaseURL, "https://example.com/v1")
            reloaded.deleteService(first.id)
            XCTAssertEqual(reloaded.provider, .apple)
            XCTAssertEqual(SettingsStore(defaults: defaults).provider, .apple)
            reloaded.selectProvider(.llm(UUID()))
            XCTAssertEqual(reloaded.provider, .apple)
        }
    }

    func testLegacyMigrationIsOneTimeAndKeepsCredentials() throws {
        let suite = "TranslationProviderMigration.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://old.example/v1", forKey: "apiBaseURL")
        defaults.set("old-key", forKey: "apiKey")
        defaults.set("old-model", forKey: "model")
        let settings = SettingsStore(defaults: defaults)
        let migrated = try XCTUnwrap(settings.services.first)
        XCTAssertEqual(settings.provider, .apple)
        XCTAssertEqual(migrated.name, "原有服务")
        XCTAssertEqual(migrated.apiBaseURL, "https://old.example/v1")
        XCTAssertEqual(migrated.apiKey, "old-key")
        XCTAssertEqual(migrated.model, "old-model")
        XCTAssertEqual(SettingsStore(defaults: defaults).services, [migrated])
        settings.deleteService(migrated.id)
        XCTAssertTrue(SettingsStore(defaults: defaults).services.isEmpty)
        defaults.set(Data("corrupt".utf8), forKey: "translation.providers")
        XCTAssertTrue(SettingsStore(defaults: defaults).services.isEmpty)
    }

    func testDanglingSavedProviderFallsBackToApple() throws {
        try withStore { settings, defaults in
            let profile = service()
            settings.saveService(profile)
            let data = try XCTUnwrap(defaults.data(forKey: "translation.providers"))
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json["services"] = []
            defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "translation.providers")
            XCTAssertEqual(SettingsStore(defaults: defaults).provider, .apple)
        }
    }

    func testAtomicValidationAndIndependentDrafts() throws {
        try withStore { settings, defaults in
            let first = service()
            let second = service("服务二")
            settings.saveService(first)
            settings.saveService(second)
            let original = settings.services
            var drafts = ServiceDrafts()
            var edit = drafts.draft(for: first)
            edit.name = "新名称"
            edit.apiBaseURL = "file:///tmp/example"
            edit.apiKey = " "
            edit.model = ""
            drafts.update(edit)
            settings.selectProvider(.llm(second.id))
            XCTAssertEqual(drafts.draft(for: first), edit)
            XCTAssertEqual(drafts.draft(for: second), second)
            XCTAssertFalse(settings.saveService(edit))
            XCTAssertEqual(settings.services, original)
            XCTAssertEqual(SettingsStore(defaults: defaults).services, original)
            XCTAssertEqual(Set(edit.validationErrors.keys), [.apiBaseURL, .apiKey, .model])
            drafts.discard(first.id)
            XCTAssertEqual(drafts.draft(for: first), first)
            XCTAssertEqual(ServiceDrafts().draft(for: first), first)
        }
    }

    func testSnapshotSurvivesEditDeleteAndAppleKeepsLLMOCRPreference() throws {
        try withStore { settings, _ in
            var profile = service()
            settings.saveService(profile)
            settings.ocrMode = .remote
            let captured = settings.snapshot()
            profile.name = "改名"
            profile.model = "new-model"
            settings.saveService(profile)
            settings.deleteService(profile.id)
            XCTAssertEqual(captured.displayName, "火山云 - model")
            XCTAssertEqual(captured.service?.apiKey, "test-key")
            XCTAssertEqual(captured.ocrMode, .remote)
            XCTAssertEqual(settings.snapshot().ocrMode, .local)
            XCTAssertEqual(settings.ocrMode, .remote)
            settings.saveService(profile)
            XCTAssertEqual(settings.snapshot().ocrMode, .remote)
        }
    }
}
