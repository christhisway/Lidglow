#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Installs or updates Lidglow from GitHub Releases.
#
#   curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash
#
# With no argument, this installs the latest stable release. To install a specific version, such
# as a beta, pass its tag after `bash -s --`:
#
#   curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash -s -- v0.9.0-beta.1
#
# Files downloaded with curl don't get macOS's quarantine attribute, so the app opens without a
# Gatekeeper warning. The download is checked against the SHA-256 published with the release.
# Running this again updates Lidglow. Nothing here needs sudo.
#
# Optional settings:
#   LIDGLOW_VERSION      a release tag to install, the same as passing it as the argument (the
#                        argument wins if both are given)
#   LIDGLOW_INSTALL_DIR  where to put Lidglow.app (default: /Applications, or ~/Applications if that
#                        isn't writable)
#   LIDGLOW_RELEASE_URL  where to download Lidglow.zip and Lidglow.zip.sha256 from (for testing)
#
# Settings → About → Check for Updates runs the copy of this script bundled inside Lidglow.app as
# `install.sh --update`, with LIDGLOW_APP set to the running app's path and LIDGLOW_PID to its process
# ID. It may pass a release tag for a beta-channel update. With no tag it checks the latest stable
# release. Either way, it installs only if the build number is higher.
# It doesn't quit Lidglow itself: it stages the new app next to the old one, exits with 0, and replaces
# the app once Lidglow has quit normally. Its other exit codes are 10 when Lidglow is already up to
# date, 11 when there's no stable release yet, and 1 for any other failure, with the reason on stderr.
set -euo pipefail

bundle_id="io.github.christhisway.lidglow"
minimum_macos="27.0"
repo="christhisway/Lidglow"
up_to_date=10
no_stable_release=11

fail() { printf 'Lidglow install: %s\n' "$1" >&2; exit "${2:-1}"; }
say() { printf '==> %s\n' "$1"; }
build_of() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist" 2>/dev/null || true; }

releases_page="https://github.com/$repo/releases"
install_command="curl -fsSL https://raw.githubusercontent.com/$repo/main/Scripts/install.sh | bash"

# 0. Read the arguments. "0.9.0-beta.1" and "v0.9.0-beta.1" both mean the tag v0.9.0-beta.1.
update=false
if [[ "${1:-}" == "--update" ]]; then
    update=true
    shift
    (( $# <= 1 )) || fail "--update takes at most one release tag."
    [[ -n "${LIDGLOW_APP:-}" && -d "$LIDGLOW_APP" ]] || fail "--update needs LIDGLOW_APP set to the app to update."
    [[ "${LIDGLOW_PID:-}" =~ ^[0-9]+$ ]] || fail "--update needs LIDGLOW_PID set to the running app's process ID."
    version="${1:-}"
else
    (( $# <= 1 )) || fail "Pass at most one version, for example: $install_command -s -- v0.9.0-beta.1"
    version="${1:-${LIDGLOW_VERSION:-}}"
fi
if [[ -n "$version" ]]; then
    [[ "$version" == v* ]] || version="v$version"
    [[ "$version" =~ ^v[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.]+)?$ ]] \
        || fail "\"$version\" isn't a Lidglow version. Versions look like v0.9.0-beta.1 or v1.0.0. See $releases_page"
fi

# 1. Check the Mac.
[[ "$(uname -s)" == "Darwin" ]] || fail "Lidglow only runs on macOS."
if [[ "$(uname -m)" != "arm64" && "$(sysctl -n sysctl.proc_translated 2>/dev/null)" != "1" ]]; then
    fail "Lidglow needs a Mac with Apple silicon."
fi
macos="$(sw_vers -productVersion)"
if [[ "$(printf '%s\n%s\n' "$minimum_macos" "$macos" | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)" != "$minimum_macos" ]]; then
    fail "Lidglow needs macOS $minimum_macos or later. This Mac has macOS $macos."
fi

# 2. Download the release and verify its checksum, signature, and bundle ID.
if [[ -n "${LIDGLOW_RELEASE_URL:-}" ]]; then
    base="$LIDGLOW_RELEASE_URL"
elif [[ -n "$version" ]]; then
    base="https://github.com/$repo/releases/download/$version"
else
    # GitHub's "latest" release is the newest one that isn't a pre-release, so betas never count.
    base="https://github.com/$repo/releases/latest/download"
fi
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
say "Downloading Lidglow from $base"
status=0
http_status="$(curl -fsSL --connect-timeout 10 --max-time 120 -w '%{http_code}' \
    "$base/Lidglow.zip" -o "$work/Lidglow.zip" 2>/dev/null)" || status=$?
if (( status == 22 )) && [[ "$http_status" == 404 && -z "${LIDGLOW_RELEASE_URL:-}" ]]; then
    if [[ -n "$version" ]]; then
        fail "There's no Lidglow release named $version. See the versions at $releases_page"
    fi
    fail "There's no stable Lidglow release yet. To install a beta, pass its version, for example:
  $install_command -s -- v0.9.0-beta.1
See the versions at $releases_page" "$no_stable_release"
fi
(( status == 0 )) || fail "Couldn't download Lidglow.zip. Check your internet connection and try again."
curl -fsSL --connect-timeout 10 --max-time 30 "$base/Lidglow.zip.sha256" \
    -o "$work/Lidglow.zip.sha256" 2>/dev/null || fail "Couldn't download the checksum."
expected="$(awk '{ print $1; exit }' "$work/Lidglow.zip.sha256")"
actual="$(shasum -a 256 "$work/Lidglow.zip" | awk '{ print $1 }')"
[[ -n "$expected" && "$expected" == "$actual" ]] || fail "The download doesn't match its checksum. Nothing was installed."
say "Checksum verified ($actual)"
ditto -x -k "$work/Lidglow.zip" "$work/unpacked"
new_app="$work/unpacked/Lidglow.app"
[[ -d "$new_app" ]] || fail "The download doesn't contain Lidglow.app."
codesign --verify --strict "$new_app" 2>/dev/null || fail "Lidglow.app's signature is invalid."
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$new_app/Contents/Info.plist" 2>/dev/null)" == "$bundle_id" ]] \
    || fail "The download isn't Lidglow. Nothing was installed."

# 3a. From Check for Updates: install only a newer build, and let Lidglow quit itself.
if $update; then
    app="${LIDGLOW_APP%/}"
    new_build="$(build_of "$new_app")"
    current_build="$(build_of "$app")"
    [[ "$new_build" =~ ^[0-9]+$ && "$current_build" =~ ^[0-9]+$ ]] || fail "Couldn't read the build numbers to compare."
    if (( new_build <= current_build )); then
        say "Lidglow is up to date (build $current_build; the selected release is build $new_build)."
        exit "$up_to_date"
    fi
    folder="$(dirname -- "$app")"
    [[ -w "$folder" ]] || fail "Lidglow can't replace itself in $folder. Run the install command in Terminal instead."
    # Stage the new app in the same folder, so the swap after Lidglow quits is a quick rename.
    stage_dir="$(mktemp -d "$folder/.Lidglow-update.XXXXXX")" || fail "Couldn't stage the update in $folder."
    staged="$stage_dir/Lidglow.app"
    backup="$stage_dir/Previous.app"
    ditto "$new_app" "$staged" || { rm -rf -- "$stage_dir"; fail "Couldn't copy the update into $folder."; }
    # Runs on after this script exits. Its output goes nowhere, so Lidglow doesn't wait on it.
    (
        trap - EXIT
        trap '' HUP
        for _ in {1..600}; do kill -0 "$LIDGLOW_PID" 2>/dev/null || break; sleep 0.1; done
        if kill -0 "$LIDGLOW_PID" 2>/dev/null; then
            # Lidglow didn't quit within a minute, so leave the installed app alone.
            rm -rf -- "$stage_dir"
            exit 1
        fi
        # Another copy may have been installed while Lidglow was quitting.
        if [[ "$(build_of "$app")" != "$current_build" ]] || ! mv -- "$app" "$backup"; then
            rm -rf -- "$stage_dir"
            exit 1
        fi
        if ! mv -- "$staged" "$app"; then
            if [[ ! -e "$app" ]] && mv -- "$backup" "$app"; then
                rm -rf -- "$stage_dir"
                open "$app"
            fi
            exit 1
        fi
        if ! open "$app"; then
            if mv -- "$app" "$staged" && mv -- "$backup" "$app"; then
                rm -rf -- "$stage_dir"
                open "$app"
            fi
            exit 1
        fi
        rm -rf -- "$stage_dir"
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    say "Build $new_build is ready. It replaces $app once Lidglow quits."
    exit 0
fi

# 3b. Quit a running Lidglow normally, so it hands the logo back to macOS. Never kill it.
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
ditto "$new_app" "$app"
say "Installed $app"
open "$app"
if [[ -n "$version" ]]; then
    say "Lidglow $version is in your menu bar. To update, run the install command again with the new version, or with no version for the latest stable release."
else
    say "Lidglow is in your menu bar. Run this command again any time to update."
fi
