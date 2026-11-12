#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Removes Lidglow and leaves the lid logo under macOS control.
#
#   curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/uninstall.sh | bash
#
# Add --reset-permission (after `bash -s --` when piping) to also reset Lidglow's System Audio
# Recording and Microphone permissions. Nothing here needs sudo.
#
# Optional setting:
#   LIDGLOW_INSTALL_DIR  look for Lidglow.app only here, instead of /Applications and ~/Applications
#
# On a Mac without a light-up logo, the panel's Uninstall button runs the copy of this script bundled inside
# Lidglow.app as `uninstall.sh --from-app`, with LIDGLOW_APP set to the running app's path and LIDGLOW_PID to
# its process ID. In that mode it removes only that copy. It doesn't quit Lidglow itself: it checks that it
# can remove the app, exits with 0, and removes everything once Lidglow has quit normally. It exits with 1
# and the reason on stderr if it can't.
set -euo pipefail

bundle_id="io.github.christhisway.lidglow"
reset_permission=false
from_app=false
for argument in "$@"; do
    case "$argument" in
        --reset-permission) reset_permission=true ;;
        --from-app) from_app=true ;;
        *) printf 'Usage: uninstall.sh [--reset-permission]\n' >&2; exit 64 ;;
    esac
done

fail() { printf 'Lidglow uninstall: %s\n' "$1" >&2; exit 1; }
say() { printf '==> %s\n' "$1"; }

apps=()
if $from_app; then
    # 1. Started by Lidglow, which quits normally once this exits. Check now that the removal can work,
    # so a failure shows in the app instead of leaving it installed after it quits.
    app="${LIDGLOW_APP:-}"
    app="${app%/}"
    [[ -n "$app" && -d "$app" ]] || fail "--from-app needs LIDGLOW_APP set to the running app's path."
    [[ "${LIDGLOW_PID:-}" =~ ^[0-9]+$ ]] || fail "--from-app needs LIDGLOW_PID set to the running app's process ID."
    [[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null || true)" == "$bundle_id" ]] \
        || fail "$app isn't Lidglow, so nothing was removed."
    folder="$(dirname -- "$app")"
    [[ -w "$folder" ]] || fail "Lidglow can't remove itself from $folder. Move it to the Trash instead."
    folders=("$folder")
    apps=("$app")
else
    # 1. Quit Lidglow normally first, so it hands the logo back to macOS. Never kill it.
    if pgrep -qx Lidglow; then
        say "Quitting Lidglow"
        osascript -e "quit app id \"$bundle_id\"" >/dev/null 2>&1 || true
        for _ in {1..50}; do pgrep -qx Lidglow || break; sleep 0.1; done
        pgrep -qx Lidglow && fail "Lidglow is still running. Quit it from its menu, then run this again."
    fi
    if [[ -n "${LIDGLOW_INSTALL_DIR:-}" ]]; then folders=("$LIDGLOW_INSTALL_DIR"); else folders=(/Applications "$HOME/Applications"); fi
    for folder in "${folders[@]}"; do
        if [[ -d "$folder/Lidglow.app" ]]; then apps+=("$folder/Lidglow.app"); fi
    done
fi

remove_lidglow() {
    # 2. Remove the login item while the app still exists, since only the app can unregister itself.
    # Builds without the flag would start the full app instead, so only run ones that have it.
    for app in "${apps[@]+"${apps[@]}"}"; do
        if grep -qa -- "--unregister-login-item" "$app/Contents/MacOS/Lidglow"; then
            "$app/Contents/MacOS/Lidglow" --unregister-login-item 2>/dev/null || true
        else
            say "This Lidglow is too old to remove its own login item. If it's in System Settings → General → Login Items, remove it there."
        fi
    done
    agent="$HOME/Library/LaunchAgents/$bundle_id.plist"
    if [[ -f "$agent" ]]; then
        launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
        rm -f -- "$agent"
        say "Removed the login LaunchAgent"
    fi

    # 3. Reset the permission if asked. macOS only finds the app's permission while the app is installed.
    if $reset_permission; then
        if tccutil reset AudioCapture "$bundle_id" >/dev/null 2>&1; then
            say "Reset the System Audio Recording permission"
        else
            say "Couldn't reset the System Audio Recording permission. Remove Lidglow in System Settings → Privacy & Security → Screen & System Audio Recording."
        fi
        if tccutil reset Microphone "$bundle_id" >/dev/null 2>&1; then
            say "Reset the Microphone permission"
        else
            say "Couldn't reset the Microphone permission. Remove Lidglow in System Settings → Privacy & Security → Microphone."
        fi
    fi

    # 4. Remove the app and its settings.
    for app in "${apps[@]+"${apps[@]}"}"; do
        rm -rf -- "$app"
        say "Removed $app"
    done
    [[ ${#apps[@]} -gt 0 ]] || say "Lidglow.app wasn't found in ${folders[*]}"
    if defaults read "$bundle_id" >/dev/null 2>&1; then
        defaults delete "$bundle_id"
        say "Removed Lidglow's settings"
    fi
    say "Lidglow is uninstalled. The lid logo is back under macOS control."
}

if $from_app; then
    # Runs on after this script exits. Its output goes nowhere, so Lidglow doesn't wait on it.
    (
        trap '' HUP
        for _ in {1..600}; do kill -0 "$LIDGLOW_PID" 2>/dev/null || break; sleep 0.1; done
        # Lidglow didn't quit within a minute, so leave it installed.
        kill -0 "$LIDGLOW_PID" 2>/dev/null && exit 1
        remove_lidglow
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    say "Lidglow will be removed from $folder once it quits."
    exit 0
fi
remove_lidglow
