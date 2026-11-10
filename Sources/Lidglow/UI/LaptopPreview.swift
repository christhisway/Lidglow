import AppKit
import SceneKit
import SwiftUI

private enum PreviewFraming {
    static let height: CGFloat = 182
    static let logoSize: CGFloat = 94
}

struct LaptopPreview: View {
    let level: Double
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var introFinished = false

    var body: some View {
        ZStack {
            Color(white: 0.057)
            RadialGradient(colors: [Color(white: 0.145), .clear],
                           center: .init(x: 0.50, y: 0.40), startRadius: 12, endRadius: 165)
            if !reduceMotion {
                LaptopSceneView(isVisible: isVisible) {
                    withAnimation(.easeInOut(duration: 0.26)) { introFinished = true }
                }
            }
            if isVisible && (introFinished || reduceMotion) {
                LidLogoCloseup(level: level)
                    .transition(.opacity)
            }
        }
        .frame(height: PreviewFraming.height)
        .clipShape(.rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.10)) }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onChange(of: isVisible) { _, visible in
            if !visible { introFinished = false }
        }
        .onChange(of: reduceMotion) { _, _ in introFinished = false }
    }
}

private struct LidLogoCloseup: View {
    let level: Double
    private static let logo = LaptopScene.logoTexture.map { Image(decorative: $0, scale: 1) }
        ?? Image(systemName: "apple.logo")

    var body: some View {
        let shade = LaptopFinish.current == .spaceBlack ? 0.16 : 0.44
        let mark = Self.logo.renderingMode(.template).resizable().scaledToFit()
            .frame(width: PreviewFraming.logoSize, height: PreviewFraming.logoSize)
        ZStack {
            LinearGradient(colors: [Color(white: shade + 0.045), Color(white: shade),
                                    Color(white: shade - 0.035)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(white: shade + 0.04).opacity(0.65), .clear],
                           center: .init(x: 0.35, y: 0.28), startRadius: 8, endRadius: 174)
            RadialGradient(stops: [
                .init(color: .white.opacity(0.34), location: 0),
                .init(color: .white.opacity(0.19), location: 0.36),
                .init(color: .white.opacity(0.06), location: 0.63),
                .init(color: .clear, location: 1)
            ], center: .center, startRadius: 0, endRadius: 80)
            .opacity(level)
            .blendMode(.plusLighter)
            mark.foregroundStyle(.white.opacity(0.14)).offset(y: 0.65)
            mark.foregroundStyle(.linearGradient(colors: [Color(white: 0.14), Color(white: 0.06)],
                                                 startPoint: .top, endPoint: .bottom))
            mark.foregroundStyle(.white)
                .opacity(level)
        }
    }
}

private struct LaptopSceneView: NSViewRepresentable {
    let isVisible: Bool
    let onFinish: () -> Void

    func makeCoordinator() -> LaptopScene { LaptopScene() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = .clear
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.update(view, visible: isVisible, onFinish: onFinish)
    }

    static func dismantleNSView(_ view: SCNView, coordinator: LaptopScene) {
        coordinator.update(view, visible: false, onFinish: {})
    }
}

private final class LaptopScene {
    private static let frontAngle: CGFloat = -0.17
    // The lid mesh is upright at zero rotation, perpendicular to the keyboard.
    private static let openAngle: CGFloat = 0
    private static let closedAngle: CGFloat = .pi / 2
    private static let introDuration: TimeInterval = 2.40
    private static let fieldOfView: CGFloat = 25
    private static let hingeOrigin = SCNVector3(0, 0.075, -1.045)
    private static let logoHeight: CGFloat = 1.08
    private static let logoDepth: CGFloat = -0.022
    private static let logoPlaneSize: CGFloat = 0.43
    private static let closeupDistance = logoPlaneSize * PreviewFraming.height
        / (2 * PreviewFraming.logoSize * tan(fieldOfView * .pi / 360))
    let scene = SCNScene()
    let camera = SCNNode()
    private let laptop = SCNNode()
    private let hinge = SCNNode()
    private let startupGlow = SCNNode()
    private let alloy: SCNMaterial
    private var wasVisible = false
    private var introID: UUID?

    init(finish: LaptopFinish = .current) {
        alloy = LaptopChassis.aluminum(finish: finish)
        scene.lightingEnvironment.contents = LaptopChassis.studio
        scene.lightingEnvironment.intensity = 1.25
        scene.rootNode.addChildNode(laptop)
        buildLaptop()

        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = Self.fieldOfView
        camera.camera?.projectionDirection = .vertical
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 25
        frameCamera(height: 0.33, zoom: 0)
        scene.rootNode.addChildNode(camera)

        addLight(.ambient, color: NSColor(white: 0.90, alpha: 1),
                 intensity: 240, position: SCNVector3Zero)
        addLight(.directional, color: NSColor(srgbRed: 0.96, green: 0.97, blue: 1, alpha: 1),
                 intensity: 610, position: SCNVector3(-3, 4, 3))
        addLight(.directional, color: NSColor(white: 0.94, alpha: 1),
                 intensity: 730, position: SCNVector3(3, 2, -3))

        let shadow = Self.plane(width: 4.25, height: 2.85, texture: Self.haloTexture())
        shadow.eulerAngles.x = -.pi / 2
        shadow.position.y = -0.079
        shadow.geometry?.firstMaterial?.multiply.contents = NSColor.black
        shadow.opacity = 0.78
        scene.rootNode.addChildNode(shadow)
    }

    func update(_ view: SCNView, visible: Bool, onFinish: @escaping () -> Void) {
        guard visible != wasVisible else { return }
        wasVisible = visible
        introID = nil
        laptop.removeAction(forKey: "intro")
        view.isPlaying = visible
        guard visible else { return }

        applyIntro(at: 0)
        let id = UUID()
        introID = id
        let intro = SCNAction.customAction(duration: Self.introDuration) { [weak self] _, elapsed in
            self?.applyIntro(at: TimeInterval(elapsed))
        }
        laptop.runAction(intro, forKey: "intro") { [weak self, weak view] in
            DispatchQueue.main.async {
                guard let self, self.introID == id else { return }
                view?.isPlaying = false
                onFinish()
            }
        }
    }

    private func frameCamera(height: CGFloat, zoom: CGFloat) {
        // At the end the lid is vertical and facing the camera. Frame the actual logo plane
        // at the same size as the live artwork, so the dissolve doesn't resize the mark.
        let logoY = Self.hingeOrigin.y + Self.logoHeight
        let logoZ = -(Self.hingeOrigin.z + Self.logoDepth)
        let target = SCNVector3(0, height + (logoY - height) * zoom, logoZ * zoom)
        camera.position = SCNVector3(0, 2.68 + (logoY - 2.68) * zoom,
                                     8.3 + (logoZ + Self.closeupDistance - 8.3) * zoom)
        camera.look(at: target)
    }

    private func applyIntro(at time: TimeInterval) {
        let open = Self.ease(time, from: 0.04, to: 1.10)
        let turn = Self.ease(time, from: 0.32, to: 1.78)
        let frame = Self.ease(time, from: 0.04, to: 1.45)
        let zoom = Self.ease(time, from: 1.30, to: 2.36)
        hinge.eulerAngles.x = Self.closedAngle + (Self.openAngle - Self.closedAngle) * open
        laptop.eulerAngles.y = Self.frontAngle + (.pi - Self.frontAngle) * turn
        frameCamera(height: 0.33 + 0.51 * frame, zoom: zoom)
        startupGlow.opacity = Self.ease(time, from: 1.50, to: 2.08)
    }

    private static func ease(_ time: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> CGFloat {
        let progress = CGFloat(min(1, max(0, (time - start) / (end - start))))
        // Quintic easing has zero velocity and acceleration at both endpoints.
        return progress * progress * progress * (progress * (progress * 6 - 15) + 10)
    }

    private func buildLaptop() {
        let dark = Self.metal(NSColor(white: 0.055, alpha: 1))
        // Scale the 35.55 × 24.42 × 1.60 cm closed chassis to a width of 3.30 scene units.
        let base = LaptopChassis.shell(width: 3.30, height: 2.27, thickness: 0.105,
                                       corner: 0.137, fillet: 0.029, material: alloy)
        base.eulerAngles.x = -.pi / 2
        laptop.addChildNode(base)

        let deck = Self.plane(width: 3.14, height: 2.17, texture: Self.deckTexture())
        deck.eulerAngles.x = -.pi / 2
        deck.position.y = 0.054
        laptop.addChildNode(deck)

        let hingeBar = Self.box(2.94, 0.039, 0.097, radius: 0.018, material: dark)
        hingeBar.position = SCNVector3(0, 0.050, -1.033)
        laptop.addChildNode(hingeBar)

        // Recessed ports remain readable in profile without making the edges bulky.
        for (side, positions) in [(1.0, [-0.72, -0.43, -0.10]), (-1.0, [-0.78, -0.51, -0.29, 0.03])] {
            for (index, z) in positions.enumerated() {
                let length = side == 1 && index < 2 ? 0.19 : 0.12
                let port = Self.box(0.009, 0.035, length, radius: 0.004, material: dark)
                port.position = SCNVector3(1.649 * side, -0.003, z)
                laptop.addChildNode(port)
            }
        }

        hinge.position = Self.hingeOrigin
        hinge.eulerAngles.x = Self.closedAngle
        laptop.addChildNode(hinge)

        let lid = LaptopChassis.shell(width: 3.29, height: 2.16, thickness: 0.037,
                                      corner: 0.079, fillet: 0.009, material: alloy)
        lid.position.y = Self.logoHeight
        hinge.addChildNode(lid)
        let glass = Self.plane(width: 3.25, height: 2.12, texture: Self.displayTexture())
        glass.position = SCNVector3(0, 1.085, 0.0195)
        hinge.addChildNode(glass)

        let unlitMark = Self.plane(width: Self.logoPlaneSize, height: Self.logoPlaneSize,
                                   texture: Self.logoTexture)
        unlitMark.geometry?.firstMaterial?.multiply.contents = NSColor(white: 0.075, alpha: 1)
        placeLidMark(unlitMark, at: -0.020, order: 1, on: hinge)

        let bootHalo = Self.plane(width: 0.79, height: 0.79, texture: Self.haloTexture())
        let bootLogo = Self.plane(width: Self.logoPlaneSize, height: Self.logoPlaneSize,
                                  texture: Self.logoTexture)
        bootHalo.geometry?.firstMaterial?.blendMode = .add
        bootHalo.opacity = 0.4
        placeLidMark(bootHalo, at: -0.021, order: 2, on: startupGlow)
        placeLidMark(bootLogo, at: Self.logoDepth, order: 3, on: startupGlow)
        hinge.addChildNode(startupGlow)
        startupGlow.opacity = 0
    }

    private func placeLidMark(_ node: SCNNode, at depth: CGFloat, order: Int, on surface: SCNNode) {
        node.position = SCNVector3(0, Self.logoHeight, depth)
        node.eulerAngles.y = .pi
        node.renderingOrder = order
        surface.addChildNode(node)
    }

    private func addLight(_ type: SCNLight.LightType, color: NSColor, intensity: CGFloat, position: SCNVector3) {
        let node = SCNNode()
        let light = SCNLight()
        light.type = type
        light.color = color
        light.intensity = intensity
        node.light = light
        node.position = position
        if type == .directional { node.look(at: SCNVector3Zero) }
        scene.rootNode.addChildNode(node)
    }

    private static func metal(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = color
        material.specular.contents = NSColor(white: 0.47, alpha: 1)
        material.shininess = 32
        return material
    }

    private static func box(_ width: CGFloat, _ height: CGFloat, _ depth: CGFloat,
                            radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: depth, chamferRadius: radius)
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }

    private static func plane(width: CGFloat, height: CGFloat, texture: Any?) -> SCNNode {
        let geometry = SCNPlane(width: width, height: height)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = texture
        material.writesToDepthBuffer = false
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }

    static let logoTexture: CGImage? = {
        let image = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { bounds in
            let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .regular)
                .applying(.init(paletteColors: [.white]))
            guard let symbol = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return false }
            let inset = bounds.insetBy(dx: 48, dy: 48)
            let scale = min(inset.width / symbol.size.width, inset.height / symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                   width: size.width, height: size.height))
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }()

    private static func haloTexture() -> NSImage {
        NSImage(size: NSSize(width: 128, height: 128), flipped: false) { bounds in
            let gradient = NSGradient(colors: [.white, NSColor(white: 1, alpha: 0.16), .clear])
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            gradient?.draw(fromCenter: center, radius: 0, toCenter: center, radius: bounds.width / 2,
                           options: [])
            return true
        }
    }

    private static func displayTexture() -> NSImage {
        NSImage(size: NSSize(width: 640, height: 418), flipped: false) { bounds in
            let glass = NSBezierPath(roundedRect: bounds, xRadius: 13, yRadius: 13)
            NSColor(white: 0.014, alpha: 1).setFill()
            glass.fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return true }

            let screen = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 5), xRadius: 10, yRadius: 10)
            NSGraphicsContext.saveGraphicsState()
            screen.addClip()
            NSColor(srgbRed: 0.021, green: 0.028, blue: 0.039, alpha: 1).setFill()
            bounds.fill()

            // Three softly lit groups of vertical fibers give the display a neutral, glass-like texture.
            for group in 0..<3 {
                let leading = CGFloat(group) * 211 + 12
                let stops: [CGFloat] = [0, 0.30 + CGFloat(group) * 0.08, 0.68, 1]
                let colors = [
                    NSColor(srgbRed: 0.76, green: 0.81, blue: 0.90, alpha: 1),
                    NSColor(srgbRed: 0.16, green: 0.20, blue: 0.27, alpha: 1),
                    NSColor(srgbRed: 0.035, green: 0.045, blue: 0.063, alpha: 1),
                    NSColor(srgbRed: 0.76, green: 0.81, blue: 0.90, alpha: 1)
                ]
                guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                                colors: colors.map(\.cgColor) as CFArray,
                                                locations: stops) else { continue }
                for strand in 0..<32 {
                    let x = leading + CGFloat(strand) * 6.15
                    let curl = 17 * sin(CGFloat(strand) / 31 * .pi)
                    context.saveGState()
                    context.move(to: CGPoint(x: x - curl, y: 405))
                    context.addCurve(to: CGPoint(x: x + curl, y: 15),
                                     control1: CGPoint(x: x + curl, y: 354),
                                     control2: CGPoint(x: x - curl, y: 61))
                    context.setLineWidth(4.0 + CGFloat(strand % 4) * 0.55)
                    context.setLineCap(.round)
                    context.replacePathWithStrokedPath()
                    context.clip()
                    context.setAlpha(0.49 + CGFloat(strand % 7) * 0.075)
                    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: group == 1 ? 10 : 410),
                                               end: CGPoint(x: 0, y: group == 1 ? 410 : 10), options: [])
                    context.restoreGState()
                }
            }
            NSGraphicsContext.restoreGraphicsState()

            NSColor(white: 0.012, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 294, y: 389, width: 52, height: 15),
                         xRadius: 7.5, yRadius: 7.5).fill()
            NSColor(srgbRed: 0.095, green: 0.14, blue: 0.23, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 334, y: 394, width: 5, height: 5)).fill()
            return true
        }
    }

    private static func deckTexture() -> NSImage {
        NSImage(size: NSSize(width: 640, height: 441), flipped: false) { _ in
            NSColor(white: 0.06, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 75, y: 174, width: 490, height: 224),
                         xRadius: 10, yRadius: 10).fill()

            let rows: [[(String, CGFloat)]] = [
                [("esc", 1.45)] + (1...12).map { ("F\($0)", 1) } + [("", 1)],
                ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "−", "="].map { ($0, 1) }
                    + [("⌫", 1.5)],
                [("⇥", 1.48)] + "QWERTYUIOP[]".map { (String($0), 1) } + [("\\", 1.05)],
                [("⇪", 1.65)] + "ASDFGHJKL;'".map { (String($0), 1) } + [("↩", 1.88)],
                [("⇧", 2.06)] + "ZXCVBNM,./".map { (String($0), 1) } + [("⇧", 2.47)],
                [("fn", 1), ("⌃", 1), ("⌥", 1), ("⌘", 1.25), ("", 4.75),
                 ("⌘", 1.25), ("⌥", 1), ("←", 1), ("↕", 1), ("→", 1)]
            ]
            let legend: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7.5, weight: .medium),
                .foregroundColor: NSColor(white: 0.76, alpha: 0.88)
            ]
            for (row, keys) in rows.enumerated() {
                let unit = 472 / keys.reduce(0) { $0 + $1.1 }
                var x: CGFloat = 84
                for (character, units) in keys {
                    let width = unit * units
                    let key = NSRect(x: x, y: 365 - CGFloat(row) * 36, width: width - 3, height: 31)
                    let keycap = NSBezierPath(roundedRect: key, xRadius: 3.5, yRadius: 3.5)
                    NSColor(white: 0.115, alpha: 1).setFill()
                    keycap.fill()
                    NSColor(white: 0.27, alpha: 0.62).setStroke()
                    keycap.lineWidth = 0.55
                    keycap.stroke()
                    let glyph = character as NSString
                    let size = glyph.size(withAttributes: legend)
                    glyph.draw(at: NSPoint(x: key.midX - size.width / 2, y: key.midY - size.height / 2),
                               withAttributes: legend)
                    x += width
                }
            }

            NSColor(white: 0.07, alpha: 0.8).setFill()
            for startX in [24, 580] {
                for row in 0..<29 {
                    for column in 0..<8 {
                        NSBezierPath(ovalIn: NSRect(x: startX + column * 5, y: 208 + row * 6,
                                                   width: 2, height: 2)).fill()
                    }
                }
            }

            let trackpad = NSBezierPath(roundedRect: NSRect(x: 170, y: 12, width: 300, height: 151),
                                       xRadius: 9, yRadius: 9)
            NSColor(white: 0.85, alpha: 0.028).setFill()
            trackpad.fill()
            NSColor(white: 0.07, alpha: 0.65).setStroke()
            trackpad.lineWidth = 2
            trackpad.stroke()
            return true
        }
    }
}
