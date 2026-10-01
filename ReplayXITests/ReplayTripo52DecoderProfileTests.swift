import Foundation
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayTripo52DecoderProfileTests: XCTestCase {
    private let semanticNames = [
        "hips", "spine", "chest", "neck", "head", "leftHip", "rightHip",
        "leftKnee", "rightKnee", "leftAnkle", "rightAnkle", "leftToe", "rightToe",
        "leftShoulder", "rightShoulder", "leftElbow", "rightElbow", "leftWrist", "rightWrist"
    ]

    private func motionDocument(jointCount: Int) -> [String: Any] {
        let firstNames = ["Root", "Root/Spine", "Root/Spine/Chest", "Root/Spine/Chest/Neck",
                          "Root/Spine/Chest/Neck/Head"]
        var names: [String] = []
        names.reserveCapacity(jointCount)
        for index in 0..<jointCount {
            names.append(index < firstNames.count ? firstNames[index] : "Root/Joint\(index)")
        }
        var joints: [[String: Any]] = []
        joints.reserveCapacity(jointCount)
        for index in 0..<jointCount {
            let parentIndex = index == 0 ? -1 : (index < 5 ? index - 1 : 0)
            let yTranslation: Double = index == 0 ? 1.0 : 0.1
            let translation: [Double] = [0.0, yTranslation, 0.0]
            let rotation: [Double] = [0.0, 0.0, 0.0, 1.0]
            let scale: [Double] = [1.0, 1.0, 1.0]
            let rightAxis: [Double] = [1.0, 0.0, 0.0]
            let upAxis: [Double] = [0.0, 1.0, 0.0]
            let forwardAxis: [Double] = [0.0, 0.0, 1.0]
            var joint: [String: Any] = [:]
            joint["name"] = names[index]
            joint["sourceName"] = "Source\(index)"
            joint["parentIndex"] = parentIndex
            joint["translation"] = translation
            joint["rotation"] = rotation
            joint["scale"] = scale
            joint["localRightAxis"] = rightAxis
            joint["localUpAxis"] = upAxis
            joint["localForwardAxis"] = forwardAxis
            joints.append(joint)
        }
        func clip(_ id: String) -> [String: Any] {
            let translations = (0..<jointCount).map { index in
                [0.0, index == 0 ? 1.0 : 0.1, 0.0]
            }
            let rotations = Array(repeating: [0.0, 0.0, 0.0, 1.0], count: jointCount)
            let scales = Array(repeating: [1.0, 1.0, 1.0], count: jointCount)
            var frames: [[String: Any]] = []
            for time in [0.0, 1.0] {
                let frame: [String: Any] = ["time": time, "translations": translations,
                                            "rotations": rotations, "scales": scales]
                frames.append(frame)
            }
            return ["id": id, "durationSeconds": 1.0, "fps": 1.0, "frames": frames]
        }
        var semantics: [String: String] = [:]
        for index in semanticNames.indices { semantics[semanticNames[index]] = names[index] }
        let geometry: [String: Any] = ["jointCount": jointCount, "nominalHeight": 1.8, "restMinY": -0.02]
        let anchors: [String: Any] = ["joint": names[2], "front": [0.0, 0.0, 0.2],
                                      "back": [0.0, 0.0, -0.15]]
        let clips: [[String: Any]] = [clip("idle"), clip("run")]
        return ["schemaVersion": 1, "sourceCommit": "synthetic-tripo-profile-test",
                "joints": joints, "semanticJoints": semantics, "clips": clips,
                "geometry": geometry, "numberAnchors": anchors]
    }

    private func encoded(_ document: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    private func contactDocument(sourceVertexCount: Int, jointCount: Int = 52,
                                 vertexCount: Int = 8) -> [String: Any] {
        var vertices: [[String: Any]] = []
        vertices.reserveCapacity(vertexCount)
        for index in 0..<vertexCount {
            let position: [Double] = [0.0, 0.0, 0.0]
            let joints: [Int] = [0]
            let weights: [Double] = [1.0]
            vertices.append(["id": "probe\(index)", "position": position,
                             "joints": joints, "weights": weights])
        }
        return ["schemaVersion": 1, "assetSHA256": "asset-test", "motionSHA256": "motion-test",
                "sourceVertexCount": sourceVertexCount, "jointCount": jointCount,
                "paddingMetres": 0.006, "vertices": vertices]
    }

    func testRigProfilesAreExactAndKeepRocketboxDefault() throws {
        XCTAssertEqual(ReplaySkinnedAthleteMotion.expectedJointCount, 80)
        let data52 = try encoded(motionDocument(jointCount: 52))
        let data80 = try encoded(motionDocument(jointCount: 80))

        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data52))
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data80, profile: .tripo52))

        let motion = try ReplaySkinnedAthleteMotion(data: data52, profile: .tripo52)
        XCTAssertEqual(motion.rigProfile, .tripo52)
        XCTAssertEqual(motion.joints.count, 52)
        var pose = motion.makePoseBuffer()
        motion.sample(clip: .run, at: 0.5, into: &pose)
        XCTAssertEqual(pose.translations.count, 52)
        XCTAssertEqual(pose.modelSpaceTransforms.count, 52)
        XCTAssertThrowsError(try motion.addingSlowRun(data: Data(), baseMotionSHA256: "unused"))
    }

    func testTripoProfileRejectsMismatchedClipJointArrays() throws {
        var document = motionDocument(jointCount: 52)
        var clips = document["clips"] as! [[String: Any]]
        var frames = clips[1]["frames"] as! [[String: Any]]
        frames[0]["rotations"] = Array(repeating: [0.0, 0.0, 0.0, 1.0], count: 51)
        clips[1]["frames"] = frames
        document["clips"] = clips
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: encoded(document), profile: .tripo52))
    }

    func testTripoContactProfilesUsePinnedCountsAndLegacyLimits() throws {
        let motion = try ReplaySkinnedAthleteMotion(
            data: encoded(motionDocument(jointCount: 52)), profile: .tripo52
        )
        let nearPayload = try encoded(contactDocument(sourceVertexCount: 9_075))
        let lowPayload = try encoded(contactDocument(sourceVertexCount: 3_269))
        let nearProfile = ReplaySkinnedAthleteContactSurface.Profile.tripoNear(sourceVertexCount: 9_075)
        let lowProfile = ReplaySkinnedAthleteContactSurface.Profile.tripoLow(sourceVertexCount: 3_269)
        let profilesAndPayloads: [(ReplaySkinnedAthleteContactSurface.Profile, Data)] = [
            (nearProfile, nearPayload), (lowProfile, lowPayload)
        ]
        for (profile, payload) in profilesAndPayloads {
            let surface = try ReplaySkinnedAthleteContactSurface(
                data: payload, motion: motion, assetSHA256: "asset-test",
                motionSHA256: "motion-test", profile: profile
            )
            XCTAssertEqual(surface.vertexCount, 8)
            XCTAssertEqual(surface.influenceCount, 8)
        }
        XCTAssertThrowsError(try ReplaySkinnedAthleteContactSurface(
            data: nearPayload, motion: motion, assetSHA256: "asset-test",
            motionSHA256: "motion-test", profile: .near
        ))
        XCTAssertThrowsError(try ReplaySkinnedAthleteContactSurface(
            data: encoded(contactDocument(sourceVertexCount: 5_012)), motion: motion,
            assetSHA256: "asset-test", motionSHA256: "motion-test", profile: .near
        ))
        for count in [0, 12_001] {
            XCTAssertThrowsError(try ReplaySkinnedAthleteContactSurface(
                data: nearPayload, motion: motion, assetSHA256: "asset-test",
                motionSHA256: "motion-test", profile: .tripoNear(sourceVertexCount: count)
            ))
        }
        XCTAssertThrowsError(try ReplaySkinnedAthleteContactSurface(
            data: encoded(contactDocument(sourceVertexCount: 9_074)), motion: motion,
            assetSHA256: "asset-test", motionSHA256: "motion-test",
            profile: .tripoNear(sourceVertexCount: 9_075)
        ))
    }

    func testTripoContactProfilesKeepThe512ProbeAnd256KBBounds() throws {
        let motion = try ReplaySkinnedAthleteMotion(
            data: encoded(motionDocument(jointCount: 52)), profile: .tripo52
        )
        let tooMany = try encoded(contactDocument(sourceVertexCount: 9_075, vertexCount: 513))
        XCTAssertThrowsError(try ReplaySkinnedAthleteContactSurface(
            data: tooMany, motion: motion, assetSHA256: "asset-test",
            motionSHA256: "motion-test", profile: .tripoNear(sourceVertexCount: 9_075)
        ))
        XCTAssertThrowsError(try ReplaySkinnedAthleteContactSurface(
            data: Data(repeating: 0x20, count: 256 * 1_024 + 1), motion: motion,
            assetSHA256: "asset-test", motionSHA256: "motion-test",
            profile: .tripoLow(sourceVertexCount: 3_269)
        ))
    }
}
