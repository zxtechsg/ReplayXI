import CryptoKit
import Foundation
import RealityKit
import UIKit

/// Deterministic low-cost stand-in for a reconstructed match environment.
///
/// This is deliberately named and surfaced as a preview: generated pixels do
/// not become tactical geometry. A hash-locked LingBot-Map/point-cloud import
/// can replace these four shared meshes after it passes the world-manifest
/// gate, while player and ball telemetry remain authoritative.
enum ReplayWorldPreviewFactory {
    static let rootName = "synthetic-world-reconstruction-preview"
    static let admittedRootName = "manifest-admitted-world-reconstruction"
    static let admissionReceiptResourceName = "ReplayXIWorldAdmission"
    static let splatCount = 640
    static let materialGroupCount = 4
    static let estimatedTriangleCount = splatCount * 4
    static let estimatedVertexCount = splatCount * 12

    static func make() -> Entity {
        make(in: .main)
    }

    /// Internal bundle seam keeps production on `Bundle.main` while allowing
    /// the admission/fallback contract to be exercised with an isolated test
    /// bundle rather than mutating application resources.
    static func make(in bundle: Bundle) -> Entity {
        if let admittedWorld = makeAdmittedWorldIfAvailable(in: bundle) {
            return admittedWorld
        }
        return makeSyntheticPreview()
    }

    /// Loads a world only when the bundle contains both a validator-issued
    /// receipt and the exact RealityKit asset named and hashed by that receipt.
    /// A missing, malformed or stale handoff cannot silently replace the
    /// clearly-labelled deterministic preview.
    private static func makeAdmittedWorldIfAvailable(
        in bundle: Bundle = .main
    ) -> Entity? {
        guard let receiptURL = bundle.url(
            forResource: admissionReceiptResourceName,
            withExtension: "json",
            subdirectory: "Worlds"
        ) ?? bundle.url(
            forResource: admissionReceiptResourceName,
            withExtension: "json"
        ),
        isRegularNonSymlinkFile(receiptURL),
        let receiptData = try? Data(contentsOf: receiptURL, options: .mappedIfSafe),
        let receipt = try? JSONDecoder().decode(WorldAdmissionReceipt.self, from: receiptData),
        receipt.isAdmissible,
        let assetURL = admittedAssetURL(
            resourceName: receipt.runtimeAsset.resourceName,
            receiptURL: receiptURL,
            bundle: bundle
        ),
        isRegularNonSymlinkFile(assetURL),
        fileIntegrityMatches(
            assetURL,
            expectedByteCount: receipt.runtimeAsset.byteCount,
            expectedSHA256: receipt.runtimeAsset.sha256
        ),
        let visualContext = try? Entity.load(contentsOf: assetURL)
        else {
            return nil
        }

        stripInteractivePhysics(from: visualContext)
        visualContext.name = "manifest-admitted-visual-context"
        let root = Entity()
        root.name = admittedRootName
        root.addChild(visualContext)
        return root
    }

    private static func makeSyntheticPreview() -> Entity {
        let root = Entity()
        root.name = rootName

        let colors = [
            UIColor(red: 0.11, green: 0.86, blue: 0.69, alpha: 1),
            UIColor(red: 0.15, green: 0.42, blue: 0.78, alpha: 1),
            UIColor(red: 0.91, green: 0.28, blue: 0.22, alpha: 1),
            UIColor(red: 0.80, green: 0.88, blue: 0.84, alpha: 1),
        ]
        let meshes = makeSurfelMeshes()
        for index in meshes.indices {
            let model = ModelEntity(
                mesh: meshes[index],
                materials: [
                    UnlitMaterial(
                        color: colors[index % colors.count],
                        applyPostProcessToneMap: false
                    )
                ]
            )
            model.name = "world-preview-surfels-\(index)"
            root.addChild(model)
        }
        return root
    }

    private static func admittedAssetURL(
        resourceName: String,
        receiptURL: URL,
        bundle: Bundle
    ) -> URL? {
        guard !resourceName.contains("/"),
              !resourceName.contains("\\"),
              URL(fileURLWithPath: resourceName).lastPathComponent == resourceName
        else {
            return nil
        }

        let sibling = receiptURL.deletingLastPathComponent().appendingPathComponent(resourceName)
        if isRegularNonSymlinkFile(sibling) {
            return sibling
        }

        let extensionName = (resourceName as NSString).pathExtension
        let baseName = (resourceName as NSString).deletingPathExtension
        return bundle.url(
            forResource: baseName,
            withExtension: extensionName,
            subdirectory: "Worlds"
        ) ?? bundle.url(forResource: baseName, withExtension: extensionName)
    }

    private static func isRegularNonSymlinkFile(_ url: URL) -> Bool {
        guard url.isFileURL,
              let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              )
        else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func fileIntegrityMatches(
        _ url: URL,
        expectedByteCount: Int,
        expectedSHA256: String
    ) -> Bool {
        guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
              resourceValues.fileSize == expectedByteCount,
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            return false
        }
        defer { try? handle.close() }

        var digest = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                digest.update(data: chunk)
            }
        } catch {
            return false
        }
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        return actual == expectedSHA256
    }

    private static func stripInteractivePhysics(from entity: Entity) {
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(PhysicsBodyComponent.self)
        entity.components.remove(PhysicsMotionComponent.self)
        for child in entity.children {
            stripInteractivePhysics(from: child)
        }
    }

    private static func makeSurfelMeshes() -> [MeshResource] {
        var builders = Array(
            repeating: SurfelMeshBuilder(),
            count: materialGroupCount
        )
        var random = DeterministicWorldRandom(seed: 0x5245_504C_4159_5849)

        for index in 0..<splatCount {
            let side = index % 4
            let horizontal = random.unit()
            let depth = random.unit()
            let heightBias = pow(random.unit(), 0.72)
            let y = 0.35 + (heightBias * 10.5)
            let centre: SIMD3<Float>
            switch side {
            case 0:
                centre = [38 + (depth * 10), y, -52 + (horizontal * 104)]
            case 1:
                centre = [-38 - (depth * 10), y, -52 + (horizontal * 104)]
            case 2:
                centre = [-34 + (horizontal * 68), y, 57 + (depth * 9)]
            default:
                centre = [-34 + (horizontal * 68), y, -57 - (depth * 9)]
            }
            let size = 0.045 + (random.unit() * 0.085) + (y * 0.0018)
            let group = Int(random.next() % UInt64(materialGroupCount))
            builders[group].appendTetrahedron(centre: centre, radius: size)
        }

        return builders.enumerated().compactMap { index, builder in
            builder.makeMesh(named: "replay-world-preview-\(index)")
        }
    }
}

private struct WorldAdmissionReceipt: Decodable {
    struct Source: Decodable {
        let kind: String
        let owner: String
        let rightsBasis: String
        let containsRealPlayerLikenesses: Bool
    }

    struct Coordinates: Decodable {
        let upAxis: String
        let metresPerUnit: Float
        let pitchLengthMetres: Float
        let pitchWidthMetres: Float
        let origin: String
        let positiveZ: String
        let positiveX: String
    }

    struct TacticalTruth: Decodable {
        let generatedPixelsAreAuthoritative: Bool
        let trackingAuthority: String
    }

    struct RuntimeAsset: Decodable {
        let resourceName: String
        let sha256: String
        let byteCount: Int
    }

    let schemaVersion: Int
    let admissionVersion: Int
    let manifestSHA256: String
    let worldID: String
    let displayName: String
    let source: Source
    let coordinates: Coordinates
    let tacticalTruth: TacticalTruth
    let runtimeAsset: RuntimeAsset
    let rightsEvidenceSHA256: String?

    var isAdmissible: Bool {
        let allowedSourceKinds = [
            "original-synthetic",
            "club-owned-capture",
            "licensed-capture",
            "open-data-reconstruction",
        ]
        let lowerHash = runtimeAsset.sha256.lowercased()
        let assetExtension = (runtimeAsset.resourceName as NSString).pathExtension.lowercased()
        let sourceIsSynthetic = source.kind == "original-synthetic"

        return schemaVersion == 1
            && admissionVersion == 1
            && isSHA256(manifestSHA256)
            && worldID == "right-wing-overlap"
            && displayName == "Real World Match Replay"
            && allowedSourceKinds.contains(source.kind)
            && !source.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !source.rightsBasis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // The current dashboard visibly says SYNTH. Captured/licensed
            // receipts remain staged at the validator until the UI presents
            // their receipt-derived provenance instead of that fixed label.
            && sourceIsSynthetic
            && !source.containsRealPlayerLikenesses
            && coordinates.upAxis == "Y"
            && coordinates.metresPerUnit == 1
            && coordinates.pitchLengthMetres == 105
            && coordinates.pitchWidthMetres == 68
            && coordinates.origin == "pitch-centre"
            && coordinates.positiveZ == "home-attacking-direction"
            && coordinates.positiveX == "home-right"
            && !tacticalTruth.generatedPixelsAreAuthoritative
            && !tacticalTruth.trackingAuthority.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ["reality", "usdz"].contains(assetExtension)
            && runtimeAsset.resourceName == URL(fileURLWithPath: runtimeAsset.resourceName).lastPathComponent
            && runtimeAsset.byteCount > 0
            && lowerHash == runtimeAsset.sha256
            && isSHA256(runtimeAsset.sha256)
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

private struct DeterministicWorldRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}

private struct SurfelMeshBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var indices: [UInt32] = []

    mutating func appendTetrahedron(centre: SIMD3<Float>, radius: Float) {
        let vertices = [
            centre + SIMD3<Float>(0, radius, 0),
            centre + SIMD3<Float>(-radius, -radius * 0.55, radius * 0.80),
            centre + SIMD3<Float>(radius, -radius * 0.55, radius * 0.80),
            centre + SIMD3<Float>(0, -radius * 0.55, -radius),
        ]
        for (a, b, c) in [(0, 2, 1), (0, 3, 2), (0, 1, 3), (1, 2, 3)] {
            let normal = simd_normalize(
                simd_cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
            )
            let base = UInt32(positions.count)
            positions.append(contentsOf: [vertices[a], vertices[b], vertices[c]])
            normals.append(contentsOf: [normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
    }

    func makeMesh(named name: String) -> MeshResource? {
        guard !positions.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
