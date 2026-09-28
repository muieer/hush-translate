import AVFoundation
import Combine
import NaturalLanguage

@MainActor
protocol SpeechSynthesizing: AnyObject {
    var delegate: AVSpeechSynthesizerDelegate? { get set }
    func speak(_ utterance: AVSpeechUtterance)
    func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool
    func continueSpeaking() -> Bool
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: SpeechSynthesizing {}

/// Owns the single speech stream shared by the original and translated text.
@MainActor
final class ResultSpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum Section { case original, translation }
    enum State { case idle, speaking, paused }

    @Published private(set) var section: Section?
    @Published private(set) var state: State = .idle
    private var utterance: AVSpeechUtterance?
    private let suppliedSynthesizer: SpeechSynthesizing?
    private lazy var synthesizer: SpeechSynthesizing = {
        let engine = suppliedSynthesizer ?? AVSpeechSynthesizer()
        engine.delegate = self
        return engine
    }()

    init(synthesizer: SpeechSynthesizing? = nil) {
        self.suppliedSynthesizer = synthesizer
        super.init()
    }

    func toggle(_ section: Section, text: String, language: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if self.section == section {
            switch state {
            case .speaking:
                if synthesizer.pauseSpeaking(at: .immediate) { state = .paused }
                return
            case .paused:
                if synthesizer.continueSpeaking() { state = .speaking }
                return
            case .idle:
                break
            }
        }

        stop()
        let utterance = AVSpeechUtterance(string: text)
        if let language = Self.voiceLanguage(for: language, text: text) {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        self.utterance = utterance
        self.section = section
        state = .speaking
        synthesizer.speak(utterance)
    }

    func stop() {
        guard utterance != nil else { return }
        // Invalidate before stopping: cancellation can arrive after the next speak call.
        utterance = nil
        section = nil
        state = .idle
        _ = synthesizer.stopSpeaking(at: .immediate)
    }

    static func voiceLanguage(for language: String, text: String) -> String? {
        let resolved = language == "auto"
            ? NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
            : language
        switch resolved {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return resolved
        }
    }

    private func finish(_ identifier: ObjectIdentifier) {
        guard let utterance, ObjectIdentifier(utterance) == identifier else { return }
        self.utterance = nil
        section = nil
        state = .idle
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                      didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(identifier) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                      didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(identifier) }
    }
}
