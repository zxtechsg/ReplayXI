import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAthleteBallActionTests: XCTestCase {
    func testSyntheticOverlapInfersControlPassAndCutbackFromTrackContact() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let winger = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let rightBack = try XCTUnwrap(scenario.player(id: "navy-rb"))

        let control = try XCTUnwrap(
            ReplayAthleteMotion.ballActionPose(
                for: winger,
                ballTrack: scenario.ball,
                at: 10.1
            )
        )
        let pass = try XCTUnwrap(
            ReplayAthleteMotion.ballActionPose(
                for: winger,
                ballTrack: scenario.ball,
                at: 13.6
            )
        )
        let cutback = try XCTUnwrap(
            ReplayAthleteMotion.ballActionPose(
                for: rightBack,
                ballTrack: scenario.ball,
                at: 17.5
            )
        )

        XCTAssertEqual(control.kind, .controlTouch)
        XCTAssertEqual(control.contactTime, 10.1, accuracy: 0.000_1)
        XCTAssertGreaterThan(control.influence, 0.60)

        XCTAssertEqual(pass.kind, .pass)
        XCTAssertEqual(pass.contactTime, 13.6, accuracy: 0.000_1)
        XCTAssertEqual(pass.kickingLeg, .right)
        XCTAssertEqual(pass.supportLeg, .left)
        XCTAssertGreaterThan(pass.influence, 0.55)

        XCTAssertEqual(cutback.kind, .cutback)
        XCTAssertEqual(cutback.contactTime, 17.5, accuracy: 0.000_1)
        XCTAssertEqual(cutback.kickingLeg, .left)
        XCTAssertEqual(cutback.supportLeg, .right)
        XCTAssertGreaterThan(cutback.influence, 0.75)
    }

    func testActionLayerRejectsPlayersWhoDoNotOwnTheContact() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let leftBack = try XCTUnwrap(scenario.player(id: "navy-lb"))
        let defender = try XCTUnwrap(scenario.player(id: "red-rcb"))

        XCTAssertNil(
            ReplayAthleteMotion.ballActionPose(
                for: leftBack,
                ballTrack: scenario.ball,
                at: 13.6
            )
        )
        XCTAssertNil(
            ReplayAthleteMotion.ballActionPose(
                for: defender,
                ballTrack: scenario.ball,
                at: 17.5
            )
        )
        XCTAssertNil(
            ReplayAthleteMotion.ballActionPose(
                for: leftBack,
                ballTrack: scenario.ball,
                at: .nan
            )
        )
    }

    func testActionSamplingIsExactlySeekAndReverseDeterministic() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let winger = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let times = [13.34, 13.42, 13.54, 13.6, 13.72, 13.84, 13.96]

        let forward = times.map {
            ReplayAthleteMotion.ballActionPose(
                for: winger,
                ballTrack: scenario.ball,
                at: $0
            )
        }
        let reverse = times.reversed().map {
            ReplayAthleteMotion.ballActionPose(
                for: winger,
                ballTrack: scenario.ball,
                at: $0
            )
        }.reversed()

        XCTAssertEqual(forward, Array(reverse))
        XCTAssertEqual(
            ReplayAthleteMotion.ballActionPose(
                for: winger,
                ballTrack: scenario.ball,
                at: 13.6
            ),
            ReplayAthleteMotion.ballActionPose(
                for: winger,
                ballTrack: scenario.ball,
                at: 13.6
            )
        )
    }

    func testPassPosePlantsSupportBootAndArticulatesKickingLegWithoutMovingBall() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let winger = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let ballBefore = scenario.ball.pose(at: 13.6)
        let baseline = ReplayAthleteMotion.locomotionPose(for: winger, at: 13.6)
        let action = ReplayAthleteMotion.locomotionPose(
            for: winger,
            at: 13.6,
            ballTrack: scenario.ball
        )

        XCTAssertNotEqual(action.rightHipOrientation, baseline.rightHipOrientation)
        XCTAssertNotEqual(action.rightKneeOrientation, baseline.rightKneeOrientation)
        XCTAssertNotEqual(action.leftAnkleOrientation, baseline.leftAnkleOrientation)

        let rig = try ReplayAthleteFactory.make(for: winger, lod: .near)
        ReplayAthleteMotion.update(
            rig,
            from: winger,
            at: 13.6,
            ballTrack: scenario.ball
        )
        let supportBoot = try XCTUnwrap(rig.root.findEntity(named: "left-boot"))
        let kickingBoot = try XCTUnwrap(rig.root.findEntity(named: "right-boot"))
        let supportMinimum = supportBoot.visualBounds(relativeTo: rig.root).min.y
        let kickingMinimum = kickingBoot.visualBounds(relativeTo: rig.root).min.y

        XCTAssertGreaterThanOrEqual(supportMinimum, -0.012)
        XCTAssertLessThanOrEqual(supportMinimum, 0.035)
        XCTAssertGreaterThanOrEqual(kickingMinimum, -0.012)

        // At contact both boots can legitimately skim the turf. The readable
        // lift belongs to follow-through, while the opposite boot stays loaded.
        ReplayAthleteMotion.update(
            rig,
            from: winger,
            at: 13.78,
            ballTrack: scenario.ball
        )
        let followThroughSupport = supportBoot.visualBounds(relativeTo: rig.root).min.y
        let followThroughKick = kickingBoot.visualBounds(relativeTo: rig.root).min.y
        let contactAction = try XCTUnwrap(
            ReplayAthleteMotion.ballActionPose(
                for: winger,
                ballTrack: scenario.ball,
                at: 13.6
            )
        )
        let followThroughAction = try XCTUnwrap(
            ReplayAthleteMotion.ballActionPose(
                for: winger,
                ballTrack: scenario.ball,
                at: 13.78
            )
        )
        XCTAssertGreaterThanOrEqual(followThroughSupport, -0.012)
        XCTAssertLessThanOrEqual(followThroughSupport, 0.040)
        XCTAssertGreaterThan(
            followThroughAction.kickingKneeFlexion,
            contactAction.kickingKneeFlexion + 0.15
        )
        XCTAssertGreaterThan(followThroughKick, followThroughSupport + 0.002)
        XCTAssertEqual(scenario.ball.pose(at: 13.6), ballBefore)
    }
}
