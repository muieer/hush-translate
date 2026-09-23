#!/usr/bin/env bash
# 使用完整 Xcode 构建 Swift package，并打包可独立运行的 macOS 应用。
# 用法：./scripts/make-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-release}"
case "$MODE" in
    debug) CONFIGURATION=Debug ;;
    release) CONFIGURATION=Release ;;
    *) echo "用法: $0 [debug|release]" >&2; exit 1 ;;
esac

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

APP_NAME=Translate
DERIVED_DATA="$PWD/.build/xcode"
PRODUCTS="$DERIVED_DATA/Build/Products/$CONFIGURATION"
APP_BUNDLE="$PWD/build/$APP_NAME.app"
LOCK_BEFORE=$(shasum -a 256 Package.resolved)

echo "==> Xcode: $DEVELOPER_DIR"
echo "==> 构建 ${CONFIGURATION}（使用锁定依赖）"
# Xcode 生成的资源 accessor 会查 Contents/Resources；swift build 的产物不可替代。
xcodebuild -quiet -scheme Translate -configuration "$CONFIGURATION" \
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
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Xcode 的资源 bundle 使用标准 Contents 结构，可从内到外签名。
for resource in "$PRODUCTS/"*.bundle; do
    [[ -d "$resource" ]] || continue
    destination="$APP_BUNDLE/Contents/Resources/$(basename "$resource")"
    ditto "$resource" "$destination"
    codesign --force --sign - "$destination"
done
codesign --force --sign - "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "完成: $APP_BUNDLE"
echo "启动: open build/Translate.app --args --show-settings"
