import XCTest
@testable import HushTranslate

final class TranslationCacheTests: XCTestCase {
    private let service = LLMService(name: "Cloud", apiBaseURL: "https://example.com/v1", apiKey: "key", model: "model")

    private func key(text: String = "Text\n", source: String = "auto", target: String = "zh-Hans",
                     service: LLMService? = nil, apple: Bool = false, prompt: String = "Translate",
                     language: InterfaceLanguage = .chinese, timeout: Double = 60) -> TranslationCache.Key {
        let service = service ?? self.service
        let request = TranslationRequest(text: text, sourceLang: source, targetLang: target)
        let config = TranslateConfig(provider: apple ? .apple : .llm(service.id),
            service: apple ? nil : service, sourceLanguage: source, targetLanguage: target,
            requestTimeout: timeout, systemPrompt: prompt, ocrMode: .local)
        return TranslationCache.Key(request: request, config: config, interfaceLanguage: language)!
    }

    func testRequestAndCloudConfigurationChangesMiss() {
        var cache = TranslationCache()
        cache.store("translation", for: key())
        var changedModel = service
        changedModel.model = "another model"
        var changedEndpoint = service
        changedEndpoint.apiBaseURL = "https://another.example/v1"
        var changedCredential = service
        changedCredential.apiKey = "another key"
        var sameNameDifferentIdentity = service
        sameNameDifferentIdentity.id = UUID()
        let misses = [key(text: "Text"), key(text: "text\n"), key(text: "Text \n"),
            key(source: "en"), key(target: "ja"), key(service: changedModel),
            key(service: changedEndpoint), key(service: changedCredential),
            key(service: sameNameDifferentIdentity), key(prompt: "Explain"), key(language: .english)]
        for candidate in misses { XCTAssertNil(cache.value(for: candidate)) }
        XCTAssertEqual(cache.value(for: key()), "translation")
    }

    func testNormalizationNameAndTimeoutDoNotInvalidate() {
        var cache = TranslationCache()
        cache.store("translation", for: key())
        var equivalent = service
        equivalent.name = "New name"
        equivalent.apiBaseURL += "/"
        equivalent.apiKey = " key "
        equivalent.model = " model "
        XCTAssertEqual(cache.value(for: key(service: equivalent, timeout: 120)), "translation")
    }

    func testAppleIgnoresCloudConfigurationButMatchesLanguages() {
        var cache = TranslationCache()
        cache.store("apple", for: key(apple: true))
        XCTAssertEqual(cache.value(for: key(apple: true, prompt: "Different", language: .english)), "apple")
        XCTAssertNil(cache.value(for: key(source: "en", apple: true)))
        XCTAssertNil(cache.value(for: key(target: "ja", apple: true)))
    }

    func testEmptyResultsCannotReplaceLatestSuccess() {
        var cache = TranslationCache()
        cache.store("translation", for: key())
        cache.store(" \n", for: key(text: "Other"))
        XCTAssertEqual(cache.value(for: key()), "translation")
        XCTAssertNil(cache.value(for: key(text: "Other")))
    }
}
