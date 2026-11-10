import AppKit

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = LidglowApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
