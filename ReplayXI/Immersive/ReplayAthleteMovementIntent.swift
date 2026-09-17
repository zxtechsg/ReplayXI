import Foundation
import simd

/// Optional presentation-aware footwork for authored reconstructions. A body
/// watching the ball can side-step/backpedal without its legs running forwards.
/// The original telemetry-only path remains unchanged when no pose is supplied.
@MainActor
enum ReplayAthleteMovementIntent {
    /// Preserve the already-validated contact preparation while easing the new
    /// off-ball mechanics in/out just outside the recorded action window.
    static let contactPreparationMargin: TimeInterval = 0.12

    struct Sample: Sendable {
        let localTravelYaw: Float
        let directionalWeight: Float
        let readiness: Float
        /// Faster lateral steps use a short, uncrossed defensive stance. Gentle
        /// repositioning and a forward run retain their existing ankle paths.
        let shuffleWeight: Float
        let contactProtection: Float
        var influence: Float { max(directionalWeight, readiness) }

        init(localTravelYaw: Float, directionalWeight: Float, readiness: Float,
             shuffleWeight: Float = 0, contactProtection: Float = 0) {
            self.localTravelYaw = localTravelYaw
            self.directionalWeight = directionalWeight
            self.readiness = readiness
            self.shuffleWeight = shuffleWeight
            self.contactProtection = contactProtection
        }
    }

    static func sample(track: PlayerTrack, at time: TimeInterval,
                       presentationPose: PlayerPose?, lookTarget: SIMD3<Float>?,
                       interaction: ReplayAthleteInteractionCue? = nil) -> Sample? {
        guard let presentationPose, time.isFinite, presentationPose.facingDegrees.isFinite,
              presentationPose.position.x.isFinite, presentationPose.position.z.isFinite else { return nil }
        let before = track.presentationPose(at: time - 0.08).position
        let after = track.presentationPose(at: time + 0.08).position
        let velocity = SIMD3<Float>((after.x - before.x) / 0.16, 0, (after.z - before.z) / 0.16)
        let speed = simd_length(velocity)
        guard speed.isFinite else { return nil }
        // Retain the original arithmetic for ordinary authored headings: tiny
        // changes can alter a grazing native-ball collision. Wrap only when an
        // otherwise finite, extreme input would overflow conversion to radians.
        let rawAngle = presentationPose.facingDegrees * .pi / 180
        let angle = rawAngle.isFinite ? rawAngle
            : presentationPose.facingDegrees.truncatingRemainder(dividingBy: 360) * .pi / 180
        let heading = simd_quatf(angle: angle, axis: [0, 1, 0])
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
        let shuffle = weight * smooth((speed - 0.65) / 0.65)
            * smooth((abs(sin(yaw)) - 0.30) / 0.55)
        return Sample(localTravelYaw: yaw, directionalWeight: weight,
                      readiness: readiness, shuffleWeight: shuffle,
                      contactProtection: contactProtection(for: interaction, track: track, at: time))
    }

    static func includesPreparation(_ cue: ReplayAthleteInteractionCue, at time: TimeInterval) -> Bool {
        time.isFinite && cue.startTime.isFinite && cue.endTime.isFinite
            && time >= cue.startTime - contactPreparationMargin
            && time <= cue.endTime + contactPreparationMargin
    }

    static func contactProtection(for cue: ReplayAthleteInteractionCue?, track: PlayerTrack,
                                  at time: TimeInterval) -> Float {
        guard let cue, includesPreparation(cue, at: time),
              ReplayAthleteInteractionPose.sample(cue: cue, at: cue.contactTime, track: track) != nil
        else { return 0 }
        let entering = smooth(Float((time - cue.startTime + contactPreparationMargin) / contactPreparationMargin))
        let leaving = 1 - smooth(Float((time - cue.endTime) / contactPreparationMargin))
        return min(entering, leaving)
    }

    static func apply(to base: ReplayAthleteLocomotionPose, sample: Sample?) -> ReplayAthleteLocomotionPose {
        guard let sample, sample.localTravelYaw.isFinite,
              sample.directionalWeight.isFinite, sample.readiness.isFinite, sample.shuffleWeight.isFinite,
              sample.contactProtection.isFinite,
              sample.influence > 0 else { return base }
        let direction = min(max(sample.directionalWeight, 0), 1)
        let ready = min(max(sample.readiness, 0), 1)
        let influence = max(direction, ready)
        let shuffle = min(max(sample.shuffleWeight, 0), direction)
        let protection = min(max(sample.contactProtection, 0), 1)
        let travel = simd_quatf(angle: sample.localTravelYaw, axis: [0, 1, 0])
        let body = simd_normalize(base.bodyOrientation * base.hipsOrientation)
        let oldHips = base.bodyPosition + base.bodyOrientation.act(base.hipsPosition)
        let legacyBodyPosition = base.bodyPosition - SIMD3<Float>(0, 0.020 * ready, 0)
        let bodyPosition = legacyBodyPosition - SIMD3<Float>(0, 0.018 * shuffle * (1 - protection), 0)
        let newHips = bodyPosition + base.bodyOrientation.act(base.hipsPosition)
        let legacyHips = legacyBodyPosition + base.bodyOrientation.act(base.hipsPosition)

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
            var goal = oldHip + relativeFoot + (rotated - relativeFoot) * direction
            var protectedLeg: (simd_quatf, simd_quatf, simd_quatf)?
            if protection > 0, let solved = ReplayAthleteTwoBoneIK.solve(
                hip: legacyHips + offset, ankle: goal, upperLength: 0.390, lowerLength: 0.350, pole: [0, 0, 1]) {
                // Deliberately identical to the validated pre-129 contact
                // footwork, including its original weighted joint solve. Native
                // collision proxies and the renderer consume this same branch.
                let original = (
                    ReplayAthleteInteractionPose.blend(hip, body.inverse * solved.upperRotation, influence),
                    ReplayAthleteInteractionPose.blend(knee, solved.upperRotation.inverse * solved.lowerRotation, influence),
                    ReplayAthleteInteractionPose.blend(ankle, solved.lowerRotation.inverse * footRotation, influence))
                if protection == 1 { return original }
                protectedLeg = original
            }
            if shuffle > 0 {
                // Rotating a forward gait by 90 degrees also rotates its lateral
                // ankle spread: on the return step a boot could pass through the
                // opposite boot. Keep each ankle in its own pelvis-local lane.
                // The eased floor has a zero slope at the inside bound and
                // matches the unmodified path at the outside edge; no hard snap.
                var lane = body.inverse.act(goal - oldHips)
                let sideSign: Float = side == .left ? -1 : 1
                let oldLane = lane.x * sideSign
                let safeLane = easedFloor(oldLane, minimum: 0.070, transition: 0.055)
                lane.x += sideSign * (safeLane - oldLane) * shuffle
                goal = oldHips + body.act(lane)
            }
            let newHip = newHips + offset
            let pole = kneePole(side: side, body: body, foot: footRotation,
                                upper: hipRotation.act([0, -0.390, 0]),
                                ankle: relativeFoot, influence: influence)
            guard let solved = ReplayAthleteTwoBoneIK.solve(hip: newHip, ankle: goal,
                                                          upperLength: 0.390, lowerLength: 0.350,
                                                          pole: pole) else { return (hip, knee, ankle) }
            // Goals/body lowering already carry their blend weights. Blending
            // the solved joints a second time left partially ready feet sinking
            // into the ground. Solve the weighted endpoints exactly instead.
            // Swing each original bone onto the solved direction, preserving
            // its axial twist. A tiny influence cannot replace that twist with
            // an unrelated minimal-rotation frame at an IK admission boundary.
            let upper = simd_normalize(simd_quatf(
                from: hipRotation.act([0, -1, 0]),
                to: simd_normalize(solved.knee - newHip)) * hipRotation)
            let lower = simd_normalize(simd_quatf(
                from: kneeRotation.act([0, -1, 0]),
                to: simd_normalize(solved.ankle - solved.knee)) * kneeRotation)
            let refined = (
                simd_normalize(body.inverse * upper),
                simd_normalize(upper.inverse * lower),
                simd_normalize(lower.inverse * footRotation)
            )
            if let protectedLeg {
                return (ReplayAthleteInteractionPose.blend(refined.0, protectedLeg.0, protection),
                        ReplayAthleteInteractionPose.blend(refined.1, protectedLeg.1, protection),
                        ReplayAthleteInteractionPose.blend(refined.2, protectedLeg.2, protection))
            }
            return refined
        }
        let left = leg(.left)
        let right = leg(.right)
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

    private static func kneePole(side: ReplayAthleteLeg, body: simd_quatf,
                                 foot: simd_quatf, upper: SIMD3<Float>,
                                 ankle: SIMD3<Float>, influence: Float) -> SIMD3<Float> {
        let down = simd_normalize(ankle)
        let original = upper - down * simd_dot(upper, down)
        // Knees follow the body's/boot's forward plane, not the direction of a
        // backpedal. A small outward component prevents knock-kneed shuffles.
        let anatomical = simd_normalize(foot.act([0, 0, 1])
            + body.act([side == .left ? -0.10 : 0.10, 0, 0]))
        let source = simd_length_squared(original) > 0.000_001
            ? simd_normalize(original) : anatomical
        let blended = source + (anatomical - source) * influence
        return simd_length_squared(blended) > 0.000_001 ? simd_normalize(blended) : anatomical
    }

    private static func easedFloor(_ value: Float, minimum: Float, transition: Float) -> Float {
        if value <= minimum { return minimum }
        if value >= minimum + transition { return value }
        let t = (value - minimum) / transition
        return minimum + transition * t * t * (2 - t)
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
