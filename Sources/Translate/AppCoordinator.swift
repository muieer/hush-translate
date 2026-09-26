import AppKit
import SwiftUI
import ApplicationServices
import ScreenCaptureKit

/// 全局 app 协调器。
/// - 持有配置 & 服务
/// - 注册全局快捷键回调
/// - 接受"启动翻译会话 / 截图 / 剪贴板"三种 action
/// - 显示 / 关闭悬浮结果窗
@MainActor
final class AppCoordinator: ObservableObject {

    static let shared = AppCoordinator()

    // MARK: - 状态

    @Published var settings: SettingsStore

    @Published private(set) var resultProviderName: String?
    @Published private(set) var resultProvider: TranslationProvider?
    @Published var lastResult: TranslationResult?
    @Published var isWorking = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    /// 结果悬浮窗是否置顶
    @Published var resultPanelPinned = false

    /// 三态：nil = 未检测，true = 已授权，false = 已知未授权
    @Published var hasAccessibilityPermission: Bool? = nil
    /// 三态：nil = 未检测，true = 已授权，false = 已知未授权
    @Published var hasScreenCapturePermission: Bool? = nil

    // MARK: - 服务

    private let performTranslation: ((TranslationRequest, TranslateConfig) async throws -> String)?
    private let recognizeScreenshot: ((Data) async throws -> String)?
    let appleTranslation: AppleTranslationService
    private let llmTranslation = TranslateService()
    let hotKey     = HotKeyService()
    let selection  = SelectionMonitor()
    let screenshot = ScreenshotService()
    let ocr        = OCRService()
    let translationSession = TranslationSessionStore()
    lazy var sessionPresentation = SessionPresentation(session: translationSession)

    private lazy var selectionTranslation = SelectionTranslationController(
        session: translationSession,
        monitor: selection,
        configuration: { [weak self] in self?.settings.defaultTranslationSession ?? .defaultPreset },
        translate: { [weak self] text in self?.runTranslate(text: text, imageData: nil, source: .selection) }
    )

    private var resultPanel: FloatingPanelController<AnyView>?
    private var workingTask: Task<Void, Never>?
    private var lastRequest: TranslationRequest?
    private var requestID = UUID()
    /// 截图选区控制器：必须持有，否则 onResult 闭包里的 weak self 在选区完成前
    /// 就随 controller 释放，导致 overlay 窗口 orderOut 不执行、画面卡在灰色选区态。
    private var screenshotOverlay: ScreenshotOverlayController?

    /// Inject the translation operation without registering shortcuts or showing windows.
    init(settings: SettingsStore,
         recognizeScreenshot: ((Data) async throws -> String)? = nil,
         translate: ((TranslationRequest, TranslateConfig) async throws -> String)? = nil,
         appleTranslation: AppleTranslationService? = nil) {
        self.settings = settings
        self.performTranslation = translate
        self.recognizeScreenshot = recognizeScreenshot
        self.appleTranslation = appleTranslation ?? AppleTranslationService()
    }

    private convenience init() {
        self.init(settings: SettingsStore())
        _ = selectionTranslation
        hotKey.onSession = { [weak self] in self?.startDefaultTranslationSession() }
        hotKey.onScreenshot = { [weak self] in self?.translateScreenshotNow() }
        hotKey.onClipboard  = { [weak self] in self?.translateClipboardNow() }
    }

    /// 完成安装位置检查后才注册快捷键和打开开发设置窗口。
    func bootstrap() {
        hotKey.install()
        if CommandLine.arguments.contains("--show-settings") {
            openPreferences()
        }
        // 不自动探测权限：由用户触发功能时检查。
    }

    // MARK: - 三种入口 action

    /// Starts a fresh preset session; never reads the current selection or toggles OFF.
    func startDefaultTranslationSession() {
        guard ensurePermissionsForSelection() else { return }
        do {
            try selectionTranslation.startDefaultSession()
        } catch {
            showSessionStartAlert(L10n.tr("翻译会话配置无效：次数和分钟数必须为正整数。"))
        }
    }

    func startTranslationSession(_ configuration: TranslationSessionConfiguration) {
        guard ensurePermissionsForSelection() else { return }
        do {
            try translationSession.start(configuration: configuration)
        } catch {
            showSessionStartAlert(L10n.tr("翻译会话配置无效：次数和分钟数必须为正整数。"))
        }
    }

    func closeTranslationSession() {
        translationSession.close()
    }

    func resetTranslationSession() {
        translationSession.reset()
    }

    /// 截图翻译
    func translateScreenshotNow() {
        guard ensurePermissionsForScreenshot() else { return }
        // 不提前显示结果面板：先全屏截图 + 弹选区框，
        // 截图/选区失败时不要留一个空面板。
        let captureID = beginRequest()
        errorMessage = nil
        statusMessage = L10n.tr("请框选截图区域…")
        isWorking = true

        let overlay = ScreenshotOverlayController()
        screenshotOverlay = overlay
        overlay.start(
            screenshot: screenshot,
            onResult: { [weak self] image in
                guard let self = self, self.requestID == captureID else { return }
                // 选区流程结束，释放 overlay（其内部已 orderOut 窗口）
                self.screenshotOverlay = nil
                guard let image = image else {
                    // 用户取消选区
                    self.isWorking = false
                    self.statusMessage = nil
                    return
                }
                self.processScreenshot(image)
            },
            onError: { [weak self] error in
                guard let self = self, self.requestID == captureID else { return }
                self.screenshotOverlay = nil
                self.isWorking = false
                self.statusMessage = nil
                // 截屏失败绝大多数是屏幕录制权限问题，主动引导授权
                if let captureError = error as? ScreenshotService.CaptureError,
                   case .permissionDenied = captureError {
                    self.hasScreenCapturePermission = false
                    self.showError(L10n.tr("需要「屏幕录制」权限才能截图翻译。\n请到 系统设置 → 隐私与安全性 → 屏幕录制 勾选「HushTranslate」，授权后重新触发本功能。"))
                    self.requestScreenCapturePermission()
                } else {
                    self.showError(L10n.format("截图失败：%@", error.localizedDescription))
                }
            }
        )
    }

    /// 翻译剪贴板内容
    func translateClipboardNow() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            showError(L10n.tr("剪贴板为空，请先复制要翻译的文本。"))
            return
        }
        runTranslate(text: text, imageData: nil, source: .clipboard)
    }

    // MARK: - 设置

    private var settingsWindow: NSWindow?
    private var settingsCloseDelegate: SettingsCloseDelegate?

    func openPreferences() {
        // 不依赖 SwiftUI Settings scene（MenuBarExtra .menu 下 sendAction 不可靠）
        // 自己管理一个 NSWindow
        if let win = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }
        let editSession = PreferencesEditSession()
        let view = PreferencesView(settings: settings, editSession: editSession)
            .environmentObject(self)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = L10n.tr("HushTranslate 设置")
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 600, height: 550))
        win.center()
        win.isReleasedWhenClosed = false
        // 在焦点变化之前标记关窗，让输入框丢弃尚未确认的草稿。
        let closeDelegate = SettingsCloseDelegate(editSession: editSession) { [weak self] in
            Task { @MainActor [weak self] in
                self?.settingsWindow = nil
                self?.settingsCloseDelegate = nil
            }
        }
        win.delegate = closeDelegate
        settingsCloseDelegate = closeDelegate
        settingsWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: - 关于

    private var aboutWindow: NSWindow?

    func openAbout() {
        if aboutWindow == nil {
            let win = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            win.title = L10n.tr("关于 HushTranslate")
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.setContentSize(NSSize(width: 480, height: 320))
            win.center()
            win.isReleasedWhenClosed = false
            aboutWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    func refreshLocalization() {
        sessionPresentation.refresh()
        settingsWindow?.title = L10n.tr("HushTranslate 设置")
        aboutWindow?.title = L10n.tr("关于 HushTranslate")
        if resultProvider == .apple { resultProviderName = L10n.tr("Apple 翻译") }
        refreshResultPanel()
    }

    // MARK: - 权限

    /// 检测当前权限状态（**不调 AXIsProcessTrustedWithOptions**）。
    /// 屏幕录制权限用 SCShareableContent 探测，**不会 crash**（未授权时 throw）。
    /// 辅助功能权限用"试一次 ⌘C 模拟"探测（不调 AX API）。
    func refreshPermissions() {
        Task { @MainActor in
            self.hasScreenCapturePermission = await ScreenCapture.probePermission()
            self.hasAccessibilityPermission = await self.probeAccessibilityPermission()
        }
    }

    /// 打开系统设置到辅助功能授权页
    func requestAccessibilityPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 打开系统设置到屏幕录制授权页
    func requestScreenCapturePermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 会话尚未开始时的提示独立于结果窗，不覆盖已有翻译状态。
    private func showSessionStartAlert(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("无法开启划词翻译会话")
        alert.informativeText = message
        alert.addButton(withTitle: L10n.tr("好"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @discardableResult
    private func ensurePermissionsForSelection() -> Bool {
        // Only an explicit session start can prompt; passive selections remain silent.
        if AXIsProcessTrusted() == false {
            showSessionStartAlert(L10n.tr("需要「辅助功能」权限才能开启划词翻译会话。\n请到 设置 → 隐私与安全性 → 辅助功能 勾选「HushTranslate」。\n\n授权后请重新打开本 App。"))
            requestAccessibilityPermission()
            return false
        }
        return true
    }

    @discardableResult
    private func ensurePermissionsForScreenshot() -> Bool {
        // 不依赖屏幕录制预探测（SCShareableContent 枚举在某些情况下即使已授权也会 throw，
        // 误报 false 后每次都弹设置）。直接放行，截图失败时再按 permissionDenied 分支引导。
        return true
    }

    // MARK: - 流程

    private func processScreenshot(_ image: NSImage) {
        guard let data = Self.pngData(from: image) else {
            showError(L10n.tr("截图无法转换为图片，请重新截图。"))
            return
        }
        runTranslate(text: "", imageData: data, source: .screenshot)
    }

    private func beginRequest() -> UUID {
        workingTask?.cancel()
        appleTranslation.cancel()
        requestID = UUID()
        return requestID
    }

    private func recognize(_ data: Data) async throws -> String {
        if let recognizeScreenshot { return try await recognizeScreenshot(data) }
        guard let image = NSImage(data: data) else { throw OCRService.OCRError.noCGImage }
        return try await ocr.recognizeText(in: image)
    }

    private enum InputError: LocalizedError {
        case emptyOCR
        var errorDescription: String? { L10n.tr("OCR 未识别到任何文字，请重新框选包含清晰文字的区域。") }
    }

    private func prepare(_ input: TranslationRequest, config: TranslateConfig) async throws -> TranslationRequest {
        var request = input
        if request.source == .screenshot, let image = request.imageData,
           request.text.isEmpty, config.ocrMode != .remote {
            do {
                statusMessage = L10n.tr("识别图中文字…")
                request.text = try await recognize(image)
                try Task.checkCancellation()
                if request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw InputError.emptyOCR
                }
            } catch {
                try Task.checkCancellation()
                guard config.ocrMode == .both else { throw error }
                request.text = ""
            }
        }
        // Apple accepts text only. Preserve the original image separately for later retranslations.
        if config.usesApple { request.imageData = nil }
        return request
    }

    private func translate(_ request: TranslationRequest, config: TranslateConfig) async throws -> String {
        if let performTranslation { return try await performTranslation(request, config) }
        if config.usesApple {
            return try await appleTranslation.translate(request) { [weak self] in
                // The system download consent is a sheet on this window. A selection result
                // normally appears without focus, so make it key before presenting the sheet.
                if self?.resultPanel?.isVisible() == true { self?.resultPanel?.activate() }
            }
        }
        return try await llmTranslation.translate(request, config: config)
    }

    func changeResultProvider(_ provider: TranslationProvider) {
        if case .llm(let id) = provider,
           !settings.services.contains(where: { $0.id == id }) { return }
        let currentProvider = resultProvider ?? settings.provider
        settings.selectProvider(provider)
        guard currentProvider != provider else { return }
        // Reuse the admitted input; changing providers never consumes a selection.
        retranslateLastInput()
    }

    func changeResultSourceLanguage(_ code: String) {
        guard settings.sourceLanguage != code else { return }
        settings.sourceLanguage = code
        retranslateLastInput()
    }

    func changeResultTargetLanguage(_ code: String) {
        guard settings.targetLanguage != code else { return }
        settings.targetLanguage = code
        retranslateLastInput()
    }

    private func retranslateLastInput() {
        guard let request = lastRequest else { return }
        runTranslate(text: request.text, imageData: request.imageData,
                     source: request.source, presentWindow: false)
    }

    func runTranslate(text: String, imageData: Data?, source: TranslationRequest.Source, presentWindow: Bool = true) {
        let id = beginRequest()
        let config = settings.snapshot()
        let input = TranslationRequest(text: text, sourceLang: config.sourceLanguage,
            targetLang: config.targetLanguage, imageData: imageData, source: source)
        resultProviderName = config.displayName
        resultProvider = config.provider
        lastResult = nil
        lastRequest = input
        isWorking = true
        errorMessage = nil
        statusMessage = L10n.tr("翻译中…")
        if presentWindow { showResultPanel() } else { refreshResultPanel() }

        workingTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.requestID == id else { return }
            let start = Date()
            do {
                let request = try await self.prepare(input, config: config)
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                // Cache OCR text, retaining the image when moving between providers.
                self.lastRequest?.text = request.text
                self.statusMessage = L10n.tr("翻译中…")
                let translated = try await self.translate(request, config: config)
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                self.isWorking = false
                self.statusMessage = nil
                self.lastResult = TranslationResult(
                    original: request.text, translated: translated,
                    sourceLang: request.sourceLang, targetLang: request.targetLang,
                    providerName: config.displayName, latency: Date().timeIntervalSince(start),
                    timestamp: Date(), source: source)
                self.refreshResultPanel()
            } catch {
                guard !Task.isCancelled, self.requestID == id else { return }
                self.isWorking = false
                self.statusMessage = nil
                self.errorMessage = error is CancellationError ? L10n.tr("翻译已取消，请重新选择文字或切换语言后重试。") : error.localizedDescription
                self.refreshResultPanel()
            }
        }
    }

    private func showError(_ msg: String, keepPosition: Bool = false) {
        errorMessage = msg
        isWorking = false
        statusMessage = nil
        showResultPanel(keepPosition: keepPosition)
    }

    // MARK: - 悬浮窗

    func showResultPanel(keepPosition: Bool = false) {
        if resultPanel == nil {
            resultPanel = FloatingPanelController<AnyView>()
        }
        resultPanel?.show(
            { AnyView(ResultPanelView(coordinator: self)) },
            size: NSSize(width: 440, height: 360),
            pinned: resultPanelPinned,
            bringToFront: !keepPosition
        )
    }

    func refreshResultPanel() {
        guard let panel = resultPanel else { return }
        panel.show(
            { AnyView(ResultPanelView(coordinator: self)) },
            size: NSSize(width: 440, height: 360),
            pinned: resultPanelPinned,
            keepPinned: true,
            bringToFront: false
        )
    }

    /// 菜单中的显式返回入口，不重新发起翻译。
    func showLastResult() {
        showResultPanel()
        resultPanel?.activate()
    }

    func dismissResultPanel() {
        resultPanel?.close()
    }

    /// 切换结果悬浮窗置顶
    func toggleResultPanelPin() {
        resultPanelPinned.toggle()
        resultPanel?.setPinned(resultPanelPinned)
    }

    // MARK: - Helpers

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }


}

@MainActor
final class PreferencesEditSession {
    var isClosing = false
}

@MainActor
private final class SettingsCloseDelegate: NSObject, NSWindowDelegate {
    private let editSession: PreferencesEditSession
    private let onDidClose: () -> Void

    init(editSession: PreferencesEditSession, onDidClose: @escaping () -> Void) {
        self.editSession = editSession
        self.onDidClose = onDidClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editSession.isClosing = true
        return true
    }

    func windowWillClose(_ notification: Notification) {
        editSession.isClosing = true
        onDidClose()
    }
}

// MARK: - 权限工具

extension AppCoordinator {
    /// 探测辅助功能权限：用 AXIsProcessTrusted()（无 options 版本，不发 prompt、ad-hoc 签名下安全不崩）。
    /// 不用 AXIsProcessTrustedWithOptions（那才会崩），也不用副作用探测法（不可靠）。
    fileprivate func probeAccessibilityPermission() async -> Bool {
        return AXIsProcessTrusted()
    }
}

private enum ScreenCapture {
    /// 用 SCShareableContent 探测：未授权时 throw（不会 crash）
    static func probePermission() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return !content.displays.isEmpty
        } catch {
            return false
        }
    }
}
