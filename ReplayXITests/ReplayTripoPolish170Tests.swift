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

    func testRecoveryLoopSeamStaysContinuousAcrossBlendWeights() throws {
        let (_, added, _) = try fixture()
        for weight: Float in [0, 0.4, 1] {
            var before = added.makePoseBuffer(), after = added.makePoseBuffer()
            added.sample(time: 3, locomotionEffort: 1, gaitPhase: 2 * .pi - 0.0001,
                slowRunWeight: weight, into: &before)
            added.sample(time: 3, locomotionEffort: 1, gaitPhase: 0.0001,
                slowRunWeight: weight, into: &after)
            for joint in added.joints.indices {
                let angle = 2 * acos(min(abs(simd_dot(before.rotations[joint].vector,
                    after.rotations[joint].vector)), 1))
                XCTAssertLessThan(angle, 0.01, added.joints[joint].sourceName)
                XCTAssertLessThan(simd_distance(before.translations[joint], after.translations[joint]), 0.0001)
                XCTAssertLessThan(simd_distance(before.scales[joint], after.scales[joint]), 0.0001)
            }
        }
    }

    func testSharedAppearanceAtlasesLoadForBothTeamsWithoutChangingGeometry() throws {
        ReplayTripoAthleteProvider.resetForTesting()
        defer { ReplayTripoAthleteProvider.resetForTesting() }
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertEqual(ReplayTripoAthleteProvider.loadedAppearanceCount, 4)
        XCTAssertEqual(ReplayTripoAthleteProvider.loadedBaseTextureBytes, 100_663_296)
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

    func testMissingOptionalAssetsKeepTheBaseTripoRigWorking() throws {
        try withAssetBundle(includesOptional: false) { bundle, _ in
            ReplayTripoAthleteProvider.resetForTesting()
            defer { ReplayTripoAthleteProvider.resetForTesting() }
            try ReplayTripoAthleteProvider.prewarm(in: bundle)
            XCTAssertTrue(ReplayTripoAthleteProvider.isPrewarmed)
            XCTAssertEqual(ReplayTripoAthleteProvider.loadedAppearanceCount, 1)
            XCTAssertEqual(ReplayTripoAthleteProvider.loadedBaseTextureBytes, 50_331_648)
            XCTAssertFalse(try XCTUnwrap(ReplayTripoAthleteProvider.motion).hasSlowRun)
            let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first)
            for team in FootballTeam.allCases {
                let track = try XCTUnwrap(scenario.players.first { $0.team == team })
                let skin = try ReplayTripoAthleteProvider.make(for: track)
                XCTAssertEqual(skin.motion.rigProfile, .tripo52)
                XCTAssertEqual(skin.model.model?.materials.count, 1)
            }
        }
    }

    func testInvalidOptionalAtlasAndRecoveryFailSoftAsCompletePalettes() throws {
        try withAssetBundle(includesOptional: true) { bundle, directory in
            // A broken home atlas must reject the whole home/away/keeper palette.
            try Data("not a PNG".utf8).write(to: directory.appendingPathComponent("ReplayXITripoHomeDeep.png"))
            try Data("{}".utf8).write(to: directory.appendingPathComponent("ReplayXITripoRecoveryMotion.json"))
            ReplayTripoAthleteProvider.resetForTesting()
            defer { ReplayTripoAthleteProvider.resetForTesting() }
            try ReplayTripoAthleteProvider.prewarm(in: bundle)
            XCTAssertTrue(ReplayTripoAthleteProvider.isPrewarmed)
            XCTAssertEqual(ReplayTripoAthleteProvider.loadedAppearanceCount, 3)
            XCTAssertEqual(ReplayTripoAthleteProvider.loadedBaseTextureBytes, 75_497_472)
            XCTAssertFalse(try XCTUnwrap(ReplayTripoAthleteProvider.motion).hasSlowRun)
            let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first)
            for team in FootballTeam.allCases {
                let track = try XCTUnwrap(scenario.players.first {
                    $0.team == team && ReplayTripoAppearance.palette(for: $0) == .deep
                })
                let skin = try ReplayTripoAthleteProvider.make(for: track)
                XCTAssertEqual(skin.motion.rigProfile, .tripo52)
                XCTAssertEqual(skin.model.model?.materials.count, 1)
            }
        }
    }

    func testWarmClonesAndPlaybackDoNotPrepareMoreTexturesOrLoadAssets() throws {
        ReplayTripoAthleteProvider.resetForTesting()
        defer { ReplayTripoAthleteProvider.resetForTesting() }
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertEqual(ReplayTripoAthleteProvider.nativeAssetLoadAttemptsForTesting, 4)
        XCTAssertEqual(ReplayTripoAthleteProvider.texturePreparationAttemptsForTesting, 15)
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first)
        let skins = try scenario.players.map { try ReplayTripoAthleteProvider.makePreferred(for: $0, detail: .near) }
        for frame in 0..<60 {
            let time = Double(frame) / 30
            for (skin, player) in zip(skins, scenario.players) {
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                    lookTarget: nil, ballAction: nil))
            }
        }
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertEqual(ReplayTripoAthleteProvider.nativeAssetLoadAttemptsForTesting, 4)
        XCTAssertEqual(ReplayTripoAthleteProvider.texturePreparationAttemptsForTesting, 15)
        XCTAssertEqual(ReplayTripoAthleteProvider.loadedNumberMaskBaseBytes,
            Set(scenario.players.map(\.shirtNumber)).count * 256 * 256 * 4)
        XCTAssertEqual(ReplayTripoAthleteProvider.loadedBaseTextureBytes,
            100_663_296 + ReplayTripoAthleteProvider.loadedNumberMaskBaseBytes)
        withExtendedLifetime(skins) {}
    }

    private func withAssetBundle(includesOptional: Bool, _ body: (Bundle, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayXI-Tripo170-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let info = ["CFBundleIdentifier": "test.replayxi.tripo170", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Info.plist"))
        var resources = ["ReplayXITripoAthlete.usdz", "ReplayXITripoLow.usdz", "ReplayXITripoMotion.json",
            "ReplayXITripoContactSurface.json", "ReplayXITripoLowContactSurface.json",
            "ReplayXITripoHome.png", "ReplayXITripoAway.png", "ReplayXITripoKeeper.png"]
        if includesOptional {
            resources.append("ReplayXITripoRecoveryMotion.json")
            resources += ReplayTripoAppearance.Palette.allCases.flatMap {
                ReplayTripoAppearance.atlases(for: $0).map { $0.name + ".png" }
            }
        }
        for filename in resources {
            let resource = URL(fileURLWithPath: filename)
            let name = resource.deletingPathExtension().lastPathComponent
            let source = Bundle.main.url(forResource: name, withExtension: resource.pathExtension,
                subdirectory: "Resources/Players")
                ?? Bundle.main.url(forResource: name, withExtension: resource.pathExtension)
            try FileManager.default.copyItem(at: XCTUnwrap(source), to: directory.appendingPathComponent(filename))
        }
        try body(XCTUnwrap(Bundle(url: directory)), directory)
    }

    func testSourceClipPanelDoesNotRequireAnAnnotationAndIsNotAnEdit() {
        XCTAssertTrue(PlaybackInlinePanel.videoReference.isValid(for: nil))
        XCTAssertFalse(PlaybackInlinePanel.videoReference.isAnnotationPanel)
        XCTAssertNil(PlaybackInlinePanel.videoReference.annotationID)
        XCTAssertEqual(PlaybackViewShelf.allCases.map(\.title), ["View", "Overlays", "Room"])
    }

    func testAppearanceSlotsFollowTheExistingFarRigToneOrder() throws {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first)
        let expected: [ReplayTripoAppearance.Palette] = [.light, .base, .warm, .deep, .base]
        for team in FootballTeam.allCases {
            let source = try XCTUnwrap(scenario.players.first { $0.team == team })
            for number in 0..<15 {
                let player = PlayerTrack(id: "palette-order-\(team.rawValue)-\(number)", displayName: "Fictional player",
                    role: source.role, shirtNumber: number, team: team, isGoalkeeper: false, keyframes: source.keyframes)
                let slot = (number + (team == .away ? 2 : 0)) % 5
                XCTAssertEqual(ReplayAthleteConfiguration(player: player).appearance,
                    ReplayAthleteAppearance.replayXI(index: slot))
                XCTAssertEqual(ReplayTripoAppearance.palette(for: player), expected[slot])
            }
        }
    }
}
