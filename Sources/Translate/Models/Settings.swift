import Foundation
import SwiftUI

/// Built-in Apple translation is a permanent choice, never a deletable service record.
enum TranslationProvider: Codable, Hashable, Sendable {
    case apple
    case llm(UUID)
}

struct LLMService: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var apiBaseURL = ""
    var apiKey = ""
    var model = ""

    var displayName: String { "\(name) - \(model)" }

    enum Field: Hashable { case name, apiBaseURL, apiKey, model }

    var validationErrors: [Field: String] {
        var errors: [Field: String] = [:]
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.name] = "请输入服务名称，例如「火山云」。"
        }
        let address = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URLComponents(string: address),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           let host = url.host, !host.isEmpty,
           url.query == nil, url.fragment == nil, url.user == nil, url.password == nil {
            // Base URL only; the client appends /chat/completions.
        } else {
            errors[.apiBaseURL] = "请输入有效的 HTTP 或 HTTPS 基础地址，例如 https://api.example.com/v1。"
        }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.apiKey] = "请输入 API Key；本地服务按其要求填写。"
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.model] = "请输入接口使用的模型名称。"
        }
        return errors
    }

    var normalized: Self {
        var value = self
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.apiBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.apiBaseURL.hasSuffix("/") { value.apiBaseURL.removeLast() }
        value.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }
}

/// Immutable request snapshot, including the selected service's identity and parameters.
struct TranslateConfig: Sendable {
    let provider: TranslationProvider
    let service: LLMService?
    let sourceLanguage: String
    let targetLanguage: String
    let requestTimeout: Double
    let systemPrompt: String
    let ocrMode: OCRMode

    var displayName: String { service?.displayName ?? "Apple 翻译" }
    var usesApple: Bool { provider == .apple }
}

/// Drafts live only as long as the preferences window; selection never commits them.
struct ServiceDrafts {
    private var values: [UUID: LLMService] = [:]
    func draft(for service: LLMService) -> LLMService { values[service.id] ?? service }
    mutating func update(_ service: LLMService) { values[service.id] = service }
    mutating func discard(_ id: UUID) { values.removeValue(forKey: id) }
}

/// 截图 OCR 模式
enum OCRMode: String, CaseIterable, Identifiable, Sendable {
    case local    // 本地 Vision（免费、离线）
    case remote   // 把图直接发给多模态大模型
    case both     // 本地优先，失败/空时降级到远程

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local:  return "本地 Vision"
        case .remote: return "多模态大模型"
        case .both:   return "本地优先"
        }
    }
}

enum SessionMode: String, CaseIterable, Identifiable {
    case always, count, timer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .always: return "持续开启"
        case .count: return "按次数开启"
        case .timer: return "按分钟开启"
        }
    }
}

/// 翻译服务配置。UserDefaults 持久化。
@MainActor
final class SettingsStore: ObservableObject {

    @Published var defaultSessionMode: SessionMode {
        didSet { defaults.set(defaultSessionMode.rawValue, forKey: "session.mode") }
    }
    @Published private(set) var sessionCount: Int
    @Published private(set) var sessionMinutes: Int

    var defaultTranslationSession: TranslationSessionConfiguration {
        switch defaultSessionMode {
        case .always: return .always
        case .count: return .count(sessionCount)
        case .timer: return .timer(minutes: sessionMinutes)
        }
    }

    @discardableResult
    func setSessionCount(_ value: Int) -> Bool {
        guard value > 0 else { return false }
        sessionCount = value
        defaults.set(value, forKey: "session.count")
        return true
    }

    @discardableResult
    func setSessionMinutes(_ value: Int) -> Bool {
        guard value > 0 else { return false }
        sessionMinutes = value
        defaults.set(value, forKey: "session.minutes")
        return true
    }

    private static func positiveInteger(_ defaults: UserDefaults, key: String, fallback: Int) -> Int {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let value = Int(number.stringValue), value > 0 else { return fallback }
        return value
    }

    @Published private(set) var services: [LLMService]
    @Published private(set) var provider: TranslationProvider

    var selectedService: LLMService? {
        guard case .llm(let id) = provider else { return nil }
        return services.first { $0.id == id }
    }

    func selectProvider(_ value: TranslationProvider) {
        if case .llm(let id) = value, !services.contains(where: { $0.id == id }) {
            provider = .apple
        } else {
            provider = value
        }
        persistProviders()
    }

    @discardableResult
    func saveService(_ draft: LLMService) -> Bool {
        guard draft.validationErrors.isEmpty else { return false }
        let value = draft.normalized
        if let index = services.firstIndex(where: { $0.id == value.id }) {
            services[index] = value
        } else {
            services.append(value)
            provider = .llm(value.id)
        }
        persistProviders()
        return true
    }

    func deleteService(_ id: UUID) {
        services.removeAll { $0.id == id }
        if provider == .llm(id) { provider = .apple }
        persistProviders()
    }

    private struct ProviderSettings: Codable {
        var version = 1
        var services: [LLMService]
        var selected: TranslationProvider
    }

    private func persistProviders() {
        if let data = try? JSONEncoder().encode(ProviderSettings(services: services, selected: provider)) {
            defaults.set(data, forKey: "translation.providers")
        }
    }

    @Published var sourceLanguage: String { didSet { defaults.set(sourceLanguage, forKey: "sourceLanguage") } }
    @Published var targetLanguage: String { didSet { defaults.set(targetLanguage, forKey: "targetLanguage") } }

    @Published var ocrMode: OCRMode { didSet { defaults.set(ocrMode.rawValue, forKey: "ocrMode") } }

    @Published var requestTimeout: Double { didSet { defaults.set(requestTimeout, forKey: "requestTimeout") } }
    @Published var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: "systemPrompt") } }

    private let defaults: UserDefaults

    init(defaults d: UserDefaults = .standard) {
        self.defaults = d
        self.defaultSessionMode = SessionMode(rawValue: d.string(forKey: "session.mode") ?? "") ?? .count
        self.sessionCount = Self.positiveInteger(d, key: "session.count", fallback: 3)
        self.sessionMinutes = Self.positiveInteger(d, key: "session.minutes", fallback: 10)
        if let data = d.data(forKey: "translation.providers"),
           let saved = try? JSONDecoder().decode(ProviderSettings.self, from: data) {
            self.services = saved.services
            if case .llm(let id) = saved.selected, !saved.services.contains(where: { $0.id == id }) {
                self.provider = .apple
            } else {
                self.provider = saved.selected
            }
        } else {
            self.services = []
            self.provider = .apple
            // A corrupt new-format value must not resurrect previously deleted legacy records.
            if d.object(forKey: "translation.providers") == nil,
               ["apiBaseURL", "apiKey", "model"].contains(where: { d.object(forKey: $0) != nil }) {
                self.services = [LLMService(name: "原有服务",
                    apiBaseURL: d.string(forKey: "apiBaseURL") ?? "http://localhost:1234/v1",
                    apiKey: d.string(forKey: "apiKey") ?? "lm-studio",
                    model: d.string(forKey: "model") ?? "qwen2.5-7b-instruct")]
            }
        }
        self.sourceLanguage       = d.string(forKey: "sourceLanguage") ?? "auto"
        self.targetLanguage       = d.string(forKey: "targetLanguage") ?? "zh-Hans"
        self.ocrMode              = OCRMode(rawValue: d.string(forKey: "ocrMode") ?? "local") ?? .local
        self.requestTimeout       = d.double(forKey: "requestTimeout") == 0 ? 60 : d.double(forKey: "requestTimeout")
        // 自定义系统提示词：作为整段 system 消息发送。
        // 支持变量渲染：{sourceLanguage}、{targetLanguage}、{input}。
        // 旧版本该字段为追加文本（键名 systemPromptAddition，值为空时无默认）；
        // 升级后键名改为 systemPrompt，并给出系统默认模板。
        if let stored = d.string(forKey: "systemPrompt"), !stored.isEmpty {
            self.systemPrompt = stored
        } else {
            self.systemPrompt = SettingsStore.defaultSystemPrompt
        }
        persistProviders()
    }

    /// 系统默认的提示词模板。翻译整段内容，只输出译文。
    /// 渲染变量：{sourceLanguage}、{targetLanguage}、{input}。
    static let defaultSystemPrompt = """
    你是一名专业翻译。请将以下文本从 {sourceLanguage} 翻译为 {targetLanguage}。
    只输出译文本身，不要任何解释、引号或前缀，保留原始换行与格式。

    需要翻译的文本：
    {input}
    """

    /// 不可变快照，actor 间传递
    func snapshot() -> TranslateConfig {
        TranslateConfig(
            provider: provider,
            service: selectedService,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            requestTimeout: requestTimeout,
            systemPrompt: systemPrompt,
            ocrMode: provider == .apple ? .local : ocrMode
        )
    }

    /// 全部语言（标签、code）
    nonisolated static let languages: [(label: String, code: String)] = [
        ("自动检测",       "auto"),
        ("中文（简体）",   "zh-Hans"),
        ("中文（繁体）",   "zh-Hant"),
        ("英语",           "en"),
        ("日语",           "ja"),
        ("韩语",           "ko"),
        ("法语",           "fr"),
        ("德语",           "de"),
        ("俄语",           "ru"),
        ("西班牙语",       "es"),
        ("意大利语",       "it"),
        ("葡萄牙语",       "pt"),
    ]
}
