# Lidglow

Lidglow is a native macOS menu-bar app for the illuminated Apple logo on MacBook Pro with PROLED XDR Display. The included app is an ad-hoc signed Apple silicon build.

## Use Lidglow

1. Quit any other app that controls the lid logo, so that only one app sends brightness commands. Lidglow also watches for this itself. If another app changes the logo while Lidglow holds it, Lidglow hands the logo back to macOS and asks you to quit that app. A few logo apps are recognized by name: while one of them is running, Lidglow leaves the logo alone, says so in its panel, and takes over when it quits.
2. Open **Lidglow.app** in Finder. Click the waveform circle in the macOS menu bar to open its controls, and turn on the switch in the panel's top-right corner. Click the gear next to the switch (or press ⌘, while the panel is open) for **Settings**, which shows the version and project links. Control-click or right-click the icon for **Open Settings…** and **Quit Lidglow**.
3. Choose **Music**, allow macOS system audio capture when prompted, and play music. By default Music reacts only to **Spotify** and **Apple Music**. Choose other apps, or **React to all apps**, in **Settings → Music**. **Brightness** sets the peak glow and **Sensitivity** adjusts how strongly hits drive it. **Focus** picks what drives the glow: **Bass** (kick drums and bass lines, the default), **Mids** (vocals, guitars, keys, and snares), **Treble** (hi-hats and cymbals), or **Full** (the whole mix). Turn on **Idle glow** to keep a base between beats and tracks. Use **Idle brightness** to raise or lower it.
4. Turn the switch off to hand brightness back to macOS. **Standard** holds the logo at the chosen brightness (drag **Brightness** all the way down to turn it off), and **Breathe** fades it up and down. Choose a **Speed** of Slow, Normal, or Fast under Brightness.

If Music remains on “Waiting for music” during playback, check that the app you're playing from is checked in **Settings → Music**. Otherwise use **System Audio Settings…** to check Lidglow’s access under **Privacy & Security → Screen & System Audio Recording**. After changing access, reselect **Music** or quit and reopen Lidglow.

If the lid logo is stuck dim, dark, or at one level (for example after Lidglow crashed or was force quit), open Lidglow again. It notices that it didn't hand the logo back and repairs it at launch, even with the switch off. If the logo still looks wrong, quit Lidglow normally and restart your Mac.

Audio processing runs locally through a private Core Audio tap. The app reduces playback to a level driven by hits in the chosen Focus and discards the samples. Hardware modes pause when the session locks, the display sleeps, or the lid closes. Older Macs can use the in-panel preview.

## Updating

Lidglow never checks for updates itself, because it has no network code. New versions are posted on [GitHub Releases](https://github.com/christhisway/Lidglow/releases) with release notes, also kept in [CHANGELOG.md](CHANGELOG.md). To be notified, click **Watch → Custom → Releases** on the repository page. **Settings → About → View Releases** opens the page in your browser.

To update, quit Lidglow from the panel or its Control-click menu so it hands the logo back to macOS, then replace `Lidglow.app` with the new version and open it. Because this build is ad-hoc signed, macOS may ask for System Audio Recording permission again after an update.

## Privacy

Lidglow uses no microphone, records nothing, and has no network code. Music mode reduces your Mac's audio output to a brightness level as it plays and then discards it. Settings are stored only in macOS preferences. Read the full [privacy statement](PRIVACY.md).

## Reporting bugs

Lidglow has no network code, so it never sends crash reports or diagnostics anywhere. To report a problem, [open an issue](https://github.com/christhisway/Lidglow/issues/new/choose) and include what you can of the following:

- **Crash reports:** open the Console app and choose **Crash Reports**, or look in `~/Library/Logs/DiagnosticReports/` for files whose names start with `Lidglow`.
- **Recent logs:** run this in Terminal shortly after the problem happens:

  ```sh
  log show --last 10m --info --predicate 'subsystem == "io.github.christhisway.lidglow"'
  ```

  Lidglow logs when it takes and releases control of the logo, the result of its hardware check, and when the system audio tap starts, stops, or fails. The logs contain no audio and stay on your Mac until you share them.

## Project layout

```
Sources/Lidglow/
  App/        Entry point, application delegate (status item, panel window), and local log categories
  Glow/       Glow modes and the model that drives the logo each tick
  UI/         SwiftUI controls, shared Liquid Glass styling, the borderless menu panel, the Settings window, and the animated laptop preview
  Audio/      Core Audio process tap and the BeatMeter detector
  Hardware/   Lid logo control, detection of other apps controlling the logo, laptop finish detection, and the Objective-C CoreBrightness bridge
  Resources/  Info.plist
Tests/BeatMeterTests/  Synthetic beat detector check
Scripts/      build.sh and test.sh
docs/         Handoff notes and the end-user install guide
```

## Build

Install Xcode or the macOS Command Line Tools (`xcode-select --install`), then run `Scripts/build.sh` from the repository root. The script builds, signs, and verifies `build/Lidglow.app` using the Mac's native architecture. Pass a path as the first argument to choose a different destination; relative paths resolve against the repository root. No third-party dependencies are required.

To run the synthetic beat detector check:

```sh
Scripts/test.sh
```

The default signature is ad hoc. For a notarization candidate, set `LIDGLOW_SIGN_IDENTITY` to a Developer ID Application identity installed in your keychain. This enables the hardened runtime and secure timestamp. Submit and staple the resulting app before distributing it as a notarized release. [Apple’s notarization instructions](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Lidglow uses the documented Core Audio tap interface and a dynamically loaded, private CoreBrightness interface. Hardware compatibility depends on macOS. [Apple’s Core Audio documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) · [LogoLight’s CoreBrightness research](https://github.com/Ark0N/LogoLight/blob/main/docs/corebrightnessd.md)
