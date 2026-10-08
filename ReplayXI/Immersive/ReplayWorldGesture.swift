import ARKit
import QuartzCore
import RealityKit
import simd

/// Device-local pose and hand samples. No replay state is stored in ARKit.
@MainActor
final class ReplayWorldGestureTracking {
    private let session = ARKitSession()
    private let world = WorldTrackingProvider()
    private let hands = HandTrackingProvider()
    private(set) var tracksHands = false

    func start() async {
        guard WorldTrackingProvider.isSupported else { return }
        do {
            try await session.run([world])
        } catch {
            return
        }
        guard HandTrackingProvider.isSupported else { return }
        let authorization = await session.queryAuthorization(for: [.handTracking])[.handTracking]
        let permission = authorization == .notDetermined
            ? await session.requestAuthorization(for: [.handTracking])[.handTracking]
            : authorization
        guard permission == .allowed else { return }
        do {
            try await session.run([world, hands])
            tracksHands = true
        } catch {
            // A failed hand provider must not also disable POV alignment.
            try? await session.run([world])
        }
    }

    func stop() {
        session.stop()
        tracksHands = false
    }

    func deviceYaw() -> Float? {
        guard let anchor = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else { return nil }
        let forward = -SIMD2(anchor.originFromAnchorTransform.columns.2.x,
                             anchor.originFromAnchorTransform.columns.2.z)
        guard simd_length_squared(forward) > 0.01 else { return nil }
        return atan2(-forward.x, -forward.y)
    }

    func pinchMidpoints() -> (SIMD3<Float>, SIMD3<Float>)? {
        guard tracksHands else { return nil }
        let anchors = hands.handAnchors(at: CACurrentMediaTime())
        guard let left = Self.pinchMidpoint(anchors.leftHand),
              let right = Self.pinchMidpoint(anchors.rightHand) else { return nil }
        return (left, right)
    }

    private static func pinchMidpoint(_ anchor: HandAnchor?) -> SIMD3<Float>? {
        guard let anchor, anchor.isTracked, let skeleton = anchor.handSkeleton else { return nil }
        let thumb = skeleton.joint(.thumbTip)
        let index = skeleton.joint(.indexFingerTip)
        guard thumb.isTracked, index.isTracked else { return nil }
        let thumbTransform = anchor.originFromAnchorTransform * thumb.anchorFromJointTransform
        let indexTransform = anchor.originFromAnchorTransform * index.anchorFromJointTransform
        let thumbPoint = SIMD3(thumbTransform.columns.3.x, thumbTransform.columns.3.y,
                               thumbTransform.columns.3.z)
        let indexPoint = SIMD3(indexTransform.columns.3.x, indexTransform.columns.3.y,
                               indexTransform.columns.3.z)
        guard simd_distance(thumbPoint, indexPoint) <= 0.035 else { return nil }
        return (thumbPoint + indexPoint) / 2
    }
}

struct ReplayPOVReference: Equatable {
    let scenarioID: String
    let playerID: String
    let rootYaw: Float

    static func rootYaw(deviceYaw: Float, playerFacingDegrees: Float,
                        lookYawRadians: Float) -> Float? {
        guard deviceYaw.isFinite, playerFacingDegrees.isFinite,
              lookYawRadians.isFinite else { return nil }
        // Player rigs face local +Z; a headset faces local -Z.
        return deviceYaw + .pi - playerFacingDegrees * .pi / 180 - lookYawRadians
    }

    static func rootYaw(deviceYaw: Float, playerFacingDegrees: Float,
                        renderedHeadForward: SIMD3<Float>?,
                        fallbackLookYawRadians: Float) -> Float? {
        if let forward = renderedHeadForward,
           forward.x.isFinite, forward.z.isFinite,
           hypot(forward.x, forward.z) > 0.0001 {
            return rootYaw(deviceYaw: deviceYaw, playerFacingDegrees: playerFacingDegrees,
                           lookYawRadians: atan2(forward.x, forward.z))
        }
        return rootYaw(deviceYaw: deviceYaw, playerFacingDegrees: playerFacingDegrees,
                       lookYawRadians: fallbackLookYawRadians)
    }
}

/// Preview starts from one fixed two-hand checkpoint, so hand jitter cannot
/// compound from frame to frame. Pitch and stadium share this world adjustment.
struct ReplayWorldPlacement: Equatable {
    private struct Baseline: Equatable {
        let distance: Float
        let midpoint: SIMD3<Float>
        let scale: Float
        let offset: SIMD3<Float>
    }

    var scale: Float = 1
    var offset: SIMD3<Float> = .zero
    private var baseline: Baseline?

    var isActive: Bool { baseline != nil }

    mutating func update(left: SIMD3<Float>?, right: SIMD3<Float>?, allowed: Bool) {
        guard allowed, let left, let right, Self.finite(left), Self.finite(right) else {
            baseline = nil
            return
        }
        let distance = simd_distance(left, right)
        guard distance.isFinite, distance >= 0.10 else { baseline = nil; return }
        let midpoint = (left + right) / 2
        if baseline == nil {
            baseline = Baseline(distance: distance, midpoint: midpoint, scale: scale, offset: offset)
        }
        guard let baseline else { return }
        scale = min(max(baseline.scale * distance / baseline.distance, 0.30), 3.0)
        let delta = midpoint - baseline.midpoint
        offset = SIMD3(
            min(max(baseline.offset.x + delta.x, -1.5), 1.5),
            min(max(baseline.offset.y + delta.y, -0.6), 0.6),
            min(max(baseline.offset.z + delta.z, -2.0), 2.0)
        )
    }

    mutating func reset() {
        baseline = nil
        scale = 1
        offset = .zero
    }

    private static func finite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    static func apply(_ placement: ReplayWorldPlacement, to base: Transform) -> Transform {
        var result = base
        result.scale *= placement.scale
        result.translation += placement.offset
        return result
    }
}
