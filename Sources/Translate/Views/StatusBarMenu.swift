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

        Button {
            coordinator.translateScreenshotNow()
        } label: {
            Label("截图翻译", systemImage: "camera.viewfinder")
        }

        Button {
            coordinator.translateClipboardNow()
        } label: {
            Label("剪贴板翻译", systemImage: "doc.on.clipboard")
        }

        Divider()

        Button {
            coordinator.openPreferences()
        } label: {
            Label("设置…", systemImage: "gearshape")
        }

        Divider()

        Text("HushTranslate 0.1.0")
            .font(.system(size: 10))
            .foregroundColor(.secondary)

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("退出", systemImage: "power")
        }
    }
}

/// Observes the same presentation as the open menu, including while the menu is closed.
struct SessionStatusLabel: View {
    @ObservedObject var presentation: SessionPresentation

    private static let menuBarImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "MenuBarTemplate", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        // MenuBarExtra bridges to AppKit, which uses the image's intrinsic point size.
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Group {
            if let image = Self.menuBarImage {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "character.bubble")
            }
        }
        .accessibilityLabel("划词翻译：\(presentation.status.title)")
        .help("划词翻译：\(presentation.status.title)")
    }
}
