# Lidglow – Claude Code guidelines

## Git workflow

- **Never push directly to `main`** unless the project owner explicitly says so for that specific change.
- **Every task gets its own new branch** named `christhisway/<task-name>` (short, kebab-case, e.g. `christhisway/fix-login-crash`).
- Branch from the latest `main`, commit the work there, and push that branch. The project owner reviews and merges into `main` themselves.
- Don't merge into `main` yourself and don't open a pull request unless asked.
- Commit messages are a single imperative sentence ending in a period (e.g. `Skip per-tick logo level reads once the glow has settled.`).

## Build and test

- `Scripts/build.sh` builds, signs, and verifies `build/Lidglow.app`. `Scripts/test.sh` runs the synthetic beat detector check.
- Both require macOS with Xcode or the Command Line Tools. In a Linux or cloud environment they can't run: say so plainly rather than claiming a change was built or tested.
- When `GlowModel`, `LidLogo`, or the panel changes, say what still needs a manual check on real hardware (see "Build and verify" in `docs/HANDOFF.md`).

## Project rules

- **Privacy:** Lidglow has no network code and stores no audio. It uses the microphone only when the user chooses Microphone as Music's source (off by default, approved by the owner), and only while Music runs. Audio samples from any source are reduced to a level and discarded. Keep it that way; never add networking, telemetry, recording, or any other use of the microphone without the owner's explicit sign-off.
- **Energy:** This is an always-running menu-bar app, so energy impact matters. Keep the tick timer only as fast as each mode needs, avoid redundant hardware reads and redraws, and don't add polling where an event or notification works.
- **Hardware safety:** Logo control goes through a private CoreBrightness interface. Keep hardware detection and restore-to-macOS behavior (switch off, quit, lock, sleep, lid close) intact on every change to `Hardware/` or `Glow/`.
- **Versioning:** Only bump `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/Lidglow/Resources/Info.plist` when asked, and always bump both. Never change the bundle ID.
- **Docs:** When adding, moving, or renaming source files, update the layout in `README.md` and the source map in `docs/HANDOFF.md`.
