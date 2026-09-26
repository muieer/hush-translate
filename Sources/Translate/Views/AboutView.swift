import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject private var settings = AppCoordinator.shared.settings
    private let projectURL = URL(string: "https://github.com/muieer/hush-translate")!

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let version else { return L10n.tr("开发版本") }
        if let build { return L10n.format("版本：%@（%@）", version, build) }
        return L10n.format("版本：%@", version)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("HushTranslate")
                .font(.system(size: 24, weight: .bold))

            Text(versionDescription)
                .font(.system(size: 14))
                .textSelection(.enabled)

            Text(L10n.tr("一款只在需要时出现的 macOS 大模型翻译工具。"))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("GitHub：")
                Link("github.com/muieer/hush-translate", destination: projectURL)
            }
            .font(.system(size: 13))
        }
        .padding(32)
        .frame(width: 480, height: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
