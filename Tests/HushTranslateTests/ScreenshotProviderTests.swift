import XCTest
@testable import HushTranslate

@MainActor
final class ScreenshotProviderTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let suite = "ScreenshotProviderTests.\(UUID())"
        let defaults: UserDefaults
        let settings: SettingsStore
        var ocrCalls = 0
        var ocr: (Data) async throws -> String = { _ in "recognized" }
        var requests: [(TranslationRequest, TranslateConfig)] = []
        lazy var coordinator = AppCoordinator(settings: settings, recognizeScreenshot: { [unowned self] data in
            ocrCalls += 1
            return try await ocr(data)
        }, translate: { [unowned self] request, config in
            requests.append((request, config))
            return "translated"
        })
        init() {
            defaults = UserDefaults(suiteName: suite)!
            settings = SettingsStore(defaults: defaults)
        }
        deinit { defaults.removePersistentDomain(forName: suite) }
        @discardableResult
        func selectLLM() -> LLMService {
            let service = LLMService(name: "Cloud", apiBaseURL: "https://example.com/v1", apiKey: "key", model: "vision")
            settings.saveService(service)
            return service
        }
        func screenshot() {
            coordinator.runTranslate(text: "", imageData: Data([1, 2, 3]), source: .screenshot, presentWindow: false)
        }
    }

    private enum TestError: Error { case failed, timeout }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw TestError.timeout
    }

    func testAppleForcesLocalOCRAndRetranslationRetainsImageForLLM() async throws {
        let f = Fixture()
        f.settings.ocrMode = .remote
        f.screenshot()
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertEqual(f.ocrCalls, 1)
        XCTAssertEqual(f.requests.count, 1)
        XCTAssertEqual(f.requests[0].0.text, "recognized")
        XCTAssertNil(f.requests[0].0.imageData)
        XCTAssertEqual(f.requests[0].1.provider, .apple)
        XCTAssertEqual(f.coordinator.lastResult?.original, "recognized")
        XCTAssertEqual(f.coordinator.lastResult?.providerName, "Apple 翻译")
        let service = f.selectLLM()
        XCTAssertEqual(f.requests.count, 1)
        f.coordinator.changeResultProvider(.llm(service.id))
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertEqual(f.requests.count, 2)
        XCTAssertEqual(f.requests[1].0.imageData, Data([1, 2, 3]))
        XCTAssertEqual(f.coordinator.lastResult?.providerName, "Cloud - vision")
    }

    func testRemoteLLMToAppleRunsOCRWhenOriginalTextIsMissing() async throws {
        let f = Fixture()
        f.selectLLM()
        f.settings.ocrMode = .remote
        f.screenshot()
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertEqual(f.ocrCalls, 0)
        XCTAssertEqual(f.requests[0].0.text, "")
        f.coordinator.changeResultProvider(.apple)
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertEqual(f.ocrCalls, 1)
        XCTAssertEqual(f.requests[1].0.text, "recognized")
        XCTAssertNil(f.requests[1].0.imageData)
    }

    func testLLMPreservesOCRModesAndFallback() async throws {
        for mode in OCRMode.allCases {
            let f = Fixture()
            f.selectLLM()
            f.settings.ocrMode = mode
            f.screenshot()
            try await waitUntil { !f.coordinator.isWorking }
            XCTAssertEqual(f.ocrCalls, mode == .remote ? 0 : 1)
            XCTAssertEqual(f.requests.count, 1)
            XCTAssertNotNil(f.requests[0].0.imageData)
            XCTAssertEqual(f.requests[0].0.text, mode == .remote ? "" : "recognized")
        }
        for shouldThrow in [false, true] {
            let f = Fixture()
            f.selectLLM()
            f.settings.ocrMode = .both
            f.ocr = { _ in if shouldThrow { throw TestError.failed }; return " " }
            f.screenshot()
            try await waitUntil { !f.coordinator.isWorking }
            XCTAssertEqual(f.requests.count, 1)
            XCTAssertEqual(f.requests[0].0.text, "")
            XCTAssertNotNil(f.requests[0].0.imageData)
        }
    }

    func testAppleOCRFailureNeverCallsTranslationOrFallsBack() async throws {
        for shouldThrow in [false, true] {
            let f = Fixture()
            f.settings.ocrMode = .both
            f.ocr = { _ in if shouldThrow { throw TestError.failed }; return " " }
            f.screenshot()
            try await waitUntil { !f.coordinator.isWorking }
            XCTAssertTrue(f.requests.isEmpty)
            XCTAssertNotNil(f.coordinator.errorMessage)
            XCTAssertNil(f.coordinator.statusMessage)
        }
    }

    func testScreenshotKeepsSnapshotWhileOCRWaits() async throws {
        let f = Fixture()
        var pending: CheckedContinuation<String, Error>?
        f.ocr = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        f.screenshot()
        try await waitUntil { pending != nil }
        f.selectLLM()
        f.settings.targetLanguage = "ja"
        pending?.resume(returning: "captured")
        try await waitUntil { !f.coordinator.isWorking }
        XCTAssertEqual(f.requests[0].1.provider, .apple)
        XCTAssertEqual(f.requests[0].0.targetLang, "zh-Hans")
        XCTAssertNil(f.requests[0].0.imageData)
    }

    func testLateOCRCannotReplaceNewSelectionOrItsRetryInput() async throws {
        for shouldThrow in [false, true] {
            let f = Fixture()
            var pending: CheckedContinuation<String, Error>?
            f.ocr = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
            f.screenshot()
            try await waitUntil { pending != nil }
            f.coordinator.runTranslate(text: "new selection", imageData: nil, source: .selection, presentWindow: false)
            try await waitUntil { !f.coordinator.isWorking }
            if shouldThrow { pending?.resume(throwing: TestError.failed) }
            else { pending?.resume(returning: "stale OCR") }
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertEqual(f.requests.count, 1)
            XCTAssertEqual(f.coordinator.lastResult?.original, "new selection")
            XCTAssertNil(f.coordinator.errorMessage)
            f.coordinator.changeResultTargetLanguage("ja")
            try await waitUntil { !f.coordinator.isWorking }
            XCTAssertEqual(f.requests[1].0.text, "new selection")
        }
    }

    func testDefaultRouterUsesAppleBridgeAndCancellationClearsLoading() async throws {
        let f = Fixture()
        let appleTranslation = AppleTranslationService(routeSelection: { _ in (.lowLatency, false) })
        let coordinator = AppCoordinator(settings: f.settings, appleTranslation: appleTranslation)
        coordinator.runTranslate(text: "Hello", imageData: nil, source: .clipboard, presentWindow: false)
        try await waitUntil { coordinator.appleTranslation.job != nil }
        let id = try XCTUnwrap(coordinator.appleTranslation.job?.id)
        await coordinator.appleTranslation.execute(id: id) { _ in "你好" }
        try await waitUntil { !coordinator.isWorking }
        XCTAssertEqual(coordinator.lastResult?.translated, "你好")
        XCTAssertEqual(coordinator.lastResult?.providerName, "Apple 翻译")
        coordinator.changeResultTargetLanguage("ja")
        try await waitUntil { coordinator.appleTranslation.job != nil }
        coordinator.appleTranslation.cancel()
        try await waitUntil { !coordinator.isWorking }
        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertNil(coordinator.statusMessage)
    }
}
