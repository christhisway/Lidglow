// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SceneKit
import simd

enum LaptopChassis {
    static func aluminum(finish: LaptopFinish) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(white: finish == .spaceBlack ? 0.31 : 0.76, alpha: 1)
        material.metalness.contents = 0.76
        material.roughness.contents = 0.33
        return material
    }

    /// A rounded rectangle with independently rounded edges and analytic surface normals.
    /// The flat faces and fillets share their boundary, so the reflected light stays continuous.
    static func shell(width: CGFloat, height: CGFloat, thickness: CGFloat, corner: CGFloat,
                      fillet: CGFloat, material: SCNMaterial) -> SCNNode {
        let cornerSteps = 32
        let filletSteps = 8
        let count = 4 * (cornerSteps + 1)
        let halfWidth = width / 2
        let halfHeight = height / 2
        let halfDepth = thickness / 2
        let centers = [
            CGPoint(x: halfWidth - corner, y: -halfHeight + corner),
            CGPoint(x: halfWidth - corner, y: halfHeight - corner),
            CGPoint(x: -halfWidth + corner, y: halfHeight - corner),
            CGPoint(x: -halfWidth + corner, y: -halfHeight + corner)
        ]

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var triangles: [UInt32] = []
        let ringCount = 2 * (filletSteps + 1)

        for ring in 0..<ringCount {
            let upper = ring > filletSteps
            let step = upper ? ring - filletSteps - 1 : ring
            let tilt = (CGFloat(step) / CGFloat(filletSteps) - (upper ? 0 : 1)) * .pi / 2
            let radial = cos(tilt)
            let vertical = sin(tilt)
            let z = (upper ? halfDepth - fillet : fillet - halfDepth) + fillet * vertical
            let radius = corner - fillet * (1 - radial)

            for (quadrant, center) in centers.enumerated() {
                for segment in 0...cornerSteps {
                    let angle = (CGFloat(quadrant - 1) + CGFloat(segment) / CGFloat(cornerSteps)) * .pi / 2
                    let x = cos(angle)
                    let y = sin(angle)
                    vertices.append(SCNVector3(center.x + x * radius, center.y + y * radius, z))
                    normals.append(SCNVector3(x * radial, y * radial, vertical))
                }
            }

            if ring > 0 {
                for i in 0..<count {
                    let next = (i + 1) % count
                    let lower = UInt32((ring - 1) * count + i)
                    let lowerNext = UInt32((ring - 1) * count + next)
                    let upper = UInt32(ring * count + i)
                    let upperNext = UInt32(ring * count + next)
                    triangles.append(contentsOf: [lower, lowerNext, upperNext, lower, upperNext, upper])
                }
            }
        }

        let bottom = UInt32(vertices.count)
        let top = bottom + 1
        vertices += [SCNVector3(0, 0, -halfDepth), SCNVector3(0, 0, halfDepth)]
        normals += [SCNVector3(0, 0, -1), SCNVector3(0, 0, 1)]
        let lastRing = (ringCount - 1) * count
        for i in 0..<count {
            let next = (i + 1) % count
            triangles.append(contentsOf: [bottom, UInt32(next), UInt32(i),
                                          top, UInt32(lastRing + i), UInt32(lastRing + next)])
        }

        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: triangles, primitiveType: .triangles)]
        )
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }

    // A neutral photo studio in six cube faces. It lights the metal without drawing a backdrop.
    // The pieces are small and explicitly typed so the Command Line Tools' compiler can type-check them.
    static let studio: [CGImage] = studioFaces.compactMap { studioImage(for: $0) }

    private struct StudioFace {
        let forward: SIMD3<Float>
        let right: SIMD3<Float>
        let up: SIMD3<Float>
    }

    private struct Softbox {
        let aim: SIMD3<Float>
        let strength: Float
        let falloff: Float
    }

    private static let studioSide = 64

    private static let studioFaces: [StudioFace] = [
        StudioFace(forward: SIMD3<Float>(1, 0, 0), right: SIMD3<Float>(0, 0, -1), up: SIMD3<Float>(0, 1, 0)),
        StudioFace(forward: SIMD3<Float>(-1, 0, 0), right: SIMD3<Float>(0, 0, 1), up: SIMD3<Float>(0, 1, 0)),
        StudioFace(forward: SIMD3<Float>(0, 1, 0), right: SIMD3<Float>(1, 0, 0), up: SIMD3<Float>(0, 0, -1)),
        StudioFace(forward: SIMD3<Float>(0, -1, 0), right: SIMD3<Float>(1, 0, 0), up: SIMD3<Float>(0, 0, 1)),
        StudioFace(forward: SIMD3<Float>(0, 0, 1), right: SIMD3<Float>(1, 0, 0), up: SIMD3<Float>(0, 1, 0)),
        StudioFace(forward: SIMD3<Float>(0, 0, -1), right: SIMD3<Float>(-1, 0, 0), up: SIMD3<Float>(0, 1, 0))
    ]

    private static let softboxes: [Softbox] = [
        Softbox(aim: simd_normalize(SIMD3<Float>(-0.75, 1, 0.65)), strength: 0.78, falloff: 9),
        Softbox(aim: simd_normalize(SIMD3<Float>(0.76, 0.55, -1)), strength: 0.63, falloff: 13),
        Softbox(aim: simd_normalize(SIMD3<Float>(0.2, 1, -0.2)), strength: 0.37, falloff: 5)
    ]

    /// Maps a pixel index to -1...1 across the face, through the pixel's center.
    private static func studioCoordinate(_ index: Int) -> Float {
        let center: Float = Float(index) + 0.5
        let span: Float = Float(studioSide)
        return center * 2 / span - 1
    }

    private static func studioLight(toward direction: SIMD3<Float>) -> Float {
        let sky: Float = max(0, direction.y)
        var light: Float = 0.055 + 0.10 * sky
        for softbox in softboxes {
            let facing: Float = max(0, simd_dot(direction, softbox.aim))
            light += softbox.strength * pow(facing, softbox.falloff)
        }
        return light
    }

    private static func studioImage(for face: StudioFace) -> CGImage? {
        let side = studioSide
        var bytes: [UInt8] = []
        bytes.reserveCapacity(side * side * 4)
        for y in 0..<side {
            let v: Float = -studioCoordinate(y)
            for x in 0..<side {
                let u: Float = studioCoordinate(x)
                let across: SIMD3<Float> = face.forward + face.right * u
                let direction: SIMD3<Float> = simd_normalize(across + face.up * v)
                let light: Float = studioLight(toward: direction)
                let gray = UInt8((min(1, light) * 255).rounded())
                bytes.append(contentsOf: [gray, gray, gray, 255])
            }
        }
        guard let data = CGDataProvider(data: Data(bytes) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4, space: colorSpace, bitmapInfo: bitmapInfo,
                       provider: data, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
