import XCTest
@testable import ReplayXI

@MainActor
final class ReplayShapeDraftContinuityTests: XCTestCase {
    func testEmptyShapeDraftRejectsEveryComparisonWithoutMovingTimeOrPlayers() throws {
        for originalStage in ShapeFocusStage.allCases {
            for requestedStage in ShapeFocusStage.allCases {
                let store = makeStore(stage: originalStage)
                store.seek(to: originalStage.referenceTime - 0.5, broadcast: false)
                let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
                let originalTime = store.playhead
                let originalPose = store.presentedPlayerPose(for: player, at: originalTime)
                let originalMarks = store.marks
                store.beginDrawing(.run)

                store.setShapeFocusStage(requestedStage, broadcast: false)

                XCTAssertTrue(store.isDrawing)
                XCTAssertNil(store.pendingDrawStart)
                XCTAssertEqual(store.shapeFocusStage, originalStage)
                XCTAssertEqual(store.playhead, originalTime)
                XCTAssertEqual(store.presentedPlayerPose(for: player, at: store.playhead), originalPose)
                XCTAssertEqual(store.marks, originalMarks)
                XCTAssertFalse(store.isPlaying)
            }
        }
    }

    func testStartedShapeDraftKeepsOriginalTimeAndPlayerBindingAcrossComparisonRequests() throws {
        for originalStage in ShapeFocusStage.allCases {
            let store = makeStore(stage: originalStage)
            let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
            let originalTime = store.playhead
            let start = store.presentedPlayerPose(for: player, at: originalTime).position
            store.beginDrawing(.run)
            XCTAssertNil(store.registerPitchTap(start))

            store.setShapeFocusStage(originalStage == .problem ? .ideal : .problem, broadcast: false)

            XCTAssertEqual(store.shapeFocusStage, originalStage)
            XCTAssertEqual(store.playhead, originalTime)
            XCTAssertEqual(store.pendingDrawStart, start)
            XCTAssertEqual(store.presentedPlayerPose(for: player, at: store.playhead).position, start)
            XCTAssertTrue(store.isDrawing)

            let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 28, z: 34)))
            XCTAssertEqual(mark.revealTime, originalTime)
            XCTAssertEqual(mark.startTrackAnchor?.playerID, player.id)
            XCTAssertNil(mark.endTrackAnchor, "An endpoint away from players stays pitch-fixed")
            XCTAssertEqual(store.presentedCoachMarkGeometry(mark, at: originalTime).start, start)
            XCTAssertTrue(ReplayStore.isValidReviewMark(mark, for: store.selectedScenario))
            XCTAssertTrue(store.saveReview(named: "Original drawing moment"))
        }
    }

    func testCancelReleasesComparisonWithoutChangingCommittedMarksOrUndoHistory() throws {
        let store = makeStore(stage: .problem)
        let baseline = store.marks
        let mark = try drawPlayerRun(in: store)
        let committed = store.marks
        let undoTitle = store.annotationUndoTitle
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -3, z: 2)))

        store.cancelDrawing()
        store.setShapeFocusStage(.ideal, broadcast: false)

        XCTAssertFalse(store.isDrawing)
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertEqual(store.shapeFocusStage, .ideal)
        XCTAssertEqual(store.playhead, ShapeFocusStage.ideal.referenceTime)
        XCTAssertEqual(store.marks, committed)
        XCTAssertEqual(store.annotationUndoTitle, undoTitle)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.last, mark)
        XCTAssertEqual(store.marks, committed)
    }

    func testCompletedShapeRunSurvivesComparisonUndoRedoAndSavedRestoration() throws {
        let store = makeStore(stage: .problem)
        let mark = try drawPlayerRun(in: store)
        store.setShapeFocusStage(.ideal, broadcast: false)
        let idealGeometry = store.presentedCoachMarkGeometry(mark, at: store.playhead)
        XCTAssertEqual(store.shapeFocusStage, .ideal)
        XCTAssertEqual(store.playhead, ShapeFocusStage.ideal.referenceTime)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertFalse(store.marks.contains(where: { $0.id == mark.id }))
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.last, mark)
        XCTAssertEqual(store.presentedCoachMarkGeometry(mark, at: store.playhead), idealGeometry)
        XCTAssertTrue(store.saveReview(named: "Shape comparison"))
        let review = try XCTUnwrap(store.savedReviews.first)

        store.setShapeFocusStage(.problem, broadcast: false)
        XCTAssertEqual(store.playhead, ShapeFocusStage.problem.referenceTime)
        XCTAssertTrue(store.restoreReview(review))

        XCTAssertEqual(store.shapeFocusStage, .ideal)
        XCTAssertEqual(store.playhead, ShapeFocusStage.ideal.referenceTime)
        XCTAssertEqual(store.marks.last, mark)
        XCTAssertEqual(store.presentedCoachMarkGeometry(mark, at: store.playhead), idealGeometry)
        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(store.isDrawing)
    }

    private func makeStore(stage: ShapeFocusStage) -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "triangle-lock", broadcast: false)
        store.setShapeFocusStage(stage, broadcast: false)
        return store
    }

    private func drawPlayerRun(in store: ReplayStore) throws -> CoachMark {
        let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(store.presentedPlayerPose(for: player, at: store.playhead).position))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 28, z: 34)))
        XCTAssertEqual(mark.startTrackAnchor?.playerID, player.id)
        return mark
    }
}
