import Combine
import Foundation

@MainActor
protocol SelectionMonitoring: AnyObject {
    /// Deliver text only after the user confirms the selection with the translation button.
    func start(shouldCapture: @escaping () -> Bool, onCapture: @escaping (String) -> Void)
    func stop()
}

/// Connects session admission to capture without introducing a second translation path.
@MainActor
final class SelectionTranslationController {
    private let session: TranslationSessionStore
    private let monitor: SelectionMonitoring
    private let configuration: () -> TranslationSessionConfiguration
    private let translate: (String) -> Void
    private var observation: AnyCancellable?
    private var captureGeneration = UUID()

    init(
        session: TranslationSessionStore,
        monitor: SelectionMonitoring,
        configuration: @escaping () -> TranslationSessionConfiguration,
        translate: @escaping (String) -> Void
    ) {
        self.session = session
        self.monitor = monitor
        self.configuration = configuration
        self.translate = translate
        observation = session.$state.sink { [weak self] state in
            self?.updateMonitoring(for: state)
        }
    }

    func startDefaultSession() throws {
        try session.start(configuration: configuration())
    }

    private func updateMonitoring(for state: TranslationSessionState) {
        // @Published emits before assigning state: use the emitted value here.
        // Replacing/restarting a session invalidates captures already in flight.
        captureGeneration = UUID()
        monitor.stop()
        guard state != .off else { return }
        let generation = captureGeneration
        monitor.start(shouldCapture: { [weak self] in
            guard let self, self.captureGeneration == generation else { return false }
            self.session.refreshExpiration()
            return self.session.state != .off && self.captureGeneration == generation
        }, onCapture: { [weak self] text in
            guard let self, self.captureGeneration == generation,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  self.session.consumeValidSelection() else { return }
            // COUNT is consumed at admission, even if the network later fails or
            // the next selection cancels this translation. The final count still translates.
            self.translate(text)
        })
    }
}
