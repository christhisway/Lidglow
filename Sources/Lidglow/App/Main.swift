// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ServiceManagement

@main
struct Main {
    static func main() {
        // Scripts/uninstall.sh runs the app this way to remove its login item before deleting it. It exits
        // before anything touches the logo or the menu bar.
        if CommandLine.arguments.dropFirst().first == "--unregister-login-item" {
            try? SMAppService.mainApp.unregister()
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
}
