#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
app_dir="$project_dir/outputs/HotspotTraffic.app"
staging_root="$project_dir/.build/app-staging"
staging_app="$staging_root/HotspotTraffic.app"
contents_dir="$staging_app/Contents"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
if test "$(xcode-select -p)" = /Library/Developer/CommandLineTools \
    && test -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; then
    sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi

mkdir -p \
    "$project_dir/.build/clang-module-cache" \
    "$project_dir/.build/swiftpm-cache" \
    "$project_dir/.build/swiftpm-config" \
    "$project_dir/.build/swiftpm-security"

SDKROOT="$sdk_path" \
CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/swiftpm-cache" \
swift build \
    --disable-sandbox \
    --package-path "$project_dir" \
    --cache-path "$project_dir/.build/swiftpm-cache" \
    --config-path "$project_dir/.build/swiftpm-config" \
    --security-path "$project_dir/.build/swiftpm-security" \
    --sdk "$sdk_path" \
    -c release \
    -Xswiftc -gnone

rm -rf "$staging_root"
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

xattr -cr "$staging_app"
codesign --force --deep --sign - "$staging_app"
mkdir -p "$project_dir/outputs"
rm -rf "$app_dir"
mv "$staging_app" "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"

echo "Built $app_dir"
