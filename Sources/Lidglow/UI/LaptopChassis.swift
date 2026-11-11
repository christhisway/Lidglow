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
    static let studio: [CGImage] = {
        let side = 64
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            ([1, 0, 0], [0, 0, -1], [0, 1, 0]), ([-1, 0, 0], [0, 0, 1], [0, 1, 0]),
            ([0, 1, 0], [1, 0, 0], [0, 0, -1]), ([0, -1, 0], [1, 0, 0], [0, 0, 1]),
            ([0, 0, 1], [1, 0, 0], [0, 1, 0]), ([0, 0, -1], [-1, 0, 0], [0, 1, 0])
        ]
        let softboxes: [(SIMD3<Float>, Float, Float)] = [
            (simd_normalize([-0.75, 1, 0.65]), 0.78, 9),
            (simd_normalize([0.76, 0.55, -1]), 0.63, 13),
            (simd_normalize([0.2, 1, -0.2]), 0.37, 5)
        ]
        return faces.compactMap { forward, right, up in
            var bytes: [UInt8] = []
            bytes.reserveCapacity(side * side * 4)
            for y in 0..<side {
                for x in 0..<side {
                    let u = (Float(x) + 0.5) * 2 / Float(side) - 1
                    let v = 1 - (Float(y) + 0.5) * 2 / Float(side)
                    let direction = simd_normalize(forward + right * u + up * v)
                    var light: Float = 0.055 + 0.10 * max(0, direction.y)
                    for (aim, strength, falloff) in softboxes {
                        light += strength * pow(max(0, simd_dot(direction, aim)), falloff)
                    }
                    let gray = UInt8((min(1, light) * 255).rounded())
                    bytes.append(contentsOf: [gray, gray, gray, 255])
                }
            }
            guard let data = CGDataProvider(data: Data(bytes) as CFData),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: side * 4, space: colorSpace,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                           provider: data, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }()
}
