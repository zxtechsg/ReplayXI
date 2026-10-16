import RealityKit
import simd

/// Capture a review in front of the viewer once. The pitch stays horizontal
/// and room-fixed after placement, including when the viewer looks elsewhere.
enum ReplayReviewPlacement {
    /// Looking straight down still has a heading: use the headset's right
    /// axis when its forward axis has no useful horizontal projection.
    nonisolated static func horizontalViewer(_ viewer: simd_float4x4) -> simd_float4x4? {
        guard (0..<4).allSatisfy({ axis in (0..<4).allSatisfy { viewer[axis][$0].isFinite } })
        else { return nil }
        let forward = SIMD2<Float>(-viewer.columns.2.x, -viewer.columns.2.z)
        let yaw: Float
        if simd_length_squared(forward) > 0.001 {
            yaw = atan2(-forward.x, -forward.y)
        } else {
            let right = SIMD2<Float>(viewer.columns.0.x, viewer.columns.0.z)
            guard simd_length_squared(right) > 0.001 else { return nil }
            yaw = atan2(-right.y, right.x)
        }
        return Transform(rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]),
            translation: [viewer.columns.3.x, viewer.columns.3.y, viewer.columns.3.z]).matrix
    }

    nonisolated static func apply(to base: Transform, viewMode: ReplayViewMode,
                      viewer: simd_float4x4) -> Transform {
        guard viewMode == .tacticalTable || viewMode == .touchline,
              let viewer = horizontalViewer(viewer)
        else { return base }
        let forward = SIMD2<Float>(-viewer.columns.2.x, -viewer.columns.2.z)
        let yaw = atan2(-forward.x, -forward.y)
        let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let eye = SIMD3<Float>(viewer.columns.3.x, viewer.columns.3.y, viewer.columns.3.z)
        var result = base
        result.rotation = rotation * base.rotation
        result.translation = eye + rotation.act([base.translation.x, 0, base.translation.z])
        result.translation.y = viewMode == .tacticalTable ? max(0.12, eye.y - 0.65) : 0.02
        return result
    }
}
