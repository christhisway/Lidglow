// SPDX-License-Identifier: GPL-3.0-or-later

import os

/// Local diagnostic messages for bug reports, read with `log show` or Console. They record what
/// Lidglow did with the logo, the audio tap, and update checks, never audio data, and stay on this Mac.
extension Logger {
    private static let subsystem = "io.github.christhisway.lidglow"
    static let hardware = Logger(subsystem: subsystem, category: "hardware")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let update = Logger(subsystem: subsystem, category: "update")
}
