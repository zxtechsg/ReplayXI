import Foundation
import simd

/// Seek-stable visual rolling from the authored horizontal ball path.
/// This is not measured spin or a physics reconstruction. Lofted segments use
/// the same projected-distance convention; height/position remain untouched.
/// A match root prepares this immutable, bounded table once, then queries it
/// without allocation or mutable frame history.
final class ReplayBallRollingMotion: Sendable {
    static let maximumKeyframes = 65_536
    static let nominalRadius: Float = 0.11
    static let identity = simd_quatf(real: 1, imag: .zero)

    private struct Segment: Sendable {
        let startTime: Double
        let endTime: Double
        let axis: SIMD3<Float>
        let angle: Double
        let startOrientation: simd_quatf
    }

    private let segments: [Segment]
    private let finalOrientation: simd_quatf
    var segmentCount: Int { segments.count }
    var isValid: Bool { !segments.isEmpty }

    init(track: BallTrack, radius: Float = ReplayBallRollingMotion.nominalRadius) {
        let frames = track.keyframes
        guard frames.count >= 2, frames.count <= Self.maximumKeyframes,
              radius.isFinite, radius >= 0.001, radius <= 10 else {
            segments = []
            finalOrientation = Self.identity
            return
        }

        // Reject the complete spin estimate rather than publish a partially
        // trusted prefix. Bounds are generous for pitch-local replay data and
        // prevent pathological counts, time spans and scalar magnitudes.
        var previousTime = -Double.infinity
        for frame in frames {
            guard frame.time.isFinite, abs(frame.time) <= 1_000_000,
                  frame.time > previousTime,
                  frame.position.x.isFinite, abs(frame.position.x) <= 10_000,
                  frame.position.z.isFinite, abs(frame.position.z) <= 10_000,
                  frame.height.isFinite, abs(frame.height) <= 10_000 else {
                segments = []
                finalOrientation = Self.identity
                return
            }
            previousTime = frame.time
        }

        var prepared: [Segment] = []
        prepared.reserveCapacity(frames.count - 1)
        var orientation = Self.identity
        for index in 1..<frames.count {
            let start = frames[index - 1]
            let end = frames[index]
            let dx = Double(end.position.x) - Double(start.position.x)
            let dz = Double(end.position.z) - Double(start.position.z)
            let distance = hypot(dx, dz)
            let axis: SIMD3<Float> = distance > 0
                ? [Float(dz / distance), 0, Float(-dx / distance)]
                : [1, 0, 0]
            let angle = distance / Double(radius)
            prepared.append(Segment(startTime: start.time, endTime: end.time,
                                    axis: axis, angle: angle, startOrientation: orientation))
            if distance > 0 {
                orientation = simd_normalize(Self.rotation(angle: angle, axis: axis) * orientation)
            }
        }
        segments = prepared
        finalOrientation = orientation
    }

    func orientation(at time: TimeInterval) -> simd_quatf {
        guard time.isFinite, let first = segments.first, let last = segments.last else {
            return Self.identity
        }
        if time <= first.startTime { return first.startOrientation }
        if time >= last.endTime { return finalOrientation }

        // The first segment whose end lies after this time. Exact knots reuse
        // the next prefix, so a direction change cannot restart the ball spin.
        var lower = 0
        var upper = segments.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if segments[middle].endTime <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let segment = segments[lower]
        guard segment.angle > 0, time > segment.startTime else {
            return segment.startOrientation
        }
        let fraction = min(max((time - segment.startTime) / (segment.endTime - segment.startTime), 0), 1)
        return simd_normalize(Self.rotation(angle: segment.angle * fraction, axis: segment.axis)
                              * segment.startOrientation)
    }

    private static func rotation(angle: Double, axis: SIMD3<Float>) -> simd_quatf {
        // Reduce in Double before converting to Float, preserving accuracy for
        // long segments that contain many complete revolutions.
        simd_quatf(angle: Float(angle.truncatingRemainder(dividingBy: 2 * .pi)), axis: axis)
    }
}
