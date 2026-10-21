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

    private func position(_ pose: ReplaySkinnedAthleteMotion.Pose, _ index: Int) -> SIMD3<Float> {
        let column = pose.modelSpaceTransforms[index].columns.3
        return [column.x, column.y, column.z]
    }

    private func assertPalmsFaceInward(_ pose: ReplaySkinnedAthleteMotion.Pose,
                                       motion: ReplaySkinnedAthleteMotion,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        let rest = motion.restPose
        let chest = try XCTUnwrap(motion.semanticJointIndices["chest"])
        let left = try XCTUnwrap(motion.joints.firstIndex { $0.sourceName == "mixamorig:LeftHand" })
        let right = try XCTUnwrap(motion.joints.firstIndex { $0.sourceName == "mixamorig:RightHand" })
        let restRight = simd_normalize(position(rest, right) - position(rest, left))
        let bodyRightLocal = simd_quatf(rest.modelSpaceTransforms[chest]).inverse.act(restRight)
        let bodyRight = simd_quatf(pose.modelSpaceTransforms[chest]).act(bodyRightLocal)
        for (side, sign) in [("Left", Float(1)), ("Right", Float(-1))] {
            func joint(_ suffix: String) throws -> Int {
                try XCTUnwrap(motion.joints.firstIndex {
                    $0.sourceName == "mixamorig:\(side)Hand\(suffix)"
                })
            }
            let wrist = try joint("")
            let index = try joint("Index1")
            let middle = try joint("Middle1")
            let pinky = try joint("Pinky1")
            let thumb = try joint("Thumb1")
            func normal(_ sample: ReplaySkinnedAthleteMotion.Pose) -> SIMD3<Float> {
                simd_normalize(simd_cross(position(sample, index) - position(sample, pinky),
                                          position(sample, middle) - position(sample, wrist)))
            }
            let restNormal = normal(rest)
            let palmSign: Float = simd_dot(restNormal, position(rest, thumb) - position(rest, wrist)) < 0
                ? -1 : 1
            let reach = simd_normalize(position(pose, middle) - position(pose, wrist))
            let medial = bodyRight * sign
            let target = simd_normalize(medial - reach * simd_dot(medial, reach))
            let alignment = simd_dot(normal(pose) * palmSign, target)
            XCTAssertGreaterThan(alignment, 0.90, "\(side) palm faces away from torso", file: file, line: line)
        }
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
                    if effort == 1 && frame == 5 {
                        for side in ["Left", "Right"] {
                            let ids = (1...3).map { ordinal in motion.joints.firstIndex {
                                $0.sourceName == "mixamorig:\(side)HandIndex\(ordinal)"
                            }! }
                            let wrist = motion.joints.firstIndex { $0.sourceName == "mixamorig:\(side)Hand" }!
                            XCTAssertLessThan(simd_distance(position(posed, wrist), position(posed, ids[2])),
                                simd_distance(position(source, wrist), position(source, ids[2])) - 0.003,
                                "\(resource) \(side) index must curl toward the hand")
                        }
                    }
                    try assertPalmsFaceInward(posed, motion: motion)
                    XCTAssertEqual(source.translations, posed.translations)
                    XCTAssertEqual(source.scales, posed.scales)
                    for index in motion.joints.indices {
                        let name = motion.joints[index].sourceName
                        if name.contains("Hand") {
                            XCTAssertTrue(posed.rotations[index].vector.x.isFinite)
                            XCTAssertTrue(posed.rotations[index].vector.y.isFinite)
                            XCTAssertTrue(posed.rotations[index].vector.z.isFinite)
                            XCTAssertTrue(posed.rotations[index].vector.w.isFinite)
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

    func testUpturnedWristIsPronatedWithBoundedFingerDirection() throws {
        for resource in ["ReplayXITripoMotion", "ReplayXITripoPlayerAMotion"] {
            let motion = try motion(resource, profile: .tripo52)
            let hand = try XCTUnwrap(ReplayAthleteHandPose(motion: motion))
            for effort: Float in [0, 1] {
                var pose = motion.makePoseBuffer()
                motion.sample(time: 0.42, locomotionEffort: effort, gaitPhase: 1.7, into: &pose)
                for side in ["Left", "Right"] {
                    let wrist = try XCTUnwrap(motion.joints.firstIndex {
                        $0.sourceName == "mixamorig:\(side)Hand"
                    })
                    let middle = try XCTUnwrap(motion.joints.firstIndex {
                        $0.sourceName == "mixamorig:\(side)HandMiddle1"
                    })
                    let restReach = simd_normalize(position(motion.restPose, middle)
                        - position(motion.restPose, wrist))
                    let localReach = simd_quatf(motion.restPose.modelSpaceTransforms[wrist])
                        .inverse.act(restReach)
                    pose.rotations[wrist] = simd_normalize(pose.rotations[wrist]
                        * simd_quatf(angle: .pi / 2, axis: localReach))
                }
                motion.rebuildModelSpaceTransforms(in: &pose)
                let before = pose
                hand.apply(to: &pose)
                motion.rebuildModelSpaceTransforms(in: &pose)
                try assertPalmsFaceInward(pose, motion: motion)
                for side in ["Left", "Right"] {
                    let wrist = try XCTUnwrap(motion.joints.firstIndex {
                        $0.sourceName == "mixamorig:\(side)Hand"
                    })
                    let middle = try XCTUnwrap(motion.joints.firstIndex {
                        $0.sourceName == "mixamorig:\(side)HandMiddle1"
                    })
                    let originalReach = simd_normalize(position(before, middle) - position(before, wrist))
                    let correctedReach = simd_normalize(position(pose, middle) - position(pose, wrist))
                    XCTAssertGreaterThan(simd_dot(originalReach, correctedReach), cos(0.60) - 0.002)
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
        motion.rebuildModelSpaceTransforms(in: &posed)
        for side in ["Left", "Right"] {
            let wrist = try XCTUnwrap(motion.joints.firstIndex {
                $0.sourceName == "mixamorig:\(side)Hand"
            })
            XCTAssertEqual(posed.rotations[wrist].vector, source.rotations[wrist].vector)
            let indexTip = try XCTUnwrap(motion.joints.firstIndex {
                $0.sourceName == "mixamorig:\(side)HandIndex3"
            })
            XCTAssertLessThan(simd_distance(position(posed, wrist), position(posed, indexTip)),
                simd_distance(position(source, wrist), position(source, indexTip)))
        }
    }
}
