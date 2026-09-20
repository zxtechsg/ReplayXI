import Foundation

/// Absolute-time, rate-bounded admission for an already eligible track.
/// This lower envelope is conservative at its sampled knots/zero cells, not
/// a proof of the raw policy between samples. Whole-track contact/impact
/// exclusion remains the caller's responsibility; no playback history is kept.
@MainActor
struct ReplaySlowRunTimeline: Sendable {
    static let sampleRate: Double = 120
    static let maximumSlopePerSecond: Double = 4
    /// Match the native replay's bound: at most 10,801 stored Float weights.
    static let maximumDuration = ReplayNativeBallPhysics.maximumDuration
    static let maximumEndTime: TimeInterval = 1_000_000

    let duration: TimeInterval
    let startTime: TimeInterval
    var endTime: TimeInterval { startTime + duration }
    private let weights: [Float]
    #if DEBUG
    private let rawSampleCount: Int
    struct Metrics: Equatable {
        let knotCount: Int
        let rawSampleCount: Int
        /// Weight payload only, not Array/object/allocator overhead.
        let storageBytes: Int
    }
    var metricsForTesting: Metrics {
        .init(knotCount: weights.count, rawSampleCount: rawSampleCount,
              storageBytes: weights.count * MemoryLayout<Float>.stride)
    }
    var knotsForTesting: [Float] { weights }
    #endif

    init?(track: PlayerTrack, duration: TimeInterval, startTime: TimeInterval = 0) {
        guard !track.isGoalkeeper, let cells = Self.cellCount(duration: duration, startTime: startTime) else { return nil }
        var caps = [Float](); caps.reserveCapacity(cells + 1)
        for index in 0...cells {
            caps.append(Self.rawWeight(track: track, at: Self.time(index, duration: duration, startTime: startTime)))
        }
        var zeroCells = [Bool](); zeroCells.reserveCapacity(cells)
        for index in 0..<cells {
            let midpoint = (Self.time(index, duration: duration, startTime: startTime)
                + Self.time(index + 1, duration: duration, startTime: startTime)) * 0.5
            let middle = Self.rawWeight(track: track, at: midpoint)
            zeroCells.append(caps[index] == 0 || middle == 0 || caps[index + 1] == 0)
        }
        self.init(duration: duration, knotCaps: caps, zeroCells: zeroCells,
                  startTime: startTime, rawSampleCount: cells * 2 + 1)
    }

    /// Pure envelope construction. Invalid caps fail closed at their knot and
    /// both touching cells. Cell flags protect the complete linear interval.
    init?(duration: TimeInterval, knotCaps: [Float], zeroCells: [Bool], startTime: TimeInterval = 0) {
        self.init(duration: duration, knotCaps: knotCaps, zeroCells: zeroCells,
                  startTime: startTime, rawSampleCount: 0)
    }

    private init?(duration: TimeInterval, knotCaps: [Float], zeroCells: [Bool],
                  startTime: TimeInterval, rawSampleCount: Int) {
        guard let cells = Self.cellCount(duration: duration, startTime: startTime),
              knotCaps.count == cells + 1, zeroCells.count == cells else { return nil }
        var bounded = knotCaps.map { $0.isFinite && (0...1).contains($0) ? $0 : 0 }
        // Read original caps when identifying zeros: newly zeroed neighbours
        // must not cascade the exclusion across otherwise valid cells.
        for index in 0..<cells {
            let left = knotCaps[index], right = knotCaps[index + 1]
            if zeroCells[index] || !left.isFinite || !right.isFinite
                || left <= 0 || right <= 0 || left > 1 || right > 1 {
                bounded[index] = 0; bounded[index + 1] = 0
            }
        }
        for index in 1...cells {
            let step = Self.maximumSlopePerSecond
                * (Self.time(index, duration: duration, startTime: startTime)
                    - Self.time(index - 1, duration: duration, startTime: startTime))
            bounded[index] = min(bounded[index], Self.roundedDown(Double(bounded[index - 1]) + step))
        }
        for index in stride(from: cells - 1, through: 0, by: -1) {
            let step = Self.maximumSlopePerSecond
                * (Self.time(index + 1, duration: duration, startTime: startTime)
                    - Self.time(index, duration: duration, startTime: startTime))
            bounded[index] = min(bounded[index], Self.roundedDown(Double(bounded[index + 1]) + step))
        }
        self.duration = duration
        self.startTime = startTime
        self.weights = bounded
        #if DEBUG
        self.rawSampleCount = rawSampleCount
        #endif
    }

    func weight(at time: TimeInterval) -> Float {
        guard time.isFinite, time >= startTime, time <= endTime else { return 0 }
        guard time < endTime else { return weights[weights.count - 1] }
        var index = min(Int((time - startTime) * Self.sampleRate), weights.count - 2)
        // Subtraction at a large valid offset can place an exact knot one
        // cell either side of its integer estimate. Correct without a search.
        if index > 0, time < Self.time(index, duration: duration, startTime: startTime) { index -= 1 }
        if index < weights.count - 2,
           time >= Self.time(index + 1, duration: duration, startTime: startTime) { index += 1 }
        let start = Self.time(index, duration: duration, startTime: startTime)
        let end = Self.time(index + 1, duration: duration, startTime: startTime)
        let fraction = min(max((time - start) / (end - start), 0), 1)
        return Float(Double(weights[index]) + (Double(weights[index + 1]) - Double(weights[index])) * fraction)
    }

    private static func cellCount(duration: TimeInterval, startTime: TimeInterval) -> Int? {
        let end = startTime + duration
        guard duration.isFinite, duration > 0, duration <= maximumDuration,
              startTime.isFinite, startTime >= 0, end.isFinite,
              end > startTime, end <= maximumEndTime else { return nil }
        var cells = max(1, Int(ceil(duration * sampleRate)))
        // A tiny fractional tail may round onto the previous absolute knot.
        if cells > 1, startTime + Double(cells - 1) / sampleRate >= end { cells -= 1 }
        return cells
    }

    private static func time(_ index: Int, duration: TimeInterval, startTime: TimeInterval) -> TimeInterval {
        min(startTime + Double(index) / sampleRate, startTime + duration)
    }

    private static func roundedDown(_ value: Double) -> Float {
        let result = Float(value)
        return Double(result) > value ? result.nextDown : result
    }

    private static func rawWeight(track: PlayerTrack, at time: TimeInterval) -> Float {
        let locomotion = track.locomotion(at: time)
        let speedTurnWeight = ReplaySlowRunAdmission.weight(locomotion: locomotion)
        guard speedTurnWeight > 0 else { return 0 }
        guard let movement = ReplayAthleteMovementIntent.sample(track: track, at: time,
            presentationPose: track.presentationPose(at: time), lookTarget: nil) else { return 0 }
        return speedTurnWeight
            * ReplaySlowRunAdmission.directionWeight(localTravelYaw: movement.localTravelYaw)
    }
}
