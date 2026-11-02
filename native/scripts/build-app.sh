#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="$PROJECT_ROOT/work/native-build"
CACHE_ROOT="$PROJECT_ROOT/work/swift-cache"
APP_PATH="$PROJECT_ROOT/output/Space.app"
mkdir -p "$CACHE_ROOT/modules" "$CACHE_ROOT/config" "$CACHE_ROOT/security"
export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/modules"
swift build --package-path "$PROJECT_ROOT/native" --scratch-path "$BUILD_ROOT" \
  --cache-path "$CACHE_ROOT" --config-path "$CACHE_ROOT/config" --security-path "$CACHE_ROOT/security" \
  --disable-sandbox -c release
if [[ ! -f "$PROJECT_ROOT/native/Resources/Space.icns" || "$PROJECT_ROOT/native/scripts/make-icon.swift" -nt "$PROJECT_ROOT/native/Resources/Space.icns" ]]; then
  swift -module-cache-path "$CACHE_ROOT/modules" "$PROJECT_ROOT/native/scripts/make-icon.swift" "$PROJECT_ROOT/work/Space.iconset" "$PROJECT_ROOT/native/Resources/Space.icns"
fi
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_ROOT/release/Space" "$APP_PATH/Contents/MacOS/Space"
cp "$PROJECT_ROOT/native/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
if [[ -f "$PROJECT_ROOT/native/Resources/Space.icns" ]]; then
  cp "$PROJECT_ROOT/native/Resources/Space.icns" "$APP_PATH/Contents/Resources/Space.icns"
fi
mkdir -p "$APP_PATH/Contents/Resources/zh-Hans.lproj"
printf 'CFBundleDisplayName = "Space";\nCFBundleName = "Space";\n' > "$APP_PATH/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
print "Built: $APP_PATH"
