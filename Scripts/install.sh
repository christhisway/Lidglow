#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs or updates Lidglow from GitHub Releases.
#
#   curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash
#
# Files downloaded with curl don't get macOS's quarantine attribute, so the app opens without a
# Gatekeeper warning. The download is checked against the SHA-256 published with the release.
# Running this again updates Lidglow. Nothing here needs sudo.
#
# Optional settings:
#   LIDGLOW_VERSION      a release tag to install, for example v0.9.0-beta.1 (default: the latest release)
#   LIDGLOW_INSTALL_DIR  where to put Lidglow.app (default: /Applications, or ~/Applications if that
#                        isn't writable)
#   LIDGLOW_RELEASE_URL  where to download Lidglow.zip and Lidglow.zip.sha256 from (for testing)
set -euo pipefail

bundle_id="io.github.christhisway.lidglow"
minimum_macos="14.2"
repo="christhisway/Lidglow"

fail() { printf 'Lidglow install: %s\n' "$1" >&2; exit 1; }
say() { printf '==> %s\n' "$1"; }

# 1. Check the Mac.
[[ "$(uname -s)" == "Darwin" ]] || fail "Lidglow only runs on macOS."
if [[ "$(uname -m)" != "arm64" && "$(sysctl -n sysctl.proc_translated 2>/dev/null)" != "1" ]]; then
    fail "Lidglow needs a Mac with Apple silicon."
fi
macos="$(sw_vers -productVersion)"
if [[ "$(printf '%s\n%s\n' "$minimum_macos" "$macos" | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)" != "$minimum_macos" ]]; then
    fail "Lidglow needs macOS $minimum_macos or later. This Mac has macOS $macos."
fi

# 2. Download the release and verify its checksum.
if [[ -n "${LIDGLOW_RELEASE_URL:-}" ]]; then
    base="$LIDGLOW_RELEASE_URL"
elif [[ -n "${LIDGLOW_VERSION:-}" ]]; then
    base="https://github.com/$repo/releases/download/$LIDGLOW_VERSION"
else
    base="https://github.com/$repo/releases/latest/download"
fi
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
say "Downloading Lidglow from $base"
curl -fsSL "$base/Lidglow.zip" -o "$work/Lidglow.zip" || fail "Couldn't download Lidglow.zip."
curl -fsSL "$base/Lidglow.zip.sha256" -o "$work/Lidglow.zip.sha256" || fail "Couldn't download the checksum."
expected="$(awk '{ print $1; exit }' "$work/Lidglow.zip.sha256")"
actual="$(shasum -a 256 "$work/Lidglow.zip" | awk '{ print $1 }')"
[[ -n "$expected" && "$expected" == "$actual" ]] || fail "The download doesn't match its checksum. Nothing was installed."
say "Checksum verified ($actual)"
ditto -x -k "$work/Lidglow.zip" "$work/unpacked"
[[ -d "$work/unpacked/Lidglow.app" ]] || fail "The download doesn't contain Lidglow.app."
codesign --verify --strict "$work/unpacked/Lidglow.app" 2>/dev/null || fail "Lidglow.app's signature is invalid."

# 3. Quit a running Lidglow normally, so it hands the logo back to macOS. Never kill it.
if pgrep -qx Lidglow; then
    say "Quitting Lidglow"
    osascript -e "quit app id \"$bundle_id\"" >/dev/null 2>&1 || true
    for _ in {1..50}; do pgrep -qx Lidglow || break; sleep 0.1; done
    pgrep -qx Lidglow && fail "Lidglow is still running. Quit it from its menu, then run this again."
fi

# 4. Replace the app and open it.
if [[ -n "${LIDGLOW_INSTALL_DIR:-}" ]]; then
    destination="$LIDGLOW_INSTALL_DIR"
elif [[ -d /Applications/Lidglow.app && -w /Applications ]]; then
    destination="/Applications"
elif [[ -d "$HOME/Applications/Lidglow.app" ]]; then
    destination="$HOME/Applications"
elif [[ -w /Applications ]]; then
    destination="/Applications"
else
    destination="$HOME/Applications"
fi
mkdir -p "$destination"
app="$destination/Lidglow.app"
rm -rf -- "$app"
ditto "$work/unpacked/Lidglow.app" "$app"
say "Installed $app"
open "$app"
say "Lidglow is in your menu bar. Run this command again any time to update."
