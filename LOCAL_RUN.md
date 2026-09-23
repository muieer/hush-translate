# 本机开发环境

更新日期：2026-09-22。当前基线分支：`codex/local-development-baseline`。

## 标准构建与启动

```bash
./scripts/make-app.sh debug
open build/Translate.app --args --show-settings
```

应用常驻菜单栏。启动参数只在进程新启动时生效；已有 Translate 运行时应先退出旧进程。
发布配置构建使用 `./scripts/make-app.sh release`。本机和 GitHub Actions 共用该脚本。

## 工具链

- 本机：macOS 26.6.1，Apple Silicon，Xcode 27.0 (27A266a)。
- 必须先打开完整 Xcode，完成首次安装与许可步骤。
- 脚本尊重 `DEVELOPER_DIR`；未指定时使用系统选中的 Xcode。如果系统仍选中 Command Line Tools，则使用 `/Applications/Xcode.app/Contents/Developer`。
- 本次未修改系统全局 `xcode-select` 设置。也可显式运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/make-app.sh debug
```

## 依赖与资源

- 依赖正式来源：`https://github.com/sindresorhus/KeyboardShortcuts.git`。
- 版本固定为 `2.4.0`，正式提交为 `1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27`。
- `Package.swift` 固定版本，`Package.resolved` 固定正式提交，两者应一起纳入版本管理。
- 已移除项目级本地镜像；不再使用先前下载的源码归档、本地 Git 提交或 `#Preview` 补丁。
- 首次构建需要 GitHub 网络连接。脚本关闭共享依赖仓库缓存，依赖 checkout 存放在 `.build/xcode-packages`，构建数据在 `.build/xcode`。
- 使用完整 Xcode 的 `xcodebuild` 构建 Swift package；它生成的资源访问代码支持 `Contents/Resources`。
- 资源 bundle 使用 Xcode 标准结构，从内到外 ad-hoc 签名，并执行 `codesign --verify --deep --strict`。
- 已删除运行时修改应用目录的资源修复代码，应用根目录不再放软链接。
- 本地 ad-hoc 签名并不等于 Developer ID 签名或 Apple 公证；对外分发另行处理。

## 重建

关闭 Xcode 中正在构建的项目和旧应用后，删除项目 `.build/` 与 `build/` 即可清理编译产物，再执行标准构建命令。
不要删除受版本管理的 `Package.resolved`。若要升级依赖，应同时更新版本约束与锁文件并重新验证。

验证干净构建时，只需复制 `Package.swift`、`Package.resolved`、`Sources/`、`Info/`、`scripts/` 到独立目录，然后执行 `./scripts/make-app.sh release`；不复制 `.build/`、`.swiftpm/` 或旧应用。

## 已知源码告警

原项目仍有 `CGWindowListCreateImage` 弃用告警，以及 `SettingsStore.languages` 跨 actor 访问告警。当前 Swift 5 语言模式下不阻止构建；本次未扩大到功能或并发代码改造。

## 本次验证结果

- Debug 构建、打包、严格签名验证通过。
- 仅复制源码、锁文件和脚本到全新临时目录，禁用共享依赖仓库缓存后，Release 构建及严格签名验证通过。
- 已将该 Release 应用复制回 `build/Translate.app`，删除整个临时构建目录后启动，进程保持运行，主线程处于正常 AppKit 事件循环，未发现新的崩溃报告。
- 应用启动后再次执行严格签名验证通过，应用根目录无资源软链接。
- 桌面自动化读取设置窗口超时，因此本次未通过 UI 自动化复验设置标签和快捷键录制；翻译及交互验收沿用用户先前的验证，后续功能改动再按需验证。
- 旧 SwiftPM 构建目录、本地依赖镜像源码、预览补丁和本次临时诊断文件已清理。
