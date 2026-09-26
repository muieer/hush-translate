# HushTranslate Icons

[中文](README.md) · English

The app icon has a white rounded background and blue “中 / A” speech bubbles. The menu bar icon uses the approved second preview: two solid overlapping bubbles with cutout lettering, preserving the chosen letter size and proportions.

- `app-icon.png`: 1024 × 1024 with transparent outer padding; the build generates a full-size `.icns`.
- `menu-bar-master.png`: transparent original for the menu bar icon.
- `menu-bar-template.png`: 44 × 36 pixels for display at 22 × 18 Retina points. It matches `Sources/Translate/Resources/MenuBarTemplate.png`.
- `menu-bar-approved-preview.png`: the selected second menu bar design.
- `preview.png`: the approved design direction. The standalone PNG files are the actual resources.

The menu bar icon sets both `NSImage.size` and its view size to 22 × 18 points. The artwork is scaled proportionally, centered, and rendered as a template so macOS adapts it to light and dark appearances. Session status appears in the menu and hover help.

Run `swift scripts/make-menu-bar-icon.swift` from the project root to regenerate the two template files from the transparent master.

The master was generated with the built-in image generation tool. Its prompt required the exact second-preview bubble outlines, letter proportions, position, and tails; removal of the dark gray background; cutout letters and overlap; and a solid black template on transparency without shadow or texture.
