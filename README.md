# Lidglow

Lidglow is a macOS menu-bar app that controls the illuminated Apple logo on MacBook Pro with PROLED XDR Display: hold it at a set brightness, let it breathe, or make it pulse to your music.

**Lidglow is in beta.** Betas are numbered 0.9.x and published as pre-releases on [GitHub Releases](https://github.com/christhisway/Lidglow/releases). 1.0 will be the first stable release.

## Requirements

- macOS 27 or later on Apple silicon.
- A MacBook Pro with PROLED XDR Display to control the logo. Other Apple silicon Macs get an on-screen preview only.

Logo control uses a private macOS interface, so a macOS update can stop it working. If that happens, Lidglow falls back to the preview.

## Install

Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash
```

Until 1.0 there's no stable release, so add the beta version you want from [GitHub Releases](https://github.com/christhisway/Lidglow/releases):

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash -s -- v0.9.0-beta.1
```

The script verifies the download, installs `Lidglow.app` in `/Applications`, and opens it. Run it again to update, or use **Settings → About → Check for Updates** once stable releases exist.

Lidglow isn't notarized by Apple. If you download `Lidglow.zip` in a browser instead, open the app once, then click **Open Anyway** in **System Settings → Privacy & Security**.

## Uninstall

Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/uninstall.sh | bash
```

It quits Lidglow so the logo goes back to macOS, then removes the app, its login item, and its settings. If you remove it by hand, quit Lidglow first, or the logo can stay stuck.

## Use

1. Click the Lidglow icon in the menu bar and turn on the switch in the panel.
2. Pick a mode: **Standard**, **Breathe**, or **Music**. For Music, allow system audio access when macOS asks.
3. Click the gear for **Settings**. Turn the switch off to hand the logo back to macOS.

Quit any other app that controls the lid logo first, so the two don't fight over it.

## Features

- **Standard** holds the logo at a brightness you choose.
- **Breathe** fades it slowly up and down.
- **Music** pulses with the beat from Spotify, Apple Music, any app, or the microphone.
- Hands the logo back to macOS when you lock, sleep, close the lid, or quit, and repairs it after a crash.
- Optional automatic switch to Music when playback starts, and Open at Login.

## Privacy

Lidglow records nothing and sends nothing. Audio is reduced to a brightness level as it plays and discarded. Its only network access is **Check for Updates**, which runs only when you click it. See the full [privacy statement](docs/PRIVACY.md).

## Contributing

Bug reports, ideas, and pull requests are welcome. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for how to report a bug, build from source, and propose a change. Report security problems privately, as described in [SECURITY.md](docs/SECURITY.md).

## License

Copyright © 2026 christhisway and Lidglow contributors. Lidglow is free software under the [GNU General Public License](LICENSE), version 3 or later, and comes with no warranty. The license covers the code, not the Lidglow name or icon, so please rename forks you distribute.

Lidglow isn't made, endorsed, or supported by Apple. Apple, the Apple logo, Mac, MacBook Pro, and macOS are trademarks of Apple Inc.
