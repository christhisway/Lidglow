import AppKit

/// Watches for other lid-logo utilities. They use the same private CoreBrightness controls, so if both
/// apps drive the logo it flickers or ends up in a state neither restores. Lidglow backs off while
/// one is running. This uses launch and quit notifications, never polling.
final class OtherLogoApps {
    /// Bundle IDs of known logo utilities and the names shown in the panel.
    static let known: [String: String] = [
        "co.supershort.backglow": "Backglow",
        "app.logolight.LogoLight": "LogoLight",
    ]

    /// The name of a running logo utility, or nil when none is running.
    private(set) var running: String?
    /// Called on the main queue when `running` changes.
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier, Self.known[id] != nil else { return }
                self?.refresh()
            })
        }
    }

    deinit {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private func refresh() {
        let current = NSWorkspace.shared.runningApplications.lazy
            .compactMap { $0.isTerminated ? nil : $0.bundleIdentifier.flatMap { Self.known[$0] } }
            .first
        guard current != running else { return }
        running = current
        onChange?()
    }
}
