import Foundation
import simd

/// A quadratic curve relative to two endpoints. Values remain compact and
/// travel with player-bound endpoints; no world transforms are persisted.
struct CoachMarkCurve: Codable, Hashable, Sendable {
    var bend: Float
    var lift: Float
    /// Rotation about the start-to-end axis, in degrees. Positive angles lift
    /// an ordinary pitch-level bend. Zero is the exact pre-rotation geometry.
    var rollDegrees: Float

    static let maximumBend: Float = 12
    static let maximumLift: Float = 4
    static let maximumRollDegrees: Float = 180
    static let segmentCount = 32

    init(bend: Float, lift: Float, rollDegrees: Float = 0) {
        self.bend = bend
        self.lift = lift
        self.rollDegrees = rollDegrees
    }

    private enum CodingKeys: String, CodingKey { case bend, lift, rollDegrees }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bend = try container.decode(Float.self, forKey: .bend)
        lift = try container.decode(Float.self, forKey: .lift)
        rollDegrees = try container.decodeIfPresent(Float.self, forKey: .rollDegrees) ?? 0
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bend, forKey: .bend)
        try container.encode(lift, forKey: .lift)
        if rollDegrees != 0 { try container.encode(rollDegrees, forKey: .rollDegrees) }
    }

    var isValid: Bool {
        bend.isFinite && lift.isFinite && rollDegrees.isFinite
            && abs(bend) <= Self.maximumBend
            && (0...Self.maximumLift).contains(lift)
            && abs(rollDegrees) <= Self.maximumRollDegrees
    }

    static func initial(start: PitchPoint, end: PitchPoint) -> Self {
        Self(bend: min(max(ReplayGeometry.distance(start, end) * 0.18, 0.6), 6), lift: 0)
    }

    func clamped() -> Self {
        Self(bend: bend.isFinite ? min(max(bend, -Self.maximumBend), Self.maximumBend) : 0,
             lift: lift.isFinite ? min(max(lift, 0), Self.maximumLift) : 0,
             rollDegrees: rollDegrees.isFinite
                ? min(max(rollDegrees, -Self.maximumRollDegrees), Self.maximumRollDegrees) : 0)
    }

    /// Midpoint displacement before pitch/floor clipping, in metres. Scaling
    /// this value preserves the existing bend/lift direction, including saves.
    var amount: Float { hypot(bend, lift) }

    func adjusting(amountDelta: Float, angleDelta: Float) -> Self {
        guard amountDelta.isFinite, angleDelta.isFinite else { return self }
        let safe = clamped()
        if amountDelta == 0 {
            return Self(bend: safe.bend, lift: safe.lift,
                        rollDegrees: safe.rollDegrees + angleDelta).clamped()
        }
        let length = safe.amount
        let direction = length > 0.0001
            ? SIMD2<Float>(safe.bend, safe.lift) / length : SIMD2<Float>(1, 0)
        let bendLimit = abs(direction.x) > 0.0001 ? Self.maximumBend / abs(direction.x) : .infinity
        let liftLimit = direction.y > 0.0001 ? Self.maximumLift / direction.y : .infinity
        let target = min(max(length + amountDelta, 0), min(bendLimit, liftLimit))
        return Self(bend: direction.x * target, lift: direction.y * target,
                    rollDegrees: safe.rollDegrees + angleDelta).clamped()
    }

    func controlPoint(for mark: CoachMark) -> SIMD3<Float> {
        let control = unconstrainedControlPoint(for: mark)
        // Clamping the control point (rather than samples) keeps the quadratic
        // smooth and inside the pitch/floor bounds. Raised endpoints allow an
        // arc to dip; arcs on the turf cannot be rotated beneath the floor.
        return SIMD3<Float>(
            min(max(control.x, -34), 34),
            min(max(control.y, 0), Self.maximumLift * 3),
            min(max(control.z, -52.5), 52.5)
        )
    }

    func isLimitedByPitch(for mark: CoachMark) -> Bool {
        simd_distance_squared(unconstrainedControlPoint(for: mark), controlPoint(for: mark)) > 0.000_001
    }

    private func unconstrainedControlPoint(for mark: CoachMark) -> SIMD3<Float> {
        let dx = mark.end.x - mark.start.x
        let dz = mark.end.z - mark.start.z
        let length = max(hypot(dx, dz), 0.0001)
        let safe = clamped()
        let midpoint = SIMD3<Float>((mark.start.x + mark.end.x) * 0.5,
            (mark.resolvedStartElevation + mark.resolvedEndElevation) * 0.5,
            (mark.start.z + mark.end.z) * 0.5)
        var offset = SIMD3<Float>(-dz / length * safe.bend * 2,
                                  safe.lift * 2, dx / length * safe.bend * 2)
        if safe.rollDegrees != 0 {
            let chord = SIMD3<Float>(dx, mark.resolvedEndElevation - mark.resolvedStartElevation, dz)
            // A vertical or coincident pair still has a stable axis. Ordinary
            // arcs use the actual 3D chord, not the viewer or world-up axis.
            let axis = simd_length_squared(chord) > 0.000_001 ? simd_normalize(chord) : SIMD3<Float>(1, 0, 0)
            offset = simd_quatf(angle: -safe.rollDegrees * .pi / 180, axis: axis).act(offset)
        }
        return midpoint + offset
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
