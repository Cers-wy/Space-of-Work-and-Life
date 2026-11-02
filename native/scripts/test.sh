#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_ROOT="$PROJECT_ROOT/work/swift-cache"
mkdir -p "$CACHE_ROOT/modules" "$CACHE_ROOT/config" "$CACHE_ROOT/security"
export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/modules"
swift test --package-path "$PROJECT_ROOT/native" --scratch-path "$PROJECT_ROOT/work/native-build" \
  --cache-path "$CACHE_ROOT" --config-path "$CACHE_ROOT/config" --security-path "$CACHE_ROOT/security" \
  --disable-sandbox
