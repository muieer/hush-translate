# HushTranslate 图标

应用图标为白色圆角底板、蓝色「中 / A」对话框；菜单栏采用已确认的第二版预览，使用实心双气泡与镂空文字，保留该版「中 / A」的大小比例。

- `app-icon.png`：1024 × 1024，透明外边距；构建时生成完整尺寸的 `.icns`。
- `menu-bar-master.png`：菜单栏透明图标原稿。
- `menu-bar-template.png`：44 × 36，供 22 × 18 pt Retina 显示使用；与 `Sources/Translate/Resources/MenuBarTemplate.png` 保持一致。
- `menu-bar-approved-preview.png`：用户选定的第二版菜单栏设计预览。
- `preview.png`：已确认的设计方向图；实际资源以独立 PNG 为准。

菜单栏图标同时设置 `NSImage.size` 和视图尺寸为 22 × 18 pt，原稿等比缩放、居中放置，使用 template 渲染，由系统适配深浅色。会话状态通过菜单正文和悬停提示显示。

在项目根目录运行 `swift scripts/make-menu-bar-icon.swift`，可从透明原稿重新生成两处模板资源。

原稿使用内置 imagegen 工具生成。提示词要求：严格保留第二版双气泡轮廓、文字比例、位置及尾部；移除深灰背景，将文字和交叠间隙镂空；输出透明底黑色实心模板，不添加阴影或纹理。
