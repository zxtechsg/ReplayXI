import CryptoKit
import Foundation
import RealityKit
import simd
import UIKit

/// Optional, audited local user-supplied scenery. A failed admission stays failed for
/// this process; callers keep the procedural environment as their fallback.
@MainActor
enum ReplayStadiumAssetProvider {
    static let resourceName = "ReplayXIStadium"
    static let visualRootName = "replay-user-stadium"
    static let sourceDescription = "User-supplied stadium, prepared in Blender"
    static let assetSHA256 = "78adb0f5fd3b240e65b3618cfcab045429827c1a94572648a5360b4aa1017c9e"
    static let maximumFileBytes = 12_000_000
    static let triangleBudget = 25_000
    static let materialDrawBudget = 4
    static let clearHalfWidth: Float = 36
    static let clearHalfLength: Float = 56
    static let clearanceTolerance: Float = 0.002

    struct AuditedBounds {
        let minimum: SIMD3<Float>
        let maximum: SIMD3<Float>
        let tolerance: Float
    }

    // Fill only from the final local USDZ audit, including its import transform.
    static let expectedBounds: AuditedBounds? = .init(
        minimum: [-83.282089, -0.860831, -98.123871],
        maximum: [73.917564, 28.079460, 98.511284],
        tolerance: 0.02)

    struct Admission: Component {
        let source: String
        let assetSHA256: String
        let triangles: Int
        let materialDraws: Int
    }

    enum AssetError: Error, Equatable {
        case missing
        case changed
        case unverifiedBounds
        case invalidGeometry(String)
        case loadFailed(String)
    }

    private static var preparation: Result<Entity, AssetError>?
    static var isPrewarmed: Bool {
        if case .success = preparation { return true }
        return false
    }

    static func prewarm(in bundle: Bundle = .main) throws {
        if let preparation { _ = try preparation.get(); return }
        let url = bundle.url(forResource: resourceName, withExtension: "usdz",
                             subdirectory: "Resources/Environment")
            ?? bundle.url(forResource: resourceName, withExtension: "usdz")
        try prepare(url: url)
    }

    private static func prepare(url: URL?) throws {
        if let preparation { _ = try preparation.get(); return }
        do {
            guard let url, url.isFileURL else { throw AssetError.missing }
            let metadata: URLResourceValues
            do {
                metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            } catch { throw AssetError.missing }
            guard metadata.isRegularFile == true, let bytes = metadata.fileSize,
                  bytes > 0, bytes < maximumFileBytes else { throw AssetError.changed }
            try validateAssetData(Data(contentsOf: url, options: .mappedIfSafe))
            guard let expectedBounds else { throw AssetError.unverifiedBounds }
            let loaded = try Entity.load(contentsOf: url)
            let root = try admit(loaded, bounds: expectedBounds)
            preparation = .success(root)
        } catch {
            let failure = error as? AssetError ?? .loadFailed(String(describing: error))
            preparation = .failure(failure)
            throw failure
        }
    }

    static func validateAssetData(_ data: Data) throws {
        guard !data.isEmpty, data.count < maximumFileBytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == assetSHA256
        else { throw AssetError.changed }
    }

    static func makeInstance() -> Entity? {
        guard case let .success(template) = preparation else { return nil }
        return template.clone(recursive: true)
    }

    private static func admit(_ loaded: Entity, bounds expected: AuditedBounds) throws -> Entity {
        let entities = allEntities(in: loaded)
        let sourceModels = entities.compactMap { $0 as? ModelEntity }.filter { $0.model != nil }
        guard !sourceModels.isEmpty, sourceModels.count <= materialDrawBudget,
              entities.allSatisfy({ $0.availableAnimations.isEmpty }) else {
            throw AssetError.invalidGeometry("Expected static scenery with at most four models")
        }
        let root = Entity()
        root.name = visualRootName
        var triangles = 0, draws = 0
        for (index, source) in sourceModels.enumerated() {
            guard let component = source.model, source.jointNames.isEmpty,
                  source.jointTransforms.isEmpty, !component.materials.isEmpty,
                  component.materials.count <= materialDrawBudget else {
                throw AssetError.invalidGeometry("Unexpected skeleton or material count")
            }
            let contents = component.mesh.contents
            guard contents.models.count == 1, let mesh = contents.models.first,
                  contents.instances.count == 1, let instance = contents.instances.first,
                  instance.model == mesh.id, instance.transform == matrix_identity_float4x4,
                  contents.skeletons.isEmpty else {
                throw AssetError.invalidGeometry("Unexpected mesh instancing or skeleton")
            }
            // Preserve every import transform, including USD's up-axis rotation.
            let transform = source.transformMatrix(relativeTo: nil)
            guard (0..<4).allSatisfy({ finite(transform[$0]) }) else {
                throw AssetError.invalidGeometry("Non-finite import transform")
            }
            for part in mesh.parts {
                guard part.skeletonID == nil, part.jointInfluences == nil,
                      part.materialIndex >= 0, part.materialIndex < component.materials.count,
                      let indices = part.triangleIndices, indices.count > 0,
                      indices.count.isMultiple(of: 3), part.positions.count > 0,
                      part.positions.elements.allSatisfy({ finite($0) }),
                      indices.elements.allSatisfy({ $0 < UInt32(part.positions.count) }) else {
                    throw AssetError.invalidGeometry("Invalid static triangles")
                }
                draws += 1
                triangles += indices.count / 3
                guard draws <= materialDrawBudget, triangles <= triangleBudget else {
                    throw AssetError.invalidGeometry("Stadium exceeds draw or triangle budget")
                }
                let positions = part.positions.elements
                let values = indices.elements
                for offset in stride(from: 0, to: values.count, by: 3) {
                    func transformed(_ slot: Int) -> SIMD3<Float> {
                        let point = positions[Int(values[offset + slot])]
                        let value = transform * SIMD4<Float>(point.x, point.y, point.z, 1)
                        return [value.x, value.y, value.z]
                    }
                    guard triangleKeepsFieldClear(transformed(0), transformed(1), transformed(2)) else {
                        throw AssetError.invalidGeometry("Scenery overlaps the clear pitch opening")
                    }
                }
            }
            let materials: [any Material] = try component.materials.map { try stableMaterial(from: $0) }
            // A new static entity carries only the existing mesh/materials.
            // Imported input, physics, audio, light or animation components are
            // never copied into the spatial room. No mesh is rebuilt here.
            let model = ModelEntity(mesh: component.mesh, materials: materials)
            model.name = "user-stadium-\(index)"
            model.transform = Transform(matrix: transform)
            root.addChild(model)
        }
        guard draws > 0 else {
            throw AssetError.invalidGeometry("Missing stadium draw geometry")
        }
        let bounds = root.visualBounds(relativeTo: root)
        guard finite(bounds.min), finite(bounds.max), finite(expected.minimum), finite(expected.maximum),
              expected.tolerance.isFinite, expected.tolerance > 0,
              (0..<3).allSatisfy({ expected.maximum[$0] > expected.minimum[$0]
                  && abs(bounds.min[$0] - expected.minimum[$0]) <= expected.tolerance
                  && abs(bounds.max[$0] - expected.maximum[$0]) <= expected.tolerance }) else {
            throw AssetError.invalidGeometry("Stadium scale or bounds differ from the audited asset")
        }
        root.components.set(Admission(source: sourceDescription, assetSHA256: assetSHA256, triangles: triangles, materialDraws: draws))
        return root
    }

    /// Preserve Blender's authored colour/AO atlas. The supplied OBJ had no
    /// original textures; stable unlit shading keeps room lighting out of it.
    static func stableMaterial(from material: any Material) throws -> UnlitMaterial {
        guard let source = material as? PhysicallyBasedMaterial else {
            throw AssetError.invalidGeometry("Unsupported source base-colour material")
        }
        var stable = UnlitMaterial(color: source.baseColor.tint, applyPostProcessToneMap: false)
        stable.color = .init(tint: source.baseColor.tint, texture: source.baseColor.texture)
        // The supplied architectural OBJ includes single-sheet roof/truss
        // faces. Its audited USDZ is explicitly double-sided.
        stable.faceCulling = .none
        return stable
    }

    /// SAT against the open pitch rectangle. Vertex-only tests miss triangles
    /// bridging the pitch. Projecting X/Z also rejects roofs above the field.
    static func triangleKeepsFieldClear(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Bool {
        guard finite(a), finite(b), finite(c) else { return false }
        let points = [SIMD2<Float>(a.x, a.z), SIMD2<Float>(b.x, b.z), SIMD2<Float>(c.x, c.z)]
        func separated(on rawAxis: SIMD2<Float>) -> Bool {
            let length = simd_length(rawAxis)
            guard length.isFinite, length > 0.000_001 else { return false }
            let axis = rawAxis / length
            let radius = abs(axis.x) * clearHalfWidth + abs(axis.y) * clearHalfLength
            let projections = points.map { simd_dot($0, axis) }
            return projections.min()! >= radius - clearanceTolerance
                || projections.max()! <= -radius + clearanceTolerance
        }
        if separated(on: [1, 0]) || separated(on: [0, 1]) { return true }
        for index in 0..<3 {
            let edge = points[(index + 1) % 3] - points[index]
            if separated(on: [-edge.y, edge.x]) { return true }
        }
        return false
    }

    static func models(in root: Entity) -> [ModelEntity] {
        allEntities(in: root).compactMap { $0 as? ModelEntity }
    }

    private static func allEntities(in root: Entity) -> [Entity] {
        [root] + root.children.flatMap { allEntities(in: $0) }
    }

    private static func finite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private static func finite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }

    #if DEBUG
    static func resetForTesting() { preparation = nil }
    static func prewarmForTesting(url: URL?) throws { try prepare(url: url) }
    #endif
}
