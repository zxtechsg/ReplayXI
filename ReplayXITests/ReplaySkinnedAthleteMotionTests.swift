import Foundation
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySkinnedAthleteMotionTests: XCTestCase {
    private let semanticNames = [
        "hips", "spine", "chest", "neck", "head", "leftHip", "rightHip",
        "leftKnee", "rightKnee", "leftAnkle", "rightAnkle", "leftToe", "rightToe",
        "leftShoulder", "rightShoulder", "leftElbow", "rightElbow", "leftWrist", "rightWrist"
    ]

    private func fixture() -> [String: Any] {
        let firstNames = ["Root", "Root/Spine", "Root/Spine/Chest", "Root/Spine/Chest/Neck", "Root/Spine/Chest/Neck/Head"]
        let names = (0..<80).map { $0 < firstNames.count ? firstNames[$0] : "Root/Joint\($0)" }
        var joints: [[String: Any]] = []
        for index in 0..<80 {
            let parent: Int = index == 0 ? -1 : (index < 5 ? index - 1 : 0)
            let translation: [Double] = [0, index == 0 ? 1 : 0.1, 0]
            let rotation: [Double] = [0, 0, 0, 1]
            let scale: [Double] = [1, 1, 1]
            var joint: [String: Any] = [:]
            joint["name"] = names[index]
            joint["sourceName"] = "Source\(index)"
            joint["parentIndex"] = parent
            joint["translation"] = translation
            joint["rotation"] = rotation
            joint["scale"] = scale
            joint["localRightAxis"] = [1.0, 0.0, 0.0]
            joint["localUpAxis"] = [0.0, 1.0, 0.0]
            joint["localForwardAxis"] = [0.0, 0.0, 1.0]
            joints.append(joint)
        }
        func clip(_ id: String) -> [String: Any] {
            var frames: [[String: Any]] = []
            let times: [Double] = [0, 0.5, 1]
            for time in times {
                var translations: [[Double]] = []
                for index in 0..<80 {
                    translations.append([0, index == 0 ? 1 : 0.1, 0])
                }
                var rotations: [[Double]] = Array(repeating: [0, 0, 0, 1], count: 80)
                if id == "run", time == 0.5 {
                    translations[1][0] = 2
                    rotations[2] = [0, sin(Double.pi / 4), 0, cos(Double.pi / 4)]
                }
                let scales: [[Double]] = Array(repeating: [1, 1, 1], count: 80)
                let frame: [String: Any] = ["time": time, "translations": translations,
                                            "rotations": rotations, "scales": scales]
                frames.append(frame)
            }
            return ["id": id, "durationSeconds": 1.0, "fps": 2, "frames": frames]
        }
        return [
            "schemaVersion": 1, "sourceCommit": "synthetic-test-only", "joints": joints,
            "semanticJoints": Dictionary(uniqueKeysWithValues: semanticNames.enumerated().map { ($0.element, names[$0.offset]) }),
            "clips": [clip("idle"), clip("run")],
            "geometry": ["jointCount": 80, "nominalHeight": 1.8, "restMinY": -0.02],
            "numberAnchors": ["joint": names[2], "front": [0.0, 0.0, 0.2], "back": [0.0, 0.0, -0.15]]
        ]
    }

    private func data(_ document: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    private func mutateJoint(_ document: inout [String: Any], index: Int, _ mutation: (inout [String: Any]) -> Void) {
        var joints = document["joints"] as! [[String: Any]]
        mutation(&joints[index])
        document["joints"] = joints
    }

    private func mutateFrame(_ document: inout [String: Any], clip: Int = 1, frame: Int = 0,
                             _ mutation: (inout [String: Any]) -> Void) {
        var clips = document["clips"] as! [[String: Any]]
        var frames = clips[clip]["frames"] as! [[String: Any]]
        mutation(&frames[frame])
        clips[clip]["frames"] = frames
        document["clips"] = clips
    }

    func testDecoderRejectsVersionsCountsAndInvalidParentTopology() throws {
        var document = fixture()
        document["schemaVersion"] = 2
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
        document = fixture()
        document["joints"] = Array((document["joints"] as! [[String: Any]]).dropLast())
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
        for parent in [-1, 2, 79] {
            document = fixture()
            mutateJoint(&document, index: 1) { $0["parentIndex"] = parent }
            XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
        }
        document = fixture()
        mutateJoint(&document, index: 2) { $0["name"] = "Root/Spine" }
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
    }

    func testDecoderRejectsBadVectorsQuaternionNormScaleAndAxes() throws {
        for (key, value) in [("translation", [1.0, 2.0]), ("rotation", [0.0, 0.0, 0.0, 0.0]),
                             ("scale", [1.0, -1.0, 1.0]), ("localUpAxis", [1.0, 0.0, 0.0])] {
            var document = fixture()
            mutateJoint(&document, index: 1) { $0[key] = value }
            XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)), key)
        }
        let overflowJSON = String(data: try data(fixture()), encoding: .utf8)!
            .replacingOccurrences(of: "\"durationSeconds\":1", with: "\"durationSeconds\":1e999")
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: Data(overflowJSON.utf8)))
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: Data(repeating: 0, count: 4 * 1_024 * 1_024 + 1)))
    }

    func testDecoderRejectsMissingClipBadDurationOrderAndSourceRootTravel() throws {
        var document = fixture()
        document["clips"] = Array((document["clips"] as! [[String: Any]]).dropLast())
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
        document = fixture()
        mutateFrame(&document, frame: 1) { $0["time"] = 0 }
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
        document = fixture()
        mutateFrame(&document, frame: 2) { $0["time"] = 0.9 }
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
        document = fixture()
        mutateFrame(&document) {
            var values = $0["translations"] as! [[Double]]
            values[0][0] = 1
            $0["translations"] = values
        }
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
        document = fixture()
        mutateFrame(&document) { $0["rotations"] = [[0.0, 0.0, 0.0, 1.0]] }
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
    }

    func testDecoderRejectsUnknownSemanticAndJerseyBindings() throws {
        var document = fixture()
        var semantics = document["semanticJoints"] as! [String: String]
        semantics["head"] = "Missing"
        document["semanticJoints"] = semantics
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
        document = fixture()
        var anchors = document["numberAnchors"] as! [String: Any]
        anchors["joint"] = "Root"
        document["numberAnchors"] = anchors
        XCTAssertThrowsError(try ReplaySkinnedAthleteMotion(data: data(document)))
    }

    func testInterpolationAndModelSpaceJerseyAnchorsUseSameHierarchy() throws {
        let motion = try ReplaySkinnedAthleteMotion(data: data(fixture()))
        var pose = motion.makePoseBuffer()
        motion.sample(clip: .run, at: 0.5, looping: false, into: &pose)
        XCTAssertEqual(pose.translations[1].x, 2, accuracy: 0.000_01)
        let front = pose.modelSpaceTransforms[motion.numberAnchors.jointIndex] * SIMD4(motion.numberAnchors.front, 1)
        XCTAssertEqual(front.x, 2.2, accuracy: 0.000_01)
        XCTAssertEqual(front.y, 1.2, accuracy: 0.000_01)
        XCTAssertEqual(front.z, 0, accuracy: 0.000_01)
        let chestBefore = pose.modelSpaceTransforms[2]
        pose.rotations[3] = simd_quatf(angle: .pi / 3, axis: [0, 1, 0])
        motion.rebuildModelSpaceTransforms(in: &pose)
        XCTAssertEqual(pose.modelSpaceTransforms[2].columns.3, chestBefore.columns.3)
        XCTAssertEqual(motion.geometry.soleOffsetMetres, 0.02, accuracy: 0.000_01)
    }

    func testQuaternionInterpolationTakesShortPathAcrossSignedAngles() throws {
        var document = fixture()
        for (index, angle) in [(0, 170.0), (1, -170.0)] {
            mutateFrame(&document, frame: index) {
                var rotations = $0["rotations"] as! [[Double]]
                rotations[2] = [0, sin(angle * .pi / 360), 0, cos(angle * .pi / 360)]
                $0["rotations"] = rotations
            }
        }
        let motion = try ReplaySkinnedAthleteMotion(data: data(document))
        var pose = motion.makePoseBuffer()
        motion.sample(clip: .run, at: 0.25, looping: false, into: &pose)
        let forward = pose.rotations[2].act(SIMD3<Float>(0, 0, 1))
        XCTAssertEqual(forward.z, -1, accuracy: 0.000_1)
        XCTAssertEqual(forward.x, 0, accuracy: 0.000_1)
        XCTAssertEqual(simd_length(pose.rotations[2].vector), 1, accuracy: 0.000_01)
    }

    func testRandomSeeksAreDeterministicAndClipLoopingHandlesNegativeTime() throws {
        let motion = try ReplaySkinnedAthleteMotion(data: data(fixture()))
        var pose = motion.makePoseBuffer()
        motion.sample(time: 9.25, locomotionEffort: 0.14, gaitPhase: 1.7, into: &pose)
        let expected = pose
        for time in [30.0, 0.0, 1.7, -3, 200] {
            motion.sample(time: time, locomotionEffort: 0.6, gaitPhase: Float(time), into: &pose)
        }
        motion.sample(time: 9.25, locomotionEffort: 0.14, gaitPhase: 1.7, into: &pose)
        XCTAssertEqual(pose.translations, expected.translations)
        XCTAssertEqual(pose.rotations.map(\.vector), expected.rotations.map(\.vector))
        XCTAssertEqual(pose.scales, expected.scales)
        motion.sample(clip: .run, at: -0.25, into: &pose)
        let negative = pose.translations
        motion.sample(clip: .run, at: 0.75, into: &pose)
        XCTAssertEqual(pose.translations, negative)
    }

    func testRunPhaseIsIndependentOfClockAndZeroEffortMatchesIdle() throws {
        let motion = try ReplaySkinnedAthleteMotion(data: data(fixture()))
        var pose = motion.makePoseBuffer(), comparison = motion.makePoseBuffer()
        motion.sample(time: 4, locomotionEffort: 1, gaitPhase: .pi, into: &pose)
        motion.sample(time: 700, locomotionEffort: 1, gaitPhase: .pi, into: &comparison)
        XCTAssertEqual(pose.translations, comparison.translations)
        XCTAssertEqual(pose.translations[1].x, 2, accuracy: 0.000_01)
        motion.sample(time: 0.25, locomotionEffort: 0, gaitPhase: .pi, into: &pose)
        motion.sample(clip: .idle, at: 0.25, into: &comparison)
        XCTAssertEqual(pose.translations, comparison.translations)
        XCTAssertEqual(pose.rotations.map(\.vector), comparison.rotations.map(\.vector))
    }

    func testInvalidRuntimeSamplesStayFiniteAndReusableBuffersKeepStorage() throws {
        let motion = try ReplaySkinnedAthleteMotion(data: data(fixture()))
        var pose = motion.makePoseBuffer()
        motion.sample(time: 0, locomotionEffort: 0, gaitPhase: 0, into: &pose)
        let translationAddress = pose.translations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        let rotationAddress = pose.rotations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        let matrixAddress = pose.modelSpaceTransforms.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        for time in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            motion.sample(time: time, locomotionEffort: .nan, gaitPhase: .infinity, into: &pose)
            XCTAssertTrue(pose.translations.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            XCTAssertTrue(pose.rotations.allSatisfy { abs(simd_length_squared($0.vector) - 1) < 0.000_1 })
        }
        XCTAssertEqual(pose.translations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, translationAddress)
        XCTAssertEqual(pose.rotations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, rotationAddress)
        XCTAssertEqual(pose.modelSpaceTransforms.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, matrixAddress)
    }

    func testActualRocketboxResourceDecodesAndProducesFiniteSeekablePoses() throws {
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let staged = projectRoot.appendingPathComponent(".codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/ReplayXIRocketboxMotion.json")
        let url = Bundle.main.url(forResource: "ReplayXIRocketboxMotion", withExtension: "json") ?? staged
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Rocketbox motion asset is not staged in this environment") }
        let motion = try ReplaySkinnedAthleteMotion(data: Data(contentsOf: url))
        XCTAssertEqual(motion.joints.count, 80)
        XCTAssertEqual(motion.footContacts.count, 2)
        XCTAssertEqual(motion.duration(of: .run), 0.6, accuracy: 0.000_01)
        var pose = motion.makePoseBuffer()
        for time in stride(from: 0.0, through: 32.0, by: 0.37) {
            motion.sample(time: time, locomotionEffort: 0.5, gaitPhase: Float(time * 4), into: &pose)
            for matrix in pose.modelSpaceTransforms {
                for column in 0..<4 {
                    XCTAssertTrue((0..<4).allSatisfy { matrix[column][$0].isFinite })
                }
            }
            XCTAssertEqual(pose.translations[0].x, 0, accuracy: 0.001)
            XCTAssertEqual(pose.translations[0].z, 0, accuracy: 0.001)
        }
    }

    func testPhaseSamplingMatchesDirectClipOracleAcrossRigsAndSeekOrder() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let rigs: [(String, ReplaySkinnedAthleteMotion.RigProfile)] = [
            ("ReplayXITripoMotion", .tripo52), ("ReplayXIRocketboxMotion", .rocketbox)
        ]
        func shortestSlerp(_ start: simd_quatf, _ end: simd_quatf, _ weight: Float) -> simd_quatf {
            let target = simd_dot(start.vector, end.vector) < 0 ? simd_quatf(vector: -end.vector) : end
            return simd_normalize(simd_slerp(start, target, weight))
        }
        for (resource, profile) in rigs {
            let url = repository.appendingPathComponent("ReplayXI/Resources/Players/\(resource).json")
            let motion = try ReplaySkinnedAthleteMotion(data: Data(contentsOf: url), profile: profile)
            let slowOracle: ReplaySkinnedAthleteMotion?
            let active: ReplaySkinnedAthleteMotion
            if profile == .rocketbox {
                let slowData = try Data(contentsOf: repository.appendingPathComponent(
                    "ReplayXI/Resources/Players/ReplayXIRocketboxSlowRun.json"))
                active = try motion.addingSlowRun(data: slowData,
                    baseMotionSHA256: ReplaySkinnedAthleteProvider.motionSHA256)
                slowOracle = try ReplaySkinnedAthleteMotion(data: Data(contentsOf:
                    repository.appendingPathComponent("ReplayXITests/Fixtures/Generated/ReplayXIRocketboxSlowRun150.json")))
            } else {
                active = motion
                slowOracle = nil
            }
            func blend(_ first: ReplaySkinnedAthleteMotion.Pose, _ second: ReplaySkinnedAthleteMotion.Pose,
                       weight: Float) -> ReplaySkinnedAthleteMotion.Pose {
                var result = first
                for index in motion.joints.indices {
                    result.translations[index] = first.translations[index]
                        + (second.translations[index] - first.translations[index]) * weight
                    result.rotations[index] = shortestSlerp(first.rotations[index], second.rotations[index], weight)
                    result.scales[index] = first.scales[index]
                        + (second.scales[index] - first.scales[index]) * weight
                }
                motion.rebuildModelSpaceTransforms(in: &result)
                return result
            }
            var reused = active.makePoseBuffer()
            // Forward, reverse and nonadjacent seeks exercise the same absolute-time path.
            for (time, phase) in [
                (0.0, Float(0)), (0.13, Float(0.7)), (0.8, Float(2 * Double.pi)),
                (3.2, Float(18.4)), (1.1, Float(-2.9)), (-0.7, Float(-17.1)),
                (84.2, Float(0.000_01)), (0.0, Float.nan), (0.3, Float.infinity),
                (0.2, -Float.leastNonzeroMagnitude), (3.2, Float(18.4))
            ] {
                for effort: Float in [0, 0.12, 0.8] {
                    let finitePhase = phase.isFinite ? Double(phase) : 0
                    let remainder = finitePhase.truncatingRemainder(dividingBy: 2 * .pi)
                    let wrapped = remainder < 0 ? remainder + 2 * .pi : remainder
                    let runTime = wrapped / (2 * .pi) * motion.duration(of: .run)
                    var idle = motion.makePoseBuffer(), run = motion.makePoseBuffer()
                    motion.sample(clip: .idle, at: time, into: &idle)
                    motion.sample(clip: .run, at: runTime, into: &run)
                    let linear = min(max((effort - 0.02) / 0.20, 0), 1)
                    let weight = linear * linear * (3 - 2 * linear)
                    for slowWeight: Float in [0, 0.4, 1] {
                        var blendedRun = run
                        if slowWeight > 0, let slowOracle {
                            var slow = slowOracle.makePoseBuffer()
                            let slowTime = wrapped / (2 * .pi) * slowOracle.duration(of: .run)
                            slowOracle.sample(clip: .run, at: slowTime, into: &slow)
                            blendedRun = slowWeight >= 1 ? slow : blend(run, slow, weight: slowWeight)
                        }
                        let expected = weight <= 0 ? idle
                            : weight >= 1 ? blendedRun : blend(idle, blendedRun, weight: weight)
                        active.sample(time: time, locomotionEffort: effort, gaitPhase: phase,
                                      slowRunWeight: slowWeight, into: &reused)
                        XCTAssertEqual(reused.translations, expected.translations, resource)
                        XCTAssertEqual(reused.rotations.map(\.vector), expected.rotations.map(\.vector), resource)
                        XCTAssertEqual(reused.scales, expected.scales, resource)
                        XCTAssertEqual(reused.modelSpaceTransforms, expected.modelSpaceTransforms, resource)
                    }
                }
            }
        }
    }
}
