import Foundation
import simd

/// Collision proxies for the shared articulated leg chain. These are bounded
/// teaching-replay envelopes, not exact collision meshes for an imported skin.
/// No entities or meshes are created while preparing a ball path.
struct ReplayBallPlayerContact: Sendable {
    struct Capsule: Sendable {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        let radius: Float

        func nearestPoint(to point: SIMD3<Float>) -> SIMD3<Float> {
            let delta = end - start
            let denominator = simd_length_squared(delta)
            let fraction = denominator > 0.000_001
                ? min(max(simd_dot(point - start, delta) / denominator, 0), 1) : 0
            return start + delta * fraction
        }
    }

    let origin: PitchPoint
    let leftShin: Capsule
    let rightShin: Capsule
    let leftBoot: Capsule
    let rightBoot: Capsule
    let leftToe: SIMD3<Float>
    let rightToe: SIMD3<Float>
    let leftForward: SIMD3<Float>
    let rightForward: SIMD3<Float>

    @MainActor
    init(player: PlayerTrack, ball: BallTrack, time: TimeInterval,
        interaction: ReplayAthleteInteractionCue? = nil, presentationPose: PlayerPose? = nil) {
        let playerPose = presentationPose ?? player.presentationPose(at: time)
        let activeInteraction = interaction.map { time >= $0.startTime && time <= $0.endTime } ?? false
        let action = activeInteraction ? nil
            : ReplayAthleteMotion.ballActionPose(for: player, ballTrack: ball, at: time)
        // Share the render-side contact preparation without applying the
        // interaction twice: the actual strike is still applied once below.
        let movement = ReplayAthleteMovementIntent.sample(track: player, at: time,
            presentationPose: presentationPose, lookTarget: nil, interaction: interaction)
        let base = ReplayAthleteMotion.locomotionPose(
            for: player, at: time, locomotion: player.locomotion(at: time),
            gaitPhase: player.gaitPhase(at: time),
            ballAction: action,
            presentationPose: presentationPose,
            movementIntent: movement
        )
        let pose = interaction.map {
            ReplayAthleteInteractionPose.apply(to: base, cue: $0, at: time,
                                               track: player, presentationPose: playerPose)
        } ?? base
        let heading = simd_quatf(angle: playerPose.facingDegrees * .pi / 180, axis: [0, 1, 0])
        let actor = SIMD3<Float>(playerPose.position.x, 0, playerPose.position.z)
        let bodyPosition = actor + heading.act(pose.bodyPosition)
        let bodyRotation = heading * pose.bodyOrientation
        let hipsPosition = bodyPosition + bodyRotation.act(pose.hipsPosition)
        let hipsRotation = bodyRotation * pose.hipsOrientation
        let usesExplicitBoot = activeInteraction
            && (interaction.map { $0.kind != .header && $0.kind != .save } ?? false)

        func leg(x: Float, hip: simd_quatf, knee: simd_quatf,
                 ankle: simd_quatf) -> (Capsule, Capsule, SIMD3<Float>, SIMD3<Float>) {
            let hipPosition = hipsPosition + hipsRotation.act([x, -0.070, 0])
            let hipRotation = hipsRotation * hip
            let kneePosition = hipPosition + hipRotation.act([0, -0.390, 0])
            let kneeRotation = hipRotation * knee
            let anklePosition = kneePosition + kneeRotation.act([0, -0.350, 0])
            let ankleRotation = kneeRotation * ankle
            // The procedural boot extends from z=-.075 to +.245. A .070 m
            // capsule around its inner heel/toe centres covers that outline.
            let heel = anklePosition + ankleRotation.act([0, -0.032, -0.005])
            let toeCentre = anklePosition + ankleRotation.act([0, -0.050, usesExplicitBoot ? 0.130 : 0.175])
            let toeTip = anklePosition + ankleRotation.act([0, -0.050, usesExplicitBoot ? 0.200 : 0.245])
            return (
                Capsule(start: kneePosition, end: anklePosition, radius: 0.075),
                Capsule(start: heel, end: toeCentre, radius: 0.070),
                toeTip, ankleRotation.act([0, 0, 1])
            )
        }
        let left = leg(x: -0.137, hip: pose.leftHipOrientation,
                       knee: pose.leftKneeOrientation, ankle: pose.leftAnkleOrientation)
        let right = leg(x: 0.137, hip: pose.rightHipOrientation,
                        knee: pose.rightKneeOrientation, ankle: pose.rightAnkleOrientation)
        origin = playerPose.position
        leftShin = left.0
        leftBoot = left.1
        leftToe = left.2
        leftForward = left.3
        rightShin = right.0
        rightBoot = right.1
        rightToe = right.2
        rightForward = right.3
    }

    func strikePoint(leg: ReplayAthleteLeg, ballRadius: Float) -> PitchPoint {
        let toe = leg == .left ? leftToe : rightToe
        let forward = leg == .left ? leftForward : rightForward
        let horizontal = SIMD2<Float>(forward.x, forward.z)
        let direction = simd_length_squared(horizontal) > 0.001
            ? simd_normalize(horizontal) : SIMD2<Float>(0, 1)
        var point = SIMD2<Float>(toe.x, toe.z) + direction * (ballRadius + 0.012)
        let centre = SIMD2<Float>(origin.x, origin.z)
        let offset = point - centre
        // A retracted strike boot can be close to the body's coarse envelope.
        // Keep a reachable toe-side contact outside that core too.
        if simd_length_squared(offset) < 0.435 * 0.435 {
            let normal = simd_length_squared(offset) > 0.001 ? simd_normalize(offset) : direction
            point = centre + normal * 0.435
        }
        return PitchPoint(x: point.x, z: point.y)
    }
}
