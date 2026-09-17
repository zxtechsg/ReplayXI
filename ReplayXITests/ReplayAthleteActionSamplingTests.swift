import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAthleteActionSamplingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteMotion.resetBallActionSampleCountForTesting()
    }

    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayAthleteMotion.resetBallActionSampleCountForTesting()
        super.tearDown()
    }

    func testProceduralMatchInfersAtMostOneActionPerPlayerPerUpdate() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson] {
            for time in [13.6, 17.5, 32.0, 13.6] {
                ReplayAthleteMotion.resetBallActionSampleCountForTesting()
                update(root, scenario: scenario, time: time, view: view)
                XCTAssertEqual(
                    ReplayAthleteMotion.ballActionSampleCount, scenario.players.count,
                    "\(view) at \(time): share one inferred action with near/far procedural bodies"
                )
            }
        }
    }

    func testSkinnedMatchSharesTheSameSingleActionSampleWithFallbacks() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson] {
            ReplayAthleteMotion.resetBallActionSampleCountForTesting()
            update(root, scenario: scenario, time: 13.6, view: view)
            XCTAssertEqual(ReplayAthleteMotion.ballActionSampleCount, scenario.players.count)
        }
    }

    func testPositionalTeachingViewStillDoesNotInferReplayBallActions() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for ideal in [false, true, false] {
            ReplayAthleteMotion.resetBallActionSampleCountForTesting()
            update(root, scenario: scenario, time: 13.6, view: .positional, ideal: ideal)
            XCTAssertEqual(ReplayAthleteMotion.ballActionSampleCount, 0)
        }
    }

    func testSharedSamplesPreserveEveryNearAndFarJointAcrossTouchesAndReverseSeek() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let ballPlayback = ReplayBallPlaybackMotion(track: scenario.ball, players: scenario.players)
        for time in [10.1, 13.6, 17.5, 32.0, 17.5, 13.6, 10.1] {
            update(root, scenario: scenario, time: time, view: .tacticalTable)
            let ball = ballPlayback.pose(at: time)
            for (id, lod, name) in [("navy-rw", ReplayAthleteLOD.near, "full-rig"),
                                    ("navy-rb", .far, "table-marker")] {
                let player = try XCTUnwrap(scenario.player(id: id))
                let actual = try XCTUnwrap(root.findEntity(named: "player-\(id)")?.findEntity(named: name))
                let expected = try ReplayAthleteFactory.make(for: player, lod: lod)
                ReplayAthleteMotion.update(
                    expected, from: player, at: time,
                    lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z],
                    ballTrack: scenario.ball
                )
                for joint in ReplayAthleteJoint.allCases {
                    let entity = try XCTUnwrap(actual.findEntity(named: joint.rawValue))
                    XCTAssertEqual(entity.transform, expected.joints[joint].transform,
                                   "\(id), \(joint), \(time): sample reuse must not change articulation")
                }
            }
        }
    }

    func testProceduralImpactStillSuppressesFootballActionBeforeApplyingImpactPose() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let time = 13.6
        let cue = PlayerRagdollCue(playerID: player.id, impactTime: 13, duration: 3)
        XCTAssertNotNil(ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time))
        update(root, scenario: scenario, time: time, view: .tacticalTable, cue: cue)
        let actual = try XCTUnwrap(root.findEntity(named: "player-\(player.id)")?.findEntity(named: "full-rig"))
        let expected = try ReplayAthleteFactory.make(for: player, lod: .near)
        let ball = ReplayBallPlaybackMotion(track: scenario.ball, players: scenario.players).pose(at: time)
        ReplayAthleteMotion.update(
            expected, from: player, at: time,
            lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z],
            ragdollCue: cue
        )
        for joint in ReplayAthleteJoint.allCases {
            let entity = try XCTUnwrap(actual.findEntity(named: joint.rawValue))
            XCTAssertEqual(entity.transform, expected.joints[joint].transform)
        }
    }

    private func update(
        _ root: Entity,
        scenario: ReplayScenario,
        time: TimeInterval,
        view: ReplayViewMode,
        ideal: Bool = false,
        cue: PlayerRagdollCue? = nil
    ) {
        PitchSceneFactory.update(
            root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: "navy-rw", marks: scenario.coachMarks,
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil,
            showsIdealBranch: ideal, ragdollCue: cue
        )
    }
}
