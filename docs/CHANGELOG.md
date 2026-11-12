# Changelog

Each release is also published on [GitHub Releases](https://github.com/christhisway/Lidglow/releases) with these notes. **Settings → About → Check for Updates** installs the latest stable release. See [Install](../README.md#install).

## 0.9.0 Beta 1

### Added
- A Settings window, opened from the gear in the panel, ⌘, while the panel is open, or the menu-bar icon's Control-click menu. It shows the version and links to the project and its releases.
- A Control-click menu on the menu-bar icon with Open Settings… and Quit Lidglow.
- A switch in the panel's top-right corner that hands the logo back to macOS.
- A sliding Liquid Glass selector for the modes, and Liquid Glass styling for the panel.
- An animated laptop preview that shows the live lid glow in your Mac's finish.
- The Terminal installer takes an optional version, such as `v0.9.0-beta.1`, to install a beta. With no version it installs the latest stable release.
- **Check for Updates** in Settings → About. It installs the latest stable release from GitHub if it's newer, then reopens Lidglow. It's Lidglow's only network access and runs only when you click it.
- Agent alerts in Settings → Agents (off by default): the logo pulses over any mode, and optionally while Lidglow is off, when Claude Code or Codex needs your input or finishes, until you reply, click in the agent's app, open the panel, or it times out. Agents signal Lidglow through hooks you paste into their config, with a `lidglow://` link and no network access.
- While your Mac charges, the logo breathes in every mode (Settings → General → Breathe while charging, on by default), except Music while music is playing. It keeps breathing while the screen is locked, until the display sleeps. With a full battery the selected mode shows as usual.

### Changed
- Off and Steady are now a single Standard mode, whose brightness can go down to off. System mode is now the switch turned off. Saved build 1 settings carry over.
- Music mode uses less energy during silence and while the panel is closed.
- On a Mac without a light-up Apple logo, Lidglow stays inactive and only offers Quit, instead of running a preview. If it can't control the logo, for example after a macOS update, the panel says so and links to the bug report form.

## Build 1 (tagged v1.0, not publicly released)

The first version, numbered 1.0 before the beta numbering: Standard, Breathe, and Music modes for the illuminated lid logo, with Music driven by your Mac's audio output.
