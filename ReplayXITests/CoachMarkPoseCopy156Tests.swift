import Foundation
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkPoseCopy156Tests: XCTestCase {
    func testFiveSpatialKindsCopyOneFixedPoseAndUndoRedoAsOneAction() throws {
        for kind in [CoachMarkKind.run, .pass, .arc, .space, .danger] {
            let store = ReplayStore()
            let source = CoachMark(kind: kind, start: .init(x: -4, z: -6), end: .init(x: 3, z: 5),
                startElevation: 1, endElevation: kind == .space ? 1 : 2,
                curve: kind == .arc ? .init(bend: 2, lift: 0.25, rollDegrees: 35) : nil,
                label: "Original \(kind.rawValue)", revealTime: 1, hideTime: 2, author: "Reference")
            XCTAssertTrue(store.appendRemoteCoachMark(source))
            store.seek(to: 5, broadcast: false)
            store.setPlaying(true, broadcast: false)
            let originals = store.marks
            var snapshots: [SharedPlaybackSnapshot] = []
            store.onBroadcastSnapshot = { snapshots.append($0) }
            XCTAssertFalse(source.isVisible(at: store.playhead), "Copy samples the explicit pose here, not In")
            XCTAssertTrue(store.canCopyCoachMarkPose(id: source.id))

            let copy = try XCTUnwrap(store.copyCoachMarkPose(id: source.id))

            XCTAssertNotEqual(copy.id, source.id)
            XCTAssertEqual(copy.kind, source.kind)
            XCTAssertEqual(copy.label, source.label)
            XCTAssertEqual(copy.author, "Coach")
            XCTAssertEqual(copy.start, source.start)
            XCTAssertEqual(copy.end, source.end)
            XCTAssertEqual(copy.startElevation, source.startElevation)
            XCTAssertEqual(copy.endElevation, source.endElevation)
            XCTAssertEqual(copy.revealTime, 5)
            XCTAssertNil(copy.hideTime)
            assertFixed(copy)
            XCTAssertEqual(store.marks, originals + [copy])
            XCTAssertFalse(store.isPlaying)
            XCTAssertEqual(snapshots.count, 1)
            XCTAssertEqual(snapshots.first?.marks, originals + [copy])
            XCTAssertEqual(snapshots.first?.isPlaying, false)
            XCTAssertEqual(store.annotationUndoTitle, "Undo add")
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertEqual(store.marks, originals)
            XCTAssertFalse(store.canUndoAnnotationEdit)
            XCTAssertTrue(store.redoAnnotationEdit())
            XCTAssertEqual(store.marks, originals + [copy])
        }
    }

    func testAuthoredOverlayCanBeCopiedBeforeItsWindowWithoutChangingTheFixture() throws {
        let store = ReplayStore()
        let source = try XCTUnwrap(store.selectedScenario.coachMarks.first { $0.revealTime > 0 })
        let originals = store.marks, fixtureMarks = store.selectedScenario.coachMarks
        XCTAssertFalse(source.isVisible(at: store.playhead))
        XCTAssertFalse(store.removeCoachMark(id: source.id))
        XCTAssertTrue(store.canCopyCoachMarkPose(id: source.id))
        let copy = try XCTUnwrap(store.copyCoachMarkPose(id: source.id))
        XCTAssertEqual(copy.revealTime, 0)
        XCTAssertEqual(copy.label, source.label)
        XCTAssertEqual(store.marks.first { $0.id == source.id }, source)
        XCTAssertEqual(store.selectedScenario.coachMarks, fixtureMarks)
        XCTAssertFalse(fixtureMarks.contains { $0.id == copy.id })
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, originals)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertTrue(store.removeCoachMark(id: copy.id), "Only the copy becomes editable")
        XCTAssertEqual(store.marks, originals)
    }

    func testTrackedImplicitArcFreezesPresentedPositionsAndVisibleDefaultBend() throws {
        let store = ReplayStore()
        let source = CoachMark(kind: .arc, start: .init(x: 20, z: 20), end: .init(x: 21, z: 20),
            startElevation: 0.5, endElevation: 1.5, label: "Player-linked legacy arc",
            startTrackAnchor: .init(playerID: "navy-rw"), endTrackAnchor: .init(playerID: "navy-rb"))
        XCTAssertTrue(store.appendRemoteCoachMark(source))
        store.seek(to: 8, broadcast: false)
        let shown = store.presentedCoachMarkGeometry(source, at: store.playhead)
        let shownCurve = CoachMarkCurve.initial(start: shown.start, end: shown.end)
        XCTAssertNotEqual(shown.start, source.start)
        XCTAssertGreaterThan(abs(shownCurve.bend - source.resolvedCurve.bend), 0.1)
        let copy = try XCTUnwrap(store.copyCoachMarkPose(id: source.id))
        XCTAssertEqual(copy.start, shown.start)
        XCTAssertEqual(copy.end, shown.end)
        XCTAssertEqual(copy.curve, shownCurve.stabilized(start: shown.start, end: shown.end))
        assertFixed(copy)
        let presentation = CoachMark(kind: .arc, start: shown.start, end: shown.end,
            startElevation: 0.5, endElevation: 1.5, label: source.label)
        assertSameCentreline(copy, presentation)
        store.seek(to: 14, broadcast: false)
        XCTAssertNotEqual(store.presentedCoachMarkGeometry(source, at: store.playhead), shown)
        XCTAssertEqual(try current(copy.id, in: store), copy)
        XCTAssertEqual(try current(source.id, in: store), source)
        XCTAssertNil(try current(source.id, in: store).curve)
    }

    func testKeyedArcCopiesInterpolatedElevationsAndCurveButNoPositionKeys() throws {
        let store = ReplayStore()
        let first = CoachMark(kind: .arc, start: .init(x: -4, z: -6), end: .init(x: 3, z: 5),
            startElevation: 0, endElevation: 1,
            curve: .init(bend: 1, lift: 0.25, rollDegrees: 20, bendBearingDegrees: 120),
            label: "Animated arc", revealTime: 1, hideTime: 7)
        let last = CoachMark(kind: .arc, start: .init(x: 0, z: -2), end: .init(x: 7, z: 9),
            startElevation: 2, endElevation: 3,
            curve: .init(bend: 3, lift: 1.25, rollDegrees: 60, bendBearingDegrees: 140), label: first.label)
        var source = first
        source.keyframes = [CoachMarkKeyframe(time: 2, mark: first), CoachMarkKeyframe(time: 6, mark: last)]
        XCTAssertTrue(store.appendRemoteCoachMark(source))
        store.seek(to: 4, broadcast: false)
        let sampled = source.sampled(at: 4)
        XCTAssertEqual(sampled.start, .init(x: -2, z: -4))
        XCTAssertEqual(sampled.resolvedStartElevation, 1)
        XCTAssertEqual(sampled.resolvedEndElevation, 2)
        let copy = try XCTUnwrap(store.copyCoachMarkPose(id: source.id))
        XCTAssertEqual(copy.start, sampled.start)
        XCTAssertEqual(copy.end, sampled.end)
        XCTAssertEqual(copy.startElevation, sampled.startElevation)
        XCTAssertEqual(copy.endElevation, sampled.endElevation)
        XCTAssertEqual(copy.curve, sampled.curve)
        assertFixed(copy)
        assertSameCentreline(copy, sampled)
        XCTAssertEqual(try current(source.id, in: store), source)
        for time in [0.0, 6, 4] {
            store.seek(to: time, broadcast: false)
            XCTAssertEqual(copy.sampled(at: time), copy)
            XCTAssertEqual(try current(copy.id, in: store), copy)
        }
    }

    func testRaisedVerticalLegacyArcBecomesFramedWithoutInventingABend() throws {
        let store = ReplayStore()
        let source = CoachMark(kind: .arc, start: .init(x: 10, z: 12), end: .init(x: 10, z: 12),
            startElevation: 1, endElevation: 3, curve: .init(bend: 3, lift: 0, rollDegrees: 40),
            label: "Vertical legacy")
        XCTAssertTrue(store.appendRemoteCoachMark(source))
        let copy = try XCTUnwrap(store.copyCoachMarkPose(id: source.id))
        XCTAssertEqual(copy.curve?.bendBearingDegrees, 90)
        XCTAssertEqual(copy.curve?.bend, 0)
        assertSameCentreline(copy, source)
        XCTAssertEqual(try current(source.id, in: store), source)
    }

    func testLastFrameCopyUsesToEndAndRepeatedCopiesHaveDistinctIDs() throws {
        let store = ReplayStore()
        let source = try XCTUnwrap(store.marks.first { $0.kind.requiresTwoPitchPoints })
        store.seek(to: store.selectedScenario.duration, broadcast: false)
        let first = try XCTUnwrap(store.copyCoachMarkPose(id: source.id))
        let second = try XCTUnwrap(store.copyCoachMarkPose(id: source.id))
        XCTAssertNotEqual(first.id, second.id)
        for copy in [first, second] {
            XCTAssertEqual(copy.revealTime, store.selectedScenario.duration)
            XCTAssertNil(copy.hideTime)
            XCTAssertTrue(copy.isVisible(at: store.playhead))
            assertFixed(copy)
        }
        XCTAssertEqual(try current(source.id, in: store), source)
    }

    func testCapabilityIsReadOnlyAndMissingLabelPlayerRoleAndCapacityAreRejected() throws {
        let store = ReplayStore()
        let source = try XCTUnwrap(store.marks.first { $0.kind.requiresTwoPitchPoints })
        store.setPlaying(true, broadcast: false)
        store.statusMessage = "Keep this message"
        let initial = store.makeSavedReviewState(), undo = store.annotationUndoTitle
        for _ in 0..<20 { XCTAssertTrue(store.canCopyCoachMarkPose(id: source.id)) }
        XCTAssertEqual(store.makeSavedReviewState(), initial)
        XCTAssertEqual(store.statusMessage, "Keep this message")
        XCTAssertEqual(store.annotationUndoTitle, undo)
        XCTAssertTrue(store.isPlaying)
        XCTAssertFalse(store.canCopyCoachMarkPose(id: UUID()))
        XCTAssertNil(store.copyCoachMarkPose(id: UUID()))
        store.localRole = .player
        XCTAssertFalse(store.canCopyCoachMarkPose(id: source.id))
        XCTAssertNil(store.copyCoachMarkPose(id: source.id))
        store.localRole = .coach
        XCTAssertEqual(store.makeSavedReviewState(), initial)
        XCTAssertEqual(store.annotationUndoTitle, undo)
        XCTAssertTrue(store.isPlaying)

        let player = try XCTUnwrap(store.selectedScenario.players.first)
        let label = CoachMark(kind: .playerLabel, start: .zero, end: .zero, label: "Player",
                              playerID: player.id)
        XCTAssertTrue(store.appendRemoteCoachMark(label))
        let beforeLabel = store.makeSavedReviewState()
        XCTAssertFalse(store.canCopyCoachMarkPose(id: label.id))
        XCTAssertNil(store.copyCoachMarkPose(id: label.id))
        XCTAssertEqual(store.makeSavedReviewState(), beforeLabel)
        XCTAssertTrue(store.isPlaying)

        for _ in store.marks.count..<ReplayStore.maximumSharedCoachMarks {
            let filler = CoachMark(kind: .run, start: .zero, end: .init(x: 2, z: 3), label: "Capacity")
            XCTAssertTrue(store.appendRemoteCoachMark(filler))
        }
        XCTAssertEqual(store.marks.count, ReplayStore.maximumSharedCoachMarks)
        let full = store.makeSavedReviewState(), fullUndo = store.annotationUndoTitle
        XCTAssertFalse(store.canCopyCoachMarkPose(id: source.id))
        XCTAssertNil(store.copyCoachMarkPose(id: source.id))
        XCTAssertEqual(store.makeSavedReviewState(), full)
        XCTAssertEqual(store.annotationUndoTitle, fullUndo)
        XCTAssertTrue(store.isPlaying)
    }

    func testUnreadableLegacyPoseDoesNotCopyPauseOrCreateHistory() throws {
        for kind in [CoachMarkKind.run, .pass, .arc, .space, .danger] {
            let store = ReplayStore()
            let source = CoachMark(kind: kind, start: .zero, end: .init(x: 0.1, z: 0),
                curve: kind == .arc ? .init(bend: 1, lift: 0) : nil, label: "Short legacy pose")
            XCTAssertTrue(store.appendRemoteCoachMark(source), "Existing legacy data remains readable")
            store.setPlaying(true, broadcast: false)
            let saved = store.makeSavedReviewState(), undo = store.annotationUndoTitle
            var broadcasts = 0
            store.onBroadcastSnapshot = { _ in broadcasts += 1 }
            XCTAssertTrue(store.canCopyCoachMarkPose(id: source.id), "Capability is not a per-frame geometry validator")
            XCTAssertNil(store.copyCoachMarkPose(id: source.id))
            XCTAssertEqual(store.makeSavedReviewState(), saved)
            XCTAssertEqual(store.annotationUndoTitle, undo)
            XCTAssertTrue(store.isPlaying)
            XCTAssertEqual(broadcasts, 0)
        }
    }

    private func current(_ id: UUID, in store: ReplayStore) throws -> CoachMark {
        try XCTUnwrap(store.marks.first { $0.id == id })
    }

    private func assertFixed(_ mark: CoachMark, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(mark.playerID, file: file, line: line)
        XCTAssertNil(mark.startTrackAnchor, file: file, line: line)
        XCTAssertNil(mark.endTrackAnchor, file: file, line: line)
        XCTAssertNil(mark.keyframes, file: file, line: line)
        XCTAssertFalse(mark.hasAnimatedGeometry, file: file, line: line)
    }

    private func assertSameCentreline(_ copy: CoachMark, _ source: CoachMark,
                                      file: StaticString = #filePath, line: UInt = #line) {
        for index in 0...32 {
            let fraction = Float(index) / 32
            XCTAssertLessThan(simd_distance(copy.resolvedCurve.point(at: fraction, for: copy),
                source.resolvedCurve.point(at: fraction, for: source)), 0.00001, file: file, line: line)
        }
    }
}
