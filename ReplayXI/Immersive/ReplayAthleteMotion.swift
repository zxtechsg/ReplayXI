import Foundation
import RealityKit
import simd

/// Absolute-time articulation generated from match telemetry.  This value is
/// independent of rendered frame count, playback direction and playback rate.
struct ReplayAthleteLocomotionPose: Sendable {
    let bodyPosition: SIMD3<Float>
    let bodyOrientation: simd_quatf
    let hipsPosition: SIMD3<Float>
    let hipsOrientation: simd_quatf
    let spineOrientation: simd_quatf
    let neckOrientation: simd_quatf
    let headOrientation: simd_quatf
    let leftHipOrientation: simd_quatf
    let rightHipOrientation: simd_quatf
    let leftKneeOrientation: simd_quatf
    let rightKneeOrientation: simd_quatf
    let leftAnkleOrientation: simd_quatf
    let rightAnkleOrientation: simd_quatf
    let leftShoulderOrientation: simd_quatf
    let rightShoulderOrientation: simd_quatf
    let leftElbowOrientation: simd_quatf
    let rightElbowOrientation: simd_quatf
    let leftWristOrientation: simd_quatf
    let rightWristOrientation: simd_quatf
}

/// Biomechanically bounded local gaze distributed across the cervical chain.
/// Values are exposed independently of RealityKit transforms so the seek-stable
/// intent can be verified without relying on rendered pixels.
struct ReplayAthleteLookPose: Equatable, Sendable {
    let neckYawRadians: Float
    let headYawRadians: Float
    let neckPitchRadians: Float
    let headPitchRadians: Float

    var combinedYawRadians: Float { neckYawRadians + headYawRadians }
    var combinedPitchRadians: Float { neckPitchRadians + headPitchRadians }
}

/// A compact, allocation-free sample of one boot's gait cycle.  Keeping this
/// separate from the final joint pose makes contact timing explicit: walking
/// retains an overlapping support phase, while sprinting has a brief flight
/// phase and a faster recovery leg.
struct ReplayAthleteFootfall: Equatable, Sendable {
    /// -1 is the forward reach at heel strike; +1 is the rearward toe-off.
    let stride: Float
    /// Normalized recovery-leg fold, applied on top of the state's base knee bend.
    let swingLift: Float
    /// Additional bend while the boot is bearing weight, expressed in radians.
    let stanceCompression: Float
    /// World-relative boot pitch after the leg chain has been compensated.
    let footPitch: Float
    /// Continuous confidence that this boot is carrying the athlete's weight.
    /// It eases in after heel strike and out before toe-off so grounding never
    /// snaps from one leg to the other, even during reverse playback.
    let contactWeight: Float
    let isStance: Bool
}

enum ReplayAthleteLeg: String, Equatable, Sendable {
    case left
    case right

    var opposite: ReplayAthleteLeg { self == .left ? .right : .left }
}

enum ReplayAthleteBallActionKind: String, Equatable, Sendable {
    case controlTouch
    case pass
    case cutback
}

/// A render-only football action inferred from the authored player and ball
/// tracks. It never moves either track: the values below only reshape the
/// procedural legs around a detected touch and provide a deterministic support
/// foot for grounding. Every field is an absolute function of replay time.
struct ReplayAthleteBallActionPose: Equatable, Sendable {
    let kind: ReplayAthleteBallActionKind
    let contactTime: TimeInterval
    let kickingLeg: ReplayAthleteLeg
    let influence: Float
    let kickingHipFlexion: Float
    let kickingKneeFlexion: Float
    let kickingFootPitch: Float
    let supportHipFlexion: Float
    let supportKneeFlexion: Float
    let supportFootPitch: Float
    let supportLateralShift: Float

    var supportLeg: ReplayAthleteLeg { kickingLeg.opposite }
}

/// Maps both telemetry locomotion and the existing fixed-step impact solver to
/// the shared named-joint contract.  Imported one-skeleton assets can conform
/// by exposing the same semantic binding; the procedural mesh is not a dead
/// end or a second animation system.
@MainActor
enum ReplayAthleteMotion {
    #if DEBUG
    private(set) static var ballActionSampleCount = 0

    static func resetBallActionSampleCountForTesting() {
        ballActionSampleCount = 0
    }
    #endif

    static func update(
        _ instance: ReplayAthleteInstance,
        from track: PlayerTrack,
        at time: TimeInterval,
        lookTargetWorldPosition: SIMD3<Float>? = nil,
        ballTrack: BallTrack? = nil,
        ragdollCue: PlayerRagdollCue? = nil,
        interaction: ReplayAthleteInteractionCue? = nil,
        presentationPose: PlayerPose? = nil
    ) {
        let locomotion = track.locomotion(at: time)
        apply(
            locomotionPose(
                for: track,
                at: time,
                locomotion: locomotion,
                gaitPhase: track.gaitPhase(at: time),
                lookTargetWorldPosition: lookTargetWorldPosition,
                ballTrack: ballTrack,
                interaction: interaction,
                presentationPose: presentationPose,
                allowsOffBallPose: !(ragdollCue.map { $0.playerID == track.id && $0.isActive(at: time) } ?? false)
            ),
            to: instance.joints
        )
        guard instance.lod.supportsRagdoll,
              let ragdollCue,
              ragdollCue.playerID == track.id,
              ragdollCue.isActive(at: time)
        else { return }
        apply(
            ragdoll: PlayerRagdollPlayback.pose(for: ragdollCue, at: time),
            influence: ragdollCue.influence(at: time),
            to: instance.joints
        )
    }

    static func locomotionPose(
        for track: PlayerTrack,
        at time: TimeInterval,
        lookTargetWorldPosition: SIMD3<Float>? = nil,
        ballTrack: BallTrack? = nil,
        interaction: ReplayAthleteInteractionCue? = nil,
        presentationPose: PlayerPose? = nil
    ) -> ReplayAthleteLocomotionPose {
        locomotionPose(
            for: track,
            at: time,
            locomotion: track.locomotion(at: time),
            gaitPhase: track.gaitPhase(at: time),
            lookTargetWorldPosition: lookTargetWorldPosition,
            ballTrack: ballTrack,
            interaction: interaction,
            presentationPose: presentationPose
        )
    }

    /// Telemetry-blended authored posing remains a pure function of match time.
    /// The renderer can compute a descriptor once per player and share it with
    /// imported-asset admission and procedural fallback without transition state.
    static func locomotionPose(
        for track: PlayerTrack,
        at time: TimeInterval,
        locomotion suppliedLocomotion: PlayerLocomotionSample,
        gaitPhase suppliedGaitPhase: Float? = nil,
        lookTargetWorldPosition: SIMD3<Float>? = nil,
        ballTrack: BallTrack? = nil,
        ballAction suppliedBallAction: ReplayAthleteBallActionPose? = nil,
        stationaryPose: PlayerPose? = nil,
        interaction: ReplayAthleteInteractionCue? = nil,
        presentationPose: PlayerPose? = nil,
        movementIntent: ReplayAthleteMovementIntent.Sample? = nil,
        allowsOffBallPose: Bool = true,
        goalkeeperReadiness: ReplayGoalkeeperReadiness.Sample? = nil
    ) -> ReplayAthleteLocomotionPose {
        let locomotion = stationaryPose == nil ? suppliedLocomotion : track.stationaryLocomotion
        // `PlayerLocomotionState` is deliberately discrete because it is also
        // used for clip admission and tactical semantics.  Driving the visible
        // body directly from that enum, however, made every classification
        // boundary an animation cut: a 0.02 m/s change around jog or sprint
        // could replace the complete hip, knee and arm pose in one frame.
        // Resolve the procedural presentation from continuous speed/turn bands
        // while retaining the enum for those non-visual decisions.
        let motionTuning = motionTuning(for: locomotion)
        let tuning = motionTuning.tuning
        let cutInfluence = motionTuning.cutInfluence
        let effort = locomotion.effort
        let turn = locomotion.turnResponse
        let acceleration = locomotion.accelerationResponse
        // Explicitly supplied phases come from PlayerTrack's integrated cadence
        // clock. Tests and external callers that author a one-off descriptor can
        // still use its embedded phase without reconstructing a telemetry track.
        let phase = stationaryPose == nil
            ? suppliedGaitPhase ?? locomotion.motion.locomotionPhase
            : locomotion.motion.locomotionPhase
        let leftFootfall = footfall(at: phase, tuning: tuning.footfall)
        let rightFootfall = footfall(at: phase + .pi, tuning: tuning.footfall)
        let cycle = (leftFootfall.stride - rightFootfall.stride) * 0.5
        let doubleCycle = sin(phase * 2)
        // Breathing belongs above the pelvis. Translating the complete body
        // made planted boots pulse through the turf; a small chest pitch keeps
        // idle athletes alive while the neck/head counter-rotation preserves
        // the authored gaze direction.
        let breathingPitch = sin(Float(time) * 1.35 + Float(track.shirtNumber))
            * (0.008 * (1 - (effort * 0.72)))
        let braking = max(-acceleration, 0)
        let forwardLean = tuning.forwardLean
            + (max(acceleration, 0) * tuning.accelerationLean)
            - (braking * (0.08 + (effort * 0.08)))
            + (track.isGoalkeeper ? 0.045 : 0)
        let runningTurnBank = turn * 0.025 * effort
        let cutBank = runningTurnBank
            + ((turn * 0.18 - runningTurnBank) * cutInfluence)
        let look = lookPose(
            for: track,
            at: time,
            locomotion: locomotion,
            targetWorldPosition: lookTargetWorldPosition,
            stationaryPose: stationaryPose,
            presentationPose: presentationPose
        )

        let ballAction = suppliedBallAction ?? ballTrack.flatMap {
            ballActionPose(for: track, ballTrack: $0, at: time)
        }
        // The legacy left lane is -X. A negative Z rotation abducts its
        // downward leg; the opposite sign collapsed keeper boots inward.
        var leftHipLateral: Float = track.isGoalkeeper ? -0.10 : tuning.lateralStance
        var rightHipLateral: Float = -leftHipLateral
        let cutPlant = abs(turn) * 0.12 * cutInfluence
        var leftHipSwing = (leftFootfall.stride * tuning.strideAmplitude)
            - (max(turn, 0) * cutPlant)
        var rightHipSwing = (rightFootfall.stride * tuning.strideAmplitude)
            + (max(-turn, 0) * cutPlant)
        let kneeBase: Float = track.isGoalkeeper ? 0.34 : tuning.kneeBase
        let kneeTravel = tuning.kneeTravel
        let brakingCrouch = braking * (0.05 + (effort * 0.11))
        var leftKneeBend = kneeBase + (leftFootfall.swingLift * kneeTravel)
            + leftFootfall.stanceCompression
            + brakingCrouch
            + (max(turn, 0) * cutPlant)
        var rightKneeBend = kneeBase + (rightFootfall.swingLift * kneeTravel)
            + rightFootfall.stanceCompression
            + brakingCrouch
            + (max(-turn, 0) * cutPlant)
        var leftAnkleAngle = -(leftHipSwing + leftKneeBend) + leftFootfall.footPitch
        var rightAnkleAngle = -(rightHipSwing + rightKneeBend) + rightFootfall.footPitch
        var leftContactWeight = leftFootfall.contactWeight
        var rightContactWeight = rightFootfall.contactWeight
        var actionLateralShift: Float = 0

        if let action = ballAction {
            func blend(_ current: Float, toward target: Float) -> Float {
                current + ((target - current) * action.influence)
            }

            let kickingAnkle = -(action.kickingHipFlexion + action.kickingKneeFlexion)
                + action.kickingFootPitch
            let supportAnkle = -(action.supportHipFlexion + action.supportKneeFlexion)
                + action.supportFootPitch
            // Ease the inferred contact a second time before it competes with
            // the gait clock. This keeps the planted leg authoritative through
            // the strike without introducing a hard support-foot hand-off at
            // either edge of the action window.
            let supportLoad = smootherStep(action.influence)
            let kickingLoadScale = 1 - (0.94 * action.influence)

            switch action.kickingLeg {
            case .left:
                leftHipSwing = blend(leftHipSwing, toward: action.kickingHipFlexion)
                leftKneeBend = blend(leftKneeBend, toward: action.kickingKneeFlexion)
                leftAnkleAngle = blend(leftAnkleAngle, toward: kickingAnkle)
                rightHipSwing = blend(rightHipSwing, toward: action.supportHipFlexion)
                rightKneeBend = blend(rightKneeBend, toward: action.supportKneeFlexion)
                rightAnkleAngle = blend(rightAnkleAngle, toward: supportAnkle)
                leftHipLateral = blend(leftHipLateral, toward: 0.015)
                rightHipLateral = blend(rightHipLateral, toward: -0.075)
                leftContactWeight *= kickingLoadScale
                rightContactWeight = max(rightContactWeight, supportLoad)
                actionLateralShift = action.supportLateralShift
            case .right:
                rightHipSwing = blend(rightHipSwing, toward: action.kickingHipFlexion)
                rightKneeBend = blend(rightKneeBend, toward: action.kickingKneeFlexion)
                rightAnkleAngle = blend(rightAnkleAngle, toward: kickingAnkle)
                leftHipSwing = blend(leftHipSwing, toward: action.supportHipFlexion)
                leftKneeBend = blend(leftKneeBend, toward: action.supportKneeFlexion)
                leftAnkleAngle = blend(leftAnkleAngle, toward: supportAnkle)
                rightHipLateral = blend(rightHipLateral, toward: -0.015)
                leftHipLateral = blend(leftHipLateral, toward: 0.075)
                rightContactWeight *= kickingLoadScale
                leftContactWeight = max(leftContactWeight, supportLoad)
                actionLateralShift = -action.supportLateralShift
            }
        }

        let leftSoleHeight = approximateSoleHeight(
            hipAngle: leftHipSwing,
            kneeAngle: leftKneeBend,
            ankleAngle: leftAnkleAngle
        )
        let rightSoleHeight = approximateSoleHeight(
            hipAngle: rightHipSwing,
            kneeAngle: rightKneeBend,
            ankleAngle: rightAnkleAngle
        )
        let grounding = groundingReference(
            leftSoleHeight: leftSoleHeight,
            leftContactWeight: leftContactWeight,
            rightSoleHeight: rightSoleHeight,
            rightContactWeight: rightContactWeight
        )

        let keeperReach: Float = track.isGoalkeeper ? 0.34 : tuning.shoulderReach
        let elbowBend: Float = track.isGoalkeeper ? 0.56 : tuning.elbowBend
        let bodyBob = abs(doubleCycle) * tuning.verticalBounce
        let sideSway = (-cycle * tuning.lateralSway)
            + (actionLateralShift * (ballAction?.influence ?? 0))
        let balanceReach = braking * (0.025 + (effort * 0.07))
            + ((ballAction?.influence ?? 0) * 0.075)
        // Counter most of the roll inherited from the body/hips/spine chain.
        // The eyes stay comparatively level while the planted body banks into
        // a cut, avoiding the metronomic head wobble of a copied gait sine.
        let inheritedGaitRoll = doubleCycle * (tuning.pelvisRoll - tuning.spineRoll)
        let stabilizedHeadRoll = (-inheritedGaitRoll * 0.72)
            + (cutBank * 0.40)
            + (doubleCycle * tuning.headRoll * 0.18)
        let offBallEnabled = allowsOffBallPose && presentationPose != nil
            && stationaryPose == nil && lookTargetWorldPosition != nil
        let interactionInfluence = offBallEnabled
            ? ReplayAthleteInteractionPose.sample(cue: interaction, at: time, track: track,
                                                  presentationPose: presentationPose)?.influence ?? 0 : 0
        let offBall = ReplayAthleteOffBallPose.sample(
            playerID: track.id, at: time, locomotion: locomotion, look: look,
            actionInfluence: max(interactionInfluence, ballAction?.influence ?? 0,
                track.isGoalkeeper && stationaryPose == nil ? goalkeeperReadiness?.influence ?? 0 : 0),
            enabled: offBallEnabled)
        let sharedLook = offBall.adjusting(look)

        let base = ReplayAthleteLocomotionPose(
            // A planted boot owns vertical placement. During the flight phase,
            // the same absolute-phase solver restores a restrained clearance
            // and the authored COM bounce. Breathing no longer translates the
            // feet through the turf; upper-body articulation carries that life.
            bodyPosition: [
                sideSway,
                min(
                    max(
                        grounding.clearance - grounding.soleHeight
                            + (bodyBob * (1 - grounding.supportWeight)),
                        -0.095
                    ),
                    0.075
                ),
                effort * 0.014,
            ],
            bodyOrientation: simd_quatf(angle: -forwardLean * 0.10, axis: [1, 0, 0])
                * simd_quatf(angle: -cutBank * 0.20, axis: [0, 0, 1]),
            hipsPosition: [sideSway * 0.72, 0.90, 0],
            hipsOrientation: simd_quatf(
                angle: (doubleCycle * tuning.pelvisRoll) - cutBank,
                axis: [0, 0, 1]
            ) * simd_quatf(angle: cycle * tuning.pelvisYaw, axis: [0, 1, 0]),
            spineOrientation: simd_quatf(
                angle: (-forwardLean * 0.90) + breathingPitch + offBall.chestPitch,
                axis: [1, 0, 0]
            )
                * simd_quatf(
                    angle: (-doubleCycle * tuning.spineRoll) + (cutBank * 0.62) + offBall.chestRoll,
                    axis: [0, 0, 1]
                )
                * simd_quatf(angle: -cycle * tuning.spineYaw + offBall.chestYaw, axis: [0, 1, 0]),
            neckOrientation: simd_quatf(
                angle: (forwardLean * 0.30) + sharedLook.neckPitchRadians
                    - (breathingPitch * 0.55),
                axis: [1, 0, 0]
            ) * simd_quatf(angle: stabilizedHeadRoll * 0.38, axis: [0, 0, 1])
                * simd_quatf(
                    angle: sharedLook.neckYawRadians + (cycle * tuning.spineYaw * 0.30),
                    axis: [0, 1, 0]
                ),
            headOrientation: simd_quatf(
                angle: (forwardLean * 0.54) + sharedLook.headPitchRadians
                    - (breathingPitch * 0.45),
                axis: [1, 0, 0]
            ) * simd_quatf(angle: stabilizedHeadRoll * 0.62, axis: [0, 0, 1])
                * simd_quatf(
                    angle: sharedLook.headYawRadians + (cycle * tuning.spineYaw * 0.70),
                    axis: [0, 1, 0]
                ),
            leftHipOrientation: simd_quatf(angle: leftHipLateral, axis: [0, 0, 1])
                * simd_quatf(angle: leftHipSwing, axis: [1, 0, 0]),
            rightHipOrientation: simd_quatf(angle: rightHipLateral, axis: [0, 0, 1])
                * simd_quatf(angle: rightHipSwing, axis: [1, 0, 0]),
            leftKneeOrientation: simd_quatf(angle: leftKneeBend, axis: [1, 0, 0]),
            rightKneeOrientation: simd_quatf(angle: rightKneeBend, axis: [1, 0, 0]),
            leftAnkleOrientation: simd_quatf(angle: leftAnkleAngle, axis: [1, 0, 0]),
            rightAnkleOrientation: simd_quatf(angle: rightAnkleAngle, axis: [1, 0, 0]),
            leftShoulderOrientation: offBall.shoulder(simd_quatf(
                angle: -(keeperReach + balanceReach),
                axis: [0, 0, 1]
            ) * simd_quatf(
                angle: rightFootfall.stride * tuning.strideAmplitude * tuning.armSwing,
                axis: [1, 0, 0]
            ), isLeft: true),
            rightShoulderOrientation: offBall.shoulder(simd_quatf(
                angle: keeperReach + balanceReach,
                axis: [0, 0, 1]
            ) * simd_quatf(
                angle: leftFootfall.stride * tuning.strideAmplitude * tuning.armSwing,
                axis: [1, 0, 0]
            ), isLeft: false),
            leftElbowOrientation: offBall.elbow(simd_quatf(
                // Limbs hang down -Y and the footballer faces +Z. Elbow
                // flexion is -X (forward), opposite to a knee's +X fold.
                angle: -(elbowBend + (max(-rightFootfall.stride, 0) * tuning.elbowTravel)),
                axis: [1, 0, 0]
            ), isLeft: true),
            rightElbowOrientation: offBall.elbow(simd_quatf(
                angle: -(elbowBend + (max(-leftFootfall.stride, 0) * tuning.elbowTravel)),
                axis: [1, 0, 0]
            ), isLeft: false),
            leftWristOrientation: simd_quatf(
                angle: rightFootfall.stride * tuning.wristTravel,
                axis: [0, 1, 0]
            ),
            rightWristOrientation: simd_quatf(
                angle: leftFootfall.stride * tuning.wristTravel,
                axis: [0, 1, 0]
            )
        )
        let movement = stationaryPose == nil
            ? movementIntent ?? ReplayAthleteMovementIntent.sample(track: track, at: time,
                presentationPose: presentationPose, lookTarget: lookTargetWorldPosition,
                interaction: interaction) : nil
        let directed = ReplayAthleteMovementIntent.apply(to: base, sample: movement)
        let prepared = ReplayGoalkeeperReadiness.apply(to: directed,
            sample: track.isGoalkeeper && stationaryPose == nil ? goalkeeperReadiness : nil)
        return ReplayAthleteInteractionPose.apply(to: prepared, cue: interaction, at: time,
                                                  track: track,
                                                  presentationPose: stationaryPose ?? presentationPose)
    }

    /// Absolute-phase football footfall used by the procedural rig.  This is
    /// intentionally exposed to tests so contact semantics cannot regress into
    /// a symmetric marching sine wave as animation tuning evolves.
    static func footfall(
        for state: PlayerLocomotionState,
        phase: Float
    ) -> ReplayAthleteFootfall {
        footfall(at: phase, tuning: tuning(for: state).footfall)
    }

    /// The continuous timing actually used by locomotionPose, including cut
    /// admission/release. A discrete state's timing cannot audit that blend.
    static func footfall(
        for locomotion: PlayerLocomotionSample,
        phase: Float
    ) -> ReplayAthleteFootfall {
        footfall(at: phase, tuning: motionTuning(for: locomotion).tuning.footfall)
    }

    /// Infers a visual touch from authored ball kinematics and player proximity.
    /// No event IDs, player IDs or hand-authored timestamps participate, so the
    /// same input tracks always return the same pose after seek or reverse play.
    static func ballActionPose(
        for track: PlayerTrack,
        ballTrack: BallTrack,
        at time: TimeInterval
    ) -> ReplayAthleteBallActionPose? {
        #if DEBUG
        ballActionSampleCount &+= 1
        #endif
        guard time.isFinite, ballTrack.keyframes.count >= 3 else { return nil }

        let keyframes = ballTrack.keyframes
        let insertionIndex = lowerBoundBallKeyframeIndex(in: keyframes, time: time)
        let firstCandidate = max(insertionIndex - 2, 1)
        let lastCandidate = min(insertionIndex + 1, keyframes.count - 2)
        guard firstCandidate <= lastCandidate else { return nil }

        var strongest: ReplayAthleteBallActionPose?
        for index in firstCandidate ... lastCandidate {
            guard let candidate = ballActionPose(
                for: track,
                keyframes: keyframes,
                contactIndex: index,
                sampleTime: time
            ) else { continue }

            if strongest == nil
                || candidate.influence > (strongest?.influence ?? 0) + 0.000_1
                || (
                    abs(candidate.influence - (strongest?.influence ?? 0)) <= 0.000_1
                        && abs(candidate.contactTime - time)
                            < abs((strongest?.contactTime ?? time) - time)
                ) {
                strongest = candidate
            }
        }
        return strongest
    }

    /// Produces a continuous, absolute-time football gaze rather than making
    /// the head mirror the instantaneous turn-rate. The player prioritises the
    /// ball when it is in the scene, glances toward travel when carrying it at
    /// their feet, and retains a low-amplitude deterministic scan. Wide looks
    /// are split across neck and head and remain inside comfortable human ranges.
    static func lookPose(
        for track: PlayerTrack,
        at time: TimeInterval,
        locomotion: PlayerLocomotionSample? = nil,
        targetWorldPosition: SIMD3<Float>? = nil,
        stationaryPose: PlayerPose? = nil,
        presentationPose: PlayerPose? = nil
    ) -> ReplayAthleteLookPose {
        let sample = stationaryPose == nil
            ? locomotion ?? track.locomotion(at: time)
            : track.stationaryLocomotion
        let finiteTime = time.isFinite ? min(max(time, -1_000_000), 1_000_000) : 0
        let current = stationaryPose ?? presentationPose ?? track.presentationPose(at: finiteTime)
        let facing = current.facingDegrees.isFinite ? current.facingDegrees : 0

        let travelBearing: Float
        if stationaryPose != nil {
            travelBearing = facing
        } else {
            let directionWindow: TimeInterval = 0.24
            let before = track.presentationPose(at: finiteTime - directionWindow).position
            let after = track.presentationPose(at: finiteTime + directionWindow).position
            let travelX = after.x - before.x
            let travelZ = after.z - before.z
            let travelDistance = hypot(travelX, travelZ)
            travelBearing = travelDistance > 0.025
                ? atan2(travelX, travelZ) * 180 / .pi
                : facing
        }
        let relativeTravelBearing = shortestAngleDelta(from: facing, to: travelBearing)
        // Backpedalling crosses the same ±180° seam as a ball behind the
        // player. A raw clamp flips +100° to -100° across that seam and can
        // whip the rendered head between opposite limits in one frame.
        // Fade this cue through the rear sector. The authored body heading
        // still owns the turn; the neck must not try to look through the back.
        let rearTravelAttention = 1 - smootherStep((abs(relativeTravelBearing) - 112) / 68)
        let travelDelta = clampAngleDelta(relativeTravelBearing, limit: 100) * rearTravelAttention

        let scan = interpolatedScanTarget(for: track.id, at: finiteTime)
        let scanAmplitude = 27 - (15 * sample.effort)
        let turnLead = sample.turnResponse * (8 - (3 * sample.effort))
        let isMoving = min(max((sample.speedMetresPerSecond - 0.18) / 1.5, 0), 1)

        var desiredYawDegrees = travelDelta * (0.30 + (0.43 * isMoving))
        var desiredPitchDegrees: Float = 0
        var scanWeight: Float = 0.22

        if let target = finiteTarget(targetWorldPosition) {
            let targetX = target.x - current.position.x
            let targetZ = target.z - current.position.z
            let horizontalDistance = hypot(targetX, targetZ)
            if horizontalDistance > 0.001 {
                let targetBearing = atan2(targetX, targetZ) * 180 / .pi
                let relativeTargetBearing = shortestAngleDelta(from: facing, to: targetBearing)
                let targetDelta = clampAngleDelta(relativeTargetBearing, limit: 112)
                // A target crossing directly behind changes its signed bearing
                // from +180 to -180. Fade horizontal attention through the rear
                // sector before that wrap, rather than snapping the head between
                // opposite shoulder checks. This is absolute-time and leaves
                // front/side attention and vertical ball glances unchanged.
                let rearAttention = 1 - smootherStep((abs(relativeTargetBearing) - 112) / 68)
                // A ball at the player's feet should not pin their gaze down:
                // footballers alternate between touch and the next picture.
                // Blend rather than branch at distance thresholds: the old
                // 1.25 m and 4 m switches could rotate the complete cervical
                // chain in one frame as a moving ball crossed either boundary.
                let nearToMid = smootherStep((horizontalDistance - 0.82) / 0.86)
                let midToFar = smootherStep((horizontalDistance - 3.15) / 1.70)
                let visibility = smootherStep((horizontalDistance - 0.015) / 0.24)
                let nearTargetWeight: Float = 0.28
                let midTargetWeight: Float = 0.52
                let farTargetWeight: Float = 0.72
                let blendedMidTargetWeight = nearTargetWeight
                    + ((midTargetWeight - nearTargetWeight) * nearToMid)
                let targetWeight = (
                    blendedMidTargetWeight
                        + ((farTargetWeight - blendedMidTargetWeight) * midToFar)
                ) * visibility * rearAttention
                let nearScanWeight: Float = 0.34
                let midScanWeight: Float = 0.16
                let farScanWeight: Float = 0.10
                let blendedMidScanWeight = nearScanWeight
                    + ((midScanWeight - nearScanWeight) * nearToMid)
                scanWeight = blendedMidScanWeight
                    + ((farScanWeight - blendedMidScanWeight) * midToFar)
                desiredYawDegrees = (travelDelta * isMoving * (1 - targetWeight))
                    + (targetDelta * targetWeight)

                let downwardPitch = atan2(max(1.70 - target.y, -0.30), horizontalDistance)
                    * 180 / .pi
                let pitchWeight = (0.52 + (0.20 * nearToMid)) * visibility
                desiredPitchDegrees = min(max(downwardPitch * pitchWeight, -7), 24)
            }
        }

        desiredYawDegrees += (scan * scanAmplitude * scanWeight) + turnLead
        let yawLimit = 64 - (18 * sample.effort)
        // Athletes face local +Z. Positive Y yaw turns that forward axis
        // towards +X, matching atan2(deltaX, deltaZ) and the player root.
        let boundedYawRadians = min(max(desiredYawDegrees, -yawLimit), yawLimit) * .pi / 180

        let pitchScan = interpolatedScanTarget(
            for: track.id,
            at: finiteTime + 0.47,
            salt: 0x9E37_79B9
        ) * 1.8
        let boundedPitchRadians = min(
            max(desiredPitchDegrees + pitchScan, -9),
            25
        ) * .pi / 180

        let neckYawShare: Float = 0.42
        let neckPitchShare: Float = 0.34
        return ReplayAthleteLookPose(
            neckYawRadians: boundedYawRadians * neckYawShare,
            headYawRadians: boundedYawRadians * (1 - neckYawShare),
            neckPitchRadians: boundedPitchRadians * neckPitchShare,
            headPitchRadians: boundedPitchRadians * (1 - neckPitchShare)
        )
    }

    static func apply(_ pose: ReplayAthleteLocomotionPose, to binding: ReplayAthleteJointBinding) {
        binding[.bodyRoot].position = pose.bodyPosition
        binding[.bodyRoot].orientation = pose.bodyOrientation
        binding[.hips].position = pose.hipsPosition
        binding[.hips].orientation = pose.hipsOrientation
        binding[.spine].orientation = pose.spineOrientation
        binding[.neck].orientation = pose.neckOrientation
        binding[.headRoot].orientation = pose.headOrientation
        binding[.leftHip].orientation = pose.leftHipOrientation
        binding[.rightHip].orientation = pose.rightHipOrientation
        binding[.leftKnee].orientation = pose.leftKneeOrientation
        binding[.rightKnee].orientation = pose.rightKneeOrientation
        binding[.leftAnkle].orientation = pose.leftAnkleOrientation
        binding[.rightAnkle].orientation = pose.rightAnkleOrientation
        binding[.leftShoulder].orientation = pose.leftShoulderOrientation
        binding[.rightShoulder].orientation = pose.rightShoulderOrientation
        binding[.leftElbow].orientation = pose.leftElbowOrientation
        binding[.rightElbow].orientation = pose.rightElbowOrientation
        binding[.leftWrist].orientation = pose.leftWristOrientation
        binding[.rightWrist].orientation = pose.rightWristOrientation
        if let articulated = binding.articulatedFar {
            articulated.update()
            binding[.bodyRoot].position.y += articulated.upwardCorrection(relativeTo: binding.root)
        } else if let support = binding.farFloorSupport {
            binding[.bodyRoot].position.y += support.upwardCorrection(relativeTo: binding.root)
        }
    }

    static func apply(
        ragdoll pose: PlayerRagdollPose,
        influence rawInfluence: Float,
        to binding: ReplayAthleteJointBinding
    ) {
        let weight = min(max(rawInfluence, 0), 1)
        guard weight > 0 else { return }

        func blend(_ joint: ReplayAthleteJoint, toward target: simd_quatf) {
            let entity = binding[joint]
            entity.orientation = simd_slerp(entity.orientation, target, weight)
        }

        let bodyTarget = simd_quatf(angle: pose.fallAngle, axis: pose.fallAxis)
            * simd_quatf(angle: pose.bodyTwist, axis: [0, 1, 0])
        // Match PlayerRagdollPlayback's authored upright centre exactly so a
        // zero-influence/impact-edge sample cannot introduce a 2 cm pop.
        let uprightCentre = SIMD3<Float>(0, 0.92, 0)
        let targetBodyPosition = pose.bodyCenter - bodyTarget.act(uprightCentre)
        let body = binding[.bodyRoot]
        body.position += (targetBodyPosition - body.position) * weight
        body.orientation = simd_slerp(body.orientation, bodyTarget, weight)

        blend(
            .spine,
            toward: simd_quatf(angle: pose.spineRoll, axis: [0, 0, 1])
                * simd_quatf(angle: pose.spinePitch, axis: [1, 0, 0])
        )
        blend(
            .neck,
            toward: simd_quatf(real: 1, imag: .zero)
        )
        blend(
            .headRoot,
            toward: simd_quatf(angle: pose.headPitch, axis: [1, 0, 0])
                * simd_quatf(angle: pose.headYaw, axis: [0, 1, 0])
        )
        blend(.leftHip, toward: simd_quatf(angle: pose.leftHip, axis: [1, 0, 0]))
        blend(.rightHip, toward: simd_quatf(angle: pose.rightHip, axis: [1, 0, 0]))
        blend(.leftKnee, toward: simd_quatf(angle: pose.leftKnee, axis: [1, 0, 0]))
        blend(.rightKnee, toward: simd_quatf(angle: pose.rightKnee, axis: [1, 0, 0]))
        blend(.leftAnkle, toward: simd_quatf(angle: pose.leftAnkle, axis: [1, 0, 0]))
        blend(.rightAnkle, toward: simd_quatf(angle: pose.rightAnkle, axis: [1, 0, 0]))
        blend(
            .leftShoulder,
            toward: simd_quatf(angle: pose.leftShoulderRoll, axis: [0, 0, 1])
                * simd_quatf(angle: pose.leftShoulderPitch, axis: [1, 0, 0])
        )
        blend(
            .rightShoulder,
            toward: simd_quatf(angle: pose.rightShoulderRoll, axis: [0, 0, 1])
                * simd_quatf(angle: pose.rightShoulderPitch, axis: [1, 0, 0])
        )
        blend(.leftElbow, toward: simd_quatf(angle: -pose.leftElbow, axis: [1, 0, 0]))
        blend(.rightElbow, toward: simd_quatf(angle: -pose.rightElbow, axis: [1, 0, 0]))
        blend(.leftWrist, toward: simd_quatf(angle: pose.leftWrist, axis: [0, 1, 0]))
        blend(.rightWrist, toward: simd_quatf(angle: pose.rightWrist, axis: [0, 1, 0]))
    }

    static func gaitEffort(for track: PlayerTrack, at time: TimeInterval) -> Float {
        track.locomotion(at: time).effort
    }

    static func turningResponse(for track: PlayerTrack, at time: TimeInterval) -> Float {
        track.locomotion(at: time).turnResponse
    }

    private struct LocomotionTuning {
        let strideAmplitude: Float
        let kneeBase: Float
        let kneeTravel: Float
        let toeLift: Float
        let forwardLean: Float
        let accelerationLean: Float
        let lateralStance: Float
        let lateralSway: Float
        let verticalBounce: Float
        let pelvisRoll: Float
        let pelvisYaw: Float
        let spineRoll: Float
        let spineYaw: Float
        let headRoll: Float
        let headTurn: Float
        let shoulderReach: Float
        let armSwing: Float
        let elbowBend: Float
        let elbowTravel: Float
        let wristTravel: Float
        let footfall: FootfallTuning
    }

    private struct ResolvedLocomotionTuning {
        let tuning: LocomotionTuning
        let cutInfluence: Float
    }

    private struct FootfallTuning {
        let stanceFraction: Float
        let stanceKneeCompression: Float
        let heelStrike: Float
        let toeOff: Float
        let swingDorsiflexion: Float
    }

    private struct BallActionTuning {
        let anticipation: TimeInterval
        let recovery: TimeInterval
        let backswingHip: Float
        let contactHip: Float
        let followThroughHip: Float
        let backswingKnee: Float
        let contactKnee: Float
        let followThroughKnee: Float
        let backswingFootPitch: Float
        let contactFootPitch: Float
        let followThroughFootPitch: Float
        let supportHip: Float
        let supportKnee: Float
        let supportFootPitch: Float
        let supportLateralShift: Float
    }

    private static func ballActionPose(
        for track: PlayerTrack,
        keyframes: [BallKeyframe],
        contactIndex: Int,
        sampleTime: TimeInterval
    ) -> ReplayAthleteBallActionPose? {
        guard contactIndex > 0, contactIndex < keyframes.count - 1 else { return nil }
        let previous = keyframes[contactIndex - 1]
        let contact = keyframes[contactIndex]
        let next = keyframes[contactIndex + 1]
        guard contact.time.isFinite,
              contact.height.isFinite,
              let incomingVelocity = ballVelocity(from: previous, to: contact),
              let outgoingVelocity = ballVelocity(from: contact, to: next)
        else { return nil }

        let incomingSpeed = simd_length(incomingVelocity)
        let outgoingSpeed = simd_length(outgoingVelocity)
        let speedChange = abs(outgoingSpeed - incomingSpeed)
        let directionChange = directionChangeDegrees(
            incoming: incomingVelocity,
            outgoing: outgoingVelocity
        )
        let speedSalience = smootherStep((speedChange - 0.35) / 2.40)
        let directionSalience = smootherStep((directionChange - 24) / 56)
        let heightChange = max(
            abs(contact.height - previous.height),
            abs(next.height - contact.height)
        )
        let heightSalience = smootherStep((heightChange - 0.025) / 0.24)
        let kinematicSalience = max(speedSalience, directionSalience, heightSalience * 0.62)
        guard kinematicSalience > 0.025 else { return nil }

        let kind: ReplayAthleteBallActionKind
        if outgoingSpeed >= 2.10, directionChange >= 62 {
            kind = .cutback
        } else if outgoingSpeed >= 2.15, outgoingSpeed >= incomingSpeed + 0.65 {
            kind = .pass
        } else {
            kind = .controlTouch
        }
        let tuning = ballActionTuning(for: kind)
        let relativeTime = sampleTime - contact.time
        guard relativeTime >= -tuning.anticipation,
              relativeTime <= tuning.recovery else { return nil }

        let temporalInfluence: Float
        if relativeTime <= 0 {
            temporalInfluence = smootherStep(
                Float((relativeTime + tuning.anticipation) / tuning.anticipation)
            )
        } else {
            temporalInfluence = 1 - smootherStep(Float(relativeTime / tuning.recovery))
        }

        let playerPose = track.presentationPose(at: contact.time)
        let dx = contact.position.x - playerPose.position.x
        let dz = contact.position.z - playerPose.position.z
        let contactDistance = hypot(dx, dz)
        let proximityInfluence = 1 - smootherStep((contactDistance - 0.18) / 1.12)
        let heightInfluence = 1 - smootherStep((contact.height - 0.22) / 0.34)
        let actionStrength = 0.62 + (0.38 * kinematicSalience)
        let influence = temporalInfluence
            * proximityInfluence
            * heightInfluence
            * actionStrength
        guard influence >= 0.025 else { return nil }

        let targetProgress: Float
        let hip: Float
        let knee: Float
        let footPitch: Float
        if relativeTime <= 0 {
            targetProgress = smootherStep(
                Float((relativeTime + tuning.anticipation) / tuning.anticipation)
            )
            hip = interpolate(tuning.backswingHip, tuning.contactHip, targetProgress)
            knee = interpolate(tuning.backswingKnee, tuning.contactKnee, targetProgress)
            footPitch = interpolate(
                tuning.backswingFootPitch,
                tuning.contactFootPitch,
                targetProgress
            )
        } else {
            targetProgress = smootherStep(Float(relativeTime / tuning.recovery))
            hip = interpolate(tuning.contactHip, tuning.followThroughHip, targetProgress)
            knee = interpolate(tuning.contactKnee, tuning.followThroughKnee, targetProgress)
            footPitch = interpolate(
                tuning.contactFootPitch,
                tuning.followThroughFootPitch,
                targetProgress
            )
        }

        return ReplayAthleteBallActionPose(
            kind: kind,
            contactTime: contact.time,
            kickingLeg: kickingLeg(
                playerPose: playerPose,
                ballPosition: contact.position,
                outgoingVelocity: outgoingVelocity
            ),
            influence: influence,
            kickingHipFlexion: hip,
            kickingKneeFlexion: knee,
            kickingFootPitch: footPitch,
            supportHipFlexion: tuning.supportHip,
            supportKneeFlexion: tuning.supportKnee,
            supportFootPitch: tuning.supportFootPitch,
            supportLateralShift: tuning.supportLateralShift
        )
    }

    private static func ballActionTuning(
        for kind: ReplayAthleteBallActionKind
    ) -> BallActionTuning {
        switch kind {
        case .controlTouch:
            BallActionTuning(
                anticipation: 0.18,
                recovery: 0.24,
                backswingHip: 0.10,
                contactHip: -0.18,
                followThroughHip: -0.28,
                backswingKnee: 0.38,
                contactKnee: 0.20,
                followThroughKnee: 0.28,
                backswingFootPitch: -0.05,
                contactFootPitch: 0.02,
                followThroughFootPitch: -0.04,
                supportHip: 0.04,
                supportKnee: 0.22,
                supportFootPitch: 0.015,
                supportLateralShift: 0.018
            )
        case .pass:
            BallActionTuning(
                anticipation: 0.26,
                recovery: 0.36,
                backswingHip: 0.28,
                contactHip: -0.30,
                followThroughHip: -0.52,
                backswingKnee: 0.58,
                contactKnee: 0.24,
                // A compact recovery fold keeps the striking boot visibly off
                // the turf after contact instead of returning immediately to
                // the underlying gait phase.
                followThroughKnee: 0.64,
                backswingFootPitch: -0.08,
                contactFootPitch: 0.015,
                followThroughFootPitch: -0.10,
                supportHip: 0.055,
                supportKnee: 0.30,
                supportFootPitch: 0.015,
                supportLateralShift: 0.030
            )
        case .cutback:
            BallActionTuning(
                anticipation: 0.30,
                recovery: 0.42,
                backswingHip: 0.20,
                contactHip: -0.24,
                followThroughHip: -0.42,
                backswingKnee: 0.62,
                contactKnee: 0.30,
                followThroughKnee: 0.68,
                backswingFootPitch: -0.06,
                contactFootPitch: 0.01,
                followThroughFootPitch: -0.06,
                supportHip: 0.07,
                supportKnee: 0.36,
                supportFootPitch: 0.02,
                supportLateralShift: 0.042
            )
        }
    }

    private static func lowerBoundBallKeyframeIndex(
        in keyframes: [BallKeyframe],
        time: TimeInterval
    ) -> Int {
        var lower = 0
        var upper = keyframes.count
        while lower < upper {
            let middle = lower + ((upper - lower) / 2)
            if keyframes[middle].time < time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func ballVelocity(
        from start: BallKeyframe,
        to end: BallKeyframe
    ) -> SIMD2<Float>? {
        let duration = end.time - start.time
        guard duration.isFinite, duration > 0.000_1 else { return nil }
        let seconds = Float(duration)
        let velocity = SIMD2<Float>(
            (end.position.x - start.position.x) / seconds,
            (end.position.z - start.position.z) / seconds
        )
        guard velocity.x.isFinite, velocity.y.isFinite else { return nil }
        return velocity
    }

    private static func directionChangeDegrees(
        incoming: SIMD2<Float>,
        outgoing: SIMD2<Float>
    ) -> Float {
        let incomingSpeed = simd_length(incoming)
        let outgoingSpeed = simd_length(outgoing)
        guard incomingSpeed > 0.025, outgoingSpeed > 0.025 else { return 0 }
        let cosine = min(
            max(simd_dot(incoming, outgoing) / (incomingSpeed * outgoingSpeed), -1),
            1
        )
        return acos(cosine) * 180 / .pi
    }

    private static func kickingLeg(
        playerPose: PlayerPose,
        ballPosition: PitchPoint,
        outgoingVelocity: SIMD2<Float>
    ) -> ReplayAthleteLeg {
        var direction = SIMD2<Float>(
            ballPosition.x - playerPose.position.x,
            ballPosition.z - playerPose.position.z
        )
        if simd_length_squared(direction) < 0.010 {
            direction = outgoingVelocity
        }
        let facing = (playerPose.facingDegrees.isFinite ? playerPose.facingDegrees : 0)
            * .pi / 180
        let localRight = (direction.x * cos(facing)) - (direction.y * sin(facing))
        return localRight >= 0 ? .right : .left
    }

    private static func interpolate(_ start: Float, _ end: Float, _ weight: Float) -> Float {
        start + ((end - start) * weight)
    }

    /// Converts continuous telemetry into continuous presentation parameters.
    /// The overlapping smoother-step bands remove pose discontinuities at the
    /// semantic idle/walk/jog/sprint/cut thresholds without keeping mutable
    /// transition state, so arbitrary seek and reverse playback remain exact.
    private static func motionTuning(
        for locomotion: PlayerLocomotionSample
    ) -> ResolvedLocomotionTuning {
        let speed = locomotion.speedMetresPerSecond.isFinite
            ? min(max(locomotion.speedMetresPerSecond, 0), 12)
            : 0
        let turnRate = locomotion.turnRateDegreesPerSecond.isFinite
            ? min(abs(locomotion.turnRateDegreesPerSecond), 360)
            : 0

        let walkingInfluence = smootherStep((speed - 0.08) / 0.54)
        let joggingInfluence = smootherStep((speed - 1.10) / 1.10)
        let sprintingInfluence = smootherStep((speed - 3.00) / 1.80)

        var resolved = interpolate(
            from: tuning(for: .idle),
            to: tuning(for: .walk),
            weight: walkingInfluence
        )
        resolved = interpolate(
            from: resolved,
            to: tuning(for: .jog),
            weight: joggingInfluence
        )
        resolved = interpolate(
            from: resolved,
            to: tuning(for: .sprint),
            weight: sprintingInfluence
        )

        // Start preparing the plant below the 70 degree/second semantic cut
        // boundary and reach the full authored cut at 150 degrees/second. This
        // produces a readable weight shift instead of a threshold pop.
        let movingInfluence = smootherStep((speed - 0.65) / 0.65)
        let turningInfluence = smootherStep((turnRate - 38) / 112)
        let cutInfluence = movingInfluence * turningInfluence
        resolved = interpolate(
            from: resolved,
            to: tuning(for: .cut),
            weight: cutInfluence
        )
        return ResolvedLocomotionTuning(
            tuning: resolved,
            cutInfluence: cutInfluence
        )
    }

    private static func interpolate(
        from start: LocomotionTuning,
        to end: LocomotionTuning,
        weight rawWeight: Float
    ) -> LocomotionTuning {
        let weight = min(max(rawWeight.isFinite ? rawWeight : 0, 0), 1)
        func blend(_ start: Float, _ end: Float) -> Float {
            start + ((end - start) * weight)
        }
        return LocomotionTuning(
            strideAmplitude: blend(start.strideAmplitude, end.strideAmplitude),
            kneeBase: blend(start.kneeBase, end.kneeBase),
            kneeTravel: blend(start.kneeTravel, end.kneeTravel),
            toeLift: blend(start.toeLift, end.toeLift),
            forwardLean: blend(start.forwardLean, end.forwardLean),
            accelerationLean: blend(start.accelerationLean, end.accelerationLean),
            lateralStance: blend(start.lateralStance, end.lateralStance),
            lateralSway: blend(start.lateralSway, end.lateralSway),
            verticalBounce: blend(start.verticalBounce, end.verticalBounce),
            pelvisRoll: blend(start.pelvisRoll, end.pelvisRoll),
            pelvisYaw: blend(start.pelvisYaw, end.pelvisYaw),
            spineRoll: blend(start.spineRoll, end.spineRoll),
            spineYaw: blend(start.spineYaw, end.spineYaw),
            headRoll: blend(start.headRoll, end.headRoll),
            headTurn: blend(start.headTurn, end.headTurn),
            shoulderReach: blend(start.shoulderReach, end.shoulderReach),
            armSwing: blend(start.armSwing, end.armSwing),
            elbowBend: blend(start.elbowBend, end.elbowBend),
            elbowTravel: blend(start.elbowTravel, end.elbowTravel),
            wristTravel: blend(start.wristTravel, end.wristTravel),
            footfall: FootfallTuning(
                stanceFraction: blend(
                    start.footfall.stanceFraction,
                    end.footfall.stanceFraction
                ),
                stanceKneeCompression: blend(
                    start.footfall.stanceKneeCompression,
                    end.footfall.stanceKneeCompression
                ),
                heelStrike: blend(start.footfall.heelStrike, end.footfall.heelStrike),
                toeOff: blend(start.footfall.toeOff, end.footfall.toeOff),
                swingDorsiflexion: blend(
                    start.footfall.swingDorsiflexion,
                    end.footfall.swingDorsiflexion
                )
            )
        )
    }

    private static func tuning(for state: PlayerLocomotionState) -> LocomotionTuning {
        switch state {
        case .idle:
            LocomotionTuning(
                strideAmplitude: 0, kneeBase: 0.015, kneeTravel: 0, toeLift: 0,
                forwardLean: 0, accelerationLean: 0, lateralStance: 0.012,
                lateralSway: 0, verticalBounce: 0, pelvisRoll: 0,
                pelvisYaw: 0, spineRoll: 0, spineYaw: 0, headRoll: 0,
                headTurn: 0.08, shoulderReach: 0.025, armSwing: 0,
                elbowBend: 0.16, elbowTravel: 0, wristTravel: 0,
                footfall: .init(
                    stanceFraction: 1, stanceKneeCompression: 0,
                    heelStrike: 0, toeOff: 0, swingDorsiflexion: 0
                )
            )
        case .walk:
            LocomotionTuning(
                strideAmplitude: 0.22, kneeBase: 0.025, kneeTravel: 0.30,
                toeLift: 0.12, forwardLean: 0.022, accelerationLean: 0.018,
                lateralStance: 0.016, lateralSway: 0.008, verticalBounce: 0.004,
                pelvisRoll: 0.012, pelvisYaw: 0.020, spineRoll: 0.010,
                spineYaw: 0.030, headRoll: 0.007, headTurn: 0.10,
                shoulderReach: 0.030, armSwing: 0.62, elbowBend: 0.28,
                elbowTravel: 0.05, wristTravel: 0.04,
                footfall: .init(
                    stanceFraction: 0.64, stanceKneeCompression: 0.055,
                    heelStrike: 0.075, toeOff: 0.115, swingDorsiflexion: 0.075
                )
            )
        case .jog:
            LocomotionTuning(
                strideAmplitude: 0.42, kneeBase: 0.035, kneeTravel: 0.58,
                toeLift: 0.19, forwardLean: 0.065, accelerationLean: 0.032,
                lateralStance: 0.018, lateralSway: 0.012, verticalBounce: 0.010,
                pelvisRoll: 0.020, pelvisYaw: 0.034, spineRoll: 0.016,
                spineYaw: 0.050, headRoll: 0.011, headTurn: 0.14,
                shoulderReach: 0.035, armSwing: 0.78, elbowBend: 0.62,
                elbowTravel: 0.10, wristTravel: 0.08,
                footfall: .init(
                    // A running foot is loaded for materially less than half of
                    // a full left-to-left cycle. The old 0.50 window asked the
                    // 0.74 m leg chain to cancel more than a metre of track
                    // travel, which could only present as boot skating.
                    stanceFraction: 0.34, stanceKneeCompression: 0.075,
                    heelStrike: 0.105, toeOff: 0.165, swingDorsiflexion: 0.105
                )
            )
        case .sprint:
            LocomotionTuning(
                strideAmplitude: 0.62, kneeBase: 0.055, kneeTravel: 0.86,
                toeLift: 0.25, forwardLean: 0.13, accelerationLean: 0.045,
                lateralStance: 0.020, lateralSway: 0.016, verticalBounce: 0.018,
                pelvisRoll: 0.027, pelvisYaw: 0.043, spineRoll: 0.021,
                spineYaw: 0.062, headRoll: 0.015, headTurn: 0.17,
                shoulderReach: 0.040, armSwing: 0.90, elbowBend: 0.92,
                elbowTravel: 0.15, wristTravel: 0.12,
                footfall: .init(
                    // At match sprint cadence this is roughly 145 ms of support,
                    // leaving a readable flight phase and keeping root travel
                    // inside the procedural leg's attainable stance sweep.
                    stanceFraction: 0.22, stanceKneeCompression: 0.095,
                    heelStrike: 0.135, toeOff: 0.220, swingDorsiflexion: 0.165
                )
            )
        case .cut:
            LocomotionTuning(
                strideAmplitude: 0.32, kneeBase: 0.15, kneeTravel: 0.50,
                toeLift: 0.16, forwardLean: 0.085, accelerationLean: 0.025,
                lateralStance: 0.060, lateralSway: 0.010, verticalBounce: 0.006,
                pelvisRoll: 0.018, pelvisYaw: 0.025, spineRoll: 0.014,
                spineYaw: 0.035, headRoll: 0.010, headTurn: 0.24,
                shoulderReach: 0.085, armSwing: 0.48, elbowBend: 0.72,
                elbowTravel: 0.08, wristTravel: 0.06,
                footfall: .init(
                    stanceFraction: 0.58, stanceKneeCompression: 0.160,
                    heelStrike: 0.065, toeOff: 0.125, swingDorsiflexion: 0.085
                )
            )
        }
    }

    private static func footfall(
        at rawPhase: Float,
        tuning: FootfallTuning
    ) -> ReplayAthleteFootfall {
        guard tuning.stanceFraction < 1 else {
            return ReplayAthleteFootfall(
                stride: 0,
                swingLift: 0,
                stanceCompression: 0,
                footPitch: 0,
                contactWeight: 1,
                isStance: true
            )
        }

        let turn = Float.pi * 2
        let finitePhase = rawPhase.isFinite ? rawPhase : 0
        // PlayerMotionState historically defines π/2 as peak rearward leg
        // drive. Align the variable contact window so that instant remains
        // toe-off for every pace instead of shifting authored replay timing.
        let contactAlignment = (tuning.stanceFraction - 0.25) * turn
        let remainder = (finitePhase + contactAlignment).truncatingRemainder(dividingBy: turn)
        let progress = (remainder < 0 ? remainder + turn : remainder) / turn

        if progress < tuning.stanceFraction {
            let stanceProgress = progress / tuning.stanceFraction
            let stride = -cos(.pi * stanceProgress)
            let compression = sin(.pi * stanceProgress) * tuning.stanceKneeCompression
            let heelWeight = 1 - smootherStep(stanceProgress / 0.22)
            let toeWeight = smootherStep((stanceProgress - 0.66) / 0.34)
            let loadWeight = smootherStep(stanceProgress / 0.14)
                * (1 - smootherStep((stanceProgress - 0.78) / 0.22))
            return ReplayAthleteFootfall(
                stride: stride,
                swingLift: 0,
                stanceCompression: compression,
                footPitch: (-tuning.heelStrike * heelWeight) + (tuning.toeOff * toeWeight),
                contactWeight: loadWeight,
                isStance: true
            )
        }

        let swingProgress = (progress - tuning.stanceFraction) / (1 - tuning.stanceFraction)
        let recovery = sin(.pi * swingProgress)
        let recoveryBlend = smootherStep(swingProgress)
        let transitionPitch = tuning.toeOff
            + ((-tuning.heelStrike - tuning.toeOff) * recoveryBlend)
        // A small polynomial bias folds the recovery leg early without the
        // comparatively expensive fractional `pow` used by many gait curves.
        let boundedRecovery = max(recovery, 0)
        let quickRecovery = boundedRecovery * (1.18 - (0.18 * boundedRecovery))
        return ReplayAthleteFootfall(
            stride: cos(.pi * swingProgress),
            swingLift: quickRecovery,
            stanceCompression: 0,
            footPitch: transitionPitch - (tuning.swingDorsiflexion * boundedRecovery),
            contactWeight: 0,
            isStance: false
        )
    }

    private struct GroundingReference {
        let soleHeight: Float
        let clearance: Float
        let supportWeight: Float
    }

    /// Resolves the support plane without mutable foot-lock state. A weighted
    /// hand-off during walking double support removes the old hard lower-sole
    /// swap; a soft minimum keeps the airborne pair clear during running flight.
    private static func groundingReference(
        leftSoleHeight: Float,
        leftContactWeight: Float,
        rightSoleHeight: Float,
        rightContactWeight: Float
    ) -> GroundingReference {
        let leftWeight = min(max(leftContactWeight.isFinite ? leftContactWeight : 0, 0), 1)
        let rightWeight = min(max(rightContactWeight.isFinite ? rightContactWeight : 0, 0), 1)
        let totalWeight = leftWeight + rightWeight
        let supportWeight = smootherStep(min(totalWeight, 1))

        // Differentiable minimum: unlike `min`, its velocity does not kink when
        // the lower airborne boot changes during the centre of the flight phase.
        let difference = leftSoleHeight - rightSoleHeight
        let flightSoleHeight = (
            leftSoleHeight + rightSoleHeight
                - sqrt((difference * difference) + (0.010 * 0.010))
        ) * 0.5
        let supportSoleHeight = totalWeight > 0.000_1
            ? ((leftSoleHeight * leftWeight) + (rightSoleHeight * rightWeight)) / totalWeight
            : flightSoleHeight
        let soleHeight = flightSoleHeight
            + ((supportSoleHeight - flightSoleHeight) * supportWeight)
        let flightClearance: Float = 0.020
        // Keep one additional millimetre of numerical headroom for the boot's
        // authored sole thickness across blended jog/cut states. The visual
        // contact still reads as planted, while dense rig-bound sampling stays
        // clear of the turf instead of relying on a looser test tolerance.
        let plantedClearance: Float = 0.007
        return GroundingReference(
            soleHeight: soleHeight,
            clearance: flightClearance
                + ((plantedClearance - flightClearance) * supportWeight),
            supportWeight: supportWeight
        )
    }

    private static func smootherStep(_ rawValue: Float) -> Float {
        let value = min(max(rawValue, 0), 1)
        return value * value * value * (value * ((value * 6) - 15) + 10)
    }

    private static func shortestAngleDelta(from start: Float, to end: Float) -> Float {
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return delta
    }

    private static func clampAngleDelta(_ value: Float, limit: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, -limit), limit)
    }

    private static func finiteTarget(_ target: SIMD3<Float>?) -> SIMD3<Float>? {
        guard let target,
              target.x.isFinite,
              target.y.isFinite,
              target.z.isFinite else { return nil }
        return target
    }

    /// Smoothly interpolated scan intentions avoid the mechanical perpetual
    /// sine-wave nod of the old rig.  The hash supplies per-player direction;
    /// smoother-step supplies zero velocity at each 1.55 second intention.
    private static func interpolatedScanTarget(
        for playerID: String,
        at time: TimeInterval,
        salt: UInt32 = 0
    ) -> Float {
        let interval: TimeInterval = 1.55
        let coordinate = time / interval
        let startIndex = Int64(floor(coordinate))
        let fraction = Float(coordinate - floor(coordinate))
        let blend = smootherStep(fraction)
        let seed = stableSeed(playerID) ^ salt
        let start = scanTarget(seed: seed, index: startIndex)
        let end = scanTarget(seed: seed, index: startIndex + 1)
        return start + ((end - start) * blend)
    }

    private static func stableSeed(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(2_166_136_261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16_777_619
        }
    }

    private static func scanTarget(seed: UInt32, index: Int64) -> Float {
        var value = seed ^ (UInt32(truncatingIfNeeded: index) &* 0x9E37_79B9)
        value ^= value >> 16
        value &*= 0x7FEB_352D
        value ^= value >> 15
        value &*= 0x846C_A68B
        value ^= value >> 16
        let unit = (Float(value & 0xFFFF) / 32_767.5) - 1
        // Bias most scan intentions toward the central visual field while still
        // allowing occasional shoulder checks.
        return unit * abs(unit)
    }

    private static func approximateSoleHeight(
        hipAngle: Float,
        kneeAngle: Float,
        ankleAngle: Float
    ) -> Float {
        let hipPivotY: Float = 0.83
        let kneePivotY = hipPivotY - (0.390 * cos(hipAngle))
        let shinAngle = hipAngle + kneeAngle
        let anklePivotY = kneePivotY - (0.350 * cos(shinAngle))
        let footAngle = shinAngle + ankleAngle
        let soleCentreY = anklePivotY
            - (0.050 * cos(footAngle))
            - (0.075 * sin(footAngle))
        // The sectioned boot spans local y -0.10...0.034. Its representative
        // sole centre is -0.05, so the upright lower half-height is 0.05—not
        // the thin outsole-only value used by the previous box rig.
        let soleHalfHeight = (0.050 * abs(cos(footAngle)))
            + (0.180 * abs(sin(footAngle)))
        return soleCentreY - soleHalfHeight
    }
}

enum ReplayAthleteProxyGeometry: Equatable, Sendable {
    case box(size: SIMD3<Float>, offset: SIMD3<Float>)
    case sphere(radius: Float, offset: SIMD3<Float>)
    case capsule(height: Float, radius: Float, offset: SIMD3<Float>)
}

struct ReplayAthleteRagdollPart: Equatable, Sendable {
    let joint: ReplayAthleteJoint
    let geometry: ReplayAthleteProxyGeometry
    let mass: Float
}

/// A measurable 76 kg query-body profile matching the deterministic joint
/// solver.  Playback keeps these proxies kinematic; the fixed-step solver owns
/// transforms so reverse and seek remain identical across SharePlay peers.
enum ReplayAthleteRagdollProfile {
    static let parts: [ReplayAthleteRagdollPart] = [
        .init(joint: .hips, geometry: .box(size: [0.38, 0.24, 0.25], offset: .zero), mass: 12),
        .init(joint: .spine, geometry: .capsule(height: 0.56, radius: 0.19, offset: [0, 0.29, 0]), mass: 27),
        .init(joint: .headRoot, geometry: .sphere(radius: 0.145, offset: .zero), mass: 5),
        .init(joint: .leftHip, geometry: .capsule(height: 0.390, radius: 0.094, offset: [0, -0.195, 0]), mass: 7.5),
        .init(joint: .rightHip, geometry: .capsule(height: 0.390, radius: 0.094, offset: [0, -0.195, 0]), mass: 7.5),
        .init(joint: .leftKnee, geometry: .capsule(height: 0.350, radius: 0.076, offset: [0, -0.175, 0]), mass: 4.3),
        .init(joint: .rightKnee, geometry: .capsule(height: 0.350, radius: 0.076, offset: [0, -0.175, 0]), mass: 4.3),
        .init(joint: .leftShoulder, geometry: .capsule(height: 0.31, radius: 0.068, offset: [0, -0.155, 0]), mass: 2.6),
        .init(joint: .rightShoulder, geometry: .capsule(height: 0.31, radius: 0.068, offset: [0, -0.155, 0]), mass: 2.6),
        .init(joint: .leftElbow, geometry: .capsule(height: 0.275, radius: 0.058, offset: [0, -0.1375, 0]), mass: 1.6),
        .init(joint: .rightElbow, geometry: .capsule(height: 0.275, radius: 0.058, offset: [0, -0.1375, 0]), mass: 1.6),
    ]

    static let totalMass = parts.reduce(Float.zero) { $0 + $1.mass }
}
