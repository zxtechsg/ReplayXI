import XCTest
@testable import ReplayXI

@MainActor
final class ReplayLiveEditing185Tests: XCTestCase {
    private func fixture(kind: CoachMarkKind = .pass) throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 0)
        let mark = try XCTUnwrap(store.addMacCoachMark(kind: kind,
            start: .init(x: -20, z: -20), end: .init(x: -10, z: -10),
            startElevation: 0, endElevation: 0, label: "Live edit"))
        return (store, mark)
    }

    func testDroppingOnThenOffPlayerKeepsEarlierBindingsAndUndo() throws {
        let (store, original) = try fixture()
        let player = try XCTUnwrap(store.selectedScenario.players.first)
        store.seek(to: 2)
        let target = store.presentedPlayerPose(for: player, at: 2).position
        let token = UUID()
        XCTAssertTrue(store.previewCoachMarkHandle(id: original.id, endpoint: .end,
            gestureID: token, point: target))
        XCTAssertEqual(store.makeSavedReviewState().marks.first { $0.id == original.id }, original)
        XCTAssertTrue(store.commitCoachMarkHandlePreview(id: original.id, gestureID: token, point: target))
        let linked = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(linked.keyframes?.map(\.time), [0, 2])
        XCTAssertNil(linked.sampled(at: 1).endTrackAnchor)
        XCTAssertEqual(linked.sampled(at: 2).endTrackAnchor?.playerID, player.id)
        let follows = store.presentedCoachMarkGeometry(linked, at: 4)
        XCTAssertEqual(follows.end, store.presentedPlayerPose(for: player, at: 4).position)

        store.seek(to: 5)
        let releasedPoint = PitchPoint(x: -32, z: -50)
        let release = UUID()
        XCTAssertTrue(store.previewCoachMarkHandle(id: original.id, endpoint: .end,
            gestureID: release, point: releasedPoint))
        XCTAssertTrue(store.commitCoachMarkHandlePreview(id: original.id, gestureID: release, point: releasedPoint))
        let released = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(released.keyframes?.map(\.time), [0, 2, 5])
        XCTAssertEqual(released.sampled(at: 4).endTrackAnchor?.playerID, player.id)
        XCTAssertNil(released.sampled(at: 5).endTrackAnchor)
        XCTAssertEqual(store.presentedCoachMarkGeometry(released, at: 6).end, releasedPoint)
        XCTAssertEqual(try JSONDecoder().decode(CoachMark.self, from: JSONEncoder().encode(released)), released)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == original.id }, linked)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == original.id }, released)
    }

    func testCancelledAutoBindingRestoresPoseAndDoesNotPersistPreview() throws {
        let (store, mark) = try fixture()
        store.seek(to: 3)
        let point = store.presentedPlayerPose(for: store.selectedScenario.players[0], at: 3).position
        let token = UUID()
        XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: token, point: point))
        XCTAssertEqual(store.makeSavedReviewState().marks.first { $0.id == mark.id }, mark)
        XCTAssertTrue(store.cancelCoachMarkHandlePreview(id: mark.id, gestureID: token))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testArcBendRecordsIndependentXYZAndHeightEditKeepsHistoricalBinding() throws {
        let (store, mark) = try fixture(kind: .arc)
        store.seek(to: 2)
        let control: SIMD3<Float> = [-7, 5, -17]
        XCTAssertTrue(store.updateCoachMarkArcControlPoint(id: mark.id, point: control))
        let edited = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(edited.keyframes?.map(\.time), [0, 2])
        let pose = edited.sampled(at: 2)
        let actual = pose.resolvedCurve.controlPoint(for: pose)
        XCTAssertEqual(actual.x, control.x, accuracy: 0.0001)
        XCTAssertEqual(actual.y, control.y, accuracy: 0.0001)
        XCTAssertEqual(actual.z, control.z, accuracy: 0.0001)
        XCTAssertEqual(edited.sampled(at: 0).resolvedCurve, mark.resolvedCurve)
        let player = store.selectedScenario.players[0]
        XCTAssertTrue(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .end, playerID: player.id))
        store.seek(to: 4)
        XCTAssertTrue(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .end, playerID: nil))
        store.seek(to: 2)
        XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .start, by: 0.5))
        let final = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(final.sampled(at: 2).endTrackAnchor?.playerID, player.id)
        XCTAssertNil(final.sampled(at: 4).endTrackAnchor)
    }

    func testEndHerePreservesPastAndDeleteEverywhereIsSeparateAndUndoable() throws {
        let (store, mark) = try fixture()
        store.seek(to: 0.1)
        XCTAssertTrue(store.endCoachMarkHere(id: mark.id))
        let ended = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertTrue(ended.isVisible(at: 0.05))
        XCTAssertFalse(ended.isVisible(at: 0.1))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        store.seek(to: 2)
        XCTAssertTrue(store.startCoachMarkHere(id: mark.id))
        XCTAssertFalse(try XCTUnwrap(store.marks.first { $0.id == mark.id }).isVisible(at: 1))
        XCTAssertFalse(store.endCoachMarkHere(id: mark.id))
        XCTAssertTrue(store.removeCoachMark(id: mark.id))
        XCTAssertNil(store.marks.first { $0.id == mark.id })
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertNotNil(store.marks.first { $0.id == mark.id })
    }

    func testHeadsetMarksStayVisibleUntilExplicitEnd() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 0)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(.init(x: -20, z: -20)))
        let drawn = try XCTUnwrap(store.registerPitchTap(.init(x: -10, z: -10)))
        XCTAssertNil(drawn.hideTime)
        XCTAssertTrue(drawn.isVisible(at: store.selectedScenario.duration))
        let label = try XCTUnwrap(store.labelPlayer(store.selectedScenario.players[0].id))
        XCTAssertNil(label.hideTime)
        store.seek(to: 4)
        XCTAssertTrue(store.endCoachMarkHere(id: drawn.id))
        XCTAssertEqual(store.marks.first { $0.id == drawn.id }?.hideTime, 4)
    }

    func testLinkedOffsetsInterpolateButBindingChangesWaitForTheirTimestamp() {
        let first = CoachMark(kind: .pass, start: .init(x: 0, z: 0), end: .init(x: 10, z: 10),
            label: "Linked", revealTime: 0,
            endTrackAnchor: .init(playerID: "player", offset: .zero)).recordingPose(at: 0)
        let moved = CoachMark(id: first.id, kind: first.kind, start: first.start,
            end: .init(x: 14, z: 12), label: first.label, revealTime: 0,
            endTrackAnchor: .init(playerID: "player", offset: .init(x: 4, z: 2)),
            keyframes: first.keyframes).recordingPose(at: 4)
        XCTAssertEqual(moved.sampled(at: 2).endTrackAnchor?.offset, .init(x: 2, z: 1))
        XCTAssertEqual(moved.sampled(at: 4).endTrackAnchor?.offset, .init(x: 4, z: 2))
        let detached = CoachMark(id: first.id, kind: first.kind, start: first.start,
            end: moved.end, label: first.label, revealTime: 0,
            keyframes: moved.keyframes).recordingPose(at: 6)
        XCTAssertEqual(detached.sampled(at: 5).endTrackAnchor?.offset, .init(x: 4, z: 2))
        XCTAssertNil(detached.sampled(at: 6).endTrackAnchor)
    }

    func testFreezeTrackedPoseKeepsDisplayedShapeAndUndoRestoresHistory() throws {
        let (store, original) = try fixture(kind: .arc)
        store.seek(to: 2)
        XCTAssertTrue(store.setCoachMarkTracking(id: original.id,
            playerID: store.selectedScenario.players[0].id))
        store.seek(to: 4)
        let tracked = try XCTUnwrap(store.marks.first { $0.id == original.id })
        let displayed = store.presentedCoachMarkGeometry(tracked, at: 4)
        XCTAssertTrue(store.freezeCoachMarkKeyframes(id: original.id))
        let frozen = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertNil(frozen.keyframes)
        XCTAssertFalse(frozen.followsPlayerTracks)
        XCTAssertEqual(frozen.start, displayed.start)
        XCTAssertEqual(frozen.end, displayed.end)
        XCTAssertEqual(store.presentedCoachMarkGeometry(frozen, at: 6).end, displayed.end)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == original.id }, tracked)
    }

    func testEndHereWorksAfterThirtySecondsWithoutRemovingEarlierVisibility() throws {
        let store = ReplayStore()
        XCTAssertGreaterThan(store.selectedScenario.duration, 30)
        store.seek(to: 0)
        store.beginDrawing(.pass)
        _ = store.registerPitchTap(.init(x: -20, z: -20))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: -10, z: -10)))
        store.seek(to: 31)
        XCTAssertTrue(store.endCoachMarkHere(id: mark.id))
        let ended = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertTrue(ended.isVisible(at: 30))
        XCTAssertFalse(ended.isVisible(at: 31))
        XCTAssertTrue(ReplayStore.isValidReviewMark(ended, for: store.selectedScenario))
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks.first { $0.id == mark.id }, ended)
    }
}
