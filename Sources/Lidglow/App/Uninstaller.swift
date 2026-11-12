// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import os

/// The Uninstall button on a Mac with no light-up logo. After the user confirms, the copy of
/// `Scripts/uninstall.sh` bundled in the app runs as `uninstall.sh --from-app`. It checks that it can remove
/// this copy, then waits in the background for Lidglow to quit normally before removing the app, its login
/// item, and its settings. Nothing is downloaded.
enum Uninstaller {
    static func confirmAndRun() {
        let app = Bundle.main.bundleURL
        // Lidglow is a menu-bar app, so it has to activate itself or the alert opens behind other apps.
        NSApp.activate()
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "Uninstall Lidglow?"
        confirm.informativeText = "This removes Lidglow from \(app.deletingLastPathComponent().path) "
            + "along with its settings, then quits it."
        let uninstall = confirm.addButton(withTitle: "Uninstall")
        uninstall.hasDestructiveAction = true
        // A destructive action shouldn't be the default, so Return does nothing. Cancel keeps the Escape key
        // that NSAlert gives a button titled Cancel.
        uninstall.keyEquivalent = ""
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        if let reason = run(app: app) {
            Logger.update.error("Uninstall failed: \(reason, privacy: .public)")
            let failed = NSAlert()
            failed.messageText = "Couldn’t uninstall Lidglow"
            failed.informativeText = reason
            failed.runModal()
            return
        }
        Logger.update.notice("Uninstalling, quitting so the app can be removed")
        // There's no logo to hand back on this Mac, but quit normally anyway. The script removes the app
        // once this process has exited.
        NSApp.terminate(nil)
    }

    /// Starts the bundled script and returns nil once it's waiting for Lidglow to quit, or why it couldn't.
    private static func run(app: URL) -> String? {
        guard let script = Bundle.main.url(forResource: "uninstall", withExtension: "sh") else {
            return "This copy of Lidglow doesn’t include the uninstaller. Move it to the Trash instead."
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--from-app"]
        // Only the settings the uninstaller needs reach it.
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("LIDGLOW_") }
        environment["LIDGLOW_APP"] = app.path
        environment["LIDGLOW_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return "Couldn’t start the uninstaller: \(error.localizedDescription)"
        }
        // The script only checks the app and starts its background step, whose output goes nowhere, so
        // this returns as soon as the script exits.
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let reason = message
            .replacingOccurrences(of: "Lidglow uninstall: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? "The uninstaller stopped (error \(process.terminationStatus)). Nothing was removed." : reason
    }
}
