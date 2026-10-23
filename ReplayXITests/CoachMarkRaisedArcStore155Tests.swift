import Foundation
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkRaisedArcStore155Tests: XCTestCase {
    func testBothNewAuthoringRoutesCaptureTheOriginalBendDirection() throws {
        let store = ReplayStore()
        store.beginDrawing(.arc)
        let start = PitchPoint(x: 26, z: 30), end = PitchPoint(x: 28, z: 34)
        XCTAssertNil(store.registerPitchTap(start))
        let drawn = try XCTUnwrap(store.registerPitchTap(end))
        XCTAssertEqual(drawn.curve, CoachMarkCurve.initial(start: start, end: end).stabilized(start: start, end: end))
        assertSameCentreline(drawn, replacingCurveWith: .initial(start: start, end: end))

        let ids = Set(store.marks.map(\.id))
        store.selectedTool = .arc
        store.addPresetMark()
        let preset = try XCTUnwrap(store.marks.first { !ids.contains($0.id) })
        XCTAssertNotNil(preset.curve?.bendBearingDegrees)
        assertSameCentreline(preset, replacingCurveWith: .initial(start: preset.start, end: preset.end))
    }

    func testLegacyNoOpAndOriginReturnDoNotMigrateSaveOrUndo() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayXI-Arc155-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reviews.json")
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)
        let mark = legacy()
        XCTAssertTrue(store.appendRemoteCoachMark(mark))
        XCTAssertTrue(store.flushReviewAutosave())
        let bytes = try Data(contentsOf: url), before = store.makeSavedReviewState()
        let undo = store.annotationUndoTitle
        var broadcasts = 0
        store.onBroadcastSnapshot = { _ in broadcasts += 1 }

        for broadcast in [false, true] {
            XCTAssertFalse(store.updateCoachMarkGeometry(id: mark.id, start: mark.start,
                                                         end: mark.end, broadcast: broadcast))
        }
        XCTAssertFalse(store.nudgeCoachMarkCurve(id: mark.id, bendDelta: 0, liftDelta: 0))
        XCTAssertFalse(store.nudgeCoachMarkElevation(id: mark.id, target: .start, by: -1))
        XCTAssertFalse(store.nudgeCoachMarkEndpoint(id: mark.id, endpoint: .end, by: .zero))
        XCTAssertNil(store.scheduledReviewAutosaveID)
        XCTAssertEqual(store.makeSavedReviewState(), before)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)

        let token = UUID()
        XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end,
            gestureID: token, point: .init(x: mark.end.x + 1, z: mark.end.z)))
        XCTAssertNotNil(try current(mark.id, in: store).curve?.bendBearingDegrees)
        XCTAssertEqual(store.makeSavedReviewState(), before)
        XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end,
            gestureID: token, point: mark.end))
        XCTAssertEqual(try current(mark.id, in: store), mark)
        XCTAssertTrue(store.isCoachMarkHandlePreviewOwner(id: mark.id, gestureID: token))
        XCTAssertFalse(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: token, point: mark.end))
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertEqual(try current(mark.id, in: store), mark)
        XCTAssertEqual(store.annotationUndoTitle, undo)
        XCTAssertFalse(store.canUndoAnnotationEdit)
        XCTAssertEqual(broadcasts, 0)
        _ = store.flushReviewAutosave()
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testEndpointNudgeDirectHandleAndJoystickPreserveBasisAcrossVertical() throws {
        for route in 0..<3 {
            let store = ReplayStore()
            let mark = legacy(start: .init(x: 20, z: 20), end: .init(x: 21, z: 20), endElevation: 2)
            XCTAssertTrue(store.appendRemoteCoachMark(mark))
            let baseline = store.marks
            let destination = PitchPoint(x: 19.5, z: 20)
            switch route {
            case 0:
                XCTAssertTrue(store.nudgeCoachMarkEndpoint(id: mark.id, endpoint: .end, by: .init(x: -1.5, z: 0)))
            case 1:
                let token = UUID()
                XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end,
                    gestureID: token, point: mark.start))
                XCTAssertEqual(store.makeSavedReviewState().marks, baseline)
                XCTAssertTrue(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: token, point: destination))
            default:
                let token = UUID()
                XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                    gestureID: token, cumulativeDelta: .init(x: -1, z: 0)))
                XCTAssertEqual(store.makeSavedReviewState().marks, baseline)
                XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                    gestureID: token, cumulativeDelta: .init(x: -1.5, z: 0)))
                XCTAssertNotNil(store.commitCoachMarkEndpointPreview(id: mark.id, gestureID: token))
            }
            let edited = try current(mark.id, in: store)
            XCTAssertEqual(edited.end, destination)
            XCTAssertEqual(edited.curve?.bendBearingDegrees,
                mark.resolvedCurve.stabilized(start: mark.start, end: mark.end).bendBearingDegrees,
                "Every route must retain the exact pre-move basis")
            XCTAssertEqual(try XCTUnwrap(edited.curve?.bendBearingDegrees), 90, accuracy: 0.00002,
                           "atan2 Float-to-degree conversion can round by one ULP")
            XCTAssertGreaterThan(edited.resolvedCurve.point(at: 0.5, for: edited).z, 20.9)
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, baseline, "Undo must restore nil bearing, not just equivalent pixels")
        }
    }

    func testElevationConversionPreservesLegacyShapeAndRejectsThreeDimensionalCollapse() throws {
        let store = ReplayStore(), mark = legacy()
        XCTAssertTrue(store.appendRemoteCoachMark(mark))
        XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .both, by: 1))
        let raised = try current(mark.id, in: store)
        XCTAssertNotNil(raised.curve?.bendBearingDegrees)
        let equivalent = copy(mark, startElevation: 1, endElevation: 1)
        for index in 0...32 {
            let t = Float(index) / 32
            XCTAssertLessThan(simd_distance(raised.resolvedCurve.point(at: t, for: raised),
                equivalent.resolvedCurve.point(at: t, for: equivalent)), 0.00001)
        }
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(try current(mark.id, in: store), mark)

        let vertical = legacy(start: .init(x: 20, z: 20), end: .init(x: 20, z: 20), endElevation: 1)
        XCTAssertTrue(store.appendRemoteCoachMark(vertical))
        store.setPlaying(true, broadcast: false)
        let before = store.makeSavedReviewState(), undo = store.annotationUndoTitle
        XCTAssertFalse(store.nudgeCoachMarkElevation(id: vertical.id, target: .end, by: -0.5))
        XCTAssertEqual(store.makeSavedReviewState(), before)
        XCTAssertEqual(store.annotationUndoTitle, undo)
        XCTAssertTrue(store.isPlaying)
    }

    func testLegacyVerticalCurveControlsStartFromEffectiveZeroAndKeepOwnedCancellation() throws {
        for mode in AnnotationCurveAdjustmentController.Mode.allCases {
            let store = ReplayStore()
            let mark = legacy(start: .init(x: 20, z: 20), end: .init(x: 20, z: 20),
                              endElevation: 2, bend: 3)
            XCTAssertTrue(store.appendRemoteCoachMark(mark))
            let before = store.marks
            let controller = AnnotationCurveAdjustmentController()
            let baseline = store.editableCoachMarkCurve(mark, at: store.playhead)
            XCTAssertEqual(baseline.bend, 0)
            XCTAssertEqual(baseline.bendBearingDegrees, 90)
            XCTAssertTrue(controller.preview(in: store, markID: mark.id,
                translation: CGSize(width: 20, height: 0), mode: mode))
            XCTAssertEqual(try XCTUnwrap(controller.transaction).baseline, baseline)
            let preview = try current(mark.id, in: store)
            XCTAssertGreaterThan(preview.resolvedCurve.bend, 0)
            XCTAssertLessThan(preview.resolvedCurve.bend, 1)
            XCTAssertEqual(preview.curve?.bendBearingDegrees, 90)
            XCTAssertEqual(store.makeSavedReviewState().marks, before)
            controller.cancel(in: store)
            XCTAssertEqual(store.marks, before)
            XCTAssertTrue(controller.adjust(in: store, markID: mark.id, mode: mode,
                                            horizontal: 0.25, vertical: 0))
            XCTAssertEqual(try current(mark.id, in: store).resolvedCurve.bend, 0.25)
            XCTAssertEqual(try current(mark.id, in: store).curve?.bendBearingDegrees, 90)
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, before)
        }
    }

    func testCurveOriginReturnAndAtomicNudgePreserveLegacyAndFixedBearing() throws {
        let store = ReplayStore(), mark = legacy()
        XCTAssertTrue(store.appendRemoteCoachMark(mark))
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: .init(width: 20, height: -20)))
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: .zero))
        XCTAssertEqual(try current(mark.id, in: store), mark)
        XCTAssertFalse(controller.finish(in: store, markID: mark.id, translation: .zero))
        XCTAssertFalse(store.canUndoAnnotationEdit)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertTrue(store.nudgeCoachMarkCurve(id: mark.id, bendDelta: 0.25, liftDelta: 0.25))
        let edited = try current(mark.id, in: store)
        XCTAssertEqual(edited.curve?.bendBearingDegrees,
                       mark.resolvedCurve.stabilized(start: mark.start, end: mark.end).bendBearingDegrees)
        XCTAssertEqual(edited.resolvedCurve.bend, mark.resolvedCurve.bend + 0.25)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(try current(mark.id, in: store), mark)
    }

    func testTrackedArcSeedsPresentedRatherThanStoredEndpointDirection() throws {
        let store = ReplayStore()
        let a = try XCTUnwrap(store.selectedScenario.players.first)
        let b = try XCTUnwrap(store.selectedScenario.players.last)
        let mark = copy(legacy(), startAnchor: .init(playerID: a.id, offset: .zero),
                         endAnchor: .init(playerID: b.id, offset: .zero))
        XCTAssertTrue(store.appendRemoteCoachMark(mark))
        store.seek(to: 3, broadcast: false)
        let presented = store.presentedCoachMarkGeometry(mark, at: store.playhead)
        let expected = mark.resolvedCurve.stabilized(start: presented.start, end: presented.end)
        XCTAssertNotEqual(expected.bendBearingDegrees,
                          mark.resolvedCurve.stabilized(start: mark.start, end: mark.end).bendBearingDegrees)
        XCTAssertTrue(store.nudgeCoachMarkEndpoint(id: mark.id, endpoint: .end, by: .init(x: 0.25, z: 0)))
        let edited = try current(mark.id, in: store)
        XCTAssertEqual(edited.curve?.bendBearingDegrees, expected.bendBearingDegrees)
        XCTAssertEqual(edited.startTrackAnchor?.playerID, a.id)
        XCTAssertEqual(edited.endTrackAnchor?.playerID, b.id)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(try current(mark.id, in: store), mark)
    }

    func testUnsafeKeyDeletionRetimeAndTimingDraftKeepMarksTransportAndUndo() throws {
        let store = ReplayStore(), mark = threeKeyArc()
        XCTAssertTrue(mark.hasSafeArcKeyframeIntervals)
        XCTAssertTrue(store.appendRemoteCoachMark(mark))
        store.setPlaying(true, broadcast: false)
        let before = store.makeSavedReviewState(), undo = store.annotationUndoTitle
        let attempts: [() -> Bool] = [
            { store.removeCoachMarkKeyframe(id: mark.id, at: 2) },
            { store.retimeCoachMarkKeyframe(id: mark.id, from: 2, to: 5) },
            { store.applyCoachMarkTimingDraft(id: mark.id, windowStart: nil, windowEnd: nil,
                                              keyframeFrom: 2, keyframeTo: 5) }
        ]
        for attempt in attempts {
            XCTAssertFalse(attempt())
            XCTAssertEqual(store.statusMessage, "Move in smaller steps, or adjust motion in Mac coach")
            XCTAssertEqual(store.makeSavedReviewState(), before)
            XCTAssertEqual(store.annotationUndoTitle, undo)
        }
        XCTAssertTrue(store.retimeCoachMarkKeyframe(id: mark.id, from: 2, to: 3))
        XCTAssertTrue(try current(mark.id, in: store).hasSafeArcKeyframeIntervals)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(try current(mark.id, in: store), mark)
    }

    func testImplicitTrackedCurveUsesDisplayedLengthAndAcceptsAnExplicitDifferentBend() throws {
        let store = ReplayStore()
        let a = try XCTUnwrap(store.selectedScenario.players.first)
        let b = try XCTUnwrap(store.selectedScenario.players.last)
        let mark = CoachMark(kind: .arc, start: .init(x: 20, z: 20), end: .init(x: 21, z: 20),
            label: "Implicit tracked arc", startTrackAnchor: .init(playerID: a.id),
            endTrackAnchor: .init(playerID: b.id))
        XCTAssertTrue(store.appendRemoteCoachMark(mark))
        store.seek(to: 3, broadcast: false)
        let geometry = store.presentedCoachMarkGeometry(mark, at: store.playhead)
        let visible = CoachMarkCurve.initial(start: geometry.start, end: geometry.end)
        let expected = visible.stabilized(start: geometry.start, end: geometry.end)
        XCTAssertGreaterThan(abs(visible.bend - mark.resolvedCurve.bend), 0.1,
                             "Actual track length must distinguish visible from stored default")
        XCTAssertEqual(store.editableCoachMarkCurve(mark, at: store.playhead), expected)
        XCTAssertFalse(store.updateCoachMarkGeometry(id: mark.id, start: geometry.start,
                                                     end: geometry.end, curve: visible))
        XCTAssertEqual(try current(mark.id, in: store), mark)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id, start: geometry.start,
                                                    end: geometry.end, curve: mark.resolvedCurve))
        let edited = try current(mark.id, in: store)
        XCTAssertEqual(edited.resolvedCurve.bend, mark.resolvedCurve.bend)
        XCTAssertEqual(edited.curve?.bendBearingDegrees, expected.bendBearingDegrees)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(try current(mark.id, in: store), mark)
        XCTAssertTrue(store.nudgeCoachMarkCurve(id: mark.id, bendDelta: 0.25, liftDelta: 0))
        XCTAssertEqual(try current(mark.id, in: store).resolvedCurve.bend, expected.bend + 0.25)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(try current(mark.id, in: store), mark)
    }

    func testUnsafeKeyedEndpointAndMixedLegacyCurveEditAreRejectedWithoutMigration() throws {
        let store = ReplayStore(), mark = threeKeyArc()
        XCTAssertTrue(store.appendRemoteCoachMark(mark))
        store.seek(to: 4, broadcast: false)
        let before = store.marks
        XCTAssertFalse(store.updateCoachMarkGeometry(id: mark.id, start: .zero,
                                                     end: .init(x: 0, z: -2)))
        XCTAssertEqual(store.statusMessage, "Move in smaller steps, or adjust motion in Mac coach")
        XCTAssertEqual(store.marks, before)

        var old = legacy(start: .zero, end: .init(x: 2, z: 0))
        let first = CoachMarkKeyframe(time: 0, mark: old)
        old = copy(old, end: .init(x: -2, z: 0))
        old.keyframes = [first, CoachMarkKeyframe(time: 4, mark: old)]
        XCTAssertTrue(store.appendRemoteCoachMark(old), "All-legacy crossing data stays readable")
        store.seek(to: 4, broadcast: false)
        XCTAssertFalse(store.nudgeCoachMarkCurve(id: old.id, bendDelta: 0.25, liftDelta: 0))
        XCTAssertEqual(store.statusMessage, "Move in smaller steps, or adjust motion in Mac coach")
        XCTAssertEqual(try current(old.id, in: store), old)
    }

    func testImplicitTrackedCurvePadOriginReturnCannotCommitTheStoredDefault() throws {
        for mode in AnnotationCurveAdjustmentController.Mode.allCases {
            let store = ReplayStore()
            let a = try XCTUnwrap(store.selectedScenario.players.first)
            let b = try XCTUnwrap(store.selectedScenario.players.last)
            let mark = CoachMark(kind: .arc, start: .init(x: 20, z: 20), end: .init(x: 21, z: 20),
                label: "Implicit tracked origin", startTrackAnchor: .init(playerID: a.id),
                endTrackAnchor: .init(playerID: b.id))
            XCTAssertTrue(store.appendRemoteCoachMark(mark))
            store.seek(to: 3, broadcast: false)
            XCTAssertGreaterThan(abs(store.editableCoachMarkCurve(mark, at: store.playhead).bend
                - mark.resolvedCurve.bend), 1)
            let saved = store.makeSavedReviewState()
            var broadcasts = 0
            store.onBroadcastSnapshot = { _ in broadcasts += 1 }
            let controller = AnnotationCurveAdjustmentController()
            XCTAssertTrue(controller.preview(in: store, markID: mark.id,
                translation: .init(width: 20, height: 0), mode: mode))
            XCTAssertNotNil(try current(mark.id, in: store).curve?.bendBearingDegrees)
            XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: .zero, mode: mode))
            XCTAssertEqual(try current(mark.id, in: store), mark)
            XCTAssertFalse(controller.finish(in: store, markID: mark.id, translation: .zero, mode: mode))
            XCTAssertEqual(try current(mark.id, in: store), mark)
            XCTAssertEqual(store.makeSavedReviewState(), saved)
            XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertFalse(store.canUndoAnnotationEdit)
            XCTAssertEqual(broadcasts, 0)
        }
    }

    func testFramedStaticChordValidationDoesNotTightenLegacyOrOtherKinds() throws {
        let store = ReplayStore()
        let old = legacy(start: .zero, end: .zero, endElevation: 0.5)
        XCTAssertTrue(ReplayStore.isValidReviewMark(old, for: store.selectedScenario))
        var framed = copy(old, curve: old.resolvedCurve.stabilized(start: old.start, end: old.end))
        XCTAssertFalse(ReplayStore.isValidReviewMark(framed, for: store.selectedScenario))
        XCTAssertFalse(store.appendRemoteCoachMark(framed))
        framed = copy(framed, endElevation: 1)
        XCTAssertTrue(ReplayStore.isValidReviewMark(framed, for: store.selectedScenario))
        let ordinary = legacy()
        XCTAssertTrue(store.appendRemoteCoachMark(ordinary))
        XCTAssertFalse(store.updateCoachMarkGeometry(id: ordinary.id, start: ordinary.start,
            end: .init(x: ordinary.start.x + 0.25, z: ordinary.start.z)))
        XCTAssertEqual(store.statusMessage, "Keep the annotation at least 0.8 metres long")
        XCTAssertEqual(try current(ordinary.id, in: store), ordinary)
        for kind in [CoachMarkKind.run, .pass, .space] {
            let mark = CoachMark(kind: kind, start: .zero, end: .init(x: 0.1, z: 0), label: "Legacy short")
            XCTAssertTrue(store.appendRemoteCoachMark(mark))
            XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .both, by: 1))
        }
    }

    private func legacy(start: PitchPoint = .init(x: 20, z: 20),
                        end: PitchPoint = .init(x: 22, z: 23), endElevation: Float? = nil,
                        bend: Float = 1) -> CoachMark {
        CoachMark(kind: .arc, start: start, end: end, endElevation: endElevation,
                  curve: .init(bend: bend, lift: 0), label: "Legacy arc")
    }

    private func threeKeyArc() -> CoachMark {
        let old = legacy(start: .zero, end: .init(x: 2, z: 0))
        var mark = copy(old, curve: old.resolvedCurve.stabilized(start: old.start, end: old.end))
        let middle = copy(mark, end: .init(x: 0, z: 2))
        let last = copy(mark, end: .init(x: -2, z: 0))
        mark.keyframes = [CoachMarkKeyframe(time: 0, mark: mark), CoachMarkKeyframe(time: 2, mark: middle),
                          CoachMarkKeyframe(time: 4, mark: last)]
        return mark
    }

    private func current(_ id: UUID, in store: ReplayStore) throws -> CoachMark {
        try XCTUnwrap(store.marks.first { $0.id == id })
    }

    private func copy(_ mark: CoachMark, end: PitchPoint? = nil,
                      startElevation: Float? = nil, endElevation: Float? = nil,
                      curve: CoachMarkCurve? = nil, startAnchor: CoachMarkTrackAnchor? = nil,
                      endAnchor: CoachMarkTrackAnchor? = nil) -> CoachMark {
        CoachMark(id: mark.id, kind: mark.kind, start: mark.start, end: end ?? mark.end,
            startElevation: startElevation ?? mark.startElevation,
            endElevation: endElevation ?? mark.endElevation, curve: curve ?? mark.curve,
            label: mark.label, revealTime: mark.revealTime, hideTime: mark.hideTime,
            author: mark.author, playerID: mark.playerID,
            startTrackAnchor: startAnchor ?? mark.startTrackAnchor,
            endTrackAnchor: endAnchor ?? mark.endTrackAnchor, keyframes: mark.keyframes)
    }

    private func assertSameCentreline(_ mark: CoachMark, replacingCurveWith curve: CoachMarkCurve,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let legacy = copy(mark, curve: curve)
        for index in 0...32 {
            let t = Float(index) / 32
            XCTAssertLessThan(simd_distance(mark.resolvedCurve.point(at: t, for: mark),
                curve.point(at: t, for: legacy)), 0.00001, file: file, line: line)
        }
    }
}
