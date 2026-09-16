import CryptoKit
import Foundation
import RealityKit

/// Optional admitted visual context for a match. The synthetic demo already
/// has a pitch and authored player tracks; it must not add fake reconstruction
/// points that obscure the play or imply recovered footage.
enum ReplayWorldPreviewFactory {
    static let rootName = "synthetic-world-reconstruction-preview"
    static let admittedRootName = "manifest-admitted-world-reconstruction"
    static let admissionReceiptResourceName = "ReplayXIWorldAdmission"

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
        // Keep provenance/scenario identity without spending four draws on
        // decorative surfels. The original pitch is provided by the scene.
        let root = Entity()
        root.name = rootName
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
