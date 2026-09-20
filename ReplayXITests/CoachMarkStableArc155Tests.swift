import Foundation
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkStableArc155Tests: XCTestCase {
    func testNilBearingKeepsExactLegacyControlAndSamples() {
        for horizontal: Float in [-2, -0.001, -0.00001, 0, 0.00001, 0.001, 2] {
            for depth: Float in [0, 0.00002, 3] {
                for roll: Float in [-180, -90, -37, 0, 37, 90, 180] {
                    for origin in [PitchPoint.zero, .init(x: 33.5, z: 51)] {
                        let curve = CoachMarkCurve(bend: 3, lift: 0.4, rollDegrees: roll)
                        let mark = mark(start: origin,
                            end: .init(x: origin.x + horizontal, z: origin.z + depth),
                            startElevation: 1, endElevation: 3, curve: curve)
                        let control = legacyControl(for: mark)
                        XCTAssertEqual(curve.controlPoint(for: mark), control)
                        for index in 0...16 {
                            let t = Float(index) / 16
                            let start = SIMD3<Float>(mark.start.x, 1, mark.start.z)
                            let end = SIMD3<Float>(mark.end.x, 3, mark.end.z)
                            let point = (1 - t) * (1 - t) * start
                                + 2 * (1 - t) * t * control + t * t * end
                            let expected = SIMD3<Float>(min(max(point.x, -34), 34), point.y,
                                                        min(max(point.z, -52.5), 52.5))
                            XCTAssertEqual(curve.point(at: t, for: mark), expected)
                        }
                    }
                }
            }
        }
        XCTAssertNil(CoachMarkCurve.initial(start: .zero, end: .init(x: 2, z: 3)).bendBearingDegrees)
    }

    func testStabilizationPreservesLegacyShapeIncludingTinyAndVerticalChords() throws {
        let endpoints: [PitchPoint] = [
            .zero, .init(x: 0.00001, z: 0), .init(x: -0.00001, z: 0.00002),
            .init(x: 2, z: 0), .init(x: -2, z: 0), .init(x: 0, z: 2),
            .init(x: 0, z: -2), .init(x: 2, z: 3)
        ]
        for end in endpoints {
            for roll: Float in [-180, -90, -37, 0, 37, 90, 180] {
                let legacy = CoachMarkCurve(bend: -3, lift: 0.7, rollDegrees: roll)
                let stable = legacy.stabilized(start: .zero, end: end)
                let bearing = try XCTUnwrap(stable.bendBearingDegrees)
                XCTAssertTrue(stable.isValid)
                XCTAssertTrue((-180...180).contains(bearing))
                XCTAssertEqual(stable.lift, legacy.lift)
                XCTAssertEqual(stable.rollDegrees, legacy.rollDegrees)
                XCTAssertEqual(stable.stabilized(start: .init(x: 7, z: 4), end: .zero), stable)
                let oldMark = mark(end: end, startElevation: 1, endElevation: 3, curve: legacy)
                let newMark = mark(end: end, startElevation: 1, endElevation: 3, curve: stable)
                XCTAssertLessThan(simd_distance(legacy.controlPoint(for: oldMark),
                                                stable.controlPoint(for: newMark)), 0.00002)
            }
        }
        let tiny = CoachMarkCurve(bend: 3, lift: 0).stabilized(start: .zero, end: .init(x: 0.00001, z: 0))
        XCTAssertEqual(tiny.bend, 0.3, accuracy: 0.000001)
        let vertical = CoachMarkCurve(bend: 3, lift: 0).stabilized(start: .zero, end: .zero)
        XCTAssertEqual(vertical.bend, 0)
        XCTAssertEqual(vertical.bendBearingDegrees, 90)
    }

    func testDenseFixedBearingPoleCrossingAndVerticalRollStayContinuous() {
        let stable = CoachMarkCurve(bend: 1, lift: 0)
            .stabilized(start: .zero, end: .init(x: -0.001, z: 0))
        for roll: Float in [-180, -90, 0, 90, 180] {
            var curve = stable
            curve.rollDegrees = roll
            var previous: SIMD3<Float>?
            for index in 0...2_000 {
                let x = Float(index - 1_000) / 1_000_000
                let posed = mark(end: .init(x: x, z: 0), endElevation: 2, curve: curve)
                let point = curve.point(at: 0.5, for: posed)
                XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite)
                if let previous { XCTAssertLessThan(simd_distance(point, previous), 0.00001) }
                if roll == 0 { XCTAssertEqual(point.z, -1, accuracy: 0.000001) }
                previous = point
            }
        }
        let verticalCurve = CoachMarkCurve(bend: 1, lift: 0, rollDegrees: 90, bendBearingDegrees: 90)
        let vertical = mark(end: .zero, endElevation: 2, curve: verticalCurve)
        let midpoint = verticalCurve.point(at: 0.5, for: vertical)
        XCTAssertEqual(midpoint.x, -1, accuracy: 0.000001)
        XCTAssertEqual(midpoint.y, 1, accuracy: 0.000001)
        XCTAssertEqual(midpoint.z, 0, accuracy: 0.000001)
        XCTAssertEqual(verticalCurve.point(at: 0, for: vertical), .zero)
        XCTAssertEqual(verticalCurve.point(at: 1, for: vertical), SIMD3<Float>(0, 2, 0))
    }

    func testBearingCodableAndScalarAdjustmentsKeepOptInMetadata() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let legacy = CoachMarkCurve(bend: 2, lift: 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(legacy)) as? [String: Any])
        XCTAssertNil(object["bendBearingDegrees"])
        XCTAssertNil(object["rollDegrees"])
        XCTAssertEqual(try decoder.decode(CoachMarkCurve.self,
            from: Data("{\"bend\":2,\"lift\":1}".utf8)), legacy)
        for bearing: Float in [-180, -90, 0, 90, 180] {
            let curve = CoachMarkCurve(bend: 2, lift: 1, rollDegrees: 25, bendBearingDegrees: bearing)
            XCTAssertTrue(curve.isValid)
            XCTAssertEqual(try decoder.decode(CoachMarkCurve.self, from: encoder.encode(curve)), curve)
            XCTAssertEqual(curve.clamped().bendBearingDegrees, bearing)
            XCTAssertEqual(curve.adjusting(amountDelta: 0, angleDelta: 10).bendBearingDegrees, bearing)
            XCTAssertEqual(curve.adjusting(amountDelta: 0.25, angleDelta: -10).bendBearingDegrees, bearing)
        }
        for bearing: Float in [-181, 181, .infinity, -.infinity, .nan] {
            let curve = CoachMarkCurve(bend: 1, lift: 0, bendBearingDegrees: bearing)
            XCTAssertFalse(curve.isValid)
            XCTAssertEqual(curve.clamped().bendBearingDegrees?.bitPattern, bearing.bitPattern)
            XCTAssertEqual(curve.adjusting(amountDelta: 1, angleDelta: 10).bendBearingDegrees?.bitPattern,
                           bearing.bitPattern)
            XCTAssertFalse(curve.clamped().isValid)
        }
        let malformed = try decoder.decode(CoachMarkCurve.self,
            from: Data("{\"bend\":1,\"lift\":0,\"bendBearingDegrees\":360}".utf8))
        XCTAssertEqual(malformed.bendBearingDegrees, 360)
        XCTAssertFalse(malformed.isValid)
    }

    func testSpatialEditLengthOnlyAppliesToExplicitlyFramedArcs() {
        let legacy = CoachMarkCurve(bend: 1, lift: 0)
        let stable = CoachMarkCurve(bend: 1, lift: 0, bendBearingDegrees: 90)
        func accepts(_ kind: CoachMarkKind = .arc, end: PitchPoint = .zero,
                     startElevation: Float? = nil, endElevation: Float? = nil,
                     curve: CoachMarkCurve? = nil) -> Bool {
            CoachMarkGeometryPolicy.acceptsEditing(kind: kind, start: .zero, end: end,
                startElevation: startElevation, endElevation: endElevation, curve: curve)
        }
        XCTAssertTrue(accepts(endElevation: 0.8, curve: stable))
        XCTAssertFalse(accepts(endElevation: 0.79999, curve: stable))
        XCTAssertTrue(accepts(startElevation: 2, endElevation: 1, curve: stable))
        XCTAssertTrue(accepts(end: .init(x: 0.75, z: 0), endElevation: 2, curve: stable))
        XCTAssertFalse(accepts(endElevation: 2, curve: legacy))
        XCTAssertFalse(accepts(endElevation: 2))
        XCTAssertFalse(accepts(.pass, endElevation: 2, curve: stable))
        XCTAssertFalse(accepts(.space, end: .init(x: 1.09, z: 0), endElevation: 2, curve: stable))
        XCTAssertTrue(accepts(.space, end: .init(x: 1.1, z: 0), curve: stable))
        XCTAssertTrue(accepts(end: .init(x: 0.8, z: 0), curve: legacy))
        for elevation: Float in [-0.01, 4.01, .infinity, -.infinity, .nan] {
            XCTAssertFalse(accepts(end: .init(x: 1, z: 0), endElevation: elevation, curve: stable))
        }
        XCTAssertFalse(accepts(end: .init(x: .infinity, z: 0), curve: stable))
        XCTAssertFalse(accepts(endElevation: 2,
            curve: .init(bend: 1, lift: 0, bendBearingDegrees: .nan)))
    }

    func testDiagonalBoundaryMatchesFramedSingleKeyValidation() {
        let curve = CoachMarkCurve(bend: 1, lift: 0, bendBearingDegrees: 90)
        // The nominal 0.48/0.64 diagonal is 0.8 m, but validation must use
        // the actual stored Float coordinates in Double, not rounded Float hypot.
        for x in [Float(0.48).nextDown, 0.48, Float(0.48).nextUp] {
            for height in [Float(0.64).nextDown, 0.64, Float(0.64).nextUp] {
                let end = PitchPoint(x: x, z: 0)
                let posed = mark(end: end, endElevation: height, curve: curve)
                let minimum = Double(CoachMarkGeometryPolicy.minimumDirectionalLength)
                let expected = Double(x) * Double(x) + Double(height) * Double(height) >= minimum * minimum
                let accepted = CoachMarkGeometryPolicy.acceptsEditing(kind: .arc, start: .zero, end: end,
                    startElevation: 0, endElevation: height, curve: curve)
                XCTAssertEqual(accepted, expected)
                XCTAssertEqual(posed.recordingPose(at: 0).hasValidKeyframes(duration: 1), accepted)
            }
        }
    }

    private func mark(start: PitchPoint? = nil, end: PitchPoint,
                      startElevation: Float = 0, endElevation: Float,
                      curve: CoachMarkCurve) -> CoachMark {
        CoachMark(kind: .arc, start: start ?? .zero, end: end,
                  startElevation: startElevation, endElevation: endElevation,
                  curve: curve, label: "Stable arc math")
    }

    /// Independent, unchanged pre-bearing arithmetic, including its pole.
    private func legacyControl(for mark: CoachMark) -> SIMD3<Float> {
        let curve = mark.resolvedCurve
        let bend = curve.bend.isFinite ? min(max(curve.bend, -12), 12) : 0
        let lift = curve.lift.isFinite ? min(max(curve.lift, 0), 4) : 0
        let roll = curve.rollDegrees.isFinite ? min(max(curve.rollDegrees, -180), 180) : 0
        let dx = mark.end.x - mark.start.x, dz = mark.end.z - mark.start.z
        let length = max(hypot(dx, dz), 0.0001)
        let midpoint = SIMD3<Float>((mark.start.x + mark.end.x) * 0.5,
            (mark.resolvedStartElevation + mark.resolvedEndElevation) * 0.5,
            (mark.start.z + mark.end.z) * 0.5)
        var offset = SIMD3<Float>(-dz / length * bend * 2, lift * 2, dx / length * bend * 2)
        if roll != 0 {
            let chord = SIMD3<Float>(dx, mark.resolvedEndElevation - mark.resolvedStartElevation, dz)
            let axis = simd_length_squared(chord) > 0.000001 ? simd_normalize(chord) : SIMD3<Float>(1, 0, 0)
            offset = simd_quatf(angle: -roll * .pi / 180, axis: axis).act(offset)
        }
        let control = midpoint + offset
        return .init(min(max(control.x, -34), 34), min(max(control.y, 0), 12),
                     min(max(control.z, -52.5), 52.5))
    }
}
