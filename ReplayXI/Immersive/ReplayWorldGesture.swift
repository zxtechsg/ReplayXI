import ARKit
import QuartzCore
import RealityKit
import simd

/// Device-local pose and hand samples. No replay state is stored in ARKit.
@MainActor
final class ReplayWorldGestureTracking {
    private var session = ARKitSession()
    private var world = WorldTrackingProvider()
    private let hands = HandTrackingProvider()
    private(set) var hasResolvedWorldStartup = false
    private(set) var tracksWorld = false
    private(set) var tracksHands = false

    func start() async {
        guard !Task.isCancelled else { return }
        guard WorldTrackingProvider.isSupported else {
            hasResolvedWorldStartup = true
            return
        }
        do {
            try await session.run([world])
        } catch {
            hasResolvedWorldStartup = true
            return
        }
        hasResolvedWorldStartup = true
        guard !Task.isCancelled else { session.stop(); return }
        tracksWorld = true
        guard HandTrackingProvider.isSupported else { return }
        let authorization = await session.queryAuthorization(for: [.handTracking])[.handTracking]
        guard !Task.isCancelled else { session.stop(); tracksWorld = false; return }
        let permission = authorization == .notDetermined
            ? await session.requestAuthorization(for: [.handTracking])[.handTracking]
            : authorization
        guard !Task.isCancelled else { session.stop(); tracksWorld = false; return }
        guard permission == .allowed else { return }
        do {
            try await session.run([world, hands])
            guard !Task.isCancelled else { session.stop(); tracksWorld = false; return }
            tracksHands = true
        } catch {
            // A failed run stops its providers. Reusing `world` can assert, so
            // recover POV tracking with a fresh session and provider pair.
            tracksWorld = false
            guard !Task.isCancelled else { return }
            let fallbackSession = ARKitSession()
            let fallbackWorld = WorldTrackingProvider()
            do {
                try await fallbackSession.run([fallbackWorld])
                guard !Task.isCancelled else { fallbackSession.stop(); return }
                session = fallbackSession
                world = fallbackWorld
                tracksWorld = true
            } catch {
                fallbackSession.stop()
            }
        }
    }

    func stop() {
        session.stop()
        hasResolvedWorldStartup = false
        tracksWorld = false
        tracksHands = false
    }

    func deviceYaw() -> Float? {
        guard tracksWorld else { return nil }
        guard let anchor = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else { return nil }
        let forward = -SIMD2(anchor.originFromAnchorTransform.columns.2.x,
                             anchor.originFromAnchorTransform.columns.2.z)
        guard simd_length_squared(forward) > 0.01 else { return nil }
        return atan2(-forward.x, -forward.y)
    }

    /// Sampled only when entering a player's POV, never used as a live camera
    /// follow signal. A seated viewer needs the same avatar eye height.
    func deviceHeight() -> Float? {
        guard tracksWorld,
              let anchor = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else { return nil }
        let height = anchor.originFromAnchorTransform.columns.3.y
        return height.isFinite ? height : nil
    }

    func deviceTransform() -> simd_float4x4? {
        guard tracksWorld,
              let anchor = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else { return nil }
        return anchor.originFromAnchorTransform
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
    /// Eyes are in front of the athlete's pelvis/neck axis. A centreline
    /// camera looks down through the shirt instead of towards the legs.
    static let eyeForwardOffsetMetres: Float = 0.15
    let scenarioID: String
    let playerID: String
    let rootYaw: Float
    let rootHeight: Float
    let roomXZ: SIMD2<Float>

    init(scenarioID: String, playerID: String, rootYaw: Float, rootHeight: Float = 0,
         roomXZ: SIMD2<Float> = .zero) {
        self.scenarioID = scenarioID
        self.playerID = playerID
        self.rootYaw = rootYaw
        self.rootHeight = rootHeight
        self.roomXZ = roomXZ.x.isFinite && roomXZ.y.isFinite ? roomXZ : .zero
    }

    /// Sample the room position only on POV entry. Later leaning/walking is
    /// free headset motion, not a signal that drags the replay world along.
    static func roomXZ(from transform: simd_float4x4?) -> SIMD2<Float>? {
        guard let transform else { return nil }
        let position = SIMD2<Float>(transform.columns.3.x, transform.columns.3.z)
        return position.x.isFinite && position.y.isFinite ? position : nil
    }

    func rootPosition(for pose: PlayerPose) -> SIMD3<Float> {
        let rotation = simd_quatf(angle: rootYaw, axis: [0, 1, 0])
        return SIMD3<Float>(roomXZ.x, rootHeight, roomXZ.y) - rotation.act(Self.playerEyePoint(pose))
    }

    /// Translation follows replayed body facing, not the live headset or
    /// animated head. The captured rootYaw remains fixed for free look.
    static func playerEyePoint(_ pose: PlayerPose) -> SIMD3<Float> {
        guard pose.position.x.isFinite, pose.position.z.isFinite,
              pose.facingDegrees.isFinite else { return .zero }
        let yaw = pose.facingDegrees.truncatingRemainder(dividingBy: 360) * .pi / 180
        return SIMD3<Float>(pose.position.x + sin(yaw) * eyeForwardOffsetMetres, 0,
                            pose.position.z + cos(yaw) * eyeForwardOffsetMetres)
    }

    /// A crouch/header at entry must not lock the viewer below the torso when
    /// the athlete stands later. Preserve the standing eye level as a floor;
    /// yaw still uses the actual posed head direction at the chosen timestamp.
    static func safeEyeHeight(crownHeight: Float?, nominalHeight: Float, heightScale: Float) -> Float {
        guard nominalHeight.isFinite, heightScale.isFinite,
              nominalHeight > 0.11, heightScale > 0 else { return 1.68 }
        let standing = (nominalHeight - 0.11) * heightScale
        guard standing.isFinite else { return 1.68 }
        guard let crownHeight, crownHeight.isFinite else { return standing }
        return max(standing, crownHeight - 0.11 * heightScale)
    }

    /// Shift the pitch once so the safe avatar eye level meets the tracked
    /// eye. The result is immutable during this entry: no gait bob or forced
    /// vertical movement follows later poses. No tracking means no shift.
    static func rootHeight(deviceHeight: Float?, renderedEyeHeight: Float?) -> Float {
        guard let deviceHeight, deviceHeight.isFinite else { return 0 }
        let tracked = min(max(deviceHeight, 0.35), 2.4)
        let eye = renderedEyeHeight.flatMap { $0.isFinite ? $0 : nil } ?? 1.68
        let boundedEye = min(max(eye, 0.8), 2.3)
        return min(max(tracked - boundedEye, -1.7), 1.2)
    }

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

/// A POV entry waits briefly for the headset pose. After the deadline it
/// commits one fixed fallback instead of showing a wrong bearing and snapping
/// the whole world later when tracking arrives.
enum ReplayPOVEntryPolicy {
    static let trackingWaitSeconds: TimeInterval = 0.6

    static func shouldUseFallback(startedAt: TimeInterval, now: TimeInterval) -> Bool {
        guard startedAt.isFinite, now.isFinite else { return false }
        return now - startedAt >= trackingWaitSeconds
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

    mutating func update(left: SIMD3<Float>?, right: SIMD3<Float>?, allowed: Bool,
                         minimumOffsetY: Float = -0.6) {
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
            min(max(baseline.offset.y + delta.y, minimumOffsetY), 0.6),
            min(max(baseline.offset.z + delta.z, -2.0), 2.0)
        )
    }

    mutating func constrainVerticalOffset(minimumY: Float) {
        let bounded = min(max(offset.y, minimumY), 0.6)
        guard bounded != offset.y else { return }
        offset.y = bounded
        baseline = nil
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
