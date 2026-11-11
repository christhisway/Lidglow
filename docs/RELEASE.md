# Releasing Lidglow

Releases go on [GitHub Releases](https://github.com/christhisway/Lidglow/releases). `Scripts/install.sh` downloads the two files each release must have: `Lidglow.zip` and `Lidglow.zip.sha256`.

## Checklist

1. On `main`, bump both `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/Lidglow/Resources/Info.plist`. Never change the bundle ID.
2. Move the **Unreleased** notes in `CHANGELOG.md` under the new version.
3. Build with the stable identity, so macOS keeps the audio permission across updates:
   ```sh
   LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh
   ```
4. Check the signature: unzip a copy of `build/release/Lidglow.zip` and run `codesign --verify --strict -dvv Lidglow.app`. Look for `Authority=Lidglow Self-Signed`.
5. Tag the commit (for example `git tag v0.9.0-beta.1 && git push origin v0.9.0-beta.1`).
6. Create the release from that tag. Upload `build/release/Lidglow.zip` and `build/release/Lidglow.zip.sha256`, and use the notes template below. Mark beta builds as a pre-release.
7. Test the update on a Mac that has the previous version: run the install command, then confirm that Lidglow reopens, controls the logo, and Music doesn't ask for permission again.

## Release notes template

```markdown
## Install or update

Run this in Terminal (it also updates an existing copy):

    curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash

Requires Apple silicon and macOS 14.2 or later. Lidglow isn't notarized by Apple. The Terminal
installer opens it without a warning. If you download Lidglow.zip in a browser, open it once, then
click Open Anyway in System Settings → Privacy & Security.

## What's new

- …

## Verify

SHA-256 of Lidglow.zip: `<paste from Lidglow.zip.sha256>`

Built from <commit link> with `LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh`.
```
