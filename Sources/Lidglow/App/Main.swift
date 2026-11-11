import AppKit

@main
struct Main {
    static func main() {
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
