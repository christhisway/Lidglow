import os

/// Local diagnostic messages for bug reports, read with `log show` or Console. They record what
/// Lidglow did with the logo and the audio tap, never audio data, and stay on this Mac.
extension Logger {
    private static let subsystem = "io.github.christhisway.lidglow"
    static let hardware = Logger(subsystem: subsystem, category: "hardware")
    static let audio = Logger(subsystem: subsystem, category: "audio")
}
