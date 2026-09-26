# Development and Verification

[中文](AGENTS.md) · English

## macOS app testing boundary

Codex may compile, build, run automated tests, and perform command-line verification.

After building, Codex may launch the macOS app. The user handles interaction and manual acceptance testing after launch. Unless the user explicitly asks otherwise, do not use Computer Use or other GUI automation to operate or test the app.

For features that require interaction to verify, describe the manual steps and expected results for the user.
