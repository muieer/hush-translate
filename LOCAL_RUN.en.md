# Local Development and Releases

[中文](LOCAL_RUN.md) · English

## Build and launch

Use a full Xcode installation on an Apple Silicon Mac. The minimum macOS version is 15.0; keep `Package.swift` and `Info/Info.plist` aligned.

```bash
./scripts/make-app.sh debug
open build/HushTranslate.app --args --show-settings
```

HushTranslate remains in the menu bar. `--show-settings` only works when starting a new process; quit an existing instance from the menu bar first. Use `./scripts/make-app.sh release` for a release build. Local builds and GitHub Actions use the same script. CI uses a `macos-26` runner with an Xcode version that can compile the current Apple Translation API. The script honors `DEVELOPER_DIR`; if Command Line Tools are selected, it uses `/Applications/Xcode.app/Contents/Developer` when available.

## Dependencies and signing

- `KeyboardShortcuts` is pinned to 2.4.0. Update `Package.swift` and `Package.resolved` together. The first build needs GitHub access. Dependency checkouts live under `.build/xcode-packages`; build data lives under `.build/xcode`.
- Debug builds need a valid `Apple Development` signing certificate. Check with `security find-identity -v -p codesigning`. If several certificates exist, set `HUSHTRANSLATE_SIGNING_IDENTITY` to the desired name or SHA-1. A stable development signature avoids repeated Accessibility and Screen Recording authorization after rebuilds.
- Release builds use ad-hoc signing. The script assembles resources, signs from the inside out, and runs `codesign --verify --deep --strict`.

## Versions and releases

- Maintain `CFBundleShortVersionString` in `Info/Info.plist`. Local builds use its `CFBundleVersion`; GitHub Actions applies `HUSHTRANSLATE_BUILD_NUMBER` only to the built app.
- Commit the version and complete release notes in both [CHANGELOG.md](CHANGELOG.md) and [CHANGELOG.en.md](CHANGELOG.en.md), then create and push the `vMAJOR.MINOR.PATCH` tag on that commit. `.github/workflows/release.yml` checks that the tag matches the version, calls `.github/workflows/build.yml` for the ZIP, and uses the matching Chinese changelog section for the GitHub Release body.
- Release builds target Apple Silicon and macOS 15 or later. Installation steps are in the [README](README.en.md) and [user guide](USER_GUIDE.en.md).

## Automated verification

This compiles the app and runs unit tests without opening the GUI:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme HushTranslate -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/xcode \
  -clonedSourcePackagesDirPath .build/xcode-packages \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -disablePackageRepositoryCache -scmProvider system \
  test CODE_SIGNING_ALLOWED=NO
```

`TranslationSessionTests` cover session transitions and `SelectionTranslationTests` cover selection gestures and session interaction. Separate tests cover provider switching, Apple Translation, and screenshot routing. The user verifies behavior that requires real mouse interaction, system permissions, or a live model service after the build.
