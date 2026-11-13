#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
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
mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources"
cp "$src/Resources/Info.plist" "$destination/Contents/Info.plist"
cp "$src/Resources/AppIcon.icns" "$destination/Contents/Resources/AppIcon.icns"
# Settings → About → Check for Updates runs this copy, so the app only runs installer code it shipped with.
cp Scripts/install.sh "$destination/Contents/Resources/install.sh"
# So does Uninstall on a Mac without a light-up logo.
cp Scripts/uninstall.sh "$destination/Contents/Resources/uninstall.sh"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
target="$(uname -m)-apple-macos27.0"
xcrun clang -target "$target" -isysroot "$sdk" -fobjc-arc -O2 \
    -c "$src/Hardware/LogoBridge.m" -o "$cache/LogoBridge.o"
xcrun swiftc -target "$target" -sdk "$sdk" -module-cache-path "$module_cache" -O \
    -import-objc-header "$src/Hardware/LogoBridge.h" "$src"/**/*.swift "$cache/LogoBridge.o" \
    -framework IOKit -o "$destination/Contents/MacOS/Lidglow"
# Ad hoc by default. A self-signed identity (for example "Lidglow Self-Signed") gives every release the
# same designated requirement, so macOS keeps the audio permission across updates. Only a Developer ID
# identity gets the hardened runtime and a secure timestamp, which notarization needs.
sign_identity="${LIDGLOW_SIGN_IDENTITY:--}"
sign_options=()
if [[ "$sign_identity" == "Developer ID Application"* ]]; then
    # The hardened runtime blocks microphone input unless the app declares it. Lidglow only opens the
    # microphone when the user chooses it as Music's source.
    sign_options=(--options runtime --timestamp --entitlements "$src/Resources/Lidglow.entitlements")
fi
codesign --force --sign "$sign_identity" "${sign_options[@]}" "$destination"
codesign --verify --strict "$destination"
