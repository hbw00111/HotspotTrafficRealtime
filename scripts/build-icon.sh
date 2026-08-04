#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source_png="$project_dir/Assets/AppIcon.png"
tiff_dir="$project_dir/.build/AppIcon.tiffs"
combined_tiff="$project_dir/.build/AppIcon.tiff"

mkdir -p "$project_dir/Resources" "$tiff_dir"
test -f "$source_png"

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
