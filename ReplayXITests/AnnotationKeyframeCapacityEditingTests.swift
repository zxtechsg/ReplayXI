import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationKeyframeCapacityEditingTests: XCTestCase {
    func testCapacityUsesTheSameStrictToleranceAsPoseReplacement() throws {
        let (_, mark) = try fixture()
        let tolerance = CoachMark.keyframeTimeTolerance
        for (time, accepted) in [(0.0, true), (tolerance.nextDown, true),
                                 (tolerance, false), (tolerance.nextUp, false), (6.35, false)] {
            XCTAssertEqual(mark.canRecordPose(at: time), accepted, "Time \(time)")
            XCTAssertEqual(mark.keyframeCapacityBlockReason(at: time) == nil, accepted)
            XCTAssertEqual(mark.recordingPose(at: time).keyframes?.count, accepted ? 64 : 65,
                           "Admission and recording must agree at the exact tolerance boundary")
        }
        for invalid in [TimeInterval(-1), .nan, .infinity] {
            XCTAssertFalse(mark.canRecordPose(at: invalid))
            XCTAssertNil(mark.keyframeCapacityBlockReason(at: invalid), "Invalid time is not a capacity error")
        }
        var unkeyed = mark
        unkeyed.keyframes = nil
        XCTAssertTrue(unkeyed.canRecordPose(at: 6.35))
        XCTAssertNil(unkeyed.keyframeCapacityBlockReason(at: 6.35))
    }

    func testFullNewTimeRejectsEveryGeometryPathWithoutChangingReplayOrUndo() throws {
        let (store, mark) = try fixture()
        store.seek(to: 6.35)
        store.setPlaying(true)
        let marks = store.marks
        let snapshot = store.makeSnapshot()
        let saved = store.makeSavedReviewState()
        let history = store.annotationUndoTitle
        let reason = try XCTUnwrap(mark.keyframeCapacityBlockReason(at: store.playhead))
        var broadcasts = 0
        store.onBroadcastSnapshot = { _ in broadcasts += 1 }
        let end = PitchPoint(x: mark.end.x + 0.5, z: mark.end.z)
        let attempts: [() -> Bool] = [
            { store.captureCoachMarkKeyframe(id: mark.id) },
            { store.updateCoachMarkGeometry(id: mark.id, start: mark.start, end: end) },
            { store.updateCoachMarkGeometry(id: mark.id, start: mark.start, end: end, broadcast: false) },
            { store.nudgeCoachMarkEndpoint(id: mark.id, endpoint: .end, by: .init(x: 0.5, z: 0)) },
            { store.nudgeCoachMarkElevation(id: mark.id, target: .both, by: 0.25) },
            { store.nudgeCoachMarkCurve(id: mark.id, bendDelta: 0.25, liftDelta: 0) },
            { store.previewCoachMarkCurve(id: mark.id, gestureID: UUID(), curve: .init(bend: 3, lift: 1)) },
            { store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end, gestureID: UUID(),
                                             cumulativeDelta: .init(x: 0.5, z: 0)) != nil },
            { store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: UUID(), point: end) },
        ]
        for attempt in attempts {
            XCTAssertFalse(attempt())
            XCTAssertEqual(store.statusMessage, reason)
            XCTAssertEqual(store.marks, marks)
            XCTAssertEqual(store.makeSnapshot(), snapshot)
            XCTAssertEqual(store.makeSavedReviewState(), saved)
            XCTAssertEqual(store.annotationUndoTitle, history)
            XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertTrue(store.canChangePlaybackView)
        }
        XCTAssertEqual(broadcasts, 0)
        XCTAssertTrue(store.isPlaying)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state, saved)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }?.keyframes?.count, 63,
                       "Rejections must not add phantom history after the last real key")
    }

    func testFullExistingKeyAllowsCurveHeightEndpointAndOwnedDragsWithOneUndoEach() throws {
        let (store, mark) = try fixture()
        for time in [0, CoachMark.keyframeTimeTolerance.nextDown] {
            store.seek(to: time)
            let baseline = store.marks
            let times = mark.keyframes?.map(\.time)
            let controller = AnnotationCurveAdjustmentController()
            XCTAssertTrue(controller.isEnabled(in: store, markID: mark.id))
            XCTAssertTrue(controller.canAdjust(in: store, markID: mark.id, mode: .shape, horizontal: 0.25, vertical: 5))
            XCTAssertTrue(controller.adjust(in: store, markID: mark.id, mode: .shape, horizontal: 0.25, vertical: 5))
            try assertReplacesThenUndo(store, id: mark.id, times: times, baseline: baseline)
            XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .both, by: 0.25))
            try assertReplacesThenUndo(store, id: mark.id, times: times, baseline: baseline)
            XCTAssertTrue(store.nudgeCoachMarkEndpoint(id: mark.id, endpoint: .end, by: .init(x: 0.5, z: 0)))
            try assertReplacesThenUndo(store, id: mark.id, times: times, baseline: baseline)
            let direct = UUID()
            XCTAssertTrue(store.previewCoachMarkHandle(id: mark.id, endpoint: .end, gestureID: direct,
                                                       point: .init(x: -15.5, z: -14)))
            XCTAssertTrue(store.commitCoachMarkHandlePreview(id: mark.id, gestureID: direct,
                                                             point: .init(x: -15, z: -14)))
            try assertReplacesThenUndo(store, id: mark.id, times: times, baseline: baseline)
            let joystick = UUID()
            XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end, gestureID: joystick,
                                                           cumulativeDelta: .init(x: 0.5, z: 0)))
            XCTAssertNotNil(store.commitCoachMarkEndpointPreview(id: mark.id, gestureID: joystick))
            try assertReplacesThenUndo(store, id: mark.id, times: times, baseline: baseline)
        }
    }

    func testFullExactToleranceAndBeyondRejectWhileExistingKeyRemainsUsable() throws {
        let (store, mark) = try fixture()
        let baseline = store.marks
        let controller = AnnotationCurveAdjustmentController()
        for time in [CoachMark.keyframeTimeTolerance, CoachMark.keyframeTimeTolerance.nextUp, 6.35] {
            store.seek(to: time)
            XCTAssertFalse(controller.isEnabled(in: store, markID: mark.id))
            XCTAssertFalse(controller.canAdjust(in: store, markID: mark.id, mode: .shape, horizontal: 0.25, vertical: 5))
            XCTAssertFalse(controller.canNudge(in: store, markID: mark.id, bend: 0.25, lift: 0))
            XCTAssertFalse(controller.adjust(in: store, markID: mark.id, mode: .shape, horizontal: 0.25, vertical: 5))
            XCTAssertFalse(store.captureCoachMarkKeyframe(id: mark.id))
            XCTAssertFalse(store.nudgeCoachMarkElevation(id: mark.id, target: .end, by: 0.25))
            XCTAssertEqual(store.marks, baseline)
        }
        store.seek(to: 0)
        XCTAssertTrue(controller.isEnabled(in: store, markID: mark.id))
        XCTAssertTrue(controller.adjust(in: store, markID: mark.id, mode: .shape, horizontal: 0.25, vertical: 5))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline)
    }

    func testSixtyThirdKeyCanOpenAndFinishAContinuousFinalSlotPreview() throws {
        let (store, mark) = try fixture(keyCount: 63)
        store.seek(to: 6.35)
        let before = store.marks
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: .init(width: 20, height: -20), mode: .shape))
        let owner = controller.transaction
        XCTAssertEqual(store.marks.first { $0.id == mark.id }?.keyframes?.count, 64)
        XCTAssertTrue(controller.isEnabled(in: store, markID: mark.id), "The newly saved preview occupies its own final slot")
        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: .init(width: 28, height: -28), mode: .shape))
        XCTAssertEqual(controller.transaction, owner)
        XCTAssertEqual(store.makeSavedReviewState().marks, before)
        XCTAssertTrue(controller.finish(in: store, markID: mark.id, translation: .init(width: 36, height: -36), mode: .shape))
        let final = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(final.keyframes?.count, 64)
        XCTAssertEqual(final.keyframes?.last?.time, 6.35)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks, store.marks)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before)
    }

    func testDeletingOneKeyRestoresNewPositionEditsWithoutImplicitEviction() throws {
        let (store, mark) = try fixture()
        store.seek(to: 6.35)
        let original = store.marks
        XCTAssertTrue(store.removeCoachMarkKeyframe(id: mark.id, at: 0))
        let afterDelete = store.marks
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.isEnabled(in: store, markID: mark.id))
        XCTAssertTrue(controller.adjust(in: store, markID: mark.id, mode: .offset, horizontal: 0.25, vertical: 0.25))
        let final = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(final.keyframes?.count, 64)
        XCTAssertEqual(final.keyframes?.dropLast().map(\.time), mark.keyframes?.dropFirst().map(\.time))
        XCTAssertEqual(final.keyframes?.last?.time, 6.35)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, afterDelete)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, original)
    }

    func testVisibleTimingArcEndpointAndHeightControlsUseCapacityPolicy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let timing = try source("ReplayXI/Immersive/AnnotationTimingEditor.swift")
        XCTAssertTrue(timing.contains(".disabled(!canEdit || !canLeaveEditor || !mark.canRecordPose(at: store.playhead))"))
        XCTAssertTrue(timing.contains("guard canEdit, canLeaveEditor, let mark, mark.canRecordPose(at: store.playhead)"))
        XCTAssertTrue(timing.contains("mark.keyframeCapacityBlockReason(at: store.playhead)"))
        let deck = try source("ReplayXI/Immersive/FootballImmersiveView.swift")
        XCTAssertEqual(deck.components(separatedBy: "disabledReason: mark.keyframeCapacityBlockReason(at: store.playhead)").count - 1, 2)
        XCTAssertTrue(deck.contains("disabledReason ?? \"Finish the active endpoint adjustment first.\""))
        for start in ["private func canNudgeAnnotationElevation(", "private func annotationJoystickIsEnabled("] {
            let lower = try XCTUnwrap(deck.range(of: start)?.lowerBound)
            let next = try XCTUnwrap(deck.range(of: "\n    private ", range: deck.index(after: lower)..<deck.endIndex)?.lowerBound)
            XCTAssertTrue(deck[lower..<next].contains("mark.canRecordPose(at: store.playhead)"), start)
        }
        let editor = try source("ReplayXI/Immersive/SpatialAnnotationEditor.swift")
        XCTAssertFalse(editor.contains("store.captureCoachMarkKeyframe(id: mark.id)"), "Fine keys are Mac-only")
        let pointEditor = try source("ReplayXI/Immersive/AnnotationArcPointEditor.swift")
        XCTAssertTrue(pointEditor.contains("mark.canRecordPose(at: store.playhead)"))
        let pad = try source("ReplayXI/Immersive/AnnotationCurveAdjustmentPad.swift")
        XCTAssertTrue(pad.contains("Text(capacityBlockReason)"))
        XCTAssertTrue(pad.contains("capacityBlockReason ?? \"Finish or cancel the current gesture first\""))
    }

    private func assertReplacesThenUndo(_ store: ReplayStore, id: UUID, times: [TimeInterval]?,
                                       baseline: [CoachMark], file: StaticString = #filePath, line: UInt = #line) throws {
        let edited = try XCTUnwrap(store.marks.first { $0.id == id }, file: file, line: line)
        XCTAssertEqual(edited.keyframes?.count, 64, file: file, line: line)
        XCTAssertEqual(edited.keyframes?.map(\.time), times, file: file, line: line)
        XCTAssertNotEqual(store.marks, baseline, file: file, line: line)
        XCTAssertTrue(store.undoAnnotationEdit(), file: file, line: line)
        XCTAssertEqual(store.marks, baseline, file: file, line: line)
    }

    private func fixture(keyCount: Int = 64) throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 0)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: -20, z: -20))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
        if created.followsPlayerTracks { XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil)) }
        for index in 0..<keyCount {
            store.seek(to: Double(index) / 10)
            XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        }
        let mark = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertEqual(mark.keyframes?.count, keyCount)
        return (store, mark)
    }
}
