import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationCurvePitchLimit151Tests: XCTestCase {
    func testReboundTrackedArcShowsLimitAfterSeekAndClearsOnExactRewind() throws {
        let store = makeReboundStore()
        let mark = try drawTrackedArc(in: store, at: 0,
            start: .init(x: -30, z: 0), end: .init(x: -30, z: 4))
        let savedMarks = store.marks
        XCTAssertEqual(mark.resolvedCurve.bend, 0.72, accuracy: 0.000001)
        XCTAssertFalse(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: mark, in: store))

        store.seek(to: 7, broadcast: false)
        let geometry = store.presentedCoachMarkGeometry(mark, at: store.playhead)
        XCTAssertEqual(geometry.start, .init(x: -33, z: 15.5))
        XCTAssertEqual(geometry.end, .init(x: -33, z: 19.5))
        XCTAssertFalse(mark.resolvedCurve.isLimitedByPitch(for: mark.sampled(at: store.playhead)),
                       "The old warning misses clipping by using the original endpoints")
        XCTAssertTrue(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: mark, in: store))
        let presented = mark.resolvingTrackGeometry(in: store.selectedScenario, at: store.playhead)
        XCTAssertEqual(presented.resolvedCurve.controlPoint(for: presented).x, -34)

        store.seek(to: 0, broadcast: false)
        XCTAssertFalse(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: mark, in: store))
        XCTAssertEqual(store.presentedCoachMarkGeometry(mark, at: store.playhead),
                       .init(start: mark.start, end: mark.end))
        XCTAssertEqual(store.marks, savedMarks, "Warning/seek must not rewrite anchors, curve or timing")
    }

    func testReboundTrackedArcDoesNotKeepAnOldLimitAfterMovingAwayFromTouchline() throws {
        let store = makeReboundStore()
        let mark = try drawTrackedArc(in: store, at: 7,
            start: .init(x: -33, z: 15.5), end: .init(x: -33, z: 19.5))
        let savedMarks = store.marks
        XCTAssertTrue(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: mark, in: store))

        store.seek(to: 0, broadcast: false)
        let geometry = store.presentedCoachMarkGeometry(mark, at: store.playhead)
        XCTAssertEqual(geometry.start, .init(x: -30, z: 0))
        XCTAssertEqual(geometry.end, .init(x: -30, z: 4))
        XCTAssertTrue(mark.resolvedCurve.isLimitedByPitch(for: mark.sampled(at: store.playhead)),
                      "The old warning stays visible despite the current unclipped arc")
        XCTAssertFalse(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: mark, in: store))

        store.seek(to: 7, broadcast: false)
        XCTAssertTrue(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: mark, in: store))
        XCTAssertEqual(store.marks, savedMarks)
    }

    func testWarningUsesPresentedIdealStationsNotRawPlayerTelemetry() {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "triangle-lock", broadcast: false)
        store.setShapeFocusStage(.ideal, broadcast: false)
        store.seek(to: 0, broadcast: false)
        let mark = CoachMark(kind: .arc, start: .init(x: 30.5, z: 0), end: .init(x: 30.5, z: -4),
            curve: .init(bend: 0.72, lift: 0), label: "Station-bound arc",
            startTrackAnchor: .init(playerID: "navy-rcm", offset: .init(x: 19.5, z: -7)),
            endTrackAnchor: .init(playerID: "navy-rcm", offset: .init(x: 19.5, z: -11)))
        let raw = mark.resolvingTrackGeometry(in: store.selectedScenario, at: store.playhead)
        XCTAssertFalse(raw.resolvedCurve.isLimitedByPitch(for: raw))
        XCTAssertEqual(store.presentedCoachMarkGeometry(mark, at: store.playhead).start,
                       .init(x: 33.5, z: 11))
        XCTAssertTrue(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: mark, in: store))

        store.setViewMode(.tacticalTable, broadcast: false)
        XCTAssertFalse(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: mark, in: store))
        store.setViewMode(.positional, broadcast: false)
        XCTAssertTrue(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: mark, in: store))
    }

    func testFixedAndKeyedArcsStillUseSampledElevationAndCurve() {
        let store = makeReboundStore()
        let flat = CoachMark(kind: .arc, start: .init(x: -20, z: -20), end: .init(x: -16, z: -14),
                             curve: .init(bend: 1, lift: 0), label: "Fixed arc")
        let first = flat.recordingPose(at: 0)
        let downward = CoachMark(id: flat.id, kind: .arc, start: flat.start, end: flat.end,
            curve: .init(bend: 1, lift: 0, rollDegrees: -45), label: flat.label,
            keyframes: first.keyframes).recordingPose(at: 7)
        for time: Double in [0, 7, 0] {
            store.seek(to: time, broadcast: false)
            XCTAssertFalse(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: flat, in: store))
            XCTAssertEqual(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: downward, in: store), time == 7)
        }
        let raised = CoachMark(kind: .arc, start: flat.start, end: flat.end,
            startElevation: 2, endElevation: 2,
            curve: .init(bend: 1, lift: 0, rollDegrees: -45), label: "Raised arc")
        XCTAssertFalse(AnnotationCurveAdjustmentPad.isLimitedByPitch(for: raised, in: store))
    }

    private func makeReboundStore() -> ReplayStore {
        let store = ReplayStore(scenarios: FootballReferenceScenarios.all)
        store.prepareForLocalExperience()
        store.selectScenario(id: "final-108-rebound-v2", broadcast: false)
        store.setViewMode(.tacticalTable, broadcast: false)
        store.seek(to: 0, broadcast: false)
        return store
    }

    private func drawTrackedArc(in store: ReplayStore, at time: Double,
                                start: PitchPoint, end: PitchPoint) throws -> CoachMark {
        store.seek(to: time, broadcast: false)
        store.beginDrawing(.arc)
        XCTAssertNil(store.registerPitchTap(start))
        let created = try XCTUnwrap(store.registerPitchTap(end))
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: "arg-24"))
        let tracked = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertEqual(tracked.anchoredPlayerIDs, Set(["arg-24"]))
        return tracked
    }
}
