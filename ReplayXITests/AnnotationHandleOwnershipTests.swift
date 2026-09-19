import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationHandleOwnershipTests: XCTestCase {
    func testCancelledAIsUnableToPreviewFinishOrCancelReplacementBOnSameMark() throws {
        let (store, mark) = try fixture()
        let a = UUID(), b = UUID()
        XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: a, point: point(1)))
        XCTAssertTrue(store.cancelCoachMarkHandlePreview(id: mark.id, gestureID: a))
        XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: b, point: point(2)))
        let replacement = store.marks
        XCTAssertFalse(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: a, point: point(3)))
        XCTAssertFalse(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: a, point: point(3)))
        XCTAssertFalse(store.cancelCoachMarkHandlePreview(id: mark.id, gestureID: a))
        XCTAssertEqual(store.marks, replacement)
        XCTAssertTrue(store.isCoachMarkHandlePreviewOwner(id: mark.id, gestureID: b))
        XCTAssertTrue(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: b, point: point(4)))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }?.end, point(4))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertFalse(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: b, point: point(5)))
    }

    func testOppositeEndpointLegacyCommitCurveAndJoystickCannotTakeHandleOwner() throws {
        let (store, mark) = try fixture()
        let id = UUID()
        XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: point(1)))
        let preview = store.marks
        XCTAssertFalse(store.previewCoachMarkHandle(id: mark.id, endpoint: .start, gestureID: id, point: .init(x: -21, z: -21)))
        XCTAssertFalse(store.previewCoachMarkHandle(id: mark.id, endpoint: .start, gestureID: UUID(), point: .init(x: -21, z: -21)))
        XCTAssertFalse(store.updateCoachMarkGeometry(id: mark.id, start: mark.start, end: point(4)))
        XCTAssertFalse(store.commitCoachMarkGeometryPreview(id: mark.id, start: mark.start, end: point(4)))
        XCTAssertFalse(store.previewCoachMarkCurve(id: mark.id, gestureID: UUID(), curve: .init(bend: 3, lift: 2)))
        XCTAssertNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end, gestureID: UUID(), cumulativeDelta: .init(x: 1, z: 1)))
        XCTAssertEqual(store.marks, preview)
        XCTAssertTrue(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: id, point: point(2)))
    }

    func testTooShortSamplesRecoverAndKeepOriginalUndoBaseline() throws {
        let (store, mark) = try fixture()
        let id = UUID()
        XCTAssertFalse(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: mark.start))
        XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: point(1)))
        let valid = store.marks
        XCTAssertFalse(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: mark.start))
        XCTAssertEqual(store.marks, valid)
        XCTAssertTrue(store.isCoachMarkHandlePreviewOwner(id: mark.id, gestureID: id))
        XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: point(2)))
        XCTAssertTrue(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: id, point: point(3)))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testInvalidFinalRestoresAllKeyframesAndTrackingAnchors() throws {
        for variant in 0...2 {
            let (store, created) = try fixture()
            if variant == 1 {
                XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
                store.seek(to: 7)
                XCTAssertTrue(store.updateCoachMarkGeometry(id: created.id, start: created.start, end: point(1)))
                store.seek(to: 6)
            } else if variant == 2 {
                XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: store.selectedScenario.homePlayers[0].id))
            }
            let baseline = store.marks
            let mark = try XCTUnwrap(baseline.first { $0.id == created.id })
            if variant == 1 { XCTAssertEqual(mark.keyframes?.count, 2) }
            if variant == 2 { XCTAssertNotNil(mark.startTrackAnchor); XCTAssertNotNil(mark.endTrackAnchor) }
            let resolved = store.presentedCoachMarkGeometry(mark, at: store.playhead)
            let id = UUID()
            XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id,
                point: .init(x: resolved.end.x + 1, z: resolved.end.z + 1)))
            XCTAssertEqual(store.makeSavedReviewState().marks, baseline)
            XCTAssertFalse(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: id, point: resolved.start))
            XCTAssertEqual(store.marks, baseline)
            XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertFalse(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: point(2)))
        }
    }

    func testNonfiniteFinalRollsBackOnlyItsMatchingOwner() throws {
        let (store, mark) = try fixture()
        let id = UUID()
        XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: point(1)))
        let preview = store.marks
        XCTAssertFalse(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: UUID(), point: .init(x: .nan, z: 0)))
        XCTAssertEqual(store.marks, preview)
        XCTAssertFalse(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: id, point: .init(x: .nan, z: 0)))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testAuthoritativeCancellationAndRoomSessionCleanupRetireTokens() throws {
        for cleanup in 0...3 {
            let (store, mark) = try fixture()
            let id = UUID()
            XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: point(1)))
            switch cleanup {
            case 0: XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
            case 1: store.prepareForImmersiveExit()
            case 2: store.resetCollaborationState()
            default: store.setCollaborationActive(true)
            }
            XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
            XCTAssertFalse(store.isCoachMarkHandlePreviewOwner(id: mark.id, gestureID: id))
            XCTAssertFalse(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: point(2)))
            let replacement = UUID()
            XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .start, gestureID: replacement,
                point: .init(x: mark.start.x - 1, z: mark.start.z - 1)))
            XCTAssertFalse(store.cancelCoachMarkHandlePreview(id: mark.id, gestureID: id))
            XCTAssertTrue(store.cancelCoachMarkHandlePreview(id: mark.id, gestureID: replacement))
        }
    }

    func testScenarioResetRestoreAndClearCannotInvalidateAnOwnedPreview() throws {
        let (store, mark) = try fixture()
        XCTAssertTrue(store.saveReview(named: "Before handle"))
        let review = try XCTUnwrap(store.savedReviews.first)
        let scenario = store.selectedScenarioID
        let other = try XCTUnwrap(store.scenarios.first { $0.id != scenario })
        let id = UUID()
        XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: point(1)))
        let preview = store.marks
        store.selectScenario(id: other.id)
        store.resetScenario()
        XCTAssertFalse(store.restoreSavedReview(id: review.id))
        store.clearMarks()
        XCTAssertEqual(store.selectedScenarioID, scenario)
        XCTAssertEqual(store.marks, preview)
        XCTAssertTrue(store.isCoachMarkHandlePreviewOwner(id: mark.id, gestureID: id))
        XCTAssertTrue(store.cancelCoachMarkHandlePreview(id: mark.id, gestureID: id))
        store.selectScenario(id: other.id)
        store.selectScenario(id: scenario)
        XCTAssertFalse(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: id, point: point(2)))
    }

    func testTokenHandleCannotEnterCurveOrJoystickPreview() throws {
        for curve in [false, true] {
            let (store, mark) = try fixture()
            let token = UUID()
            if curve {
                XCTAssertTrue(store.previewCoachMarkCurve(id: mark.id, gestureID: token, curve: .init(bend: 3, lift: 1)))
            } else {
                XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                    gestureID: token, cumulativeDelta: .init(x: 1, z: 1)))
            }
            let preview = store.marks
            let rejected = UUID()
            XCTAssertFalse(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: rejected, point: point(3)))
            XCTAssertFalse(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: rejected, point: point(3)))
            XCTAssertFalse(store.cancelCoachMarkHandlePreview(id: mark.id, gestureID: rejected))
            XCTAssertEqual(store.marks, preview)
            if curve { XCTAssertTrue(store.cancelCoachMarkCurvePreview(id: mark.id, gestureID: token)) }
            else { XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: token)) }
        }
    }

    func testPreviewAutosaveIsMaskedAndFinalGeometrySurvivesReopenAsOneUndo() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnnotationHandleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reviews.json")
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        let (store, mark) = try fixture(store: ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library))
        let baseline = store.makeSavedReviewState()
        let id = UUID()
        for offset in 1...4 {
            XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end,
                gestureID: id, point: point(Float(offset))))
        }
        XCTAssertTrue(store.flushReviewAutosave())
        let masked = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        XCTAssertEqual(masked.autosavedReview?.state.marks, baseline.marks)
        XCTAssertEqual(masked.autosavedReview?.state.playhead, baseline.playhead)

        XCTAssertTrue(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: id, point: point(5)))
        let final = store.makeSavedReviewState()
        XCTAssertEqual(final.marks.first { $0.id == mark.id }?.end, point(5))
        XCTAssertTrue(store.flushReviewAutosave())
        let reopened = ReplayStore(scenarios: DemoScenarios.all,
            reviewLibrary: ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url))
        XCTAssertTrue(reopened.restoreAutosavedReview())
        XCTAssertEqual(reopened.marks, final.marks)
        XCTAssertEqual(reopened.playhead, baseline.playhead)
        XCTAssertFalse(reopened.hasActiveCoachMarkGeometryPreview)
        XCTAssertFalse(reopened.isCoachMarkHandlePreviewOwner(id: mark.id, gestureID: id))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline.marks, "All preview samples and final coordinates form one Undo")
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks, final.marks)
        store.flushReviewAutosave()
        reopened.flushReviewAutosave()
    }

    private func fixture(store providedStore: ReplayStore? = nil) throws -> (ReplayStore, CoachMark) {
        let store = providedStore ?? ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: -20, z: -20))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
        if created.followsPlayerTracks { XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil)) }
        return (store, try XCTUnwrap(store.marks.first { $0.id == created.id }))
    }

    private func point(_ offset: Float) -> PitchPoint { .init(x: -16 + offset, z: -14 + offset) }
}
