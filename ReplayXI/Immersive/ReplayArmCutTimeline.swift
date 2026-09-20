import Foundation

/// Experimental arm-only cut admission. This reuses the tested absolute-time
/// envelope kernel, not the slow-run source policy or animation clock.
/// Knot/midpoint caps are sampled, not a proof of the policy between samples.
@MainActor
struct ReplayArmCutTimeline: Sendable {
    struct Admission: Sendable {
        let envelopeWeight: Float
        fileprivate let track: PlayerTrack
        fileprivate let sourceCommit: String
        fileprivate let time: TimeInterval
        fileprivate let locomotion: PlayerLocomotionSample

        func matchingWeight(sourceCommit: String, track: PlayerTrack, at time: TimeInterval,
                            locomotion: PlayerLocomotionSample) -> Float? {
            guard self.time == time, self.sourceCommit == sourceCommit,
                  self.locomotion == locomotion, self.track == track else { return nil }
            return envelopeWeight
        }
    }

    private let track: PlayerTrack
    private let sourceCommit: String
    private let envelope: ReplaySlowRunTimeline

    #if DEBUG
    struct Metrics: Equatable {
        let knotCount: Int
        let rawSampleCount: Int
        let evaluatedRawSampleCount: Int
        let skippedMidpointCount: Int
        /// Float table only; excludes retained track/cue input and Array overhead.
        let storageBytes: Int
    }
    private let evaluatedRawSampleCount: Int
    private let logicalRawSampleCount: Int
    private(set) static var coldPolicyEvaluationCountForTesting = 0
    private(set) static var warmAdmissionCountForTesting = 0
    static func resetCountersForTesting() {
        coldPolicyEvaluationCountForTesting = 0
        warmAdmissionCountForTesting = 0
    }
    var knotsForTesting: [Float] { envelope.knotsForTesting }
    var metricsForTesting: Metrics {
        .init(knotCount: envelope.metricsForTesting.knotCount,
              rawSampleCount: logicalRawSampleCount, evaluatedRawSampleCount: evaluatedRawSampleCount,
              skippedMidpointCount: logicalRawSampleCount - evaluatedRawSampleCount,
              storageBytes: envelope.metricsForTesting.storageBytes)
    }
    #endif

    init?(track: PlayerTrack, interactions: [ReplayAthleteInteractionCue], duration: TimeInterval,
          startTime: TimeInterval = 0,
          sourceCommit requestedSourceCommit: String? = nil) {
        let sourceCommit = requestedSourceCommit ?? ReplaySkinnedAthleteCutPhase.sourceCommit
        let endTime = startTime + duration
        guard sourceCommit == ReplaySkinnedAthleteCutPhase.sourceCommit, !track.isGoalkeeper,
              !track.keyframes.isEmpty, track.keyframes.count <= ReplayNativeBallPhysics.maximumSourceFrames,
              interactions.count <= ReplayNativeBallPhysics.maximumSourceFrames,
              interactions.allSatisfy({ $0.playerID == track.id && $0.startTime.isFinite
                  && $0.contactTime.isFinite && $0.endTime.isFinite
                  && $0.startTime <= $0.contactTime && $0.contactTime <= $0.endTime }),
              duration.isFinite, duration > 0, duration <= ReplaySlowRunTimeline.maximumDuration,
              startTime.isFinite, startTime >= 0, endTime.isFinite, endTime > startTime,
              endTime <= ReplaySlowRunTimeline.maximumEndTime else { return nil }
        var cells = max(1, Int(ceil(duration * ReplaySlowRunTimeline.sampleRate)))
        if cells > 1, startTime + Double(cells - 1) / ReplaySlowRunTimeline.sampleRate >= endTime { cells -= 1 }
        func time(_ index: Int) -> TimeInterval {
            min(startTime + Double(index) / ReplaySlowRunTimeline.sampleRate, endTime)
        }
        var evaluations = 0
        func cap(at time: TimeInterval) -> Float {
            evaluations += 1
            #if DEBUG
            Self.coldPolicyEvaluationCountForTesting += 1
            #endif
            // Same nearest-prepared-cue rule as the native recording cache.
            var cue: ReplayAthleteInteractionCue?
            for candidate in interactions where ReplayAthleteMovementIntent.includesPreparation(candidate, at: time) {
                if cue == nil || abs(candidate.contactTime - time) < abs(cue!.contactTime - time) { cue = candidate }
            }
            return ReplaySkinnedAthleteCutWeight.sample(source: sourceCommit, track: track, at: time,
                locomotion: track.locomotion(at: time), interaction: cue, enabled: true).influence
        }
        var caps: [Float] = []
        caps.reserveCapacity(cells + 1)
        for index in 0...cells { caps.append(cap(at: time(index))) }
        var zeroCells: [Bool] = []
        zeroCells.reserveCapacity(cells)
        for index in 0..<cells {
            if caps[index] == 0 || caps[index + 1] == 0 {
                zeroCells.append(true)
            } else {
                zeroCells.append(cap(at: (time(index) + time(index + 1)) * 0.5) == 0)
            }
        }
        guard let envelope = ReplaySlowRunTimeline(duration: duration, knotCaps: caps,
                                                   zeroCells: zeroCells, startTime: startTime) else { return nil }
        self.track = track
        self.sourceCommit = sourceCommit
        self.envelope = envelope
        #if DEBUG
        self.evaluatedRawSampleCount = evaluations
        self.logicalRawSampleCount = cells * 2 + 1
        #endif
    }

    /// The caller supplies the authoritative track locomotion it already uses
    /// for this frame. The resulting value is bound to it and the full track;
    /// reuse with a different override, timestamp or route fails closed.
    func admission(at time: TimeInterval, locomotion: PlayerLocomotionSample) -> Admission? {
        guard time.isFinite, time >= envelope.startTime, time <= envelope.endTime else { return nil }
        #if DEBUG
        Self.warmAdmissionCountForTesting += 1
        #endif
        return Admission(envelopeWeight: envelope.weight(at: time), track: track,
                         sourceCommit: sourceCommit, time: time, locomotion: locomotion)
    }
}
