<p align="center">
  <img src="design/icons/app-icon.png" width="160" alt="HushTranslate 应用图标">
</p>
<h1 align="center">HushTranslate</h1>
<p align="center">一款只在需要时出现的 macOS 大模型翻译工具。</p>
<p align="center">中文 · <a href="README.en.md">English</a></p>

## 项目简述

HushTranslate 面向以自主阅读为主、偶尔需要翻译的用户，提供划词翻译和截图翻译。

选中文字不一定是为了翻译。一直开启的划词翻译容易频繁出现，打断阅读。HushTranslate 通过「翻译会话」控制何时响应划词：需要时，主动开启持续、按次数或按分钟的会话，随后划词会在选区上方显示「翻译」按钮，点击后才执行翻译，无须每次按快捷键。只有点击「翻译」才扣减会话次数。次数用完或时间到期后，会话自动关闭；关闭时，普通划词不会触发翻译。

例如，开启接下来 3 次划词翻译，处理完眼前的几处疑问后，继续安静阅读。持续会话则可以随时从菜单栏关闭。

![HushTranslate 操作演示](image/introduction.gif)

## 功能特征

- **划词翻译会话**：支持持续开启、开启 N 次、开启 N 分钟，次数与时长可配置。
- **截图翻译**：框选屏幕区域，默认使用本地 OCR 识别文字后翻译；也可使用支持图片输入的多模态模型。
- **云端与本地模型**：通过兼容 OpenAI Chat Completions API 的接口接入模型服务。
- **轻量结果面板**：在浮动窗口中查看译文，减少应用切换。
- **菜单栏与快捷键**：查看会话状态、开启或关闭会话，并自定义快捷键。
- **剪贴板翻译**：直接翻译已复制的文字。

## 安装与首次运行

HushTranslate 免费分发，适用于 Apple Silicon Mac，要求 macOS 15 或更高版本。发布版使用 ad-hoc 签名，未使用 Apple Developer ID 签名，也未经过 Apple 公证（Notarization）。

1. 从 [GitHub Releases](https://github.com/muieer/hush-translate/releases) 下载 `HushTranslate-x.x.x.zip`。
2. 解压 ZIP 文件。
3. 建议将 `HushTranslate.app` 移至 `/Applications`（应用程序）文件夹，也可放在其他位置。
4. 双击应用。首次运行时，macOS Gatekeeper 可能阻止打开；此时前往「系统设置 → 隐私与安全性」，找到 HushTranslate 的提示，点击「仍要打开」，并按系统提示确认。
5. 启动后，根据系统提示和所需功能授予「辅助功能」「屏幕录制」等权限。应用常驻菜单栏。
6. 在应用设置中自行配置模型服务的 API Key。API Key 由用户自行从服务商获取，API 使用费用由用户自己的服务商账号承担；本地模型按其服务要求配置。

具体配置见下方「首次使用」和 [使用说明](USER_GUIDE.md)。

## 从源码构建与使用

### 环境要求

- Apple Silicon Mac，macOS 15 或更高版本。
- 完整安装的 Xcode，并已完成首次启动时的组件安装。
- 首次构建时能够连接 GitHub，以获取依赖。

### 构建

在项目根目录执行：

```bash
./scripts/make-app.sh release
open build/HushTranslate.app --args --show-settings
```

脚本会生成 `build/HushTranslate.app`，第二条命令启动应用并打开设置。应用常驻菜单栏。

日常开发可使用 `./scripts/make-app.sh debug`，需要有效的 Apple Development 签名证书。更多开发说明见 [LOCAL_RUN.md](LOCAL_RUN.md)。

### 首次使用

1. 在「设置 → 通用」中填写模型服务的 `Base URL`、`API Key` 和 `Model`，选择目标语言。`Base URL` 应为服务的 API 基础地址，例如 `http://localhost:1234/v1`，不要包含 `/chat/completions`；使用本地模型前，先启动对应的模型服务。
2. 在「设置 → 快捷键」中按需授权：划词翻译需要「辅助功能」权限，截图翻译需要「屏幕录制」权限。
3. 从菜单栏选择「开启 3 次」，然后在其他应用中选中文字，点击选区上方的「翻译」按钮开始翻译。也可在「设置 → 翻译会话」中修改默认模式、次数和时长，再用快捷键启动会话。

截图翻译可直接从菜单栏启动，无须开启划词翻译会话。
