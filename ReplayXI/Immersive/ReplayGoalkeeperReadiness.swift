import Foundation
import simd

/// Render-only, evidence-informed keeper preparation, not a save solver or
/// recovered match mocap. FIFA's distance-dependent set-position guidance:
/// https://www.fifatrainingcentre.com/en/practice/elite-sessions/goalkeeper/in_and_out_of_possession.php
/// Keep the existing shoulder-width stance; lower posture/hands as danger gets
/// closer. Only an already observed opponent shot permits a lateral reaction.
/// No root path, ball trajectory, bone length or cervical limit is changed.
@MainActor
enum ReplayGoalkeeperReadiness {
    /// Authored visual delay, not a measured reaction time from the match.
    static let reactionDelay: TimeInterval = 0.18
    static let reactionDuration: TimeInterval = 1.0

    /// The caller supplies only an actual recorded opponent shot, never an
    /// upcoming intent/waypoint or a teammate's distribution. Direction is the
    /// observed outgoing velocity; no eventual goal/save result is supplied.
    struct Shot: Equatable, Sendable {
        let time: TimeInterval
        let origin: SIMD3<Float>
        let velocity: SIMD3<Float>
        /// A later admitted touch invalidates this flight. Release only once
        /// that event is observed, never from knowledge of its future time.
        var supersededAt: TimeInterval? = nil
    }

    struct Sample: Equatable, Sendable {
        let readiness: Float
        let reaction: Float
        /// Signed actor-local X intent, not an anatomical left/right label.
        let lateralIntent: Float
        let highShot: Float
        let closeRange: Float
        let stanceWeight: Float

        var influence: Float { max(readiness, reaction) }
        var armInfluence: Float { influence }
        var crouchMetres: Float {
            readiness * (0.022 + 0.026 * closeRange) + reaction * stanceWeight * 0.016
        }
        var lateralShiftMetres: Float { reaction * stanceWeight * lateralIntent * 0.035 }
        var chestPitchRadians: Float { -0.045 * readiness - 0.025 * reaction }
        var chestRollRadians: Float { -0.11 * lateralIntent * reaction }

        fileprivate var isValid: Bool {
            readiness.isFinite && reaction.isFinite && lateralIntent.isFinite && highShot.isFinite
                && closeRange.isFinite && stanceWeight.isFinite
                && (0...1).contains(readiness) && (0...1).contains(reaction)
                && (-1...1).contains(lateralIntent) && (0...1).contains(highShot)
                && (0...1).contains(closeRange) && (0...1).contains(stanceWeight)
        }
    }

    /// Defensive ceiling for a caller retaining an old preparation sample.
    /// Fresh samples already include this availability, so do not multiply
    /// their easing twice. At the contact core preparation is exactly absent.
    static func limited(_ sample: Sample?, actionInfluence: Float) -> Sample? {
        guard let sample, sample.isValid, sample.influence > 0,
              actionInfluence.isFinite, actionInfluence >= 0, actionInfluence < 0.05 else { return nil }
        let available = 1 - smooth(actionInfluence / 0.05)
        guard available > 0 else { return nil }
        guard sample.influence > available else { return sample }
        let factor = available / sample.influence
        return .init(readiness: sample.readiness * factor, reaction: sample.reaction * factor,
            lateralIntent: sample.lateralIntent, highShot: sample.highShot,
            closeRange: sample.closeRange, stanceWeight: sample.stanceWeight)
    }

    static func sample(track: PlayerTrack, at time: TimeInterval,
                       presentationPose: PlayerPose?, ballPosition: SIMD3<Float>?,
                       shot: Shot? = nil, actionInfluence: Float = 0, enabled: Bool = true,
                       locomotion: PlayerLocomotionSample? = nil) -> Sample? {
        guard enabled, track.isGoalkeeper, time.isFinite,
              let presentationPose, presentationPose.facingDegrees.isFinite,
              presentationPose.position.x.isFinite, presentationPose.position.z.isFinite,
              let ballPosition, finite(ballPosition),
              actionInfluence.isFinite, actionInfluence >= 0, actionInfluence < 0.05 else { return nil }
        if let shot {
            guard shot.time.isFinite, finite(shot.origin), finite(shot.velocity) else { return nil }
            if let supersededAt = shot.supersededAt {
                guard supersededAt.isFinite, supersededAt >= shot.time else { return nil }
            }
        }
        let speed = (locomotion ?? track.locomotion(at: time)).speedMetresPerSecond
        guard speed.isFinite, speed >= 0 else { return nil }
        let angle = presentationPose.facingDegrees.truncatingRemainder(dividingBy: 360) * .pi / 180
        let heading = simd_quatf(angle: angle, axis: [0, 1, 0])
        let origin = SIMD3<Float>(presentationPose.position.x, 0, presentationPose.position.z)
        let localBall = heading.inverse.act(ballPosition - origin)
        let distance = hypot(localBall.x, localBall.z)
        guard distance.isFinite else { return nil }

        // Setting is not a sprint pose. As the keeper relocates quickly, retain
        // the original running cycle; at slower adjustment speeds it can settle.
        let stance = 1 - smooth((speed - 0.7) / 2)
        let available = 1 - smooth(max(actionInfluence, 0) / 0.05)
        let facingBall = 1 - smooth((-localBall.z - 0.25) / 2)
        let nearby = 1 - smooth((distance - 5) / 25)
        let readiness = nearby * facingBall * stance * available
        let closeRange = 1 - smooth((distance - 3) / 5)
        var reaction: Float = 0
        var lateral: Float = 0
        var highShot: Float = 0

        if let shot {
            let elapsed = time - shot.time - reactionDelay
            if elapsed > 0, elapsed < reactionDuration {
                let travel = SIMD2<Float>(shot.velocity.x, shot.velocity.z)
                let toKeeper = SIMD2<Float>(origin.x - shot.origin.x, origin.z - shot.origin.z)
                let speedSquared = simd_length_squared(travel)
                let fromDistance = simd_length(toKeeper)
                if speedSquared > 9, fromDistance > 0.2 {
                    let incoming = simd_dot(travel / sqrt(speedSquared), toKeeper / fromDistance)
                    // A bounded straight-flight estimate reads the velocity we
                    // have already observed. It is only a small reaction cue,
                    // not interception IK or knowledge of a future ball sample.
                    let seconds = min(max(simd_dot(toKeeper, travel) / speedSquared, 0), 1.5)
                    let closest = shot.origin + shot.velocity * seconds
                    let miss = hypot(closest.x - origin.x, closest.z - origin.z)
                    let oncoming = smooth((incoming - 0.45) / 0.40)
                        * (1 - smooth((miss - 3.5) / 5))
                        * (1 - smooth((fromDistance - 30) / 15))
                    let pulse = smooth(Float(elapsed / 0.16))
                        * (1 - smooth(Float((elapsed - 0.38) / 0.62)))
                    reaction = pulse * oncoming * (0.4 + 0.6 * stance) * available
                    if let supersededAt = shot.supersededAt, time >= supersededAt {
                        reaction *= 1 - smooth(Float((time - supersededAt) / 0.10))
                    }
                    if reaction > 0 {
                        let side = heading.inverse.act(closest - origin).x
                        lateral = side / sqrt(side * side + 1.4 * 1.4)
                        // Raise the arms from the visible current ball height,
                        // not an unreached trajectory point or eventual result.
                        highShot = smooth((ballPosition.y - 0.7) / 1.4)
                    }
                }
            }
        }
        let result = Sample(readiness: readiness, reaction: reaction, lateralIntent: lateral,
                            highShot: highShot, closeRange: closeRange, stanceWeight: stance)
        return result.influence > 0 ? result : nil
    }

    /// The keeper's ordinary gait already has a wider base than an outfielder.
    /// Preserve both existing sole positions/orientations instead of spreading
    /// planted feet across the grass. Lowering/weight shift is solved once with
    /// fixed-length legs. No jump, sideways root travel or artificial save.
    static func apply(to base: ReplayAthleteLocomotionPose, sample: Sample?) -> ReplayAthleteLocomotionPose {
        guard let sample, sample.isValid, sample.influence > 0 else { return base }
        let body = simd_normalize(base.bodyOrientation * base.hipsOrientation)
        let oldHips = base.bodyPosition + base.bodyOrientation.act(base.hipsPosition)
        let bodyPosition = base.bodyPosition
            + SIMD3<Float>(sample.lateralShiftMetres, -sample.crouchMetres, 0)
        let newHips = bodyPosition + base.bodyOrientation.act(base.hipsPosition)

        func leg(_ side: ReplayAthleteLeg) -> (simd_quatf, simd_quatf, simd_quatf) {
            let hip = side == .left ? base.leftHipOrientation : base.rightHipOrientation
            let knee = side == .left ? base.leftKneeOrientation : base.rightKneeOrientation
            let ankle = side == .left ? base.leftAnkleOrientation : base.rightAnkleOrientation
            guard sample.crouchMetres > 0 || sample.lateralShiftMetres != 0 else { return (hip, knee, ankle) }
            let upperRotation = body * hip
            let lowerRotation = upperRotation * knee
            let boot = lowerRotation * ankle
            let offset = body.act([side == .left ? -0.137 : 0.137, -0.070, 0])
            let upper = upperRotation.act([0, -0.390, 0])
            let oldAnkle = upper + lowerRotation.act([0, -0.350, 0])
            let sourceAxis = simd_normalize(oldAnkle)
            let sourceBend = upper - sourceAxis * simd_dot(upper, sourceAxis)
            let anatomical = simd_normalize(boot.act([0, 0, 1])
                + body.act([side == .left ? -0.08 : 0.08, 0, 0]))
            let originalPole = simd_length_squared(sourceBend) > 0.000001
                ? simd_normalize(sourceBend) : anatomical
            let pole = originalPole + (anatomical - originalPole) * sample.influence
            let newHip = newHips + offset
            guard let solved = ReplayAthleteTwoBoneIK.solve(hip: newHip, ankle: oldHips + offset + oldAnkle,
                upperLength: 0.390, lowerLength: 0.350, pole: pole) else { return (hip, knee, ankle) }
            let solvedUpper = simd_normalize(simd_quatf(from: upperRotation.act([0, -1, 0]),
                to: simd_normalize(solved.knee - newHip)) * upperRotation)
            let solvedLower = simd_normalize(simd_quatf(from: lowerRotation.act([0, -1, 0]),
                to: simd_normalize(solved.ankle - solved.knee)) * lowerRotation)
            return (simd_normalize(body.inverse * solvedUpper),
                    simd_normalize(solvedUpper.inverse * solvedLower),
                    simd_normalize(solvedLower.inverse * boot))
        }
        let left = leg(.left), right = leg(.right)
        let arms = sample.armInfluence
        let forward = 0.20 - 0.08 * sample.closeRange
            + sample.reaction * (0.25 + 0.65 * sample.highShot)
        let outward: Float = 0.27
        let reach = sample.lateralIntent * sample.reaction * 0.42
        let elbow = 0.92 - 0.22 * sample.closeRange - 0.42 * sample.reaction
        func shoulder(_ original: simd_quatf, lane: Float) -> simd_quatf {
            let target = simd_quatf(angle: lane * outward + reach, axis: [0, 0, 1])
                * simd_quatf(angle: -forward, axis: [1, 0, 0])
            return ReplayAthleteInteractionPose.blend(original, target, arms)
        }
        let chest = simd_quatf(angle: sample.chestRollRadians, axis: [0, 0, 1])
            * simd_quatf(angle: sample.chestPitchRadians, axis: [1, 0, 0]) * base.spineOrientation
        return ReplayAthleteLocomotionPose(
            bodyPosition: bodyPosition, bodyOrientation: base.bodyOrientation,
            hipsPosition: base.hipsPosition, hipsOrientation: base.hipsOrientation,
            spineOrientation: simd_normalize(chest), neckOrientation: base.neckOrientation,
            headOrientation: base.headOrientation,
            leftHipOrientation: left.0, rightHipOrientation: right.0,
            leftKneeOrientation: left.1, rightKneeOrientation: right.1,
            leftAnkleOrientation: left.2, rightAnkleOrientation: right.2,
            leftShoulderOrientation: shoulder(base.leftShoulderOrientation, lane: -1),
            rightShoulderOrientation: shoulder(base.rightShoulderOrientation, lane: 1),
            leftElbowOrientation: ReplayAthleteInteractionPose.blend(base.leftElbowOrientation,
                simd_quatf(angle: -elbow, axis: [1, 0, 0]), arms),
            rightElbowOrientation: ReplayAthleteInteractionPose.blend(base.rightElbowOrientation,
                simd_quatf(angle: -elbow, axis: [1, 0, 0]), arms),
            leftWristOrientation: base.leftWristOrientation, rightWristOrientation: base.rightWristOrientation)
    }

    private static func finite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
            && abs(value.x) < 10_000 && abs(value.y) < 10_000 && abs(value.z) < 10_000
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return min(max(x * x * x * (x * (x * 6 - 15) + 10), 0), 1)
    }
}
