import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Bone lengths must stay constant during preparation and release, not only
/// at the full-support contact frame. These are synthetic rig constraints.
@MainActor
final class ReplaySkinnedAthleteContactTransitionTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func track(team: FootballTeam, speed: Float = 1.1) -> PlayerTrack {
        .init(id: "contact-transition-\(team.rawValue)", displayName: "Transition", role: "CM",
              shirtNumber: 8, team: team, isGoalkeeper: false, keyframes: [
                .init(time: 0, position: .init(x: 0, z: -speed * 5), facingDegrees: 0),
                .init(time: 10, position: .init(x: 0, z: speed * 5), facingDegrees: 0)
              ])
    }

    private func cue(_ track: PlayerTrack, kind: ReplayAthleteInteractionCue.Kind,
                     side: ReplayAthleteLeg) -> ReplayAthleteInteractionCue {
        .init(playerID: track.id, kind: kind, contactTime: 5, startTime: 4.6, endTime: 5.4,
              kickingLeg: side,
              contactBallWorldPosition: [side == .left ? -0.137 : 0.137, kind == .shot ? 0.65 : 0.11, 0.46],
              outgoingDirectionWorld: [side == .left ? -0.2 : 0.2, 0, 1])
    }

    private func position(_ pose: ReplaySkinnedAthleteMotion.Pose, index: Int) -> SIMD3<Float> {
        let point = pose.modelSpaceTransforms[index].columns.3
        return [point.x, point.y, point.z]
    }

    private func assertLegLengths(_ pose: ReplaySkinnedAthleteMotion.Pose,
                                  motion: ReplaySkinnedAthleteMotion,
                                  context: String, file: StaticString = #filePath, line: UInt = #line) throws {
        for side in ["left", "right"] {
            for (first, second) in [("Hip", "Knee"), ("Knee", "Ankle")] {
                let a = try XCTUnwrap(motion.semanticJointIndices[side + first])
                let b = try XCTUnwrap(motion.semanticJointIndices[side + second])
                let length = simd_distance(position(pose, index: a), position(pose, index: b))
                let rest = simd_distance(position(motion.restPose, index: a), position(motion.restPose, index: b))
                XCTAssertEqual(length, rest, accuracy: 0.0002,
                               "\(context) \(side) \(first)-\(second) must not shrink during contact blending",
                               file: file, line: line)
            }
        }
    }

    func testContactPreparationKeepsRealThighAndShinLengthsForBothTeams() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var partialFrames = 0
        for team in FootballTeam.allCases {
            let track = track(team: team)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
                var retargeter = try XCTUnwrap(ReplaySkinnedAthleteFootballPose(
                    motion: skin.motion, bootMarkers: skin.bootMarkers))
                for kind in [ReplayAthleteInteractionCue.Kind.pass, .shot] {
                    for side in [ReplayAthleteLeg.left, .right] {
                        let cue = cue(track, kind: kind, side: side)
                        for time in [4.61, 4.68, 4.78, 4.9, 5, 5.18, 5.30, 5.38] {
                            let locomotion = track.locomotion(at: time)
                            let interaction = try XCTUnwrap(ReplayAthleteInteractionPose.sample(
                                cue: cue, at: time, track: track))
                            if interaction.influence < 1 { partialFrames += 1 }
                            let authored = ReplayAthleteMotion.locomotionPose(
                                for: track, at: time, locomotion: locomotion,
                                gaitPhase: track.gaitPhase(at: time), interaction: cue,
                                allowsOffBallPose: false)
                            var pose = skin.motion.makePoseBuffer()
                            skin.motion.sample(time: time, locomotionEffort: locomotion.effort,
                                               gaitPhase: track.gaitPhase(at: time), into: &pose)
                            retargeter.apply(authored, influence: 1, armInfluence: 1,
                                             motion: skin.motion, to: &pose, interaction: interaction)
                            skin.motion.rebuildModelSpaceTransforms(in: &pose)
                            try assertLegLengths(pose, motion: skin.motion,
                                context: "\(team) \(detail) \(kind) \(side) at \(time)")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(partialFrames, 80)
    }

    func testActualSkinContactTransitionsKeepBonesFloorAndExactRewind() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let times = [4.61, 4.7, 4.85, 4.945, 5, 5.07, 5.25, 5.39]
        for team in FootballTeam.allCases {
            let track = track(team: team)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
                let cue = cue(track, kind: .pass, side: team == .home ? .left : .right)
                func seek(_ time: Double) {
                    XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                        lookTarget: cue.contactBallWorldPosition, ballAction: nil, interaction: cue,
                        presentationPose: track.presentationPose(at: time)))
                }
                var saved: [[Transform]] = []
                for time in times {
                    seek(time)
                    try assertLegLengths(skin.pose, motion: skin.motion, context: "\(team) \(detail) at \(time)")
                    XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose)
                        - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.0001)
                    XCTAssertTrue(skin.pose.rotations.allSatisfy { abs(simd_length($0.vector) - 1) < 0.0001 })
                    saved.append(skin.model.jointTransforms)
                }
                for index in times.indices.reversed() {
                    seek(times[index])
                    XCTAssertEqual(skin.model.jointTransforms, saved[index])
                }
            }
        }
    }

    func testPreparationAndFullContactEdgesDoNotSnap() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let track = track(team: .away)
        let skin = try ReplaySkinnedAthleteProvider.make(for: track)
        let cue = cue(track, kind: .shot, side: .right)
        for edge in [cue.startTime, cue.contactTime - 0.055, cue.contactTime + 0.070, cue.endTime] {
            func seek(_ time: Double) {
                XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                    lookTarget: nil, ballAction: nil, interaction: cue))
            }
            seek(edge - 0.00001)
            let before = skin.pose
            seek(edge + 0.00001)
            for side in ["left", "right"] {
                for name in ["Hip", "Knee", "Ankle"] {
                    let index = try XCTUnwrap(skin.motion.semanticJointIndices[side + name])
                    XCTAssertLessThan(simd_distance(position(before, index: index),
                                                    position(skin.pose, index: index)), 0.002)
                    XCTAssertGreaterThan(abs(simd_dot(before.rotations[index].vector,
                                                      skin.pose.rotations[index].vector)), 0.9999)
                }
            }
        }
    }
}
