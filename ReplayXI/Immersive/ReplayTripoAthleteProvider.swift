import CryptoKit
import Foundation
import Metal
import RealityKit
import UIKit

/// The FBX-derived player has its own exact 52-joint asset contract. The
/// Rocketbox provider remains independent and is never given Tripo data.
@MainActor
enum ReplayTripoAthleteProvider {
    // Filled only from the audited native build, never from downloaded GLBs.
    static let assetSHA256 = "25585fd5fff5dc0060178c52fa559fe217773acfeab1b578d44174cb85e890db"
    static let lowAssetSHA256 = "343a8ef2527ac236a20c1bbe73202f650829be008c1d5381b3618f35933b349d"
    static let motionSHA256 = "525b42f4377d16644d81dc46456169be33818ec806e37ffd18a7a2041072b4f2"
    static let recoveryMotionSHA256 = "12485c8ca93c09da6d8b326c76f007821d102f8181d48f411ace8445ef43e969"
    static let contactSHA256 = "054a10f93888f6ac4ac0a1505929ae1f4f9d4695d5dd418ba2a6fc815818fa05"
    static let lowContactSHA256 = "6efcdcd2a3df2fd4f48948e32f62b400c6750dec79480a7afd12262a83dd5061"
    // Contact sidecars describe the original UV-split source vertex arrays.
    // RealityKit expands welded USD face-varying UVs to its own vertex arrays.
    static let skinVertices = 9_075
    static let importedSkinVertices = 9_075
    static let skinTriangles = 7_685
    static let lowSkinVertices = 3_269
    static let lowImportedSkinVertices = 3_267
    static let lowSkinTriangles = 1_964
    static let materialDrawsPerInstance = 3 // One skin plus front/back numbers.
    static let diverseMaterialDrawsPerInstance = 4 // Plus the source head-island bridge.
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
        let numberSurface: ReplaySkinnedNumberSurface?
        let requiresNeckBridge: Bool
        let firstPersonBodyMesh: MeshResource?
    }
    private struct GeometryVariant {
        let near: Skin
        let low: Skin
        let motion: ReplaySkinnedAthleteMotion
        let kits: [PhysicallyBasedMaterial]
    }
    private static var near: Skin?
    private static var low: Skin?
    private static var diversity: GeometryVariant?
    private static var numberMeshes: [String: (front: MeshResource, back: MeshResource)] = [:]
    private static var numberMasks: [Int: TextureResource] = [:]
    static var loadedNumberMaskBaseBytes: Int { numberMasks.count * 256 * 256 * 4 }
    private(set) static var motion: ReplaySkinnedAthleteMotion?
    private static var kits: [PhysicallyBasedMaterial] = []
    private static let playerANeckMesh = MeshResource.generateCylinder(height: 1, radius: 0.052)
    private static var appearanceKits: [ReplayTripoAppearance.Palette: [PhysicallyBasedMaterial]] = [:]
    static var loadedAppearanceCount: Int { appearanceKits.count + (kits.isEmpty ? 0 : 1) }
    static var diversityIsPrewarmed: Bool { diversity != nil }
    static var loadedGeometryCount: Int { (isPrewarmed ? 1 : 0) + (diversityIsPrewarmed ? 1 : 0) }
    /// Base RGBA levels only; excludes mipmaps, native staging and geometry.
    static var loadedBaseTextureBytes: Int {
        (kits.isEmpty ? 0 : decodedTextureBytes)
            + appearanceKits.count * 3 * ReplayTripoAppearance.textureSize * ReplayTripoAppearance.textureSize * 4
            + (diversityIsPrewarmed ? ReplayTripoDiversityAssets.decodedTextureBytes : 0)
            + loadedNumberMaskBaseBytes
    }
    static var isPrewarmed: Bool { near != nil && low != nil && motion != nil && kits.count == 3 }
    static func firstPersonBodyIsReady(for player: PlayerTrack) -> Bool {
        guard isPrewarmed else { return false }
        if prefersDiverseGeometry(for: player), let diversity {
            return diversity.near.firstPersonBodyMesh != nil
        }
        return near?.firstPersonBodyMesh != nil
    }

    #if DEBUG
    private(set) static var nativeAssetLoadAttemptsForTesting = 0
    private(set) static var texturePreparationAttemptsForTesting = 0
    private(set) static var diversityPreparationErrorForTesting: String?
    #endif

    /// Both detail levels and all team kits are published together. An invalid
    /// resource leaves the existing renderer available, not half a new squad.
    static func prewarm(in bundle: Bundle = .main) throws {
        guard !isPrewarmed else { return }
        var preparedMotion = try ReplaySkinnedAthleteMotion(
            data: data("ReplayXITripoMotion", "json", hash: motionSHA256, in: bundle), profile: .tripo52)
        // Optional extension is source/base hash-bound. Missing or invalid
        // recovery data never replaces the validated base locomotion.
        if let recovery = try? data("ReplayXITripoRecoveryMotion", "json", hash: recoveryMotionSHA256, in: bundle),
           let extended = try? preparedMotion.addingSlowRun(data: recovery, baseMotionSHA256: motionSHA256) {
            preparedMotion = extended
        }
        let preparedNear = try loadSkin(name: "ReplayXITripoAthlete", hash: assetSHA256,
            contactName: "ReplayXITripoContactSurface", contactHash: contactSHA256,
            sourceVertices: skinVertices, importedVertices: importedSkinVertices,
            triangles: skinTriangles, detail: .near,
            motion: preparedMotion, motionHash: motionSHA256, bundle: bundle)
        let preparedLow = try loadSkin(name: "ReplayXITripoLow", hash: lowAssetSHA256,
            contactName: "ReplayXITripoLowContactSurface", contactHash: lowContactSHA256,
            sourceVertices: lowSkinVertices, importedVertices: lowImportedSkinVertices,
            triangles: lowSkinTriangles, detail: .lowDetail,
            motion: preparedMotion, motionHash: motionSHA256, bundle: bundle)
        var preparedKits: [PhysicallyBasedMaterial] = []
        for (index, kit) in ["Home", "Away", "Keeper"].enumerated() {
            preparedKits.append(try textureMaterial(name: "ReplayXITripo\(kit)", size: 2_048,
                pixelSHA256: kitPixelHashes[index], bundle: bundle))
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
        // Publish each complete palette atomically. A bad optional atlas falls
        // back to its original kit, without discarding the audited player rig.
        for palette in ReplayTripoAppearance.Palette.allCases where palette != .base {
            if let prepared = try? ReplayTripoAppearance.atlases(for: palette).map({ atlas in
                try textureMaterial(name: atlas.name, size: ReplayTripoAppearance.textureSize,
                    pixelSHA256: atlas.pixelSHA256, bundle: bundle)
            }), prepared.count == 3 {
                appearanceKits[palette] = prepared
            }
        }
        // Publish a whole identity only after both levels, its own motion,
        // contacts and team atlases pass admission. A partial download cannot
        // give a player a different body when the detail level changes.
        do {
            diversity = try loadDiversity(in: bundle)
        } catch {
            #if DEBUG
            diversityPreparationErrorForTesting = String(describing: error)
            #endif
        }
    }

    private static func loadDiversity(in bundle: Bundle) throws -> GeometryVariant {
        _ = playerANeckMesh // Build with the other immutable meshes before immersion.
        let source = ReplayTripoDiversityAssets.motion
        let motion = try ReplaySkinnedAthleteMotion(
            data: data(source.name, "json", hash: source.sha256, in: bundle), profile: .tripo52)
        func skin(_ spec: ReplayTripoDiversityAssets.Skin,
                  detail: ReplaySkinnedAthleteProvider.Detail) throws -> Skin {
            try loadSkin(name: spec.asset.name, hash: spec.asset.sha256,
                contactName: spec.contacts.name, contactHash: spec.contacts.sha256,
                sourceVertices: spec.sourceVertices, importedVertices: spec.importedVertices,
                triangles: spec.triangles, detail: detail, motion: motion,
                motionHash: source.sha256, bundle: bundle, requiresNeckBridge: true)
        }
        let near = try skin(ReplayTripoDiversityAssets.near, detail: .near)
        let low = try skin(ReplayTripoDiversityAssets.low, detail: .lowDetail)
        let kits = try ReplayTripoDiversityAssets.atlases.map {
            try textureMaterial(name: $0.name, size: ReplayTripoDiversityAssets.textureSize,
                                pixelSHA256: $0.sha256, bundle: bundle, doubleSided: true)
        }
        guard kits.count == 3 else { throw ReplaySkinnedAthleteError.invalidMaterials }
        return GeometryVariant(near: near, low: low, motion: motion, kits: kits)
    }

    private static func textureMaterial(name: String, size expectedSize: Int, pixelSHA256: String,
                                        bundle: Bundle, doubleSided: Bool = false) throws
        -> PhysicallyBasedMaterial {
        #if DEBUG
        texturePreparationAttemptsForTesting += 1
        #endif
        let url = try resource(name, "png", in: bundle)
        let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard metadata.isRegularFile == true, let size = metadata.fileSize,
              (1...12 * 1_024 * 1_024).contains(size) else {
            throw ReplayArticulatedFarKitProvider.PreparationError.invalidTexture
        }
        let pixels = try ReplayTexturePixels.rgbaPNG(Data(contentsOf: url, options: .mappedIfSafe),
            size: expectedSize, maximumEncodedBytes: 12 * 1_024 * 1_024)
        guard SHA256.hash(data: pixels).map({ String(format: "%02x", $0) }).joined() == pixelSHA256 else {
            throw ReplaySkinnedAthleteError.invalidHash(name)
        }
        let texture = try TextureResource.load(contentsOf: url)
        guard texture.width == expectedSize, texture.height == expectedSize else {
            throw ReplayArticulatedFarKitProvider.PreparationError.invalidTexture
        }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.roughness = .init(floatLiteral: 0.78)
        material.metallic = .init(floatLiteral: 0)
        // The generated garment has thin folds that can turn inward in a pose.
        // Retain both sides without duplicating mesh geometry or draw calls.
        if doubleSided { material.faceCulling = .none }
        return material
    }

    private static func loadSkin(name: String, hash: String, contactName: String, contactHash: String,
                                 sourceVertices: Int, importedVertices: Int, triangles: Int,
                                 detail: ReplaySkinnedAthleteProvider.Detail,
                                 motion: ReplaySkinnedAthleteMotion,
                                 motionHash: String, bundle: Bundle,
                                 requiresNeckBridge: Bool = false) throws -> Skin {
        let url = try resource(name, "usdz", in: bundle)
        _ = try checkedData(url, hash: hash)
        let contact = try ReplaySkinnedAthleteContactSurface(
            data: data(contactName, "json", hash: contactHash, in: bundle), motion: motion,
            assetSHA256: hash, motionSHA256: motionHash,
            profile: detail == .near ? .tripoNear(sourceVertexCount: sourceVertices)
                                    : .tripoLow(sourceVertexCount: sourceVertices))
        guard (64...96).contains(contact.headerProbeCount) else {
            throw ReplaySkinnedAthleteError.invalidSkeleton
        }
        #if DEBUG
        nativeAssetLoadAttemptsForTesting += 1
        #endif
        let loaded = try Entity.load(contentsOf: url)
        loaded.stopAllAnimations(recursive: true)
        let models = ReplaySkinnedAthleteProvider.skinnedModels(in: loaded)
        guard models.count == 1, let model = models.first,
              model.jointNames == motion.jointNames,
              model.jointTransforms.count == 52, let component = model.model
        else { throw ReplaySkinnedAthleteError.invalidSkeleton }
        var parts = component.mesh.contents.models.lazy.flatMap { $0.parts }.makeIterator()
        guard component.materials.count == 1, component.materials[0] is PhysicallyBasedMaterial,
              let part = parts.next(), parts.next() == nil, part.id == "Body", part.materialIndex == 0,
              part.positions.count == importedVertices,
              part.normals?.rate == .vertex, part.normals?.count == importedVertices,
              part.textureCoordinates?.rate == .vertex,
              part.textureCoordinates?.count == importedVertices,
              part.jointInfluences?.influences.count == importedVertices * 4,
              (part.triangleIndices?.count ?? 0) == triangles * 3,
              let boots = ReplaySkinnedAthleteBootMarkers(model: model, motion: motion,
                                                          maximumVertices: sourceVertices)
        else { throw ReplaySkinnedAthleteError.invalidMaterials }
        guard let _ = ReplaySkinnedAthleteFootballPose(motion: motion, bootMarkers: boots),
              let _ = ReplaySkinnedAthleteImpactPose(motion: motion, contactSurface: contact)
        else { throw ReplaySkinnedAthleteError.invalidSkeleton }
        return Skin(template: loaded, contacts: contact, boots: boots,
                    numberSurface: ReplaySkinnedNumberSurface(model: model, motion: motion),
                    requiresNeckBridge: requiresNeckBridge,
                    firstPersonBodyMesh: try? ReplayFirstPersonBodyMesh.make(from: model, motion: motion))
    }

    static func make(for player: PlayerTrack, detail: ReplaySkinnedAthleteProvider.Detail = .near) throws
        -> ReplaySkinnedAthleteInstance {
        guard isPrewarmed, let motion, let skin = detail == .near ? near : low else {
            throw ReplaySkinnedAthleteError.notPrepared
        }
        let palette = ReplayTripoAppearance.palette(for: player)
        let playerKits = appearanceKits[palette] ?? kits
        return try makeInstance(for: player, detail: detail, skin: skin, motion: motion, kits: playerKits)
    }

    /// Distribute the two verified geometries across each team. Kit palette is
    /// independent: a skin tone does not determine a player's body/face shape.
    static func prefersDiverseGeometry(for player: PlayerTrack) -> Bool {
        !player.shirtNumber.isMultiple(of: 2)
    }

    static func makeDiverse(for player: PlayerTrack, detail: ReplaySkinnedAthleteProvider.Detail = .near) throws
        -> ReplaySkinnedAthleteInstance {
        guard let diversity else { throw ReplaySkinnedAthleteError.notPrepared }
        return try makeInstance(for: player, detail: detail,
            skin: detail == .near ? diversity.near : diversity.low,
            motion: diversity.motion, kits: diversity.kits)
    }

    private static func makeInstance(for player: PlayerTrack, detail: ReplaySkinnedAthleteProvider.Detail,
                                     skin: Skin, motion: ReplaySkinnedAthleteMotion,
                                     kits: [PhysicallyBasedMaterial]) throws -> ReplaySkinnedAthleteInstance {
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
        var ink = UnlitMaterial(color: configuration.kit.number.uiColor, applyPostProcessToneMap: false)
        let numberKey = "\(skin.requiresNeckBridge)-\(detail)-\(player.shirtNumber)"
        let conforming: (front: MeshResource, back: MeshResource)?
        if let cached = numberMeshes[numberKey] {
            conforming = cached
        } else if let surface = skin.numberSurface,
                  let frontMesh = try surface.clothDecalMesh(from: digits.mesh, isFront: true, scale: 0.115),
                  let backMesh = try surface.clothDecalMesh(from: digits.mesh, isFront: false, scale: 0.23) {
            conforming = (frontMesh, backMesh)
            numberMeshes[numberKey] = (frontMesh, backMesh)
        } else { conforming = nil }
        if conforming != nil {
            let mask: TextureResource
            if let cached = numberMasks[player.shirtNumber] { mask = cached }
            else {
                mask = try numberMask(for: player.shirtNumber, digit: digits.mesh)
                numberMasks[player.shirtNumber] = mask
            }
            let descriptor = MTLSamplerDescriptor()
            descriptor.sAddressMode = .clampToZero
            descriptor.tAddressMode = .clampToZero
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .linear
            let sampler = MaterialParameters.Texture.Sampler(descriptor)
            ink.color = .init(tint: configuration.kit.number.uiColor,
                texture: .init(mask, sampler: sampler))
            // Native A/B showed alpha cutout perforating thin strokes. Blended
            // opacity keeps the same cached cloth decal and solid ink.
            ink.opacityThreshold = nil
            ink.blending = .transparent(opacity: .init(texture: ink.color.texture))
        }
        let front = ModelEntity(mesh: conforming?.front ?? digits.mesh, materials: [ink])
        front.name = "skinned-chest-number"
        let back = ModelEntity(mesh: conforming?.back ?? digits.mesh, materials: [ink])
        back.name = "skinned-shirt-number"
        clone.addChild(front)
        clone.addChild(back)
        var neckBridge: ModelEntity?
        if skin.requiresNeckBridge {
            // The Player A source contains a detached head mesh island. This
            // small FK-driven bridge stays inside its head/collar envelope.
            // The tint is sampled from a verified common skin texel (410,260)
            // in all three unchanged 1024 px Player A kit atlases.
            var skinMaterial = PhysicallyBasedMaterial()
            skinMaterial.baseColor = .init(tint: UIColor(red: 75 / 255, green: 56 / 255,
                blue: 52 / 255, alpha: 1))
            skinMaterial.roughness = .init(floatLiteral: 0.78)
            let bridge = ModelEntity(mesh: playerANeckMesh, materials: [skinMaterial])
            bridge.name = "skinned-neck-bridge"
            clone.addChild(bridge)
            neckBridge = bridge
        }
        return ReplaySkinnedAthleteInstance(root: root, skinRoot: clone, model: model, front: front, back: back,
            playerID: player.id, motion: motion, contactSurface: skin.contacts, detail: detail,
            bootMarkers: skin.boots, numberSurface: skin.numberSurface,
            numbersUseShirtSkin: conforming != nil, neckBridge: neckBridge,
            firstPersonBodyMesh: skin.firstPersonBodyMesh)
    }

    private static func numberMask(for number: Int, digit: MeshResource) throws -> TextureResource {
        let image = try numberMaskImage(number: number, digit: digit)
        return try TextureResource(image: image,
            withName: "replay-shirt-number-mask-\(number)",
            options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
    }

    /// A bold system numeral is rasterized once, then projected onto the
    /// original weighted shirt triangles. The seven-segment mesh stays as the
    /// no-texture fallback, but does not determine the close-player typography.
    static func numberMaskImage(number: Int, digit: MeshResource) throws -> CGImage {
        guard ReplaySkinnedNumberSurface.DecalBounds(digit: digit) != nil else {
            throw ReplaySkinnedAthleteError.invalidMaterials
        }
        let label = String(min(max(number, 0), 99))
        let previewFont = UIFont.monospacedDigitSystemFont(ofSize: 220, weight: .heavy)
        let measured = (label as NSString).size(withAttributes: [.font: previewFont])
        guard measured.width > 0, measured.height > 0 else {
            throw ReplaySkinnedAthleteError.invalidMaterials
        }
        let font = UIFont.monospacedDigitSystemFont(ofSize: 220 * min(216 / measured.width,
            216 / measured.height), weight: .heavy)
        let size = (label as NSString).size(withAttributes: [.font: font])
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format)
        let image = renderer.image { _ in
            (label as NSString).draw(at: CGPoint(x: (256 - size.width) * 0.5,
                                              y: (256 - size.height) * 0.5),
                                     withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
        func rgbaContext() -> CGContext? {
            CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8,
                bytesPerRow: 256 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let raw = image.cgImage, let source = rgbaContext() else {
            throw ReplaySkinnedAthleteError.invalidMaterials
        }
        source.draw(raw, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        guard let bytes = source.data?.assumingMemoryBound(to: UInt8.self) else {
            throw ReplaySkinnedAthleteError.invalidMaterials
        }
        var minX = 256, minY = 256, maxX = -1, maxY = -1
        for y in 0..<256 {
            for x in 0..<256 where bytes[y * source.bytesPerRow + x * 4 + 3] > 8 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY,
              let canonical = source.makeImage(),
              let cropped = canonical.cropping(to: CGRect(x: minX, y: minY,
                  width: maxX - minX + 1, height: maxY - minY + 1)) else {
            throw ReplaySkinnedAthleteError.invalidMaterials
        }
        // UIFont line metrics include much unused space. Fill the actual ink
        // to a 216 px box, leaving 20 px transparent border for shirt seams.
        let fit = min(216 / CGFloat(cropped.width), 216 / CGFloat(cropped.height))
        let inkSize = CGSize(width: CGFloat(cropped.width) * fit,
                             height: CGFloat(cropped.height) * fit)
        guard let normalized = rgbaContext() else {
            throw ReplaySkinnedAthleteError.invalidMaterials
        }
        normalized.draw(cropped, in: CGRect(
            x: (256 - inkSize.width) * 0.5, y: (256 - inkSize.height) * 0.5,
            width: inkSize.width, height: inkSize.height))
        guard let cgImage = normalized.makeImage() else {
            throw ReplaySkinnedAthleteError.invalidMaterials
        }
        return cgImage
    }

    // The scene cache still owns instances; render selection is local and does
    // not alter tracks, replay clocks, annotations or saved-review schemas.
    static var preferredIsReady: Bool { isPrewarmed || ReplaySkinnedAthleteProvider.isPrewarmed }
    static var preferredLowIsReady: Bool { isPrewarmed || ReplaySkinnedAthleteProvider.isLowDetailPrewarmed }
    static func makePreferred(for player: PlayerTrack, detail: ReplaySkinnedAthleteProvider.Detail) throws
        -> ReplaySkinnedAthleteInstance {
        if prefersDiverseGeometry(for: player), diversityIsPrewarmed,
           let skin = try? makeDiverse(for: player, detail: detail) { return skin }
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
    static func resetForTesting() {
        near = nil; low = nil; motion = nil; kits = []; appearanceKits = [:]; diversity = nil
        numberMeshes = [:]; numberMasks = [:]
        nativeAssetLoadAttemptsForTesting = 0; texturePreparationAttemptsForTesting = 0
        diversityPreparationErrorForTesting = nil
    }
    #endif
}
