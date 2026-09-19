import Foundation

/// Native-only cut admission, sampled from absolute replay time. A rapidly
/// falling cut weight can expose a very different source knee in one frame
/// even when both endpoint poses are smooth. This bounded three-tap window
/// eases that crossfade; it never clips joint angles or changes the gait clock.
@MainActor
enum ReplaySkinnedAthleteCutWeight {
    static let halfWindow: TimeInterval = 0.10

    struct Sample {
        let influence: Float
        let rawInfluence: Float
        let admission: Float
        let neighbourSamples: Int
    }

    #if DEBUG
    private(set) static var neighbourLocomotionSampleCount = 0
    static func resetSampleCountForTesting() { neighbourLocomotionSampleCount = 0 }
    #endif

    static func sample(source: String, track: PlayerTrack, at time: TimeInterval,
                       locomotion: PlayerLocomotionSample, interaction: ReplayAthleteInteractionCue?,
                       enabled: Bool) -> Sample {
        let raw = ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil)
        guard enabled, source == ReplaySkinnedAthleteCutPhase.sourceCommit, !track.isGoalkeeper,
              time.isFinite, locomotion.speedMetresPerSecond.isFinite else {
            return .init(influence: raw, rawInfluence: raw, admission: 0, neighbourSamples: 0)
        }
        let protection = ReplayAthleteMovementIntent.contactProtection(for: interaction, track: track, at: time)
        let admission = smooth((locomotion.speedMetresPerSecond - 2.4) / 1.2) * (1 - protection)
        guard admission > 0 else {
            return .init(influence: raw, rawInfluence: raw, admission: 0, neighbourSamples: 0)
        }
        // Sample fast raw-zero frames too. Gating on raw>0 would abruptly admit
        // a neighbour's weight at the first positive cut frame and recreate a pop.
        let before = ReplaySkinnedAthleteFootballPose.influence(
            locomotion: track.locomotion(at: time - halfWindow), ballAction: nil)
        let after = ReplaySkinnedAthleteFootballPose.influence(
            locomotion: track.locomotion(at: time + halfWindow), ballAction: nil)
        #if DEBUG
        neighbourLocomotionSampleCount += 2
        #endif
        let filtered = (before + 2 * raw + after) * 0.25
        return .init(influence: raw + (filtered - raw) * admission,
                     rawInfluence: raw, admission: admission, neighbourSamples: 2)
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
