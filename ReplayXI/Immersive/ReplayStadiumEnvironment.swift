import CoreGraphics
import Foundation
import RealityKit
import UIKit
import simd

/// Original local geometry, not a generated or downloaded Tripo asset.
/// The owner controls visibility and transforms; neither factory runs per frame.
/// A later USDZ replacement belongs behind `makeStadium`, after explicit hash,
/// geometry, material-budget and clear-field admission. No asset is loaded here.
@MainActor
enum ReplayStadiumEnvironment {
    static let skyRootName = "replay-local-sky-root"
    static let stadiumRootName = "replay-local-stadium-root"
    static let lightingRootName = "replay-local-stadium-lighting"
    static let sourceDescription = "Local procedural stadium"
    static let maximumMaterialDraws = 6
    static let maximumTriangles = 12_000
    static let clearHalfWidth: Float = 36
    static let clearHalfLength: Float = 56
    static let skyRadius: Float = 250
    static let groundY: Float = -0.08
    static let skyTextureWidth = 1
    static let skyTextureHeight = 128

    struct Provenance: Component {
        let source: String
    }

    struct Geometry {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var textureCoordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var triangleCount: Int { indices.count / 3 }

        mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>,
                           _ c: SIMD3<Float>, _ d: SIMD3<Float>, normal: SIMD3<Float>) {
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a, b, c, d])
            normals.append(contentsOf: Array(repeating: simd_normalize(normal), count: 4))
            if simd_dot(simd_cross(b - a, c - a), normal) >= 0 {
                indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            } else {
                indices.append(contentsOf: [base, base + 2, base + 1, base, base + 3, base + 2])
            }
        }

        mutating func box(centre: SIMD3<Float>, along: SIMD3<Float>,
                          across: SIMD3<Float>, height: Float) {
            let x = along * 0.5, z = across * 0.5, y = SIMD3<Float>(0, height * 0.5, 0)
            let corners = [centre - x - y - z, centre + x - y - z,
                           centre + x - y + z, centre - x - y + z,
                           centre - x + y - z, centre + x + y - z,
                           centre + x + y + z, centre - x + y + z]
            for (a, b, c, d, normal) in [
                (0, 1, 2, 3, -y), (4, 7, 6, 5, y),
                (0, 4, 5, 1, -z), (3, 2, 6, 7, z),
                (0, 3, 7, 4, -x), (1, 5, 6, 2, x)
            ] {
                quad(corners[a], corners[b], corners[c], corners[d], normal: normal)
            }
        }

        @MainActor
        func makeMesh(name: String) -> MeshResource? {
            var descriptor = MeshDescriptor(name: name)
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            if !textureCoordinates.isEmpty {
                descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(textureCoordinates)
            }
            descriptor.primitives = .triangles(indices)
            return try? MeshResource.generate(from: [descriptor])
        }
    }

    struct LocalGeometry {
        let structure: Geometry
        let seats: Geometry
        let roof: Geometry
        let lights: Geometry
        let sky: Geometry
        let ground: Geometry
        var stadium: [Geometry] { [structure, seats, roof, lights] }
        var triangleCount: Int { stadium.reduce(sky.triangleCount + ground.triangleCount) { $0 + $1.triangleCount } }
    }

    // Immutable CPU geometry and GPU templates are each prepared once, including
    // a failed preparation. Re-entry never retries texture or mesh construction.
    static let geometry = makeGeometry()
    private static let templates = makeTemplates()

    private struct Templates {
        let sky: Entity
        let stadium: Entity
    }

    static func prewarm() { _ = templates }

    /// Add directly to RealityView content. Keep room-fixed and unscaled. The
    /// floor is a plain backdrop below Y=0, not turf or a physical play surface.
    static func makeSkyRoot() -> Entity { templates.sky.clone(recursive: true) }

    /// Seated POV can put the virtual pitch below the room origin. The sky
    /// remains room-fixed, but its opaque floor must stay below that pitch.
    static func placeBackdropBelowPitch(in sky: Entity, pitchHeight: Float) {
        guard pitchHeight.isFinite,
              let floor = sky.children.first(where: { $0.name == "local-backdrop-floor" }) else { return }
        let offset = min(0, pitchHeight)
        if floor.position.y != offset { floor.position.y = offset }
    }

    /// Metres, Y-up, centred on the existing 68 × 105m pitch. No field, goals,
    /// collision, input or physics components. Clone visibility is independent.
    /// Keep full-sized around the wearer for tabletop; align with the match
    /// transform for first-person. Disable during physical placement.
    static func makeStadium() -> Entity { templates.stadium.clone(recursive: true) }

    /// Full immersion cannot rely on passthrough lighting. Two fixed lights
    /// illuminate the match, not the unlit scenery, without shadow render passes.
    /// Keep this root unscaled and disable it when returning to Room mode.
    static func makeReplayLighting() -> Entity {
        let root = Entity()
        root.name = lightingRootName
        let key = DirectionalLight()
        key.name = "stadium-key"
        key.light.intensity = 2_200
        key.look(at: .zero, from: [-3, 4, 3], relativeTo: nil)
        key.components.remove(DirectionalLightComponent.Shadow.self)
        let fill = DirectionalLight()
        fill.name = "stadium-fill"
        fill.light.intensity = 500
        fill.look(at: .zero, from: [3, 2, -2], relativeTo: nil)
        fill.components.remove(DirectionalLightComponent.Shadow.self)
        root.addChild(key)
        root.addChild(fill)
        return root
    }

    static var preparationSucceeded: Bool {
        templates.sky.children.count == 2 && templates.stadium.children.count == 4
    }

    private static func makeTemplates() -> Templates {
        let skyRoot = Entity()
        skyRoot.name = skyRootName
        skyRoot.components.set(Provenance(source: sourceDescription))
        var skyMaterial = UnlitMaterial(color: UIColor(red: 0.035, green: 0.065, blue: 0.13, alpha: 1),
                                        applyPostProcessToneMap: false)
        if let texture = makeSkyTexture() {
            skyMaterial.color = .init(tint: .white, texture: .init(texture))
        }
        append(geometry.sky, name: "local-twilight-sky", material: skyMaterial, to: skyRoot)
        append(geometry.ground, name: "local-backdrop-floor",
               material: UnlitMaterial(color: UIColor(red: 0.045, green: 0.07, blue: 0.065, alpha: 1),
                                       applyPostProcessToneMap: false), to: skyRoot)

        let stadium = Entity()
        stadium.name = stadiumRootName
        stadium.components.set(Provenance(source: sourceDescription))
        append(geometry.structure, name: "local-stadium-structure",
               material: UnlitMaterial(color: UIColor(red: 0.075, green: 0.115, blue: 0.16, alpha: 1),
                                       applyPostProcessToneMap: false), to: stadium)
        append(geometry.seats, name: "local-stadium-teal-tiers",
               material: UnlitMaterial(color: UIColor(red: 0.08, green: 0.26, blue: 0.29, alpha: 1),
                                       applyPostProcessToneMap: false), to: stadium)
        append(geometry.roof, name: "local-stadium-open-roof",
               material: UnlitMaterial(color: UIColor(red: 0.11, green: 0.17, blue: 0.22, alpha: 1),
                                       applyPostProcessToneMap: false), to: stadium)
        // Bright panels provide the look of floodlights, with no actual lights,
        // shadow passes or per-frame light evaluation.
        append(geometry.lights, name: "local-stadium-light-panels",
               material: UnlitMaterial(color: UIColor(red: 0.75, green: 0.93, blue: 0.96, alpha: 1),
                                       applyPostProcessToneMap: false), to: stadium)
        return Templates(sky: skyRoot, stadium: stadium)
    }

    private static func append(_ geometry: Geometry, name: String, material: UnlitMaterial, to root: Entity) {
        guard let mesh = geometry.makeMesh(name: name) else { return }
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.name = name
        root.addChild(model)
    }

    private static func makeGeometry() -> LocalGeometry {
        var structure = Geometry(), seats = Geometry(), roof = Geometry(), lights = Geometry()
        let rows = 28
        let depth: Float = 0.9, rise: Float = 0.65
        for row in 0..<rows {
            let radius = 4 + Float(row) * depth
            let lowerY = Float(row) * rise
            // From the pitch, upper horizontal treads face away from the eye.
            // A seat-coloured front on each tier keeps the bowl readable at
            // standing head height without more materials or model entities.
            let seatFrontY = lowerY + rise - 0.26
            wall(radius: radius, lowerY: lowerY, upperY: seatFrontY, inward: true, into: &structure)
            wall(radius: radius, lowerY: seatFrontY, upperY: lowerY + rise, inward: true, into: &seats)
            ring(inner: radius, outer: radius + depth, innerY: lowerY + rise,
                 outerY: lowerY + rise, upward: true, into: &seats)
        }
        wall(radius: 4 + Float(rows) * depth, lowerY: 0, upperY: Float(rows) * rise,
             inward: false, into: &structure)
        ring(inner: 0.15, outer: 4, innerY: -0.025, outerY: -0.025, upward: true, into: &structure)

        ring(inner: 20, outer: 33, innerY: 23.8, outerY: 22.2, upward: true, into: &roof)
        ring(inner: 20, outer: 33, innerY: 23.3, outerY: 21.7, upward: false, into: &roof)
        wall(radius: 20, lowerY: 23.3, upperY: 23.8, inward: true, into: &roof)
        wall(radius: 33, lowerY: 21.7, upperY: 22.2, inward: false, into: &roof)

        let supports = outline(radius: 32, y: 10.85)
        let panels = outline(radius: 20.4, y: 23)
        for index in stride(from: 0, to: supports.count, by: 4) {
            structure.box(centre: supports[index], along: [0.6, 0, 0], across: [0, 0, 0.6], height: 21.7)
            let previous = panels[(index + panels.count - 1) % panels.count]
            let next = panels[(index + 1) % panels.count]
            let tangent = simd_normalize(next - previous)
            let across = simd_cross(tangent, SIMD3<Float>(0, 1, 0))
            for offset in [-1, 0, 1] {
                lights.box(centre: panels[index] + tangent * Float(offset) * 1.9,
                           along: tangent * 1.65, across: across * 0.5, height: 0.3)
            }
        }
        var ground = Geometry()
        ground.quad([-150, groundY, -150], [-150, groundY, 150],
                    [150, groundY, 150], [150, groundY, -150], normal: [0, 1, 0])
        return LocalGeometry(structure: structure, seats: seats, roof: roof, lights: lights,
                             sky: makeSkyGeometry(), ground: ground)
    }

    /// Rounded rectangle enclosing the clear 72 × 112m opening. Corner centres
    /// are on its corners, so neither tiers nor roof cut across the field.
    private static func outline(radius: Float, y: Float) -> [SIMD3<Float>] {
        let centres: [SIMD2<Float>] = [[clearHalfWidth, clearHalfLength],
                                      [-clearHalfWidth, clearHalfLength],
                                      [-clearHalfWidth, -clearHalfLength],
                                      [clearHalfWidth, -clearHalfLength]]
        return (0..<32).map { index in
            let corner = index / 8
            let angle = (Float(corner) + Float(index % 8) / 7) * .pi / 2
            return [centres[corner].x + cos(angle) * radius, y,
                    centres[corner].y + sin(angle) * radius]
        }
    }

    private static func ring(inner: Float, outer: Float, innerY: Float, outerY: Float,
                             upward: Bool, into geometry: inout Geometry) {
        let a = outline(radius: inner, y: innerY), b = outline(radius: outer, y: outerY)
        for index in a.indices {
            let next = (index + 1) % a.count
            geometry.quad(a[index], a[next], b[next], b[index], normal: upward ? [0, 1, 0] : [0, -1, 0])
        }
    }

    private static func wall(radius: Float, lowerY: Float, upperY: Float,
                             inward: Bool, into geometry: inout Geometry) {
        let lower = outline(radius: radius, y: lowerY), upper = outline(radius: radius, y: upperY)
        for index in lower.indices {
            let next = (index + 1) % lower.count
            var normal = lower[index] + lower[next]
            normal.y = 0
            if inward { normal = -normal }
            geometry.quad(lower[index], lower[next], upper[next], upper[index], normal: normal)
        }
    }

    private static func makeSkyGeometry() -> Geometry {
        let longitudeCount = 32, latitudeCount = 16
        var result = Geometry()
        for latitude in 0...latitudeCount {
            let v = Float(latitude) / Float(latitudeCount)
            let polar = v * .pi
            for longitude in 0...longitudeCount {
                let u = Float(longitude) / Float(longitudeCount)
                let azimuth = u * 2 * .pi
                let direction = SIMD3<Float>(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
                result.positions.append(direction * skyRadius)
                result.normals.append(-direction)
                result.textureCoordinates.append([u, v])
            }
        }
        func appendTriangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
            let p = result.positions[Int(a)], q = result.positions[Int(b)], r = result.positions[Int(c)]
            let inward = -(p + q + r)
            result.indices.append(contentsOf: simd_dot(simd_cross(q - p, r - p), inward) > 0 ? [a, b, c] : [a, c, b])
        }
        for latitude in 0..<latitudeCount {
            for longitude in 0..<longitudeCount {
                let a = UInt32(latitude * (longitudeCount + 1) + longitude)
                let b = a + 1, c = a + UInt32(longitudeCount + 1), d = c + 1
                if latitude > 0 { appendTriangle(a, b, c) }
                if latitude < latitudeCount - 1 { appendTriangle(b, d, c) }
            }
        }
        return result
    }

    private static func makeSkyTexture() -> TextureResource? {
        var bytes: [UInt8] = []
        let zenith = SIMD3<Float>(0.025, 0.045, 0.11)
        let horizon = SIMD3<Float>(0.20, 0.32, 0.38)
        let nadir = SIMD3<Float>(0.035, 0.055, 0.07)
        for row in 0..<skyTextureHeight {
            let v = Float(row) / Float(skyTextureHeight - 1)
            let t = v <= 0.5 ? pow(v * 2, 2) : pow((1 - v) * 2, 3)
            let pole = v <= 0.5 ? zenith : nadir
            let colour = pole + (horizon - pole) * t
            bytes.append(contentsOf: [UInt8((colour.x * 255).rounded()), UInt8((colour.y * 255).rounded()),
                                      UInt8((colour.z * 255).rounded()), 255])
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: skyTextureWidth, height: skyTextureHeight,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                  space: space, bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                                    CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else { return nil }
        return try? TextureResource(image: image, options: .init(semantic: .color, compression: .none,
                                                                 mipmapsMode: .allocateAndGenerateAll))
    }
}
