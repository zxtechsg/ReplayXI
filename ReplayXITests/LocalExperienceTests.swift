import XCTest
@testable import ReplayXI

@MainActor
final class LocalExperienceTests: XCTestCase {
    private func addMark(to store: ReplayStore) throws -> CoachMark {
        store.beginDrawing(.pass)
        _ = store.registerPitchTap(PitchPoint(x: 2, z: 3))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 10)))
        store.cancelDrawing()
        return mark
    }

    func testLocalLaunchKeepsReviewAndRemovesRemoteAuthority() throws {
        let store = ReplayStore()
        store.seek(to: 12.5)
        store.setPlaybackRate(2)
        store.openLocalPlayerPOV("red-lb")
        let mark = try addMark(to: store)
        store.localRole = .player
        store.setCollaborationActive(true)
        store.participantSeatAssignments[UUID()] = "navy-rw"
        store.onBroadcastSnapshot = { _ in XCTFail("Local review must not send snapshots") }

        store.prepareForLocalExperience()

        XCTAssertFalse(store.isCollaborationActive)
        XCTAssertNil(store.onBroadcastSnapshot)
        XCTAssertEqual(store.localRole, .coach)
        XCTAssertFalse(store.coachLockEnabled)
        XCTAssertFalse(store.isLocallyPaused)
        XCTAssertTrue(store.participantSeatAssignments.isEmpty)
        XCTAssertEqual(store.localPerspectiveID, "red-lb")
        XCTAssertEqual(store.playhead, 12.5)
        XCTAssertEqual(store.playbackRate, 2)
        XCTAssertTrue(store.marks.contains(mark))
    }

    func testEveryPlayerPOVRemainsEditableWithoutSession() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        XCTAssertEqual(store.selectedScenario.players.count, 22)
        for player in store.selectedScenario.players {
            store.openLocalPlayerPOV(player.id)
            XCTAssertEqual(store.activePerspectiveID, player.id)
            XCTAssertEqual(store.viewMode, .firstPerson)
            XCTAssertFalse(store.isLocallyPaused)
        }
        let mark = try addMark(to: store)
        XCTAssertTrue(store.updateCoachMarkLabel(id: mark.id, label: "Overlap"))
        XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: "navy-rb"))
        XCTAssertTrue(store.removeCoachMark(id: mark.id))
    }

    func testLocalTimelineScrubCommitsAndPlaybackAdvances() {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 14))
        XCTAssertTrue(store.commitTimelineScrub(to: 14))
        store.setPlaybackRate(2)
        store.setPlaying(true)
        store.advance(by: 1)
        XCTAssertEqual(store.playhead, 16)
        XCTAssertFalse(store.isCollaborationActive)
    }

    func testLocalSaveRestoresPOVTimeAndAnnotations() throws {
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all)
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)
        store.prepareForLocalExperience()
        store.seek(to: 13.6)
        store.openLocalPlayerPOV("red-lb")
        let mark = try addMark(to: store)
        XCTAssertTrue(store.saveReview(named: "Local overlap"))
        let id = try XCTUnwrap(store.savedReviews.first?.id)

        let restored = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)
        XCTAssertTrue(restored.restoreSavedReview(id: id))
        restored.prepareForLocalExperience()
        XCTAssertEqual(restored.playhead, 13.6)
        XCTAssertEqual(restored.activePerspectiveID, "red-lb")
        XCTAssertTrue(restored.marks.contains(mark))
        XCTAssertTrue(restored.canRestoreSavedReview)
        XCTAssertNil(restored.onBroadcastSnapshot)
    }

    func testLocalPositioningDoesNotNeedParticipantsOrBroadcastAnchor() {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let scenario = DemoScenarios.all.first { $0.kind == .shapeLab }!
        store.selectScenario(id: scenario.id)
        let anchorID = UUID()
        store.activateLocalTrianglePreview(anchorID: anchorID)
        XCTAssertEqual(store.triangleLockMode, .place)
        XCTAssertTrue(store.isLocalTrianglePreview)
        XCTAssertTrue(store.hasLocallyAcknowledgedTrianglePlacement)
        XCTAssertTrue(store.participantSeatAssignments.isEmpty)
        XCTAssertNil(store.makeSnapshot().sharedPitchAnchorID)
        XCTAssertNotNil(store.physicalTriangleTarget(participantID: nil, sharedSession: false))
        store.endTrianglePlacement()
        XCTAssertEqual(store.triangleLockMode, .visualise)
        XCTAssertNil(store.sharedPitchAnchorID)
    }
}
