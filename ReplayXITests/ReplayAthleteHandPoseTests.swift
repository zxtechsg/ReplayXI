import Foundation
import simd
import XCTest
@testable import ReplayXI

final class ReplayAthleteHandPoseTests: XCTestCase {
    private func motion(_ name: String, profile: ReplaySkinnedAthleteMotion.RigProfile) throws
        -> ReplaySkinnedAthleteMotion {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json",
            subdirectory: "Resources/Players") ?? Bundle.main.url(forResource: name, withExtension: "json"))
        return try ReplaySkinnedAthleteMotion(data: Data(contentsOf: url), profile: profile)
    }

    private func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        2 * acos(min(abs(simd_dot(a.vector, b.vector)), 1))
    }

    func testTripoHandsAreRelaxedWithoutChangingBodyOrBoneLengths() throws {
        for resource in ["ReplayXITripoMotion", "ReplayXITripoPlayerAMotion"] {
            let motion = try motion(resource, profile: .tripo52)
            let hand = try XCTUnwrap(ReplayAthleteHandPose(motion: motion))
            for effort: Float in [0, 0.5, 1] {
                for frame in 0..<30 {
                    let time = Double(frame) / 15
                    var source = motion.makePoseBuffer()
                    motion.sample(time: time, locomotionEffort: effort,
                        gaitPhase: Float(time) * 9, into: &source)
                    var posed = source
                    hand.apply(to: &posed)
                    motion.rebuildModelSpaceTransforms(in: &posed)
                    XCTAssertEqual(source.translations, posed.translations)
                    XCTAssertEqual(source.scales, posed.scales)
                    for index in motion.joints.indices {
                        let name = motion.joints[index].sourceName
                        if name.contains("Hand") {
                            XCTAssertTrue(posed.rotations[index].vector.x.isFinite)
                            XCTAssertTrue(posed.rotations[index].vector.y.isFinite)
                            XCTAssertTrue(posed.rotations[index].vector.z.isFinite)
                            XCTAssertTrue(posed.rotations[index].vector.w.isFinite)
                            if name.hasSuffix("Hand") {
                                XCTAssertLessThanOrEqual(angle(motion.restPose.rotations[index],
                                    posed.rotations[index]), 50 * .pi / 180 + 0.001)
                            } else {
                                XCTAssertLessThanOrEqual(angle(motion.restPose.rotations[index],
                                    posed.rotations[index]), angle(motion.restPose.rotations[index],
                                        source.rotations[index]) + 0.001)
                            }
                        } else {
                            XCTAssertEqual(source.rotations[index].vector, posed.rotations[index].vector,
                                "Unexpected change: \(name)")
                            XCTAssertEqual(source.modelSpaceTransforms[index], posed.modelSpaceTransforms[index],
                                "Unexpected body movement: \(name)")
                        }
                        let parent = motion.joints[index].parentIndex
                        if parent >= 0 {
                            let original = simd_distance(source.modelSpaceTransforms[parent].columns.3,
                                source.modelSpaceTransforms[index].columns.3)
                            let result = simd_distance(posed.modelSpaceTransforms[parent].columns.3,
                                posed.modelSpaceTransforms[index].columns.3)
                            XCTAssertEqual(original, result, accuracy: 0.0001, name)
                        }
                    }
                }
            }
        }
    }

    func testHandPoseIsSeekDeterministicAndRocketboxIsUntouched() throws {
        let rocketbox = try motion("ReplayXIRocketboxMotion", profile: .rocketbox)
        XCTAssertNil(ReplayAthleteHandPose(motion: rocketbox))
        let motion = try motion("ReplayXITripoMotion", profile: .tripo52)
        let hand = try XCTUnwrap(ReplayAthleteHandPose(motion: motion))
        var pose = motion.makePoseBuffer()
        func sample(_ time: Double) -> [SIMD4<Float>] {
            motion.sample(time: time, locomotionEffort: 1,
                gaitPhase: Float(time) * 8, rebuildingModelSpace: false, into: &pose)
            hand.apply(to: &pose)
            return pose.rotations.map(\.vector)
        }
        let expected = sample(1.25)
        for time in [4.9, 0, 3.1, 0.2] { _ = sample(time) }
        XCTAssertEqual(sample(1.25), expected)
    }

    func testSaveCanKeepItsSolvedWristOrientation() throws {
        let motion = try motion("ReplayXITripoMotion", profile: .tripo52)
        let hand = try XCTUnwrap(ReplayAthleteHandPose(motion: motion))
        var source = motion.makePoseBuffer()
        motion.sample(time: 0, locomotionEffort: 0, gaitPhase: 0, into: &source)
        var posed = source
        hand.apply(to: &posed, preserveWrist: true)
        for side in ["Left", "Right"] {
            let wrist = try XCTUnwrap(motion.joints.firstIndex {
                $0.sourceName == "mixamorig:\(side)Hand"
            })
            XCTAssertEqual(posed.rotations[wrist].vector, source.rotations[wrist].vector)
            let indexBase = try XCTUnwrap(motion.joints.firstIndex {
                $0.sourceName == "mixamorig:\(side)HandIndex1"
            })
            XCTAssertLessThan(angle(motion.restPose.rotations[indexBase], posed.rotations[indexBase]),
                angle(motion.restPose.rotations[indexBase], source.rotations[indexBase]))
        }
    }
}
