#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version="${1:-1.0.0}"
architecture="$(uname -m)"
source_app="$project_dir/outputs/HotspotTraffic.app"
release_root="$(mktemp -d /private/tmp/hotspot-release.XXXXXX)"
release_app="$release_root/HotspotTraffic.app"
archive="$project_dir/outputs/HotspotTraffic-v$version-macOS-$architecture.zip"

test -d "$source_app"
cp -R "$source_app" "$release_app"
xattr -cr "$release_app"
codesign --force --deep --sign - "$release_app"
codesign --verify --deep --strict --verbose=2 "$release_app"
ditto -c -k --keepParent --norsrc "$release_app" "$archive"

echo "Packaged $archive"
