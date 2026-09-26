#!/usr/bin/env bash
# 使用完整 Xcode 构建 Swift package，并打包可独立运行的 macOS 应用。
# 用法：./scripts/make-app.sh [debug|release]
#
# Debug 构建必须使用稳定的 Apple Development 签名，避免每次重建后
# macOS TCC（辅助功能 / 屏幕录制）把应用视为新的代码身份。
# 如需显式指定签名身份：
#   HUSHTRANSLATE_SIGNING_IDENTITY="<identity name or SHA-1>" ./scripts/make-app.sh debug
# CI 通过 HUSHTRANSLATE_BUILD_NUMBER 覆盖产物构建号，不修改源 Info.plist。
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-release}"
case "$MODE" in
    debug) CONFIGURATION=Debug ;;
    release) CONFIGURATION=Release ;;
    *) echo "用法: $0 [debug|release]" >&2; exit 1 ;;
esac

BUILD_NUMBER="${HUSHTRANSLATE_BUILD_NUMBER:-}"
if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "HUSHTRANSLATE_BUILD_NUMBER 必须为正整数。" >&2
    exit 1
fi

# 尊重显式指定的工具链；系统仍选择 CLT 时使用标准位置的完整 Xcode。
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    DEVELOPER_DIR=$(xcode-select -p)
    if [[ "$DEVELOPER_DIR" == /Library/Developer/CommandLineTools && -d /Applications/Xcode.app/Contents/Developer ]]; then
        DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
    export DEVELOPER_DIR
fi
if ! xcodebuild -version >/dev/null 2>&1; then
    echo "需要完整 Xcode。请首次打开 Xcode 完成组件安装，或设置 DEVELOPER_DIR。" >&2
    exit 1
fi
if [[ ! -f Package.resolved ]]; then
    echo "缺少 Package.resolved；请先恢复版本库中的依赖锁文件。" >&2
    exit 1
fi
if [[ -f .swiftpm/configuration/mirrors.json ]]; then
    echo "请先移除项目级依赖镜像配置，使用 Package.resolved 中的正式来源。" >&2
    exit 1
fi

# Debug 使用稳定的 Apple Development 代码身份。
# Release 使用免费的 ad-hoc 签名，通过 GitHub Releases 分发，不做 Apple 公证。
if [[ "$MODE" == "debug" ]]; then
    REQUESTED_IDENTITY="${HUSHTRANSLATE_SIGNING_IDENTITY:-}"
    SIGNING_IDENTITY=$(
        security find-identity -v -p codesigning 2>/dev/null |
            awk -v requested="$REQUESTED_IDENTITY" '
                /"Apple Development:/ {
                    name = $0
                    sub(/^[^"]*"/, "", name)
                    sub(/".*$/, "", name)
                    if (requested == "" || requested == $2 || requested == name) {
                        print $2
                        exit
                    }
                }'
    )
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        cat >&2 <<'EOF'
Debug 构建需要有效的 Apple Development 签名证书，且显式指定的身份必须与其名称或 SHA-1 匹配。

请先在 Xcode → Settings → Accounts 登录 Apple ID，并确保钥匙串中存在 Apple Development 证书。
可用以下命令检查：
  security find-identity -v -p codesigning

如果存在多个开发证书，可显式指定：
  HUSHTRANSLATE_SIGNING_IDENTITY="<identity name or SHA-1>" ./scripts/make-app.sh debug
EOF
        exit 1
    fi
    SIGNING_DESCRIPTION="Apple Development"
else
    SIGNING_IDENTITY="-"
    SIGNING_DESCRIPTION="ad-hoc"
fi

APP_NAME=HushTranslate
DERIVED_DATA="$PWD/.build/xcode"
PRODUCTS="$DERIVED_DATA/Build/Products/$CONFIGURATION"
APP_BUNDLE="$PWD/build/$APP_NAME.app"
LOCK_BEFORE=$(shasum -a 256 Package.resolved)

echo "==> Xcode: $DEVELOPER_DIR"
echo "==> 构建 ${CONFIGURATION}（使用锁定依赖）"
echo "==> 签名: $SIGNING_DESCRIPTION"
# Xcode 生成的资源 accessor 会查 Contents/Resources；swift build 的产物不可替代。
# 先无签名编译，组装完整 .app 后统一从内到外签名。
xcodebuild -quiet -scheme HushTranslate -configuration "$CONFIGURATION" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$DERIVED_DATA" \
    -clonedSourcePackagesDirPath "$PWD/.build/xcode-packages" \
    -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
    -disablePackageRepositoryCache \
    -scmProvider system build CODE_SIGNING_ALLOWED=NO

if [[ "$LOCK_BEFORE" != "$(shasum -a 256 Package.resolved)" ]]; then
    echo "构建期间 Package.resolved 被修改，请检查依赖状态后重试。" >&2
    exit 1
fi
[[ -f "$PRODUCTS/$APP_NAME" ]] || { echo "未找到应用可执行文件" >&2; exit 1; }
[[ -d "$PRODUCTS/KeyboardShortcuts_KeyboardShortcuts.bundle" ]] || { echo "缺少快捷键资源包" >&2; exit 1; }

# 先完成编译，再替换旧产物。只清理本脚本生成的 .app。
echo "==> 组装 .app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$PRODUCTS/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info/Info.plist "$APP_BUNDLE/Contents/Info.plist"
for localization in Info/*.lproj; do
    [[ -d "$localization" ]] || continue
    ditto "$localization" "$APP_BUNDLE/Contents/Resources/$(basename "$localization")"
done
if [[ -n "$BUILD_NUMBER" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
fi
echo "==> Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
echo "==> Build: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 从已确认的 1024px 图稿生成 macOS 所需的多尺寸 .icns。
ICON_SOURCE="$PWD/design/icons/app-icon.png"
ICON_WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hushtranslate-icon.XXXXXX")
ICONSET_DIR="$ICON_WORK_DIR/HushTranslate.iconset"
mkdir -p "$ICONSET_DIR"
trap 'rm -rf "$ICON_WORK_DIR"' EXIT
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$ICON_SOURCE" \
        --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -s format png -z "$retina_size" "$retina_size" "$ICON_SOURCE" \
        --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"

sign_path() {
    local path="$1"
    if [[ "$SIGNING_IDENTITY" == "-" ]]; then
        codesign --force --sign - "$path"
    else
        # 本地开发签名不需要可信时间戳，避免构建依赖时间戳服务网络状态。
        codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$path"
    fi
}

# Xcode 的资源 bundle 使用标准 Contents 结构，可从内到外签名。
for resource in "$PRODUCTS/"*.bundle; do
    [[ -d "$resource" ]] || continue
    destination="$APP_BUNDLE/Contents/Resources/$(basename "$resource")"
    ditto "$resource" "$destination"
    sign_path "$destination"
done
sign_path "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
sign_path "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$MODE" == "debug" ]]; then
    echo "==> Debug 代码身份"
    codesign -d --verbose=2 "$APP_BUNDLE" 2>&1 |
        grep -E '^(Identifier|Authority|TeamIdentifier)=' || true
fi

echo "完成: $APP_BUNDLE"
echo "启动: open build/HushTranslate.app --args --show-settings"
