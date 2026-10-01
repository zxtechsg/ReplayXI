import Foundation
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayHeadSubtreeUpdateTests: XCTestCase {
    private func motions() throws -> [ReplaySkinnedAthleteMotion] {
        try [("ReplayXITripoMotion", ReplaySkinnedAthleteMotion.RigProfile.tripo52),
             ("ReplayXIRocketboxMotion", .rocketbox)].map { name, profile in
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json",
                subdirectory: "Resources/Players") ?? Bundle.main.url(forResource: name, withExtension: "json"))
            return try ReplaySkinnedAthleteMotion(data: Data(contentsOf: url), profile: profile)
        }
    }

    private func assertIdentical(_ a: ReplaySkinnedAthleteMotion.Pose,
                                 _ b: ReplaySkinnedAthleteMotion.Pose,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.translations, b.translations, file: file, line: line)
        XCTAssertEqual(a.scales, b.scales, file: file, line: line)
        XCTAssertEqual(a.rotations.map(\.vector), b.rotations.map(\.vector), file: file, line: line)
        XCTAssertEqual(a.modelSpaceTransforms.count, b.modelSpaceTransforms.count, file: file, line: line)
        for (a, b) in zip(a.modelSpaceTransforms, b.modelSpaceTransforms) {
            for column in 0..<4 { XCTAssertEqual(a[column], b[column], file: file, line: line) }
        }
    }

    func testHeadOnlyRebuildExactlyMatchesFullHierarchyAcrossBothRigsAndRewinds() throws {
        for motion in try motions() {
            let head = try XCTUnwrap(motion.semanticJointIndices["head"])
            let branch = Set(motion.headSubtreeJointIndices)
            XCTAssertEqual(motion.headSubtreeJointIndices.first, head)
            XCTAssertEqual(motion.headSubtreeJointIndices, motion.headSubtreeJointIndices.sorted())
            let expectedCount = motion.rigProfile == .tripo52 ? 1 : 29
            XCTAssertEqual(branch.count, expectedCount)
            var current = motion.makePoseBuffer()
            // Forward, reverse and repeated seeks; both source gaits and all axes.
            for clip in ReplaySkinnedAthleteMotion.ClipID.allCases {
                for frame in Array(0..<48) + Array((0..<48).reversed()) + [0, 23, 47] {
                    motion.sample(clip: clip, at: Double(frame) / 24, into: &current)
                    let previous = current.modelSpaceTransforms
                    let yaw = Float(frame - 24) * 0.04
                    current.rotations[head] = simd_normalize(current.rotations[head]
                        * simd_quatf(angle: yaw, axis: [0, 1, 0])
                        * simd_quatf(angle: yaw * 0.2, axis: [1, 0, 0])
                        * simd_quatf(angle: -yaw * 0.1, axis: [0, 0, 1]))
                    var full = current
                    motion.rebuildModelSpaceTransforms(in: &full)
                    XCTAssertEqual(motion.rebuildHeadModelSpaceTransforms(in: &current), expectedCount)
                    assertIdentical(current, full)
                    for index in motion.joints.indices where !branch.contains(index) {
                        for column in 0..<4 {
                            XCTAssertEqual(current.modelSpaceTransforms[index][column], previous[index][column])
                        }
                    }
                }
            }
        }
    }

    func testHeadBranchRecoveryMatchesFullRebuildForEveryMalformedBuffer() throws {
        for motion in try motions() {
            for component in 0..<4 {
                var malformed = motion.makePoseBuffer()
                switch component {
                case 0: malformed.translations.removeLast()
                case 1: malformed.rotations.removeLast()
                case 2: malformed.scales.removeLast()
                default: malformed.modelSpaceTransforms.removeLast()
                }
                var full = malformed
                motion.rebuildModelSpaceTransforms(in: &full)
                XCTAssertEqual(motion.rebuildHeadModelSpaceTransforms(in: &malformed), motion.joints.count)
                assertIdentical(malformed, full)
            }
        }
    }
}
