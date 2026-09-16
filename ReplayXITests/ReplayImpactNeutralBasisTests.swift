import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayImpactNeutralBasisTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func prepare() throws -> (PlayerTrack, PlayerRagdollCue, ReplaySkinnedAthleteInstance) {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let cue = try XCTUnwrap(PlayerRagdollCue.authoredDemo(for: scenario))
        let player = try XCTUnwrap(scenario.player(id: cue.playerID))
        return (player, cue, try ReplaySkinnedAthleteProvider.make(for: player))
    }

    private func position(_ matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    private func assertRotation(_ actual: simd_quatf, _ expected: simd_quatf, _ message: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(simd_length(actual.vector), 1, accuracy: 0.00001, message, file: file, line: line)
        XCTAssertEqual(simd_length(expected.vector), 1, accuracy: 0.00001, message, file: file, line: line)
        XCTAssertGreaterThan(abs(simd_dot(actual.vector, expected.vector)), 0.99999,
                             message, file: file, line: line)
    }

    private func exported(_ name: String, time: Double, pose: ReplaySkinnedAthleteMotion.Pose,
                          motion: ReplaySkinnedAthleteMotion) -> [String: Any] {
        ["name": name, "time": time, "groundOffset": -motion.geometry.restMinY,
         "translations": pose.translations.map { [$0.x, $0.y, $0.z] },
         "rotations": pose.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] },
         "scales": pose.scales.map { [$0.x, $0.y, $0.z] }]
    }

    private func attach(_ poses: [[String: Any]], report: [[String: Any]], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["samples": poses, "report": report],
                                              options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNeutralImpactKeepsTheAuditedBootAxesAndArmNeutralBasis() throws {
        let (_, cue, skin) = try prepare()
        let motion = skin.motion
        var retarget = try XCTUnwrap(ReplaySkinnedAthleteImpactPose(motion: motion,
                                                                  contactSurface: skin.contactSurface))
        let neutral = PlayerRagdollPlayback.pose(for: cue, at: cue.impactTime)
        XCTAssertEqual(neutral.fallAngle, 0)
        XCTAssertEqual(neutral.leftHip + neutral.rightHip + neutral.leftKnee + neutral.rightKnee
                        + neutral.leftAnkle + neutral.rightAnkle, 0)
        var pose = motion.makePoseBuffer()
        retarget.apply(neutral, influence: 1, motion: motion, to: &pose)
        motion.rebuildModelSpaceTransforms(in: &pose)
        var report: [[String: Any]] = []
        for side in ["left", "right"] {
            let ankle = try XCTUnwrap(motion.semanticJointIndices[side + "Ankle"])
            let rest = simd_normalize(simd_quatf(motion.restPose.modelSpaceTransforms[ankle]))
            let actual = simd_normalize(simd_quatf(pose.modelSpaceTransforms[ankle]))
            let up = motion.joints[ankle].localUpAxis
            let forward = motion.joints[ankle].localForwardAxis
            XCTAssertGreaterThan(rest.act(up).y, 0.999, "The source asset defines an upright sole basis")
            XCTAssertGreaterThan(rest.act(forward).z, 0.999, "The source boot defines pitch-forward +Z")
            assertRotation(actual, rest, "Neutral \(side) ankle must retain the asset's rest basis")
            XCTAssertGreaterThan(actual.act(up).y, 0.999, "Neutral \(side) sole must face up")
            XCTAssertGreaterThan(actual.act(forward).z, 0.999, "Neutral \(side) toe direction must face forward")
            report.append(["side": side, "restAgreement": abs(simd_dot(actual.vector, rest.vector)),
                           "actualUpY": actual.act(up).y, "actualForwardZ": actual.act(forward).z])

            // The arm branch intentionally rotates the source T-pose downward.
            // It must keep that different, already-correct neutral mapping.
            let elbow = try XCTUnwrap(motion.semanticJointIndices[side + "Elbow"])
            let wrist = try XCTUnwrap(motion.semanticJointIndices[side + "Wrist"])
            let lower = position(motion.restPose.modelSpaceTransforms[wrist])
                - position(motion.restPose.modelSpaceTransforms[elbow])
            let expectedWrist = simd_normalize(simd_quatf(from: simd_normalize(lower), to: [0, -1, 0])
                * simd_quatf(motion.restPose.modelSpaceTransforms[wrist]))
            assertRotation(simd_normalize(simd_quatf(pose.modelSpaceTransforms[wrist])), expectedWrist,
                           "Neutral \(side) wrist control must preserve the arm-specific basis")
        }
        try attach([exported("neutral-impact-basis", time: cue.impactTime, pose: pose, motion: motion)],
                   report: report, name: "ReplayXI-Impact-NeutralBootBasis.json")
    }

    func testAuthoredImpactBootRotationsComposeWithTheirRestBasis() throws {
        let (player, cue, skin) = try prepare()
        var poses: [[String: Any]] = []
        var report: [[String: Any]] = []
        for (name, elapsed) in [("fall-boot-basis", 0.25), ("land-boot-basis", 0.55),
                                ("settled-boot-basis", 1.5)] {
            let time = cue.impactTime + elapsed
            let sample = try XCTUnwrap(PlayerRagdollPlayback.sample(for: cue, at: time))
            XCTAssertEqual(sample.influence, 1)
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                      lookTarget: nil, ballAction: nil, impact: sample))
            let impact = sample.pose
            let body = simd_quatf(angle: impact.fallAngle, axis: impact.fallAxis)
                * simd_quatf(angle: impact.bodyTwist, axis: [0, 1, 0])
            for side in ["left", "right"] {
                let hip = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Hip"])
                let ankle = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Ankle"])
                let negativeSide = position(skin.motion.restPose.modelSpaceTransforms[hip]).x < 0
                let end = body
                    * simd_quatf(angle: negativeSide ? impact.leftHip : impact.rightHip, axis: [1, 0, 0])
                    * simd_quatf(angle: negativeSide ? impact.leftKnee : impact.rightKnee, axis: [1, 0, 0])
                    * simd_quatf(angle: negativeSide ? impact.leftAnkle : impact.rightAnkle, axis: [1, 0, 0])
                let rest = simd_quatf(skin.motion.restPose.modelSpaceTransforms[ankle])
                let expected = simd_normalize(end * rest)
                let actual = simd_normalize(simd_quatf(skin.pose.modelSpaceTransforms[ankle]))
                assertRotation(actual, expected, "\(name) \(side): authored ankle motion must retain neutral boot basis")
                report.append(["name": name, "side": side,
                               "expectedRotationAgreement": abs(simd_dot(actual.vector, expected.vector))])
            }
            poses.append(exported(name, time: time, pose: skin.pose, motion: skin.motion))
        }
        try attach(poses, report: report, name: "ReplayXI-Impact-AuthoredBootBasis.json")
    }

    func testZeroAndInvalidImpactInfluenceLeaveSourceSkinExactlyUnchanged() throws {
        let (player, cue, skin) = try prepare()
        let time = cue.impactTime + 0.55
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                  lookTarget: nil, ballAction: nil))
        let source = skin.pose
        var retarget = try XCTUnwrap(ReplaySkinnedAthleteImpactPose(motion: skin.motion,
                                                                  contactSurface: skin.contactSurface))
        for influence: Float in [0, -1, .nan, .infinity] {
            var pose = source
            retarget.apply(PlayerRagdollPlayback.pose(for: cue, at: time), influence: influence,
                           motion: skin.motion, to: &pose)
            XCTAssertEqual(pose.translations, source.translations)
            XCTAssertEqual(pose.rotations.map(\.vector), source.rotations.map(\.vector))
            XCTAssertEqual(pose.scales, source.scales)
            XCTAssertEqual(pose.modelSpaceTransforms, source.modelSpaceTransforms)
        }
    }

    func testProceduralImpactNeckBlendsToNeutralAsSmoothlyAsTheHead() throws {
        let (player, cue, _) = try prepare()
        let rig = try ReplayAthleteFactory.make(for: player, lod: .near)
        let neutral = PlayerRagdollPlayback.pose(for: cue, at: cue.impactTime)
        let start = simd_quatf(angle: 0.8, axis: [0, 1, 0])
        let identity = simd_quatf(real: 1, imag: .zero)
        for weight: Float in [0, 0.25, 0.5, 0.75, 1] {
            rig.joints[.neck].orientation = start
            rig.joints[.headRoot].orientation = start
            ReplayAthleteMotion.apply(ragdoll: neutral, influence: weight, to: rig.joints)
            let expected = simd_normalize(simd_slerp(start, identity, weight))
            assertRotation(rig.joints[.neck].orientation, expected,
                           "The neck must unwind gradually at influence \(weight), not snap only at 1")
            assertRotation(rig.joints[.headRoot].orientation, expected,
                           "The existing head target is a unit-identity control at influence \(weight)")
        }
    }
}
