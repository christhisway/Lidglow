# Lidglow handoff

This package captures Lidglow 1.4 (build 5). Open the extracted folder as a workspace and use `Source/` as the source of truth. The bundled `Lidglow.app` is the compiled release. `START HERE.txt` covers installation and first use.

## Current behavior

- Lidglow starts in the menu bar and opens its controls only when the icon is clicked. The panel anchors below the status item, clamps to the active display’s visible frame, and expands down when Music controls appear. It scrolls when vertical space is limited.
- Modes are System, Off, Steady, Breathe, and Music. System returns control to macOS. A fresh launch starts in System. Brightness, sensitivity, and idle glow settings persist.
- Music uses a private Core Audio process tap to meter system playback, with separate bass and drum transient detection. It uses no microphone, stores no recordings, and has no network code.
- Idle glow sets a base between hits and tracks, capped at 90% of the chosen peak so beats can still brighten the logo. Amber is a preview tint. The physical LED emits white.
- Music and logo control pause on session lock, sleep, or lid closure. Normal quit restores macOS control. Unsupported hardware uses the preview.

## Source map

| File | Role |
| --- | --- |
| `App.swift` | AppKit status item and panel, SwiftUI controls, mode and settings state, session lifecycle |
| `Music.swift` | Core Audio tap lifecycle and `BeatMeter` |
| `Logo.swift` | Logo brightness transitions, original state tracking, and restoration |
| `LogoBridge.h`, `LogoBridge.m` | IOKit hardware detection and dynamically loaded CoreBrightness calls |
| `Info.plist` | Version, bundle ID, menu-bar activation, deployment target, and audio permission text |
| `build.sh` | Command-line build and signing |
| `Tests/BeatMeterCheck.swift` | Synthetic checks for kick and snare response, steady audio, and silence |

## Build and verify

Run `cd Source && ./build.sh` from the package root. It writes `build/Lidglow.app` and leaves the bundled release in place. See [the source README](Source/README.md) for compiler setup, the beat test command, and Developer ID signing. No package manager, external assets, or credentials are needed for local builds. Bump both version fields in `Info.plist` for a release and keep the bundle ID stable for an in-place update.

This build was exercised on the original Mac. Previous checks confirmed that the hardware reached several brightness levels and returned to macOS control, that playback reached Music mode, and that the panel stayed within the screen when expanded. The synthetic check covers 44.1, 48, and 96 kHz. Recheck actual hardware behavior and first launch on the recipient’s Mac.

For changes, quit other logo utilities and older Lidglow copies before testing. Launch from Finder and confirm that the menu panel opens below the icon with its controls fully visible. Test Music with playback and silence, toggle Idle glow, and check restoration in System mode and on quit. A Mac without a controllable logo can exercise the interface and audio preview.

## Compatibility and distribution

Logo control uses a private CoreBrightness interface and may need adjustment after macOS updates. Keep hardware detection and restoration intact when changing that path. Core Audio capture uses the public process tap API and needs per-app system audio permission.

The bundled release is arm64, ad-hoc signed, and unnotarized. For a release that can pass Gatekeeper’s standard distribution checks, use a Developer ID Application signature and Apple notarization. After notarization, staple the ticket to the app and then recreate the ZIP. [Apple’s notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
