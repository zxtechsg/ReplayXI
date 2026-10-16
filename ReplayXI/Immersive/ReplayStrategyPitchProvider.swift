import CryptoKit
import Foundation
import RealityKit
import simd
import UIKit

/// Original Blender pitch. Import before room entry, then reuse mesh/texture
/// resources. Semantic child names preserve contrast and physical-drill hiding.
@MainActor
enum ReplayStrategyPitchProvider {
    struct Admission: Component {}
    static let assetSHA256 = "982ca747a1ac9eddde558ad3af470119256f5b261d3e666818aaa3c108da0197"
    static let triangleBudget = 8_000
    private static var template: Entity?
    static var isPrewarmed: Bool { template != nil }

    enum AssetError: Error { case missing, changed, invalidGeometry(String) }

    static func prewarm(in bundle: Bundle = .main) throws {
        guard template == nil else { return }
        guard let url = bundle.url(forResource: "ReplayXIStrategyPitch", withExtension: "usdz",
                                   subdirectory: "Resources/Strategy")
                ?? bundle.url(forResource: "ReplayXIStrategyPitch", withExtension: "usdz")
        else { throw AssetError.missing }
        let data = try Data(contentsOf: url)
        guard data.count < 1_500_000,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == assetSHA256
        else { throw AssetError.changed }
        let loaded = try Entity.load(contentsOf: url)
        let sourceModels = models(in: loaded)
        guard sourceModels.count == 2,
              sourceModels.allSatisfy({ $0.model?.materials.count == 2 }),
              triangleCount(in: loaded) <= triangleBudget
        else {
            throw AssetError.invalidGeometry(
                "Models: \(sourceModels.count), materials: \(sourceModels.map { $0.model?.materials.count ?? 0 }), triangles: \(triangleCount(in: loaded))"
            )
        }

        // Flatten only the two static models, keeping each accumulated import
        // transform (including Blender's up-axis conversion). No per-frame lookup.
        let root = Entity()
        for source in sourceModels {
            let model = source.clone(recursive: false)
            // `loaded` itself carries USD's Z-up → Y-up rotation. Relative-to-
            // loaded would discard that rotation and leave the entire pitch upright.
            model.setTransformMatrix(source.transformMatrix(relativeTo: nil), relativeTo: root)
            let bounds = source.visualBounds(relativeTo: nil)
            model.name = bounds.extents.y < 0.01 ? "field-surface" : "pitch-markings-and-goals"
            if model.name == "field-surface", var component = model.model {
                // A strategy surface must stay legible in a dim/warm physical
                // room. Keep the authored turf textures without room-light tint.
                component.materials = try component.materials.map { material in
                    guard let pbr = material as? PhysicallyBasedMaterial,
                          let texture = pbr.baseColor.texture else {
                        throw AssetError.invalidGeometry("Missing original turf texture")
                    }
                    var stable = UnlitMaterial(color: .white, applyPostProcessToneMap: false)
                    stable.color = .init(tint: .white, texture: texture)
                    stable.faceCulling = .none
                    return stable
                }
                model.model = component
            } else if model.name == "pitch-markings-and-goals", var component = model.model {
                // Initial tactical entry never changes contrast mode. Give it
                // legible lines immediately, even without stadium lighting.
                component.materials[0] = UnlitMaterial(
                    color: UIColor(red: 0.94, green: 0.93, blue: 0.82, alpha: 1),
                    applyPostProcessToneMap: false)
                model.model = component
            }
            root.addChild(model)
        }
        let bounds = root.visualBounds(relativeTo: root)
        guard root.children.contains(where: { $0.name == "field-surface" }),
              root.children.contains(where: { $0.name == "pitch-markings-and-goals" }),
              abs(bounds.extents.x - 72) < 0.02,
              abs(bounds.extents.z - 111) < 0.02,
              abs(bounds.extents.y - 2.56) < 0.02,
              abs(bounds.min.y) < 0.01
        else {
            throw AssetError.invalidGeometry(
                "Extents: \(bounds.extents), minimum: \(bounds.min), children: \(root.children.map(\.name)), import transform: \(loaded.transform)"
            )
        }
        root.components.set(Admission())
        template = root
    }

    static func makeInstance() -> Entity? { template?.clone(recursive: true) }

    static func models(in root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? [])
            + root.children.flatMap { models(in: $0) }
    }

    static func triangleCount(in root: Entity) -> Int {
        models(in: root).reduce(0) { total, model in
            total + (model.model?.mesh.contents.models.reduce(0) { count, mesh in
                count + mesh.parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 }
            } ?? 0)
        }
    }
}
