# HushTranslate User Guide

[中文](USER_GUIDE.md) · English

HushTranslate lives in the macOS menu bar and translates selected text, screenshots, and clipboard text. It requires macOS 15 or later. Apple Translation is the default provider; you can also configure an OpenAI-compatible service.

## Install and get started

Release builds are free, ad-hoc signed, and are not notarized with an Apple Developer ID.

1. Download `HushTranslate-x.x.x.zip` from [GitHub Releases](https://github.com/muieer/hush-translate/releases), unzip it, and move `HushTranslate.app` to `/Applications` if you prefer.
2. Open the app. If Gatekeeper blocks the first launch, go to System Settings → Privacy & Security, find the HushTranslate notice, and choose Open Anyway.
3. Grant Accessibility for selection translation and Screen Recording for screenshot translation when needed. HushTranslate appears in the menu bar without opening a main window.
4. Apple Translation needs no endpoint or API key. macOS may ask to download language resources. On macOS 26.4 or later, HushTranslate explicitly requests the low-latency strategy; older releases use the system default.

## App language and translation languages

Open **Settings → General → App Language** and choose **简体中文** or **English**. The app starts in Simplified Chinese, even when macOS uses another language. The choice is saved and updates the app interface. It does not change the text you translate or the selected translation languages.

In the same tab, use **From** and **To** to set translation languages. From can detect automatically; To requires a specific language. Changes are saved immediately and apply to the next request. A custom system prompt is preserved when you switch the app language. If you were using the built-in default prompt, the editor shows the default in your chosen app language.

## Translation providers

In **Settings → General → Translation Provider**, choose Apple Translation or a saved OpenAI-compatible service. All three input methods use the selected provider. Apple Translation is always available and cannot be deleted. It runs on your Mac. If the language pair is unsupported, change the source or target language, or choose another provider.

To use an LLM, choose **Add Service** and enter:

- **Service Name:** a label that helps identify this configuration. You can save multiple configurations for one provider or model.
- **Base URL:** an HTTP or HTTPS API base address, such as `http://localhost:1234/v1`. Leave off `/chat/completions`.
- **API Key:** the key supplied by your provider. For a local service, enter the value that service requires.
- **Model Name:** the model identifier expected by the API.

Choose **Save** to add or update a service. A new service becomes the current provider. **Discard Changes** restores the saved fields. Switching providers keeps unsaved drafts while Settings stays open; closing Settings discards them. Deleting the current service switches back to Apple Translation. When upgrading from an older version, the previous endpoint remains available as **Previous service**, while Apple Translation becomes the default.

## Translate text and screenshots

| Action | Default shortcut | How it works |
| --- | --- | --- |
| Start a translation session | `⌃⌥⌘D` | Start a session, then select text in another app and click **Translate** above the selection. Selecting alone does not translate or use a selection. By default, three clicks are available. Pressing the shortcut again starts a fresh session. |
| Translate a screenshot | `⌘⌥⇧S` | Drag to select a screen region. Press `Esc` to cancel. A session is not required. |
| Translate the clipboard | `⌃⌥⌘V` | Copy text first, then run the shortcut. A session is not required. |

The same actions are available from the menu bar. In **Settings → Sessions**, choose a continuous session, a selection limit, or a duration for the session shortcut. Set the default count and duration there. Limited sessions end automatically when their limit is reached. End a continuous session from the menu bar. A session count decreases only when you click Translate. You can change or clear shortcuts in **Settings → Shortcuts**.

## Screenshot OCR modes

With Apple Translation, screenshots use on-device Vision text recognition before translation. No image is sent to an LLM. If no text is found, HushTranslate shows an error.

With an OpenAI-compatible service, **Settings → Screenshots** offers:

- **On-device Vision:** recognize text on the Mac first.
- **Vision model:** let a model read and translate the image directly.
- **On-device first:** use Vision first, then ask the model to read the image if local recognition fails or finds nothing.

With any LLM OCR mode, the screenshot is included in the request to the configured service, including On-device Vision. The selected model must support images. Switching to Apple Translation keeps your LLM OCR choice for when you switch back.

## Permissions

- **Accessibility** allows selection translation to simulate `⌘C` in another app.
- **Screen Recording** allows screenshot translation to read the screen.

In **Settings → Shortcuts → Permissions**, choose **Open Settings** for the relevant macOS pane. After granting access, return to HushTranslate and choose **Check Again**. If selection translation still does not work, quit and reopen the app. Clipboard translation needs neither permission.

## Result window

The floating window shows the original text, translation, and elapsed time. You can select or copy either text, switch the provider or languages to translate the same input again without using a session selection, keep the window on top, and close it with its title-bar button or `Esc` once it has focus. Long content scrolls. HushTranslate does not currently store translation history.

## Advanced settings

**Settings → Advanced** contains the request timeout and custom system prompt for OpenAI-compatible services. They are shared by all LLM configurations and are disabled when Apple Translation is selected. The entire custom prompt is sent as the system message. `{sourceLanguage}`, `{targetLanguage}`, and `{input}` are replaced before sending; **Restore Default** resets the prompt. The tab also provides permission checks and a Finder shortcut to the app data folder.

## Troubleshooting

- **Nothing happens after selecting text:** start a session, grant Accessibility, and click Translate above the selection. Some browsers, Electron apps, and remote desktops may resist simulated copying; copy manually and translate the clipboard instead.
- **Screenshot capture does not start:** grant Screen Recording, try again, and restart HushTranslate if needed.
- **Apple Translation fails:** choose the source language manually or change the language pair. If a language download fails, check the network and retry. HushTranslate does not automatically fall back to an LLM.
- **An LLM cannot translate a screenshot:** confirm the model supports images, and check the Base URL, API key, model name, and connection.
- **An API request times out or fails:** check that the service is running, supports `/chat/completions`, and has a suitable timeout in Advanced settings.
- **You cannot find the app window:** use the HushTranslate icon in the menu bar. Choose **Quit HushTranslate** there to exit completely.
