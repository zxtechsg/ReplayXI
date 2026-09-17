import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayBallPlaybackContactTests: XCTestCase {
    private func update(_ root: Entity, scenario: ReplayScenario, time: Double,
                        view: ReplayViewMode = .firstPerson) throws -> Entity {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
                                 perspectiveID: scenario.defaultPerspectiveID, marks: [],
                                 showsLaneLens: false, isDrawing: false,
                                 positionalOriginTransform: nil)
        return try XCTUnwrap(root.findEntity(named: "ball"))
    }

    private func fixture(ball: BallTrack, blockerMoves: Bool = false) -> ReplayScenario {
        let blocker = PlayerTrack(
            id: "ball-path-blocker", displayName: "Blocker", role: "Midfielder",
            shirtNumber: 6, team: .away, isGoalkeeper: false,
            keyframes: [
                .init(time: 0, position: .init(x: 0, z: blockerMoves ? -0.3 : 0), facingDegrees: 0),
                .init(time: 1, position: .init(x: 0, z: blockerMoves ? 0.3 : 0), facingDegrees: 0),
            ]
        )
        return ReplayScenario(
            id: "ball-playback-contact", kind: .squadReplay, title: "Ball contact", strapline: "",
            matchContext: "Synthetic fixture", objective: "", coachPrompt: "", proofPoint: "",
            duration: 1, defaultViewMode: .firstPerson, defaultPerspectiveID: blocker.id,
            featuredPerspectiveIDs: [], players: [blocker], ball: ball,
            moments: [], coachMarks: [], formationTargets: []
        )
    }

    func testAuthoredPassAndShotContactsSitAtBootReachNotInsidePlayerRoots() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let source = scenario.ball
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for (time, playerID) in [(13.6, "navy-rw"), (17.5, "navy-rb"), (24.0, "navy-cf")] {
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let origin = player.presentationPose(at: time).position
            for view in [ReplayViewMode.firstPerson, .tacticalTable, .touchline] {
                let ball = try update(root, scenario: scenario, time: time, view: view)
                let separation = hypot(ball.position.x - origin.x, ball.position.z - origin.z)
                XCTAssertGreaterThanOrEqual(separation, 0.40,
                                             "\(playerID) at \(time): ball centre is inside the body core")
                XCTAssertLessThanOrEqual(separation, 0.90, "The touch must remain within a boot's reach")
                XCTAssertEqual(ball.position.y, 0.11, accuracy: 0.00001)
            }
        }
        XCTAssertEqual(scenario.ball, source, "Presentation repair must not rewrite saved/source telemetry")
    }

    func testFastPassHasContinuousClearanceAcrossStationaryAndMovingBlockers() throws {
        let track = BallTrack(keyframes: [
            .init(time: 0, position: .init(x: -2, z: 0), height: 0.11),
            .init(time: 1, position: .init(x: 2, z: 0), height: 0.11),
        ])
        for moving in [false, true] {
            let scenario = fixture(ball: track, blockerMoves: moving)
            let blocker = try XCTUnwrap(scenario.players.first)
            let root = PitchSceneFactory.makeMatchRoot(for: scenario)
            var minimum: Float = .greatestFiniteMagnitude
            for frame in 0...240 {
                let time = Double(frame) / 240
                let ball = try update(root, scenario: scenario, time: time)
                let player = blocker.presentationPose(at: time).position
                minimum = min(minimum, hypot(ball.position.x - player.x, ball.position.z - player.z))
            }
            XCTAssertGreaterThanOrEqual(minimum, 0.40,
                                         "A pass must not tunnel through a \(moving ? "moving" : "stationary") body")
            let start = try update(root, scenario: scenario, time: 0).position
            let end = try update(root, scenario: scenario, time: 1).position
            XCTAssertEqual(start.x, -2, accuracy: 0.00001)
            XCTAssertEqual(end.x, 2, accuracy: 0.00001)
        }
    }

    func testPresentedBallReturnsExactlyAfterScrubbingAndViewChanges() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let times: [Double] = [0, 6.2, 10.1, 13.45, 13.6, 14.15, 17.5, 24, 25.4, 27, 32]
        let expected = try times.map { try update(root, scenario: scenario, time: $0).transform }
        for view in [ReplayViewMode.touchline, .tacticalTable, .firstPerson] {
            for index in times.indices.reversed() {
                let ball = try update(root, scenario: scenario, time: times[index], view: view)
                XCTAssertEqual(ball.position.x, expected[index].translation.x)
                XCTAssertEqual(ball.position.z, expected[index].translation.z)
                XCTAssertEqual(ball.orientation.vector, expected[index].rotation.vector)
            }
        }
    }

    func testHeadHeightPassClearsTheCoarseHeadIncludingBallRadius() throws {
        let height: Float = 1.95
        XCTAssertGreaterThan(height, ReplayBallPlaybackMotion.bodyVerticalExtent)
        XCTAssertLessThan(height - ReplayBallPlaybackMotion.ballRadius,
                          ReplayBallPlaybackMotion.bodyVerticalExtent,
                          "The sphere still overlaps the head even though its centre is above it")
        let track = BallTrack(keyframes: [
            .init(time: 0, position: .init(x: -2, z: 0), height: height),
            .init(time: 1, position: .init(x: 2, z: 0), height: height),
        ])
        let scenario = fixture(ball: track)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        var minimum: Float = .greatestFiniteMagnitude
        for index in 0...240 {
            let ball = try update(root, scenario: scenario, time: Double(index) / 240)
            minimum = min(minimum, hypot(ball.position.x, ball.position.z))
            XCTAssertEqual(ball.position.y, height, accuracy: 0.00001)
        }
        XCTAssertGreaterThanOrEqual(minimum, 0.40, "Head-height travel must not pass through the body proxy")
    }

    func testClearlyOverheadPassKeepsItsAuthoredPathWithoutADetour() throws {
        let height: Float = 2.20
        XCTAssertGreaterThan(height - ReplayBallPlaybackMotion.ballRadius,
                             ReplayBallPlaybackMotion.bodyVerticalExtent + 0.1)
        let track = BallTrack(keyframes: [
            .init(time: 0, position: .init(x: -2, z: 0), height: height),
            .init(time: 1, position: .init(x: 2, z: 0), height: height),
        ])
        let scenario = fixture(ball: track)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for index in 0...240 {
            let time = Double(index) / 240
            let ball = try update(root, scenario: scenario, time: time)
            let source = track.pose(at: time)
            XCTAssertEqual(ball.position.x, source.position.x, accuracy: 0.00001)
            XCTAssertEqual(ball.position.z, source.position.z, accuracy: 0.00001)
            XCTAssertEqual(ball.position.y, height, accuracy: 0.00001)
        }
    }
}
