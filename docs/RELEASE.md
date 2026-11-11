# Releasing Lidglow

Releases go on [GitHub Releases](https://github.com/christhisway/Lidglow/releases). `Scripts/install.sh` downloads the two files each release must have: `Lidglow.zip` and `Lidglow.zip.sha256`. The **Release** workflow (`.github/workflows/release.yml`) builds them from `main` and creates the release. It runs only when you start it.

## One-time setup

The workflow signs with the same `Lidglow Self-Signed` identity as local builds, so macOS keeps the audio permission across updates. Give it a copy:

1. In **Keychain Access**, find the `Lidglow Self-Signed` certificate under **My Certificates**, Control-click it, and choose **Export**. Save it as a `.p12` with a strong password.
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
   - Keep `LidglowReleaseLabel` set to `Beta` for betas, so Settings → About reads, for example, "0.9.0 Beta (2)". Remove it for a stable release.
2. In `CHANGELOG.md`, move the **Unreleased** notes under a heading for the release: `## 0.9.0 Beta 1` for a beta, `## 1.0` for a stable release. A date may follow, as in `## 1.0 (2027-01-15)`. The workflow copies that section into the release notes.
3. Merge the branch into `main`.
4. In **Actions → Release → Run workflow**, keep the branch on `main` and enter the tag:
   - Betas: `v0.9.0-beta.1`, `v0.9.0-beta.2`, and so on.
   - Stable releases use three numbers with no suffix: 1.0 is `v1.0.0`.

   Leave **Publish right away** off to get a draft. Leave **Mark as a GitHub pre-release** off (see below).
5. The workflow stops without releasing anything if the tag doesn't match `Info.plist`, the tag or release already exists, the signing secrets are missing, the zip lacks `LICENSE`, or the app isn't signed by `Lidglow Self-Signed`. Otherwise it creates the release from the exact commit it built, titled for example **Lidglow 0.9.0 Beta 1**, with both files attached and the notes filled in from the template below.
6. Open the draft on the Releases page, read the notes, and click **Publish release**. Publishing creates the tag.
7. Test the update on a Mac that has the previous version: run the install command, then confirm that Lidglow reopens, controls the logo, and Music doesn't ask for permission again.

### Pre-releases and the install command

The install command downloads from `releases/latest`, and GitHub never counts drafts or pre-releases as the latest release. If every release so far is marked as a pre-release, the install command fails. So betas aren't marked as GitHub pre-releases: their title, tag, and Settings → About already say Beta. Only tick **Mark as a GitHub pre-release** for a test build that the install command should skip.

## Building a release locally

To build the same files by hand, for example to test packaging:

```sh
LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh
```

It packages whatever is checked out, including uncommitted changes, so don't upload a local build as a release. Check its signature by unzipping a copy of `build/release/Lidglow.zip` and running `codesign --verify --strict -dvv Lidglow.app`. Look for `Authority=Lidglow Self-Signed`.

## Release notes template

The workflow fills this in. For a release made by hand, use it as is:

```markdown
## Install or update

Run this in Terminal (it also updates an existing copy):

    curl -fsSL https://raw.githubusercontent.com/christhisway/Lidglow/main/Scripts/install.sh | bash

Requires Apple silicon and macOS 27 or later. Lidglow isn't notarized by Apple. The Terminal
installer opens it without a warning. If you download Lidglow.zip in a browser, open it once, then
click Open Anyway in System Settings → Privacy & Security.

## What's new

- …

## Verify

SHA-256 of Lidglow.zip: `<paste from Lidglow.zip.sha256>`

Built from <commit link> with `LIDGLOW_SIGN_IDENTITY="Lidglow Self-Signed" Scripts/package.sh`.
```
