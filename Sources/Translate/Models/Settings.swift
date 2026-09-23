import Foundation
import SwiftUI

/// 给 TranslateService 用的不可变配置快照（Sendable，actor 内部安全）
struct TranslateConfig: Sendable {
    let apiBaseURL: String
    let apiKey: String
    let model: String
    let sourceLanguage: String
    let targetLanguage: String
    let requestTimeout: Double
    let systemPrompt: String
}

/// 截图 OCR 模式
enum OCRMode: String, CaseIterable, Identifiable {
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

    @Published var apiBaseURL: String { didSet { defaults.set(apiBaseURL, forKey: "apiBaseURL") } }
    @Published var apiKey: String { didSet { defaults.set(apiKey, forKey: "apiKey") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "model") } }

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
        self.apiBaseURL           = d.string(forKey: "apiBaseURL") ?? "http://localhost:1234/v1"
        self.apiKey               = d.string(forKey: "apiKey") ?? "lm-studio"
        self.model                = d.string(forKey: "model") ?? "qwen2.5-7b-instruct"
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
            apiBaseURL: apiBaseURL,
            apiKey: apiKey,
            model: model,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            requestTimeout: requestTimeout,
            systemPrompt: systemPrompt
        )
    }

    /// 全部语言（标签、code）
    static let languages: [(label: String, code: String)] = [
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
