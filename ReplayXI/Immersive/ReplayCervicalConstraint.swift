import Foundation
import simd

/// Render safety envelope relative to the chest's rest frame. Bounds apply to
/// source animation + procedural gaze together, not to either in isolation.
/// These are presentation limits, not clinical measurements of neck mobility.
enum ReplayCervicalConstraint {
    static func limited(_ rotation: simd_quatf) -> simd_quatf {
        let length = simd_length(rotation.vector)
        guard length.isFinite, length > 0.000_001 else { return simd_quatf(real: 1, imag: .zero) }
        let value = simd_normalize(rotation)
        let forward = value.act([0, 0, 1])
        let yaw = atan2(forward.x, forward.z)
        let pitch = atan2(-forward.y, hypot(forward.x, forward.z))
        let swing = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        let residualRight = (swing.inverse * value).act([1, 0, 0])
        let roll = atan2(residualRight.y, residualRight.x)
        let boundedYaw = softBound(yaw, knee: 55, limit: 70)
        let boundedPitch = softBound(pitch, knee: 25, limit: 40)
        let boundedRoll = softBound(roll, knee: 12, limit: 22)
        // Preserve unmodified transforms exactly in the ordinary range.
        guard boundedYaw != yaw || boundedPitch != pitch || boundedRoll != roll else { return value }
        return simd_normalize(simd_quatf(angle: boundedYaw, axis: [0, 1, 0])
            * simd_quatf(angle: boundedPitch, axis: [1, 0, 0])
            * simd_quatf(angle: boundedRoll, axis: [0, 0, 1]))
    }

    private static func softBound(_ value: Float, knee: Float, limit: Float) -> Float {
        let start = knee * .pi / 180
        let width = (limit - knee) * .pi / 180
        let magnitude = abs(value)
        guard magnitude > start else { return value }
        // C1 join: no hard angular stop as a gaze approaches its limit.
        let bounded = start + width * (1 - exp(-(magnitude - start) / width))
        return value < 0 ? -bounded : bounded
    }
}
