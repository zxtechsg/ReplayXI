import Foundation
import simd

/// Optional presentation-aware footwork for authored reconstructions. A body
/// watching the ball can side-step/backpedal without its legs running forwards.
/// The original telemetry-only path remains unchanged when no pose is supplied.
@MainActor
enum ReplayAthleteMovementIntent {
    struct Sample: Sendable {
        let localTravelYaw: Float
        let directionalWeight: Float
        let readiness: Float
        var influence: Float { max(directionalWeight, readiness) }
    }

    static func sample(track: PlayerTrack, at time: TimeInterval,
                       presentationPose: PlayerPose?, lookTarget: SIMD3<Float>?) -> Sample? {
        guard let presentationPose, time.isFinite, presentationPose.facingDegrees.isFinite,
              presentationPose.position.x.isFinite, presentationPose.position.z.isFinite else { return nil }
        let before = track.presentationPose(at: time - 0.08).position
        let after = track.presentationPose(at: time + 0.08).position
        let velocity = SIMD3<Float>((after.x - before.x) / 0.16, 0, (after.z - before.z) / 0.16)
        let speed = simd_length(velocity)
        guard speed.isFinite else { return nil }
        let heading = simd_quatf(angle: presentationPose.facingDegrees * .pi / 180, axis: [0, 1, 0])
        let local = heading.inverse.act(velocity)
        let yaw = speed > 0.0001 ? atan2(local.x, local.z) : 0
        let weight = smooth((speed - 0.08) / 0.25) * (1 - smooth((speed - 2.8) / 1.7))
            * smooth((abs(yaw) - 0.22) / 0.50)
        var readiness: Float = 0
        if let target = lookTarget, target.x.isFinite, target.y.isFinite, target.z.isFinite {
            let distance = hypot(target.x - presentationPose.position.x, target.z - presentationPose.position.z)
            if distance.isFinite {
                readiness = smooth((1.05 - speed) / 0.80) * (1 - smooth((distance - 3) / 6))
            }
        }
        return Sample(localTravelYaw: yaw, directionalWeight: weight, readiness: readiness)
    }

    static func apply(to base: ReplayAthleteLocomotionPose, sample: Sample?) -> ReplayAthleteLocomotionPose {
        guard let sample, sample.influence > 0 else { return base }
        let travel = simd_quatf(angle: sample.localTravelYaw, axis: [0, 1, 0])
        let body = simd_normalize(base.bodyOrientation * base.hipsOrientation)
        let oldHips = base.bodyPosition + base.bodyOrientation.act(base.hipsPosition)
        let bodyPosition = base.bodyPosition - SIMD3<Float>(0, 0.020 * sample.readiness, 0)
        let newHips = bodyPosition + base.bodyOrientation.act(base.hipsPosition)

        func leg(_ side: ReplayAthleteLeg) -> (simd_quatf, simd_quatf, simd_quatf) {
            let hip = side == .left ? base.leftHipOrientation : base.rightHipOrientation
            let knee = side == .left ? base.leftKneeOrientation : base.rightKneeOrientation
            let ankle = side == .left ? base.leftAnkleOrientation : base.rightAnkleOrientation
            let hipRotation = body * hip
            let kneeRotation = hipRotation * knee
            let footRotation = kneeRotation * ankle
            let offset = body.act([side == .left ? -0.137 : 0.137, -0.070, 0])
            let oldHip = oldHips + offset
            let relativeFoot = hipRotation.act([0, -0.390, 0]) + kneeRotation.act([0, -0.350, 0])
            let rotated = travel.act(relativeFoot)
            let goal = oldHip + relativeFoot + (rotated - relativeFoot) * sample.directionalWeight
            guard let solved = ReplayAthleteTwoBoneIK.solve(hip: newHips + offset, ankle: goal,
                                                          upperLength: 0.390, lowerLength: 0.350,
                                                          pole: [0, 0, 1]) else { return (hip, knee, ankle) }
            return (
                ReplayAthleteInteractionPose.blend(hip, body.inverse * solved.upperRotation, sample.influence),
                ReplayAthleteInteractionPose.blend(knee, solved.upperRotation.inverse * solved.lowerRotation, sample.influence),
                ReplayAthleteInteractionPose.blend(ankle, solved.lowerRotation.inverse * footRotation, sample.influence)
            )
        }
        let left = leg(.left)
        let right = leg(.right)
        let ready = sample.readiness
        return ReplayAthleteLocomotionPose(
            bodyPosition: bodyPosition, bodyOrientation: base.bodyOrientation,
            hipsPosition: base.hipsPosition, hipsOrientation: base.hipsOrientation,
            spineOrientation: base.spineOrientation, neckOrientation: base.neckOrientation,
            headOrientation: base.headOrientation,
            leftHipOrientation: left.0, rightHipOrientation: right.0,
            leftKneeOrientation: left.1, rightKneeOrientation: right.1,
            leftAnkleOrientation: left.2, rightAnkleOrientation: right.2,
            leftShoulderOrientation: ReplayAthleteInteractionPose.blend(base.leftShoulderOrientation,
                simd_quatf(angle: -0.22, axis: [0, 0, 1]) * simd_quatf(angle: -0.16, axis: [1, 0, 0]), ready),
            rightShoulderOrientation: ReplayAthleteInteractionPose.blend(base.rightShoulderOrientation,
                simd_quatf(angle: 0.22, axis: [0, 0, 1]) * simd_quatf(angle: -0.16, axis: [1, 0, 0]), ready),
            leftElbowOrientation: ReplayAthleteInteractionPose.blend(base.leftElbowOrientation,
                simd_quatf(angle: -0.42, axis: [1, 0, 0]), ready),
            rightElbowOrientation: ReplayAthleteInteractionPose.blend(base.rightElbowOrientation,
                simd_quatf(angle: -0.42, axis: [1, 0, 0]), ready),
            leftWristOrientation: base.leftWristOrientation, rightWristOrientation: base.rightWristOrientation
        )
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
