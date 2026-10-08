import Foundation
import simd

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
    static let keyframeTimeTolerance: TimeInterval = 0.000_001
    var hasKeyframes: Bool { !(keyframes?.isEmpty ?? true) }
    var hasAnimatedGeometry: Bool { hasKeyframes || followsPlayerTracks }

    /// At capacity, editing an existing timestamp replaces its pose; editing
    /// between timestamps would need an additional key. Match recordingPose's
    /// strict tolerance, without silently dropping any saved position.
    func canRecordPose(at time: TimeInterval) -> Bool {
        guard time.isFinite, time >= 0 else { return false }
        return (keyframes?.count ?? 0) < Self.maximumKeyframes || keyframeIndex(at: time) != nil
    }

    func keyframeCapacityBlockReason(at time: TimeInterval) -> String? {
        guard time.isFinite, time >= 0, !canRecordPose(at: time) else { return nil }
        return "\(Self.maximumKeyframes) positions saved. Select a key or delete one."
    }

    private func keyframeIndex(at time: TimeInterval) -> Int? {
        keyframes?.firstIndex { abs($0.time - time) < Self.keyframeTimeTolerance }
    }

    func canShiftKeyframes(by delta: TimeInterval, duration: TimeInterval) -> Bool {
        guard delta.isFinite, duration.isFinite, duration >= 0 else { return false }
        return (keyframes ?? []).allSatisfy {
            $0.time.isFinite && (0...duration).contains($0.time + delta)
        }
    }

    func canRetimeKeyframe(from time: TimeInterval, to destination: TimeInterval,
                          duration: TimeInterval) -> Bool {
        guard time.isFinite, destination.isFinite, duration.isFinite, duration >= 0,
              (0...duration).contains(destination),
              abs(destination - time) >= Self.keyframeTimeTolerance,
              let frames = keyframes,
              let index = frames.firstIndex(where: { abs($0.time - time) < Self.keyframeTimeTolerance })
        else { return false }
        // Never silently overwrite another saved pose, including nearly-equal timestamps.
        return !frames.enumerated().contains {
            $0.offset != index && abs($0.element.time - destination) < Self.keyframeTimeTolerance
        }
    }

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
            if x.controlOffset != nil || y.controlOffset != nil {
                if t == 0 { resolvedCurve = x }
                else if t == 1 { resolvedCurve = y }
                else {
                    func control(_ frame: CoachMarkKeyframe, _ curve: CoachMarkCurve) -> SIMD3<Float> {
                        curve.controlPoint(for: CoachMark(id: id, kind: .arc,
                            start: frame.start, end: frame.end,
                            startElevation: frame.startElevation, endElevation: frame.endElevation,
                            curve: curve, label: label, revealTime: revealTime))
                    }
                    let c0 = control(a, x), c1 = control(b, y)
                    let sampledMark = CoachMark(id: id, kind: .arc,
                        start: point(a.start, b.start), end: point(a.end, b.end),
                        startElevation: mix(a.startElevation, b.startElevation),
                        endElevation: mix(a.endElevation, b.endElevation), label: label, revealTime: revealTime)
                    resolvedCurve = x.settingControlPoint(c0 + (c1 - c0) * t, for: sampledMark)
                }
            } else if x.bendBearingDegrees == nil && y.bendBearingDegrees == nil {
                // Saved legacy intervals keep the original arithmetic/order,
                // including their current-chord basis and roll tie behavior.
                resolvedCurve = CoachMarkCurve(bend: mix(x.bend, y.bend), lift: mix(x.lift, y.lift),
                    rollDegrees: ReplayGeometry.interpolateAngle(from: x.rollDegrees, to: y.rollDegrees, fraction: t)
                        .truncatingRemainder(dividingBy: 360))
                if let angle = resolvedCurve?.rollDegrees, angle > 180 { resolvedCurve?.rollDegrees -= 360 }
                if let angle = resolvedCurve?.rollDegrees, angle < -180 { resolvedCurve?.rollDegrees += 360 }
            } else if t == 0 {
                resolvedCurve = x
            } else if t == 1 {
                resolvedCurve = y
            } else {
                // Each legacy endpoint contributes its own authored frame;
                // using the sampled chord here would reintroduce the flip.
                let startCurve = x.stabilized(start: a.start, end: a.end)
                let endCurve = y.stabilized(start: b.start, end: b.end)
                guard let startBearing = startCurve.bendBearingDegrees,
                      let endBearing = endCurve.bendBearingDegrees else { return self }
                var delta = (endBearing - startBearing).truncatingRemainder(dividingBy: 360)
                if delta > 180 { delta -= 360 }
                if delta <= -180 { delta += 360 } // Exact antipodes always take +180.
                var bearing = (startBearing + delta * t).truncatingRemainder(dividingBy: 360)
                if bearing > 180 { bearing -= 360 }
                if bearing < -180 { bearing += 360 }
                resolvedCurve = CoachMarkCurve(bend: mix(startCurve.bend, endCurve.bend),
                    lift: mix(startCurve.lift, endCurve.lift),
                    rollDegrees: ReplayGeometry.interpolateAngle(from: x.rollDegrees, to: y.rollDegrees, fraction: t)
                        .truncatingRemainder(dividingBy: 360), bendBearingDegrees: bearing)
                if let angle = resolvedCurve?.rollDegrees, angle > 180 { resolvedCurve?.rollDegrees -= 360 }
                if let angle = resolvedCurve?.rollDegrees, angle < -180 { resolvedCurve?.rollDegrees += 360 }
            }
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
        if let i = keyframeIndex(at: time) {
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
        return hasSafeArcKeyframeIntervals
    }

    /// A linear endpoint interpolation can collapse between otherwise valid
    /// keys. Check the exact quadratic minimum of |D0 + t(D1-D0)|², not a
    /// finite sampling grid. Legacy-only intervals retain their saved behavior.
    var hasSafeArcKeyframeIntervals: Bool {
        guard kind == .arc, let frames = keyframes, !frames.isEmpty else { return true }
        let minimum = Double(CoachMarkGeometryPolicy.minimumDirectionalLength)
        func chord(_ frame: CoachMarkKeyframe) -> SIMD3<Double> {
            .init(Double(frame.end.x) - Double(frame.start.x),
                  Double(frame.endElevation) - Double(frame.startElevation),
                  Double(frame.end.z) - Double(frame.start.z))
        }
        func isSafe(_ a: CoachMarkKeyframe, _ b: CoachMarkKeyframe) -> Bool {
            let d = chord(a), v = chord(b) - d
            let speedSquared = simd_length_squared(v)
            guard simd_length_squared(d).isFinite, speedSquared.isFinite else { return false }
            let t = speedSquared > 0 ? min(max(-simd_dot(d, v) / speedSquared, 0), 1) : 0
            return simd_length_squared(d + t * v) >= minimum * minimum
        }
        // A lone framed key holds forever and still needs a usable roll axis.
        for frame in frames where frame.curve?.hasFixedControlFrame == true {
            guard isSafe(frame, frame) else { return false }
        }
        for (a, b) in zip(frames, frames.dropFirst())
            where a.curve?.hasFixedControlFrame == true || b.curve?.hasFixedControlFrame == true {
            guard isSafe(a, b) else { return false }
        }
        return true
    }
}
