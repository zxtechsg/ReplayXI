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
        apply(locomotionPose(for: track, at: time), to: instance.joints)
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

    static func locomotionPose(for track: PlayerTrack, at time: TimeInterval) -> ReplayAthleteLocomotionPose {
        let motion = track.motion(at: time)
        let effort = gaitEffort(for: track, at: time)
        let turn = turningResponse(for: track, at: time)
        let phase = motion.locomotionPhase
        let cycle = sin(phase)
        let doubleCycle = sin(phase * 2)
        let isMoving = effort > (0.12 / 7.2)
        let strideAmplitude: Float = isMoving ? 0.14 + (effort * 0.50) : 0
        let swing = cycle * strideAmplitude
        let breathing = sin(Float(time) * 1.35 + Float(track.shirtNumber)) * 0.004
        let forwardLean: Float = (effort * 0.11) + (track.isGoalkeeper ? 0.06 : 0)

        let goalkeeperStance: Float = track.isGoalkeeper ? 0.10 : 0.018
        let leftHipSwing = swing
        let rightHipSwing = -swing
        let kneeBase: Float = track.isGoalkeeper ? 0.44 : 0.018 * effort
        let kneeTravel: Float = 0.24 + (effort * 0.68)
        let leftKneeBend = kneeBase + (max(-cycle, 0) * kneeTravel)
        let rightKneeBend = kneeBase + (max(cycle, 0) * kneeTravel)
        let leftToeLift = max(-cycle, 0) * 0.22 * effort
        let rightToeLift = max(cycle, 0) * 0.22 * effort
        let leftAnkleAngle = -((leftHipSwing + leftKneeBend) * 0.90) + leftToeLift
        let rightAnkleAngle = -((rightHipSwing + rightKneeBend) * 0.90) + rightToeLift

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

        let keeperReach: Float = track.isGoalkeeper ? 0.34 : 0.035
        let elbowBend: Float = track.isGoalkeeper ? 0.56 : 0.68 + (effort * 0.32)

        return ReplayAthleteLocomotionPose(
            bodyPosition: [0, groundingOffset + breathing, effort * 0.014],
            bodyOrientation: simd_quatf(angle: -forwardLean * 0.10, axis: [1, 0, 0]),
            hipsPosition: [-cycle * 0.014 * effort, 0.90, 0],
            hipsOrientation: simd_quatf(
                angle: (doubleCycle * 0.024 * effort) - (turn * 0.030 * effort),
                axis: [0, 0, 1]
            ) * simd_quatf(angle: cycle * 0.030 * effort, axis: [0, 1, 0]),
            spineOrientation: simd_quatf(angle: -forwardLean * 0.90, axis: [1, 0, 0])
                * simd_quatf(
                    angle: (-doubleCycle * 0.019 * effort) + (turn * 0.065 * effort),
                    axis: [0, 0, 1]
                )
                * simd_quatf(angle: -cycle * 0.050 * effort, axis: [0, 1, 0]),
            headOrientation: simd_quatf(angle: forwardLean * 0.58, axis: [1, 0, 0])
                * simd_quatf(angle: doubleCycle * 0.014 * effort, axis: [0, 0, 1])
                * simd_quatf(angle: turn * 0.15 * effort, axis: [0, 1, 0]),
            leftHipOrientation: simd_quatf(angle: goalkeeperStance, axis: [0, 0, 1])
                * simd_quatf(angle: leftHipSwing, axis: [1, 0, 0]),
            rightHipOrientation: simd_quatf(angle: -goalkeeperStance, axis: [0, 0, 1])
                * simd_quatf(angle: rightHipSwing, axis: [1, 0, 0]),
            leftKneeOrientation: simd_quatf(angle: leftKneeBend, axis: [1, 0, 0]),
            rightKneeOrientation: simd_quatf(angle: rightKneeBend, axis: [1, 0, 0]),
            leftAnkleOrientation: simd_quatf(angle: leftAnkleAngle, axis: [1, 0, 0]),
            rightAnkleOrientation: simd_quatf(angle: rightAnkleAngle, axis: [1, 0, 0]),
            leftShoulderOrientation: simd_quatf(angle: -keeperReach, axis: [0, 0, 1])
                * simd_quatf(angle: -swing * 0.82, axis: [1, 0, 0]),
            rightShoulderOrientation: simd_quatf(angle: keeperReach, axis: [0, 0, 1])
                * simd_quatf(angle: swing * 0.82, axis: [1, 0, 0]),
            leftElbowOrientation: simd_quatf(
                angle: elbowBend + (max(cycle, 0) * 0.12 * effort),
                axis: [1, 0, 0]
            ),
            rightElbowOrientation: simd_quatf(
                angle: elbowBend + (max(-cycle, 0) * 0.12 * effort),
                axis: [1, 0, 0]
            ),
            leftWristOrientation: simd_quatf(angle: -cycle * 0.10 * effort, axis: [0, 1, 0]),
            rightWristOrientation: simd_quatf(angle: cycle * 0.10 * effort, axis: [0, 1, 0])
        )
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
        let halfWindow: TimeInterval = 0.12
        let start = track.pose(at: time - halfWindow).position
        let end = track.pose(at: time + halfWindow).position
        let sampledSpeed = ReplayGeometry.distance(start, end) / Float(halfWindow * 2)
        return min(max(sampledSpeed / 7.2, 0), 1)
    }

    static func turningResponse(for track: PlayerTrack, at time: TimeInterval) -> Float {
        let halfWindow: TimeInterval = 0.12
        let start = track.pose(at: time - halfWindow).facingDegrees
        let end = track.pose(at: time + halfWindow).facingDegrees
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        let degreesPerSecond = delta / Float(halfWindow * 2)
        return min(max(degreesPerSecond / 180, -1), 1)
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
