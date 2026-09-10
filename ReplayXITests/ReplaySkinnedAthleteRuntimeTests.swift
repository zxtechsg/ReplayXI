import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySkinnedAthleteRuntimeTests: XCTestCase {
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

    private func jogging(_ player: PlayerTrack, at time: Double) -> PlayerLocomotionSample {
        let sample = player.locomotion(at: time)
        return PlayerLocomotionSample(motion: sample.motion, speedMetresPerSecond: 3.6,
                                     accelerationMetresPerSecondSquared: 0,
                                     turnRateDegreesPerSecond: 0, state: .jog)
    }

    func testBundledRigHasVerifiedSkinAndIndependentClones() throws {
        let (player, first) = try prepare()
        let second = try ReplaySkinnedAthleteProvider.make(for: player)
        XCTAssertEqual(first.model.jointNames.count, 80)
        XCTAssertEqual(first.model.jointTransforms.count, 80)
        XCTAssertEqual(first.model.model?.materials.count, 2)
        XCTAssertTrue(first.model.model?.mesh === second.model.model?.mesh)
        XCTAssertFalse(first.model === second.model)
        XCTAssertEqual(ReplaySkinnedAthleteProvider.materialDrawsPerInstance, 4)
        XCTAssertTrue(first.update(at: 12, track: player, locomotion: jogging(player, at: 12),
                                  lookTarget: nil, hasBallAction: false, hasImpact: false))
        XCTAssertNotEqual(first.model.jointTransforms, second.model.jointTransforms)
        XCTAssertEqual(first.model.jointNames, first.motion.jointNames)
    }

    func testArbitrarySeekAndRewindHaveIdenticalSkinAndNumbers() throws {
        let (player, skin) = try prepare()
        func seek(_ time: Double) {
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: jogging(player, at: time),
                                      lookTarget: [9, 0.2, 20], hasBallAction: false, hasImpact: false))
        }
        seek(12)
        let first = skin.model.jointTransforms
        let front = skin.front.transform
        let back = skin.back.transform
        seek(17)
        XCTAssertNotEqual(skin.model.jointTransforms, first)
        seek(3)
        seek(12)
        XCTAssertEqual(skin.model.jointTransforms, first)
        XCTAssertEqual(skin.front.transform, front)
        XCTAssertEqual(skin.back.transform, back)
        let chest = skin.pose.modelSpaceTransforms[skin.motion.numberAnchors.jointIndex]
        let expected = chest * SIMD4<Float>(skin.motion.numberAnchors.front, 1)
        XCTAssertLessThan(simd_distance(skin.front.position, SIMD3(expected.x, expected.y, expected.z)), 0.00001)
    }

    func testTurningHeadDoesNotDragShouldersWithNeck() throws {
        let (player, skin) = try prepare()
        let time = 12.0
        let pose = player.presentationPose(at: time)
        let bearing = pose.facingDegrees * .pi / 180
        func target(_ side: Float) -> SIMD3<Float> {
            [pose.position.x + sin(bearing) * 10 + cos(bearing) * side * 10,
             1.5,
             pose.position.z + cos(bearing) * 10 - sin(bearing) * side * 10]
        }
        _ = skin.update(at: time, track: player, locomotion: jogging(player, at: time),
                        lookTarget: target(-1),
                        hasBallAction: false, hasImpact: false)
        let first = skin.pose
        _ = skin.update(at: time, track: player, locomotion: jogging(player, at: time),
                        lookTarget: target(1),
                        hasBallAction: false, hasImpact: false)
        let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
        XCTAssertNotEqual(skin.pose.modelSpaceTransforms[head], first.modelSpaceTransforms[head])
        for name in ["leftShoulder", "rightShoulder", "leftWrist", "rightWrist"] {
            let index = try XCTUnwrap(skin.motion.semanticJointIndices[name])
            for column in 0..<4 {
                XCTAssertLessThan(simd_distance(skin.pose.modelSpaceTransforms[index][column],
                                                first.modelSpaceTransforms[index][column]), 0.0001, name)
            }
        }
    }

    func testUnsupportedFootballActionsKeepProceduralFallback() throws {
        let (player, skin) = try prepare()
        let motion = jogging(player, at: 12)
        XCTAssertFalse(skin.update(at: 12, track: player, locomotion: motion, lookTarget: nil,
                                   hasBallAction: true, hasImpact: false))
        XCTAssertFalse(skin.root.isEnabled)
        XCTAssertFalse(skin.update(at: 12, track: player, locomotion: motion, lookTarget: nil,
                                   hasBallAction: false, hasImpact: true))
        XCTAssertTrue(skin.update(at: 12, track: player, locomotion: motion, lookTarget: nil,
                                  hasBallAction: false, hasImpact: false))
    }

    func testSceneSelectionReleasesOldSkinsAndPOVHidesWearer() throws {
        let (_, _) = try prepare()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        func update(_ playerID: String, mode: ReplayViewMode) {
            PitchSceneFactory.update(root: root, scenario: scenario, time: 12, viewMode: mode,
                                     perspectiveID: playerID, marks: [], showsLaneLens: false,
                                     isDrawing: false, positionalOriginTransform: nil)
        }
        func skins(_ entity: Entity) -> [Entity] {
            let own = entity.name == ReplaySkinnedAthleteProvider.visualRootName ? [entity] : []
            return own + entity.children.flatMap { skins($0) }
        }
        let first = try XCTUnwrap(scenario.players.first)
        let last = try XCTUnwrap(scenario.players.last)
        update(last.id, mode: .tacticalTable)
        XCTAssertEqual(skins(root).count, 1)
        let old = try XCTUnwrap(skins(root).first)
        update(first.id, mode: .tacticalTable)
        XCTAssertNil(old.parent)
        XCTAssertEqual(skins(root).count, 1)
        update(first.id, mode: .firstPerson)
        let wearer = try XCTUnwrap(root.findEntity(named: "player-\(first.id)"))
        XCTAssertTrue(skins(wearer).isEmpty)
        XCTAssertLessThanOrEqual(skins(root).count, PitchSceneFactory.firstPersonDetailedRigLimit)
    }
}
