# Lidglow

Lidglow is a native macOS menu-bar app for the illuminated Apple logo on MacBook Pro with PROLED XDR Display. The included app is an ad-hoc signed Apple silicon build.

## Use Lidglow

1. Quit Backglow or any other utility controlling the lid logo so that only one app sends brightness commands.
2. Open **Lidglow.app** in Finder. Click the waveform circle in the macOS menu bar to open its controls, and turn on the switch in the panel's top-right corner. Click the gear next to the switch (or press ⌘, while the panel is open) for **Settings**, which shows the version and project links. Control-click or right-click the icon for **Open Settings…** and **Quit Lidglow**.
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
