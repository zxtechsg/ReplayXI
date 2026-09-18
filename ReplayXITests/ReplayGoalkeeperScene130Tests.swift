import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Checks production scene wiring, not just the isolated pose helper.
@MainActor
final class ReplayGoalkeeperScene130Tests: XCTestCase {
    func testNativeSceneUsesKeeperReadinessAndRewindsWithoutChangingBallOrRoot() async throws {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        defer {
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayNativeBallPhysics.resetCacheForTesting()
        }
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-81-volley-v2" })
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        let shots = ReplayFootballShotTimeline(touches: recording.touches, players: scenario.players)
        let shot = try XCTUnwrap(recording.touches.first { $0.kind == .shot })
        let shooter = try XCTUnwrap(scenario.players.first { $0.id == shot.playerID })
        let keeper = try XCTUnwrap(scenario.players.first { $0.isGoalkeeper && $0.team != shooter.team })
        let time = shot.time + 0.42
        let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        func update(_ time: Double) {
            PitchSceneFactory.update(root: root, scenario: scenario, time: time,
                viewMode: .tacticalTable, perspectiveID: keeper.id, marks: [],
                showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
        }
        update(time)
        let presented = keeper.presentationPose(at: time)
        let ball = recording.sample(at: time).position
        let readiness = try XCTUnwrap(ReplayGoalkeeperReadiness.sample(track: keeper, at: time,
            presentationPose: presented, ballPosition: ball,
            shot: shots.latestOpposingShot(for: keeper, at: time)))
        XCTAssertGreaterThan(readiness.readiness, 0)
        XCTAssertGreaterThan(readiness.reaction, 0)
        let actual = try XCTUnwrap(PitchSceneFactory.skinnedAthletesForTesting(in: root)[keeper.id])
        let expected = try ReplaySkinnedAthleteProvider.make(for: keeper, detail: actual.detail)
        let actor = Entity()
        actor.position = [presented.position.x, 0, presented.position.z]
        actor.orientation = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
        actor.addChild(expected.root)
        defer { expected.root.removeFromParent() }
        XCTAssertTrue(expected.update(at: time, track: keeper, locomotion: keeper.locomotion(at: time),
            lookTarget: ball, ballAction: nil, presentationPose: presented,
            goalkeeperReadiness: readiness))
        XCTAssertEqual(actual.model.jointTransforms, expected.model.jointTransforms)
        let checkpoint = actual.model.jointTransforms
        XCTAssertTrue(expected.update(at: time, track: keeper, locomotion: keeper.locomotion(at: time),
            lookTarget: ball, ballAction: nil, presentationPose: presented))
        XCTAssertNotEqual(actual.model.jointTransforms, expected.model.jointTransforms,
                          "Scene must show the new set/reaction, not just ordinary idle arms")
        let playerRoot = try XCTUnwrap(root.findEntity(named: "player-\(keeper.id)"))
        XCTAssertEqual(playerRoot.position, actor.position)
        update(scenario.duration)
        update(0.1)
        update(time)
        XCTAssertEqual(try XCTUnwrap(PitchSceneFactory.skinnedAthletesForTesting(in: root)[keeper.id])
            .model.jointTransforms, checkpoint)
        XCTAssertEqual(playerRoot.position, actor.position)
        XCTAssertEqual(try XCTUnwrap(root.findEntity(named: "ball")).position,
                       SIMD3<Float>(ball.x, max(ball.y, ReplayNativeBallPhysics.radius), ball.z))
    }
}
