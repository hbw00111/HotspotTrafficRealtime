#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
app_dir="$project_dir/outputs/HotspotTraffic.app"
contents_dir="$app_dir/Contents"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
if test "$(xcode-select -p)" = /Library/Developer/CommandLineTools \
    && test -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; then
    sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi

mkdir -p \
    "$project_dir/.build/clang-module-cache" \
    "$project_dir/.build/swiftpm-cache"

SDKROOT="$sdk_path" \
CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/swiftpm-cache" \
swift build \
    --disable-sandbox \
    --package-path "$project_dir" \
    --sdk "$sdk_path" \
    -c release \
    -Xswiftc -gnone

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
install -m 755 \
    "$project_dir/.build/release/HotspotTrafficApp" \
    "$contents_dir/MacOS/HotspotTrafficApp"
install -m 644 \
    "$project_dir/Resources/Info.plist" \
    "$contents_dir/Info.plist"
install -m 644 \
    "$project_dir/Resources/AppIcon.icns" \
    "$contents_dir/Resources/AppIcon.icns"

xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"

echo "Built $app_dir"
