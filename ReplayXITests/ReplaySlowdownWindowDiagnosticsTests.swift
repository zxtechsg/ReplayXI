import RealityKit
import XCTest
@testable import ReplayXI

/// Bounded evidence capture, not a visual smoothness acceptance threshold.
@MainActor
final class ReplaySlowdownWindowDiagnosticsTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func quaternion(_ matrix: simd_float4x4) -> simd_quatf {
        simd_normalize(simd_quatf(matrix))
    }

    private func array(_ value: simd_quatf) -> [Float] {
        [value.vector.x, value.vector.y, value.vector.z, value.vector.w]
    }

    private func withoutTurn(_ sample: PlayerLocomotionSample) -> PlayerLocomotionSample {
        PlayerLocomotionSample(motion: sample.motion, speedMetresPerSecond: sample.speedMetresPerSecond,
                               accelerationMetresPerSecondSquared: sample.accelerationMetresPerSecondSquared,
                               turnRateDegreesPerSecond: 0,
                               state: PlayerLocomotionSample.classify(speedMetresPerSecond: sample.speedMetresPerSecond,
                                                                     turnRateDegreesPerSecond: 0))
    }

    func testExportExactHeadAndNeckAcrossKeeperSlowdownWithStandingAndRunningControls() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        var report: [[String: Any]] = []
        var poses: [[String: Any]] = []
        let windows: [(String, String, Double)] = [
            ("keeper", "red-gk", 26.46),
            ("standing", "red-gk", 10),
            ("running", "navy-rb", 12.10),
        ]
        for (label, playerID, start) in windows {
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let skin = try ReplaySkinnedAthleteProvider.make(for: player)
            let procedural = try ReplayAthleteFactory.make(for: player, lod: .near)
            let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
            let neck = try XCTUnwrap(skin.motion.semanticJointIndices["neck"])
            let forward = skin.motion.joints[head].localForwardAxis
            var firstPose: ReplaySkinnedAthleteMotion.Pose?

            for step in 0...26 {
                let time = start + Double(step) * 0.005
                let sample = player.locomotion(at: time)
                let actor = player.presentationPose(at: time)
                let ball = scenario.ball.pose(at: time)
                let target = SIMD3<Float>(ball.position.x, ball.height, ball.position.z)
                let action = ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time)
                let heading = simd_quatf(angle: actor.facingDegrees * .pi / 180, axis: [0, 1, 0])

                func updateSkin(_ locomotion: PlayerLocomotionSample) -> ReplaySkinnedAthleteMotion.Pose {
                    XCTAssertTrue(skin.update(at: time, track: player, locomotion: locomotion,
                                              lookTarget: target, ballAction: action))
                    return skin.pose
                }
                func updateProcedural(_ locomotion: PlayerLocomotionSample) -> (neck: simd_quatf, head: simd_quatf) {
                    ReplayAthleteMotion.apply(
                        ReplayAthleteMotion.locomotionPose(for: player, at: time, locomotion: locomotion,
                                                         gaitPhase: player.gaitPhase(at: time),
                                                         lookTargetWorldPosition: target, ballAction: action),
                        to: procedural.joints
                    )
                    return (
                        simd_normalize(heading * procedural.joints[.neck].orientation(relativeTo: procedural.root)),
                        simd_normalize(heading * procedural.joints[.headRoot].orientation(relativeTo: procedural.root))
                    )
                }

                let baselineSample = withoutTurn(sample)
                let baselineSkin = updateSkin(baselineSample)
                let baselineProcedural = updateProcedural(baselineSample)
                let actualSkin = updateSkin(sample)
                let actualProcedural = updateProcedural(sample)
                if step == 0 { firstPose = actualSkin }
                let skinHead = simd_normalize(heading * quaternion(actualSkin.modelSpaceTransforms[head]))
                let skinNeck = simd_normalize(heading * quaternion(actualSkin.modelSpaceTransforms[neck]))
                let baselineHead = simd_normalize(heading * quaternion(baselineSkin.modelSpaceTransforms[head]))
                let baselineNeck = simd_normalize(heading * quaternion(baselineSkin.modelSpaceTransforms[neck]))
                let skinForward = skinHead.act(forward)
                let baselineForward = baselineHead.act(forward)
                let proceduralForward = actualProcedural.head.act([0, 0, 1])
                let baselineProceduralForward = baselineProcedural.head.act([0, 0, 1])
                let gaze = ReplayAthleteMotion.lookPose(for: player, at: time, locomotion: sample,
                                                       targetWorldPosition: target)
                for rotation in [skinHead, skinNeck, baselineHead, baselineNeck,
                                 actualProcedural.head, actualProcedural.neck,
                                 baselineProcedural.head, baselineProcedural.neck] {
                    XCTAssertTrue(array(rotation).allSatisfy(\.isFinite))
                    XCTAssertEqual(simd_length(rotation.vector), 1, accuracy: 0.00001)
                }
                XCTAssertTrue(sample.speedMetresPerSecond.isFinite)
                XCTAssertTrue(sample.turnRateDegreesPerSecond.isFinite)
                report.append([
                    "window": label, "playerID": playerID, "time": time,
                    "position": [actor.position.x, actor.position.z], "facingDegrees": actor.facingDegrees,
                    "ballPosition": [ball.position.x, ball.height, ball.position.z],
                    "ballBearingDegrees": atan2(ball.position.x - actor.position.x,
                                                 ball.position.z - actor.position.z) * 180 / .pi,
                    "speed": sample.speedMetresPerSecond, "turnRate": sample.turnRateDegreesPerSecond,
                    "estimatedLocalGazeYawDegrees": gaze.combinedYawRadians * 180 / .pi,
                    "skinHead": array(skinHead), "skinNeck": array(skinNeck),
                    "baselineSkinHead": array(baselineHead), "baselineSkinNeck": array(baselineNeck),
                    "proceduralHead": array(actualProcedural.head), "proceduralNeck": array(actualProcedural.neck),
                    "baselineProceduralHead": array(baselineProcedural.head),
                    "baselineProceduralNeck": array(baselineProcedural.neck),
                    "skinHeadYawDegrees": atan2(skinForward.x, skinForward.z) * 180 / .pi,
                    "baselineSkinHeadYawDegrees": atan2(baselineForward.x, baselineForward.z) * 180 / .pi,
                    "proceduralHeadYawDegrees": atan2(proceduralForward.x, proceduralForward.z) * 180 / .pi,
                    "baselineProceduralHeadYawDegrees": atan2(baselineProceduralForward.x,
                                                               baselineProceduralForward.z) * 180 / .pi,
                ])

                if (label == "keeper" && [0, 4, 8, 13, 17, 21].contains(step)) || (label != "keeper" && step == 0) {
                    poses.append([
                        "name": "\(label)-window-\(step)", "time": time,
                        "groundOffset": -skin.motion.geometry.restMinY,
                        "translations": actualSkin.translations.map { [$0.x, $0.y, $0.z] },
                        "rotations": actualSkin.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] },
                        "scales": actualSkin.scales.map { [$0.x, $0.y, $0.z] },
                    ])
                }
            }

            let first = try XCTUnwrap(firstPose)
            let ball = scenario.ball.pose(at: start)
            XCTAssertTrue(skin.update(at: start, track: player, locomotion: player.locomotion(at: start),
                                      lookTarget: [ball.position.x, ball.height, ball.position.z],
                                      ballAction: ReplayAthleteMotion.ballActionPose(for: player,
                                                                                   ballTrack: scenario.ball, at: start)))
            XCTAssertEqual(skin.pose.translations, first.translations)
            XCTAssertEqual(skin.pose.rotations.map(\.vector), first.rotations.map(\.vector))
            XCTAssertEqual(skin.pose.scales, first.scales)
        }
        let data = try JSONSerialization.data(withJSONObject: ["samples": poses, "report": report],
                                              options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Slowdown80-Window.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
