# Contributing to Lidglow

Thanks for helping. Lidglow is a small, free project, so the process is light.

## Reporting bugs

Lidglow never sends crash reports or diagnostics anywhere. To report a problem, [open an issue](https://github.com/christhisway/Lidglow/issues/new/choose) and include what you can of the following:

- **Crash reports:** open the Console app and choose **Crash Reports**, or look in `~/Library/Logs/DiagnosticReports/` for files whose names start with `Lidglow`.
- **Recent logs:** run this in Terminal shortly after the problem happens:

  ```sh
  log show --last 10m --info --predicate 'subsystem == "io.github.christhisway.lidglow"'
  ```

  Lidglow logs when it takes and releases control of the logo, the result of its hardware check, and when the system audio tap starts, stops, or fails. The logs contain no audio and stay on your Mac until you share them.

If Music stays on “Waiting for music” during playback, check that the app you're playing from is chosen in **Settings → Music**, then check Lidglow's access under **System Settings → Privacy & Security → Screen & System Audio Recording** (or **Microphone**). If the logo is stuck dim, dark, or at one level, open Lidglow again: it repairs the logo at launch. If it still looks wrong, quit Lidglow normally and restart your Mac.

## Build

Install Xcode or the macOS Command Line Tools (`xcode-select --install`), then run `Scripts/build.sh` from the repository root. The script builds, signs, and verifies `build/Lidglow.app` using the Mac's native architecture. Pass a path as the first argument to choose a different destination; relative paths resolve against the repository root. With Xcode, the build compiles the Liquid Glass app icon (`AppIcon.icon`) with `actool`; with only the Command Line Tools, it uses the flat `AppIcon.icns` instead. No third-party dependencies are required.

To run the synthetic beat detector check:

```sh
Scripts/test.sh
```

`Scripts/package.sh` builds the release files that the installer downloads: `build/release/Lidglow.zip` and `Lidglow.zip.sha256`. Published releases are built by the **Release** workflow in GitHub Actions instead, from `main`. See [RELEASE.md](RELEASE.md) for the release checklist.

The default signature is ad hoc, which changes with every build, so macOS asks for System Audio Recording permission again after each update. To avoid that for free, sign releases with a self-signed certificate:

1. Once, in **Keychain Access**, choose **Keychain Access → Certificate Assistant → Create a Certificate…**. Name it `Lidglow Self-Signed`, set **Identity Type** to **Self-Signed Root** and **Certificate Type** to **Code Signing**, and create it. Back it up (export it as a `.p12` with a password) and never commit it.
2. Build with `LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh`.

Every release signed this way has the same designated requirement, so macOS keeps the audio and microphone permissions. For a notarized release instead, set `LIDGLOW_SIGN_IDENTITY` to a `Developer ID Application` identity. Only that kind of identity enables the hardened runtime, the microphone entitlement it requires, and a secure timestamp. Then submit and staple the app before distributing it. [Apple’s notarization instructions](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Lidglow uses the documented Core Audio tap interface and a dynamically loaded, private CoreBrightness interface. Hardware compatibility depends on macOS. It can't be offered on the Mac App Store because of that private interface. [Apple’s Core Audio documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) · [LogoLight’s CoreBrightness research](https://github.com/Ark0N/LogoLight/blob/main/docs/corebrightnessd.md)

## Project layout

```
Sources/Lidglow/
  App/        Entry point, application delegate (status item, panel window, agent links), local log categories, the Check for Updates runner, and the uninstaller for Macs without a light-up logo
  Glow/       Glow modes, agent alerts (supported agents, link parsing, the pulse, and clicks in an agent's app), and the model that drives the logo each tick
  UI/         SwiftUI controls, the panel shown on Macs without a light-up logo, shared Liquid Glass styling, the borderless menu panel, the Settings window and its Agents section, and the animated laptop preview
  Audio/      Core Audio process tap, the playback watcher for automatic switching to Music, and the BeatMeter detector
  Hardware/   Lid logo control, detection of other apps controlling the logo, charging state, laptop finish detection, and the Objective-C CoreBrightness bridge
  Resources/  Info.plist (including the lidglow URL scheme), the app icon (AppIcon.icon, with AppIcon.icns as the fallback), the menu-bar glyphs, and the entitlements used for Developer ID (hardened-runtime) signing
Tests/BeatMeterTests/  Synthetic beat detector check
Scripts/      build.sh, test.sh, package.sh (release zip and checksum), install.sh (the Terminal installer, also bundled in the app for Check for Updates), and uninstall.sh (also bundled in the app for Uninstall on Macs without a light-up logo)
docs/         Architecture notes (behavior, source map, manual checks), the release checklist, the changelog, and the contributing, security, and privacy notes
.github/      Issue templates and the Release workflow, which builds a draft release from main when started by hand
```

## Proposing a change

1. **Start with an issue** for anything bigger than a typo or a small fix, so we can agree on the approach first. Use the bug report or feature request templates.
2. **Fork the repository and branch from `main`.** Keep each pull request to one change.
3. **Build and test on a Mac** with Xcode or the Command Line Tools:
   ```sh
   Scripts/build.sh
   Scripts/test.sh
   ```
   If you change the glow, the logo control, or the panel, also test on a MacBook Pro with a light-up Apple logo. Check that the logo goes back to macOS when you turn the switch off, quit, lock the screen, sleep, and close the lid. Say in the pull request what you checked and on which Mac.
4. **Open a pull request** that describes what changed and why.

## Project rules

These keep Lidglow safe to leave running all day. Pull requests that break them won't be merged.

- **Privacy:** no network access beyond the user-started Check for Updates, and no telemetry, recording, or new uses of the microphone. Audio is reduced to a level and discarded. See [PRIVACY.md](PRIVACY.md).
- **Energy:** keep the tick timer only as fast as each mode needs, avoid redundant hardware reads and redraws, and use events or notifications instead of polling.
- **Hardware safety:** keep hardware detection and the hand-back to macOS (switch off, quit, lock, sleep, lid close) working on every change to `Hardware/` or `Glow/`.
- **Docs:** when you add, move, or rename a source file, update the layout in this file and the source map in `docs/ARCHITECTURE.md`.
- **License header:** start each new source file with `// SPDX-License-Identifier: GPL-3.0-or-later` (or `# SPDX-License-Identifier: GPL-3.0-or-later` after the `#!` line of a script).
- Don't change the version numbers or the bundle ID. The maintainer does that at release time.

## Sign off your commits (DCO)

Lidglow is licensed under the [GNU General Public License v3.0 or later](../LICENSE). To keep every contribution clearly licensed, each commit must be signed off under the [Developer Certificate of Origin](https://developercertificate.org/). Signing off means you wrote the change, or otherwise have the right to submit it, under the project's license.

Add the sign-off with `-s`:

```sh
git commit -s -m "Describe the change."
```

This adds a line like `Signed-off-by: Your Name <you@example.com>` to the commit message. To sign off commits you already made on your branch, run `git rebase --signoff main` and force-push the branch.

## Security problems

Please don't open a public issue for a security problem. See [SECURITY.md](SECURITY.md).
