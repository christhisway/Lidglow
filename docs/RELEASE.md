# Releasing Lidglow

Releases go on [GitHub Releases](https://github.com/christhisway/Lidglow/releases). `Scripts/install.sh` downloads the two files each release must have: `Lidglow.zip` and `Lidglow.zip.sha256`. The **Release** workflow (`.github/workflows/release.yml`) builds them from `main` and creates the release as a draft. It runs only when you start it.

## Signing

Until the signing secrets below are added, the workflow signs releases **ad hoc**. That works, but an ad hoc signature changes with every build, so macOS asks users for System Audio Recording (and, if they use it, Microphone) permission again after each update. macOS might also treat the updated app as a new login item and turn Open at Login off. That hasn't been tested yet. The release notes mention both. Adding a stable identity is tracked post-beta in #69.

### Optional: a stable signing identity

With the secrets set, the workflow signs with the `Lidglow Self-Signed` identity instead, so macOS keeps the permissions across updates. The first update after switching from ad hoc still asks once.

1. If you don't have the identity yet, create it as described under **Build** in the README. Then, in **Keychain Access**, find the `Lidglow Self-Signed` certificate under **My Certificates**, Control-click it, and choose **Export**. Save it as a `.p12` with a strong password.
2. In Terminal, copy it as base64: `base64 -i "Lidglow Self-Signed.p12" | pbcopy`.
3. In the repository's **Settings → Secrets and variables → Actions**, add two repository secrets:
   - `LIDGLOW_SIGNING_P12`: paste the base64 text.
   - `LIDGLOW_SIGNING_P12_PASSWORD`: the export password.
4. Delete the exported `.p12` and its base64 copy. Keep your usual backup of the identity somewhere safe, and never commit it.

Always export the same identity. A new certificate changes the app's designated requirement, and every user gets asked for audio permission again.

## Checklist

1. On a branch, bump both `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/Lidglow/Resources/Info.plist`. Never change the bundle ID.
   - `CFBundleShortVersionString` stays numeric: 0.9.x for betas, 1.0 for the first stable release.
   - `CFBundleVersion` is a whole number that goes up by one every release, betas included, and never resets. Build 1 was the pre-beta `v1.0` tag, and 0.9.0 Beta is build 2.
   - Keep `LidglowReleaseLabel` set to `Beta` for betas. Remove it for a stable release. The Release workflow adds the beta number from the tag to the release build only, so in Beta 1 Settings → About reads "0.9.0 Beta 1 (2)". Local builds read "0.9.0 Beta (2)".
2. In `docs/CHANGELOG.md`, move the **Unreleased** notes under a heading for the release: `## 0.9.0 Beta 1` for a beta, `## 1.0` for a stable release. A date may follow, as in `## 1.0 (2027-01-15)`. The workflow copies that section into the release notes.
3. Merge the branch into `main`.
4. In **Actions → Release → Run workflow**, keep the branch on `main` and enter the tag:
   - Betas: `v0.9.0-beta.1`, `v0.9.0-beta.2`, and so on.
   - Stable releases use three numbers with no suffix: 1.0 is `v1.0.0`.
5. The workflow stops without releasing anything if the tag doesn't match `Info.plist`, the tag or release already exists, only one of the two signing secrets is set, the zip lacks `LICENSE`, the signature isn't the expected one (`Lidglow Self-Signed` with the secrets, ad hoc without them), or the built app's release label doesn't match the tag. Otherwise it creates a **draft** release from the exact commit it built, titled for example **Lidglow 0.9.0 Beta 1**, with both files attached and the notes filled in from the template below. Betas (`LidglowReleaseLabel` is `Beta`) are always marked as pre-releases, and stable releases never are.
6. Open the draft on the Releases page, read the notes, and click **Publish release**. Publishing creates the tag. A repository ruleset lets only admins create, move, or delete `v*` tags, which is why the workflow stops at a draft: it runs as `github-actions[bot]`, which can't create the tag.
7. Test the update on a Mac that has the previous version: run the install command from the release notes, then confirm that Lidglow reopens, controls the logo, and Music doesn't ask for permission again. If Open at Login was on, check that it's still on in Settings → General and that Lidglow opens after a restart.

### Pre-releases and the install command

The install command with no version installs GitHub's latest release, which never includes drafts or pre-releases. So betas are only installed by name (`… | bash -s -- v0.9.0-beta.1`), and every release's notes give the command with its own tag. Until 1.0 is out, the command with no version says there's no stable release yet and shows how to install a beta.

## Building a release locally

To build the same files by hand, for example to test packaging:

```sh
Scripts/package.sh
```

That signs ad hoc. To sign with the stable identity, run `LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh` instead. It packages whatever is checked out, including uncommitted changes, so don't upload a local build as a release. Check its signature by unzipping a copy of `build/release/Lidglow.zip` and running `codesign --verify --strict -dvv Lidglow.app`. Look for `Signature=adhoc`, or `Authority=Lidglow Self-Signed` with the identity.

## Release notes template

The workflow fills this in, replacing `<tag>` with the release's tag. For a release made by hand, use it the same way:

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

Built from <commit link> with `Scripts/package.sh`. It's signed ad hoc, so macOS asks for System Audio Recording permission again after you update. Open at Login might also turn off after an update. If it does, turn it back on in Settings → General.
```

With a stable identity, the last line instead reads:

```markdown
Built from <commit link> with `LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh`.
```
