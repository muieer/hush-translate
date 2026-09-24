import SwiftUI

/// 菜单栏下拉菜单
struct StatusBarMenu: View {
    /// 直接传 coordinator，不依赖 EnvironmentObject（MenuBarExtra .menu 样式对 EnvironmentObject 兼容性差）
    let coordinator: AppCoordinator

    @ObservedObject private var presentation: SessionPresentation
    @ObservedObject private var settings: SettingsStore

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.presentation = coordinator.sessionPresentation
        self.settings = coordinator.settings
    }

    var body: some View {
        Text("划词翻译：\(presentation.status.title)")

        Button("关闭会话") { coordinator.closeTranslationSession() }
            .disabled(!presentation.status.isActive)
        Button("持续开启") { coordinator.startTranslationSession(.always) }
        Button("开启 \(settings.sessionCount) 次") {
            coordinator.startTranslationSession(.count(settings.sessionCount))
        }
        Button("开启 \(settings.sessionMinutes) 分钟") {
            coordinator.startTranslationSession(.timer(minutes: settings.sessionMinutes))
        }

        Divider()

        Button("截图翻译") { coordinator.translateScreenshotNow() }

        Button("剪贴板翻译") { coordinator.translateClipboardNow() }

        Divider()

        Button("显示翻译窗口") { coordinator.showLastResult() }

        Button("设置") { coordinator.openPreferences() }

        Divider()

        Button("退出") { NSApp.terminate(nil) }
    }
}

/// Observes the same presentation as the open menu, including while the menu is closed.
struct SessionStatusLabel: View {
    @ObservedObject var presentation: SessionPresentation

    private static let iconSize = NSSize(width: 22, height: 18)

    private static let menuBarImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "MenuBarTemplate", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        // MenuBarExtra bridges to AppKit, which uses the image's intrinsic point size.
        image.size = iconSize
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Group {
            if let image = Self.menuBarImage {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .frame(width: Self.iconSize.width, height: Self.iconSize.height)
            } else {
                Image(systemName: "character.bubble")
            }
        }
        .accessibilityLabel("划词翻译：\(presentation.status.title)")
        .help("划词翻译：\(presentation.status.title)")
    }
}
