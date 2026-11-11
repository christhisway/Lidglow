#!/bin/bash
# Removes Lidglow and leaves the lid logo under macOS control.
#
#   curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/uninstall.sh | bash
#
# Add --reset-permission (after `bash -s --` when piping) to also reset Lidglow's System Audio
# Recording permission. Nothing here needs sudo.
#
# Optional setting:
#   LIDGLOW_INSTALL_DIR  look for Lidglow.app only here, instead of /Applications and ~/Applications
set -euo pipefail

bundle_id="io.github.christhisway.lidglow"
reset_permission=false
for argument in "$@"; do
    case "$argument" in
        --reset-permission) reset_permission=true ;;
        *) printf 'Usage: uninstall.sh [--reset-permission]\n' >&2; exit 64 ;;
    esac
done

fail() { printf 'Lidglow uninstall: %s\n' "$1" >&2; exit 1; }
say() { printf '==> %s\n' "$1"; }

# 1. Quit Lidglow normally first, so it hands the logo back to macOS. Never kill it.
if pgrep -qx Lidglow; then
    say "Quitting Lidglow"
    osascript -e "quit app id \"$bundle_id\"" >/dev/null 2>&1 || true
    for _ in {1..50}; do pgrep -qx Lidglow || break; sleep 0.1; done
    pgrep -qx Lidglow && fail "Lidglow is still running. Quit it from its menu, then run this again."
fi

apps=()
if [[ -n "${LIDGLOW_INSTALL_DIR:-}" ]]; then folders=("$LIDGLOW_INSTALL_DIR"); else folders=(/Applications "$HOME/Applications"); fi
for folder in "${folders[@]}"; do
    if [[ -d "$folder/Lidglow.app" ]]; then apps+=("$folder/Lidglow.app"); fi
done

# 2. Remove the login item while the app still exists, since only the app can unregister itself.
for app in "${apps[@]+"${apps[@]}"}"; do
    "$app/Contents/MacOS/Lidglow" --unregister-login-item 2>/dev/null || true
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
        say "Couldn't reset the permission. Remove Lidglow in System Settings → Privacy & Security → Screen & System Audio Recording."
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
