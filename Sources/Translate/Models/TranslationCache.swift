import Foundation

/// One successful text translation per provider, scoped to the owning coordinator.
struct TranslationCache {
    struct Key: Equatable {
        let provider: TranslationProvider
        let text: String
        let sourceLanguage: String
        let targetLanguage: String
        private let cloud: CloudConfiguration?

        private struct CloudConfiguration: Equatable {
            let endpoint: String
            let model: String
            let apiKey: String
            let systemPrompt: String
            let interfaceLanguage: InterfaceLanguage
        }

        init?(request: TranslationRequest, config: TranslateConfig,
              interfaceLanguage: InterfaceLanguage) {
            guard request.source != .screenshot, request.imageData == nil else { return nil }
            provider = config.provider
            text = request.text
            sourceLanguage = request.sourceLang
            targetLanguage = request.targetLang
            if config.usesApple {
                cloud = nil
            } else {
                guard let service = config.service?.normalized else { return nil }
                cloud = CloudConfiguration(endpoint: service.apiBaseURL, model: service.model,
                    apiKey: service.apiKey, systemPrompt: config.systemPrompt,
                    interfaceLanguage: interfaceLanguage)
            }
        }
    }

    private struct Entry {
        let key: Key
        let translated: String
    }

    private var entries: [TranslationProvider: Entry] = [:]

    func value(for key: Key?) -> String? {
        guard let key, let entry = entries[key.provider], entry.key == key else { return nil }
        return entry.translated
    }

    mutating func store(_ translated: String, for key: Key?) {
        guard let key, !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        entries[key.provider] = Entry(key: key, translated: translated)
    }

    mutating func retainProviders(_ providers: Set<TranslationProvider>) {
        entries = entries.filter { providers.contains($0.key) }
    }
}
