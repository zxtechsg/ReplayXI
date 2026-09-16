import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayLocomotionTurnContinuityTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func angleDelta(_ first: Float, _ second: Float) -> Float {
        var delta = (second - first).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    /// Continuous source directions, before the production 5 mm admission gate
    /// or strongest-magnitude selection. These fixtures have nonzero vectors.
    private func rawTurns(_ player: PlayerTrack, at time: Double) -> (path: Float, facing: Float, distance: Float) {
        let before = player.presentationPose(at: time - 0.12)
        let centre = player.presentationPose(at: time)
        let after = player.presentationPose(at: time + 0.12)
        let incoming = SIMD2<Float>(centre.position.x - before.position.x,
                                    centre.position.z - before.position.z)
        let outgoing = SIMD2<Float>(after.position.x - centre.position.x,
                                    after.position.z - centre.position.z)
        let path = atan2(incoming.y * outgoing.x - incoming.x * outgoing.y,
                         simd_dot(incoming, outgoing)) * 180 / .pi / 0.12
        return (path, angleDelta(before.facingDegrees, after.facingDegrees) / 0.24,
                min(simd_length(incoming), simd_length(outgoing)))
    }

    private func assertContinuousInputs(_ player: PlayerTrack, before: Double, after: Double,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let a = player.presentationPose(at: before), b = player.presentationPose(at: after)
        XCTAssertEqual(after - before, 0.005, accuracy: 0.0000001, file: file, line: line)
        XCTAssertLessThan(ReplayGeometry.distance(a.position, b.position), 0.006,
                          "The body moves under 6 mm across this 5 ms pair", file: file, line: line)
        XCTAssertLessThan(abs(angleDelta(a.facingDegrees, b.facingDegrees)), 0.5,
                          "The authored heading is continuous, not an intentional turn cut", file: file, line: line)
    }

    private func assertTurnContinuity(_ fixtures: [(String, Double, Double)], name: String) throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        var report: [[String: Any]] = []
        for (id, before, after) in fixtures {
            let player = try XCTUnwrap(scenario.player(id: id))
            assertContinuousInputs(player, before: before, after: after)
            let a = rawTurns(player, at: before), b = rawTurns(player, at: after)
            let first = player.locomotion(at: before), second = player.locomotion(at: after)
            // The turn estimate may choose either cue. It must not create an
            // abrupt opposite-direction response much larger than the change
            // in both continuous cues. 2× plus 5°/s leaves interpolation/Float
            // headroom; it does not prescribe a preferred sign or exact value.
            let inputChange = max(abs(b.path - a.path), abs(b.facing - a.facing))
            let limit = inputChange * 2 + 5
            let change = abs(second.turnRateDegreesPerSecond - first.turnRateDegreesPerSecond)
            XCTAssertLessThan(inputChange, 60, "\(id): source direction fixture must itself stay smooth")
            XCTAssertLessThan(change, limit, "\(id) \(before)→\(after): turn gate/selector must not amplify a smooth input into a snap")
            report.append(["playerID": id, "before": before, "after": after,
                           "pathBefore": a.path, "pathAfter": b.path,
                           "facingBefore": a.facing, "facingAfter": b.facing,
                           "shortestWindowBefore": a.distance, "shortestWindowAfter": b.distance,
                           "speedBefore": first.speedMetresPerSecond, "speedAfter": second.speedMetresPerSecond,
                           "turnBefore": first.turnRateDegreesPerSecond, "turnAfter": second.turnRateDegreesPerSecond,
                           "turnChange": change, "continuousInputLimit": limit])
        }
        try attach(["report": report], name: name)
    }

    func testAuthoredSlowdownsDoNotSnapAtThePathDirectionAdmissionGate() throws {
        try assertTurnContinuity([
            ("navy-rcm", 13.490, 13.495),
            ("red-gk", 26.480, 26.485), ("red-gk", 26.560, 26.565),
        ], name: "ReplayXI-Turn76-Slowdown.json")
    }

    func testOpposedPathAndFacingCuesDoNotFlipTheTurnResponse() throws {
        try assertTurnContinuity([
            ("navy-rw", 12.610, 12.615), ("navy-rw", 12.925, 12.930),
            ("navy-cf", 26.710, 26.715),
        ], name: "ReplayXI-Turn76-OpposedCues.json")
    }

    private func target(_ ball: BallTrack, at time: Double) -> SIMD3<Float> {
        let pose = ball.pose(at: time)
        return [pose.position.x, pose.height, pose.position.z]
    }

    private func withoutTurn(_ sample: PlayerLocomotionSample) -> PlayerLocomotionSample {
        PlayerLocomotionSample(motion: sample.motion, speedMetresPerSecond: sample.speedMetresPerSecond,
                               accelerationMetresPerSecondSquared: sample.accelerationMetresPerSecondSquared,
                               turnRateDegreesPerSecond: 0,
                               state: PlayerLocomotionSample.classify(speedMetresPerSecond: sample.speedMetresPerSecond,
                                                                     turnRateDegreesPerSecond: 0))
    }

    private func rotationDifference(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        let first = simd_normalize(simd_quatf(a)), second = simd_normalize(simd_quatf(b))
        return 2 * acos(min(max(abs(simd_dot(first.vector, second.vector)), 0), 1))
    }

    func testActualSkinnedHeadAndNeckStaySmoothThroughAuthoredSlowdowns() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        var poses: [[String: Any]] = []
        var report: [[String: Any]] = []
        for (label, id, before, after) in [("midfielder", "navy-rcm", 13.490, 13.495),
                                          ("keeper", "red-gk", 26.560, 26.565)] {
            let player = try XCTUnwrap(scenario.player(id: id))
            let skin = try ReplaySkinnedAthleteProvider.make(for: player)
            assertContinuousInputs(player, before: before, after: after)
            func update(_ time: Double, suppressTurn: Bool) -> ReplaySkinnedAthleteMotion.Pose {
                let sampled = player.locomotion(at: time)
                XCTAssertTrue(skin.update(at: time, track: player,
                                          locomotion: suppressTurn ? withoutTurn(sampled) : sampled,
                                          lookTarget: target(scenario.ball, at: time),
                                          ballAction: ReplayAthleteMotion.ballActionPose(for: player,
                                                                                       ballTrack: scenario.ball, at: time)))
                return skin.pose
            }
            let baselineBefore = update(before, suppressTurn: true)
            let baselineAfter = update(after, suppressTurn: true)
            let actualBefore = update(before, suppressTurn: false)
            let actualAfter = update(after, suppressTurn: false)
            for semantic in ["neck", "head"] {
                let index = try XCTUnwrap(skin.motion.semanticJointIndices[semantic])
                let baseline = rotationDifference(baselineBefore.modelSpaceTransforms[index],
                                                  baselineAfter.modelSpaceTransforms[index])
                let actual = rotationDifference(actualBefore.modelSpaceTransforms[index],
                                                actualAfter.modelSpaceTransforms[index])
                // The same source animation, ball target, breathing and gaze
                // provide a measured baseline. Only the turn signal differs.
                // One additional degree over 5 ms is generous headroom for a
                // body moving millimetres with under 0.5° heading change.
                XCTAssertLessThan(baseline, .pi / 180, "\(label) control must itself be continuous")
                XCTAssertLessThan(actual, baseline + .pi / 180,
                                  "\(label) \(semantic): the real skin must not inherit a turn-estimator snap")
                report.append(["playerID": id, "joint": semantic,
                               "baselineDegrees": baseline * 180 / .pi,
                               "actualDegrees": actual * 180 / .pi])
            }
            for (suffix, time, pose) in [("a", before, actualBefore), ("b", after, actualAfter)] {
                poses.append(["name": "\(label)-slowdown-\(suffix)", "time": time,
                              "groundOffset": -skin.motion.geometry.restMinY,
                              "translations": pose.translations.map { [$0.x, $0.y, $0.z] },
                              "rotations": pose.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] },
                              "scales": pose.scales.map { [$0.x, $0.y, $0.z] }])
            }
        }
        try attach(["samples": poses, "report": report], name: "ReplayXI-Turn76-ActualSkin.json")
    }

    func testPlantedPathTurnsAndStationaryBodyTurnsRemainDetectable() {
        func track(_ frames: [MotionKeyframe]) -> PlayerTrack {
            PlayerTrack(id: "turn-76-control", displayName: "Control", role: "Midfielder",
                        shirtNumber: 8, team: .home, isGoalkeeper: false, keyframes: frames)
        }
        func frame(_ time: Double, _ x: Float, _ z: Float, _ facing: Float = 0) -> MotionKeyframe {
            MotionKeyframe(time: time, position: .init(x: x, z: z), facingDegrees: facing)
        }
        let right = track([frame(0, 0, -2), frame(1, 0, 0), frame(2, 2, 0)])
        let left = track([frame(0, 0, -2), frame(1, 0, 0), frame(2, -2, 0)])
        let stationary = track([frame(0, 0, 0, 0), frame(1, 0, 0, 45), frame(2, 0, 0, 90)])
        let straight = track([frame(0, 0, 0), frame(2, 0, 8)])
        XCTAssertGreaterThan(right.locomotion(at: 1).turnRateDegreesPerSecond, 300)
        XCTAssertLessThan(left.locomotion(at: 1).turnRateDegreesPerSecond, -300)
        XCTAssertEqual(stationary.locomotion(at: 1).turnRateDegreesPerSecond, 45, accuracy: 0.001)
        XCTAssertEqual(straight.locomotion(at: 1).turnRateDegreesPerSecond, 0, accuracy: 0.001)
        XCTAssertEqual(straight.locomotion(at: 1).speedMetresPerSecond, 4, accuracy: 0.001)
    }

    func testSlowdownMotionAndSkinStayFiniteAndExactAcrossRepeatedAndReverseSeeks() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let times = [0.0, 12.61, 12.615, 13.49, 13.495, 26.56, 26.565, 32.0]
        for id in ["navy-rcm", "navy-rw", "red-gk"] {
            let player = try XCTUnwrap(scenario.player(id: id))
            let skin = try ReplaySkinnedAthleteProvider.make(for: player)
            let rootScale = skin.root.scale
            func update(_ time: Double) -> ReplaySkinnedAthleteMotion.Pose {
                let sample = player.locomotion(at: time)
                XCTAssertTrue(sample.speedMetresPerSecond.isFinite)
                XCTAssertTrue(sample.accelerationMetresPerSecondSquared.isFinite)
                XCTAssertTrue(sample.turnRateDegreesPerSecond.isFinite)
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                                          lookTarget: target(scenario.ball, at: time),
                                          ballAction: ReplayAthleteMotion.ballActionPose(for: player,
                                                                                       ballTrack: scenario.ball, at: time)))
                XCTAssertEqual(skin.root.scale, rootScale)
                for matrix in skin.pose.modelSpaceTransforms {
                    for column in 0..<4 {
                        XCTAssertTrue((0..<4).allSatisfy { matrix[column][$0].isFinite })
                    }
                }
                for (rotation, scale) in zip(skin.pose.rotations, skin.pose.scales) {
                    XCTAssertEqual(simd_length(rotation.vector), 1, accuracy: 0.00001)
                    XCTAssertTrue(scale.x > 0 && scale.y > 0 && scale.z > 0)
                }
                return skin.pose
            }
            let expected = times.map(update)
            let expectedMotion = times.map { player.locomotion(at: $0) }
            for index in Array(times.indices.reversed()) + [3, 0, 6, 1, 7, 4, 3] {
                let current = update(times[index])
                XCTAssertEqual(current.translations, expected[index].translations)
                XCTAssertEqual(current.rotations.map(\.vector), expected[index].rotations.map(\.vector))
                XCTAssertEqual(current.scales, expected[index].scales)
                XCTAssertEqual(current.modelSpaceTransforms, expected[index].modelSpaceTransforms)
                XCTAssertEqual(player.locomotion(at: times[index]), expectedMotion[index])
            }
        }
    }

    private func attach(_ content: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
