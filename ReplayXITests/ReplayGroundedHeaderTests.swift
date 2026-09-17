import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayGroundedHeaderTests: XCTestCase {
    private func player(_ team: FootballTeam) -> PlayerTrack {
        .init(id: "header-\(team.rawValue)", displayName: "Header", role: "Forward", shirtNumber: 10,
              team: team, isGoalkeeper: false,
              keyframes: [.init(time: 0, position: .init(x: 0, z: -0.6), facingDegrees: -10),
                          .init(time: 2, position: .init(x: 0, z: 0.6), facingDegrees: 10)])
    }

    private func cue(_ player: PlayerTrack, support: ReplayAthleteLeg?, kind: ReplayAthleteInteractionCue.Kind = .header)
        -> ReplayAthleteInteractionCue {
        .init(playerID: player.id, kind: kind, contactTime: 1, startTime: 0.68, endTime: 1.42,
              kickingLeg: .right, contactBallWorldPosition: [0, 1.75, 0.24],
              outgoingDirectionWorld: [1, 0.1, 1], headerSupportLeg: support)
    }

    private func sole(_ pose: ReplayAthleteLocomotionPose, _ side: ReplayAthleteLeg) -> SIMD3<Float> {
        let hips = pose.bodyOrientation * pose.hipsOrientation
        let hip = hips * (side == .left ? pose.leftHipOrientation : pose.rightHipOrientation)
        let knee = hip * (side == .left ? pose.leftKneeOrientation : pose.rightKneeOrientation)
        let ankle = knee * (side == .left ? pose.leftAnkleOrientation : pose.rightAnkleOrientation)
        return pose.bodyPosition + pose.bodyOrientation.act(pose.hipsPosition)
            + hips.act([side == .left ? -0.137 : 0.137, -0.070, 0])
            + hip.act([0, -0.390, 0]) + knee.act([0, -0.350, 0])
            + ankle.act(ReplayAthleteInteractionPose.bootSoleMarker)
    }

    func testExplicitPlantDoesNotDependOnTeamOrKickingFoot() throws {
        for team in FootballTeam.allCases {
            let track = player(team)
            for support in [ReplayAthleteLeg.left, .right] {
                let action = cue(track, support: support)
                for time in [0.95, 0.975, 1.0, 1.025, 1.05, 1.0] {
                    let presented = track.presentationPose(at: time)
                    let sample = try XCTUnwrap(ReplayAthleteInteractionPose.sample(
                        cue: action, at: time, track: track, presentationPose: presented))
                    XCTAssertTrue(sample.plantsFeet)
                    XCTAssertEqual(sample.headerSupportLeg, support)
                    XCTAssertEqual(sample.headerSupportLane, support.opposite)
                    let pose = ReplayAthleteMotion.locomotionPose(for: track, at: time, locomotion: track.locomotion(at: time),
                        interaction: action, presentationPose: presented, allowsOffBallPose: false)
                    let facing = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
                    let world = SIMD3<Float>(presented.position.x, 0, presented.position.z)
                        + facing.act(sole(pose, support.opposite))
                    XCTAssertLessThan(simd_distance(world, [support == .right ? -0.137 : 0.137, 0, 0.035]), 0.0001)
                    XCTAssertGreaterThan(sole(pose, support).y, 0.02)
                }
            }
        }
    }

    func testUnspecifiedHeaderRetainsLegacyGaitAndNonHeaderPlantIsRejected() throws {
        let track = player(.away)
        let legacy = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: cue(track, support: nil), at: 1, track: track))
        XCTAssertFalse(legacy.plantsFeet)
        XCTAssertNil(legacy.headerSupportLeg)
        XCTAssertNil(ReplayAthleteInteractionPose.sample(cue: cue(track, support: .right, kind: .save), at: 1, track: track))
    }

    func testPlantedHeaderSeeksExactlyAndEntersWithoutPosePop() {
        let track = player(.home)
        let action = cue(track, support: .right)
        let first = ReplayAthleteMotion.locomotionPose(for: track, at: 1, interaction: action)
        for time in [1.32, 0.76, 1.05, 0.71, 1.42] {
            _ = ReplayAthleteMotion.locomotionPose(for: track, at: time, interaction: action)
        }
        let repeated = ReplayAthleteMotion.locomotionPose(for: track, at: 1, interaction: action)
        XCTAssertEqual(first.rightHipOrientation.vector, repeated.rightHipOrientation.vector)
        XCTAssertEqual(first.rightAnkleOrientation.vector, repeated.rightAnkleOrientation.vector)
        for edge in [action.startTime, action.endTime] {
            let a = ReplayAthleteMotion.locomotionPose(for: track, at: edge - 0.0001, interaction: action)
            let b = ReplayAthleteMotion.locomotionPose(for: track, at: edge + 0.0001, interaction: action)
            XCTAssertLessThan(simd_distance(a.rightHipOrientation.vector, b.rightHipOrientation.vector), 0.001)
            XCTAssertLessThan(simd_distance(a.bodyPosition, b.bodyPosition), 0.001)
        }
    }

    func testNativeSupportFootStaysOnItsWorldPlantAcrossBothTeamsAndDetails() throws {
        defer {
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayAthleteHeadProvider.resetForTesting()
        }
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        for team in FootballTeam.allCases {
            let track = player(team)
            let action = cue(track, support: .right)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
                let foot = try XCTUnwrap(skin.motion.footContacts["right"])
                // Validate the source's real anatomical R_Foot, not the
                // opposite +X lane called `.right` by the legacy proxy gait.
                XCTAssertLessThan(skin.motion.restPose.modelSpaceTransforms[foot.footJointIndex].columns.3.x, 0)
                XCTAssertGreaterThan(skin.contactSurface.headerProbeCount, 8)
                XCTAssertLessThanOrEqual(skin.contactSurface.headerProbeCount, 96)
                var first: SIMD3<Float>?
                for time in [0.95, 0.975, 1.0, 1.025, 1.05, 1.0] {
                    let presented = track.presentationPose(at: time)
                    XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                        lookTarget: action.contactBallWorldPosition, ballAction: nil,
                        interaction: action, presentationPose: presented))
                    let local = skin.pose.modelSpaceTransforms[foot.footJointIndex] * SIMD4(foot.solePoint, 1)
                    let heading = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
                    let world = SIMD3<Float>(presented.position.x, 0, presented.position.z)
                        + heading.act([local.x, local.y - skin.motion.geometry.restMinY, local.z])
                    XCTAssertLessThan(simd_distance(SIMD2(world.x, world.z), [-0.137, 0.035]), 0.002)
                    XCTAssertGreaterThanOrEqual(world.y, -0.001)
                    XCTAssertLessThan(world.y, 0.02)
                    if let first { XCTAssertLessThan(simd_distance(SIMD2(first.x, first.z), SIMD2(world.x, world.z)), 0.002) }
                    else { first = world }
                }
            }
        }
    }
}
