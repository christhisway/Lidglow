# Lidglow

Lidglow is a native macOS menu-bar app for the illuminated Apple logo on MacBook Pro with PROLED XDR Display. The included app is an ad-hoc signed Apple silicon build.

**Lidglow is in beta.** Beta versions are numbered 0.9.x, show **Beta** in **Settings → About**, and are marked as pre-releases on [GitHub Releases](https://github.com/christhisway/Lidglow/releases). 1.0 will be the first stable release. Please [report anything that goes wrong](#reporting-bugs).

## Requirements

| | Support |
| --- | --- |
| **MacBook Pro with PROLED XDR display** | Full control of the illuminated lid logo |
| **Other Apple silicon Macs** | Preview only. The panel shows an on-screen preview and never sends anything to the hardware. The status line says why. |
| **Intel Macs** | Not supported. Lidglow is built for Apple silicon only and won't open. |
| **macOS** | 27 or later. Every MacBook Pro with a light-up Apple logo ships with macOS 27 or later. On an older macOS, macOS won't open Lidglow. |

Logo control uses a private macOS interface, so a macOS update can stop it working. If that happens, Lidglow shows “Lid logo service unavailable” and switches to the preview instead of controlling the logo.

## Install

Lidglow needs a Mac with Apple silicon and macOS 27 or later. Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash
```

Until 1.0 is out there's no stable release, so install a beta by adding its version after `bash -s --`. Find the versions on [GitHub Releases](https://github.com/christhisway/Lidglow/releases):

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash -s -- v0.9.0-beta.1
```

The script checks your Mac, downloads the latest stable release (or the version you named) from GitHub Releases, verifies its SHA-256 checksum, quits any running Lidglow normally so the logo goes back to macOS, installs `Lidglow.app` in `/Applications` (or `~/Applications` if `/Applications` isn't writable), and opens it. Run the command again to update: with a newer version to move to that beta, or with no version for the latest stable release. It doesn't use `sudo`.

To read the script before running it:

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh -o install-lidglow.sh
less install-lidglow.sh
bash install-lidglow.sh
```

To start Lidglow automatically, turn on **Settings → General → Open at Login**.

**Lidglow isn't notarized by Apple.** It's a free personal project, so it doesn't pay for an Apple Developer ID. Installing with the command above opens the app normally, because files downloaded with `curl` aren't marked as quarantined. If you download `Lidglow.zip` in a browser instead, macOS blocks the first launch: open the app once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. (Since macOS 15, Control-click → Open no longer bypasses this.) Either way, you're trusting this project directly. Each release lists its checksum and the source it was built from.

## Uninstall

Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/uninstall.sh | bash
```

It quits Lidglow normally so the logo goes back to macOS, removes its login item, deletes `Lidglow.app` and its settings. To also reset the System Audio Recording and Microphone permissions, add `-s -- --reset-permission` after `bash`.

To uninstall by hand:

1. **Quit Lidglow first** with **Quit** in the panel or its Control-click menu, so it hands the logo back to macOS. Deleting the app while it's running can leave the logo stuck.
2. If **Open at Login** is on, turn it off in **Settings → General**, or remove Lidglow in **System Settings → General → Login Items**.
3. Delete `Lidglow.app` from `/Applications` (or wherever you put it).
4. Optional cleanup:
   - Remove its settings: `defaults delete io.github.christhisway.lidglow`
   - Remove its audio permission in **System Settings → Privacy & Security → Screen & System Audio Recording**, or with `tccutil reset AudioCapture io.github.christhisway.lidglow` (before deleting the app).
   - If you used **Microphone**, remove that permission in **System Settings → Privacy & Security → Microphone**, or with `tccutil reset Microphone io.github.christhisway.lidglow` (before deleting the app).
5. If the logo still looks wrong afterwards, restart your Mac.

## Use Lidglow

1. Quit any other app that controls the lid logo, so that only one app sends brightness commands. Lidglow also watches for this itself. If another app changes the logo while Lidglow holds it, Lidglow hands the logo back to macOS and asks you to quit that app. A few logo apps are recognized by name: while one of them is running, Lidglow leaves the logo alone, says so in its panel, and takes over when it quits.
2. Open **Lidglow.app** (the installer opens it for you). Click the waveform circle in the macOS menu bar to open its controls, and turn on the switch in the panel's top-right corner. Click the gear next to the switch (or press ⌘, while the panel is open) for **Settings**, which shows the version and project links. Control-click or right-click the icon for **Open Settings…** and **Quit Lidglow**.
3. Choose **Music**, allow macOS system audio capture when prompted, and play music. By default Music reacts only to **Spotify** and **Apple Music**. In **Settings → Music**, **Listen to** switches between **Chosen apps** (click **Choose…** to pick them), **All apps**, and **Microphone**, which reacts to sound around your Mac and is off by default. **Brightness** sets the peak glow and **Sensitivity** adjusts how strongly hits drive it. **Focus** picks what drives the glow: **Bass** (kick drums and bass lines, the default), **Mids** (vocals, guitars, keys, and snares), **Treble** (hi-hats and cymbals), or **Full** (the whole mix). Turn on **Idle glow** to keep a base between beats and tracks. Use **Idle brightness** to raise or lower it. With **Chosen apps** or **All apps**, turn on **Automatically switch to Music** to have Lidglow select Music when one of those apps starts playing. With **All apps**, macOS system sounds such as alerts and volume feedback are ignored, both for switching and for the glow. When nothing has played for a while, Music switches back to the mode you used before it. Set how long in **Settings → Music → Switch back after silence**: 5, 10 (the default), 15, or 30 seconds, 1 minute, or **Never**. **Automatically** switches back as soon as the audio stream from all chosen apps (or, with **All apps**, every app) stops, for example when you pause. With **Microphone** it uses 10 seconds of silence.
4. Turn the switch off to hand brightness back to macOS. **Standard** holds the logo at the chosen brightness (drag **Brightness** all the way down to turn it off), and **Breathe** fades it up and down. Choose a **Speed** of Slow, Normal, or Fast under Brightness. Each mode remembers its own **Brightness**, so turning Standard off doesn't dim Breathe or Music. Breathe and Music never go below 5%.

If Music remains on “Waiting for music” during playback, check that the app you're playing from is chosen in **Settings → Music**. Otherwise use **System Audio Settings…** to check Lidglow’s access under **Privacy & Security → Screen & System Audio Recording**. With **Microphone**, the same button opens **Microphone Settings…** instead. After changing access, reselect **Music** or quit and reopen Lidglow.

If the lid logo is stuck dim, dark, or at one level (for example after Lidglow crashed or was force quit), open Lidglow again. It notices that it didn't hand the logo back and repairs it at launch, even with the switch off. If the logo still looks wrong, quit Lidglow normally and restart your Mac.

Audio processing runs locally through a private Core Audio tap. The app reduces playback to a level driven by hits in the chosen Focus and discards the samples. Hardware modes pause when the session locks, the display sleeps, or the lid closes. Older Macs can use the in-panel preview.

## Updating

New versions are posted on [GitHub Releases](https://github.com/christhisway/Lidglow/releases) with release notes, also kept in [CHANGELOG.md](docs/CHANGELOG.md). Lidglow never checks for updates on its own. To be notified, click **Watch → Custom → Releases** on the repository page. **Settings → About → View Releases** opens the page in your browser.

**Settings → About → Check for Updates** installs the latest stable release if it's newer than yours. It verifies the download the same way the install command does, quits Lidglow normally so the logo goes back to macOS, replaces the app, and reopens it. If you're already up to date, or there's no stable release yet, it says so and changes nothing. It only offers stable releases, so to move to a newer beta, use the install command with that beta's version. It can't update a copy of Lidglow in a folder you can't write to.

To update, run the [install command](#install) again, adding the new version if you're on a beta. It quits Lidglow normally so it hands the logo back to macOS, then replaces the app and opens it. If you installed by hand, quit Lidglow from the panel or its Control-click menu, then replace `Lidglow.app` with the new version and open it. An ad-hoc signed build may ask for System Audio Recording or Microphone permission again after an update.

## Privacy

Lidglow records nothing, and its only network access is **Check for Updates**, which runs only when you click it. Music mode reduces your Mac's audio output to a brightness level as it plays and then discards it. It uses the microphone only if you choose **Microphone** as Music's source, and only while Music is running. Settings are stored only in macOS preferences. Read the full [privacy statement](docs/PRIVACY.md).

## Reporting bugs

Lidglow never sends crash reports or diagnostics anywhere. To report a problem, [open an issue](https://github.com/christhisway/Lidglow/issues/new/choose) and include what you can of the following:

- **Crash reports:** open the Console app and choose **Crash Reports**, or look in `~/Library/Logs/DiagnosticReports/` for files whose names start with `Lidglow`.
- **Recent logs:** run this in Terminal shortly after the problem happens:

  ```sh
  log show --last 10m --info --predicate 'subsystem == "io.github.christhisway.lidglow"'
  ```

  Lidglow logs when it takes and releases control of the logo, the result of its hardware check, and when the system audio tap starts, stops, or fails. The logs contain no audio and stay on your Mac until you share them.

## Project layout

```
Sources/Lidglow/
  App/        Entry point, application delegate (status item, panel window), local log categories, and the Check for Updates runner
  Glow/       Glow modes and the model that drives the logo each tick
  UI/         SwiftUI controls, shared Liquid Glass styling, the borderless menu panel, the Settings window, and the animated laptop preview
  Audio/      Core Audio process tap, the playback watcher for automatic switching to Music, and the BeatMeter detector
  Hardware/   Lid logo control, detection of other apps controlling the logo, laptop finish detection, and the Objective-C CoreBrightness bridge
  Resources/  Info.plist and the entitlements used for Developer ID (hardened-runtime) signing
Tests/BeatMeterTests/  Synthetic beat detector check
Scripts/      build.sh, test.sh, package.sh (release zip and checksum), install.sh (the Terminal installer, also bundled in the app for Check for Updates), and uninstall.sh
docs/         Handoff notes, the end-user install guide, the release checklist, the changelog, and the contributing, security, and privacy notes
.github/      Issue templates and the Release workflow, which builds a draft release from main when started by hand
```

## Build

Install Xcode or the macOS Command Line Tools (`xcode-select --install`), then run `Scripts/build.sh` from the repository root. The script builds, signs, and verifies `build/Lidglow.app` using the Mac's native architecture. Pass a path as the first argument to choose a different destination; relative paths resolve against the repository root. No third-party dependencies are required.

To run the synthetic beat detector check:

```sh
Scripts/test.sh
```

`Scripts/package.sh` builds the release files that the installer downloads: `build/release/Lidglow.zip` and `Lidglow.zip.sha256`. Published releases are built by the **Release** workflow in GitHub Actions instead, from `main`. See [docs/RELEASE.md](docs/RELEASE.md) for the release checklist.

The default signature is ad hoc, which changes with every build, so macOS asks for System Audio Recording permission again after each update. To avoid that for free, sign releases with a self-signed certificate:

1. Once, in **Keychain Access**, choose **Keychain Access → Certificate Assistant → Create a Certificate…**. Name it `Lidglow Self-Signed`, set **Identity Type** to **Self-Signed Root** and **Certificate Type** to **Code Signing**, and create it. Back it up (export it as a `.p12` with a password) and never commit it.
2. Build with `LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh`.

Every release signed this way has the same designated requirement, so macOS keeps the audio and microphone permissions. For a notarized release instead, set `LIDGLOW_SIGN_IDENTITY` to a `Developer ID Application` identity. Only that kind of identity enables the hardened runtime, the microphone entitlement it requires, and a secure timestamp. Then submit and staple the app before distributing it. [Apple’s notarization instructions](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Lidglow uses the documented Core Audio tap interface and a dynamically loaded, private CoreBrightness interface. Hardware compatibility depends on macOS. [Apple’s Core Audio documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) · [LogoLight’s CoreBrightness research](https://github.com/Ark0N/LogoLight/blob/main/docs/corebrightnessd.md)

## Contributing

Bug reports, ideas, and pull requests are welcome. See [CONTRIBUTING.md](docs/CONTRIBUTING.md). Commits need a [DCO](https://developercertificate.org/) sign-off (`git commit -s`). Report security problems privately, as described in [SECURITY.md](docs/SECURITY.md).

## License

Copyright © 2026 christhisway and Lidglow contributors.

Lidglow is free software: you can redistribute it and modify it under the terms of the [GNU General Public License](LICENSE), version 3 or (at your option) any later version. Anything you distribute that's based on Lidglow must also be released under the GPL, with its full source. Lidglow comes with **no warranty**. See the license for details.

Lidglow can't be offered on the Mac App Store, because it relies on a private macOS interface (CoreBrightness) to control the logo.

**Name and icon:** the license covers the code, not the Lidglow name or icon. Forks are welcome, but if you distribute your own builds, please give them a different name and icon so people can tell them apart.

**Not affiliated with Apple.** Lidglow isn't made, endorsed, or supported by Apple. Apple, the Apple logo, Mac, MacBook Pro, and macOS are trademarks of Apple Inc.
