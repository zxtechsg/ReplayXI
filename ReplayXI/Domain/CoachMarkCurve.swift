import Foundation
import simd

/// A quadratic curve relative to two endpoints. Values remain compact and
/// travel with player-bound endpoints; no world transforms are persisted.
struct CoachMarkCurve: Codable, Hashable, Sendable {
    var bend: Float
    var lift: Float

    static let maximumBend: Float = 12
    static let maximumLift: Float = 4
    static let segmentCount = 32

    var isValid: Bool {
        bend.isFinite && lift.isFinite
            && abs(bend) <= Self.maximumBend
            && (0...Self.maximumLift).contains(lift)
    }

    static func initial(start: PitchPoint, end: PitchPoint) -> Self {
        Self(bend: min(max(ReplayGeometry.distance(start, end) * 0.18, 0.6), 6), lift: 0)
    }

    func clamped() -> Self {
        Self(bend: bend.isFinite ? min(max(bend, -Self.maximumBend), Self.maximumBend) : 0,
             lift: lift.isFinite ? min(max(lift, 0), Self.maximumLift) : 0)
    }

    func controlPoint(for mark: CoachMark) -> SIMD3<Float> {
        let dx = mark.end.x - mark.start.x
        let dz = mark.end.z - mark.start.z
        let length = max(hypot(dx, dz), 0.0001)
        let safe = clamped()
        // Clamp the control point, not individual curve samples: the entire
        // quadratic stays smooth inside the pitch's convex boundary.
        return SIMD3<Float>(
            min(max((mark.start.x + mark.end.x) * 0.5 - dz / length * safe.bend * 2, -34), 34),
            (mark.resolvedStartElevation + mark.resolvedEndElevation) * 0.5 + safe.lift * 2,
            min(max((mark.start.z + mark.end.z) * 0.5 + dx / length * safe.bend * 2, -52.5), 52.5)
        )
    }

    func point(at fraction: Float, for mark: CoachMark, baseY: Float = 0) -> SIMD3<Float> {
        let t = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        let start = SIMD3<Float>(mark.start.x, mark.resolvedStartElevation, mark.start.z)
        let end = SIMD3<Float>(mark.end.x, mark.resolvedEndElevation, mark.end.z)
        let point = (1 - t) * (1 - t) * start
            + 2 * (1 - t) * t * controlPoint(for: mark) + t * t * end
        // Floating-point weights can sum to just above one at the touchline.
        // Clamp only this rounding overshoot after the smooth bounded curve.
        return SIMD3<Float>(min(max(point.x, -34), 34), point.y + baseY,
                            min(max(point.z, -52.5), 52.5))
    }

    func endTangent(for mark: CoachMark) -> SIMD3<Float> {
        let end = SIMD3<Float>(mark.end.x, mark.resolvedEndElevation, mark.end.z)
        return end - controlPoint(for: mark)
    }
}
