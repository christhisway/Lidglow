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
        let app = NSApplication.shared
        let delegate = LidglowApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
