import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackReviewIndexVersionIntegrationTests: XCTestCase {
    func testStoreVersionTracksRailMetadataButIgnoresLiveGeometry() throws {
        let store = ReplayStore()
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 1, z: 2)))
        let mark = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 8, z: 14))
        )
        let insertedVersion = store.reviewIndexVersion

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: PitchPoint(x: 2, z: 3),
                end: PitchPoint(x: 9, z: 15),
                broadcast: false
            )
        )
        XCTAssertEqual(store.reviewIndexVersion, insertedVersion)
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertEqual(store.reviewIndexVersion, insertedVersion)

        XCTAssertTrue(store.updateCoachMarkLabel(id: mark.id, label: "Attack channel"))
        let labelVersion = store.reviewIndexVersion
        XCTAssertNotEqual(labelVersion, insertedVersion)

        XCTAssertTrue(store.retimeCoachMark(id: mark.id, to: 9))
        XCTAssertNotEqual(store.reviewIndexVersion, labelVersion)
    }
}
