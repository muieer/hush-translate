import SwiftUI
import AppKit

/// 翻译结果悬浮窗内容
struct ResultPanelView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var sessionPresentation: SessionPresentation
    @State private var copiedTranslation = false
    @State private var copiedOriginal = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.settings = coordinator.settings
        self.sessionPresentation = coordinator.sessionPresentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .background { AppleTranslationHost(service: coordinator.appleTranslation) }
        .padding(14)
        .frame(minWidth: 412, maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            providerMenu
            Spacer()
            languageMenu(
                code: settings.sourceLanguage,
                includeAuto: true
            ) { coordinator.changeResultSourceLanguage($0) }
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            languageMenu(
                code: settings.targetLanguage,
                includeAuto: false
            ) { coordinator.changeResultTargetLanguage($0) }
        }
    }

    private var providerMenu: some View {
        Menu {
            Picker(L10n.tr("翻译来源"), selection: Binding(
                get: { coordinator.resultProvider ?? settings.provider },
                set: { coordinator.changeResultProvider($0) }
            )) {
                Text(L10n.tr("Apple 翻译")).tag(TranslationProvider.apple)
                ForEach(settings.services) { service in
                    Text(service.displayName).tag(TranslationProvider.llm(service.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(coordinator.resultProviderName ?? settings.snapshot().displayName)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.tr("切换翻译来源并重新翻译，不消耗会话次数"))
    }

    /// 内联语言下拉选择器：点击展开语言列表，选中即改，
    /// 标签显示当前语言名，免去了开设置页才能改的麻烦。
    private func languageMenu(code: String, includeAuto: Bool, onSelect: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(SettingsStore.languages, id: \.code) { l in
                if includeAuto || l.code != "auto" {
                    Button(l.label) { onSelect(l.code) }
                }
            }
        } label: {
            Text(langLabel(code))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        if coordinator.isWorking {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(coordinator.statusMessage ?? L10n.tr("翻译中…"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 40, maxHeight: 60)
        } else if let err = coordinator.errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.tr("出错了"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 12, weight: .semibold))
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let result = coordinator.lastResult {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !result.original.isEmpty {
                        sectionTitle(L10n.tr("原文"))
                        selectableText(result.original, font: 11, color: .secondary)
                        copyButton(result.original, isOriginal: true)
                    }
                    if !result.original.isEmpty && !result.translated.isEmpty {
                        Divider()
                    }
                    if !result.translated.isEmpty {
                        sectionTitle(L10n.tr("译文"))
                        selectableText(result.translated, font: 13, color: .primary)
                        copyButton(result.translated, isOriginal: false)
                    }
                }
            }
        } else {
            Text(L10n.tr("等待翻译结果…"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40, maxHeight: 60)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(L10n.format("会话：%@", sessionPresentation.status.title))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Button(L10n.tr("关闭会话")) { coordinator.closeTranslationSession() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!sessionPresentation.status.isActive)

            Button(L10n.tr("重置会话")) { coordinator.resetTranslationSession() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!sessionPresentation.status.isActive || !coordinator.translationSession.canReset)

            Spacer(minLength: 0)

            if let result = coordinator.lastResult {
                Text(String(format: "%.1fs", result.latency))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Button {
                coordinator.toggleResultPanelPin()
            } label: {
                Image(systemName: coordinator.resultPanelPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(coordinator.resultPanelPinned ? L10n.tr("取消置顶") : L10n.tr("置顶（浮在最前）"))
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
    }

    private func selectableText(_ s: String, font: CGFloat, color: Color) -> some View {
        Text(s)
            .font(.system(size: font))
            .foregroundColor(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyButton(_ value: String, isOriginal: Bool) -> some View {
        let copied = isOriginal ? copiedOriginal : copiedTranslation
        let label = isOriginal ? L10n.tr("原文") : L10n.tr("译文")
        return Button {
            copy(value)
            if isOriginal {
                copiedOriginal = true
                scheduleReset(\.copiedOriginal)
            } else {
                copiedTranslation = true
                scheduleReset(\.copiedTranslation)
            }
        } label: {
            Label(copied ? L10n.format("已复制%@", label) : L10n.format("复制%@", label), systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func scheduleReset(_ keyPath: ReferenceWritableKeyPath<ResultPanelView, Bool>) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self[keyPath: keyPath] = false
        }
    }

    private func langLabel(_ code: String) -> String {
        SettingsStore.languages.first(where: { $0.code == code })?.label ?? code
    }
}
