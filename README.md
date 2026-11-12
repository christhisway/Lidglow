# Lidglow

Lidglow is a macOS menu-bar app that controls the illuminated Apple logo on MacBook Pro with PROLED XDR Display: hold it at a set brightness, let it breathe, or make it pulse to your music.

**Lidglow is in beta.** Betas are numbered 0.9.x and published as pre-releases on [GitHub Releases](https://github.com/christhisway/Lidglow/releases). 1.0 will be the first stable release.

## Requirements

- macOS 27 or later on Apple silicon. The app will not launch at all on Intel Macs.
- A MacBook Pro with PROLED XDR Display. On other Macs, Lidglow only says the Mac has no light-up Apple logo and offers Quit. It doesn't run anything in the background.

Logo control uses a private macOS interface, so a macOS update can stop it working. If that happens, Lidglow leaves the logo to macOS, says it couldn't control the lid logo, and shows a **Report a bug** link that opens the bug report form in your browser.

## Install

Until 1.0 there's no stable release, so run the install command with the beta version from [GitHub Releases](https://github.com/christhisway/Lidglow/releases).

Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash -s -- v0.9.0-beta.2
```

Upon stable release, this command installs the latest version:

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash
```

The script verifies the download, installs `Lidglow.app` in `/Applications`, and opens it. In builds that support beta updates, **Settings → About → Check for Updates** installs a newer beta or stable release and reopens Lidglow. Stable builds check for stable releases.

Lidglow is not notarized by Apple. If you download `Lidglow.zip` in a browser instead, open the app once, close the security alert, then click **Open Anyway** in **System Settings → Privacy & Security**.

## Uninstall

Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/uninstall.sh | bash
```

It quits Lidglow so the logo goes back to macOS, then removes the app, its login item, and its settings. On a Mac without a light-up logo, the panel's **Uninstall…** button does the same for the copy that's running. If you remove it by hand without the above command, quit Lidglow first, or the logo can stay stuck. In the event the logo gets stuck, it can be restored by closing and reopening the lid.

## Use

1. Click the Lidglow icon in the menu bar and turn on the switch in the panel.
2. Pick a mode: **Standard**, **Breathe**, or **Music**. For Music, allow system audio access when macOS asks (see Privacy below).
3. Click the gear for **Settings**. Turn the switch off to hand the logo back to macOS.

Quit any other app that controls the lid logo first, so the two don't fight over it.

If Lidglow crashes or is force quit and the logo stays dim, dark, or stuck at one level, open Lidglow again. It repairs the logo when it starts.

## Features

- **Standard** holds the logo at a brightness you choose.
- **Breathe** fades it slowly up and down. Speed can be chosen from three presets.
- **Music** pulses with the beat from a configured list of apps (default Spotify and Apple Music), all apps, or the microphone (requires Microphone access).
  - Lidglow supports **automatic mode switching**, which turns on Music mode automatically when an allowed app is detected as playing audio, and immediately reverts back to the last selected mode when this audio stops (or after a set length of silence). This is off by default and can be enabled in Settings.
- **Agent alerts** pulse the logo when a coding agent needs you: Claude Code or Codex waiting on a permission prompt or a question, or finishing a turn. It works over any mode, and optionally even while Lidglow is switched off, and stops when you reply, click in the agent's app, open the panel, or after a timeout. This is off by default. Turn it on in **Settings → Agents**, where **Set Up…** shows the hooks to paste into each agent's config.
- Hands the logo back to macOS when you lock, sleep, close the lid, or quit, and repairs it after a crash.
- Optional Open at Login, configurable in settings.

## Privacy

Lidglow records nothing and sends nothing. Agent alerts receive only an agent's name and whether it needs you, through a local link rather than the network. Audio is reduced to a brightness level as it plays and discarded. Its only network access is **Check for Updates**, which runs only when you click it. See the full [privacy statement](docs/PRIVACY.md).

## Contributing

Bug reports, ideas, and pull requests are welcome. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for how to report a bug, build from source, and propose a change. Report security problems privately, as described in [SECURITY.md](docs/SECURITY.md).

## License

Copyright © 2026 christhisway and Lidglow contributors. Lidglow is free software under the [GNU General Public License](LICENSE), version 3 or later, and comes with no warranty. The license covers the code, not the Lidglow name or icon, so please rename forks you distribute.

Lidglow isn't made, endorsed, or supported by Apple. Apple, the Apple logo, Mac, MacBook Pro, and macOS are trademarks of Apple Inc.

Created by Jayden Webb and Kunal Singh.
