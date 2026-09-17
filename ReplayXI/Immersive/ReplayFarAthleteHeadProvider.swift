import CryptoKit
import Foundation
import RealityKit
import simd

/// Static MIT face for the seven-model far rig. Only the mesh is cached here;
/// colour/normal textures remain owned by the existing five-palette provider.
/// The package has a neutral placeholder material and no embedded images.
/// Explicit prewarm is required. Neither make nor animation loads resources.
@MainActor
enum ReplayFarAthleteHeadProvider {
    static let resourceName = "ReplayXIFarAthleteHead"
    static let expectedSHA256 = "30b5213f5967da5fa2574f39dfe942b989fe94629994cd10ad7a739c45e32b3f"
    static let expectedBytes = 21_563
    static let metrics = ReplayAthleteMeshMetrics(vertices: 486, triangles: 749)

    enum PreparationError: Error, Equatable {
        case materialsNotReady, resourceMissing, hashMismatch, invalidAsset, previousFailure, forcedFailure
    }

    private static var mesh: MeshResource?
    private static var attemptedPreparation = false
    static var isPrewarmed: Bool { mesh != nil && ReplayAthleteHeadProvider.isPrewarmed }

    static func prewarm(in bundle: Bundle = .main) throws {
        // An out-of-order caller must not poison the one asset attempt. The
        // dashboard prepares the shared palettes first; make stays fail-soft.
        guard ReplayAthleteHeadProvider.isPrewarmed else { throw PreparationError.materialsNotReady }
        if mesh != nil { return }
        guard !attemptedPreparation else { throw PreparationError.previousFailure }
        attemptedPreparation = true
        #if DEBUG
        preparationAttemptCount += 1
        if forcesFailureForTesting { throw PreparationError.forcedFailure }
        #endif
        guard let url = bundle.url(forResource: resourceName, withExtension: "usdz", subdirectory: "Resources/Players")
            ?? bundle.url(forResource: resourceName, withExtension: "usdz") else {
            throw PreparationError.resourceMissing
        }
        let file = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard file.isRegularFile == true, file.fileSize == expectedBytes else { throw PreparationError.invalidAsset }
        try validateAssetData(Data(contentsOf: url, options: .mappedIfSafe))
        #if DEBUG
        meshLoadCount += 1
        #endif
        let loaded = try Entity.load(contentsOf: url)
        let models = allModels(in: loaded)
        guard models.count == 1, let source = models.first, let component = source.model,
              let placeholder = component.materials.first as? PhysicallyBasedMaterial,
              isIdentity(loaded.transform.matrix), isIdentity(source.transformMatrix(relativeTo: loaded)),
              component.materials.count == 1,
              placeholder.baseColor.texture == nil, placeholder.normal.texture == nil,
              source.jointNames.isEmpty, source.jointTransforms.isEmpty, source.availableAnimations.isEmpty
        else { throw PreparationError.invalidAsset }
        let contents = component.mesh.contents
        let parts = contents.models.flatMap { Array($0.parts) }
        guard contents.models.count == 1, let model = contents.models.first,
              contents.instances.count == 1, let instance = contents.instances.first,
              instance.model == model.id, isIdentity(instance.transform), contents.skeletons.isEmpty,
              parts.count == 1, let part = parts.first,
              part.materialIndex == 0, part.skeletonID == nil, part.jointInfluences == nil,
              part.positions.count == metrics.vertices,
              part.normals?.count == metrics.vertices, part.textureCoordinates?.count == metrics.vertices,
              part.triangleIndices?.count == metrics.triangles * 3,
              part.positions.elements.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
              part.normals?.elements.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) == true,
              part.textureCoordinates?.elements.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) == true,
              part.triangleIndices?.elements.allSatisfy({ $0 < UInt32(metrics.vertices) }) == true
        else { throw PreparationError.invalidAsset }
        let bounds = source.visualBounds(relativeTo: source)
        guard simd_distance(bounds.min, [-0.09021137, -0.15823624, -0.10883906]) < 0.000_002,
              simd_distance(bounds.max, [0.09007151, 0.15959060, 0.12460621]) < 0.000_002
        else { throw PreparationError.invalidAsset }
        // Publish only after every admission check. No partially valid head
        // escapes a failed load, and the ellipsoid remains the fallback.
        mesh = component.mesh
    }

    static func make(appearance: ReplayAthleteAppearance) -> ModelEntity? {
        guard let mesh, ReplayAthleteHeadProvider.isPrewarmed else { return nil }
        let index = (0..<5).first { ReplayAthleteAppearance.replayXI(index: $0).skin == appearance.skin } ?? 0
        guard let material = ReplayAthleteHeadProvider.material(at: index) else { return nil }
        let head = ModelEntity(mesh: mesh, materials: [material])
        head.name = "head"
        head.scale = [1.07, 1, 1]
        return head
    }

    static func validateAssetData(_ data: Data) throws {
        guard data.count == expectedBytes else { throw PreparationError.invalidAsset }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else { throw PreparationError.hashMismatch }
    }

    private static func allModels(in root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? []) + root.children.flatMap { allModels(in: $0) }
    }

    private static func isIdentity(_ matrix: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { simd_distance(matrix[$0], matrix_identity_float4x4[$0]) < 0.000_001 }
    }

    #if DEBUG
    private(set) static var preparationAttemptCount = 0
    private(set) static var meshLoadCount = 0
    private static var forcesFailureForTesting = false

    static func resetForTesting(forceFailure: Bool = false) {
        mesh = nil
        attemptedPreparation = false
        preparationAttemptCount = 0
        meshLoadCount = 0
        forcesFailureForTesting = forceFailure
    }
    #endif
}
