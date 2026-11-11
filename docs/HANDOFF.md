# Lidglow handoff

This package captures Lidglow 1.0 (build 1). Open the extracted folder as a workspace and use `Sources/Lidglow/` as the source of truth. The bundled `Lidglow.app` is the compiled release. `docs/START HERE.txt` covers installation and first use.

## Current behavior

- Lidglow starts in the menu bar and opens its controls only when the icon is clicked. The panel anchors below the status item, clamps to the active display’s visible frame, and expands down when Music controls appear. It scrolls when vertical space is limited. Control-clicking or right-clicking the icon opens a context menu with Open Settings… and Quit Lidglow. A gear in the panel header, left of the switch, and ⌘, while the panel is focused also open Settings. The Settings window currently has an About section (version and project links). It closes with ⌘W.
- A switch in the panel's top-right corner turns Lidglow on or off. Off returns control to macOS (1.0's System mode, which migrates to the switch being off) and is the first-launch default. Modes are Standard, Breathe, and Music. Standard holds a fixed brightness, and zero brightness turns the logo off (this replaced 1.0's separate Off and Steady modes, which migrate to Standard). The switch, selected mode, brightness, sensitivity, and idle glow settings persist.
- Music uses a private Core Audio process tap to meter system playback, with separate bass and drum transient detection. It uses no microphone, stores no recordings, and has no network code.
- Idle glow sets a base between hits and tracks, capped at 90% of the chosen peak so beats can still brighten the logo. The preview and physical LED both glow white.
- Each opening of the panel replays the laptop animation, then switches to a 2D logo that follows the live brightness. Reduce Motion goes directly to the 2D view.
- Music and logo control pause on session lock, sleep, or lid closure. Normal quit restores macOS control. Unsupported hardware uses the preview.

## Source map

| File | Role |
| --- | --- |
| `App/Main.swift` | Entry point; starts the accessory (menu-bar) app |
| `App/LidglowApp.swift` | Application delegate: status item and its context menu, panel window, positioning, event monitors, Settings window |
| `Glow/GlowMode.swift` | The modes and their icons |
| `Glow/GlowModel.swift` | Mode and settings state, tick loop, session lifecycle |
| `UI/GlowPanel.swift` | SwiftUI glow controls |
| `UI/GlassStyle.swift` | Shared Liquid Glass surfaces and the glass mode selector |
| `UI/LaptopPreview.swift` | SceneKit intro and live logo close-up |
| `UI/LaptopChassis.swift` | Laptop geometry and materials |
| `UI/MenuPanel.swift` | Borderless key-capable panel |
| `UI/SettingsWindow.swift` | The Settings window with its General (Open at Login) and About sections, built on open and released on close |
| `Audio/SystemMusic.swift` | Core Audio tap lifecycle |
| `Audio/BeatMeter.swift` | Bass and drum transient detection |
| `Hardware/LidLogo.swift` | Logo brightness transitions, original state tracking, and restoration |
| `Hardware/LaptopFinish.swift` | Automatic laptop finish detection |
| `Hardware/LogoBridge.h`, `.m` | IOKit hardware detection and dynamically loaded CoreBrightness calls |
| `Resources/Info.plist` | Version, bundle ID, menu-bar activation, deployment target, and audio permission text |

Paths are relative to `Sources/Lidglow/`. Outside it, `Scripts/build.sh` builds and signs the app, `Scripts/package.sh` makes the release zip and its SHA-256, `Scripts/install.sh` is the Terminal installer and updater, `docs/RELEASE.md` is the release checklist, `Scripts/test.sh` runs `Tests/BeatMeterTests/BeatMeterCheck.swift` (synthetic checks for kick and snare response, steady audio, and silence).

## Build and verify

Run `Scripts/build.sh` from the repository root. It writes `build/Lidglow.app` and leaves the bundled release in place. Run `Scripts/test.sh` for the beat check. See [the README](../README.md) for compiler setup and Developer ID signing. No package manager, external assets, or credentials are needed for local builds. Bump both version fields in `Resources/Info.plist` for a release and keep the bundle ID stable for an in-place update.

This build was exercised on the original Mac. Previous checks confirmed that the hardware reached several brightness levels and returned to macOS control, that playback reached Music mode, and that the panel stayed within the screen when expanded. The synthetic check covers 44.1, 48, and 96 kHz. Recheck actual hardware behavior and first launch on the recipient’s Mac.

For changes, quit other logo utilities and older Lidglow copies before testing. Launch from Finder and confirm that the menu panel opens below the icon with its controls fully visible. Test Music with playback and silence, toggle Idle glow, and check restoration when the switch is turned off and on quit. A Mac without a controllable logo can exercise the interface and audio preview.

## Compatibility and distribution

Logo control uses a private CoreBrightness interface and may need adjustment after macOS updates. Keep hardware detection and restoration intact when changing that path. Core Audio capture uses the public process tap API and needs per-app system audio permission.

Releases are arm64 and unnotarized on purpose (no paid Developer ID). They're installed with `Scripts/install.sh`, which downloads with `curl` so no quarantine attribute is set, and verifies the published SHA-256. Sign releases with the owner's self-signed `Lidglow Self-Signed` identity (`LIDGLOW_SIGN_IDENTITY`) so the audio permission survives updates. Open at Login uses `SMAppService.mainApp`. The steps below only apply if a Developer ID is ever used. For a release that can pass Gatekeeper’s standard distribution checks, use a Developer ID Application signature and Apple notarization. After notarization, staple the ticket to the app and then recreate the ZIP. [Apple’s notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
