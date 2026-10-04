import CryptoKit
import RealityKit
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayTripoPolish170Tests: XCTestCase {
    private func resource(_ name: String) throws -> Data {
        let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Resources/Players")
            ?? Bundle.main.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    private func fixture() throws -> (ReplaySkinnedAthleteMotion, ReplaySkinnedAthleteMotion, Data) {
        let base = try ReplaySkinnedAthleteMotion(data: resource("ReplayXITripoMotion"), profile: .tripo52)
        let data = try resource("ReplayXITripoRecoveryMotion")
        return (base, try base.addingSlowRun(data: data,
            baseMotionSHA256: ReplayTripoAthleteProvider.motionSHA256), data)
    }

    func testRecoveryClipRetainsLowerBodyAndChangesOnlyArmRotations() throws {
        let (base, added, data) = try fixture()
        XCTAssertFalse(base.hasSlowRun)
        XCTAssertTrue(added.hasSlowRun)
        XCTAssertGreaterThanOrEqual(added.slowRunUnchangedJointCountForTesting, 44)
        XCTAssertLessThan(added.slowRunUnchangedJointCountForTesting, 52)
        XCTAssertLessThan(data.count, 110_000)
        XCTAssertEqual(base.jointNames, added.jointNames)
        var changedArmSamples = 0
        for index in 0..<120 {
            let phase = Float(index) * .pi / 60
            var control = base.makePoseBuffer(), recovery = added.makePoseBuffer()
            base.sample(time: 0, locomotionEffort: 1, gaitPhase: phase, into: &control)
            added.sample(time: 0, locomotionEffort: 1, gaitPhase: phase, slowRunWeight: 1, into: &recovery)
            for joint in base.joints.indices {
                XCTAssertLessThan(simd_distance(control.translations[joint], recovery.translations[joint]), 0.000_01)
                XCTAssertLessThan(simd_distance(control.scales[joint], recovery.scales[joint]), 0.000_01)
                let name = base.joints[joint].sourceName
                let isArm = ["Shoulder", "Arm", "ForeArm", "Hand"].contains { name.hasSuffix($0) }
                let angularDelta = 2 * acos(min(abs(simd_dot(control.rotations[joint].vector,
                                                           recovery.rotations[joint].vector)), 1))
                if isArm { if angularDelta > 0.005 { changedArmSamples += 1 } }
                else {
                    XCTAssertLessThan(angularDelta, 0.002, name)
                    // Partial blends skip channels proven identical at load time.
                    var partial = added.makePoseBuffer()
                    added.sample(time: 0, locomotionEffort: 1, gaitPhase: phase, slowRunWeight: 0.4, into: &partial)
                    XCTAssertEqual(partial.rotations[joint].vector, control.rotations[joint].vector)
                    XCTAssertEqual(partial.translations[joint], control.translations[joint])
                }
            }
        }
        XCTAssertGreaterThan(changedArmSamples, 100)
    }

    func testSupplementalRejectsWrongSourceRigBaseAndPhase() throws {
        let (base, _, data) = try fixture()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in [("sourceClipSHA256", "wrong" as Any), ("baseMotionSHA256", "wrong"),
                              ("jointCount", 80), ("phaseOffsetRadians", 0.1), ("units", "feet")] {
            var bad = original; bad[key] = value
            XCTAssertThrowsError(try base.addingSlowRun(data: JSONSerialization.data(withJSONObject: bad),
                baseMotionSHA256: ReplayTripoAthleteProvider.motionSHA256), key)
        }
        let rocketbox = try ReplaySkinnedAthleteMotion(data: resource("ReplayXIRocketboxMotion"))
        XCTAssertThrowsError(try rocketbox.addingSlowRun(data: data,
            baseMotionSHA256: ReplayTripoAthleteProvider.motionSHA256))
    }

    func testRecoverySeeksAreIndependentOfHistoryAndZeroWeightPreservesSource() throws {
        let (base, added, _) = try fixture()
        var pose = added.makePoseBuffer()
        added.sample(time: 7.2, locomotionEffort: 0.9, gaitPhase: 1.73, slowRunWeight: 0.8, into: &pose)
        let expected = pose.rotations.map(\.vector)
        for time in [13.0, 0.0, 5.4, 12.0, 1.0] {
            added.sample(time: time, locomotionEffort: 1, gaitPhase: Float(time), slowRunWeight: 1, into: &pose)
        }
        added.sample(time: 7.2, locomotionEffort: 0.9, gaitPhase: 1.73, slowRunWeight: 0.8, into: &pose)
        XCTAssertEqual(pose.rotations.map(\.vector), expected)
        var control = base.makePoseBuffer()
        for phase: Float in [-50, 0, 1.73, 100] {
            base.sample(time: 2, locomotionEffort: 0.9, gaitPhase: phase, into: &control)
            added.sample(time: 2, locomotionEffort: 0.9, gaitPhase: phase, slowRunWeight: 0, into: &pose)
            XCTAssertEqual(pose.rotations.map(\.vector), control.rotations.map(\.vector))
            XCTAssertEqual(pose.translations, control.translations)
        }
    }

    func testSharedAppearanceAtlasesLoadForBothTeamsWithoutChangingGeometry() throws {
        ReplayTripoAthleteProvider.resetForTesting()
        defer { ReplayTripoAthleteProvider.resetForTesting() }
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertEqual(ReplayTripoAthleteProvider.loadedAppearanceCount, 4)
        XCTAssertTrue(try XCTUnwrap(ReplayTripoAthleteProvider.motion).hasSlowRun)
        XCTAssertEqual(ReplayTripoAppearance.additionalBaseRGBABytes, 37_748_736)
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-36-counter-v2" })
        for team in FootballTeam.allCases {
            let tracks = scenario.players.filter { $0.team == team }
            XCTAssertGreaterThanOrEqual(Set(tracks.map { ReplayTripoAppearance.palette(for: $0).rawValue }).count, 3)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let players = try tracks.map { try ReplayTripoAthleteProvider.make(for: $0, detail: detail) }
                XCTAssertTrue(players.allSatisfy { $0.root.scale == SIMD3<Float>(repeating: 1) })
                XCTAssertTrue(players.allSatisfy { $0.model.model?.materials.count == 1 })
                XCTAssertTrue(players.dropFirst().allSatisfy { $0.model.model?.mesh === players[0].model.model?.mesh })
                withExtendedLifetime(players) {}
            }
        }
    }

    func testSourceClipPanelDoesNotRequireAnAnnotationAndIsNotAnEdit() {
        XCTAssertTrue(PlaybackInlinePanel.videoReference.isValid(for: nil))
        XCTAssertFalse(PlaybackInlinePanel.videoReference.isAnnotationPanel)
        XCTAssertNil(PlaybackInlinePanel.videoReference.annotationID)
        XCTAssertEqual(PlaybackViewShelf.allCases.map(\.title), ["View", "Overlays", "Room"])
    }
}
