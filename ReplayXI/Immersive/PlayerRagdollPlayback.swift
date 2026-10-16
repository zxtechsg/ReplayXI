import Foundation
import simd

/// An explicit, single-player impact cue authored on the same clock as match
/// telemetry. Nothing in normal playback infers a fall from player proximity;
/// callers opt into this state for a reviewed contact moment.
struct PlayerRagdollCue: Equatable, Sendable {
    static let maximumDuration: TimeInterval = 4

    let playerID: String
    let impactTime: TimeInterval
    let duration: TimeInterval
    /// Unit push direction in the player's local X/Z plane.
    let impactDirection: SIMD2<Float>
    let impulse: Float

    init(
        playerID: String,
        impactTime: TimeInterval,
        duration: TimeInterval = 3.2,
        impactDirection: SIMD2<Float> = SIMD2<Float>(0.34, 0.94),
        impulse: Float = 1
    ) {
        self.playerID = playerID
        self.impactTime = impactTime.isFinite ? impactTime : 0
        self.duration = min(
            max(duration.isFinite ? duration : 3.2, 1),
            Self.maximumDuration
        )

        let directionLength = simd_length(impactDirection)
        if directionLength.isFinite, directionLength > 0.001 {
            self.impactDirection = impactDirection / directionLength
        } else {
            self.impactDirection = SIMD2<Float>(0, 1)
        }
        self.impulse = min(max(impulse.isFinite ? impulse : 1, 0.35), 2.1)
    }

    var endTime: TimeInterval { impactTime + duration }

    func isActive(at time: TimeInterval) -> Bool {
        time >= impactTime && time < endTime
    }

    /// Soft entry and recovery prevent a discontinuity at either edge when a
    /// coach scrubs across the authored cue.
    func influence(at time: TimeInterval) -> Float {
        guard isActive(at: time) else { return 0 }
        let elapsed = Float(time - impactTime)
        let attack = ragdollSmoothstep(min(max(elapsed / 0.12, 0), 1))
        let releaseDuration = min(Float(duration) * 0.28, 0.72)
        let timeRemaining = Float(endTime - time)
        let release = ragdollSmoothstep(min(max(timeRemaining / releaseDuration, 0), 1))
        return attack * release
    }

    /// Holds the player at the impact location until the recovery blend. This
    /// avoids a fallen body being carried downfield by its upright telemetry.
    func telemetryRelease(at time: TimeInterval) -> Float {
        guard isActive(at: time) else { return 1 }
        let releaseDuration = min(Float(duration) * 0.28, 0.72)
        let releaseStart = Float(duration) - releaseDuration
        let elapsed = Float(time - impactTime)
        return ragdollSmoothstep(min(max((elapsed - releaseStart) / releaseDuration, 0), 1))
    }

    /// Rights-safe authored showcase: during Coach Focus, the nearby left-back
    /// loses balance as seven releases the overlap. Keeping this mapping here
    /// makes the physics state visible in the shipped prototype while limiting
    /// it to one known subject and one short, reviewable match window.
    static func authoredDemo(for scenario: ReplayScenario) -> PlayerRagdollCue? {
        guard scenario.id == "everyone-with-seven",
              scenario.player(id: "red-lb") != nil
        else { return nil }
        return PlayerRagdollCue(
            playerID: "red-lb",
            impactTime: 13.55,
            duration: 2.8,
            impactDirection: SIMD2<Float>(-0.55, 0.84),
            impulse: 0.92
        )
    }
}

/// Joint-space output from the deterministic impact solver. Keeping this as a
/// value type makes reset and seek behaviour testable without a running scene.
struct PlayerRagdollPose: Equatable, Sendable {
    let bodyCenter: SIMD3<Float>
    let fallAxis: SIMD3<Float>
    let fallAngle: Float
    let bodyTwist: Float
    let spinePitch: Float
    let spineRoll: Float
    let headPitch: Float
    let headYaw: Float
    let leftHip: Float
    let rightHip: Float
    let leftKnee: Float
    let rightKnee: Float
    let leftAnkle: Float
    let rightAnkle: Float
    let leftShoulderPitch: Float
    let rightShoulderPitch: Float
    let leftShoulderRoll: Float
    let rightShoulderRoll: Float
    let leftElbow: Float
    let rightElbow: Float
    let leftWrist: Float
    let rightWrist: Float
}

/// A small fixed-step rigid-body approximation for replay, not a frame-driven
/// gameplay simulation. Gravity, angular momentum, ground restitution,
/// friction, joint springs and hard joint limits all contribute to the pose.
/// Reintegrating from the cue at an absolute timestamp is deliberately cheap
/// (at most 360 stack-only steps) and guarantees identical results after seek.
enum PlayerRagdollPlayback {
    static let fixedTimeStep: Float = 1 / 90
    static let maximumStepCount = 360

    /// One absolute-clock result shared by the skin and its kinematic query rig.
    /// The solver must not run on separate frame clocks for those two bodies.
    struct Sample: Equatable, Sendable {
        let playerID: String
        let time: TimeInterval
        let pose: PlayerRagdollPose
        let influence: Float
    }

    static func sample(for cue: PlayerRagdollCue, at time: TimeInterval) -> Sample? {
        guard time.isFinite, cue.isActive(at: time) else { return nil }
        return Sample(playerID: cue.playerID, time: time, pose: pose(for: cue, at: time),
                      influence: cue.influence(at: time))
    }

    static func pose(for cue: PlayerRagdollCue, at time: TimeInterval) -> PlayerRagdollPose {
        // A malformed timestamp must not reach Int(NaN) in the fixed-step loop.
        let elapsed = time.isFinite ? min(max(Float(time - cue.impactTime), 0), Float(cue.duration)) : 0
        var state = SimulationState(cue: cue)
        let completeSteps = min(Int(elapsed / fixedTimeStep), maximumStepCount)
        if completeSteps > 0 {
            for _ in 0..<completeSteps {
                state.advance(by: fixedTimeStep, cue: cue)
            }
        }
        let simulatedTime = Float(completeSteps) * fixedTimeStep
        let remainder = min(max(elapsed - simulatedTime, 0), fixedTimeStep)
        if remainder > 0.000_001, completeSteps < maximumStepCount {
            state.advance(by: remainder, cue: cue)
        }
        return state.pose(cue: cue)
    }

    private struct JointState {
        var angle: Float = 0
        var velocity: Float
    }

    private struct SimulationState {
        var bodyCenter = SIMD3<Float>(0, 0.92, 0)
        var linearVelocity: SIMD3<Float>
        var fallAngle: Float = 0
        var fallVelocity: Float
        var bodyTwist: Float = 0
        var twistVelocity: Float

        var spinePitch: JointState
        var spineRoll: JointState
        var headPitch: JointState
        var headYaw: JointState
        var leftHip: JointState
        var rightHip: JointState
        var leftKnee: JointState
        var rightKnee: JointState
        var leftAnkle: JointState
        var rightAnkle: JointState
        var leftShoulderPitch: JointState
        var rightShoulderPitch: JointState
        var leftShoulderRoll: JointState
        var rightShoulderRoll: JointState
        var leftElbow: JointState
        var rightElbow: JointState
        var leftWrist: JointState
        var rightWrist: JointState

        init(cue: PlayerRagdollCue) {
            let direction = cue.impactDirection
            let seed = stableSeed(cue.playerID)
            let lateralVariation = seededUnit(seed, salt: 1)
            let reachVariation = seededUnit(seed, salt: 2)
            linearVelocity = [
                direction.x * (0.55 + cue.impulse * 0.55),
                0.20 + cue.impulse * 0.24,
                direction.y * (0.55 + cue.impulse * 0.55),
            ]
            fallVelocity = 1.22 + cue.impulse * 1.34
            twistVelocity = lateralVariation * (0.48 + cue.impulse * 0.28)

            spinePitch = JointState(velocity: -0.32 * cue.impulse)
            spineRoll = JointState(velocity: lateralVariation * 0.52)
            headPitch = JointState(velocity: -0.58 * cue.impulse)
            headYaw = JointState(velocity: -lateralVariation * 0.82)
            leftHip = JointState(velocity: (0.68 + reachVariation * 0.18) * cue.impulse)
            rightHip = JointState(velocity: (-0.52 + reachVariation * 0.12) * cue.impulse)
            leftKnee = JointState(velocity: 0.84 * cue.impulse)
            rightKnee = JointState(velocity: 0.48 * cue.impulse)
            leftAnkle = JointState(velocity: -0.44 * cue.impulse)
            rightAnkle = JointState(velocity: 0.32 * cue.impulse)
            leftShoulderPitch = JointState(velocity: (-1.05 + reachVariation * 0.2) * cue.impulse)
            rightShoulderPitch = JointState(velocity: (0.80 + reachVariation * 0.2) * cue.impulse)
            leftShoulderRoll = JointState(velocity: -0.72 * cue.impulse)
            rightShoulderRoll = JointState(velocity: 0.58 * cue.impulse)
            leftElbow = JointState(velocity: 1.05 * cue.impulse)
            rightElbow = JointState(velocity: 0.78 * cue.impulse)
            leftWrist = JointState(velocity: -0.62 * cue.impulse)
            rightWrist = JointState(velocity: 0.54 * cue.impulse)
        }

        mutating func advance(by dt: Float, cue: PlayerRagdollCue) {
            linearVelocity.y -= 9.81 * dt
            let airDrag = max(0, 1 - 0.18 * dt)
            linearVelocity.x *= airDrag
            linearVelocity.z *= airDrag
            bodyCenter += linearVelocity * dt

            // A falling body's centre approaches the turf as its long axis
            // turns horizontal. This orientation-aware support height is the
            // ground constraint for the simplified rigid torso.
            fallVelocity += (2.35 + 4.15 * sin(min(fallAngle, 1.48))) * dt
            fallVelocity *= max(0, 1 - 0.34 * dt)
            fallAngle += fallVelocity * dt
            if fallAngle > 1.48 {
                fallAngle = 1.48
                fallVelocity = min(fallVelocity, 0) * -0.10
            }

            let supportHeight = 0.18 + 0.74 * abs(cos(fallAngle))
            if bodyCenter.y < supportHeight {
                bodyCenter.y = supportHeight
                if linearVelocity.y < 0 {
                    linearVelocity.y *= -0.08
                }
                let turfFriction = max(0, 1 - 7.2 * dt)
                linearVelocity.x *= turfFriction
                linearVelocity.z *= turfFriction
                fallVelocity *= max(0, 1 - 6.0 * dt)
            }

            bodyTwist += twistVelocity * dt
            twistVelocity *= max(0, 1 - 2.3 * dt)
            bodyTwist = min(max(bodyTwist, -0.42), 0.42)

            let settled = ragdollSmoothstep(min(max((fallAngle - 0.12) / 1.30, 0), 1))
            let side = cue.impactDirection.x >= 0 ? Float(1) : -1

            advanceJoint(&spinePitch, target: -0.10 * settled, stiffness: 8, damping: 4.7, limits: -0.42...0.34, dt: dt)
            advanceJoint(&spineRoll, target: side * 0.13 * settled, stiffness: 7, damping: 4.3, limits: -0.38...0.38, dt: dt)
            advanceJoint(&headPitch, target: 0.16 * settled, stiffness: 6.5, damping: 4.1, limits: -0.55...0.58, dt: dt)
            advanceJoint(&headYaw, target: -side * 0.20 * settled, stiffness: 5.8, damping: 3.9, limits: -0.60...0.60, dt: dt)

            advanceJoint(&leftHip, target: (0.48 + side * 0.10) * settled, stiffness: 7.2, damping: 4.0, limits: -1.0...1.18, dt: dt)
            advanceJoint(&rightHip, target: (-0.34 + side * 0.08) * settled, stiffness: 7.0, damping: 4.0, limits: -1.0...1.18, dt: dt)
            advanceJoint(&leftKnee, target: 0.92 * settled, stiffness: 8.5, damping: 4.6, limits: 0...1.62, dt: dt)
            advanceJoint(&rightKnee, target: 0.54 * settled, stiffness: 8.2, damping: 4.5, limits: 0...1.62, dt: dt)
            advanceJoint(&leftAnkle, target: -0.18 * settled, stiffness: 8, damping: 4.4, limits: -0.62...0.48, dt: dt)
            advanceJoint(&rightAnkle, target: 0.12 * settled, stiffness: 8, damping: 4.4, limits: -0.62...0.48, dt: dt)

            advanceJoint(&leftShoulderPitch, target: -0.72 * settled, stiffness: 6, damping: 3.6, limits: -1.35...1.35, dt: dt)
            advanceJoint(&rightShoulderPitch, target: 0.56 * settled, stiffness: 6, damping: 3.6, limits: -1.35...1.35, dt: dt)
            advanceJoint(&leftShoulderRoll, target: -0.38 * settled, stiffness: 6.4, damping: 3.8, limits: -1.0...0.85, dt: dt)
            advanceJoint(&rightShoulderRoll, target: 0.30 * settled, stiffness: 6.4, damping: 3.8, limits: -0.85...1.0, dt: dt)
            advanceJoint(&leftElbow, target: 0.88 * settled, stiffness: 7.5, damping: 4.1, limits: 0.08...1.72, dt: dt)
            advanceJoint(&rightElbow, target: 0.70 * settled, stiffness: 7.5, damping: 4.1, limits: 0.08...1.72, dt: dt)
            advanceJoint(&leftWrist, target: -0.16 * settled, stiffness: 7, damping: 4.0, limits: -0.65...0.65, dt: dt)
            advanceJoint(&rightWrist, target: 0.13 * settled, stiffness: 7, damping: 4.0, limits: -0.65...0.65, dt: dt)
        }

        func pose(cue: PlayerRagdollCue) -> PlayerRagdollPose {
            // Rotating upright +Y around this horizontal axis sends the torso
            // along the requested X/Z impact direction.
            let fallAxis = simd_normalize(
                SIMD3<Float>(cue.impactDirection.y, 0, -cue.impactDirection.x)
            )
            return PlayerRagdollPose(
                bodyCenter: bodyCenter,
                fallAxis: fallAxis,
                fallAngle: fallAngle,
                bodyTwist: bodyTwist,
                spinePitch: spinePitch.angle,
                spineRoll: spineRoll.angle,
                headPitch: headPitch.angle,
                headYaw: headYaw.angle,
                leftHip: leftHip.angle,
                rightHip: rightHip.angle,
                leftKnee: leftKnee.angle,
                rightKnee: rightKnee.angle,
                leftAnkle: leftAnkle.angle,
                rightAnkle: rightAnkle.angle,
                leftShoulderPitch: leftShoulderPitch.angle,
                rightShoulderPitch: rightShoulderPitch.angle,
                leftShoulderRoll: leftShoulderRoll.angle,
                rightShoulderRoll: rightShoulderRoll.angle,
                leftElbow: leftElbow.angle,
                rightElbow: rightElbow.angle,
                leftWrist: leftWrist.angle,
                rightWrist: rightWrist.angle
            )
        }
    }

    private static func advanceJoint(
        _ joint: inout JointState,
        target: Float,
        stiffness: Float,
        damping: Float,
        limits: ClosedRange<Float>,
        dt: Float
    ) {
        let acceleration = ((target - joint.angle) * stiffness) - (joint.velocity * damping)
        joint.velocity += acceleration * dt
        joint.angle += joint.velocity * dt
        if joint.angle < limits.lowerBound {
            joint.angle = limits.lowerBound
            joint.velocity = max(joint.velocity, 0) * 0.12
        } else if joint.angle > limits.upperBound {
            joint.angle = limits.upperBound
            joint.velocity = min(joint.velocity, 0) * 0.12
        }
    }

    private static func stableSeed(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(2_166_136_261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16_777_619
        }
    }

    private static func seededUnit(_ seed: UInt32, salt: UInt32) -> Float {
        var value = seed &+ (salt &* 0x9E37_79B9)
        value ^= value >> 16
        value &*= 0x7FEB_352D
        value ^= value >> 15
        value &*= 0x846C_A68B
        value ^= value >> 16
        return (Float(value & 0xFFFF) / 32_767.5) - 1
    }
}

private func ragdollSmoothstep(_ value: Float) -> Float {
    value * value * (3 - (2 * value))
}
