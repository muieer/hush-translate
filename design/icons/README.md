# HushTranslate 图标

使用已确认的蓝白双语对话框设计：应用图标为白色圆角底板、蓝色「中 / A」对话框；菜单栏使用对应的单色开放轮廓。

- `app-icon.png`：1024 × 1024，透明外边距；构建时生成完整尺寸的 `.icns`。
- `menu-bar-master.png`：菜单栏透明图标原稿。
- `menu-bar-template.png`：36 × 36，供 18 × 18 pt Retina 显示使用；与 `Sources/Translate/Resources/MenuBarTemplate.png` 保持一致。
- `preview.png`：已确认的设计方向图；实际资源以独立 PNG 为准。

菜单栏图标同时设置 `NSImage.size` 和视图尺寸为 18 × 18 pt，使用 template 渲染，由系统适配深浅色。会话状态通过菜单正文和悬停提示显示。
