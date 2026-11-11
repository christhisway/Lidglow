# Lidglow handoff

This package captures Lidglow 1.0 (build 1). Open the extracted folder as a workspace and use `Sources/Lidglow/` as the source of truth. The bundled `Lidglow.app` is the compiled release. `docs/START HERE.txt` covers installation and first use.

## Current behavior

- Lidglow starts in the menu bar and opens its controls only when the icon is clicked. The panel anchors below the status item, clamps to the active display’s visible frame, and grows or shrinks smoothly from its top edge when controls appear or disappear. `GlowPanel` reports its natural height through `onGeometryChange` in the same layout pass, and `positionPanel` animates the window over the same 0.22 s as the SwiftUI fade, or without animation when Reduce Motion is on. The content is pinned to the top, both in SwiftUI and in a flipped container view, so only the bottom edge moves. It never scrolls: it's always sized to its content, and capped at the visible frame. Control-clicking or right-clicking the icon opens a context menu with Open Settings… and Quit Lidglow. A gear in the panel header, left of the switch, and ⌘, while the panel is focused also open Settings. The Settings window currently has an About section (version and project links). It closes with ⌘W.
- A switch in the panel's top-right corner turns Lidglow on or off. Off returns control to macOS (1.0's System mode, which migrates to the switch being off) and is the first-launch default. Modes are Standard, Breathe, and Music. Standard holds a fixed brightness, and zero brightness turns the logo off (this replaced 1.0's separate Off and Steady modes, which migrate to Standard). Breathe has Slow (8 s), Normal (5 s, the default), and Fast (3 s) speeds. Changing speed keeps the current point in the breath. The switch, selected mode, brightness, Breathe speed, Focus preset, sensitivity, and idle glow settings persist.
- Music uses a private Core Audio process tap to meter system playback, and detects transients per band. The Focus preset picks the bands. Bass (the default), Mids, and Treble each use one narrow band with 24 dB/octave Butterworth filters: 40–120 Hz, 300 Hz–3 kHz, and above 6 kHz. A hit counts only when that band carries at least 15% (fully at 50%) of the whole mix's onset energy, so leaks from other instruments don't flash the logo. Full is the original wide bass, drum, and treble detector. It uses no microphone, stores no recordings, and has no network code.
- Idle glow sets a base between hits and tracks, capped at 90% of the chosen peak so beats can still brighten the logo. The preview and physical LED both glow white.
- Each opening of the panel replays the laptop animation, then switches to a 2D logo that follows the live brightness. Reduce Motion goes directly to the 2D view.
- Lidglow steps aside for any other app that controls the logo. While it holds the logo, `LidLogo` compares each level reading with the way its last command should move the logo (up, down, or held still) over windows of at least 0.3 s, and reads the backlight mode once a second. Four unexplained moves within 20 seconds, or the backlight switched off, make it restore the logo and ask the user to quit the other app. `OtherLogoApps` also recognizes some logo apps by bundle ID (currently `co.supershort.backglow`, `app.logolight.LogoLight`, and `app.lidlight.Lidlight`): while one is running, Lidglow doesn't take control, names it in the panel, and takes over when it quits.
- Music and logo control pause on session lock, sleep, or lid closure. Normal quit restores macOS control, and so do `SIGTERM`, `SIGINT`, and `SIGHUP` (`kill`, Ctrl-C, or closing Terminal), which go through a normal quit. While Lidglow holds the logo, macOS's original backlight mode is saved in `UserDefaults` (`logoHeldOriginalMode`) and cleared by every restore. If it's still set at launch, after a crash, a force quit, or `kill -9`, `LidLogo.recoverAfterUnexpectedExit()` runs the restore sequence before anything reads the logo's state. Unsupported hardware uses the preview.

## Source map

| File | Role |
| --- | --- |
| `App/Main.swift` | Entry point; starts the accessory (menu-bar) app |
| `App/Log.swift` | `Logger` categories for local diagnostics (hardware and audio, no audio data) |
| `App/LidglowApp.swift` | Application delegate: status item and its context menu, panel window, positioning, event monitors, Settings window |
| `Glow/GlowMode.swift` | The modes and their icons, and the Breathe speeds |
| `Glow/GlowModel.swift` | Mode and settings state, tick loop, session lifecycle |
| `UI/GlowPanel.swift` | SwiftUI glow controls |
| `UI/GlassStyle.swift` | Shared Liquid Glass surfaces and the glass mode selector |
| `UI/LaptopPreview.swift` | SceneKit intro and live logo close-up |
| `UI/LaptopChassis.swift` | Laptop geometry and materials |
| `UI/MenuPanel.swift` | Borderless key-capable panel |
| `UI/SettingsWindow.swift` | The Settings window and its About section, built on open and released on close |
| `Audio/SystemMusic.swift` | Core Audio tap lifecycle |
| `Audio/BeatMeter.swift` | Band transient detection and the Focus (EQ) presets |
| `Hardware/LidLogo.swift` | Logo brightness transitions, original state tracking, restoration, recovery after an unexpected exit, and detection of other apps changing the logo |
| `Hardware/OtherLogoApps.swift` | Recognizes some other logo apps by bundle ID through launch and quit notifications |
| `Hardware/LaptopFinish.swift` | Automatic laptop finish detection |
| `Hardware/LogoBridge.h`, `.m` | IOKit hardware detection and dynamically loaded CoreBrightness calls |
| `Resources/Info.plist` | Version, bundle ID, menu-bar activation, deployment target, and audio permission text |

Paths are relative to `Sources/Lidglow/`. Outside it, `Scripts/build.sh` builds and signs the app, `Scripts/test.sh` runs `Tests/BeatMeterTests/BeatMeterCheck.swift` (synthetic checks for kick, snare, hi-hat, and guitar-note response, steady audio, and silence, for every Focus preset).

## Build and verify

Run `Scripts/build.sh` from the repository root. It writes `build/Lidglow.app` and leaves the bundled release in place. Run `Scripts/test.sh` for the beat check. See [the README](../README.md) for compiler setup and Developer ID signing. No package manager, external assets, or credentials are needed for local builds. Bump both version fields in `Resources/Info.plist` for a release and keep the bundle ID stable for an in-place update.

This build was exercised on the original Mac. Previous checks confirmed that the hardware reached several brightness levels and returned to macOS control, that playback reached Music mode, and that the panel stayed within the screen when expanded. The synthetic check covers 44.1, 48, and 96 kHz. Recheck actual hardware behavior and first launch on the recipient’s Mac.

For changes, quit other logo utilities and older Lidglow copies before testing. Launch from Finder and confirm that the menu panel opens below the icon with its controls fully visible. Test Music with playback and silence, toggle Idle glow, and check restoration when the switch is turned off and on quit. A Mac without a controllable logo can exercise the interface and audio preview.

## Compatibility and distribution

Logo control uses a private CoreBrightness interface and may need adjustment after macOS updates. Keep hardware detection and restoration intact when changing that path. Core Audio capture uses the public process tap API and needs per-app system audio permission.

The bundled release is arm64, ad-hoc signed, and unnotarized. For a release that can pass Gatekeeper’s standard distribution checks, use a Developer ID Application signature and Apple notarization. After notarization, staple the ticket to the app and then recreate the ZIP. [Apple’s notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
