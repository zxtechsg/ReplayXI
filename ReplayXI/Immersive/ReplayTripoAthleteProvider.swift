import CryptoKit
import Foundation
import RealityKit
import UIKit

/// The FBX-derived player has its own exact 52-joint asset contract. The
/// Rocketbox provider remains independent and is never given Tripo data.
@MainActor
enum ReplayTripoAthleteProvider {
    // Filled only from the audited native build, never from downloaded GLBs.
    static let assetSHA256 = "af01e0ea9e8e4ae6d9dae068f87fe03f1550732583a553eb64660ce1bd6afe90"
    static let lowAssetSHA256 = "48712cb85bc92c798fd7c6dc53ef721f43a0797db7739facd61f30449e80b390"
    static let motionSHA256 = "877857959a46e2ea1c47de3fbbf5822ff8e774d20c973f1e9eade55ff578a84f"
    static let contactSHA256 = "ae384cf32679b5f57851a5b10032ba0fc41892605c98c81030ba77104ba8007e"
    static let lowContactSHA256 = "f12a6d033535790654af6c75b80c8afb5decf4c2125cc12a0a1dd2a18bc1aa92"
    static let skinVertices = 9_075
    static let skinTriangles = 7_685
    static let lowSkinVertices = 3_269
    static let lowSkinTriangles = 1_964
    static let materialDrawsPerInstance = 3 // One skin plus front/back numbers.
    static let decodedTextureBytes = 3 * 2_048 * 2_048 * 4 // Base levels only.
    private static let kitPixelHashes = [
        "800ab6749d04b18694f0a9413f9e83a10a3606d2f4394a705de11b8564f9634b",
        "d70cb2de0946ce41113d4a5e28e21f7b4a55f8920cf58969c8fe80d6a0fee677",
        "b4a32492c3a9c8c7ee134b006a489741e046cf0f07c54c19d2448086ed3208f7"
    ]

    private struct Skin {
        let template: Entity
        let contacts: ReplaySkinnedAthleteContactSurface
        let boots: ReplaySkinnedAthleteBootMarkers
    }
    private static var near: Skin?
    private static var low: Skin?
    private(set) static var motion: ReplaySkinnedAthleteMotion?
    private static var kits: [PhysicallyBasedMaterial] = []
    static var isPrewarmed: Bool { near != nil && low != nil && motion != nil && kits.count == 3 }

    /// Both detail levels and all team kits are published together. An invalid
    /// resource leaves the existing renderer available, not half a new squad.
    static func prewarm(in bundle: Bundle = .main) throws {
        guard !isPrewarmed else { return }
        let preparedMotion = try ReplaySkinnedAthleteMotion(
            data: data("ReplayXITripoMotion", "json", hash: motionSHA256, in: bundle), profile: .tripo52)
        let preparedNear = try loadSkin(name: "ReplayXITripoAthlete", hash: assetSHA256,
            contactName: "ReplayXITripoContactSurface", contactHash: contactSHA256,
            vertices: skinVertices, triangles: skinTriangles, detail: .near,
            motion: preparedMotion, bundle: bundle)
        let preparedLow = try loadSkin(name: "ReplayXITripoLow", hash: lowAssetSHA256,
            contactName: "ReplayXITripoLowContactSurface", contactHash: lowContactSHA256,
            vertices: lowSkinVertices, triangles: lowSkinTriangles, detail: .lowDetail,
            motion: preparedMotion, bundle: bundle)
        var preparedKits: [PhysicallyBasedMaterial] = []
        for (index, kit) in ["Home", "Away", "Keeper"].enumerated() {
            let name = "ReplayXITripo\(kit)"
            let url = try resource(name, "png", in: bundle)
            let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard metadata.isRegularFile == true, let encodedBytes = metadata.fileSize,
                  (1...12 * 1_024 * 1_024).contains(encodedBytes)
            else { throw ReplayArticulatedFarKitProvider.PreparationError.invalidTexture }
            let textureData = try Data(contentsOf: url, options: .mappedIfSafe)
            let pixels = try ReplayTexturePixels.rgbaPNG(textureData, size: 2_048,
                maximumEncodedBytes: 12 * 1_024 * 1_024)
            guard SHA256.hash(data: pixels).map({ String(format: "%02x", $0) }).joined() == kitPixelHashes[index]
            else { throw ReplaySkinnedAthleteError.invalidHash(name) }
            let texture = try TextureResource.load(contentsOf: url)
            guard texture.width == 2_048, texture.height == 2_048 else {
                throw ReplayArticulatedFarKitProvider.PreparationError.invalidTexture
            }
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = .init(floatLiteral: 0.78)
            material.metallic = .init(floatLiteral: 0)
            preparedKits.append(material)
        }
        // Replace the neutral imported material on both templates. Clones
        // share the same three atlases; there is no per-player texture decode.
        for skin in [preparedNear, preparedLow] {
            guard let model = ReplaySkinnedAthleteProvider.skinnedModels(in: skin.template).first,
                  var component = model.model else { throw ReplaySkinnedAthleteError.invalidSkeleton }
            component.materials = [preparedKits[0]]
            model.model = component
        }
        near = preparedNear
        low = preparedLow
        motion = preparedMotion
        kits = preparedKits
    }

    private static func loadSkin(name: String, hash: String, contactName: String, contactHash: String,
                                 vertices: Int, triangles: Int, detail: ReplaySkinnedAthleteProvider.Detail,
                                 motion: ReplaySkinnedAthleteMotion, bundle: Bundle) throws -> Skin {
        let url = try resource(name, "usdz", in: bundle)
        _ = try checkedData(url, hash: hash)
        let contact = try ReplaySkinnedAthleteContactSurface(
            data: data(contactName, "json", hash: contactHash, in: bundle), motion: motion,
            assetSHA256: hash, motionSHA256: motionSHA256,
            profile: detail == .near ? .tripoNear(sourceVertexCount: vertices) : .tripoLow(sourceVertexCount: vertices))
        guard (64...96).contains(contact.headerProbeCount) else {
            throw ReplaySkinnedAthleteError.invalidSkeleton
        }
        let loaded = try Entity.load(contentsOf: url)
        loaded.stopAllAnimations(recursive: true)
        let models = ReplaySkinnedAthleteProvider.skinnedModels(in: loaded)
        guard models.count == 1, let model = models.first,
              model.jointNames == motion.jointNames,
              model.jointTransforms.count == 52, let component = model.model
        else { throw ReplaySkinnedAthleteError.invalidSkeleton }
        let parts = component.mesh.contents.models.flatMap { Array($0.parts) }
        guard component.materials.count == 1, component.materials[0] is PhysicallyBasedMaterial,
              parts.count == 1, let part = parts.first, part.id == "Body", part.materialIndex == 0,
              part.positions.count == vertices,
              (part.triangleIndices?.count ?? 0) == triangles * 3,
              let boots = ReplaySkinnedAthleteBootMarkers(model: model, motion: motion, maximumVertices: vertices)
        else { throw ReplaySkinnedAthleteError.invalidMaterials }
        guard let _ = ReplaySkinnedAthleteFootballPose(motion: motion, bootMarkers: boots),
              let _ = ReplaySkinnedAthleteImpactPose(motion: motion, contactSurface: contact)
        else { throw ReplaySkinnedAthleteError.invalidSkeleton }
        return Skin(template: loaded, contacts: contact, boots: boots)
    }

    static func make(for player: PlayerTrack, detail: ReplaySkinnedAthleteProvider.Detail = .near) throws
        -> ReplaySkinnedAthleteInstance {
        guard isPrewarmed, let motion, let skin = detail == .near ? near : low else {
            throw ReplaySkinnedAthleteError.notPrepared
        }
        let clone = skin.template.clone(recursive: true)
        clone.stopAllAnimations(recursive: true)
        guard let model = ReplaySkinnedAthleteProvider.skinnedModels(in: clone).first,
              var component = model.model else { throw ReplaySkinnedAthleteError.invalidSkeleton }
        component.materials = [kits[player.isGoalkeeper ? 2 : (player.team == .home ? 0 : 1)]]
        model.model = component
        let configuration = ReplayAthleteConfiguration(player: player)
        let root = Entity()
        root.name = ReplaySkinnedAthleteProvider.visualRootName
        root.scale = [configuration.appearance.widthScale, configuration.appearance.heightScale, 1]
        root.addChild(clone)
        let digits = try ReplayAthleteMeshLibrary.jerseyNumber(player.shirtNumber)
        let ink = UnlitMaterial(color: configuration.kit.number.uiColor, applyPostProcessToneMap: false)
        let front = ModelEntity(mesh: digits.mesh, materials: [ink])
        front.name = "skinned-chest-number"
        let back = ModelEntity(mesh: digits.mesh, materials: [ink])
        back.name = "skinned-shirt-number"
        clone.addChild(front)
        clone.addChild(back)
        return ReplaySkinnedAthleteInstance(root: root, skinRoot: clone, model: model, front: front, back: back,
            playerID: player.id, motion: motion, contactSurface: skin.contacts, detail: detail, bootMarkers: skin.boots)
    }

    // The scene cache still owns instances; render selection is local and does
    // not alter tracks, replay clocks, annotations or saved-review schemas.
    static var preferredIsReady: Bool { isPrewarmed || ReplaySkinnedAthleteProvider.isPrewarmed }
    static var preferredLowIsReady: Bool { isPrewarmed || ReplaySkinnedAthleteProvider.isLowDetailPrewarmed }
    static func makePreferred(for player: PlayerTrack, detail: ReplaySkinnedAthleteProvider.Detail) throws
        -> ReplaySkinnedAthleteInstance {
        if isPrewarmed, let skin = try? make(for: player, detail: detail) { return skin }
        return try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
    }

    private static func resource(_ name: String, _ suffix: String, in bundle: Bundle) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: suffix, subdirectory: "Resources/Players")
                ?? bundle.url(forResource: name, withExtension: suffix) else {
            throw ReplaySkinnedAthleteError.missingResource(name)
        }
        return url
    }
    private static func checkedData(_ url: URL, hash: String) throws -> Data {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else {
            throw ReplaySkinnedAthleteError.invalidHash(url.lastPathComponent)
        }
        return data
    }
    private static func data(_ name: String, _ suffix: String, hash: String, in bundle: Bundle) throws -> Data {
        try checkedData(resource(name, suffix, in: bundle), hash: hash)
    }

    #if DEBUG
    static func resetForTesting() { near = nil; low = nil; motion = nil; kits = [] }
    #endif
}
