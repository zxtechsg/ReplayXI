import RealityKit
import XCTest
@testable import ReplayXI

final class ReplayReviewPlacement178Tests: XCTestCase {
    func testReviewRemainsLevelAndInFrontOfTranslatedTurnedViewer() {
        let head = Transform(rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
            * simd_quatf(angle: 0.4, axis: [1, 0, 0]), translation: [5, 1.6, -3])
        let base = Transform(scale: .init(repeating: 0.0255), translation: [0, 0.92, -3.15])
        let placed = ReplayReviewPlacement.apply(to: base, viewMode: .tacticalTable, viewer: head.matrix)
        XCTAssertEqual(placed.translation.x, 1.85, accuracy: 0.001)
        XCTAssertEqual(placed.translation.y, 0.95, accuracy: 0.001)
        XCTAssertEqual(placed.translation.z, -3, accuracy: 0.001)
        XCTAssertEqual(placed.scale, base.scale)
        XCTAssertLessThan(simd_distance(placed.rotation.act([0, 1, 0]), [0, 1, 0]), 0.001)
    }

    func testSeatedTableStaysBelowEyesAndTouchlineStaysAboveFloor() {
        let viewer = Transform(translation: [2, 0.85, 4]).matrix
        let base = Transform(translation: [0, 0.92, -3.15])
        let table = ReplayReviewPlacement.apply(to: base, viewMode: .tacticalTable, viewer: viewer)
        XCTAssertEqual(table.translation.x, 2, accuracy: 0.001)
        XCTAssertEqual(table.translation.y, 0.2, accuracy: 0.001)
        XCTAssertEqual(table.translation.z, 0.85, accuracy: 0.001)
        let touchline = ReplayReviewPlacement.apply(to: base, viewMode: .touchline, viewer: viewer)
        XCTAssertEqual(touchline.translation.y, 0.02)
    }

    func testInvalidOriginAndOtherViewsKeepTheirExistingTransform() {
        let base = Transform(scale: .init(repeating: 0.0255), translation: [0, 0.92, -3.15])
        for view in [ReplayViewMode.firstPerson, .positional] {
            XCTAssertEqual(ReplayReviewPlacement.apply(to: base, viewMode: view,
                viewer: Transform(translation: [2, 1.6, 4]).matrix), base)
        }
        var invalid = matrix_identity_float4x4
        invalid.columns.3.x = .nan
        XCTAssertEqual(ReplayReviewPlacement.apply(to: base, viewMode: .tacticalTable, viewer: invalid), base)
        XCTAssertNil(ReplayReviewPlacement.horizontalViewer(invalid))
        XCTAssertNil(ReplayReviewPlacement.horizontalViewer(simd_float4x4()))
    }

    func testLookingStraightUpOrDownRetainsHeadingForPlacement() throws {
        let base = Transform(scale: .init(repeating: 0.0255), translation: [0, 0.92, -3.15])
        for pitch: Float in [-.pi / 2, .pi / 2] {
            let head = Transform(rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                * simd_quatf(angle: pitch, axis: [1, 0, 0]), translation: [5, 1.6, -3])
            let captured = try XCTUnwrap(ReplayReviewPlacement.horizontalViewer(head.matrix))
            let placed = ReplayReviewPlacement.apply(to: base, viewMode: .tacticalTable, viewer: captured)
            XCTAssertEqual(placed.translation.x, 1.85, accuracy: 0.001)
            XCTAssertEqual(placed.translation.z, -3, accuracy: 0.001)
            XCTAssertEqual(placed.translation.y, 0.95, accuracy: 0.001)
            XCTAssertLessThan(simd_distance(placed.rotation.act([0, 1, 0]), [0, 1, 0]), 0.001)
        }
    }
}
