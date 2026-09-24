import XCTest
@testable import HushTranslate

@MainActor
final class ResultTranslationTests: XCTestCase {
    @MainActor
    private final class Fixture {
        struct Call {
            let request: TranslationRequest
            let config: TranslateConfig
            let continuation: CheckedContinuation<String, Error>
        }
        let suite = "ResultTranslationTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: SettingsStore
        var calls: [Call] = []
        lazy var coordinator = AppCoordinator(settings: settings) { [unowned self] request, config in
            // Deliberately ignore cancellation to exercise late responses from the service.
            try await withCheckedThrowingContinuation { continuation in
                calls.append(Call(request: request, config: config, continuation: continuation))
            }
        }

        init() {
            defaults = UserDefaults(suiteName: suite)!
            settings = SettingsStore(defaults: defaults)
        }
        deinit { defaults.removePersistentDomain(forName: suite) }

        func start(text: String = "original", image: Data? = nil,
                   source: TranslationRequest.Source = .selection) {
            coordinator.runTranslate(text: text, imageData: image, source: source, presentWindow: false)
        }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for translation state", file: file, line: line)
        throw TestError.timeout
    }

    private enum TestError: Error { case oldFailure, timeout }

    func testLanguageChangesReuseTextAndPersistWithoutConsumingSession() async throws {
        let f = Fixture()
        try f.coordinator.translationSession.start(configuration: .count(3))
        f.start(source: .clipboard)
        try await waitUntil { f.calls.count == 1 }
        f.calls[0].continuation.resume(returning: "first")
        try await waitUntil { !f.coordinator.isWorking }

        f.coordinator.changeResultSourceLanguage("en")
        XCTAssertEqual(f.settings.sourceLanguage, "en")
        XCTAssertTrue(f.coordinator.isWorking)
        try await waitUntil { f.calls.count == 2 }
        XCTAssertEqual(f.calls[1].request.text, "original")
        XCTAssertEqual(f.calls[1].request.source, .clipboard)
        XCTAssertEqual(f.calls[1].request.sourceLang, "en")
        f.calls[1].continuation.resume(returning: "second")
        try await waitUntil { !f.coordinator.isWorking }

        f.coordinator.changeResultTargetLanguage("ja")
        XCTAssertEqual(f.settings.targetLanguage, "ja")
        try await waitUntil { f.calls.count == 3 }
        XCTAssertEqual(f.calls[2].request.text, "original")
        XCTAssertEqual(f.calls[2].request.sourceLang, "en")
        XCTAssertEqual(f.calls[2].request.targetLang, "ja")
        f.calls[2].continuation.resume(returning: "third")
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertEqual(f.coordinator.lastResult?.translated, "third")
        XCTAssertEqual(f.coordinator.translationSession.state, .count(remaining: 3))
        XCTAssertEqual(f.defaults.string(forKey: "sourceLanguage"), "en")
        XCTAssertEqual(f.defaults.string(forKey: "targetLanguage"), "ja")
    }

    func testNoInputOnlyUpdatesSettingsAndRepeatedSelectionDoesNotRequest() async throws {
        let f = Fixture()
        f.coordinator.changeResultSourceLanguage("en")
        f.coordinator.changeResultTargetLanguage("ja")
        XCTAssertEqual(f.settings.sourceLanguage, "en")
        XCTAssertEqual(f.settings.targetLanguage, "ja")
        XCTAssertFalse(f.coordinator.isWorking)
        XCTAssertTrue(f.calls.isEmpty)
        f.start()
        try await waitUntil { f.calls.count == 1 }
        f.coordinator.changeResultSourceLanguage("en")
        f.coordinator.changeResultTargetLanguage("ja")
        f.calls[0].continuation.resume(returning: "unchanged")
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertEqual(f.calls.count, 1)
        XCTAssertEqual(f.coordinator.lastResult?.translated, "unchanged")
    }

    func testScreenshotCanRetranslateWithoutOriginalText() async throws {
        let f = Fixture()
        let image = Data([1, 2, 3])
        f.start(text: "", image: image, source: .screenshot)
        try await waitUntil { f.calls.count == 1 }
        f.calls[0].continuation.resume(returning: "image result")
        try await waitUntil { !f.coordinator.isWorking }
        f.coordinator.changeResultTargetLanguage("en")
        try await waitUntil { f.calls.count == 2 }
        XCTAssertEqual(f.calls[1].request.imageData, image)
        XCTAssertEqual(f.calls[1].request.text, "")
        XCTAssertEqual(f.calls[1].request.source, .screenshot)
        f.calls[1].continuation.resume(returning: "new image result")
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertEqual(f.coordinator.lastResult?.translated, "new image result")
    }

    func testRapidChangesIgnoreOldSuccessAndFailure() async throws {
        let f = Fixture()
        f.start()
        try await waitUntil { f.calls.count == 1 }
        f.coordinator.changeResultTargetLanguage("ja")
        try await waitUntil { f.calls.count == 2 }
        f.coordinator.changeResultSourceLanguage("en")
        try await waitUntil { f.calls.count == 3 }
        f.calls[2].continuation.resume(returning: "latest")
        try await waitUntil { !f.coordinator.isWorking }
        f.calls[0].continuation.resume(returning: "stale")
        f.calls[1].continuation.resume(throwing: TestError.oldFailure)
        // Allow the deliberately late completions to run.
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(f.coordinator.lastResult?.translated, "latest")
        XCTAssertEqual(f.coordinator.lastResult?.sourceLang, "en")
        XCTAssertEqual(f.coordinator.lastResult?.targetLang, "ja")
        XCTAssertNil(f.coordinator.errorMessage)
        XCTAssertFalse(f.coordinator.isWorking)
    }

    func testConfigurationCapturedBeforeTaskStartsAndSettingsEditsDoNotRetranslate() async throws {
        let f = Fixture()
        f.settings.model = "request-model"
        f.start()
        f.settings.sourceLanguage = "en"
        f.settings.targetLanguage = "ja"
        f.settings.model = "later-model"
        try await waitUntil { f.calls.count == 1 }
        XCTAssertEqual(f.calls[0].config.model, "request-model")
        XCTAssertEqual(f.calls[0].config.sourceLanguage, "auto")
        XCTAssertEqual(f.calls[0].config.targetLanguage, "zh-Hans")
        f.calls[0].continuation.resume(returning: "result")
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertEqual(f.calls.count, 1)
        XCTAssertEqual(f.coordinator.lastResult?.model, "request-model")
        XCTAssertEqual(f.coordinator.lastResult?.sourceLang, "auto")
        XCTAssertEqual(f.coordinator.lastResult?.targetLang, "zh-Hans")
    }

    func testFailureClearsLoadingAndLanguageChangeRetriesSameInput() async throws {
        let f = Fixture()
        f.start()
        try await waitUntil { f.calls.count == 1 }
        f.calls[0].continuation.resume(throwing: TestError.oldFailure)
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertNotNil(f.coordinator.errorMessage)
        XCTAssertNil(f.coordinator.statusMessage)
        f.coordinator.changeResultTargetLanguage("ja")
        XCTAssertNil(f.coordinator.errorMessage)
        try await waitUntil { f.calls.count == 2 }
        XCTAssertEqual(f.calls[1].request.text, "original")
        f.calls[1].continuation.resume(returning: "recovered")
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertEqual(f.coordinator.lastResult?.translated, "recovered")
    }
}
