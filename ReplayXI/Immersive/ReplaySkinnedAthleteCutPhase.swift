import Foundation
import simd

/// Align this asset's running recovery with the native authored cut target.
/// Source toe-off occurs near7π/6 (opposite boot nearπ/6), whereas the authored
/// negative-X boot ends support atπ/2. These are animation-event estimates from
/// the native source sole curve, not measured force/contact data from a match.
/// The source clip and the track's integrated gait clock remain untouched.
@MainActor
enum ReplaySkinnedAthleteCutPhase {
    static let sourceCommit = "0943055db6ec570bcef9f2c8b41c9e5467c808f9"
    static let offset: Float = 2 * .pi / 3

    static func weight(source: String, track: PlayerTrack, at time: TimeInterval,
                       locomotion: PlayerLocomotionSample, interaction: ReplayAthleteInteractionCue?,
                       retargetInfluence: Float, enabled: Bool) -> Float {
        guard enabled, source == sourceCommit, !track.isGoalkeeper,
              time.isFinite, locomotion.speedMetresPerSecond.isFinite,
              locomotion.turnRateDegreesPerSecond.isFinite,
              retargetInfluence.isFinite, retargetInfluence > 0 else { return 0 }
        let cut = ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil)
        let cutShare = min(max(cut / retargetInfluence, 0), 1)
        let protection = ReplayAthleteMovementIntent.contactProtection(for: interaction, track: track, at: time)
        // Fade complete poses, not their clock phase: interpolating phase can
        // reverse a boot's gait while sprint effort is rising or falling.
        return smooth((locomotion.speedMetresPerSecond - 3) / 1.8) * cutShare * (1 - protection)
    }

    static func authoredPose(phase: Float, weight: Float,
                             sample: (Float) -> ReplayAthleteLocomotionPose) -> ReplayAthleteLocomotionPose {
        let weight = min(max(weight.isFinite ? weight : 0, 0), 1)
        guard phase.isFinite, weight > 0 else { return sample(phase) }
        if weight >= 1 { return sample(phase - offset) }
        return blend(sample(phase), sample(phase - offset), weight: weight)
    }

    /// One shared blend for legs, opposite arms, pelvis and chest. Retiming only
    /// boots would leave the source and authored arm swing on different beats.
    static func blend(_ a: ReplayAthleteLocomotionPose, _ b: ReplayAthleteLocomotionPose,
                      weight rawWeight: Float) -> ReplayAthleteLocomotionPose {
        let weight = min(max(rawWeight.isFinite ? rawWeight : 0, 0), 1)
        if weight <= 0 { return a }
        if weight >= 1 { return b }
        func q(_ a: simd_quatf, _ b: simd_quatf) -> simd_quatf {
            ReplayAthleteInteractionPose.blend(a, b, weight)
        }
        func p(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> { a + (b - a) * weight }
        return ReplayAthleteLocomotionPose(
            bodyPosition: p(a.bodyPosition, b.bodyPosition), bodyOrientation: q(a.bodyOrientation, b.bodyOrientation),
            hipsPosition: p(a.hipsPosition, b.hipsPosition), hipsOrientation: q(a.hipsOrientation, b.hipsOrientation),
            spineOrientation: q(a.spineOrientation, b.spineOrientation), neckOrientation: q(a.neckOrientation, b.neckOrientation),
            headOrientation: q(a.headOrientation, b.headOrientation),
            leftHipOrientation: q(a.leftHipOrientation, b.leftHipOrientation),
            rightHipOrientation: q(a.rightHipOrientation, b.rightHipOrientation),
            leftKneeOrientation: q(a.leftKneeOrientation, b.leftKneeOrientation),
            rightKneeOrientation: q(a.rightKneeOrientation, b.rightKneeOrientation),
            leftAnkleOrientation: q(a.leftAnkleOrientation, b.leftAnkleOrientation),
            rightAnkleOrientation: q(a.rightAnkleOrientation, b.rightAnkleOrientation),
            leftShoulderOrientation: q(a.leftShoulderOrientation, b.leftShoulderOrientation),
            rightShoulderOrientation: q(a.rightShoulderOrientation, b.rightShoulderOrientation),
            leftElbowOrientation: q(a.leftElbowOrientation, b.leftElbowOrientation),
            rightElbowOrientation: q(a.rightElbowOrientation, b.rightElbowOrientation),
            leftWristOrientation: q(a.leftWristOrientation, b.leftWristOrientation),
            rightWristOrientation: q(a.rightWristOrientation, b.rightWristOrientation))
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
