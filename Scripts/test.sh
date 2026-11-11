#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds and runs the synthetic beat detector check. Usage: Scripts/test.sh
set -eu
cd -- "${0:A:h}/.."
mkdir -p build
xcrun swiftc -O -target "$(uname -m)-apple-macos27.0" -module-cache-path build/ModuleCache \
    Sources/Lidglow/Audio/BeatMeter.swift Tests/BeatMeterTests/BeatMeterCheck.swift \
    -o build/BeatMeterCheck
build/BeatMeterCheck
