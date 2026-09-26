# 本机开发与发布

## 构建与启动

在 Apple Silicon Mac 上使用完整 Xcode。应用最低部署目标为 macOS 15.0，`Package.swift` 与 `Info/Info.plist` 需保持一致。

```bash
./scripts/make-app.sh debug
open build/HushTranslate.app --args --show-settings
```

应用常驻菜单栏。`--show-settings` 仅在新进程启动时生效；已有实例运行时，先从菜单栏退出。发布配置使用 `./scripts/make-app.sh release`，本机和 GitHub Actions 共用同一脚本。CI 使用 `macos-26` runner，以取得编译当前 Apple Translation API 所需的 Xcode。脚本尊重 `DEVELOPER_DIR`；系统选中 Command Line Tools 时，会使用 `/Applications/Xcode.app/Contents/Developer` 中的完整 Xcode。

## 依赖与签名

- `KeyboardShortcuts` 固定为 2.4.0；`Package.swift` 与 `Package.resolved` 应一同更新。首次构建需要访问 GitHub，脚本使用 `.build/xcode-packages` 中的依赖检出和 `.build/xcode` 中的构建数据。
- Debug 构建需要有效的 `Apple Development` 签名证书；可用 `security find-identity -v -p codesigning` 检查。若有多张证书，可通过 `HUSHTRANSLATE_SIGNING_IDENTITY` 指定证书名称或 SHA-1。稳定的开发签名有助于避免重建后反复授权辅助功能和屏幕录制。
- Release 构建使用 ad-hoc 签名。脚本组装资源后从内到外签名，并执行 `codesign --verify --deep --strict`。

## 版本与发布

- 在 `Info/Info.plist` 中维护 `CFBundleShortVersionString`。本地构建沿用其中的 `CFBundleVersion`；GitHub Actions 使用 `HUSHTRANSLATE_BUILD_NUMBER` 仅修改构建产物的构建号。
- 先提交版本号和 `CHANGELOG.md` 中该版本的完整记录，再在同一提交上创建并推送 `vMAJOR.MINOR.PATCH` 标签。`.github/workflows/release.yml` 检查标签与版本号一致，随后调用 `.github/workflows/build.yml` 构建 ZIP，并提取 `CHANGELOG.md` 对应版本的条目作为 GitHub Release 正文。
- 发布版为 Apple Silicon 构建，要求 macOS 15.0 或更高版本。用户安装与首次运行步骤见 [README.md](README.md) 和 [USER_GUIDE.md](USER_GUIDE.md)。

## 自动化验证

以下命令编译并运行单元测试，不启动应用或执行 GUI 操作：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme HushTranslate -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/xcode \
  -clonedSourcePackagesDirPath .build/xcode-packages \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -disablePackageRepositoryCache -scmProvider system \
  test CODE_SIGNING_ALLOWED=NO
```

`TranslationSessionTests` 验证会话状态转换，`SelectionTranslationTests` 验证划词候选手势与会话连接。翻译来源、Apple 翻译及截图路由由各自测试覆盖。需要实际鼠标操作、系统授权或真实模型服务的行为，应在构建后由用户手动验收。
