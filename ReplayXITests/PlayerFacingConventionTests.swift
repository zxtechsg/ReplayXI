import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class PlayerFacingConventionTests: XCTestCase {
    private let forward = SIMD3<Float>(0, 0, 1)

    private func track(_ frames: [MotionKeyframe], id: String = "facing-regression") -> PlayerTrack {
        PlayerTrack(id: id, displayName: "Facing Test", role: "Midfielder", shirtNumber: 8,
                    team: .home, isGoalkeeper: false, keyframes: frames)
    }

    private func frame(_ time: Double, _ x: Float, _ z: Float, _ facing: Float) -> MotionKeyframe {
        MotionKeyframe(time: time, position: .init(x: x, z: z), facingDegrees: facing)
    }

    private func scenario(_ player: PlayerTrack) -> ReplayScenario {
        ReplayScenario(id: "facing-regression", kind: .squadReplay,
                       title: "Facing", strapline: "", matchContext: "", objective: "",
                       coachPrompt: "", proofPoint: "", duration: 2,
                       defaultViewMode: .tacticalTable, defaultPerspectiveID: player.id,
                       featuredPerspectiveIDs: [player.id], players: [player],
                       ball: BallTrack(keyframes: [
                           .init(time: 0, position: .init(x: -25, z: 40), height: 0.11),
                           .init(time: 2, position: .init(x: -25, z: 40), height: 0.11),
                       ]), moments: [], coachMarks: [], formationTargets: [])
    }

    private func update(_ root: Entity, scenario: ReplayScenario, at time: Double,
                        mode: ReplayViewMode = .tacticalTable, idealShape: Bool = false) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: mode,
                                 perspectiveID: scenario.defaultPerspectiveID, marks: [],
                                 showsLaneLens: false, isDrawing: false,
                                 positionalOriginTransform: nil, showsIdealBranch: idealShape)
    }

    func testPositiveXBearingFacesAlongPositiveXTravelAndRecordedDirection() throws {
        let player = track([frame(0, 0, 0, 90), frame(2, 6, 0, 90)])
        let fixture = scenario(player)
        let root = PitchSceneFactory.makeMatchRoot(for: fixture)
        update(root, scenario: fixture, at: 1)
        let actor = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
        let travel = SIMD3<Float>(1, 0, 0)
        XCTAssertGreaterThan(simd_dot(actor.orientation.act(forward), travel), 0.9999)

        update(root, scenario: fixture, at: 0.5, mode: .firstPerson)
        let fixedWorldOrientation = root.orientation.vector
        let indicator = try XCTUnwrap(root.findEntity(named: "recorded-facing"))
        XCTAssertGreaterThan(simd_dot(indicator.orientation.act(forward), travel), 0.9999)
        // Rotating the complete pitch must not mirror an actor relative to
        // its travel direction, nor attach authored yaw to the headset view.
        let renderedForward = root.orientation.act(indicator.orientation.act(forward))
        XCTAssertGreaterThan(simd_dot(renderedForward, root.orientation.act(travel)), 0.9999)
        update(root, scenario: fixture, at: 1.5, mode: .firstPerson)
        XCTAssertEqual(root.orientation.vector, fixedWorldOrientation)
    }

    func testAuthoredDiagonalHeadingIsNotMirroredAgainstDemoTravel() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "red-cf"))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        PitchSceneFactory.update(root: root, scenario: scenario, time: 6,
                                 viewMode: .tacticalTable, perspectiveID: player.id, marks: [],
                                 showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
        let actor = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
        let before = player.pose(at: 3).position
        let after = player.pose(at: 6).position
        let travel = simd_normalize(SIMD3<Float>(after.x - before.x, 0, after.z - before.z))
        XCTAssertEqual(player.pose(at: 6).facingDegrees, 45)
        XCTAssertGreaterThan(simd_dot(actor.orientation.act(forward), travel), 0.97)
    }

    func testIdealShapePlayersActuallyFaceThePresentedBall() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, at: 12, mode: .positional, idealShape: true)
        let ball = try XCTUnwrap(root.findEntity(named: "ball"))
        for target in scenario.formationTargets {
            let actor = try XCTUnwrap(root.findEntity(named: "player-\(target.playerID)"))
            let delta = ball.position - actor.position
            let towardBall = simd_normalize(SIMD3<Float>(delta.x, 0, delta.z))
            XCTAssertGreaterThan(simd_dot(actor.orientation.act(forward), towardBall), 0.9999,
                                 "\(target.playerID) faces across the ball's wrong side")
        }
    }

    func testAppliedHeadGazeTurnsTowardTheTargetNotItsReflection() throws {
        let player = track([frame(0, 0, 0, 0), frame(2, 0, 0, 0)])
        let athlete = try ReplayAthleteFactory.make(for: player, lod: .near)
        let head = try XCTUnwrap(athlete.root.findEntity(named: ReplayAthleteJoint.headRoot.rawValue))
        for sign in [Float(-1), Float(1)] {
            ReplayAthleteMotion.update(athlete, from: player, at: 1,
                                       lookTargetWorldPosition: [sign * 10, 1.7, 10])
            let actualForward = head.orientation(relativeTo: athlete.root).act(forward)
            XCTAssertGreaterThan(actualForward.x * sign, 0.15)
            XCTAssertGreaterThan(actualForward.z, 0.5)
        }
    }

    func testPathTurnAndAuthoredFacingTurnHaveTheSameSignedConvention() {
        let right = track([frame(0, 0, -2, 0), frame(1, 0, 0, 0), frame(2, 2, 0, 0)])
        let left = track([frame(0, 0, -2, 0), frame(1, 0, 0, 0), frame(2, -2, 0, 0)])
        let turningOnSpot = track([frame(0, 0, 0, 0), frame(1, 0, 0, 45), frame(2, 0, 0, 90)])
        // Constant authored facing isolates the signed path curvature. A
        // stationary track then isolates the independently sampled facing turn.
        XCTAssertGreaterThan(right.locomotion(at: 1).turnRateDegreesPerSecond, 300)
        XCTAssertLessThan(left.locomotion(at: 1).turnRateDegreesPerSecond, -300)
        XCTAssertGreaterThan(turningOnSpot.locomotion(at: 1).turnRateDegreesPerSecond, 40)
    }
}
