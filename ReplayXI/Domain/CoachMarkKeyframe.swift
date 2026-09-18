import Foundation

struct CoachMarkKeyframe: Codable, Hashable, Sendable {
    var time: TimeInterval
    let start: PitchPoint
    let end: PitchPoint
    let startElevation: Float
    let endElevation: Float
    let curve: CoachMarkCurve?

    init(time: TimeInterval, mark: CoachMark) {
        self.time = time
        start = mark.start; end = mark.end
        startElevation = mark.resolvedStartElevation
        endElevation = mark.resolvedEndElevation
        curve = mark.kind == .arc ? mark.resolvedCurve : nil
    }
}

extension CoachMark {
    static let maximumKeyframes = 64
    var hasKeyframes: Bool { !(keyframes?.isEmpty ?? true) }
    var hasAnimatedGeometry: Bool { hasKeyframes || followsPlayerTracks }

    /// Linear, absolute-time sampling: seeking and reverse playback are exact.
    /// End poses hold outside their keyed interval; visibility is independent.
    func sampled(at time: TimeInterval) -> CoachMark {
        guard time.isFinite, let frames = keyframes, let first = frames.first,
              let last = frames.last else { return self }
        var a = first, b = first
        if time >= last.time { a = last; b = last }
        else if time > first.time {
            var low = 0, high = frames.count - 1
            while high - low > 1 {
                let mid = (low + high) / 2
                if frames[mid].time <= time { low = mid } else { high = mid }
            }
            a = frames[low]; b = frames[high]
        }
        let t: Float = b.time > a.time ? Float((time - a.time) / (b.time - a.time)) : 0
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }
        func point(_ x: PitchPoint, _ y: PitchPoint) -> PitchPoint {
            .init(x: mix(x.x, y.x), z: mix(x.z, y.z))
        }
        var resolvedCurve: CoachMarkCurve?
        if let x = a.curve, let y = b.curve {
            resolvedCurve = CoachMarkCurve(bend: mix(x.bend, y.bend), lift: mix(x.lift, y.lift),
                rollDegrees: ReplayGeometry.interpolateAngle(from: x.rollDegrees, to: y.rollDegrees, fraction: t)
                    .truncatingRemainder(dividingBy: 360))
            if let angle = resolvedCurve?.rollDegrees, angle > 180 { resolvedCurve?.rollDegrees -= 360 }
            if let angle = resolvedCurve?.rollDegrees, angle < -180 { resolvedCurve?.rollDegrees += 360 }
        }
        return CoachMark(id: id, kind: kind, start: point(a.start, b.start), end: point(a.end, b.end),
            startElevation: mix(a.startElevation, b.startElevation), endElevation: mix(a.endElevation, b.endElevation),
            curve: resolvedCurve, label: label, revealTime: revealTime, hideTime: hideTime,
            author: author, playerID: playerID, startTrackAnchor: startTrackAnchor,
            endTrackAnchor: endTrackAnchor, keyframes: frames)
    }

    func recordingPose(at time: TimeInterval) -> CoachMark {
        var result = self
        var frames = keyframes ?? []
        if let i = frames.firstIndex(where: { abs($0.time - time) < 0.000_001 }) {
            frames[i] = CoachMarkKeyframe(time: frames[i].time, mark: self)
        } else { frames.append(CoachMarkKeyframe(time: time, mark: self)) }
        result.keyframes = frames.sorted { $0.time < $1.time }
        return result
    }

    func hasValidKeyframes(duration: TimeInterval) -> Bool {
        guard let frames = keyframes else { return true }
        guard !frames.isEmpty, frames.count <= Self.maximumKeyframes, kind != .playerLabel,
              !followsPlayerTracks else { return false }
        var previous: TimeInterval = -1
        for frame in frames {
            guard frame.time.isFinite, frame.time >= 0, frame.time <= duration, frame.time > previous,
                  frame.start.x.isFinite, frame.start.z.isFinite, frame.end.x.isFinite, frame.end.z.isFinite,
                  abs(frame.start.x) <= 34, abs(frame.end.x) <= 34,
                  abs(frame.start.z) <= 52.5, abs(frame.end.z) <= 52.5,
                  CoachMarkGeometryPolicy.accepts(elevation: frame.startElevation),
                  CoachMarkGeometryPolicy.accepts(elevation: frame.endElevation),
                  kind != .space || abs(frame.startElevation - frame.endElevation) <= 0.001,
                  kind == .arc ? (frame.curve?.isValid ?? false) : frame.curve == nil else { return false }
            previous = frame.time
        }
        return true
    }
}
