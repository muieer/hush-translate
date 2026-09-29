# Changelog

[中文](CHANGELOG.md) · English

## Unreleased

## 2.2.2 (since 2.2.1)

- Updated startup installation guidance: launching outside the system or user Applications folder now prompts users to drag the app into Applications and reopen it, and prevents normal services from starting. This avoids read-aloud failures caused by moving the app while it is running.
- The installation prompt now offers only “Open Applications and Quit”; removed automatic relocation, relaunch, and skip-installation logic.
- Updated the Chinese and English installation prompts and user guides.

## 2.2.1 (since 2.2.0)

- Switching translation providers in the result window now keeps the previous LLM request running in the background. Switching back with the same input, languages, and configuration reuses the in-flight request or completed result to reduce duplicate requests.
- Each LLM provider manages its own request. A new request for the same provider replaces the previous one, while background status, results, and errors do not overwrite the currently displayed provider. Deleting a provider cancels its request and clears its cache.
- Switching providers for the same screenshot in the result window can reuse requests and results. Taking a new screenshot or changing translation languages starts processing again; screenshot results stay out of the plain-text cache.
- Refined the project introduction in the Chinese and English README files.

## 2.2.0 (since 2.1.3)

- Added read-aloud buttons for the original and translated text using native macOS speech synthesis, with pause and resume controls. Starting another passage stops the current one.
- Selects system voices using the source language for the original text and the target language for the translation. Automatic source-language detection uses the system language recognizer, with voice-language mappings for Simplified and Traditional Chinese.
- Stops speech when a new translation starts, the result changes, or the result window closes. Refreshing the same result preserves playback state.
- Read-aloud buttons follow the existing result panel style, with play and pause symbols, Chinese and English labels, and accessibility labels.

## 2.1.3 (since 2.1.2)

- Fixed translation results being obscured when shown automatically. The result window temporarily stays above normal windows without taking input focus from the current app.
- Clicking the result, clicking another window, or switching apps restores normal window behavior. Clicking another normal window places the result just below that window instead of behind all normal windows. Explicit pinning remains in effect.

## 2.1.2 (since 2.1.1)

- Each translation provider now keeps its most recent successful plain-text translation in memory. Text selection and clipboard translation can reuse the same result to reduce duplicate requests. Changes to the input, languages, or relevant service configuration trigger a new translation; quitting the app clears the cache.
- Screenshot translation neither uses nor replaces the plain-text cache. Failed, cancelled, or stale requests do not replace cached results, and deleting a service clears its cache.
- Updated the Chinese and English app descriptions in About to cover both Apple Translation and LLM translation.

## 2.1.1 (since 2.1.0)

- Fixed session and screenshot settings that did not update when switching the interface language.
- Stopped checking permissions automatically when Settings opens, avoiding a Screen Recording prompt caused by that check. Missing permissions are still reported when screenshot translation or a text selection session is first used; permissions can also be checked manually in Settings.

## 2.1.0 (since 2.0.0)

- Added a Simplified Chinese and English interface switch under Settings → General → App Language. Simplified Chinese remains the default, independent of translation languages.
- Added English versions of the user guide, development guide, changelog, and other project documents, and moved the documentation into the `document` directory.

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
