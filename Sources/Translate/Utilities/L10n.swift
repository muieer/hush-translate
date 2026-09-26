import Foundation

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

/// Explicit app language, independent of macOS and the translation target language.
enum L10n {
    static var language: InterfaceLanguage {
        InterfaceLanguage(rawValue: UserDefaults.standard.string(forKey: "interface.language") ?? "") ?? .chinese
    }

    private static let englishBundle: Bundle? = {
        guard let path = Bundle.module.path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }()

    static func tr(_ chinese: String) -> String {
        tr(chinese, language: language)
    }

    static func tr(_ chinese: String, language: InterfaceLanguage) -> String {
        guard language == .english, let englishBundle else { return chinese }
        return englishBundle.localizedString(forKey: chinese, value: chinese, table: "Localizable")
    }

    static func format(_ chinese: String, _ args: CVarArg...) -> String {
        String(format: tr(chinese), locale: Locale(identifier: language.rawValue), arguments: args)
    }

    static func selectionsLeft(_ count: Int, language: InterfaceLanguage = L10n.language) -> String {
        language == .english
            ? "\(count) \(count == 1 ? "selection" : "selections") left"
            : "剩余 \(count) 次"
    }

    static func minutesLeft(_ count: String, language: InterfaceLanguage = L10n.language) -> String {
        language == .english
            ? "\(count) \(count == "1" ? "minute" : "minutes") left"
            : "剩余 \(count) 分钟"
    }

    static func startForSelections(_ count: Int, language: InterfaceLanguage = L10n.language) -> String {
        language == .english
            ? "Start for \(count) \(count == 1 ? "selection" : "selections")"
            : "开启 \(count) 次"
    }

    static func startForMinutes(_ count: Int, language: InterfaceLanguage = L10n.language) -> String {
        language == .english
            ? "Start for \(count) \(count == 1 ? "minute" : "minutes")"
            : "开启 \(count) 分钟"
    }

    static func invalidSelectionLimit(current: Int) -> String {
        language == .english
            ? "Enter a whole number greater than zero. The current limit is \(current)."
            : "请输入有效正整数；当前仍使用 \(current) 次。"
    }

    static func invalidDuration(current: Int) -> String {
        language == .english
            ? "Enter a whole number greater than zero. The current duration is \(current) \(current == 1 ? "minute" : "minutes")."
            : "请输入有效正整数；当前仍使用 \(current) 分钟。"
    }
}
