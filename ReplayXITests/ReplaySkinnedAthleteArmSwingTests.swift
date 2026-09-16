import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySkinnedAthleteArmSwingTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func prepare() throws -> (PlayerTrack, ReplaySkinnedAthleteInstance) {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        return (player, try ReplaySkinnedAthleteProvider.make(for: player))
    }

    private func locomotion(_ player: PlayerTrack, at time: Double, speed: Float, turn: Float) -> PlayerLocomotionSample {
        PlayerLocomotionSample(motion: player.locomotion(at: time).motion,
                               speedMetresPerSecond: speed, accelerationMetresPerSecondSquared: 0,
                               turnRateDegreesPerSecond: turn,
                               state: PlayerLocomotionSample.classify(speedMetresPerSecond: speed,
                                                                     turnRateDegreesPerSecond: turn))
    }

    private func position(_ skin: ReplaySkinnedAthleteInstance, _ name: String) throws -> SIMD3<Float> {
        let index = try XCTUnwrap(skin.motion.semanticJointIndices[name])
        let value = skin.pose.modelSpaceTransforms[index].columns.3
        return SIMD3(value.x, value.y, value.z)
    }

    private func armIndices(_ motion: ReplaySkinnedAthleteMotion) throws -> [Int] {
        try ["leftShoulder", "leftElbow", "leftWrist", "rightShoulder", "rightElbow", "rightWrist"]
            .map { try XCTUnwrap(motion.semanticJointIndices[$0]) }
    }

    func testWalkingAndCutsKeepOppositeArmAndLegSwing() throws {
        let (player, skin) = try prepare()
        var samples: [[String: Any]] = []
        var report: [[String: Any]] = []
        for (name, time, speed, turn, checksCounterSwing) in [
            ("walk-backward-step", 12.23, Float(1.1), Float(0), true),
            ("walk-forward-step", 13.866666666666667, 1.1, 0, true),
            ("cut-left", 15.0, 3.0, -180, true),
            ("cut-right", 11.4, 3.0, 180, true),
            ("source-run-a", 12.0, 3.6, 0, false),
            ("source-run-b", 14.333333333333334, 3.6, 0, false),
            ("slow-walk", 12.666666666666666, 0.35, 0, false),
            ("walk-run-blend", 13.4, 1.7, 0, false)
        ] {
            let sample = locomotion(player, at: time, speed: speed, turn: turn)
            XCTAssertTrue(skin.update(at: time, track: player,
                                      locomotion: sample,
                                      lookTarget: nil, ballAction: nil))
            let armLead = try (position(skin, "leftWrist").z - position(skin, "leftShoulder").z)
                - (position(skin, "rightWrist").z - position(skin, "rightShoulder").z)
            let legLead = try (position(skin, "leftAnkle").z - position(skin, "leftHip").z)
                - (position(skin, "rightAnkle").z - position(skin, "rightHip").z)
            report.append(["name": name, "time": time, "armForwardDifference": armLead,
                           "legForwardDifference": legLead, "counterSwing": armLead * legLead < 0])
            samples.append([
                "name": name, "time": time, "groundOffset": -skin.motion.geometry.restMinY,
                "translations": skin.pose.translations.map { [$0.x, $0.y, $0.z] },
                "rotations": skin.pose.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] },
                "scales": skin.pose.scales.map { [$0.x, $0.y, $0.z] }
            ])
            if checksCounterSwing {
                XCTAssertGreaterThan(abs(legLead), 0.1, "The fixture must contain a clear lead leg")
                XCTAssertLessThan(armLead * legLead, -0.001,
                                  "\(name): authored walking/cutting should counter-swing, not march same-side")
                let authored = ReplayAthleteMotion.locomotionPose(
                    for: player, at: time, locomotion: sample, gaitPhase: player.gaitPhase(at: time),
                    lookTargetWorldPosition: nil, ballAction: nil
                )
                let root = try XCTUnwrap(skin.motion.semanticJointIndices["hips"])
                let rootX = skin.motion.restPose.modelSpaceTransforms[root].columns.3.x
                for side in ["left", "right"] {
                    let shoulder = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Shoulder"])
                    let negativeSide = skin.motion.restPose.modelSpaceTransforms[shoulder].columns.3.x < rootX
                    let expected = (negativeSide ? authored.leftElbowOrientation : authored.rightElbowOrientation).angle
                    let upper = try position(skin, side + "Elbow") - position(skin, side + "Shoulder")
                    let lower = try position(skin, side + "Wrist") - position(skin, side + "Elbow")
                    let bend = acos(min(max(simd_dot(simd_normalize(upper), simd_normalize(lower)), -1), 1))
                    XCTAssertEqual(bend, expected, accuracy: 0.0001,
                                   "\(name) \(side): the skin must retain the authored elbow bend")
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["samples": samples, "report": report],
                                              options: [.sortedKeys])
        let poses = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        poses.name = "ReplayXI-ArmSwing-Poses.json"
        poses.lifetime = .keepAlways
        add(poses)
    }

    func testStraightRunningRetainsExactSourceArmLocals() throws {
        let (player, skin) = try prepare()
        let indices = try armIndices(skin.motion)
        var source = skin.motion.makePoseBuffer()
        for time in stride(from: 11.0, through: 15.0, by: 0.05) {
            let sample = locomotion(player, at: time, speed: 3.6, turn: 0)
            skin.motion.sample(time: time, locomotionEffort: sample.effort,
                               gaitPhase: player.gaitPhase(at: time), into: &source)
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                                      lookTarget: nil, ballAction: nil))
            for index in indices {
                XCTAssertEqual(skin.pose.translations[index], source.translations[index])
                XCTAssertEqual(skin.pose.rotations[index].vector, source.rotations[index].vector)
                XCTAssertEqual(skin.pose.scales[index], source.scales[index])
            }
        }
    }

    func testStraightRunBallContactDoesNotOverrideSourceArms() throws {
        let (player, skin) = try prepare()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let time = 13.6
        let sample = locomotion(player, at: time, speed: 3.6, turn: 0)
        let action = try XCTUnwrap(ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time))
        XCTAssertGreaterThan(ReplaySkinnedAthleteFootballPose.influence(locomotion: sample, ballAction: action), 0)
        XCTAssertEqual(ReplaySkinnedAthleteFootballPose.influence(locomotion: sample, ballAction: nil), 0)
        var source = skin.motion.makePoseBuffer()
        skin.motion.sample(time: time, locomotionEffort: sample.effort,
                           gaitPhase: player.gaitPhase(at: time), into: &source)
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample, lookTarget: nil, ballAction: action))
        for index in try armIndices(skin.motion) {
            XCTAssertEqual(skin.pose.translations[index], source.translations[index])
            XCTAssertEqual(skin.pose.rotations[index].vector, source.rotations[index].vector)
            XCTAssertEqual(skin.pose.scales[index], source.scales[index])
        }
    }

    func testArmsRewindExactlyWhileFingerLocalsRemainSourceAuthored() throws {
        let (player, skin) = try prepare()
        let wrists = Set(try ["leftWrist", "rightWrist"].map { try XCTUnwrap(skin.motion.semanticJointIndices[$0]) })
        let fingers = skin.motion.joints.indices.filter { index in
            var parent = skin.motion.joints[index].parentIndex
            while parent >= 0 {
                if wrists.contains(parent) { return true }
                parent = skin.motion.joints[parent].parentIndex
            }
            return false
        }
        XCTAssertGreaterThan(fingers.count, 10)
        var source = skin.motion.makePoseBuffer()
        for (speed, turn) in [(Float(1.1), Float(0)), (1.7, 0), (3.0, -180), (3.0, 180)] {
            func seek(_ time: Double) {
                let sample = locomotion(player, at: time, speed: speed, turn: turn)
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                                          lookTarget: nil, ballAction: nil))
            }
            let time = 12.23
            seek(time)
            let expected = skin.model.jointTransforms
            for other in [15.0, 0.0, 11.4, 7.0, time] { seek(other) }
            XCTAssertEqual(skin.model.jointTransforms, expected)
            let effort = locomotion(player, at: time, speed: speed, turn: turn).effort * min(speed / 2.4, 1)
            skin.motion.sample(time: time, locomotionEffort: effort, gaitPhase: player.gaitPhase(at: time), into: &source)
            for index in fingers {
                XCTAssertEqual(skin.pose.translations[index], source.translations[index])
                XCTAssertEqual(skin.pose.rotations[index].vector, source.rotations[index].vector)
                XCTAssertEqual(skin.pose.scales[index], source.scales[index])
            }
        }
    }

    func testAuthoredArmsKeepLimbLengthsAndDoNotFollowHeadTurns() throws {
        let (player, skin) = try prepare()
        let indices = try armIndices(skin.motion)
        for (speed, turn) in [(Float(1.1), Float(0)), (1.7, 0), (3, -180), (3, 180)] {
            for time in stride(from: 11.0, through: 15.0, by: 0.13) {
                let sample = locomotion(player, at: time, speed: speed, turn: turn)
                let current = player.presentationPose(at: time)
                let bearing = current.facingDegrees * .pi / 180
                func target(_ side: Float) -> SIMD3<Float> {
                    [current.position.x + sin(bearing) * 10 + cos(bearing) * side * 10,
                     1.5, current.position.z + cos(bearing) * 10 - sin(bearing) * side * 10]
                }
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                                          lookTarget: target(-1), ballAction: nil))
                let first = skin.pose
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                                          lookTarget: target(1), ballAction: nil))
                for index in indices {
                    for column in 0..<4 {
                        XCTAssertLessThan(simd_distance(first.modelSpaceTransforms[index][column],
                                                       skin.pose.modelSpaceTransforms[index][column]), 0.0001)
                    }
                }
                for side in ["left", "right"] {
                    for (start, end) in [("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                        let firstIndex = try XCTUnwrap(skin.motion.semanticJointIndices[side + start])
                        let secondIndex = try XCTUnwrap(skin.motion.semanticJointIndices[side + end])
                        let before = skin.motion.restPose.modelSpaceTransforms[firstIndex].columns.3
                            - skin.motion.restPose.modelSpaceTransforms[secondIndex].columns.3
                        let actual = try simd_distance(position(skin, side + start), position(skin, side + end))
                        XCTAssertEqual(actual, simd_length(SIMD3(before.x, before.y, before.z)), accuracy: 0.004)
                    }
                }
                XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose)
                    - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.00001)
            }
        }
    }

    func testArmBlendIsContinuousAcrossSpeedAndTurnEdges() throws {
        let (player, skin) = try prepare()
        let indices = try armIndices(skin.motion)
        for (speed, turn) in [(Float(0.08), Float(0)), (0.40, 0), (1.35, 0), (2.25, 0),
                              (0.65, 180), (1.30, 180), (3.0, 38), (3.0, 150)] {
            var first: ReplaySkinnedAthleteMotion.Pose?
            for offset: Float in [-0.001, 0.001] {
                XCTAssertTrue(skin.update(at: 13.4, track: player,
                                          locomotion: locomotion(player, at: 13.4, speed: speed + offset, turn: turn + offset),
                                          lookTarget: nil, ballAction: nil))
                if let first {
                    for index in indices {
                        XCTAssertLessThan(simd_distance(first.translations[index], skin.pose.translations[index]), 0.003)
                        XCTAssertGreaterThan(abs(simd_dot(first.rotations[index].vector, skin.pose.rotations[index].vector)), 0.999)
                    }
                }
                first = skin.pose
            }
        }
    }

    func testPartialArmBlendsRemainContinuousAcrossEveryGaitPhase() throws {
        let (player, skin) = try prepare()
        let indices = try armIndices(skin.motion)
        for (speed, turn) in [(Float(0.20), Float(0)), (0.35, 0), (1.55, 0), (1.80, 0),
                              (2.10, 0), (3.0, 70), (3.0, 100), (3.0, 130)] {
            var previous: ReplaySkinnedAthleteMotion.Pose?
            for time in stride(from: 11.0, through: 15.0, by: 1.0 / 120) {
                XCTAssertTrue(skin.update(at: time, track: player,
                                          locomotion: locomotion(player, at: time, speed: speed, turn: turn),
                                          lookTarget: nil, ballAction: nil))
                if let previous {
                    for index in indices {
                        XCTAssertGreaterThan(abs(simd_dot(previous.rotations[index].vector,
                                                          skin.pose.rotations[index].vector)), 0.995,
                                             "Arm rotation snapped at \(time), speed \(speed), turn \(turn)")
                        XCTAssertLessThan(simd_distance(previous.modelSpaceTransforms[index].columns.3,
                                                       skin.pose.modelSpaceTransforms[index].columns.3), 0.07,
                                          "Arm joint jumped at \(time), speed \(speed), turn \(turn)")
                    }
                }
                previous = skin.pose
            }
        }
    }
}
