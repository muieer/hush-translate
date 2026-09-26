# Changelog

[中文](CHANGELOG.md) · English

## Unreleased

- Added a Simplified Chinese and English interface switch under Settings → General → App Language. Simplified Chinese remains the default, independent of translation languages.
- Added English versions of the user, development, changelog, and other project documents.

## 2.0.0 (since 1.1.0)

### Requirements and defaults

- macOS 15.0 or later is required; macOS 14 is no longer supported.
- Apple Translation is the default provider and needs no endpoint or API key. An older endpoint configuration is retained as **Previous service** when upgrading.

### Translation providers

- Added Apple Translation with automatic source-language detection, on-demand system language downloads, and errors for unsupported language pairs. On macOS 26.4 or later, the app explicitly requests a low-latency strategy; older systems use the default strategy.
- Added saved, editable, and removable cloud or local OpenAI-compatible services. A service is saved as one complete configuration. Unsaved drafts remain while Settings is open and are discarded when it closes.
- Selected text, clipboard text, and screenshots use the current provider. Apple screenshot translation uses local Vision OCR. With an LLM, the screenshot is still sent to the chosen service, so the model must accept images.
- The result window can switch provider, source language, or target language and translate the same input again without a new selection or another session count. Choices are saved.

### Selection and settings

- Selecting text now shows a Translate confirmation button. Only clicking it copies the selection and starts translation. Ignored selections do not change the clipboard or consume the session count.
- Adjusted Settings form layout and field hints.
