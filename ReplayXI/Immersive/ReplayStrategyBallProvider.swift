import CryptoKit
import Foundation
import RealityKit
import simd

/// Original Blender-built ball. Import once before entering replay; clone the
/// cached mesh/material resources for subsequent scenes, never import per frame.
@MainActor
enum ReplayStrategyBallProvider {
    static let visualRootName = "original-blender-ball"
    static let assetSHA256 = "4defbfdcdf09df651f11340cb52778890f609b556ff84e628cf93713a8798911"
    private static var template: Entity?
    static var isPrewarmed: Bool { template != nil }

    enum AssetError: Error { case missing, changed, invalidGeometry }

    static func prewarm(in bundle: Bundle = .main) throws {
        guard template == nil else { return }
        guard let url = bundle.url(forResource: "ReplayXIStrategyBall", withExtension: "usdz",
                                   subdirectory: "Resources/Strategy")
                ?? bundle.url(forResource: "ReplayXIStrategyBall", withExtension: "usdz")
        else { throw AssetError.missing }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == assetSHA256 else { throw AssetError.changed }
        let loaded = try Entity.load(contentsOf: url)
        let models = models(in: loaded)
        let bounds = loaded.visualBounds(relativeTo: loaded)
        guard models.count == 1,
              models[0].model?.materials.count == 2,
              bounds.extents.min() > 0.21, bounds.extents.max() < 0.225,
              length(bounds.center) < 0.002
        else { throw AssetError.invalidGeometry }
        loaded.name = visualRootName
        template = loaded
    }

    static func makeInstance() -> Entity? {
        template?.clone(recursive: true)
    }

    static func models(in root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? [])
            + root.children.flatMap { models(in: $0) }
    }
}
