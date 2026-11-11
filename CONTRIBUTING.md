# Contributing to Lidglow

Thanks for helping. Lidglow is a small, free project, so the process is light.

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

- **Privacy:** no network code, telemetry, recording, or new uses of the microphone. Audio is reduced to a level and discarded. See [PRIVACY.md](PRIVACY.md).
- **Energy:** keep the tick timer only as fast as each mode needs, avoid redundant hardware reads and redraws, and use events or notifications instead of polling.
- **Hardware safety:** keep hardware detection and the hand-back to macOS (switch off, quit, lock, sleep, lid close) working on every change to `Hardware/` or `Glow/`.
- **Docs:** when you add, move, or rename a source file, update the layout in `README.md` and the source map in `docs/HANDOFF.md`.
- **License header:** start each new source file with `// SPDX-License-Identifier: GPL-3.0-or-later` (or `# SPDX-License-Identifier: GPL-3.0-or-later` after the `#!` line of a script).
- Don't change the version numbers or the bundle ID. The maintainer does that at release time.

## Sign off your commits (DCO)

Lidglow is licensed under the [GNU General Public License v3.0 or later](LICENSE). To keep every contribution clearly licensed, each commit must be signed off under the [Developer Certificate of Origin](https://developercertificate.org/). Signing off means you wrote the change, or otherwise have the right to submit it, under the project's license.

Add the sign-off with `-s`:

```sh
git commit -s -m "Describe the change."
```

This adds a line like `Signed-off-by: Your Name <you@example.com>` to the commit message. To sign off commits you already made on your branch, run `git rebase --signoff main` and force-push the branch.

## Security problems

Please don't open a public issue for a security problem. See [SECURITY.md](SECURITY.md).
