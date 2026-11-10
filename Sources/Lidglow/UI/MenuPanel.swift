import AppKit

final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    static func backdrop(containing content: NSView) -> NSView {
        let radius: CGFloat = 24
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.cornerRadius = radius
        content.layer?.masksToBounds = true

        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            glass.tintColor = NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(white: isDark ? 0.06 : 1, alpha: isDark ? 0.42 : 0.24)
            }
            glass.contentView = content
            return glass
        }
        #endif

        let material = NSVisualEffectView()
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = radius
        material.layer?.masksToBounds = true
        material.addSubview(content)
        return material
    }
}
