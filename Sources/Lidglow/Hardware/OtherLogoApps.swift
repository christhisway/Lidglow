import AppKit

/// Recognizes some other lid-logo apps by bundle ID, so Lidglow can step aside before the two fight and
/// name the app in the panel. This is only a fast path: any other app that drives the logo is caught by
/// `LidLogo`'s interference check instead. Uses launch and quit notifications, never polling.
final class OtherLogoApps {
    /// Bundle IDs of logo apps known so far and the names shown in the panel. Add more as they turn up.
    static let known: [String: String] = [
        "co.supershort.backglow": "Backglow",
        "app.logolight.LogoLight": "LogoLight",
        "app.lidlight.Lidlight": "Lidlight",
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
