import Foundation
import simd

/// Small presentation-only upper-body intent. This is procedural variation,
/// not recovered match body motion. No root, leg, scale or clock is changed.
enum ReplayAthleteOffBallPose {
    struct Sample: Equatable, Sendable {
        let chestYaw: Float
        let chestPitch: Float
        let chestRoll: Float

        static let zero = Sample(chestYaw: 0, chestPitch: 0, chestRoll: 0)
        var isIdentity: Bool { self == .zero }
        var chestRotation: simd_quatf {
            simd_quatf(angle: chestPitch, axis: [1, 0, 0])
                * simd_quatf(angle: chestRoll, axis: [0, 0, 1])
                * simd_quatf(angle: chestYaw, axis: [0, 1, 0])
        }

        /// Share the existing gaze with the chest, rather than adding another
        /// turn on top of the neck/head. The final anatomical clamp still wins.
        func adjusting(_ look: ReplayAthleteLookPose) -> ReplayAthleteLookPose {
            guard !isIdentity else { return look }
            return .init(neckYawRadians: look.neckYawRadians - chestYaw * 0.42,
                         headYawRadians: look.headYawRadians - chestYaw * 0.58,
                         neckPitchRadians: look.neckPitchRadians - chestPitch * 0.34,
                         headPitchRadians: look.headPitchRadians - chestPitch * 0.66)
        }
    }

    static func sample(playerID: String, at time: TimeInterval,
                       locomotion: PlayerLocomotionSample, look: ReplayAthleteLookPose,
                       actionInfluence: Float, sourceFraction: Float = 0,
                       enabled: Bool = true) -> Sample {
        guard enabled, time.isFinite, locomotion.speedMetresPerSecond.isFinite,
              locomotion.accelerationMetresPerSecondSquared.isFinite,
              look.combinedYawRadians.isFinite, actionInfluence.isFinite,
              sourceFraction.isFinite else { return .zero }
        // Keep the admitted contact and its full-support core exactly intact.
        // The quintic edge avoids a new animation cut during preparation/release.
        let availability = 1 - smooth((actionInfluence - 0.05) / 0.65)
        guard availability > 0 else { return .zero }
        let speed = max(locomotion.speedMetresPerSecond, 0)
        let settled = 1 - smooth((speed - 0.35) / 2.45)
        let effort = locomotion.effort
        let phase = Float(playerID.utf8.reduce(UInt32(2_166_136_261)) {
            ($0 ^ UInt32($1)) &* 16_777_619
        } % 65_521) / 65_521 * (2 * .pi)
        let seconds = Float(min(max(time, -1_000_000), 1_000_000))
        let quietYaw = sin(seconds * 0.71 + phase) * 0.012 * settled
        let breath = sin(seconds * 1.19 + phase * 1.73) * 0.006 * settled
        let balance = sin(seconds * 0.53 + phase * 2.31) * 0.008 * settled
        let share = look.combinedYawRadians * (0.17 - 0.08 * effort)
        // The far/procedural pose already has acceleration lean. Only fill the
        // fraction still owned by the native source run; never replace its legs.
        let acceleration = locomotion.accelerationResponse
        let source = min(max(sourceFraction, 0), 1)
        let sourcePitch = (-max(acceleration, 0) * 0.09 + max(-acceleration, 0) * 0.10) * source
        return .init(chestYaw: min(max(share + quietYaw, -0.16), 0.16) * availability,
                     chestPitch: (breath + sourcePitch) * availability,
                     chestRoll: balance * availability)
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
