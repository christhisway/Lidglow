#!/bin/zsh
# Builds, signs, and verifies Lidglow.app. Usage: Scripts/build.sh [destination]
# A relative destination is resolved against the repository root. Default: build/Lidglow.app
set -eu
cd -- "${0:A:h}/.."
destination="${1:-build/Lidglow.app}"
if [[ "$destination" != /* ]]; then destination="$PWD/$destination"; fi
src="Sources/Lidglow"
cache="$(mktemp -d)"
module_cache="${LIDGLOW_MODULE_CACHE:-$cache}"
mkdir -p "$module_cache"
trap 'rm -rf -- "$cache"' EXIT
mkdir -p "$destination/Contents/MacOS"
cp "$src/Resources/Info.plist" "$destination/Contents/Info.plist"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
target="$(uname -m)-apple-macos14.2"
xcrun clang -target "$target" -isysroot "$sdk" -fobjc-arc -O2 \
    -c "$src/Hardware/LogoBridge.m" -o "$cache/LogoBridge.o"
xcrun swiftc -target "$target" -sdk "$sdk" -module-cache-path "$module_cache" -O \
    -import-objc-header "$src/Hardware/LogoBridge.h" "$src"/**/*.swift "$cache/LogoBridge.o" \
    -framework IOKit -o "$destination/Contents/MacOS/Lidglow"
sign_identity="${LIDGLOW_SIGN_IDENTITY:--}"
sign_options=()
if [[ "$sign_identity" != "-" ]]; then
    sign_options=(--options runtime --timestamp)
fi
codesign --force --sign "$sign_identity" "${sign_options[@]}" "$destination"
codesign --verify --strict "$destination"
