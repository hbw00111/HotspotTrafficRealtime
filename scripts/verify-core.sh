#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
if test "$(xcode-select -p)" = /Library/Developer/CommandLineTools \
    && test -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; then
    sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi

verify_dir="$(mktemp -d /private/tmp/hotspot-verify.XXXXXX)"
trap 'rm -rf "$verify_dir"' EXIT HUP INT TERM
mkdir -p "$project_dir/.build/clang-module-cache"

SDKROOT="$sdk_path" \
CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-module-cache" \
swiftc \
    -sdk "$sdk_path" \
    -parse-as-library \
    "$project_dir/Sources/HotspotTrafficApp/Models.swift" \
    "$project_dir/Sources/HotspotTrafficApp/NettopParser.swift" \
    "$project_dir/Sources/HotspotTrafficApp/TrafficHistoryBuffer.swift" \
    "$project_dir/Sources/HotspotTrafficApp/TrafficStore.swift" \
    "$project_dir/scripts/verify-core.swift" \
    -lsqlite3 \
    -o "$verify_dir/verify-core"

"$verify_dir/verify-core"
