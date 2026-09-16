import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAthleteGazeContinuityTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func track(heading: Float = 0) -> PlayerTrack {
        PlayerTrack(
            id: "rear-gaze-continuity-seven", displayName: "Gaze Test", role: "Right winger",
            shirtNumber: 7, team: .home, isGoalkeeper: false,
            keyframes: [
                .init(time: 0, position: .zero, facingDegrees: heading),
                .init(time: 20, position: .zero, facingDegrees: heading),
            ]
        )
    }

    private func locomotion(speed: Float) -> PlayerLocomotionSample {
        PlayerLocomotionSample(
            motion: .init(speedMetresPerSecond: speed, distanceTravelled: 0, locomotionPhase: 0),
            speedMetresPerSecond: speed, accelerationMetresPerSecondSquared: 0,
            turnRateDegreesPerSecond: 0,
            state: PlayerLocomotionSample.classify(speedMetresPerSecond: speed,
                                                 turnRateDegreesPerSecond: 0)
        )
    }

    private func target(heading: Float, relativeBearing: Float, distance: Float = 10) -> SIMD3<Float> {
        let radians = (heading + relativeBearing) * .pi / 180
        return [sin(radians) * distance, 0.11, cos(radians) * distance]
    }

    private func look(_ player: PlayerTrack, heading: Float, bearing: Float,
                      speed: Float = 0, time: Double = 5) -> ReplayAthleteLookPose {
        ReplayAthleteMotion.lookPose(
            for: player, at: time, locomotion: locomotion(speed: speed),
            targetWorldPosition: target(heading: heading, relativeBearing: bearing)
        )
    }

    func testBallCrossingDirectlyBehindDoesNotSnapTheHead() {
        for heading: Float in [0, 90, 180, -90] {
            let player = track(heading: heading)
            for speed: Float in [0, 1.1, 3.6, 7.2] {
                // A 0.012-degree rear-axis crossing is only 2.1 mm at 10 m.
                let before = look(player, heading: heading, bearing: 179.994, speed: speed)
                let after = look(player, heading: heading, bearing: 180.006, speed: speed)
                XCTAssertLessThan(abs(after.combinedYawRadians - before.combinedYawRadians), 0.005,
                                  "heading \(heading), speed \(speed): a rear ball must not flip shoulder checks")
                XCTAssertEqual(after.combinedPitchRadians, before.combinedPitchRadians, accuracy: 0.00001)
            }
        }
    }

    func testDenseBallAzimuthSweepHasNoSideOrRearDiscontinuity() {
        for heading: Float in [0, 90, 180, -90] {
            let player = track(heading: heading)
            for speed: Float in [0, 1.1, 3.6, 7.2] {
                var previous = look(player, heading: heading, bearing: -180, speed: speed)
                let first = previous
                for angle in -179...180 {
                    let current = look(player, heading: heading, bearing: Float(angle), speed: speed)
                    XCTAssertLessThan(abs(current.combinedYawRadians - previous.combinedYawRadians),
                                      2.5 * .pi / 180,
                                      "heading \(heading), speed \(speed), azimuth \(angle)")
                    XCTAssertEqual(current.combinedPitchRadians, previous.combinedPitchRadians,
                                   accuracy: 0.00001)
                    XCTAssertLessThanOrEqual(abs(current.combinedYawRadians), 64 * .pi / 180)
                    previous = current
                }
                XCTAssertEqual(previous.combinedYawRadians, first.combinedYawRadians, accuracy: 0.00001,
                               "Equivalent ±180-degree targets must agree")
            }
        }
    }

    func testRearAttentionSectorJoinsRemainContinuous() {
        let player = track()
        for boundary: Float in [-180, -112, 112, 180] {
            for speed: Float in [0, 3.6, 7.2] {
                let before = look(player, heading: 0, bearing: boundary - 0.01, speed: speed)
                let after = look(player, heading: 0, bearing: boundary + 0.01, speed: speed)
                XCTAssertLessThan(abs(after.combinedYawRadians - before.combinedYawRadians), 0.001,
                                  "Attention must join smoothly at \(boundary) degrees")
            }
        }
    }

    func testRearAttentionRemainsExactForRepeatedAndReversedTimeSamples() {
        let player = track(heading: 90)
        let times: [Double] = [0, 0.3, 1.55, 3.1, 5, 8.45, 12, 19.9]
        let bearings: [Float] = [-180.01, -179.99, -145, -112, 0, 112, 145, 179.99]
        for speed: Float in [0, 1.1, 3.6, 7.2] {
            let expected = zip(times, bearings).map {
                look(player, heading: 90, bearing: $0.1, speed: speed, time: $0.0)
            }
            for index in times.indices.reversed() {
                XCTAssertEqual(look(player, heading: 90, bearing: bearings[index],
                                    speed: speed, time: times[index]), expected[index])
            }
            for index in [3, 0, 7, 4, 1, 6, 2, 5, 3, 0] {
                XCTAssertEqual(look(player, heading: 90, bearing: bearings[index],
                                    speed: speed, time: times[index]), expected[index])
            }
        }
    }

    func testFrontAndSideBallAttentionRetainTheirExistingWeightAndPitch() {
        // A stationary player isolates ball attention from travel and turn lead.
        // Forward gaze provides the unchanged per-player scan contribution.
        for heading: Float in [0, 90, 180, -90] {
            let player = track(heading: heading)
            let forward = look(player, heading: heading, bearing: 0)
            for bearing: Float in [-112, -90, -45, 0, 45, 90, 112] {
                let actual = look(player, heading: heading, bearing: bearing)
                let expected = min(max((bearing * 0.72 * .pi / 180) + forward.combinedYawRadians,
                                       -64 * .pi / 180), 64 * .pi / 180)
                XCTAssertEqual(actual.combinedYawRadians, expected, accuracy: 0.00001)
                XCTAssertEqual(actual.combinedPitchRadians, forward.combinedPitchRadians, accuracy: 0.00001)
                XCTAssertEqual(actual.neckYawRadians, actual.combinedYawRadians * 0.42, accuracy: 0.00001)
                XCTAssertEqual(actual.neckPitchRadians, actual.combinedPitchRadians * 0.34, accuracy: 0.00001)
            }
        }
    }

    func testSkinnedHeadAndNeckStayContinuousAcrossTheRearAxisAndExportPoses() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let player = track()
        let skin = try ReplaySkinnedAthleteProvider.make(for: player)
        let neck = try XCTUnwrap(skin.motion.semanticJointIndices["neck"])
        let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
        var poses: [[String: Any]] = []
        var report: [[String: Any]] = []

        func update(_ name: String, speed: Float, bearing: Float) throws -> ReplaySkinnedAthleteMotion.Pose {
            let target = target(heading: 0, relativeBearing: bearing)
            let sample = locomotion(speed: speed)
            XCTAssertTrue(skin.update(at: 5, track: player, locomotion: sample,
                                      lookTarget: target, ballAction: nil))
            let gaze = ReplayAthleteMotion.lookPose(for: player, at: 5, locomotion: sample,
                                                   targetWorldPosition: target)
            report.append(["name": name, "bearingDegrees": bearing, "speed": speed,
                           "combinedYawRadians": gaze.combinedYawRadians,
                           "combinedPitchRadians": gaze.combinedPitchRadians])
            poses.append([
                "name": name, "time": 5, "groundOffset": -skin.motion.geometry.restMinY,
                "translations": skin.pose.translations.map { [$0.x, $0.y, $0.z] },
                "rotations": skin.pose.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] },
                "scales": skin.pose.scales.map { [$0.x, $0.y, $0.z] },
            ])
            return skin.pose
        }

        for (label, speed) in [("idle", Float(0)), ("run", Float(3.6))] {
            let before = try update(label + "-rear-left", speed: speed, bearing: 179.994)
            let after = try update(label + "-rear-right", speed: speed, bearing: 180.006)
            for (name, index) in [("neck", neck), ("head", head)] {
                let a = simd_normalize(simd_quatf(before.modelSpaceTransforms[index]))
                let b = simd_normalize(simd_quatf(after.modelSpaceTransforms[index]))
                let angle = 2 * acos(min(max(abs(simd_dot(a.vector, b.vector)), 0), 1))
                XCTAssertLessThan(angle, 0.01, "\(label) \(name): the actual skin must not snap")
                report.append(["name": label + "-" + name + "-crossing", "jointAngleRadians": angle])
            }
            for semantic in ["leftShoulder", "rightShoulder", "leftWrist", "rightWrist"] {
                let index = try XCTUnwrap(skin.motion.semanticJointIndices[semantic])
                for column in 0..<4 {
                    XCTAssertLessThan(simd_distance(before.modelSpaceTransforms[index][column],
                                                    after.modelSpaceTransforms[index][column]), 0.0001)
                }
            }
            let repeated = try update(label + "-rear-repeat", speed: speed, bearing: 179.994)
            XCTAssertEqual(repeated.translations, before.translations)
            XCTAssertEqual(repeated.rotations.map(\.vector), before.rotations.map(\.vector))
            XCTAssertEqual(repeated.scales, before.scales)
        }
        _ = try update("idle-front-control", speed: 0, bearing: 0)
        _ = try update("idle-side-control", speed: 0, bearing: 90)

        let data = try JSONSerialization.data(withJSONObject: ["samples": poses, "report": report],
                                              options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-RearGaze-Poses.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
