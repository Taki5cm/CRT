#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

mkdir -p "$ROOT/.build/ModuleCache" "$ROOT/.swiftpm" "$ROOT/build"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/ModuleCache"
export SWIFTPM_CONFIG_PATH="$ROOT/.swiftpm"

VERSION="0.11"
APP="$ROOT/build/CRT.app"
DERIVED="$ROOT/.build/XcodeDerivedData"

xcodebuild \
  -project "$ROOT/CRT.xcodeproj" \
  -scheme CRT \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache" \
  clean \
  build

rm -rf "$APP"
ditto "$DERIVED/Build/Products/Release/CRT.app" "$APP"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

rm -f "$ROOT/build/CRT-$VERSION.zip"
ditto --norsrc --noextattr -c -k --keepParent "$APP" "$ROOT/build/CRT-$VERSION.zip"
xattr -cr "$APP"

echo "Built: $APP"
echo "Zip:   $ROOT/build/CRT-$VERSION.zip"
