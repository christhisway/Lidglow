// SPDX-License-Identifier: GPL-3.0-or-later

import os

/// Local diagnostic messages for bug reports, read with `log show` or Console. They record what
/// Lidglow did with the logo, the audio tap, update checks, and agent alerts, never audio data, and stay on
/// this Mac.
extension Logger {
    private static let subsystem = "io.github.christhisway.lidglow"
    static let hardware = Logger(subsystem: subsystem, category: "hardware")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let update = Logger(subsystem: subsystem, category: "update")
    /// Which agent asked for attention and when it cleared. Agents send nothing else.
    static let agents = Logger(subsystem: subsystem, category: "agents")
}
