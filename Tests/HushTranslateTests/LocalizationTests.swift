import XCTest
@testable import HushTranslate

@MainActor
final class LocalizationTests: XCTestCase {
    func testEnglishResourcesAndChineseFallback() {
        XCTAssertEqual(L10n.tr("设置", language: .english), "Settings")
        XCTAssertEqual(L10n.tr("翻译中…", language: .english), "Translating…")
        XCTAssertEqual(L10n.tr("设置", language: .chinese), "设置")
        XCTAssertEqual(L10n.tr("missing", language: .english), "missing")
        XCTAssertEqual(L10n.selectionsLeft(1, language: .english), "1 selection left")
        XCTAssertEqual(L10n.selectionsLeft(2, language: .english), "2 selections left")
        XCTAssertEqual(L10n.minutesLeft("1", language: .english), "1 minute left")
        XCTAssertEqual(L10n.startForMinutes(2, language: .english), "Start for 2 minutes")
    }

    func testSessionAndScreenshotOptionLabelsUseSelectedLanguage() {
        XCTAssertEqual(SessionMode.count.label(for: .chinese), "按次数开启")
        XCTAssertEqual(SessionMode.count.label(for: .english), "By selection count")
        XCTAssertEqual(OCRMode.both.label(for: .chinese), "本地优先")
        XCTAssertEqual(OCRMode.both.label(for: .english), "On-device first")
        XCTAssertEqual(L10n.tr("会话参数", language: .english), "Session Defaults")
        XCTAssertEqual(L10n.tr("OCR 模式", language: .english), "OCR Mode")
    }

    func testLanguagePersistsAndOnlyBuiltInPromptChanges() throws {
        let suite = "LocalizationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.interfaceLanguage, .chinese)
        XCTAssertEqual(settings.systemPrompt, SettingsStore.defaultSystemPrompt)

        settings.interfaceLanguage = .english
        XCTAssertEqual(settings.systemPrompt, SettingsStore.defaultSystemPromptEnglish)
        XCTAssertEqual(SettingsStore(defaults: defaults).interfaceLanguage, .english)
        XCTAssertEqual(SettingsStore(defaults: defaults).systemPrompt, SettingsStore.defaultSystemPromptEnglish)

        settings.systemPrompt = "Keep this custom prompt: {input}"
        settings.interfaceLanguage = .chinese
        XCTAssertEqual(settings.systemPrompt, "Keep this custom prompt: {input}")
        XCTAssertEqual(SettingsStore(defaults: defaults).systemPrompt, "Keep this custom prompt: {input}")
    }
}
