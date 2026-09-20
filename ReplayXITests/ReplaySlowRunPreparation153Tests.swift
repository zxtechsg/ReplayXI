import Foundation
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySlowRunPreparation153Tests: XCTestCase {
    func testSkippedMidpointsKeepAllFiveDemoTablesBitExact() throws {
        var rows: [[String: Any]] = []
        var skipped = 0
        for scenario in FootballReferenceScenarios.all {
            for track in scenario.players where !track.isGoalkeeper {
                let timeline = try XCTUnwrap(ReplaySlowRunTimeline(track: track, duration: scenario.duration))
                let original = try originalBuilder(track: track, duration: scenario.duration, optimized: timeline)
                assertExact(timeline, original: original)
                let metrics = timeline.metricsForTesting
                skipped += metrics.skippedMidpointCount
                rows.append(["scenario": scenario.id, "player": track.id,
                    "logicalRawSamples": metrics.rawSampleCount,
                    "evaluatedRawSamples": metrics.evaluatedRawSampleCount,
                    "skippedMidpoints": metrics.skippedMidpointCount,
                    "exactKnots": true])
            }
        }
        XCTAssertGreaterThan(skipped, 0)
        let report: [String: Any] = [
            "scope": "Exact comparison to run152's unconditional midpoint sampling. All non-keepers, including protected actors; native admission is unchanged.",
            "tracks": rows, "totalSkippedMidpoints": skipped
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-SlowRunPreparation153-ExactTables.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testShiftedPartialCellsAndZeroTracksKeepExactWeightsAndHonestCounts() throws {
        for start: Double in [0, 12.5, 999_997] {
            for duration in [1 / 960.0, 2 / 120.0 + 1 / 960.0, 2.0] {
                for speed: Float in [0, 2, 4] {
                    let track = PlayerTrack(id: "preparation153", displayName: "Preparation", role: "Test",
                        shirtNumber: 2, team: .away, isGoalkeeper: false,
                        keyframes: [.init(time: start, position: .init(x: 0, z: 0), facingDegrees: 0),
                            .init(time: start + duration, position: .init(x: 0, z: speed * Float(duration)), facingDegrees: 0)])
                    let timeline = try XCTUnwrap(ReplaySlowRunTimeline(track: track, duration: duration, startTime: start))
                    assertExact(timeline, original: try originalBuilder(track: track, duration: duration,
                                                                        start: start, optimized: timeline))
                    if speed == 0 {
                        XCTAssertTrue(timeline.knotsForTesting.allSatisfy { $0 == 0 })
                        XCTAssertEqual(timeline.metricsForTesting.evaluatedRawSampleCount,
                                       timeline.metricsForTesting.knotCount)
                    }
                }
            }
        }
        let pure = try XCTUnwrap(ReplaySlowRunTimeline(duration: 1 / 120,
            knotCaps: [1, 1], zeroCells: [false]))
        XCTAssertEqual(pure.metricsForTesting.rawSampleCount, 0)
        XCTAssertEqual(pure.metricsForTesting.evaluatedRawSampleCount, 0)
        XCTAssertEqual(pure.metricsForTesting.skippedMidpointCount, 0)
    }

    private func assertExact(_ timeline: ReplaySlowRunTimeline, original: ReplaySlowRunTimeline,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(timeline.knotsForTesting.map(\.bitPattern), original.knotsForTesting.map(\.bitPattern),
                       file: file, line: line)
        let metrics = timeline.metricsForTesting
        XCTAssertEqual(metrics.evaluatedRawSampleCount + metrics.skippedMidpointCount, metrics.rawSampleCount,
                       file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.evaluatedRawSampleCount, metrics.knotCount, file: file, line: line)
        XCTAssertLessThanOrEqual(metrics.evaluatedRawSampleCount, metrics.rawSampleCount, file: file, line: line)
        for sample in 0...120 {
            let time = timeline.startTime + timeline.duration * Double(sample) / 120
            XCTAssertEqual(timeline.weight(at: time).bitPattern, original.weight(at: time).bitPattern,
                           file: file, line: line)
        }
    }

    /// Frozen run152 grid construction: every midpoint is evaluated even
    /// when an endpoint already excludes that cell. The shared pure envelope
    /// is separately covered by ReplaySlowRunTimelineTests.
    private func originalBuilder(track: PlayerTrack, duration: Double, start: Double = 0,
                                 optimized: ReplaySlowRunTimeline) throws -> ReplaySlowRunTimeline {
        let end = start + duration
        var cells = max(1, Int(ceil(duration * 120)))
        if cells > 1, start + Double(cells - 1) / 120 >= end { cells -= 1 }
        func time(_ index: Int) -> Double { min(start + Double(index) / 120, end) }
        let caps = (0...cells).map { rawWeight(track: track, time: time($0)) }
        let requiredMidpoints = (0..<cells).filter { caps[$0] != 0 && caps[$0 + 1] != 0 }.count
        XCTAssertEqual(optimized.metricsForTesting.evaluatedRawSampleCount, caps.count + requiredMidpoints,
                       "Independent cap-derived evaluation count: \(track.id)")
        XCTAssertEqual(optimized.metricsForTesting.skippedMidpointCount, cells - requiredMidpoints)
        let zeros = (0..<cells).map { index in
            let middle = rawWeight(track: track, time: (time(index) + time(index + 1)) * 0.5)
            return caps[index] == 0 || middle == 0 || caps[index + 1] == 0
        }
        return try XCTUnwrap(ReplaySlowRunTimeline(duration: duration, knotCaps: caps,
                                                  zeroCells: zeros, startTime: start))
    }

    private func rawWeight(track: PlayerTrack, time: Double) -> Float {
        let weight = ReplaySlowRunAdmission.weight(locomotion: track.locomotion(at: time))
        guard weight > 0,
              let movement = ReplayAthleteMovementIntent.sample(track: track, at: time,
                  presentationPose: track.presentationPose(at: time), lookTarget: nil) else { return 0 }
        return weight * ReplaySlowRunAdmission.directionWeight(localTravelYaw: movement.localTravelYaw)
    }
}
