import AppKit

/// 在常规服务启动前检查安装位置；未安装时引导用户拖拽安装并退出。
enum AppInstallation {
    static func needsInstallation(at bundleURL: URL, applicationsDirectories: [URL]) -> Bool {
        guard bundleURL.pathExtension.lowercased() == "app" else { return false }
        let path = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        return !applicationsDirectories.contains { directory in
            let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
            return path.hasPrefix(root + "/")
        }
    }

    /// Returns true when installation is required; callers must not start app services.
    @MainActor
    static func promptForInstallationIfNeeded() -> Bool {
        let source = Bundle.main.bundleURL
        let directories = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        guard needsInstallation(at: source, applicationsDirectories: directories) else { return false }

        let alert = NSAlert()
        alert.messageText = L10n.tr("请先将 HushTranslate 拖入“应用程序”")
        alert.informativeText = L10n.tr("请将 HushTranslate 拖到“应用程序”文件夹，再从该文件夹打开。点击下方按钮将打开“应用程序”文件夹，并退出 HushTranslate。")
        alert.addButton(withTitle: L10n.tr("打开“应用程序”并退出"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        NSApp.terminate(nil)
        return true
    }
}
