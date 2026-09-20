import CryptoKit
import Foundation
import simd
import XCTest
@testable import ReplayXI

/// Supplemental source sampling only: not a contact/foot-force or FPS claim.
@MainActor
final class ReplaySlowRunMotion151Tests: XCTestCase {
    private typealias Motion = ReplaySkinnedAthleteMotion
    private typealias Pose = Motion.Pose
    private let baseHash = "d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4"
    private let slowHash = "865b7d45ce021731adb8b80febb89c39d5f71a42f284af10be3a601cad33890e"

    private struct Fixture {
        let base: Motion
        let added: Motion
        let slowOracle: Motion
        let supplemental: Data
    }

    private func fixture() throws -> Fixture {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let baseData = try Data(contentsOf: repository.appendingPathComponent("ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json"))
        let slowData = try Data(contentsOf: repository.appendingPathComponent("ReplayXI/Resources/Players/ReplayXIRocketboxSlowRun.json"))
        let probeData = try Data(contentsOf: repository.appendingPathComponent("ReplayXITests/Fixtures/Generated/ReplayXIRocketboxSlowRun150.json"))
        XCTAssertEqual(digest(baseData), baseHash)
        XCTAssertEqual(digest(slowData), slowHash)
        let base = try Motion(data: baseData)
        return try Fixture(base: base, added: base.addingSlowRun(data: slowData, baseMotionSHA256: baseHash),
                           slowOracle: Motion(data: probeData), supplemental: slowData)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func exact(_ a: Pose, _ b: Pose, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.translations, b.translations, file: file, line: line)
        XCTAssertEqual(a.scales, b.scales, file: file, line: line)
        XCTAssertEqual(a.rotations.map(\.vector), b.rotations.map(\.vector), file: file, line: line)
        XCTAssertEqual(a.modelSpaceTransforms, b.modelSpaceTransforms, file: file, line: line)
    }

    private func sample(_ motion: Motion, time: Double, effort: Float, phase: Float, slow: Float) -> Pose {
        var pose = motion.makePoseBuffer()
        motion.sample(time: time, locomotionEffort: effort, gaitPhase: phase,
                      slowRunWeight: slow, into: &pose)
        return pose
    }

    func testCompactSourceKeepsExactBaseRigIdleAndIndependentSlowRun() throws {
        let f = try fixture()
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: f.supplemental) as? [String: Any])
        XCTAssertNil(document["joints"])
        XCTAssertNil(document["clips"])
        XCTAssertNil(document["geometry"])
        XCTAssertNil(document["footContacts"])
        XCTAssertLessThan(f.supplemental.count, 200_000)
        XCTAssertTrue(try XCTUnwrap(document["license"] as? String).contains("Copyright (c) 2020 Microsoft"))
        XCTAssertFalse(f.base.hasSlowRun)
        XCTAssertTrue(f.added.hasSlowRun)
        XCTAssertEqual(f.base.jointNames, f.added.jointNames)
        XCTAssertEqual(f.base.semanticJointIndices, f.added.semanticJointIndices)
        XCTAssertEqual(f.base.geometry.restMinY, f.added.geometry.restMinY)
        XCTAssertEqual(f.base.numberAnchors.front, f.added.numberAnchors.front)
        XCTAssertEqual(f.base.numberAnchors.back, f.added.numberAnchors.back)
        exact(f.base.restPose, f.added.restPose)
        for phase: Float in [-20, -0.01, 0, 0.9, 3, 2 * .pi - 0.0001, 2 * .pi, 100] {
            for effort: Float in [0, 0.12, 0.22, 0.8] {
                exact(sample(f.added, time: -0.17, effort: effort, phase: phase, slow: 1),
                      sample(f.slowOracle, time: -0.17, effort: effort, phase: phase, slow: 0))
            }
        }
    }

    func testZeroInvalidOrUnavailableSlowRetainsExactFastAndSameWork() throws {
        let f = try fixture()
        for effort: Float in [0, 0.019, 0.12, 0.22, 0.8] {
            for time in [-0.4, 0, 0.27, 1.13, 8_000] {
                let phase = Float(time * 2.13)
                Motion.resetClipSampleCountsForTesting()
                let control = sample(f.base, time: time, effort: effort, phase: phase, slow: 0)
                let work = Motion.clipSampleCountsForTesting
                for weight: Float in [0, -1, .nan, .infinity, -.infinity] {
                    Motion.resetClipSampleCountsForTesting()
                    exact(control, sample(f.added, time: time, effort: effort, phase: phase, slow: weight))
                    XCTAssertEqual(Motion.clipSampleCountsForTesting, work)
                }
                Motion.resetClipSampleCountsForTesting()
                exact(control, sample(f.base, time: time, effort: effort, phase: phase, slow: 1))
                XCTAssertEqual(Motion.clipSampleCountsForTesting, work)
            }
        }
    }

    func testActualClipCountsAreOneTwoOrThreeOnlyForPositiveContributions() throws {
        let f = try fixture()
        let cases: [(Float, Float, Motion.ClipSampleCounts)] = [
            (0, 0.5, .init(idle: 1)),
            (0.8, 0, .init(fastRun: 1)),
            (0.12, 0, .init(idle: 1, fastRun: 1)),
            (0.8, 1, .init(slowRun: 1)),
            (0.12, 1, .init(idle: 1, slowRun: 1)),
            (0.8, 0.5, .init(fastRun: 1, slowRun: 1)),
            (0.12, 0.5, .init(idle: 1, fastRun: 1, slowRun: 1)),
        ]
        for (effort, slow, expected) in cases {
            Motion.resetClipSampleCountsForTesting()
            _ = sample(f.added, time: 0.37, effort: effort, phase: 1.1, slow: slow)
            XCTAssertEqual(Motion.clipSampleCountsForTesting, expected)
            XCTAssertLessThanOrEqual(Motion.clipSampleCountsForTesting.total, 3)
        }
    }

    func testThreeWayBlendUsesTheSameWholeBodyWeightBeforeIdle() throws {
        let f = try fixture()
        let time = 0.37
        let phase: Float = 1.17, effort: Float = 0.12, slowWeight: Float = 0.35
        let fast = sample(f.base, time: time, effort: 1, phase: phase, slow: 0)
        let slow = sample(f.slowOracle, time: time, effort: 1, phase: phase, slow: 0)
        var idle = f.base.makePoseBuffer()
        f.base.sample(clip: .idle, at: time, into: &idle)
        let mixed = sample(f.added, time: time, effort: effort, phase: phase, slow: slowWeight)
        let linear = min(max((effort - 0.02) / 0.20, 0), 1)
        let runWeight = linear * linear * (3 - 2 * linear)
        func slerp(_ a: simd_quatf, _ b: simd_quatf, _ weight: Float) -> simd_quatf {
            let signed = simd_dot(a.vector, b.vector) < 0 ? simd_quatf(vector: -b.vector) : b
            return simd_normalize(simd_slerp(a, signed, weight))
        }
        for index in f.base.joints.indices {
            let runT = fast.translations[index] + (slow.translations[index] - fast.translations[index]) * slowWeight
            let runS = fast.scales[index] + (slow.scales[index] - fast.scales[index]) * slowWeight
            let expectedT = idle.translations[index] + (runT - idle.translations[index]) * runWeight
            let expectedS = idle.scales[index] + (runS - idle.scales[index]) * runWeight
            let runQ = slerp(fast.rotations[index], slow.rotations[index], slowWeight)
            let expectedQ = slerp(idle.rotations[index], runQ, runWeight)
            XCTAssertEqual(mixed.translations[index], expectedT, "joint \(index)")
            XCTAssertEqual(mixed.scales[index], expectedS, "joint \(index)")
            XCTAssertEqual(mixed.rotations[index].vector, expectedQ.vector, "joint \(index)")
        }
    }

    func testWeightEndpointsAreContinuousAndSeekingIsExact() throws {
        let f = try fixture()
        func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
            let delta = simd_normalize(a.inverse * b)
            return 2 * atan2(simd_length(delta.imag), abs(delta.real)) * 180 / .pi
        }
        for effort: Float in [0.12, 0.8] {
            let start = sample(f.added, time: 0.73, effort: effort, phase: 2.13, slow: 0)
            let end = sample(f.added, time: 0.73, effort: effort, phase: 2.13, slow: 1)
            for epsilon: Float in [0.01, 0.001, 0.0001] {
                let entering = sample(f.added, time: 0.73, effort: effort, phase: 2.13, slow: epsilon)
                let leaving = sample(f.added, time: 0.73, effort: effort, phase: 2.13, slow: 1 - epsilon)
                for index in f.base.joints.indices {
                    // A geodesic source blend cannot traverse more than 180°;
                    // the small constant only covers float quaternion arithmetic.
                    XCTAssertLessThan(angle(start.rotations[index], entering.rotations[index]), 180 * epsilon + 0.002)
                    XCTAssertLessThan(angle(end.rotations[index], leaving.rotations[index]), 180 * epsilon + 0.002)
                    XCTAssertLessThan(simd_length(start.translations[index] - entering.translations[index]), epsilon + 0.000001)
                    XCTAssertLessThan(simd_length(end.translations[index] - leaving.translations[index]), epsilon + 0.000001)
                }
            }
            let original = sample(f.added, time: 0.73, effort: effort, phase: 2.13, slow: 0.39)
            var buffer = f.added.makePoseBuffer()
            for time in [9.0, -2, 0, 1_000, 0.73] {
                f.added.sample(time: time, locomotionEffort: effort,
                               gaitPhase: time == 0.73 ? 2.13 : Float(time), slowRunWeight: 0.39, into: &buffer)
            }
            exact(original, buffer)
        }
    }

    func testDeferredHierarchyMatchesSingleFinalRebuild() throws {
        let f = try fixture()
        let expected = sample(f.added, time: 0.19, effort: 0.12, phase: 5.13, slow: 0.6)
        var deferred = f.added.makePoseBuffer()
        let restMatrices = deferred.modelSpaceTransforms
        f.added.sample(time: 0.19, locomotionEffort: 0.12, gaitPhase: 5.13,
                       slowRunWeight: 0.6, rebuildingModelSpace: false, into: &deferred)
        XCTAssertEqual(deferred.modelSpaceTransforms, restMatrices)
        f.added.rebuildModelSpaceTransforms(in: &deferred)
        exact(expected, deferred)
    }

    func testProviderOptionalAdmissionFailsSoftWithoutChangingFastPoseOrWork() throws {
        let f = try fixture()
        var changed = try document(f.supplemental)
        // Still valid JSON and motion metadata; only its package digest differs.
        changed["license"] = "changed notice"
        let candidates: [Data?] = [
            nil, Data("not-json".utf8),
            Data(repeating: 0, count: Motion.maximumSlowRunPayloadBytes + 1),
            try data(changed),
        ]
        for candidate in candidates {
            let fallback = ReplaySkinnedAthleteProvider.addingOptionalSlowRun(to: f.base, data: candidate)
            XCTAssertFalse(fallback.hasSlowRun)
            for effort: Float in [0, 0.12, 0.8] {
                Motion.resetClipSampleCountsForTesting()
                let original = sample(f.base, time: 0.31, effort: effort, phase: 2.4, slow: 0)
                let originalWork = Motion.clipSampleCountsForTesting
                Motion.resetClipSampleCountsForTesting()
                exact(original, sample(fallback, time: 0.31, effort: effort, phase: 2.4, slow: 1))
                XCTAssertEqual(Motion.clipSampleCountsForTesting, originalWork)
            }
        }
        XCTAssertFalse(f.base.hasSlowRun)
    }

    func testProviderAcceptsHashLockedSupplementAndRetainsBaseValue() throws {
        let f = try fixture()
        let admitted = ReplaySkinnedAthleteProvider.addingOptionalSlowRun(to: f.base, data: f.supplemental)
        XCTAssertTrue(admitted.hasSlowRun)
        XCTAssertFalse(f.base.hasSlowRun)
        exact(f.base.restPose, admitted.restPose)
        exact(sample(admitted, time: 0.31, effort: 0.8, phase: 2.4, slow: 1),
              sample(f.slowOracle, time: 0.31, effort: 0.8, phase: 2.4, slow: 0))
    }

    private func document(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func data(_ document: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    func testSupplementRejectsWrongBaseSourceUnitsPhaseAndSize() throws {
        let f = try fixture()
        let original = try document(f.supplemental)
        let mutations: [(String, Any)] = [
            ("schemaVersion", 2), ("baseMotionSHA256", String(repeating: "0", count: 64)),
            ("sourceCommit", "different-source"), ("sourceClipSHA256", String(repeating: "0", count: 64)),
            ("jointCount", 79), ("units", "centimetres"), ("phaseOffsetRadians", 0.01),
        ]
        for (key, value) in mutations {
            var changed = original
            changed[key] = value
            XCTAssertThrowsError(try f.base.addingSlowRun(data: data(changed), baseMotionSHA256: baseHash), key)
        }
        var forged = original
        let wrongHash = String(repeating: "0", count: 64)
        forged["baseMotionSHA256"] = wrongHash
        // Matching caller/document strings do not override the actual base digest.
        XCTAssertThrowsError(try f.base.addingSlowRun(data: data(forged), baseMotionSHA256: wrongHash))
        XCTAssertThrowsError(try f.base.addingSlowRun(data: f.supplemental, baseMotionSHA256: wrongHash))
        XCTAssertThrowsError(try f.base.addingSlowRun(
            data: Data(repeating: 0, count: Motion.maximumSlowRunPayloadBytes + 1), baseMotionSHA256: baseHash))
        XCTAssertFalse(f.base.hasSlowRun)
    }

    func testSupplementUsesStrictFrameAndTransformValidation() throws {
        let f = try fixture()
        let original = try document(f.supplemental)
        let originalClip = try XCTUnwrap(original["clip"] as? [String: Any])
        let clipChanges: [(String, Any)] = [
            ("id", "idle"), ("durationSeconds", 0), ("fps", 121), ("frames", [] as [Any]),
        ]
        for (key, value) in clipChanges {
            var changed = original, clip = originalClip
            clip[key] = value; changed["clip"] = clip
            XCTAssertThrowsError(try f.base.addingSlowRun(data: data(changed), baseMotionSHA256: baseHash), key)
        }
        let originalFrames = try XCTUnwrap(originalClip["frames"] as? [[String: Any]])
        for kind in ["firstTime", "endTime", "duplicateTime", "translationCount", "rootTravel", "rotation", "scale"] {
            var changed = original, clip = originalClip, frames = originalFrames
            switch kind {
            case "firstTime": frames[0]["time"] = 0.1
            case "endTime": frames[frames.count - 1]["time"] = 0.2
            case "duplicateTime": frames[1]["time"] = 0
            case "translationCount":
                frames[0]["translations"] = Array(try XCTUnwrap(frames[0]["translations"] as? [[Double]]).dropLast())
            case "rootTravel":
                var values = try XCTUnwrap(frames[0]["translations"] as? [[Double]])
                values[0][0] = 0.002; frames[0]["translations"] = values
            case "rotation":
                var values = try XCTUnwrap(frames[0]["rotations"] as? [[Double]])
                values[7] = [0, 0, 0, 0]; frames[0]["rotations"] = values
            default:
                var values = try XCTUnwrap(frames[0]["scales"] as? [[Double]])
                values[7] = [1, -1, 1]; frames[0]["scales"] = values
            }
            clip["frames"] = frames; changed["clip"] = clip
            XCTAssertThrowsError(try f.base.addingSlowRun(data: data(changed), baseMotionSHA256: baseHash), kind)
        }
        XCTAssertFalse(f.base.hasSlowRun)
        XCTAssertTrue(f.added.hasSlowRun)
    }
}
