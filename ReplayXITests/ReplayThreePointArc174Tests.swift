import Foundation
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayThreePointArc174Tests: XCTestCase {
    private func mark(start: PitchPoint = .init(x: 0, z: 0), end: PitchPoint = .init(x: 8, z: 6),
                      height: Float = 0, control: SIMD3<Float>) -> CoachMark {
        let base = CoachMark(kind: .arc, start: start, end: end,
            startElevation: height, endElevation: height, label: "Arc", revealTime: 0)
        return CoachMark(id: base.id, kind: .arc, start: start, end: end,
            startElevation: height, endElevation: height,
            curve: base.resolvedCurve.settingControlPoint(control, for: base), label: "Arc", revealTime: 0)
    }

    func testThirdPointControlsEveryAxisAndExactEndpoints() {
        for point: SIMD3<Float> in [[2, 8, 3], [-6, 2, 11], [9, 0, -4]] {
            let value = mark(control: point)
            let curve = value.resolvedCurve
            XCTAssertTrue(curve.isValid)
            XCTAssertEqual(curve.controlPoint(for: value), point)
            XCTAssertEqual(curve.point(at: 0, for: value), SIMD3<Float>(0, 0, 0))
            XCTAssertEqual(curve.point(at: 1, for: value), SIMD3<Float>(8, 0, 6))
            XCTAssertEqual(curve.point(at: 0.5, for: value), SIMD3<Float>(2, 0, 1.5) + point * 0.5)
        }
    }

    func testControlPointRoundTripAndLegacyPayloadCompatibility() throws {
        let legacy = CoachMarkCurve(bend: 2, lift: 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(object["controlOffset"])
        XCTAssertEqual(try JSONDecoder().decode(CoachMarkCurve.self,
            from: Data("{\"bend\":2,\"lift\":1}".utf8)), legacy)
        let value = mark(control: [3, 7, -2])
        XCTAssertEqual(try JSONDecoder().decode(CoachMark.self, from: JSONEncoder().encode(value)), value)
        for invalid: SIMD3<Float> in [[.nan, 0, 0], [69, 0, 0], [0, 13, 0], [0, 0, 106]] {
            let curve = CoachMarkCurve(bend: 0, lift: 0, controlOffset: invalid)
            XCTAssertFalse(curve.isValid)
            XCTAssertFalse(curve.clamped().isValid)
        }
    }

    func testControlPositionInterpolatesAtTimestampsAndReverseSeeks() {
        let a = mark(control: [1, 6, -2])
        var b = mark(start: .init(x: 4, z: 2), end: .init(x: 12, z: 8), height: 2, control: [7, 10, 4])
        b.keyframes = [CoachMarkKeyframe(time: 0, mark: a), CoachMarkKeyframe(time: 10, mark: b)]
        XCTAssertTrue(b.hasValidKeyframes(duration: 10))
        for time in [0.0, 1, 5, 9, 10, 5, 0] {
            let pose = b.sampled(at: time)
            let expected = SIMD3<Float>(1, 6, -2) + SIMD3<Float>(6, 4, 6) * Float(time / 10)
            XCTAssertLessThan(simd_distance(pose.resolvedCurve.controlPoint(for: pose), expected), 0.00001)
        }
    }

    func testDesktopPoseEditHasOneUndoAndRejectsBadPointsAndTimingDraft() throws {
        let store = ReplayStore()
        store.seek(to: 3, broadcast: false)
        let value = try XCTUnwrap(store.addMacCoachMark(kind: .arc, start: .zero,
            end: .init(x: 8, z: 6), startElevation: 0, endElevation: 0, label: "Pass"))
        let before = store.marks
        XCTAssertTrue(store.setMacCoachMarkPose(id: value.id, start: .init(x: 1, z: 2),
            end: .init(x: 9, z: 8), startElevation: 1, endElevation: 2, controlPoint: [4, 8, -2]))
        XCTAssertEqual(store.marks.last?.resolvedStartElevation, 1)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before)
        XCTAssertFalse(store.updateCoachMarkArcControlPoint(id: value.id, point: [0, 13, 0]))
        XCTAssertEqual(store.marks, before)
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: value.id, isPending: true))
        XCTAssertFalse(store.updateCoachMarkArcControlPoint(id: value.id, point: [0, 2, 0]))
        XCTAssertNil(store.addMacCoachMark(kind: .run, start: .zero, end: .init(x: 5, z: 0),
            startElevation: 0, endElevation: 0, label: "Run"))
        XCTAssertEqual(store.marks, before)
    }
}
