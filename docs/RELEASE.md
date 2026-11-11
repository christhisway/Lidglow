# Releasing Lidglow

Releases go on [GitHub Releases](https://github.com/christhisway/Lidglow/releases). `Scripts/install.sh` downloads the two files each release must have: `Lidglow.zip` and `Lidglow.zip.sha256`.

## Checklist

1. On `main`, bump both `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/Lidglow/Resources/Info.plist`. Never change the bundle ID.
   - `CFBundleShortVersionString` stays numeric: 0.9.x for betas, 1.0 for the first stable release.
   - `CFBundleVersion` is a whole number that goes up by one every release, betas included, and never resets. Build 1 was the pre-beta `v1.0` tag, and 0.9.0 Beta is build 2.
   - Keep `LidglowReleaseLabel` set to `Beta` for betas, so Settings → About reads, for example, "0.9.0 Beta (2)". Remove it for a stable release.
2. Move the **Unreleased** notes in `docs/CHANGELOG.md` under the new version.
3. Build with the stable identity, so macOS keeps the audio permission across updates:
   ```sh
   LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh
   ```
4. Check the signature: unzip a copy of `build/release/Lidglow.zip` and run `codesign --verify --strict -dvv Lidglow.app`. Look for `Authority=Lidglow Self-Signed`.
5. Tag the commit (for example `git tag v0.9.0-beta.1 && git push origin v0.9.0-beta.1`). Number betas of the same version `-beta.1`, `-beta.2`, and so on. Stable releases drop the suffix (`v1.0.0`). A repository ruleset lets only admins create, move, or delete `v*` tags.
6. Create the release from that tag. Upload `build/release/Lidglow.zip` and `build/release/Lidglow.zip.sha256`, and use the notes template below, replacing `<tag>` with the release's tag. Title betas to match the tag, for example **Lidglow 0.9.0 Beta 1**, and mark them as a pre-release. The install command with no version installs GitHub's latest release, which never includes pre-releases, so betas are only installed by name.
7. Test the update on a Mac that has the previous version: run the install command from the release notes, then confirm that Lidglow reopens, controls the logo, and Music doesn't ask for permission again.

## Release notes template

```markdown
## Install or update

Run this in Terminal (it also updates an existing copy):

    curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash -s -- <tag>

Requires Apple silicon and macOS 27 or later. Lidglow isn't notarized by Apple. The Terminal
installer opens it without a warning. If you download Lidglow.zip in a browser, open it once, then
click Open Anyway in System Settings → Privacy & Security.

## What's new

- …

## Verify

SHA-256 of Lidglow.zip: `<paste from Lidglow.zip.sha256>`

Built from <commit link> with `LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh`.
```
