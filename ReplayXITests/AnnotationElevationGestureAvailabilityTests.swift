import XCTest
@testable import ReplayXI

/// Private SwiftUI availability is source-checked; the controls below execute
/// real Store transactions. This is not an interactive button/VoiceOver test.
@MainActor
final class AnnotationElevationGestureAvailabilityTests: XCTestCase {
    func testHeightButtonEligibilityChecksGestureOwnershipBeforeHeightBounds() throws {
        let source = try immersiveSource()
        let policy = try slice(source, after: "private func canNudgeAnnotationElevation(",
            before: "private func annotationElevationTargetName(")
        let admission = policy.range(of: "guard store.canChangePlaybackView else { return false }")?.lowerBound
        let bounds = try XCTUnwrap(policy.range(of: "let elevations: [Float]")?.lowerBound)
        XCTAssertNotNil(admission, "Height buttons must reflect the existing gesture owner")
        if let admission { XCTAssertLessThan(admission, bounds) }
        let button = try slice(source, after: "private func annotationElevationButton(",
            before: "private func canNudgeAnnotationElevation(")
        XCTAssertTrue(button.contains(
            ".disabled(!canNudgeAnnotationElevation(mark, target: target, delta: delta))"))
        XCTAssertTrue(policy.contains("return elevations.contains { $0 < CoachMarkGeometryPolicy.maximumElevation }"))
        XCTAssertTrue(policy.contains("return elevations.contains { $0 > 0 }"))
    }

    func testHeightButtonHintExplainsTheGestureBarrier() throws {
        let source = try immersiveSource()
        let button = try slice(source, after: "private func annotationElevationButton(",
            before: "private func canNudgeAnnotationElevation(")
        XCTAssertTrue(button.contains(".accessibilityHint(store.canChangePlaybackView"))
        XCTAssertTrue(button.contains("Finish or cancel the current gesture first"))
        XCTAssertTrue(button.contains("Moves vertically by 0.25 metres"))
        let action = try slice(source, after: "private func nudgeAnnotationElevation(",
            before: "private func previewAnnotation(")
        let resultGate = try XCTUnwrap(action.range(of: "guard store.nudgeCoachMarkElevation(")?.lowerBound)
        let feedback = try XCTUnwrap(action.range(of: "annotationConfirmation =")?.lowerBound)
        XCTAssertLessThan(resultGate, feedback, "A late callback still uses the Store's result")
    }

    func testTimelineOwnershipRejectsHeightEditsAndPreservesCommitAndCancel() throws {
        for shouldCommit in [false, true] {
            let (store, mark) = try makeRaisedMark()
            let baseline = store.marks
            store.setPlaying(true, broadcast: false)
            XCTAssertTrue(store.beginTimelineScrub())
            XCTAssertTrue(store.previewTimelineScrub(to: 12))
            XCTAssertFalse(store.canChangePlaybackView)

            assertHeightStepsAreRejected(in: store, id: mark.id)

            XCTAssertTrue(store.hasActiveTimelineScrub)
            XCTAssertEqual(store.playhead, 12)
            XCTAssertEqual(store.marks, baseline)
            if shouldCommit {
                XCTAssertTrue(store.commitTimelineScrub(to: 14))
                XCTAssertEqual(store.playhead, 14)
            } else {
                store.cancelTimelineScrub()
                XCTAssertEqual(store.playhead, 5)
            }
            XCTAssertTrue(store.isPlaying)
            XCTAssertTrue(store.canChangePlaybackView)
            XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .end, by: 0.25))
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, baseline)
        }
    }

    func testDirectHandleOwnershipRejectsHeightEditsAndPreservesCommitAndCancel() throws {
        for shouldCommit in [false, true] {
            let (store, mark) = try makeRaisedMark()
            let baseline = store.marks
            let previewEnd = PitchPoint(x: mark.end.x + 0.5, z: mark.end.z)
            XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id,
                start: mark.start, end: previewEnd, broadcast: false))
            XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)
            XCTAssertFalse(store.canChangePlaybackView)

            assertHeightStepsAreRejected(in: store, id: mark.id)

            XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
            if shouldCommit {
                XCTAssertTrue(store.commitCoachMarkGeometryPreview(id: mark.id,
                    start: mark.start, end: previewEnd))
                XCTAssertEqual(try currentMark(mark.id, in: store).end, previewEnd)
            } else {
                XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
                XCTAssertEqual(store.marks, baseline)
            }
            XCTAssertTrue(store.canChangePlaybackView)
            let settled = store.marks
            XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .start, by: -0.25))
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, settled)
        }
    }

    func testJoystickOwnershipRejectsHeightEditsAndPreservesCommitAndCancel() throws {
        for shouldCommit in [false, true] {
            let (store, mark) = try makeRaisedMark()
            let baseline = store.marks
            let gesture = UUID()
            let movement = PitchPoint(x: 0.5, z: -0.25)
            XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                gestureID: gesture, cumulativeDelta: movement))
            let owner = CoachMarkEndpointPreviewOwner(markID: mark.id, endpoint: .end)
            XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner, owner)
            XCTAssertFalse(store.canChangePlaybackView)

            assertHeightStepsAreRejected(in: store, id: mark.id)

            XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner, owner)
            XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
            if shouldCommit {
                XCTAssertEqual(store.commitCoachMarkEndpointPreview(id: mark.id, gestureID: gesture), movement)
            } else {
                XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: gesture))
                XCTAssertEqual(store.marks, baseline)
            }
            XCTAssertTrue(store.canChangePlaybackView)
            let settled = store.marks
            XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .both, by: 0.25))
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, settled)
        }
    }

    func testOrdinaryQuarterMetreHeightStepsCommitOnceAndUndoExactly() throws {
        for target in [CoachMarkElevationTarget.start, .end, .both] {
            for delta: Float in [-0.25, 0.25] {
                let (store, mark) = try makeRaisedMark()
                let baseline = store.marks
                store.setPlaying(true, broadcast: false)
                var broadcasts = 0
                store.onBroadcastSnapshot = { _ in broadcasts += 1 }

                XCTAssertTrue(store.canChangePlaybackView)
                XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: target, by: delta))

                let raised = try currentMark(mark.id, in: store)
                XCTAssertEqual(raised.resolvedStartElevation, target == .end ? 1 : 1 + delta)
                XCTAssertEqual(raised.resolvedEndElevation, target == .start ? 1 : 1 + delta)
                XCTAssertFalse(store.isPlaying)
                XCTAssertEqual(broadcasts, 1)
                XCTAssertTrue(store.undoAnnotationEdit())
                XCTAssertEqual(store.marks, baseline)
            }
        }
    }

    func testWholeArrowStillMovesTheUncappedEndpointWithoutChangingClampSemantics() throws {
        for raising in [false, true] {
            let (store, mark) = try makeRaisedMark()
            let initialStep: Float = raising ? 3 : -1
            XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .start, by: initialStep))
            XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .end,
                by: raising ? 2.75 : -0.75))
            let baseline = store.marks
            let limit: Float = raising ? CoachMarkGeometryPolicy.maximumElevation : 0
            var broadcasts = 0
            store.onBroadcastSnapshot = { _ in broadcasts += 1 }

            XCTAssertTrue(store.nudgeCoachMarkElevation(id: mark.id, target: .both,
                by: raising ? 0.25 : -0.25))

            let clamped = try currentMark(mark.id, in: store)
            XCTAssertEqual(clamped.resolvedStartElevation, limit)
            XCTAssertEqual(clamped.resolvedEndElevation, limit)
            XCTAssertEqual(broadcasts, 1)
            XCTAssertFalse(store.nudgeCoachMarkElevation(id: mark.id, target: .both,
                by: raising ? 0.25 : -0.25))
            XCTAssertEqual(broadcasts, 1)
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, baseline)
        }
    }

    private func assertHeightStepsAreRejected(in store: ReplayStore, id: UUID,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let marks = store.marks
        let snapshot = store.makeSnapshot()
        let undoTitle = store.annotationUndoTitle
        let redoTitle = store.annotationRedoTitle
        var broadcasts = 0
        store.onBroadcastSnapshot = { _ in broadcasts += 1 }
        for target in [CoachMarkElevationTarget.start, .end, .both] {
            for delta: Float in [-0.25, 0.25] {
                XCTAssertFalse(store.nudgeCoachMarkElevation(id: id, target: target, by: delta),
                    file: file, line: line)
            }
        }
        XCTAssertEqual(store.marks, marks, file: file, line: line)
        XCTAssertEqual(store.makeSnapshot(), snapshot, file: file, line: line)
        XCTAssertEqual(store.annotationUndoTitle, undoTitle, file: file, line: line)
        XCTAssertEqual(store.annotationRedoTitle, redoTitle, file: file, line: line)
        XCTAssertEqual(broadcasts, 0, file: file, line: line)
        store.onBroadcastSnapshot = nil
    }

    private func makeRaisedMark() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        XCTAssertFalse(store.reviewLibrary.usesDisk)
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let created = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 12)))
        if created.followsPlayerTracks {
            XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil))
        }
        XCTAssertTrue(store.nudgeCoachMarkElevation(id: created.id, target: .both, by: 1))
        return (store, try currentMark(created.id, in: store))
    }

    private func currentMark(_ id: UUID, in store: ReplayStore) throws -> CoachMark {
        try XCTUnwrap(store.marks.first { $0.id == id })
    }

    private func immersiveSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
