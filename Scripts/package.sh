#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds a release zip for GitHub Releases. Usage: Scripts/package.sh
# Writes build/release/Lidglow.zip and build/release/Lidglow.zip.sha256, the two files that
# Scripts/install.sh downloads. Set LIDGLOW_SIGN_IDENTITY to sign with a stable identity (see README).
set -eu
cd -- "${0:A:h}/.."
release="build/release"
# Every release must carry the license.
if [[ ! -f LICENSE ]]; then
    print -u2 "package.sh: LICENSE is missing, so no release zip was made."
    exit 1
fi
rm -rf -- "$release"
mkdir -p "$release/stage"
Scripts/build.sh "$release/stage/Lidglow.app"
cp LICENSE "$release/stage/"
if [[ -f docs/PRIVACY.md ]]; then cp docs/PRIVACY.md "$release/stage/"; fi
(cd "$release/stage" && ditto -c -k --sequesterRsrc --keepParent Lidglow.app ../Lidglow.zip)
if [[ -n "$(ls "$release/stage" | grep -v '^Lidglow.app$')" ]]; then
    (cd "$release/stage" && zip -q ../Lidglow.zip $(ls | grep -v '^Lidglow.app$'))
fi
rm -rf -- "$release/stage"
(cd "$release" && shasum -a 256 Lidglow.zip > Lidglow.zip.sha256)
cat "$release/Lidglow.zip.sha256"
