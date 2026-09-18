import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Synthetic constraints for a render-only reaction. These do not establish a
/// goalkeeper save, measured match reaction time, or recovered pose accuracy.
@MainActor
final class ReplayGoalkeeperReadiness130Tests: XCTestCase {
    private func keeper(_ team: FootballTeam = .home, speed: Float = 0,
                        isGoalkeeper: Bool = true) -> PlayerTrack {
        .init(id: "keeper130-\(team.rawValue)", displayName: "Keeper", role: "GK", shirtNumber: 1,
              team: team, isGoalkeeper: isGoalkeeper, keyframes: [
                .init(time: 0, position: .init(x: 0, z: -speed), facingDegrees: 0),
                .init(time: 2, position: .init(x: 0, z: speed), facingDegrees: 0),
                .init(time: 4, position: .init(x: 0, z: speed * 3), facingDegrees: 0)
              ])
    }

    private func shot(side: Float = 1, time: Double = 1) -> ReplayGoalkeeperReadiness.Shot {
        .init(time: time, origin: [0, 0.5, 18], velocity: [side * 4, 0.8, -25])
    }

    private func sample(_ track: PlayerTrack, time: Double = 1,
                        ball: SIMD3<Float> = [0, 0.11, 18],
                        shot: ReplayGoalkeeperReadiness.Shot? = nil,
                        action: Float = 0) -> ReplayGoalkeeperReadiness.Sample? {
        ReplayGoalkeeperReadiness.sample(track: track, at: time,
            presentationPose: track.presentationPose(at: time), ballPosition: ball,
            shot: shot, actionInfluence: action)
    }

    private func base(_ track: PlayerTrack, time: Double = 1, phase: Float? = nil) -> ReplayAthleteLocomotionPose {
        ReplayAthleteMotion.locomotionPose(for: track, at: time, locomotion: track.locomotion(at: time),
            gaitPhase: phase, allowsOffBallPose: false)
    }

    private func rotations(_ pose: ReplayAthleteLocomotionPose) -> [SIMD4<Float>] {
        [pose.bodyOrientation, pose.hipsOrientation, pose.spineOrientation, pose.neckOrientation,
         pose.headOrientation, pose.leftHipOrientation, pose.rightHipOrientation,
         pose.leftKneeOrientation, pose.rightKneeOrientation, pose.leftAnkleOrientation,
         pose.rightAnkleOrientation, pose.leftShoulderOrientation, pose.rightShoulderOrientation,
         pose.leftElbowOrientation, pose.rightElbowOrientation,
         pose.leftWristOrientation, pose.rightWristOrientation].map(\.vector)
    }

    private func chain(_ pose: ReplayAthleteLocomotionPose, side: ReplayAthleteLeg)
        -> (hip: SIMD3<Float>, knee: SIMD3<Float>, ankle: SIMD3<Float>, boot: simd_quatf, sole: SIMD3<Float>) {
        let body = pose.bodyOrientation * pose.hipsOrientation
        let upper = body * (side == .left ? pose.leftHipOrientation : pose.rightHipOrientation)
        let lower = upper * (side == .left ? pose.leftKneeOrientation : pose.rightKneeOrientation)
        let boot = lower * (side == .left ? pose.leftAnkleOrientation : pose.rightAnkleOrientation)
        let hip = pose.bodyPosition + pose.bodyOrientation.act(pose.hipsPosition)
            + body.act([side == .left ? -0.137 : 0.137, -0.070, 0])
        let knee = hip + upper.act([0, -0.390, 0])
        let ankle = knee + lower.act([0, -0.350, 0])
        return (hip, knee, ankle, boot, ankle + boot.act(ReplayAthleteInteractionPose.bootSoleMarker))
    }

    func testFutureShotsAndTheAuthoredReactionDelayCannotRevealShotDirection() throws {
        for team in FootballTeam.allCases {
            let track = keeper(team)
            for time in [0.5, 0.999, 1.0, 1.10, 1.18] {
                let original = try XCTUnwrap(sample(track, time: time))
                for side: Float in [-1, 1] {
                    let actual = try XCTUnwrap(sample(track, time: time, shot: shot(side: side)))
                    XCTAssertEqual(actual, original, "Direction must not be visible before observed shot + delay")
                    XCTAssertEqual(actual.reaction, 0)
                    XCTAssertEqual(actual.lateralIntent, 0)
                }
            }
        }
    }

    func testDistanceBasedSetLowersNearDangerWithoutOverspreadingTheStance() throws {
        let track = keeper()
        let close = try XCTUnwrap(sample(track, ball: [0, 0.11, 2]))
        let medium = try XCTUnwrap(sample(track, ball: [0, 0.11, 15]))
        let far = try XCTUnwrap(sample(track, ball: [0, 0.11, 29]))
        XCTAssertGreaterThan(close.crouchMetres, medium.crouchMetres)
        XCTAssertGreaterThan(medium.crouchMetres, far.crouchMetres)
        XCTAssertEqual(close.reaction, 0)
        XCTAssertEqual(close.lateralShiftMetres, 0)
        XCTAssertLessThanOrEqual(close.crouchMetres, 0.048)
        XCTAssertNil(sample(track, ball: [0, 0.11, 31]))
        XCTAssertNil(sample(track, ball: [0, 0.11, -5]))
        let original = base(track)
        let prepared = ReplayGoalkeeperReadiness.apply(to: original, sample: close)
        let oldWidth = abs(chain(original, side: .right).sole.x - chain(original, side: .left).sole.x)
        let newWidth = abs(chain(prepared, side: .right).sole.x - chain(prepared, side: .left).sole.x)
        XCTAssertEqual(newWidth, oldWidth, accuracy: 0.00003)
        XCTAssertGreaterThan(newWidth, 0.28, "The keeper must have a stable outward stance, not crossed feet")
        XCTAssertLessThan(newWidth, 0.55, "Keep the existing near-shoulder-width base, not an X-block")
        XCTAssertLessThan(prepared.bodyPosition.y, original.bodyPosition.y)
    }

    func testObservedIncomingShotsReactToBothSidesAndRecoverWithoutDiveOrRootRotation() throws {
        for team in FootballTeam.allCases {
            let track = keeper(team)
            for side: Float in [-1, 1] {
                let value = try XCTUnwrap(sample(track, time: 1.42, ball: [side * 1.5, 1.4, 5], shot: shot(side: side)))
                XCTAssertGreaterThan(value.reaction, 0.95)
                XCTAssertGreaterThan(value.lateralIntent * side, 0.7)
                XCTAssertGreaterThan(value.lateralShiftMetres * side, 0)
                XCTAssertLessThanOrEqual(abs(value.lateralShiftMetres), 0.035)
                XCTAssertLessThanOrEqual(value.crouchMetres, 0.064)
                XCTAssertLessThanOrEqual(abs(value.chestRollRadians), 0.11)
                let original = base(track, time: 1.42)
                let result = ReplayGoalkeeperReadiness.apply(to: original, sample: value)
                XCTAssertEqual(result.bodyOrientation.vector, original.bodyOrientation.vector)
                XCTAssertEqual(result.hipsOrientation.vector, original.hipsOrientation.vector)
                XCTAssertEqual(result.hipsPosition, original.hipsPosition)
                XCTAssertEqual(result.bodyPosition.z, original.bodyPosition.z)
                XCTAssertEqual(result.neckOrientation.vector, original.neckOrientation.vector)
                XCTAssertEqual(result.headOrientation.vector, original.headOrientation.vector)
                XCTAssertEqual(sample(track, time: 2.5, shot: shot(side: side)), sample(track, time: 2.5))
            }
            let away = ReplayGoalkeeperReadiness.Shot(time: 1, origin: [0, 0.5, 18], velocity: [0, 1, 25])
            XCTAssertEqual(sample(track, time: 1.42, shot: away), sample(track, time: 1.42))
            let slow = ReplayGoalkeeperReadiness.Shot(time: 1, origin: [0, 0.5, 18], velocity: [0, 0, -2])
            XCTAssertEqual(sample(track, time: 1.42, shot: slow), sample(track, time: 1.42))
        }
    }

    func testBothFeetKeepTheirSoleGoalsBoneLengthsAndForwardKneePlanes() throws {
        for team in FootballTeam.allCases {
            for speed: Float in [0, 0.4, 1.5] {
                let track = keeper(team, speed: speed)
                for phase: Float in [0, 0.6, 1.8, 3.4, 5.8] {
                    for side: Float in [-1, 1] {
                        let value = try XCTUnwrap(sample(track, time: 1.42, ball: [side, 0.8, 4], shot: shot(side: side)))
                        let original = base(track, time: 1.42, phase: phase)
                        let result = ReplayGoalkeeperReadiness.apply(to: original, sample: value)
                        for leg in [ReplayAthleteLeg.left, .right] {
                            let before = chain(original, side: leg), after = chain(result, side: leg)
                            XCTAssertLessThan(simd_distance(after.sole, before.sole), 0.00003)
                            XCTAssertEqual(simd_distance(after.hip, after.knee), 0.390, accuracy: 0.00001)
                            XCTAssertEqual(simd_distance(after.knee, after.ankle), 0.350, accuracy: 0.00001)
                            XCTAssertGreaterThanOrEqual(after.sole.y, before.sole.y - 0.00003)
                            let down = simd_normalize(after.ankle - after.hip)
                            let bend = after.knee - after.hip - down * simd_dot(after.knee - after.hip, down)
                            XCTAssertGreaterThan(simd_dot(simd_normalize(bend), [0, 0, 1]), 0.3)
                            for axis in [SIMD3<Float>(1, 0, 0), [0, 1, 0], [0, 0, 1]] {
                                XCTAssertLessThan(simd_distance(before.boot.act(axis), after.boot.act(axis)), 0.00003)
                            }
                        }
                        for rotation in rotations(result) {
                            XCTAssertEqual(simd_length(rotation), 1, accuracy: 0.00001)
                        }
                    }
                }
            }
        }
    }

    func testSaveContactSuppressionAndInvalidOrOutfieldInputsHaveExactNilIdentity() throws {
        let track = keeper()
        for action: Float in [0.05, 0.3, 0.7, 1] {
            XCTAssertNil(sample(track, time: 1.42, shot: shot(), action: action))
        }
        XCTAssertNil(sample(track, action: .nan))
        XCTAssertNil(sample(track, action: -0.01))
        XCTAssertNil(sample(keeper(isGoalkeeper: false)))
        XCTAssertNil(sample(track, time: .nan))
        XCTAssertNil(sample(track, ball: [.nan, 0, 1]))
        XCTAssertNil(sample(track, time: 1.42,
            shot: .init(time: 1, origin: [0, 0.5, 18], velocity: [.nan, 0, -25])))
        XCTAssertNil(ReplayGoalkeeperReadiness.sample(track: track, at: 1,
            presentationPose: nil, ballPosition: [0, 0.11, 10]))
        XCTAssertNil(ReplayGoalkeeperReadiness.sample(track: track, at: 1,
            presentationPose: track.presentationPose(at: 1), ballPosition: nil))
        XCTAssertNil(ReplayGoalkeeperReadiness.sample(track: track, at: 1,
            presentationPose: .init(position: .zero, facingDegrees: .infinity), ballPosition: [0, 0.11, 10]))
        XCTAssertNil(ReplayGoalkeeperReadiness.sample(track: track, at: 1,
            presentationPose: track.presentationPose(at: 1), ballPosition: [0, 0.11, 10], enabled: false))
        let original = base(track)
        let missing = ReplayGoalkeeperReadiness.apply(to: original, sample: nil)
        XCTAssertEqual(rotations(missing), rotations(original))
        XCTAssertEqual(missing.bodyPosition, original.bodyPosition)
        let invalid = ReplayGoalkeeperReadiness.Sample(readiness: .nan, reaction: 1, lateralIntent: 1,
                                                      highShot: 0, closeRange: 0, stanceWeight: 1)
        XCTAssertEqual(rotations(ReplayGoalkeeperReadiness.apply(to: original, sample: invalid)), rotations(original))
    }

    func testReverseSeekIsExactAndReactionAdmissionRecoveryAndSuppressionAreContinuous() throws {
        let track = keeper()
        let times = [0.8, 1, 1.18, 1.25, 1.42, 1.75, 2.18, 2.5]
        let saved = times.map { sample(track, time: $0, shot: shot()) }
        let poses = times.enumerated().map { index, time in
            ReplayGoalkeeperReadiness.apply(to: base(track, time: time), sample: saved[index])
        }
        for index in times.indices.reversed() {
            let current = sample(track, time: times[index], shot: shot())
            XCTAssertEqual(current, saved[index])
            let pose = ReplayGoalkeeperReadiness.apply(to: base(track, time: times[index]), sample: current)
            XCTAssertEqual(rotations(pose), rotations(poses[index]))
            XCTAssertEqual(pose.bodyPosition, poses[index].bodyPosition)
        }
        for edge in [1.18, 1.34, 1.56, 2.18] {
            let a = try XCTUnwrap(sample(track, time: edge - 0.0001, shot: shot()))
            let b = try XCTUnwrap(sample(track, time: edge + 0.0001, shot: shot()))
            XCTAssertLessThan(abs(a.reaction - b.reaction), 0.001)
            let pa = ReplayGoalkeeperReadiness.apply(to: base(track, time: edge - 0.0001), sample: a)
            let pb = ReplayGoalkeeperReadiness.apply(to: base(track, time: edge + 0.0001), sample: b)
            for (index, pair) in zip(rotations(pa), rotations(pb)).enumerated() {
                XCTAssertLessThan(min(simd_distance(pair.0, pair.1), simd_distance(pair.0, -pair.1)),
                                  0.001, "Reaction edge \(edge), rotation \(index)")
            }
        }
        let nearlySuppressed = try XCTUnwrap(sample(track, time: 1.42, shot: shot(), action: 0.049))
        XCTAssertLessThan(nearlySuppressed.influence, 0.0001)
        let a = ReplayGoalkeeperReadiness.apply(to: base(track, time: 1.42), sample: nearlySuppressed)
        let b = base(track, time: 1.42)
        for (qa, qb) in zip(rotations(a), rotations(b)) {
            XCTAssertLessThan(min(simd_distance(qa, qb), simd_distance(qa, -qb)), 0.001)
        }
    }

    func testAnObservedInterveningTouchReleasesReactionWithoutFutureKnowledgeOrReactivation() throws {
        let track = keeper()
        let uninterrupted = shot()
        var interrupted = uninterrupted
        interrupted.supersededAt = 1.42
        for time in [1.0, 1.25, 1.4199, 1.42] {
            XCTAssertEqual(sample(track, time: time, shot: interrupted),
                           sample(track, time: time, shot: uninterrupted))
        }
        var previous: Float = 1
        for time in [1.44, 1.47, 1.50, 1.521] {
            let releasing = try XCTUnwrap(sample(track, time: time, shot: interrupted))
            XCTAssertLessThan(releasing.reaction, previous)
            previous = releasing.reaction
        }
        for time in [1.521, 1.8, 2.0, 2.5] {
            XCTAssertEqual(sample(track, time: time, shot: interrupted), sample(track, time: time))
        }
        for edge in [1.42, 1.52] {
            let a = try XCTUnwrap(sample(track, time: edge - 0.0001, shot: interrupted))
            let b = try XCTUnwrap(sample(track, time: edge + 0.0001, shot: interrupted))
            XCTAssertLessThan(abs(a.reaction - b.reaction), 0.001)
            let pa = ReplayGoalkeeperReadiness.apply(to: base(track, time: edge - 0.0001), sample: a)
            let pb = ReplayGoalkeeperReadiness.apply(to: base(track, time: edge + 0.0001), sample: b)
            for (qa, qb) in zip(rotations(pa), rotations(pb)) {
                XCTAssertLessThan(min(simd_distance(qa, qb), simd_distance(qa, -qb)), 0.001)
            }
        }
        interrupted.supersededAt = 0.9
        XCTAssertNil(sample(track, time: 1.42, shot: interrupted))
        interrupted.supersededAt = .nan
        XCTAssertNil(sample(track, time: 1.42, shot: interrupted))
    }

    func testMovingKeeperKeepsLocomotionAndTeamDoesNotChangeReactionRules() throws {
        let home = keeper(.home), away = keeper(.away)
        XCTAssertEqual(sample(home, time: 1.42, shot: shot()), sample(away, time: 1.42, shot: shot()))
        let sprinting = keeper(speed: 4)
        XCTAssertNil(sample(sprinting, ball: [0, 0.11, 10]))
        let reacting = try XCTUnwrap(sample(sprinting, time: 1.42, ball: [0, 0.11, 10], shot: shot()))
        XCTAssertEqual(reacting.stanceWeight, 0)
        XCTAssertEqual(reacting.crouchMetres, 0)
        XCTAssertEqual(reacting.lateralShiftMetres, 0)
        XCTAssertGreaterThan(reacting.reaction, 0)
        XCTAssertLessThanOrEqual(reacting.reaction, 0.4)
        let original = base(sprinting, time: 1.42)
        let prepared = ReplayGoalkeeperReadiness.apply(to: original, sample: reacting)
        XCTAssertEqual(prepared.leftHipOrientation.vector, original.leftHipOrientation.vector)
        XCTAssertEqual(prepared.rightHipOrientation.vector, original.rightHipOrientation.vector)
        XCTAssertEqual(prepared.leftKneeOrientation.vector, original.leftKneeOrientation.vector)
        XCTAssertEqual(prepared.rightKneeOrientation.vector, original.rightKneeOrientation.vector)
        XCTAssertEqual(prepared.leftAnkleOrientation.vector, original.leftAnkleOrientation.vector)
        XCTAssertEqual(prepared.rightAnkleOrientation.vector, original.rightAnkleOrientation.vector)
    }

    func testFullKeeperReadinessSuppressesTheOrdinaryOffBallUpperBodyLayer() throws {
        for team in FootballTeam.allCases {
            let track = keeper(team)
            let time = 1.42
            let ball: SIMD3<Float> = [0.5, 0.8, 4]
            let readiness = try XCTUnwrap(sample(track, time: time, ball: ball, shot: shot()))
            XCTAssertEqual(readiness.influence, 1)
            func prepared(offBall: Bool) -> ReplayAthleteLocomotionPose {
                ReplayAthleteMotion.locomotionPose(for: track, at: time,
                    locomotion: track.locomotion(at: time), lookTargetWorldPosition: ball,
                    presentationPose: track.presentationPose(at: time), allowsOffBallPose: offBall,
                    goalkeeperReadiness: readiness)
            }
            let enabled = prepared(offBall: true), disabled = prepared(offBall: false)
            XCTAssertEqual(rotations(enabled), rotations(disabled))
            XCTAssertEqual(enabled.bodyPosition, disabled.bodyPosition)
            XCTAssertEqual(enabled.hipsPosition, disabled.hipsPosition)
        }
    }

    func testDefensiveActionCeilingLeavesFreshEasingUntouchedAndReleasesStaleReadiness() throws {
        let track = keeper()
        let stale = try XCTUnwrap(sample(track, time: 1.42, shot: shot()))
        var previous = stale.influence
        for action: Float in [0, 0.001, 0.01, 0.025, 0.04, 0.049] {
            let fresh = sample(track, time: 1.42, shot: shot(), action: action)
            XCTAssertEqual(ReplayGoalkeeperReadiness.limited(fresh, actionInfluence: action), fresh,
                           "A fresh sample must not receive a second fade")
            let capped = try XCTUnwrap(ReplayGoalkeeperReadiness.limited(stale, actionInfluence: action))
            XCTAssertLessThanOrEqual(capped.influence, previous)
            previous = capped.influence
        }
        XCTAssertLessThan(previous, 0.0001)
        XCTAssertNil(ReplayGoalkeeperReadiness.limited(stale, actionInfluence: 0.05))
    }

    func testNativeNearAndLowBothTeamsKeepGroundedSolesBoneLengthsAndExactRewind() throws {
        defer {
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayAthleteHeadProvider.resetForTesting()
        }
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        for team in FootballTeam.allCases {
            let track = keeper(team)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
                let root = skin.root.transform
                let right = try XCTUnwrap(skin.motion.footContacts["right"])
                let left = try XCTUnwrap(skin.motion.footContacts["left"])
                // Source names are anatomical: R_Foot=-X, L_Foot=+X. Both
                // plants are checked, not a mislabeled legacy gait lane.
                XCTAssertLessThan(skin.motion.restPose.modelSpaceTransforms[right.footJointIndex].columns.3.x, 0)
                XCTAssertGreaterThan(skin.motion.restPose.modelSpaceTransforms[left.footJointIndex].columns.3.x, 0)
                let times = [1.0, 1.25, 1.42, 1.75, 2.25]
                var saved: [[Transform]] = []
                let ball: SIMD3<Float> = [1.5, 1.2, 5]
                func update(_ time: Double) throws {
                    let readiness = try XCTUnwrap(sample(track, time: time, ball: ball, shot: shot()))
                    XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                        lookTarget: ball, ballAction: nil, presentationPose: track.presentationPose(at: time),
                        goalkeeperReadiness: readiness))
                }
                for time in times {
                    try update(time)
                    saved.append(skin.model.jointTransforms)
                    XCTAssertEqual(skin.root.transform, root)
                    XCTAssertEqual(skin.model.jointTransforms.count, 80)
                    XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                                               skin.contactSurface.paddingMetres - 0.0001)
                    func sole(_ contact: ReplaySkinnedAthleteMotion.FootContact) -> SIMD3<Float> {
                        let p = skin.pose.modelSpaceTransforms[contact.footJointIndex] * SIMD4(contact.solePoint, 1)
                        return [p.x, p.y - skin.motion.geometry.restMinY, p.z]
                    }
                    let a = sole(left), b = sole(right)
                    XCTAssertGreaterThanOrEqual(min(a.y, b.y), -0.001)
                    XCTAssertLessThan(min(a.y, b.y), 0.03, "A set must have a planted foot, not hover")
                    XCTAssertGreaterThan(a.x - b.x, 0.18)
                    XCTAssertLessThan(a.x - b.x, 0.60, "No X-block or uncontrolled leg spread")
                    for side in ["left", "right"] {
                        for pair in [("Hip", "Knee"), ("Knee", "Ankle"), ("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                            let first = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                            let second = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                            let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[first].columns.3,
                                                     skin.motion.restPose.modelSpaceTransforms[second].columns.3)
                            let current = simd_distance(skin.pose.modelSpaceTransforms[first].columns.3,
                                                        skin.pose.modelSpaceTransforms[second].columns.3)
                            XCTAssertEqual(current, rest, accuracy: 0.0002)
                        }
                    }
                    for rotation in skin.pose.rotations {
                        XCTAssertEqual(simd_length(rotation.vector), 1, accuracy: 0.0001)
                    }
                }
                for index in times.indices.reversed() {
                    try update(times[index])
                    XCTAssertEqual(skin.model.jointTransforms, saved[index])
                }
                let contact = ReplayAthleteInteractionCue(playerID: track.id, kind: .save,
                    contactTime: 1, startTime: 0.7, endTime: 1.4, kickingLeg: .right,
                    contactBallWorldPosition: [0, 0.8, 0.4], outgoingDirectionWorld: [0, 1, 1])
                let action = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: contact, at: 1, track: track))
                let suppressed = sample(track, ball: contact.contactBallWorldPosition,
                                        shot: shot(time: 0.6), action: action.influence)
                XCTAssertNil(suppressed)
                _ = skin.update(at: 1, track: track, locomotion: track.locomotion(at: 1),
                    lookTarget: contact.contactBallWorldPosition, ballAction: nil, interaction: contact,
                    presentationPose: track.presentationPose(at: 1))
                let exactSave = skin.model.jointTransforms
                _ = skin.update(at: 1, track: track, locomotion: track.locomotion(at: 1),
                    lookTarget: contact.contactBallWorldPosition, ballAction: nil, interaction: contact,
                    presentationPose: track.presentationPose(at: 1), goalkeeperReadiness: suppressed)
                XCTAssertEqual(skin.model.jointTransforms, exactSave)
                let staleReady = try XCTUnwrap(sample(track, time: 1.42, ball: [0, 0.8, 4], shot: shot()))
                _ = skin.update(at: 1, track: track, locomotion: track.locomotion(at: 1),
                    lookTarget: contact.contactBallWorldPosition, ballAction: nil, interaction: contact,
                    presentationPose: track.presentationPose(at: 1), goalkeeperReadiness: staleReady)
                XCTAssertEqual(skin.model.jointTransforms, exactSave,
                               "A caller's stale non-nil preparation must not deform an explicit save")
            }
        }
    }

    func testActualVolleyKeeperMovingSetKeepsNativeSoleLanesAndBoneLengths() async throws {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        defer {
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayNativeBallPhysics.resetCacheForTesting()
        }
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-81-volley-v2" })
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        let track = try XCTUnwrap(scenario.players.first { $0.id == "arg-23" })
        let shots = ReplayFootballShotTimeline(touches: recording.touches, players: scenario.players)
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
            let root = skin.root.transform
            let times = [7.35, 7.4, 7.55, 7.65, 7.75, 7.78, 7.8, 7.9, 8.0]
            var saved: [[Transform]] = []
            func update(_ time: Double) throws {
                let ball = recording.sample(at: time).position
                let readiness = try XCTUnwrap(ReplayGoalkeeperReadiness.sample(track: track, at: time,
                    presentationPose: track.presentationPose(at: time), ballPosition: ball,
                    shot: shots.latestOpposingShot(for: track, at: time)))
                XCTAssertGreaterThan(max(readiness.readiness, readiness.reaction * readiness.stanceWeight), 0.45)
                XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                    lookTarget: ball, ballAction: nil, presentationPose: track.presentationPose(at: time),
                    goalkeeperReadiness: readiness))
            }
            for time in times {
                try update(time)
                saved.append(skin.model.jointTransforms)
                XCTAssertEqual(skin.root.transform, root)
                func sole(_ side: String) throws -> SIMD3<Float> {
                    let contact = try XCTUnwrap(skin.motion.footContacts[side])
                    let value = skin.pose.modelSpaceTransforms[contact.footJointIndex] * SIMD4(contact.solePoint, 1)
                    return [value.x, value.y - skin.motion.geometry.restMinY, value.z]
                }
                let left = try sole("left"), right = try sole("right")
                XCTAssertGreaterThan(left.x - right.x, 0.18, "Native moving set at \(time)")
                XCTAssertLessThan(left.x - right.x, 0.60, "No X-block at \(time)")
                XCTAssertGreaterThanOrEqual(min(left.y, right.y), -0.001)
                XCTAssertLessThan(min(left.y, right.y), 0.03)
                for side in ["left", "right"] {
                    for pair in [("Hip", "Knee"), ("Knee", "Ankle")] {
                        let first = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                        let second = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                        let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[first].columns.3,
                                                skin.motion.restPose.modelSpaceTransforms[second].columns.3)
                        let current = simd_distance(skin.pose.modelSpaceTransforms[first].columns.3,
                                                   skin.pose.modelSpaceTransforms[second].columns.3)
                        XCTAssertEqual(current, rest, accuracy: 0.0002)
                    }
                }
            }
            for index in times.indices.reversed() {
                try update(times[index])
                XCTAssertEqual(skin.model.jointTransforms, saved[index])
            }
            let contactPose = track.presentationPose(at: 7.78)
            let cue = ReplayAthleteInteractionCue(playerID: track.id, kind: .save,
                contactTime: 7.78, startTime: 7.6, endTime: 8.0, kickingLeg: .right,
                contactBallWorldPosition: [contactPose.position.x - 0.1, 0.8, contactPose.position.z - 0.3],
                outgoingDirectionWorld: [0, 1, -1])
            let stale = try XCTUnwrap(ReplayGoalkeeperReadiness.sample(track: track, at: 7.78,
                presentationPose: contactPose, ballPosition: recording.sample(at: 7.78).position,
                shot: shots.latestOpposingShot(for: track, at: 7.78)))
            for staleInput in [false, true] {
                for edge in [cue.startTime, cue.endTime] {
                    var before: ReplaySkinnedAthleteMotion.Pose?
                    for time in [edge - 0.0001, edge + 0.0001] {
                        let presented = track.presentationPose(at: time)
                        let ball = recording.sample(at: time).position
                        let action = ReplayAthleteInteractionPose.sample(cue: cue, at: time,
                            track: track, presentationPose: presented)?.influence ?? 0
                        let fresh = ReplayGoalkeeperReadiness.sample(track: track, at: time,
                            presentationPose: presented, ballPosition: ball,
                            shot: shots.latestOpposingShot(for: track, at: time), actionInfluence: action)
                        XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                            lookTarget: ball, ballAction: nil, interaction: cue, presentationPose: presented,
                            goalkeeperReadiness: staleInput ? stale : fresh))
                        if let before {
                            for side in ["left", "right"] {
                                for joint in ["Hip", "Knee", "Ankle"] {
                                    let index = try XCTUnwrap(skin.motion.semanticJointIndices[side + joint])
                                    XCTAssertLessThan(simd_distance(before.modelSpaceTransforms[index].columns.3,
                                        skin.pose.modelSpaceTransforms[index].columns.3), 0.001,
                                        "Keeper sole-layer cue edge \(edge), stale=\(staleInput), \(side)\(joint)")
                                    let a = before.rotations[index].vector, b = skin.pose.rotations[index].vector
                                    XCTAssertLessThan(min(simd_distance(a, b), simd_distance(a, -b)), 0.001)
                                }
                            }
                        } else { before = skin.pose }
                    }
                }
            }
        }
    }
}
