#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source_png="$project_dir/Assets/AppIcon.png"
tiff_dir="$project_dir/.build/AppIcon.tiffs"
combined_tiff="$project_dir/.build/AppIcon.tiff"

mkdir -p "$project_dir/Assets" "$project_dir/Resources" "$tiff_dir"
mkdir -p "$project_dir/.build/clang-module-cache"
icon_sdk="$(xcrun --sdk macosx --show-sdk-path)"
if test "$(xcode-select -p)" = /Library/Developer/CommandLineTools \
    && test -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; then
    icon_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi
CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-module-cache" \
    swift \
    -sdk "$icon_sdk" \
    "$project_dir/scripts/generate-icon.swift" \
    "$source_png"

make_tiff() {
    size="$1"
    sips \
        -z "$size" "$size" \
        -s format tiff \
        "$source_png" \
        --out "$tiff_dir/icon-$size.tiff" \
        >/dev/null
}

make_tiff 16
make_tiff 32
make_tiff 48
make_tiff 128
make_tiff 256
make_tiff 512
make_tiff 1024

tiffutil -catnosizecheck \
    "$tiff_dir/icon-16.tiff" \
    "$tiff_dir/icon-32.tiff" \
    "$tiff_dir/icon-48.tiff" \
    "$tiff_dir/icon-128.tiff" \
    "$tiff_dir/icon-256.tiff" \
    "$tiff_dir/icon-512.tiff" \
    "$tiff_dir/icon-1024.tiff" \
    -out "$combined_tiff"
tiff2icns "$combined_tiff" "$project_dir/Resources/AppIcon.icns"
echo "Built $project_dir/Resources/AppIcon.icns"
