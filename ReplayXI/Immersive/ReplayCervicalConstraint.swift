import Foundation
import simd

/// Render safety envelope relative to the chest's rest frame. Bounds apply to
/// source animation + procedural gaze together, not to either in isolation.
/// These are presentation limits, not clinical measurements of neck mobility.
enum ReplayCervicalConstraint {
    /// Gaze is expressed in the player's root frame, not the moving chest.
    /// Retain source motion while reducing the torso lean/yaw inherited by the
    /// head. Keep source roll; this is not a rigid horizon lock or eye tracking.
    static func aimedModelRotation(_ current: simd_quatf, look: ReplayAthleteLookPose,
                                   weight: Float) -> simd_quatf {
        guard weight.isFinite, weight > 0,
              look.combinedYawRadians.isFinite, look.combinedPitchRadians.isFinite else { return current }
        let forward = current.act([0, 0, 1])
        let yaw = atan2(forward.x, forward.z)
        let pitch = atan2(-forward.y, hypot(forward.x, forward.z))
        let swing = simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
        let right = (swing.inverse * current).act([1, 0, 0])
        let roll = atan2(right.y, right.x)
        let wanted = simd_quatf(angle: look.combinedYawRadians, axis: [0, 1, 0])
            * simd_quatf(angle: look.combinedPitchRadians, axis: [1, 0, 0])
            * simd_quatf(angle: roll, axis: [0, 0, 1])
        let target = simd_dot(current.vector, wanted.vector) < 0
            ? simd_quatf(vector: -wanted.vector) : wanted
        return simd_normalize(simd_slerp(current, target, min(weight, 1)))
    }

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
