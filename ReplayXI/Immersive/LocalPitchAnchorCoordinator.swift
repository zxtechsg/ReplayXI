import ARKit
import Foundation
import Observation
import QuartzCore
import simd

/// Tracks this headset relative to a device-local pitch origin.
///
/// This coordinator reports the horizontal pose of the Apple Vision Pro headset.
/// It does not track the wearer's feet, stance, stride, or full body.
@available(visionOS 26.0, *)
@MainActor
@Observable
final class LocalPitchAnchorCoordinator {
    struct HorizontalHeadsetPose: Equatable, Sendable {
        /// Headset position along the pitch anchor's horizontal x-axis, in metres.
        let x: Float

        /// Headset position along the pitch anchor's horizontal z-axis, in metres.
        let z: Float

        /// Headset heading relative to the pitch anchor. Zero faces the anchor's -z direction.
        let yawRadians: Float

        /// The monotonic timestamp used to query the device pose.
        let sampledAt: TimeInterval

        var position: SIMD2<Float> {
            SIMD2(x, z)
        }
    }

    struct WearerRelativeDisplacement: Equatable, Sendable {
        /// Positive values are to the wearer's right; negative values are left.
        let rightMetres: Float

        /// Positive values are in front of the wearer; negative values are behind.
        let forwardMetres: Float

        var distanceMetres: Float {
            hypot(rightMetres, forwardMetres)
        }
    }

    /// Rotates a pitch-locked target vector into the current headset heading.
    /// At yaw zero the wearer faces pitch -z, matching RealityKit camera forward.
    static func wearerRelativeDisplacement(
        from pose: HorizontalHeadsetPose,
        targetX: Float,
        targetZ: Float
    ) -> WearerRelativeDisplacement {
        let deltaX = targetX - pose.x
        let deltaZ = targetZ - pose.z
        let cosine = cos(pose.yawRadians)
        let sine = sin(pose.yawRadians)
        return WearerRelativeDisplacement(
            rightMetres: deltaX * cosine + deltaZ * sine,
            forwardMetres: deltaX * sine - deltaZ * cosine
        )
    }

    enum TrackingStatus: Equatable, Sendable {
        case stopped
        case starting
        case waitingForSharedPitchAnchor
        case localizingPitchAnchor
        case localizingHeadset
        case trackingHeadsetRelativeToPitch
        case unavailable(String)

        var label: String {
            switch self {
            case .stopped: "POSITIONING OFF"
            case .starting: "STARTING POSITIONING"
            case .waitingForSharedPitchAnchor: "WAITING FOR PITCH ORIGIN"
            case .localizingPitchAnchor: "LOCALIZING PITCH ORIGIN"
            case .localizingHeadset: "LOCALIZING HEADSET"
            case .trackingHeadsetRelativeToPitch: "HEADSET POSITION LIVE"
            case .unavailable: "POSITIONING UNAVAILABLE"
            }
        }
    }

    /// Suitable for display near positional feedback so it isn't mistaken for foot tracking.
    static let trackingDisclosure =
        "Position comes from the Apple Vision Pro headset, not the player's feet or full body."

    private(set) var status: TrackingStatus = .stopped
    private(set) var horizontalHeadsetPose: HorizontalHeadsetPose?
    private(set) var sharedPitchAnchorID: UUID?
    private(set) var pitchOriginTransform: simd_float4x4?
    private(set) var isPitchAnchorTracked = false
    private(set) var placedPitchAnchorLocally = false
    private(set) var isPlacingPitchAnchor = false

    /// Called only when ARKit unexpectedly removes the anchor currently selected
    /// by shared playback state. Explicit app-driven removal clears the selection
    /// first and therefore does not produce a duplicate transition.
    @ObservationIgnored
    var onSelectedAnchorRemoved: (@MainActor (UUID) -> Void)?

    var isRunning: Bool {
        arkitSession != nil
    }

    var hasUsableSharedPitchFrame: Bool {
        isPitchAnchorTracked
            && pitchOriginTransform != nil
            && horizontalHeadsetPose != nil
    }

    @ObservationIgnored private var arkitSession: ARKitSession?
    @ObservationIgnored private var worldTrackingProvider: WorldTrackingProvider?
    @ObservationIgnored private var pitchAnchor: WorldAnchor?
    @ObservationIgnored private var locallyPlacedPitchAnchorID: UUID?
    @ObservationIgnored private var selectedSharedPitchAnchorID: UUID?
    @ObservationIgnored private var sharedAnchorCache: [UUID: WorldAnchor] = [:]
    @ObservationIgnored private var anchorUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var poseSamplingTask: Task<Void, Never>?
    @ObservationIgnored private var pitchAnchorRemovalTask: Task<Void, Never>?

    /// Starts world tracking. Call this only while the app presents a Full Space.
    func start() async {
        guard arkitSession == nil else { return }
        guard WorldTrackingProvider.isSupported else {
            status = .unavailable("World tracking isn't supported on this device.")
            return
        }

        status = .starting
        horizontalHeadsetPose = nil

        let session = ARKitSession()
        let provider = WorldTrackingProvider()
        arkitSession = session
        worldTrackingProvider = provider

        anchorUpdatesTask = makeAnchorUpdatesTask(provider: provider)
        poseSamplingTask = makePoseSamplingTask(provider: provider)

        do {
            // World tracking alone doesn't request scene reconstruction or plane data.
            try await session.run([provider])
            status = .waitingForSharedPitchAnchor
        } catch {
            tearDownSession()
            status = .unavailable("World tracking could not start: \(error.localizedDescription)")
        }
    }

    /// Places a device-local pitch origin. No anchor is shared with another headset.
    @discardableResult
    func placeLocalPitchAnchor(
        originFromAnchorTransform transform: simd_float4x4
    ) async throws -> UUID {
        try await placePitchAnchor(
            originFromAnchorTransform: transform
        )
    }

    private func placePitchAnchor(
        originFromAnchorTransform transform: simd_float4x4
    ) async throws -> UUID {
        guard let provider = worldTrackingProvider, arkitSession != nil else {
            throw CoordinatorError.worldTrackingNotRunning
        }
        guard !isPlacingPitchAnchor else {
            throw CoordinatorError.placementInProgress
        }
        isPlacingPitchAnchor = true
        defer { isPlacingPitchAnchor = false }

        let previousAnchor = pitchAnchor
        let newAnchor = WorldAnchor(
            originFromAnchorTransform: transform
        )

        try await provider.addAnchor(newAnchor)

        selectedSharedPitchAnchorID = newAnchor.id
        sharedAnchorCache[newAnchor.id] = newAnchor
        pitchAnchor = newAnchor
        sharedPitchAnchorID = newAnchor.id
        pitchOriginTransform = newAnchor.originFromAnchorTransform
        locallyPlacedPitchAnchorID = newAnchor.id
        placedPitchAnchorLocally = true
        isPitchAnchorTracked = newAnchor.isTracked
        horizontalHeadsetPose = nil
        status = .localizingPitchAnchor

        if let previousAnchor, previousAnchor.id != newAnchor.id {
            try? await provider.removeAnchor(previousAnchor)
            sharedAnchorCache.removeValue(forKey: previousAnchor.id)
        }

        return newAnchor.id
    }

    /// Places a yaw-aligned origin at the current headset position.
    ///
    /// The position is still a headset reference—not a measured foot or floor point.
    @discardableResult
    func placeLocalPitchAnchorAtCurrentHeadset() async throws -> UUID {
        let origin = try currentHeadsetFloorOrigin()
        return try await placeLocalPitchAnchor(originFromAnchorTransform: origin)
    }

    private func currentHeadsetFloorOrigin() throws -> simd_float4x4 {
        guard let provider = worldTrackingProvider, arkitSession != nil else {
            throw CoordinatorError.worldTrackingNotRunning
        }
        let sampleTime = CACurrentMediaTime()
        guard let deviceAnchor = provider.queryDeviceAnchor(atTimestamp: sampleTime),
              deviceAnchor.isTracked else {
            throw CoordinatorError.headsetNotTracked
        }

        let deviceTransform = deviceAnchor.originFromAnchorTransform
        let forward = -SIMD3<Float>(
            deviceTransform.columns.2.x,
            deviceTransform.columns.2.y,
            deviceTransform.columns.2.z
        )
        let yaw = atan2(-forward.x, -forward.z)
        var origin = simd_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]))
        origin.columns.3 = deviceTransform.columns.3
        // The physical rehearsal frame is horizontal at floor height. X/Z still come from the
        // headset; this does not imply foot or full-body tracking.
        origin.columns.3.y = 0
        return origin
    }

    /// Selects the local anchor ID used by the positioning view.
    /// Anchor updates may arrive before or after that state, so updates are cached by UUID.
    func selectSharedPitchAnchor(id: UUID?) {
        selectedSharedPitchAnchorID = id
        guard let id else {
            pitchAnchor = nil
            sharedPitchAnchorID = nil
            pitchOriginTransform = nil
            isPitchAnchorTracked = false
            horizontalHeadsetPose = nil
            status = arkitSession == nil ? .stopped : .waitingForSharedPitchAnchor
            return
        }
        if let anchor = sharedAnchorCache[id] {
            adopt(anchor)
        } else {
            pitchAnchor = nil
            sharedPitchAnchorID = id
            pitchOriginTransform = nil
            isPitchAnchorTracked = false
            horizontalHeadsetPose = nil
            status = arkitSession == nil ? .stopped : .waitingForSharedPitchAnchor
        }
    }

    /// Cancels observation, stops ARKit, and clears transient positional state.
    func stop() {
        tearDownSession()
        status = .stopped
    }

    /// Removes only the anchor created by this headset.
    func removeLocallyPlacedPitchAnchor() async {
        if let pitchAnchorRemovalTask {
            await pitchAnchorRemovalTask.value
            return
        }
        guard let localID = locallyPlacedPitchAnchorID else { return }
        let anchor = sharedAnchorCache[localID]
            ?? (pitchAnchor?.id == localID ? pitchAnchor : nil)
        let provider = worldTrackingProvider
        let removalTask = Task { [weak self] in
            if let provider, let anchor {
                try? await provider.removeAnchor(anchor)
            }
            guard let self else { return }
            sharedAnchorCache.removeValue(forKey: localID)
            locallyPlacedPitchAnchorID = nil
            placedPitchAnchorLocally = false
            if selectedSharedPitchAnchorID == localID {
                selectSharedPitchAnchor(id: nil)
            }
        }
        pitchAnchorRemovalTask = removalTask
        await removalTask.value
        pitchAnchorRemovalTask = nil
    }

    private func makeAnchorUpdatesTask(
        provider: WorldTrackingProvider
    ) -> Task<Void, Never> {
        Task { [weak self] in
            for await update in provider.anchorUpdates {
                guard let self, !Task.isCancelled else { return }
                handleAnchorUpdate(update)
            }
        }
    }

    private func makePoseSamplingTask(
        provider: WorldTrackingProvider
    ) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                sampleHorizontalHeadsetPose(with: provider)

                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }
    }



    private func handleAnchorUpdate(_ update: AnchorUpdate<WorldAnchor>) {
        let anchor = update.anchor
        guard anchor.id == locallyPlacedPitchAnchorID else {
            return
        }

        switch update.event {
        case .added:
            sharedAnchorCache[anchor.id] = anchor
            if selectedSharedPitchAnchorID == anchor.id {
                adopt(anchor)
            }

        case .updated:
            sharedAnchorCache[anchor.id] = anchor
            if selectedSharedPitchAnchorID == anchor.id {
                adopt(anchor)
            }

        case .removed:
            sharedAnchorCache.removeValue(forKey: anchor.id)
            guard selectedSharedPitchAnchorID == anchor.id else { return }
            if locallyPlacedPitchAnchorID == anchor.id {
                locallyPlacedPitchAnchorID = nil
            }
            pitchAnchor = nil
            sharedPitchAnchorID = nil
            pitchOriginTransform = nil
            placedPitchAnchorLocally = false
            isPitchAnchorTracked = false
            horizontalHeadsetPose = nil
            status = .waitingForSharedPitchAnchor
            onSelectedAnchorRemoved?(anchor.id)
        }
    }

    private func adopt(_ anchor: WorldAnchor) {
        pitchAnchor = anchor
        sharedPitchAnchorID = anchor.id
        pitchOriginTransform = anchor.originFromAnchorTransform
        isPitchAnchorTracked = anchor.isTracked
        placedPitchAnchorLocally = locallyPlacedPitchAnchorID == anchor.id
        if !anchor.isTracked {
            horizontalHeadsetPose = nil
            status = .localizingPitchAnchor
        }
    }

    private func sampleHorizontalHeadsetPose(with provider: WorldTrackingProvider) {
        guard arkitSession != nil else { return }
        guard let pitchAnchor else {
            horizontalHeadsetPose = nil
            status = .waitingForSharedPitchAnchor
            return
        }
        guard pitchAnchor.isTracked else {
            horizontalHeadsetPose = nil
            isPitchAnchorTracked = false
            status = .localizingPitchAnchor
            return
        }

        let sampleTime = CACurrentMediaTime()
        guard let deviceAnchor = provider.queryDeviceAnchor(atTimestamp: sampleTime),
              deviceAnchor.isTracked else {
            horizontalHeadsetPose = nil
            status = .localizingHeadset
            return
        }

        let anchorFromOrigin = simd_inverse(pitchAnchor.originFromAnchorTransform)
        let anchorFromHeadset = simd_mul(
            anchorFromOrigin,
            deviceAnchor.originFromAnchorTransform
        )
        let translation = anchorFromHeadset.columns.3

        // A RealityKit/ARKit camera looks along local -z. Project that direction onto the pitch.
        let forward = -SIMD3<Float>(
            anchorFromHeadset.columns.2.x,
            anchorFromHeadset.columns.2.y,
            anchorFromHeadset.columns.2.z
        )
        let horizontalForward = SIMD2<Float>(forward.x, forward.z)
        let yaw = simd_length_squared(horizontalForward) > 0.000_001
            ? atan2(horizontalForward.x, -horizontalForward.y)
            : (horizontalHeadsetPose?.yawRadians ?? 0)

        horizontalHeadsetPose = HorizontalHeadsetPose(
            x: translation.x,
            z: translation.z,
            yawRadians: yaw,
            sampledAt: sampleTime
        )
        isPitchAnchorTracked = true
        status = .trackingHeadsetRelativeToPitch
    }

    private func tearDownSession() {
        anchorUpdatesTask?.cancel()
        poseSamplingTask?.cancel()
        anchorUpdatesTask = nil
        poseSamplingTask = nil
        pitchAnchorRemovalTask?.cancel()
        pitchAnchorRemovalTask = nil

        arkitSession?.stop()
        arkitSession = nil
        worldTrackingProvider = nil
        pitchAnchor = nil
        locallyPlacedPitchAnchorID = nil
        selectedSharedPitchAnchorID = nil
        sharedAnchorCache.removeAll()

        horizontalHeadsetPose = nil
        sharedPitchAnchorID = nil
        pitchOriginTransform = nil
        isPitchAnchorTracked = false
        placedPitchAnchorLocally = false
        isPlacingPitchAnchor = false
    }
}

@available(visionOS 26.0, *)
extension LocalPitchAnchorCoordinator {
    enum CoordinatorError: LocalizedError {
        case worldTrackingNotRunning
        case headsetNotTracked
        case placementInProgress

        var errorDescription: String? {
            switch self {
            case .worldTrackingNotRunning:
                "Start world tracking in the immersive space before placing the pitch origin."
            case .headsetNotTracked:
                "The headset pose is not currently tracked."
            case .placementInProgress:
                "A shared pitch origin is already being placed."
            }
        }
    }
}
