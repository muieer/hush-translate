import AppKit
import SwiftUI

@main
struct HushTranslateApp: App {
    @NSApplicationDelegateAdaptor(HushTranslateAppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            StatusBarMenu(coordinator: coordinator)
        } label: {
            SessionStatusLabel(presentation: coordinator.sessionPresentation)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandMenu("窗口") {
                Button("显示翻译窗口") { coordinator.showLastResult() }
                Button("关闭窗口") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: .command)
                Button("最小化") { NSApp.keyWindow?.miniaturize(nil) }
                    .keyboardShortcut("m", modifiers: .command)
            }
        }
    }
}

@MainActor
final class HushTranslateAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            if await AppInstallation.promptAndMoveIfNeeded() { return }
            AppCoordinator.shared.bootstrap()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 再次启动只保持菜单栏常驻，不恢复或抬起任何窗口。
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
