#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds, signs, and verifies Lidglow.app. Usage: Scripts/build.sh [destination]
# A relative destination is resolved against the repository root. Default: build/Lidglow.app
set -eu
set -o pipefail
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
resources="$destination/Contents/Resources"
cp "$src/Resources/MenuBarIcon.png" "$src/Resources/MenuBarIconOutline.png" "$resources/"
if xcrun --find actool >/dev/null 2>&1; then
    mkdir -p "$cache/IconOutput" "$cache/IconSupport.xcassets"
    printf '%s\n' '{"info":{"author":"xcode","version":1}}' > "$cache/IconSupport.xcassets/Contents.json"
    # actool can report diagnostics on stdout alongside its generated-file list.
    xcrun actool "$cache/IconSupport.xcassets" "$src/Resources/AppIcon.icon" \
        --compile "$cache/IconOutput" --app-icon AppIcon --platform macosx \
        --target-device mac --minimum-deployment-target 27.0 \
        --output-partial-info-plist "$cache/IconInfo.plist" --warnings --errors |
        awk '/^\/\* com\.apple\.actool\./ { results = /compilation-results/ } !results && NF' >&2
    cp "$cache/IconOutput/Assets.car" "$resources/Assets.car"
    if [[ -f "$cache/IconOutput/AppIcon.icns" ]]; then
        cp "$cache/IconOutput/AppIcon.icns" "$resources/AppIcon.icns"
    else
        rm -f -- "$resources/AppIcon.icns"
        /usr/libexec/PlistBuddy -c 'Delete :CFBundleIconFile' "$destination/Contents/Info.plist"
    fi
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconName string AppIcon' "$destination/Contents/Info.plist"
else
    rm -f -- "$resources/Assets.car"
    cp "$src/Resources/AppIcon.icns" "$resources/AppIcon.icns"
fi
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
