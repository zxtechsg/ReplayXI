import XCTest
import simd
@testable import ReplayXI

@MainActor
final class CoachMarkFramedKeyframe155Tests: XCTestCase {
    func testLegacyIntervalsRetainFrozenSamplingExactly() throws {
        let chords: [(PitchPoint, PitchPoint)] = [
            (.init(x: 4, z: 2), .init(x: 8, z: 7)),
            (.init(x: 0.00001, z: 0), .init(x: -0.00001, z: 0)),
            (.init(x: 0, z: 0), .init(x: 0, z: 0)),
            (.init(x: 2, z: 0), .init(x: -2, z: 0))
        ]
        for (first, last) in chords {
            let mark = keyed([
                key(time: 2, end: first, height: 0.5, curve: .init(bend: 2, lift: 1, rollDegrees: 170)),
                key(time: 6, end: last, height: 3, curve: .init(bend: 4, lift: 3, rollDegrees: -170))
            ])
            XCTAssertTrue(mark.hasValidKeyframes(duration: 8))
            let times = [-1.0, 2, 6, 10] + (0...480).map { 2 + Double($0) / 120 }
            for time in times + Array(times.reversed()) {
                let actual = mark.sampled(at: time)
                XCTAssertEqual(actual, frozenLegacySample(mark, at: time), "time=\(time), end=\(last)")
                XCTAssertNil(actual.curve?.bendBearingDegrees)
            }
            XCTAssertEqual(try JSONDecoder().decode(CoachMark.self, from: JSONEncoder().encode(mark)), mark)
        }
    }

    func testMixedIntervalsUseEachKeysOwnGeometryAndKeepExactStoredEndpoints() throws {
        let legacy = key(time: 2, end: .init(x: 4, z: 0), height: 1,
                         curve: .init(bend: 2, lift: 1, rollDegrees: 170))
        let framed = key(time: 6, end: .init(x: 0, z: 4), height: 1,
                         curve: .init(bend: 4, lift: 3, rollDegrees: -170, bendBearingDegrees: -90))
        let mark = keyed([legacy, framed])
        XCTAssertTrue(mark.hasValidKeyframes(duration: 8))
        let mid = try XCTUnwrap(mark.sampled(at: 4).curve)
        XCTAssertEqual(mid.bendBearingDegrees, 180, "Legacy +X chord contributes +Z bearing, not sampled-chord bearing")
        XCTAssertEqual(mid.bend, 3)
        XCTAssertEqual(mid.lift, 2)
        XCTAssertEqual(mid.rollDegrees, 180)
        for time in [-1.0, 2] { XCTAssertEqual(mark.sampled(at: time).curve, legacy.curve) }
        for time in [6.0, 10] { XCTAssertEqual(mark.sampled(at: time).curve, framed.curve) }

        let first = key(time: 2, end: .init(x: 4, z: 0), height: 1,
                        curve: .init(bend: 2, lift: 1, bendBearingDegrees: 90))
        let last = key(time: 6, end: .init(x: 0, z: 4), height: 1,
                       curve: .init(bend: 4, lift: 3))
        let reverseMixed = keyed([first, last])
        XCTAssertEqual(try XCTUnwrap(reverseMixed.sampled(at: 4).curve?.bendBearingDegrees), 135, accuracy: 0.0001)
        XCTAssertEqual(reverseMixed.sampled(at: 6).curve, last.curve)

        // Conversion must also retain the old small-horizontal-chord scale.
        let tiny = key(time: 2, end: .init(x: 0.00001, z: 0), height: 1,
                       curve: .init(bend: 2, lift: 1))
        let tinyMixed = keyed([tiny, framed])
        XCTAssertTrue(tinyMixed.hasValidKeyframes(duration: 8))
        let expectedBend = (try XCTUnwrap(tiny.curve).stabilized(start: tiny.start, end: tiny.end).bend + 4) / 2
        XCTAssertEqual(try XCTUnwrap(tinyMixed.sampled(at: 4).curve).bend, expectedBend)
    }

    func testBearingShortestPathPositiveAntipodalTieAndSeekDeterminism() throws {
        let cases: [(Float, Float, Float)] = [(170, -170, 180), (0, -180, 90),
                                               (-180, 0, -90), (180, 0, -90)]
        for (a, b, middle) in cases {
            let mark = keyed([
                key(time: 2, end: .init(x: 4, z: 0), curve: .init(bend: 2, lift: 1, bendBearingDegrees: a)),
                key(time: 6, end: .init(x: 3, z: 1), curve: .init(bend: 4, lift: 2, bendBearingDegrees: b))
            ])
            XCTAssertEqual(try XCTUnwrap(mark.sampled(at: 4).curve?.bendBearingDegrees), middle)
            let times = (0...720).map { Double($0) / 120 }
            let forward = times.map { mark.sampled(at: $0) }
            for index in times.indices.reversed() { XCTAssertEqual(mark.sampled(at: times[index]), forward[index]) }
            XCTAssertEqual(mark.sampled(at: 2).curve?.bendBearingDegrees, a)
            XCTAssertEqual(mark.sampled(at: 6).curve?.bendBearingDegrees, b)
        }
    }

    func testAnalyticChordGuardRejectsOnlyFramedOrMixedCollapse() {
        let bearingCases: [[Float?]] = [[nil, nil], [0, nil], [nil, 0], [0, 90]]
        for bearings in bearingCases {
            let mark = keyed([
                key(time: 0, end: .init(x: 2, z: 0), curve: .init(bend: 1, lift: 0, bendBearingDegrees: bearings[0])),
                key(time: 1, end: .init(x: -2, z: 0), curve: .init(bend: 1, lift: 0, bendBearingDegrees: bearings[1]))
            ])
            let expected = bearings.allSatisfy { $0 == nil }
            XCTAssertEqual(mark.hasSafeArcKeyframeIntervals, expected)
            XCTAssertEqual(mark.hasValidKeyframes(duration: 2), expected)
        }
        let heights: [Float] = [0.799, 0.8, 1]
        for height in heights {
            let mark = keyed([
                key(time: 0, end: .init(x: -3, z: 0), height: height, curve: .init(bend: 1, lift: 0, bendBearingDegrees: 90)),
                key(time: 1, end: .init(x: 5, z: 0), height: height, curve: .init(bend: 1, lift: 0, bendBearingDegrees: 90))
            ])
            XCTAssertEqual(mark.hasValidKeyframes(duration: 2), height >= 0.8,
                           "Actual 3D chord, not horizontal distance, determines the interval guard")
        }
        let shortLegacy = key(time: 0, end: .init(x: 0.1, z: 0), height: 0.2, curve: .init(bend: 1, lift: 0))
        let shortFramed = key(time: 0, end: .init(x: 0.1, z: 0), height: 0.2,
                              curve: .init(bend: 1, lift: 0, bendBearingDegrees: 90))
        XCTAssertTrue(keyed([shortLegacy]).hasValidKeyframes(duration: 2))
        XCTAssertFalse(keyed([shortFramed]).hasValidKeyframes(duration: 2))

        let independentIntervals = keyed([
            key(time: 0, end: .init(x: 2, z: 0), curve: .init(bend: 1, lift: 0, bendBearingDegrees: 90)),
            key(time: 1, end: .init(x: 3, z: 0), curve: .init(bend: 1, lift: 0)),
            key(time: 2, end: .init(x: -3, z: 0), curve: .init(bend: 1, lift: 0))
        ])
        XCTAssertTrue(independentIntervals.hasValidKeyframes(duration: 2), "The last all-legacy interval remains legacy")
        XCTAssertNil(independentIntervals.sampled(at: 1.5).curve?.bendBearingDegrees)
        XCTAssertEqual(independentIntervals.sampled(at: 1).curve, independentIntervals.keyframes?[1].curve)
    }

    func testAnalyticMinimumRejectsDipMissedBy120HzGrid() {
        let mark = keyed([
            key(time: 0, end: .init(x: -1.2345, z: 0), height: 0.79999,
                curve: .init(bend: 1, lift: 0, bendBearingDegrees: 90)),
            key(time: 1, end: .init(x: 8.7655, z: 0), height: 0.79999,
                curve: .init(bend: 1, lift: 0, bendBearingDegrees: 90))
        ])
        for index in 0...120 {
            let pose = mark.sampled(at: Double(index) / 120)
            let chord = SIMD3<Float>(pose.end.x - pose.start.x,
                                     pose.resolvedEndElevation - pose.resolvedStartElevation,
                                     pose.end.z - pose.start.z)
            XCTAssertGreaterThanOrEqual(simd_length(chord), 0.8)
        }
        XCTAssertFalse(mark.hasSafeArcKeyframeIntervals)
        XCTAssertFalse(mark.hasValidKeyframes(duration: 1))
    }

    private func key(time: TimeInterval, end: PitchPoint, height: Float = 0,
                     curve: CoachMarkCurve) -> CoachMarkKeyframe {
        .init(time: time, mark: CoachMark(kind: .arc, start: .init(x: 0, z: 0), end: end,
              startElevation: 0, endElevation: height, curve: curve, label: "Frame"))
    }

    private func keyed(_ keys: [CoachMarkKeyframe]) -> CoachMark {
        CoachMark(kind: .arc, start: .init(x: 1, z: 1), end: .init(x: 6, z: 2),
                  curve: .init(bend: 1, lift: 0), label: "Legacy metadata", revealTime: 0.5,
                  hideTime: 7, author: "Coach", keyframes: keys)
    }

    /// Frozen pre-frame two-key algorithm, independent of the new branch.
    private func frozenLegacySample(_ mark: CoachMark, at time: TimeInterval) -> CoachMark {
        let frames = mark.keyframes!
        var a = frames[0], b = frames[0]
        if time >= frames[1].time { a = frames[1]; b = frames[1] }
        else if time > frames[0].time { b = frames[1] }
        let t: Float = b.time > a.time ? Float((time - a.time) / (b.time - a.time)) : 0
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }
        func point(_ x: PitchPoint, _ y: PitchPoint) -> PitchPoint { .init(x: mix(x.x, y.x), z: mix(x.z, y.z)) }
        let x = a.curve!, y = b.curve!
        var delta = (y.rollDegrees - x.rollDegrees).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        var roll = (x.rollDegrees + delta * min(max(t, 0), 1)).truncatingRemainder(dividingBy: 360)
        if roll > 180 { roll -= 360 }
        if roll < -180 { roll += 360 }
        return CoachMark(id: mark.id, kind: mark.kind, start: point(a.start, b.start), end: point(a.end, b.end),
            startElevation: mix(a.startElevation, b.startElevation), endElevation: mix(a.endElevation, b.endElevation),
            curve: .init(bend: mix(x.bend, y.bend), lift: mix(x.lift, y.lift), rollDegrees: roll),
            label: mark.label, revealTime: mark.revealTime, hideTime: mark.hideTime, author: mark.author,
            playerID: mark.playerID, startTrackAnchor: mark.startTrackAnchor, endTrackAnchor: mark.endTrackAnchor,
            keyframes: frames)
    }
}
