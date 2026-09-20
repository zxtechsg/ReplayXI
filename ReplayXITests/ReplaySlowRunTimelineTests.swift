import Foundation
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySlowRunTimelineTests: XCTestCase {
    func testTwoSidedEnvelopeBoundsRampAndNeverExceedsKnotCaps() throws {
        var caps = [Float](repeating: 1, count: 241)
        caps[60] = 0.2; caps[180] = 0.35
        let timeline = try XCTUnwrap(ReplaySlowRunTimeline(duration: 2, knotCaps: caps,
                                                         zeroCells: [Bool](repeating: false, count: 240)))
        let knots = timeline.knotsForTesting
        for index in knots.indices {
            XCTAssertGreaterThanOrEqual(knots[index], 0)
            XCTAssertLessThanOrEqual(knots[index], caps[index])
            if index > 0 {
                XCTAssertLessThanOrEqual(abs(Double(knots[index]) - Double(knots[index - 1])),
                                        4 / 120.0 + 0.0000001)
            }
        }
        XCTAssertEqual(knots[60], 0.2)
        XCTAssertEqual(knots[180], 0.35)
        XCTAssertEqual(knots[120], 1, "A sustained plateau with enough clearance stays fully admitted")
        // Exact sampled lower-envelope oracle, allowing only conservative Float rounding.
        for index in stride(from: 0, through: 240, by: 7) {
            let expected = caps.indices.map { Double(caps[$0]) + 4 * Double(abs($0 - index)) / 120 }.min()!
            XCTAssertEqual(Double(knots[index]), expected, accuracy: 0.000002)
        }
    }

    func testZeroCellsAreZeroThroughoutAndDoNotCascadeAcrossWholeTimeline() throws {
        let caps = [Float](repeating: 1, count: 241)
        var exclusions = [Bool](repeating: false, count: 240)
        exclusions[120] = true
        let timeline = try XCTUnwrap(ReplaySlowRunTimeline(duration: 2, knotCaps: caps, zeroCells: exclusions))
        for substep in 0...32 {
            XCTAssertEqual(timeline.weight(at: (120 + Double(substep) / 32) / 120), 0)
        }
        XCTAssertEqual(timeline.weight(at: 0), 1)
        XCTAssertEqual(timeline.weight(at: 2), 1)
        XCTAssertLessThanOrEqual(timeline.weight(at: 0.875), 0.5)
        XCTAssertGreaterThan(timeline.weight(at: 0.875), 0.49999)
        let forward = (0...1_920).map { timeline.weight(at: Double($0) / 960) }
        let backward = (0...1_920).reversed().map { timeline.weight(at: Double($0) / 960) }
        XCTAssertEqual(forward, Array(backward.reversed()))
        let largest = zip(forward, forward.dropFirst()).map { pair in abs(pair.1 - pair.0) }.max()!
        XCTAssertLessThanOrEqual(largest, Float(4 / 960.0) + 0.0000001)
    }

    func testBoundsInvalidCapsAndShortFinalCellFailClosed() throws {
        for duration in [Double.nan, .infinity, -.infinity, -1, 0, ReplaySlowRunTimeline.maximumDuration.nextUp] {
            XCTAssertNil(ReplaySlowRunTimeline(duration: duration, knotCaps: [1, 1], zeroCells: [false]))
        }
        XCTAssertNil(ReplaySlowRunTimeline(duration: 1, knotCaps: [1, 1], zeroCells: [false]))
        XCTAssertNil(ReplaySlowRunTimeline(duration: 1 / 120, knotCaps: [1, 1], zeroCells: []))
        for invalid in [Float.nan, .infinity, -.infinity, -0.01, 1.01] {
            let timeline = try XCTUnwrap(ReplaySlowRunTimeline(duration: 2 / 120,
                knotCaps: [1, invalid, 1], zeroCells: [false, false]))
            XCTAssertEqual(timeline.knotsForTesting, [0, 0, 0])
        }
        let duration = 1 / 120.0 + 1 / 960.0
        let short = try XCTUnwrap(ReplaySlowRunTimeline(duration: duration,
            knotCaps: [1, 1, 0.2], zeroCells: [false, false]))
        XCTAssertLessThanOrEqual(Double(short.knotsForTesting[1] - short.knotsForTesting[2]),
                                4 / 960.0 + 0.0000001)
        XCTAssertEqual(short.weight(at: duration), 0.2)
        for time in [Double.nan, .infinity, -.infinity, -0.001, duration.nextUp] {
            XCTAssertEqual(short.weight(at: time), 0)
        }
    }

    func testTrackBuildIsBoundedAndKeepsAForwardJogPlateau() throws {
        let track = forwardTrack()
        let timeline = try XCTUnwrap(ReplaySlowRunTimeline(track: track, duration: 2))
        XCTAssertEqual(timeline.metricsForTesting.knotCount, 241)
        XCTAssertEqual(timeline.metricsForTesting.rawSampleCount, 481)
        XCTAssertEqual(timeline.metricsForTesting.storageBytes, 241 * MemoryLayout<Float>.stride)
        XCTAssertEqual(timeline.weight(at: 1), 1)
        XCTAssertNil(ReplaySlowRunTimeline(track: track, duration: .infinity))
        XCTAssertNil(ReplaySlowRunTimeline(track: track, duration: ReplaySlowRunTimeline.maximumDuration.nextUp))
        let keeper = PlayerTrack(id: track.id, displayName: track.displayName, role: track.role,
            shirtNumber: track.shirtNumber, team: track.team, isGoalkeeper: true, keyframes: track.keyframes)
        XCTAssertNil(ReplaySlowRunTimeline(track: keeper, duration: 2))
        let count = Int(ReplaySlowRunTimeline.maximumDuration * 120) + 1
        let largest = try XCTUnwrap(ReplaySlowRunTimeline(duration: ReplaySlowRunTimeline.maximumDuration,
            knotCaps: [Float](repeating: 1, count: count), zeroCells: [Bool](repeating: false, count: count - 1)))
        XCTAssertEqual(largest.metricsForTesting.knotCount, 10_801)
        XCTAssertEqual(largest.metricsForTesting.storageBytes, 43_204)
    }

    func testShiftedAbsoluteTimesMatchAndInvalidNativeTimeBoundsFailFast() throws {
        var caps = [Float](repeating: 1, count: 241)
        caps[90] = 0.1
        let cells = [Bool](repeating: false, count: 240)
        let baseline = try XCTUnwrap(ReplaySlowRunTimeline(duration: 2, knotCaps: caps, zeroCells: cells))
        for offset: Double in [12.5, 999_998] {
            let shifted = try XCTUnwrap(ReplaySlowRunTimeline(duration: 2, knotCaps: caps,
                                                            zeroCells: cells, startTime: offset))
            XCTAssertEqual(shifted.startTime, offset)
            XCTAssertEqual(shifted.endTime, offset + 2)
            for index in 0...1_920 {
                let relative = Double(index) / 960
                let value = shifted.weight(at: offset + relative)
                XCTAssertEqual(value, baseline.weight(at: relative), accuracy: 0.000002)
                XCTAssertEqual(value, shifted.weight(at: offset + relative), "Absolute lookup has no cursor")
            }
            for index in shifted.knotsForTesting.indices {
                XCTAssertEqual(shifted.weight(at: offset + Double(index) / 120), shifted.knotsForTesting[index])
            }
            XCTAssertEqual(shifted.weight(at: offset.nextDown), 0)
            XCTAssertEqual(shifted.weight(at: shifted.endTime.nextUp), 0)
        }
        let shiftedTrack = forwardTrack(startTime: 12.5)
        let shiftedTimeline = try XCTUnwrap(ReplaySlowRunTimeline(track: shiftedTrack, duration: 2, startTime: 12.5))
        let original = try XCTUnwrap(ReplaySlowRunTimeline(track: forwardTrack(), duration: 2))
        for relative: Double in [0, 0.25, 0.5, 1, 1.75, 2] {
            XCTAssertEqual(shiftedTimeline.weight(at: relative + 12.5), original.weight(at: relative), accuracy: 0.000002)
        }
        for offset in [Double.nan, .infinity, -.infinity, -0.1, 999_999, 1_000_000, Double.greatestFiniteMagnitude] {
            XCTAssertNil(ReplaySlowRunTimeline(duration: 2, knotCaps: caps, zeroCells: cells, startTime: offset))
        }
        XCTAssertNil(ReplaySlowRunTimeline(duration: Double.leastNonzeroMagnitude,
            knotCaps: [1, 1], zeroCells: [false], startTime: 1))
    }

    /// Dense corpus check, not an all-real-times proof or native motion test.
    /// Planned contacts exclude whole actors; native recorded-touch equality
    /// and final joint motion are checked by the separate integration suite.
    func testActualFiveTracksAt960HzReportHardZeroAndFastCutOverlap() throws {
        XCTAssertEqual(FootballReferenceScenarios.all.count, 5)
        var rows: [[String: Any]] = []
        var misses: [[String: Any]] = []
        var totalMisses = 0, totalFastOverlaps = 0, positiveSamples = 0
        for scenario in FootballReferenceScenarios.all {
            let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let protected = Set(plan.map(\.playerID))
                .union(scenario.players.filter(\.isGoalkeeper).map(\.id))
                .union(PlayerRagdollCue.authoredDemo(for: scenario).map { [$0.playerID] } ?? [])
            for track in scenario.players where !protected.contains(track.id) {
                let timeline = try XCTUnwrap(ReplaySlowRunTimeline(track: track, duration: scenario.duration))
                var localMisses = 0, fastOverlaps = 0, peakRate: Double = 0
                var previousTime: Double = 0, previousWeight = timeline.weight(at: 0)
                let samples = Int(ceil(scenario.duration * 960))
                for index in 0...samples {
                    let time = min(Double(index) / 960, scenario.duration)
                    let locomotion = track.locomotion(at: time)
                    let movement = ReplayAthleteMovementIntent.sample(track: track, at: time,
                        presentationPose: track.presentationPose(at: time), lookTarget: nil)
                    let raw = ReplaySlowRunAdmission.weight(locomotion: locomotion)
                        * (movement.map { ReplaySlowRunAdmission.directionWeight(localTravelYaw: $0.localTravelYaw) } ?? 0)
                    let weight = timeline.weight(at: time)
                    if weight > 0 { positiveSamples += 1 }
                    if raw == 0, weight > 0 {
                        localMisses += 1
                        if misses.count < 24 {
                            misses.append(["scenario": scenario.id, "player": track.id, "time": time,
                                "weight": weight, "speed": locomotion.speedMetresPerSecond,
                                "turn": locomotion.turnRateDegreesPerSecond,
                                "yaw": movement?.localTravelYaw ?? 0])
                        }
                    }
                    if locomotion.speedMetresPerSecond > 3, weight > 0 { fastOverlaps += 1 }
                    if time > previousTime {
                        peakRate = max(peakRate, abs(Double(weight) - Double(previousWeight)) / (time - previousTime))
                    }
                    previousTime = time; previousWeight = weight
                }
                totalMisses += localMisses; totalFastOverlaps += fastOverlaps
                XCTAssertLessThanOrEqual(peakRate, 4.0002, "\(scenario.id)/\(track.id)")
                rows.append(["scenario": scenario.id, "player": track.id,
                    "knots": timeline.metricsForTesting.knotCount,
                    "rawSamples": timeline.metricsForTesting.rawSampleCount,
                    "weightPayloadBytes": timeline.metricsForTesting.storageBytes,
                    "hardZeroMisses": localMisses, "speedAbove3Overlaps": fastOverlaps, "peakWeightRate": peakRate])
            }
        }
        let receipt: [String: Any] = ["scope": "960 Hz actual-track audit; not proof between samples or native joint quality",
            "tracks": rows, "firstMisses": misses, "hardZeroMisses": totalMisses,
            "speedAbove3Overlaps": totalFastOverlaps, "positiveSamples": positiveSamples]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: receipt,
            options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-SlowRunTimeline152.json"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertGreaterThan(positiveSamples, 0)
        XCTAssertEqual(totalMisses, 0, "Inspect the receipt before refining; do not add a live raw clamp")
        XCTAssertEqual(totalFastOverlaps, 0)
    }

    private func forwardTrack(startTime: Double = 0) -> PlayerTrack {
        .init(id: "forward-jog", displayName: "Forward jog", role: "Test", shirtNumber: 1,
              team: .home, isGoalkeeper: false,
              keyframes: [.init(time: startTime, position: .init(x: 0, z: 0), facingDegrees: 0),
                          .init(time: startTime + 2, position: .init(x: 0, z: 4), facingDegrees: 0)])
    }
}
