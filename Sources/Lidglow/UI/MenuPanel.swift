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
            // Liquid Glass draws a soft shadow just outside its shape. Inside a transparent window that
            // shadow fills the corners with faint pixels, and macOS builds the window's shadow and its
            // edge line from the window's alpha, so the panel got a near-rectangular outline: square at
            // the bottom, where the glass shadow is strongest, and barely rounded at the top. Clipping
            // the glass to its own shape leaves the corners fully transparent, so the system shadow
            // follows the panel's rounded corners.
            let clip = NSView()
            clip.wantsLayer = true
            clip.layer?.cornerRadius = radius
            clip.layer?.cornerCurve = .continuous
            clip.layer?.masksToBounds = true
            glass.autoresizingMask = [.width, .height]
            clip.addSubview(glass)
            return clip
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
