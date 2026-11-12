// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import os
import ServiceManagement

@main
struct Main {
    static func main() {
        // Scripts/uninstall.sh runs the app this way to remove its login item before deleting it. It exits
        // before anything touches the logo or the menu bar, so it works while Lidglow is running.
        if CommandLine.arguments.dropFirst().first == "--unregister-login-item" {
            try? SMAppService.mainApp.unregister()
            exit(0)
        }
        // Two copies would fight over the logo, so a second one quits before it recovers, reads, or takes
        // the logo, and before it adds a menu-bar icon. The copy already running keeps the logo, and the
        // link that launched this one, if any, is dropped.
        if let other = otherRunningCopy() {
            let path = other.bundleURL?.path ?? "an unknown location"
            Logger.hardware.notice(
                "Another Lidglow is already running (process \(other.processIdentifier, privacy: .public) from \(path, privacy: .public)), so this copy quits.")
            FileHandle.standardError.write(Data(
                "Lidglow is already running from \(path), so this copy quits. Quit that one first to run this one.\n".utf8))
            exit(0)
        }
        // Show tooltips after one second of hover instead of the system's longer default. Registered,
        // not saved, so it only applies while Lidglow runs.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 1000])
        let app = NSApplication.shared
        let delegate = LidglowApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Another running Lidglow for this user, from any location, if there is one. Agent hooks check for a
    /// running Lidglow with `pgrep`, but `open` sends their link to the copy LaunchServices has registered
    /// for `lidglow://`, so with two copies on the Mac a hook can launch the second one (#81).
    private static func otherRunningCopy() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let current = getpid()
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { app in
            let pid = app.processIdentifier
            // A copy that just quit can stay listed for a moment, for example when Check for Updates opens
            // the new version right after the old one exits, so only a process that still exists counts.
            return pid > 0 && pid != current && !app.isTerminated && kill(pid, 0) == 0
        }
    }
}
