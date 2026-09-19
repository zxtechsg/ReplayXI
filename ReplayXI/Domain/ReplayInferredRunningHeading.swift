import Foundation
import simd

/// Presentation headings for inferred, non-contact outfield routes only.
/// A late ball→travel switch made a defender accelerate into a forward run
/// while still facing backwards. Anticipate the authored acceleration, without
/// changing positions, inventing tracking evidence or twisting the leg rig.
enum ReplayInferredRunningHeading {
    static let anticipation: TimeInterval = 0.65
    /// Bound on generated waypoint steps. PlayerTrack's Hermite interpolation
    /// has its own derivative; native120Hz tests measure that separately.
    static let waypointDegreesPerSecond: Float = 140

    static func applying(to baseline: [MotionKeyframe], route: PlayerTrack,
                         ball: BallTrack) -> [MotionKeyframe] {
        guard let first = baseline.first, let last = baseline.last,
              first.time.isFinite, last.time.isFinite, last.time > first.time,
              first.facingDegrees.isFinite else { return baseline }
        var heading = first.facingDegrees
        var previousTime = first.time
        return baseline.enumerated().map { index, frame in
            guard index > 0 else { return frame }
            let span = frame.time - previousTime
            previousTime = frame.time
            guard span.isFinite, span > 0 else { heading = frame.facingDegrees; return frame }
            func velocity(at time: Double) -> SIMD2<Float> {
                let before = route.presentationPose(at: max(first.time, time - 0.12)).position
                let after = route.presentationPose(at: min(last.time, time + 0.12)).position
                return SIMD2(after.x - before.x, after.z - before.z) / 0.24
            }
            let current = velocity(at: frame.time)
            let future = velocity(at: min(frame.time + anticipation, last.time))
            let speed = simd_length(current)
            let upcomingSpeed = simd_length(future)
            let targetBall = ball.pose(at: frame.time).position
            let toBall = SIMD2(targetBall.x - frame.position.x, targetBall.z - frame.position.z)
            guard speed.isFinite, upcomingSpeed.isFinite, simd_length_squared(toBall).isFinite else {
                heading = frame.facingDegrees
                return frame
            }
            // Slow shuffles keep their ball-facing intent. The future speed
            // admits preparation before a sprint; an existing run faces its
            // CURRENT direction, not a distant corner further along the route.
            let demand = smooth((max(speed, upcomingSpeed) - 3) / 1)
            let travel = speed > 0.25 ? current : future
            let ballBearing = simd_length_squared(toBall) > 0.0001
                ? atan2(toBall.x, toBall.y) * 180 / .pi : heading
            let travelBearing = simd_length_squared(travel) > 0.0001
                ? atan2(travel.x, travel.y) * 180 / .pi : ballBearing
            // Blend bounded steering errors, not almost-opposite vectors whose
            // length can vanish. Wrap against the already unwrapped heading.
            let ballError = min(max(delta(from: heading, to: ballBearing), -90), 90)
            let travelError = min(max(delta(from: heading, to: travelBearing), -90), 90)
            let error = ballError + (travelError - ballError) * demand
            let limit = waypointDegreesPerSecond * Float(span)
            heading += min(max(error, -limit), limit)
            return .init(time: frame.time, position: frame.position, facingDegrees: heading)
        }
    }

    private static func delta(from: Float, to: Float) -> Float {
        let value = (to.truncatingRemainder(dividingBy: 360)
            - from.truncatingRemainder(dividingBy: 360)) * .pi / 180
        return atan2(sin(value), cos(value)) * 180 / .pi
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
