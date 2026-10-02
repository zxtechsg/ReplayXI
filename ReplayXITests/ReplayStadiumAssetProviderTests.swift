import RealityKit
import XCTest
import UIKit
import simd
@testable import ReplayXI

@MainActor
final class ReplayStadiumAssetProviderTests: XCTestCase {
    override func tearDown() {
        ReplayStadiumAssetProvider.resetForTesting()
        super.tearDown()
    }

    func testMissingAssetFailureIsCachedAndNeverProducesPartialScenery() {
        ReplayStadiumAssetProvider.resetForTesting()
        XCTAssertThrowsError(try ReplayStadiumAssetProvider.prewarmForTesting(url: nil)) {
            XCTAssertEqual($0 as? ReplayStadiumAssetProvider.AssetError, .missing)
        }
        XCTAssertFalse(ReplayStadiumAssetProvider.isPrewarmed)
        XCTAssertNil(ReplayStadiumAssetProvider.makeInstance())
        // A later request cannot trigger an import retry within this process.
        XCTAssertThrowsError(try ReplayStadiumAssetProvider.prewarm()) {
            XCTAssertEqual($0 as? ReplayStadiumAssetProvider.AssetError, .missing)
        }
        XCTAssertNil(ReplayStadiumAssetProvider.makeInstance())
    }

    func testRemoteAssetURLCannotReachTheLoader() throws {
        ReplayStadiumAssetProvider.resetForTesting()
        let url = try XCTUnwrap(URL(string: "https://example.invalid/ReplayXIStadium.usdz"))
        XCTAssertThrowsError(try ReplayStadiumAssetProvider.prewarmForTesting(url: url)) {
            XCTAssertEqual($0 as? ReplayStadiumAssetProvider.AssetError, .missing)
        }
        XCTAssertNil(ReplayStadiumAssetProvider.makeInstance())
    }

    func testChangedEmptyAndOversizedBytesAreRejectedBeforeImport() {
        for data in [Data(), Data("changed stadium".utf8),
                     Data(repeating: 0, count: ReplayStadiumAssetProvider.maximumFileBytes)] {
            XCTAssertThrowsError(try ReplayStadiumAssetProvider.validateAssetData(data)) {
                XCTAssertEqual($0 as? ReplayStadiumAssetProvider.AssetError, .changed)
            }
        }
    }

    func testUntexturedPreparedMaterialKeepsItsSolidColourWithoutRoomLighting() throws {
        var original = PhysicallyBasedMaterial()
        original.baseColor = .init(tint: UIColor(red: 0.18, green: 0.31, blue: 0.28, alpha: 1))
        let stable = try ReplayStadiumAssetProvider.stableMaterial(from: original)
        XCTAssertEqual(stable.color.tint, original.baseColor.tint)
        XCTAssertNil(stable.color.texture)
    }

    func testPitchClearanceRejectsBridgesAndOverheadRoofs() {
        let crossing: [SIMD3<Float>] = [[-60, 12, 0], [60, 12, 0], [0, 12, 80]]
        // Every vertex is outside, yet the triangle spans the playing field.
        for shift in 0..<3 {
            let a = crossing[shift], b = crossing[(shift + 1) % 3], c = crossing[(shift + 2) % 3]
            XCTAssertFalse(ReplayStadiumAssetProvider.triangleKeepsFieldClear(a, b, c))
            XCTAssertFalse(ReplayStadiumAssetProvider.triangleKeepsFieldClear(a, c, b))
        }
        XCTAssertFalse(ReplayStadiumAssetProvider.triangleKeepsFieldClear(
            [-36.5, 24, -56.5], [36.5, 24, -56.5], [0, 24, 60]))
        XCTAssertFalse(ReplayStadiumAssetProvider.triangleKeepsFieldClear(
            [0, 0, 0], [0, 1, 0], [0, 2, 0]))
        XCTAssertFalse(ReplayStadiumAssetProvider.triangleKeepsFieldClear(
            [.nan, 0, 90], [50, 0, 90], [50, 10, 90]))
    }

    func testPitchClearanceAcceptsExteriorWallsAndDiagonalCorners() {
        XCTAssertTrue(ReplayStadiumAssetProvider.triangleKeepsFieldClear(
            [36, 0, -60], [36, 20, 60], [40, 0, 0]))
        XCTAssertTrue(ReplayStadiumAssetProvider.triangleKeepsFieldClear(
            [-45, 0, -60], [-36, 10, 0], [-40, 0, 60]))
        // No shared X/Z half-plane separates these vertices, but their
        // diagonal edge stays beyond the (36, 56) corner of the clear field.
        XCTAssertTrue(ReplayStadiumAssetProvider.triangleKeepsFieldClear(
            [35, 0, 59], [39, 10, 55], [45, 0, 65]))
        XCTAssertFalse(ReplayStadiumAssetProvider.triangleKeepsFieldClear(
            [35, 0, 57], [37, 10, 55], [34, 0, 54]))
    }

    func testAuditedNativeAssetPreservesTexturesAndSharedResourcesWithoutInput() throws {
        guard ReplayStadiumAssetProvider.assetSHA256.count == 64,
              let expected = ReplayStadiumAssetProvider.expectedBounds else {
            throw XCTSkip("The final user stadium hash and bounds have not been audited yet")
        }
        ReplayStadiumAssetProvider.resetForTesting()
        try ReplayStadiumAssetProvider.prewarm()
        XCTAssertTrue(ReplayStadiumAssetProvider.isPrewarmed)
        let first = try XCTUnwrap(ReplayStadiumAssetProvider.makeInstance())
        let second = try XCTUnwrap(ReplayStadiumAssetProvider.makeInstance())
        let admission = try XCTUnwrap(first.components[ReplayStadiumAssetProvider.Admission.self])
        XCTAssertEqual(admission.source, "User-supplied stadium, prepared in Blender")
        XCTAssertEqual(admission.assetSHA256, ReplayStadiumAssetProvider.assetSHA256)
        XCTAssertEqual(admission.triangles, 24_768, "Candidate 04 keeps the audited supplied geometry")
        XCTAssertLessThanOrEqual(admission.triangles, ReplayStadiumAssetProvider.triangleBudget)
        XCTAssertEqual(admission.materialDraws, 1, "Candidate 04 uses one baked atlas draw")
        XCTAssertLessThanOrEqual(admission.materialDraws, ReplayStadiumAssetProvider.materialDrawBudget)
        let bounds = first.visualBounds(relativeTo: first)
        for axis in 0..<3 {
            XCTAssertEqual(bounds.min[axis], expected.minimum[axis], accuracy: expected.tolerance)
            XCTAssertEqual(bounds.max[axis], expected.maximum[axis], accuracy: expected.tolerance)
        }
        for (a, b) in zip(ReplayStadiumAssetProvider.models(in: first),
                          ReplayStadiumAssetProvider.models(in: second)) {
            let one = try XCTUnwrap(a.model), two = try XCTUnwrap(b.model)
            XCTAssertTrue(one.mesh === two.mesh)
            for (left, right) in zip(one.materials, two.materials) {
                let material = try XCTUnwrap(left as? UnlitMaterial)
                let other = try XCTUnwrap(right as? UnlitMaterial)
                let texture = try XCTUnwrap(material.color.texture?.resource,
                                           "Every Candidate 04 material must retain the baked atlas")
                let otherTexture = try XCTUnwrap(other.color.texture?.resource)
                XCTAssertEqual(texture, otherTexture)
                XCTAssertEqual(material.faceCulling, .none)
                XCTAssertEqual(other.faceCulling, .none)
                XCTAssertEqual(material.color.tint, other.color.tint)
            }
        }
        for root in [first, second] {
            for entity in [root] + ReplayStadiumAssetProvider.models(in: root).map({ $0 as Entity }) {
                XCTAssertFalse(entity.components.has(InputTargetComponent.self))
                XCTAssertFalse(entity.components.has(CollisionComponent.self))
                XCTAssertFalse(entity.components.has(PhysicsBodyComponent.self))
                XCTAssertFalse(entity.components.has(PhysicsMotionComponent.self))
                XCTAssertTrue(entity.availableAnimations.isEmpty)
            }
        }
        first.isEnabled = false
        first.position = [1, 2, 3]
        XCTAssertTrue(second.isEnabled)
        XCTAssertEqual(second.position, .zero)
        // A repeated warm-up does not replace resources already in use.
        try ReplayStadiumAssetProvider.prewarm()
        let third = try XCTUnwrap(ReplayStadiumAssetProvider.makeInstance())
        XCTAssertTrue(try XCTUnwrap(ReplayStadiumAssetProvider.models(in: second).first?.model?.mesh)
            === XCTUnwrap(ReplayStadiumAssetProvider.models(in: third).first?.model?.mesh))
    }
}
