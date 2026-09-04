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
    let isStance: Bool
}

/// Maps both telemetry locomotion and the existing fixed-step impact solver to
/// the shared named-joint contract.  Imported one-skeleton assets can conform
/// by exposing the same semantic binding; the procedural mesh is not a dead
/// end or a second animation system.
@MainActor
enum ReplayAthleteMotion {
    static func update(
        _ instance: ReplayAthleteInstance,
        from track: PlayerTrack,
        at time: TimeInterval,
        ragdollCue: PlayerRagdollCue? = nil
    ) {
        let locomotion = track.locomotion(at: time)
        apply(
            locomotionPose(for: track, at: time, locomotion: locomotion),
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
        at time: TimeInterval
    ) -> ReplayAthleteLocomotionPose {
        locomotionPose(
            for: track,
            at: time,
            locomotion: track.locomotion(at: time)
        )
    }

    /// State-specific authored posing remains a pure function of match time.
    /// The renderer can compute a descriptor once per player and share it with
    /// imported-asset admission and procedural fallback without transition state.
    static func locomotionPose(
        for track: PlayerTrack,
        at time: TimeInterval,
        locomotion: PlayerLocomotionSample
    ) -> ReplayAthleteLocomotionPose {
        let tuning = tuning(for: locomotion.state)
        let effort = locomotion.effort
        let turn = locomotion.turnResponse
        let acceleration = locomotion.accelerationResponse
        let phase = locomotion.motion.locomotionPhase
        let leftFootfall = footfall(at: phase, tuning: tuning.footfall)
        let rightFootfall = footfall(at: phase + .pi, tuning: tuning.footfall)
        let cycle = (leftFootfall.stride - rightFootfall.stride) * 0.5
        let doubleCycle = sin(phase * 2)
        let breathing = sin(Float(time) * 1.35 + Float(track.shirtNumber)) * 0.004
        let braking = max(-acceleration, 0)
        let forwardLean = tuning.forwardLean
            + (max(acceleration, 0) * tuning.accelerationLean)
            - (braking * (0.08 + (effort * 0.08)))
            + (track.isGoalkeeper ? 0.045 : 0)
        let cutBank = locomotion.state == .cut ? turn * 0.18 : turn * 0.025 * effort

        let goalkeeperStance: Float = track.isGoalkeeper ? 0.10 : tuning.lateralStance
        let cutPlant = locomotion.state == .cut ? abs(turn) * 0.12 : 0
        let leftHipSwing = (leftFootfall.stride * tuning.strideAmplitude)
            - (max(turn, 0) * cutPlant)
        let rightHipSwing = (rightFootfall.stride * tuning.strideAmplitude)
            + (max(-turn, 0) * cutPlant)
        let kneeBase: Float = track.isGoalkeeper ? 0.34 : tuning.kneeBase
        let kneeTravel = tuning.kneeTravel
        let brakingCrouch = braking * (0.05 + (effort * 0.11))
        let leftKneeBend = kneeBase + (leftFootfall.swingLift * kneeTravel)
            + leftFootfall.stanceCompression
            + brakingCrouch
            + (max(turn, 0) * cutPlant)
        let rightKneeBend = kneeBase + (rightFootfall.swingLift * kneeTravel)
            + rightFootfall.stanceCompression
            + brakingCrouch
            + (max(-turn, 0) * cutPlant)
        let leftAnkleAngle = -(leftHipSwing + leftKneeBend) + leftFootfall.footPitch
        let rightAnkleAngle = -(rightHipSwing + rightKneeBend) + rightFootfall.footPitch

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
        let groundingOffset = min(
            max(0.006 - min(leftSoleHeight, rightSoleHeight), -0.070),
            0.065
        )

        let keeperReach: Float = track.isGoalkeeper ? 0.34 : tuning.shoulderReach
        let elbowBend: Float = track.isGoalkeeper ? 0.56 : tuning.elbowBend
        let bodyBob = abs(doubleCycle) * tuning.verticalBounce
        let sideSway = -cycle * tuning.lateralSway
        let balanceReach = braking * (0.025 + (effort * 0.07))

        return ReplayAthleteLocomotionPose(
            bodyPosition: [sideSway, groundingOffset + breathing + bodyBob, effort * 0.014],
            bodyOrientation: simd_quatf(angle: -forwardLean * 0.10, axis: [1, 0, 0])
                * simd_quatf(angle: -cutBank * 0.20, axis: [0, 0, 1]),
            hipsPosition: [sideSway * 0.72, 0.90, 0],
            hipsOrientation: simd_quatf(
                angle: (doubleCycle * tuning.pelvisRoll) - cutBank,
                axis: [0, 0, 1]
            ) * simd_quatf(angle: cycle * tuning.pelvisYaw, axis: [0, 1, 0]),
            spineOrientation: simd_quatf(angle: -forwardLean * 0.90, axis: [1, 0, 0])
                * simd_quatf(
                    angle: (-doubleCycle * tuning.spineRoll) + (cutBank * 0.62),
                    axis: [0, 0, 1]
                )
                * simd_quatf(angle: -cycle * tuning.spineYaw, axis: [0, 1, 0]),
            headOrientation: simd_quatf(angle: forwardLean * 0.58, axis: [1, 0, 0])
                * simd_quatf(angle: doubleCycle * tuning.headRoll, axis: [0, 0, 1])
                * simd_quatf(angle: turn * tuning.headTurn, axis: [0, 1, 0]),
            leftHipOrientation: simd_quatf(angle: goalkeeperStance, axis: [0, 0, 1])
                * simd_quatf(angle: leftHipSwing, axis: [1, 0, 0]),
            rightHipOrientation: simd_quatf(angle: -goalkeeperStance, axis: [0, 0, 1])
                * simd_quatf(angle: rightHipSwing, axis: [1, 0, 0]),
            leftKneeOrientation: simd_quatf(angle: leftKneeBend, axis: [1, 0, 0]),
            rightKneeOrientation: simd_quatf(angle: rightKneeBend, axis: [1, 0, 0]),
            leftAnkleOrientation: simd_quatf(angle: leftAnkleAngle, axis: [1, 0, 0]),
            rightAnkleOrientation: simd_quatf(angle: rightAnkleAngle, axis: [1, 0, 0]),
            leftShoulderOrientation: simd_quatf(
                angle: -(keeperReach + balanceReach),
                axis: [0, 0, 1]
            ) * simd_quatf(
                angle: rightFootfall.stride * tuning.strideAmplitude * tuning.armSwing,
                axis: [1, 0, 0]
            ),
            rightShoulderOrientation: simd_quatf(
                angle: keeperReach + balanceReach,
                axis: [0, 0, 1]
            ) * simd_quatf(
                angle: leftFootfall.stride * tuning.strideAmplitude * tuning.armSwing,
                axis: [1, 0, 0]
            ),
            leftElbowOrientation: simd_quatf(
                angle: elbowBend + (max(-rightFootfall.stride, 0) * tuning.elbowTravel),
                axis: [1, 0, 0]
            ),
            rightElbowOrientation: simd_quatf(
                angle: elbowBend + (max(-leftFootfall.stride, 0) * tuning.elbowTravel),
                axis: [1, 0, 0]
            ),
            leftWristOrientation: simd_quatf(
                angle: rightFootfall.stride * tuning.wristTravel,
                axis: [0, 1, 0]
            ),
            rightWristOrientation: simd_quatf(
                angle: leftFootfall.stride * tuning.wristTravel,
                axis: [0, 1, 0]
            )
        )
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

    static func apply(_ pose: ReplayAthleteLocomotionPose, to binding: ReplayAthleteJointBinding) {
        binding[.bodyRoot].position = pose.bodyPosition
        binding[.bodyRoot].orientation = pose.bodyOrientation
        binding[.hips].position = pose.hipsPosition
        binding[.hips].orientation = pose.hipsOrientation
        binding[.spine].orientation = pose.spineOrientation
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
        blend(.leftElbow, toward: simd_quatf(angle: pose.leftElbow, axis: [1, 0, 0]))
        blend(.rightElbow, toward: simd_quatf(angle: pose.rightElbow, axis: [1, 0, 0]))
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

    private struct FootfallTuning {
        let stanceFraction: Float
        let stanceKneeCompression: Float
        let heelStrike: Float
        let toeOff: Float
        let swingDorsiflexion: Float
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
                    stanceFraction: 0.50, stanceKneeCompression: 0.075,
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
                    stanceFraction: 0.40, stanceKneeCompression: 0.095,
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
                    stanceFraction: 0.68, stanceKneeCompression: 0.160,
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
            return ReplayAthleteFootfall(
                stride: stride,
                swingLift: 0,
                stanceCompression: compression,
                footPitch: (-tuning.heelStrike * heelWeight) + (tuning.toeOff * toeWeight),
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
            isStance: false
        )
    }

    private static func smootherStep(_ rawValue: Float) -> Float {
        let value = min(max(rawValue, 0), 1)
        return value * value * value * (value * ((value * 6) - 15) + 10)
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
