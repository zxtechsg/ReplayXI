import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackViewGestureOwnershipTests: XCTestCase {
    private func attemptEveryCameraRoute(_ store: ReplayStore) {
        store.setViewMode(.touchline)
        store.openLocalPlayerPOV("red-lb")
        store.setLocalPerspective("red-lb")
        store.selectAdjacentPerspective(by: 1)
        store.broadcastPerspective("red-lb")
    }

    func testUnfinishedDrawingKeepsCameraAndStartPointAcrossAllRoutes() {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let mode = store.viewMode
        let perspective = store.activePerspectiveID
        let start = PitchPoint(x: 2, z: 3)
        store.beginDrawing(.pass)
        _ = store.registerPitchTap(start)

        XCTAssertFalse(store.canChangePlaybackView)
        attemptEveryCameraRoute(store)

        XCTAssertEqual(store.viewMode, mode)
        XCTAssertEqual(store.activePerspectiveID, perspective)
        XCTAssertEqual(store.pendingDrawStart, start)
        XCTAssertTrue(store.isDrawing)
        XCTAssertEqual(store.statusMessage, "Finish or cancel the annotation first")

        store.cancelDrawing()
        XCTAssertTrue(store.canChangePlaybackView)
        store.openLocalPlayerPOV("red-lb")
        XCTAssertEqual(store.activePerspectiveID, "red-lb")
        XCTAssertEqual(store.viewMode, .firstPerson)
    }

    func testScrubKeepsCameraAndPreviewUntilCommit() {
        let store = ReplayStore()
        let mode = store.viewMode
        let perspective = store.activePerspectiveID
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 12))
        XCTAssertFalse(store.canChangePlaybackView)

        attemptEveryCameraRoute(store)

        XCTAssertEqual(store.viewMode, mode)
        XCTAssertEqual(store.activePerspectiveID, perspective)
        XCTAssertEqual(store.playhead, 12)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertTrue(store.commitTimelineScrub(to: 12))
        XCTAssertTrue(store.canChangePlaybackView)
    }
}
