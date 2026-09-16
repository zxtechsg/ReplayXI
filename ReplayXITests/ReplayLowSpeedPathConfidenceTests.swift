import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayLowSpeedPathConfidenceTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func track(_ frames: [MotionKeyframe]) -> PlayerTrack {
        PlayerTrack(id: "low-speed-path-confidence", displayName: "Control", role: "Midfielder",
                    shirtNumber: 8, team: .home, isGoalkeeper: false, keyframes: frames)
    }

    private func frame(_ time: Double, _ x: Float, _ z: Float, _ facing: Float = 0) -> MotionKeyframe {
        MotionKeyframe(time: time, position: .init(x: x, z: z), facingDegrees: facing)
    }

    private func corner(speed: Float, direction: Float, facingTurn: Float = 0) -> PlayerTrack {
        let base = track([frame(0, 0, -2), frame(1, 0, 0), frame(2, direction * 2, 0)])
        let scale = speed / base.locomotion(at: 1).speedMetresPerSecond
        return track([frame(0, 0, -2 * scale, -facingTurn), frame(1, 0, 0),
                      frame(2, direction * 2 * scale, 0, facingTurn)])
    }

    private func facingTurn(_ player: PlayerTrack, at time: Double) -> Float {
        var delta = (player.presentationPose(at: time + 0.12).facingDegrees
            - player.presentationPose(at: time - 0.12).facingDegrees).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return min(max(delta / 0.24, -360), 360)
    }

    func testNearIdlePathCurvatureYieldsToAuthoredFacingForBothTurnDirections() {
        for speed: Float in [0, 0.05, 0.10, 0.17] {
            for direction: Float in [-1, 1] {
                for bodyTurn: Float in [-45, 0, 45] {
                    let player = corner(speed: speed, direction: direction, facingTurn: bodyTurn)
                    let sample = player.locomotion(at: 1)
                    XCTAssertEqual(sample.speedMetresPerSecond, speed, accuracy: 0.000001)
                    XCTAssertEqual(sample.turnRateDegreesPerSecond, facingTurn(player, at: 1), accuracy: 0.0001,
                                   "A near-idle path must not replace the independently authored body turn")
                }
            }
        }
    }

    func testPathConfidenceHasContinuousJoinsAndMonotoneIntermediateStrength() {
        for direction: Float in [-1, 1] {
            func response(_ speed: Float) -> Float {
                corner(speed: speed, direction: direction).locomotion(at: 1).turnRateDegreesPerSecond * direction
            }
            // A 0.00002 m/s interval brackets each exact join. The smoothstep's
            // zero endpoint derivative leaves only Float-sized differences;
            // this tolerance is a mathematical join check, not a head-speed limit.
            for boundary: Float in [0.18, 0.40] {
                XCTAssertLessThan(abs(response(boundary + 0.00001) - response(boundary - 0.00001)), 0.01)
            }
            XCTAssertEqual(response(0.18), 0, accuracy: 0.0001)
            XCTAssertEqual(response(0.40), 360, accuracy: 0.0001)
            XCTAssertGreaterThan(response(0.29), 0)
            XCTAssertLessThan(response(0.29), 360,
                              "The confidence band must blend, not reach full strength immediately after idle")
            let speeds = (0...100).map { Float(0.18) + Float($0) * 0.0022 }
            let responses = speeds.map(response)
            XCTAssertTrue(responses.allSatisfy { $0.isFinite && $0 >= -0.0001 && $0 <= 360.0001 })
            XCTAssertTrue(zip(responses, responses.dropFirst()).allSatisfy { pair in pair.1 >= pair.0 - 0.0001 })
            for index in speeds.indices.reversed() {
                XCTAssertEqual(response(speeds[index]), responses[index])
            }
        }
    }

    func testConfidentMovingCutsAndBodyOnlyTurnsKeepTheirExistingResponse() {
        for direction: Float in [-1, 1] {
            for speed: Float in [0.40, 0.4512, 0.60, 1.2, 5.5] {
                XCTAssertEqual(corner(speed: speed, direction: direction).locomotion(at: 1).turnRateDegreesPerSecond,
                               direction * 360, accuracy: 0.0001)
            }
        }
        for speed: Float in [0, 0.10, 0.18, 0.29, 0.40, 1.2] {
            for bodyTurn: Float in [-45, 45] {
                let player = track([frame(0, 0, -speed, -bodyTurn), frame(1, 0, 0),
                                    frame(2, 0, speed, bodyTurn)])
                XCTAssertEqual(player.locomotion(at: 1).turnRateDegreesPerSecond, bodyTurn, accuracy: 0.0001)
            }
        }
    }

    func testMeasuredNearStopHeadsUseTheSameBodyTurnCueInBothRenderers() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "red-gk"))
        let skin = try ReplaySkinnedAthleteProvider.make(for: player)
        let rig = try ReplayAthleteFactory.make(for: player, lod: .near)
        let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
        let neck = try XCTUnwrap(skin.motion.semanticJointIndices["neck"])
        for time in [26.49, 26.515, 26.535, 26.545, 26.55, 26.56] {
            let actual = player.locomotion(at: time)
            XCTAssertLessThan(actual.speedMetresPerSecond, 0.18)
            let bodyTurn = facingTurn(player, at: time)
            let expected = PlayerLocomotionSample(
                motion: actual.motion, speedMetresPerSecond: actual.speedMetresPerSecond,
                accelerationMetresPerSecondSquared: actual.accelerationMetresPerSecondSquared,
                turnRateDegreesPerSecond: bodyTurn,
                state: PlayerLocomotionSample.classify(speedMetresPerSecond: actual.speedMetresPerSecond,
                                                     turnRateDegreesPerSecond: bodyTurn)
            )
            let ball = scenario.ball.pose(at: time)
            let target = SIMD3<Float>(ball.position.x, ball.height, ball.position.z)
            let action = ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time)
            func apply(_ sample: PlayerLocomotionSample) -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample, lookTarget: target,
                                          ballAction: action))
                ReplayAthleteMotion.apply(
                    ReplayAthleteMotion.locomotionPose(for: player, at: time, locomotion: sample,
                                                     gaitPhase: player.gaitPhase(at: time),
                                                     lookTargetWorldPosition: target, ballAction: action),
                    to: rig.joints
                )
                return (skin.pose.rotations[head].vector, skin.pose.rotations[neck].vector,
                        rig.joints[.headRoot].orientation(relativeTo: rig.root).vector,
                        rig.joints[.neck].orientation(relativeTo: rig.root).vector)
            }
            let baseline = apply(expected), rendered = apply(actual)
            XCTAssertEqual(rendered.0, baseline.0, "\(time): skin head must retain authored body turn, not noisy path curvature")
            XCTAssertEqual(rendered.1, baseline.1)
            XCTAssertEqual(rendered.2, baseline.2, "\(time): procedural and skinned policies must agree")
            XCTAssertEqual(rendered.3, baseline.3)
        }
    }
}
