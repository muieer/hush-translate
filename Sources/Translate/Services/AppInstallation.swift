import AppKit

/// 在常规服务启动前完成安装位置检查；不持久化用户的跳过选择。
enum AppInstallation {
    static func needsInstallation(at bundleURL: URL, applicationsDirectories: [URL]) -> Bool {
        guard bundleURL.pathExtension.lowercased() == "app" else { return false }
        let path = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        return !applicationsDirectories.contains { directory in
            let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
            return path.hasPrefix(root + "/")
        }
    }

    /// FileManager 拒绝覆盖已有目标；失败时保留错误交给启动流程展示。
    static func move(from source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    /// 返回 true 表示已经交接到新实例，当前实例正在退出。
    @MainActor
    static func promptAndMoveIfNeeded() async -> Bool {
        let source = Bundle.main.bundleURL
        let directories = FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        guard needsInstallation(at: source, applicationsDirectories: directories) else { return false }

        let destination = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent("HushTranslate.app", isDirectory: true)
        let alert = NSAlert()
        alert.messageText = L10n.tr("将 HushTranslate 移到“应用程序”？")
        alert.informativeText = L10n.tr("当前应用不在 Applications 目录中。移动后将从 /Applications 重新启动，并退出当前实例。")
        alert.addButton(withTitle: L10n.tr("移动并重新启动"))
        alert.addButton(withTitle: L10n.tr("暂不移动"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try move(from: source, to: destination)
        } catch {
            showError(L10n.tr("无法移动 HushTranslate"), detail: L10n.format("%@\n\n请检查“应用程序”目录的写入权限，以及是否已有同名应用。也可以退出后通过 Finder 手动移动。当前实例将继续运行。", error.localizedDescription))
            return false
        }

        do {
            let configuration = NSWorkspace.OpenConfiguration()
            // 即使 Launch Services 将移动前后的 bundle 视作同一个 App，也必须新建进程。
            configuration.createsNewApplicationInstance = true
            configuration.arguments = Array(CommandLine.arguments.dropFirst())
            let application = try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
            guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                throw NSError(domain: "HushTranslate.Installation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: L10n.tr("系统未能创建新的应用实例。")])
            }
            NSApp.terminate(nil)
            return true
        } catch {
            let launchError = error.localizedDescription
            do {
                try move(from: destination, to: source)
                showError(L10n.tr("无法重新启动 HushTranslate"), detail: L10n.format("%@\n\n应用已恢复到原位置，当前实例将继续运行。", launchError))
            } catch {
                showError(L10n.tr("无法重新启动 HushTranslate"), detail: L10n.format("%@\n\n应用位于 %@，恢复原位置失败：%@\n请退出当前实例后，从“应用程序”重新打开。", launchError, destination.path, error.localizedDescription))
            }
            return false
        }
    }

    @MainActor
    private static func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: L10n.tr("好"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
