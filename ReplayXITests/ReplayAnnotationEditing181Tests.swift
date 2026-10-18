import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAnnotationEditing181Tests: XCTestCase {
    private func fixture() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 2)
        let mark = try XCTUnwrap(store.addMacCoachMark(kind: .arc,
            start: .init(x: -10, z: -12), end: .init(x: 3, z: 8),
            startElevation: 0.2, endElevation: 0.8, label: "Overlap"))
        return (store, mark)
    }

    func testOriginLinkKeepsOffsetAndLeavesEndFixed() throws {
        let (store, mark) = try fixture()
        let player = try XCTUnwrap(store.selectedScenario.homePlayers.first { !$0.isGoalkeeper })
        let playerStart = store.presentedPlayerPose(for: player, at: 2).position
        XCTAssertTrue(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .start, playerID: player.id))
        let linked = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(linked.startTrackAnchor?.playerID, player.id)
        XCTAssertNil(linked.endTrackAnchor)
        let initial = store.presentedCoachMarkGeometry(linked, at: 2)
        XCTAssertEqual(initial.start.x, mark.start.x, accuracy: 0.0001)
        XCTAssertEqual(initial.start.z, mark.start.z, accuracy: 0.0001)
        store.seek(to: 6)
        let moved = store.presentedCoachMarkGeometry(linked, at: 6)
        let playerEnd = store.presentedPlayerPose(for: player, at: 6).position
        XCTAssertEqual(moved.start.x - initial.start.x, playerEnd.x - playerStart.x, accuracy: 0.0001)
        XCTAssertEqual(moved.start.z - initial.start.z, playerEnd.z - playerStart.z, accuracy: 0.0001)
        XCTAssertEqual(moved.end, mark.end)
        XCTAssertTrue(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .start, playerID: nil))
        let frozen = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(frozen.start.x, moved.start.x, accuracy: 0.0001)
        XCTAssertEqual(frozen.start.z, moved.start.z, accuracy: 0.0001)
        XCTAssertFalse(frozen.followsPlayerTracks)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, linked)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, frozen)
    }

    func testEachEndCanLinkToADifferentTeamAndRoundTrip() throws {
        let (store, mark) = try fixture()
        let home = try XCTUnwrap(store.selectedScenario.homePlayers.first)
        let away = try XCTUnwrap(store.selectedScenario.awayPlayers.first)
        XCTAssertTrue(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .start, playerID: home.id))
        XCTAssertTrue(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .end, playerID: away.id))
        let linked = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(linked.startTrackAnchor?.playerID, home.id)
        XCTAssertEqual(linked.endTrackAnchor?.playerID, away.id)
        XCTAssertEqual(try JSONDecoder().decode(CoachMark.self, from: JSONEncoder().encode(linked)), linked)
        XCTAssertTrue(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .end, playerID: nil))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }?.startTrackAnchor, linked.startTrackAnchor)
        XCTAssertFalse(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .both, playerID: home.id))
        XCTAssertFalse(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .start, playerID: "not-on-pitch"))
    }

    func testFirstDragRecordsBaselineAndNewPoseAsOneUndo() throws {
        let (store, mark) = try fixture()
        store.seek(to: 6)
        XCTAssertTrue(store.setMacCoachMarkPose(id: mark.id,
            start: .init(x: -6, z: -8), end: .init(x: 10, z: 14),
            startElevation: 0.4, endElevation: 1.2, recordMotion: true))
        let animated = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(animated.keyframes?.map(\.time), [2, 6])
        XCTAssertEqual(animated.sampled(at: 2).start, mark.start)
        XCTAssertEqual(animated.sampled(at: 4).start.x, -8, accuracy: 0.0001)
        XCTAssertEqual(animated.sampled(at: 6).resolvedEndElevation, 1.2, accuracy: 0.0001)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, animated)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks.first { $0.id == mark.id }, animated)
    }

    func testMotionEditDoesNotDeleteTrackingAndLinksDoNotDeleteKeys() throws {
        let (store, mark) = try fixture()
        let player = try XCTUnwrap(store.selectedScenario.homePlayers.first)
        XCTAssertTrue(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .start, playerID: player.id))
        XCTAssertTrue(store.setMacCoachMarkPose(id: mark.id,
            start: .init(x: -9, z: -10), end: mark.end,
            startElevation: 0.2, endElevation: 0.8, recordMotion: true))
        let linked = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertFalse(linked.hasKeyframes)
        XCTAssertNotNil(linked.startTrackAnchor)
        XCTAssertTrue(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .start, playerID: nil))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        let keys = store.marks
        XCTAssertFalse(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .end, playerID: player.id))
        XCTAssertEqual(store.marks, keys)
    }

    func testWireEndpointAndMotionCommandsKeepRevisionAndTimeGates() throws {
        let (store, mark) = try fixture()
        let service = ReplayXILocalCoachService(store: store)
        let player = try XCTUnwrap(store.selectedScenario.players.first)
        var command = ReplayXIWireCommand(name: "trackEndpoint", expectedRevision: 0,
            expectedScenarioID: store.selectedScenarioID, time: store.playhead,
            playerID: player.id, markID: mark.id, endpoint: "start")
        command.expectedRevision = 1
        XCTAssertFalse(service.apply(command))
        command.expectedRevision = 0; command.time = 4
        XCTAssertFalse(service.apply(command))
        command.time = store.playhead; command.endpoint = "invalid"
        XCTAssertFalse(service.apply(command))
        command.endpoint = "start"
        XCTAssertTrue(service.apply(command))
        XCTAssertNotNil(store.marks.first { $0.id == mark.id }?.startTrackAnchor)
        let original = store.marks
        store.setPlaying(true)
        command.playerID = nil
        XCTAssertFalse(service.apply(command))
        XCTAssertEqual(store.marks, original)
    }

    func testInvalidPoseDoesNotLeaveSeedKeyBehind() throws {
        let (store, mark) = try fixture()
        XCTAssertFalse(store.setMacCoachMarkPose(id: mark.id, start: .init(x: .nan, z: 0), end: mark.end,
            startElevation: 0, endElevation: 1, recordMotion: true))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testEditingBeforeVisibilityStillPreservesOriginalRevealPose() throws {
        let (store, mark) = try fixture()
        store.seek(to: 1)
        XCTAssertTrue(store.setMacCoachMarkPose(id: mark.id, start: .init(x: -8, z: -10), end: mark.end,
            startElevation: 0.2, endElevation: 0.8, recordMotion: true))
        let animated = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(animated.keyframes?.map(\.time), [1, 2])
        XCTAssertEqual(animated.sampled(at: 2).start, mark.start)
    }
}
