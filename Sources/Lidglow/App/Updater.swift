// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import os

/// Settings → About → Check for Updates, Lidglow's only network access. It runs only when the user clicks
/// the button and only downloads from GitHub Releases, sending nothing about the user. The copy of
/// `Scripts/install.sh` bundled in the app does the work as `install.sh --update`: it installs the latest
/// stable release only if its build number is higher, then waits for Lidglow to quit normally (which hands
/// the logo back to macOS) before replacing the app and reopening it.
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case noStableRelease
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// The installer's exit codes in `--update` mode. Anything else is a failure with its reason on stderr.
    private enum Exit {
        static let staged: Int32 = 0
        static let upToDate: Int32 = 10
        static let noStableRelease: Int32 = 11
    }

    private init() {}

    var isBusy: Bool { state == .checking || state == .installing }

    func check() {
        guard !isBusy else { return }
        guard let script = Bundle.main.url(forResource: "install", withExtension: "sh") else {
            state = .failed("This copy of Lidglow doesn’t include the updater. Run the install command in Terminal instead.")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--update"]
        // Only the settings this check needs reach the installer. LIDGLOW_RELEASE_URL is kept for testing.
        var environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("LIDGLOW_") || $0.key == "LIDGLOW_RELEASE_URL"
        }
        environment["LIDGLOW_APP"] = Bundle.main.bundleURL.path
        environment["LIDGLOW_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        process.terminationHandler = { [weak self] process in
            // The installer's background step writes nowhere, so this ends when the script exits.
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let status = process.terminationStatus
            DispatchQueue.main.async { self?.finish(status: status, message: message) }
        }
        state = .checking
        Logger.update.info("Checking for updates")
        do {
            try process.run()
        } catch {
            Logger.update.error("Couldn't start the installer: \(error.localizedDescription, privacy: .public)")
            state = .failed("Couldn’t start the updater: \(error.localizedDescription)")
        }
    }

    private func finish(status: Int32, message: String) {
        switch status {
        case Exit.staged:
            Logger.update.info("Update staged, quitting so it can be installed")
            state = .installing
            // A normal quit, so Lidglow hands the logo back to macOS before the app is replaced.
            NSApp.terminate(nil)
        case Exit.upToDate:
            Logger.update.info("Already up to date")
            state = .upToDate
        case Exit.noStableRelease:
            Logger.update.info("No stable release yet")
            state = .noStableRelease
        default:
            let reason = message
                .replacingOccurrences(of: "Lidglow install: ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.update.error("Update failed with status \(status): \(reason, privacy: .public)")
            state = .failed(reason.isEmpty ? "The update didn’t finish (error \(status)). Nothing was installed." : reason)
        }
    }
}
