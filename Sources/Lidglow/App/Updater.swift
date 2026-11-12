// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import os

/// Settings → About → Check for Updates, Lidglow's only network access. It runs only when the user clicks
/// the button and only downloads from GitHub Releases, sending nothing about the user. The copy of
/// `Scripts/install.sh` bundled in the app installs a release only if its build number is higher.
/// It waits for Lidglow to quit normally (which hands
/// the logo back to macOS) before replacing the app and reopening it.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case noRelease
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
    static var includesBetas: Bool {
        let label = Bundle.main.object(forInfoDictionaryKey: "LidglowReleaseLabel") as? String
        return label?.lowercased().hasPrefix("beta") == true
    }

    func check() {
        guard !isBusy else { return }
        state = .checking
        Logger.update.info("Checking for updates")
        // Keep the installer's local release override available for end-to-end development tests.
        guard Self.includesBetas, ProcessInfo.processInfo.environment["LIDGLOW_RELEASE_URL"] == nil else {
            runInstaller()
            return
        }
        Task {
            do {
                guard let tag = try await Self.latestBetaChannelTag() else {
                    state = .noRelease
                    return
                }
                runInstaller(tag: tag)
            } catch {
                Logger.update.error("Release lookup failed: \(error.localizedDescription, privacy: .public)")
                state = .failed("Couldn’t check GitHub for updates. Try again in a moment.")
            }
        }
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
    }

    private static func latestBetaChannelTag() async throws -> String? {
        let url = URL(string: "https://api.github.com/repos/christhisway/Lidglow/releases?per_page=100")!
        let request = URLRequest(url: url, timeoutInterval: 20)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let releases = try JSONDecoder().decode([Release].self, from: data)
        return releases.filter { release in
            !release.draft && release.tag_name.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$"#,
                                                     options: .regularExpression) != nil
        }.map(\.tag_name).max { left, right in
            let leftParts = left.split(separator: "-")
            let rightParts = right.split(separator: "-")
            let baseOrder = leftParts[0].compare(rightParts[0], options: .numeric)
            if baseOrder != .orderedSame { return baseOrder == .orderedAscending }
            if leftParts.count != rightParts.count { return leftParts.count > rightParts.count }
            return left.compare(right, options: .numeric) == .orderedAscending
        }
    }

    private func runInstaller(tag: String? = nil) {
        guard let script = Bundle.main.url(forResource: "install", withExtension: "sh") else {
            state = .failed("This copy of Lidglow doesn’t include the updater. Run the install command in Terminal instead.")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--update"] + (tag.map { [$0] } ?? [])
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
            state = .noRelease
        default:
            let reason = message
                .replacingOccurrences(of: "Lidglow install: ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.update.error("Update failed with status \(status): \(reason, privacy: .public)")
            state = .failed(reason.isEmpty ? "The update didn’t finish (error \(status)). Nothing was installed." : reason)
        }
    }
}
