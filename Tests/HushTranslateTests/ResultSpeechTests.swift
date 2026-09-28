import AVFoundation
import XCTest
import SwiftUI
@testable import HushTranslate

@MainActor
final class ResultSpeechTests: XCTestCase {
    private final class Synthesizer: SpeechSynthesizing {
        weak var delegate: AVSpeechSynthesizerDelegate?
        var utterances: [AVSpeechUtterance] = []
        var operations: [String] = []
        var acceptsControl = true
        func speak(_ utterance: AVSpeechUtterance) {
            utterances.append(utterance)
            operations.append("speak")
        }
        func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool {
            operations.append("pause")
            return acceptsControl
        }
        func continueSpeaking() -> Bool {
            operations.append("resume")
            return acceptsControl
        }
        func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
            operations.append("stop")
            return true
        }
    }

    func testPauseAndResumeDoNotRestartText() {
        let engine = Synthesizer()
        let speech = ResultSpeechController(synthesizer: engine)
        speech.toggle(.original, text: "Hello world", language: "en")
        XCTAssertEqual(speech.state, .speaking)
        XCTAssertEqual(speech.section, .original)
        speech.toggle(.original, text: "Hello world", language: "en")
        XCTAssertEqual(speech.state, .paused)
        speech.toggle(.original, text: "Hello world", language: "en")
        XCTAssertEqual(speech.state, .speaking)
        XCTAssertEqual(engine.operations, ["speak", "pause", "resume"])
        XCTAssertEqual(engine.utterances.map(\.speechString), ["Hello world"])
        XCTAssertTrue(engine.utterances[0].voice?.language.hasPrefix("en") == true)
    }

    func testSwitchStopsSpeakingOrPausedTextAndIgnoresLateCallbacks() async {
        for paused in [false, true] {
            let engine = Synthesizer()
            let speech = ResultSpeechController(synthesizer: engine)
            speech.toggle(.original, text: "Hello", language: "en")
            let old = engine.utterances[0]
            if paused { speech.toggle(.original, text: "Hello", language: "en") }
            speech.toggle(.translation, text: "你好", language: "zh-Hans")
            XCTAssertEqual(Array(engine.operations.suffix(2)), ["stop", "speak"])
            XCTAssertEqual(engine.utterances.last?.speechString, "你好")
            let callbackEngine = AVSpeechSynthesizer()
            speech.speechSynthesizer(callbackEngine, didCancel: old)
            speech.speechSynthesizer(callbackEngine, didFinish: old)
            await Task.yield()
            XCTAssertEqual(speech.section, .translation)
            XCTAssertEqual(speech.state, .speaking)
            speech.speechSynthesizer(callbackEngine, didFinish: engine.utterances[1])
            for _ in 0..<100 where speech.state != .idle { await Task.yield() }
            XCTAssertEqual(speech.state, .idle)
            XCTAssertNil(speech.section)
            speech.toggle(.translation, text: "你好", language: "zh-Hans")
            XCTAssertEqual(engine.utterances.count, 3)
        }
    }

    func testRejectedPauseAndResumeKeepActualState() {
        let engine = Synthesizer()
        let speech = ResultSpeechController(synthesizer: engine)
        speech.toggle(.original, text: "Hello", language: "en")
        engine.acceptsControl = false
        speech.toggle(.original, text: "Hello", language: "en")
        XCTAssertEqual(speech.state, .speaking)
        engine.acceptsControl = true
        speech.toggle(.original, text: "Hello", language: "en")
        engine.acceptsControl = false
        speech.toggle(.original, text: "Hello", language: "en")
        XCTAssertEqual(speech.state, .paused)
    }

    func testStopClearsPausedPlaybackAndBlankTextDoesNotStart() {
        let engine = Synthesizer()
        let speech = ResultSpeechController(synthesizer: engine)
        speech.toggle(.original, text: " \n ", language: "auto")
        XCTAssertTrue(engine.operations.isEmpty)
        speech.toggle(.original, text: "Hello", language: "en")
        speech.toggle(.original, text: "Hello", language: "en")
        speech.stop()
        speech.stop()
        XCTAssertEqual(speech.state, .idle)
        XCTAssertNil(speech.section)
        XCTAssertEqual(engine.operations, ["speak", "pause", "stop"])
    }

    func testResultLifecycleStopsSpeech() {
        let suite = "ResultSpeechTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = Synthesizer()
        let speech = ResultSpeechController(synthesizer: engine)
        let coordinator = AppCoordinator(settings: SettingsStore(defaults: defaults), resultSpeech: speech)
        let result = TranslationResult(original: "Hello", translated: "你好", sourceLang: "en",
                                       targetLang: "zh-Hans", providerName: "Test", latency: 0,
                                       timestamp: Date(), source: .selection)
        coordinator.lastResult = result
        speech.toggle(.original, text: result.original, language: result.sourceLang)
        coordinator.lastResult = result
        XCTAssertEqual(speech.state, .speaking, "Reusing the same result must preserve playback")
        coordinator.isWorking = true
        XCTAssertEqual(speech.state, .idle)
        coordinator.isWorking = false
        speech.toggle(.translation, text: result.translated, language: result.targetLang)
        coordinator.lastResult = nil
        XCTAssertEqual(speech.state, .idle)
        speech.toggle(.original, text: result.original, language: result.sourceLang)
        coordinator.dismissResultPanel()
        XCTAssertEqual(speech.state, .idle)
        XCTAssertEqual(engine.operations.filter { $0 == "stop" }.count, 3)
    }

    func testWindowCloseNotifiesSpeechOwner() {
        let engine = Synthesizer()
        let speech = ResultSpeechController(synthesizer: engine)
        let panel = FloatingPanelController<AnyView>(autosaveName: nil)
        panel.onClose = { speech.stop() }
        speech.toggle(.original, text: "Hello", language: "en")
        panel.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertEqual(speech.state, .idle)
        XCTAssertEqual(engine.operations, ["speak", "stop"])
    }

    func testLanguageResolution() {
        XCTAssertEqual(ResultSpeechController.voiceLanguage(for: "zh-Hans", text: ""), "zh-CN")
        XCTAssertEqual(ResultSpeechController.voiceLanguage(for: "zh-Hant", text: ""), "zh-TW")
        for language in ["en", "ja", "ko", "fr", "de", "ru", "es", "it", "pt"] {
            XCTAssertEqual(ResultSpeechController.voiceLanguage(for: language, text: "你好"), language)
        }
        XCTAssertEqual(ResultSpeechController.voiceLanguage(for: "auto", text: "This is a complete sentence written in English."), "en")
        XCTAssertNil(ResultSpeechController.voiceLanguage(for: "auto", text: ""))
    }
}
