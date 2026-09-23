import SwiftUI
import KeyboardShortcuts

/// 设置面板
struct PreferencesView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject var settings: SettingsStore
    let editSession: PreferencesEditSession

    private enum Tab: Hashable { case general, session, hotkey, screenshot, advanced }
    private enum Field: Hashable { case apiBaseURL, apiKey, model, sessionCount, sessionMinutes, requestTimeout, systemPrompt }
    private enum SaveStatus: Equatable {
        case unsaved, saved, invalid(String)
    }

    @State private var selectedTab: Tab = .general
    @State private var drafts: [Field: String]
    @State private var statuses: [Field: SaveStatus] = [:]
    @FocusState private var focusedField: Field?

    init(settings: SettingsStore, editSession: PreferencesEditSession) {
        self.settings = settings
        self.editSession = editSession
        _drafts = State(initialValue: [
            .apiBaseURL: settings.apiBaseURL,
            .apiKey: settings.apiKey,
            .model: settings.model,
            .sessionCount: String(settings.sessionCount),
            .sessionMinutes: String(settings.sessionMinutes),
            .requestTimeout: settings.requestTimeout.formatted(.number),
            .systemPrompt: settings.systemPrompt,
        ])
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab.tabItem { Label("通用", systemImage: "gearshape") }.tag(Tab.general)
            sessionTab.tabItem { Label("翻译会话", systemImage: "character.cursor.ibeam") }.tag(Tab.session)
            hotkeyTab.tabItem { Label("快捷键", systemImage: "keyboard") }.tag(Tab.hotkey)
            screenshotTab.tabItem { Label("截图翻译", systemImage: "camera.viewfinder") }.tag(Tab.screenshot)
            advancedTab.tabItem { Label("高级", systemImage: "slider.horizontal.3") }.tag(Tab.advanced)
        }
        .frame(width: 580, height: 460)
        .padding(8)
        .onAppear { coordinator.refreshPermissions() }
        .onChange(of: focusedField) { oldField, newField in
            if oldField != newField, let oldField { commit(oldField) }
        }
        .onChange(of: selectedTab) { _, _ in
            if let focusedField { commit(focusedField) }
            focusedField = nil
        }
    }

    // MARK: - 通用

    private var generalTab: some View {
        Form {
            Section("OpenAI 兼容接口") {
                settingsRow("Base URL", field: .apiBaseURL)
                settingsRow("API Key", field: .apiKey)
                settingsRow("Model", field: .model)
                Text("支持 LM Studio、Ollama、OpenAI、DeepSeek、SiliconFlow、Moonshot 等所有 OpenAI 兼容 chat 接口。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("语言") {
                Picker("源语言", selection: $settings.sourceLanguage) {
                    ForEach(SettingsStore.languages, id: \.code) { l in
                        Text(l.label).tag(l.code)
                    }
                }
                Picker("目标语言", selection: $settings.targetLanguage) {
                    ForEach(SettingsStore.languages.filter { $0.code != "auto" }, id: \.code) { l in
                        Text(l.label).tag(l.code)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var sessionTab: some View {
        Form {
            Section("快捷键默认启动") {
                Picker("会话类型", selection: $settings.defaultSessionMode) {
                    ForEach(SessionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text("按快捷键会启动新的默认会话，再次按下会重新开始。开启后，在其他应用中划词即可翻译；关闭会话请使用菜单栏。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("会话参数") {
                sessionSettingsRow("默认次数", field: .sessionCount, unit: "次")
                sessionSettingsRow("默认时长", field: .sessionMinutes, unit: "分钟")
                Text("菜单栏的「开启 N 次」与「开启 N 分钟」也使用这些值。修改设置将在下次启动会话时生效。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 快捷键

    private var hotkeyTab: some View {
        Form {
            Section("全局快捷键（在系统任意位置生效）") {
                KeyboardShortcuts.Recorder(for: .startTranslationSession) {
                    Text("启动翻译会话：")
                }
                KeyboardShortcuts.Recorder(for: .translateScreenshot) {
                    Text("截图翻译：")
                }
                KeyboardShortcuts.Recorder(for: .translateClipboard) {
                    Text("剪贴板翻译：")
                }
                Text("默认：⌃⌥⌘D 启动默认会话 / ⌘⌥⇧S 截图 / ⌃⌥⌘V 剪贴板。可在录制框中按下新组合键覆盖。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("权限") {
                permissionRow(
                    "辅助功能",
                    status: coordinator.hasAccessibilityPermission,
                    request: { coordinator.requestAccessibilityPermission() },
                    help: "划词翻译会话依赖此权限。先按快捷键开启会话，再在其他应用中划词；再次按快捷键会重新开始会话。"
                )
                permissionRow(
                    "屏幕录制",
                    status: coordinator.hasScreenCapturePermission,
                    request: { coordinator.requestScreenCapturePermission() },
                    help: "截图翻译依赖此权限。未授权时，截图会提示权限错误。"
                )
                Button {
                    coordinator.refreshPermissions()
                } label: {
                    Label("重新检测", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Text("提示：辅助功能权限用 AXIsProcessTrusted() 探测；屏幕录制权限用 SCShareableContent 探测，未授权或偶发异常时可能误报未授权。点「去授权」打开系统设置，授权后回到此处点「重新检测」验证。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func permissionRow(_ name: String, status: Bool?, request: @escaping () -> Void, help: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon(status))
                .foregroundColor(statusColor(status))
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).font(.system(size: 13, weight: .semibold))
                    Text(statusText(status))
                        .font(.caption)
                        .foregroundColor(statusColor(status))
                }
                Text(help).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("去授权") { request() }
        }
        .padding(.vertical, 4)
    }

    private func statusIcon(_ status: Bool?) -> String {
        switch status {
        case .some(true):  return "checkmark.circle.fill"
        case .some(false): return "xmark.circle.fill"
        case .none:        return "questionmark.circle.fill"
        }
    }

    private func statusColor(_ status: Bool?) -> Color {
        switch status {
        case .some(true):  return .green
        case .some(false): return .orange
        case .none:        return .secondary
        }
    }

    private func statusText(_ status: Bool?) -> String {
        switch status {
        case .some(true):  return "已授权"
        case .some(false): return "未授权"
        case .none:        return "未检测"
        }
    }

    // MARK: - 截图翻译

    private var screenshotTab: some View {
        Form {
            Section("OCR 模式") {
                Picker("OCR 模式", selection: $settings.ocrMode) {
                    ForEach(OCRMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 6) {
                    bulletRow("本地 Vision：免费、离线、Mac 原生。识别不到时降级到远程（仅「本地优先」模式）。")
                    bulletRow("多模态大模型：直接把图片发给模型（需支持 vision 的模型，如 GPT-4o、Qwen2-VL、Qwen2.5-VL、Llama 3.2 Vision 等）。")
                    bulletRow("本地优先：先本地 OCR 拿文字，识别为空/失败再发图片给大模型。推荐使用。")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
        }
    }

    // MARK: - 高级

    private var advancedTab: some View {
        Form {
            Section("请求") {
                settingsRow("超时 (秒)", field: .requestTimeout, width: 80)
            }
            Section("自定义系统提示词") {
                TextEditor(text: draftBinding(for: .systemPrompt))
                    .font(.system(size: 12))
                    .frame(height: 120)
                    .focused($focusedField, equals: .systemPrompt)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                saveStatus(for: .systemPrompt)
                HStack {
                    Text("整段作为 system 消息发送。支持以下变量，发送前自动替换为实际值：")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("恢复默认") {
                        statuses[.systemPrompt] = .saved
                        drafts[.systemPrompt] = SettingsStore.defaultSystemPrompt
                        settings.systemPrompt = SettingsStore.defaultSystemPrompt
                        focusedField = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text("• {sourceLanguage} — 源语言（如“自动检测”、“英语”）\n• {targetLanguage} — 目标语言（如“中文（简体）”）\n• {input} — 需要翻译的原始文本")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("诊断") {
                Button("检查权限") {
                    coordinator.refreshPermissions()
                }
                Button("在 Finder 中显示数据目录") {
                    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        .appendingPathComponent("HushTranslate", isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
            }
        }
        .formStyle(.grouped)
    }

    private func draftBinding(for field: Field) -> Binding<String> {
        Binding(
            get: { drafts[field] ?? "" },
            set: { newValue in
                guard drafts[field] != newValue else { return }
                drafts[field] = newValue
                if !matchesSavedValue(newValue, for: field) {
                    statuses[field] = .unsaved
                }
            }
        )
    }

    private func settingsRow(_ title: String, field: Field, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 8) {
                    input(for: field)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: width)
                    saveStatus(for: field)
                }
            }
            if case .invalid(let message) = statuses[field] {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func sessionSettingsRow(_ title: String, field: Field, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    input(for: field)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: 100)
                    Spacer(minLength: 8)
                    Text(unit)
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    saveStatus(for: field)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if case .invalid(let message) = statuses[field] {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private func input(for field: Field) -> some View {
        if field == .apiKey {
            SecureField("", text: draftBinding(for: field))
                .focused($focusedField, equals: field)
                .onSubmit { commit(field, explicit: true) }
        } else {
            TextField("", text: draftBinding(for: field))
                .focused($focusedField, equals: field)
                .onSubmit { commit(field, explicit: true) }
        }
    }

    private func saveStatus(for field: Field) -> some View {
        let isSaved = statuses[field] == .saved
        return Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.green)
            .frame(width: 22, height: 22)
            .opacity(isSaved ? 1 : 0)
            .allowsHitTesting(isSaved)
            .help("已保存")
            .accessibilityLabel("已保存")
            .accessibilityHidden(!isSaved)
    }

    private func matchesSavedValue(_ draft: String, for field: Field) -> Bool {
        switch field {
        case .apiBaseURL: return draft == settings.apiBaseURL
        case .apiKey: return draft == settings.apiKey
        case .model: return draft == settings.model
        case .sessionCount: return positiveInteger(draft) == settings.sessionCount
        case .sessionMinutes: return positiveInteger(draft) == settings.sessionMinutes
        case .requestTimeout: return Double(draft) == settings.requestTimeout
        case .systemPrompt: return draft == settings.systemPrompt
        }
    }

    private func positiveInteger(_ field: Field) -> Int? {
        positiveInteger(drafts[field] ?? "")
    }

    private func positiveInteger(_ text: String) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(text), value > 0 else { return nil }
        return value
    }

    private func commit(_ field: Field, explicit: Bool = false) {
        guard !editSession.isClosing else { return }
        guard explicit || statuses[field] == .unsaved || isInvalid(field) else { return }
        switch field {
        case .apiBaseURL:
            settings.apiBaseURL = drafts[field] ?? ""
        case .apiKey:
            settings.apiKey = drafts[field] ?? ""
        case .model:
            settings.model = drafts[field] ?? ""
        case .sessionCount:
            guard let value = positiveInteger(field) else {
                statuses[field] = .invalid("请输入有效正整数；当前仍使用 \(settings.sessionCount) 次。")
                return
            }
            settings.setSessionCount(value)
        case .sessionMinutes:
            guard let value = positiveInteger(field) else {
                statuses[field] = .invalid("请输入有效正整数；当前仍使用 \(settings.sessionMinutes) 分钟。")
                return
            }
            settings.setSessionMinutes(value)
        case .requestTimeout:
            let input = drafts[field] ?? ""
            guard let value = Double(input), value.isFinite, value > 0 else {
                statuses[field] = .invalid("请输入大于 0 的秒数；当前仍使用 \(settings.requestTimeout.formatted(.number)) 秒。")
                return
            }
            settings.requestTimeout = value
        case .systemPrompt:
            let input = drafts[field] ?? ""
            guard !input.isEmpty else {
                statuses[field] = .invalid("提示词不能为空；当前仍使用已保存的内容。")
                return
            }
            settings.systemPrompt = input
        }
        statuses[field] = .saved
    }

    private func isInvalid(_ field: Field) -> Bool {
        if case .invalid = statuses[field] { return true }
        return false
    }
}
