# Lidglow

Lidglow is a native macOS menu-bar app for the illuminated Apple logo on MacBook Pro with PROLED XDR Display. The included app is an ad-hoc signed Apple silicon build.

## Install

Lidglow needs a Mac with Apple silicon and macOS 14.2 or later. Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash
```

The script checks your Mac, downloads the latest release from GitHub Releases, verifies its SHA-256 checksum, quits any running Lidglow normally so the logo goes back to macOS, installs `Lidglow.app` in `/Applications` (or `~/Applications` if `/Applications` isn't writable), and opens it. Run the same command again to update. It doesn't use `sudo`.

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

It quits Lidglow normally so the logo goes back to macOS, removes its login item, deletes `Lidglow.app` and its settings. To also reset the System Audio Recording permission, add `-s -- --reset-permission` after `bash`.

To uninstall by hand:

1. **Quit Lidglow first** with **Quit** in the panel or its Control-click menu, so it hands the logo back to macOS. Deleting the app while it's running can leave the logo stuck.
2. If **Open at Login** is on, turn it off in **Settings → General**, or remove Lidglow in **System Settings → General → Login Items**.
3. Delete `Lidglow.app` from `/Applications` (or wherever you put it).
4. Optional cleanup:
   - Remove its settings: `defaults delete io.github.christhisway.lidglow`
   - Remove its audio permission in **System Settings → Privacy & Security → Screen & System Audio Recording**, or with `tccutil reset AudioCapture io.github.christhisway.lidglow` (before deleting the app).
5. If the logo still looks wrong afterwards, restart your Mac.

## Use Lidglow

1. Quit Backglow or any other utility controlling the lid logo so that only one app sends brightness commands.
2. Open **Lidglow.app** (the installer opens it for you). Click the waveform circle in the macOS menu bar to open its controls, and turn on the switch in the panel's top-right corner. Click the gear next to the switch (or press ⌘, while the panel is open) for **Settings**, which shows the version and project links. Control-click or right-click the icon for **Open Settings…** and **Quit Lidglow**.
3. Choose **Music**, allow macOS system audio capture when prompted, and play music. **Brightness** sets the peak glow and **Sensitivity** adjusts how strongly bass and drum hits drive it. Turn on **Idle glow** to keep a base between beats and tracks. Use **Idle brightness** to raise or lower it.
4. Turn the switch off to hand brightness back to macOS. **Standard** holds the logo at the chosen brightness (drag **Brightness** all the way down to turn it off), and **Breathe** fades it slowly.

If Music remains on “Waiting for music” during playback, use **System Audio Settings…** to check Lidglow’s access under **Privacy & Security → Screen & System Audio Recording**. After changing access, reselect **Music** or quit and reopen Lidglow.

Audio processing runs locally through a private Core Audio tap. The app reduces playback to a level driven by bass and drum hits and discards the samples. Hardware modes pause when the session locks, the display sleeps, or the lid closes. Older Macs can use the in-panel preview.

## Project layout

```
Sources/Lidglow/
  App/        Entry point and application delegate (status item, panel window)
  Glow/       Glow modes and the model that drives the logo each tick
  UI/         SwiftUI controls, shared Liquid Glass styling, the borderless menu panel, the Settings window, and the animated laptop preview
  Audio/      Core Audio process tap and the BeatMeter detector
  Hardware/   Lid logo control, laptop finish detection, and the Objective-C CoreBrightness bridge
  Resources/  Info.plist
Tests/BeatMeterTests/  Synthetic beat detector check
Scripts/      build.sh, test.sh, package.sh (release zip and checksum), install.sh (the Terminal installer), and uninstall.sh
docs/         Handoff notes, the end-user install guide, and the release checklist
```

## Build

Install Xcode or the macOS Command Line Tools (`xcode-select --install`), then run `Scripts/build.sh` from the repository root. The script builds, signs, and verifies `build/Lidglow.app` using the Mac's native architecture. Pass a path as the first argument to choose a different destination; relative paths resolve against the repository root. No third-party dependencies are required.

To run the synthetic beat detector check:

```sh
Scripts/test.sh
```

`Scripts/package.sh` builds the release files that the installer downloads: `build/release/Lidglow.zip` and `Lidglow.zip.sha256`. See [docs/RELEASE.md](docs/RELEASE.md) for the release checklist.

The default signature is ad hoc, which changes with every build, so macOS asks for System Audio Recording permission again after each update. To avoid that for free, sign releases with a self-signed certificate:

1. Once, in **Keychain Access**, choose **Keychain Access → Certificate Assistant → Create a Certificate…**. Name it `Lidglow Self-Signed`, set **Identity Type** to **Self-Signed Root** and **Certificate Type** to **Code Signing**, and create it. Back it up (export it as a `.p12` with a password) and never commit it.
2. Build with `LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh`.

Every release signed this way has the same designated requirement, so macOS keeps the audio permission. For a notarized release instead, set `LIDGLOW_SIGN_IDENTITY` to a `Developer ID Application` identity. Only that kind of identity enables the hardened runtime and secure timestamp. Then submit and staple the app before distributing it. [Apple’s notarization instructions](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Lidglow uses the documented Core Audio tap interface and a dynamically loaded, private CoreBrightness interface. Hardware compatibility depends on macOS. [Apple’s Core Audio documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) · [LogoLight’s CoreBrightness research](https://github.com/Ark0N/LogoLight/blob/main/docs/corebrightnessd.md)
