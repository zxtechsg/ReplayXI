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
    private(set) var isRemovingPitchAnchor = false

    enum SurfaceDetectionStatus: Equatable, Sendable {
        case stopped, starting, scanning, ready
        case unavailable(String)
    }
    private(set) var surfaceDetectionStatus: SurfaceDetectionStatus = .stopped
    private(set) var horizontalSurfaces: [ReplayPitchSurfaceSnap.Surface] = []
    /// Observe this small token, not triangle arrays, during playback updates.
    private(set) var surfaceRevision: UInt = 0

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
    @ObservationIgnored private var sessionStartTask: Task<Void, Never>?
    @ObservationIgnored private var pitchAnchorRemovalTask: Task<Void, Never>?
    @ObservationIgnored private var sessionRevision = UUID()
    @ObservationIgnored private var placementIntentRevision = UUID()
    @ObservationIgnored private var trackingOwnerID: UUID?
    @ObservationIgnored private var trackingRequestRevision = UUID()
    @ObservationIgnored private var planeDetectionProvider: PlaneDetectionProvider?
    @ObservationIgnored private var surfaceUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var surfaceEventsTask: Task<Void, Never>?
    @ObservationIgnored private var surfaceStartTask: Task<Void, Never>?
    @ObservationIgnored private var surfaceStopTask: Task<Void, Never>?
    @ObservationIgnored private var surfaceRequestRevision = UUID()
    @ObservationIgnored private var surfaceAuthorizationAllowed = false

    var currentWorldDeviceTransform: simd_float4x4? {
        guard let provider = worldTrackingProvider,
              let device = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              device.isTracked else { return nil }
        return device.originFromAnchorTransform
    }

    /// Called only by the Room/table surface action. An active physical drill
    /// cannot replace its providers or surrender ownership to a surface scan.
    func startSurfaceDetection(for ownerID: UUID) async {
        guard !Task.isCancelled else { return }
        guard !placedPitchAnchorLocally, !isPlacingPitchAnchor, !isRemovingPitchAnchor else {
            surfaceDetectionStatus = .unavailable("End physical practice before finding a surface.")
            return
        }
        await surfaceStopTask?.value
        guard !Task.isCancelled else { return }
        await start(for: ownerID)
        guard !Task.isCancelled, ownsTracking(for: ownerID) else { return }
        guard let session = arkitSession, let world = worldTrackingProvider else {
            surfaceDetectionStatus = .unavailable("Surface detection is unavailable. The pitch keeps its last position.")
            return
        }
        guard world.state != .stopped else {
            surfaceDetectionStatus = .unavailable("Tracking stopped. Reopen the room to find surfaces again.")
            return
        }
        guard PlaneDetectionProvider.isSupported else {
            surfaceDetectionStatus = .unavailable("Surface detection needs a supported headset. Use the default level pitch.")
            return
        }
        if surfaceStartTask?.isCancelled == true { surfaceStartTask = nil }
        if let surfaceStartTask { await surfaceStartTask.value; return }
        let revision = sessionRevision
        let request = UUID()
        surfaceRequestRevision = request
        surfaceDetectionStatus = .starting
        let startup = Task { [weak self] in
            guard let self else { return }
            defer { if surfaceRequestRevision == request { surfaceStartTask = nil } }
            do {
                let authorization = try await withSessionLifetime {
                    await session.requestAuthorization(for: [.worldSensing])
                }
                guard surfaceRequestRevision == request, ownsTracking(for: ownerID) else { return }
                guard authorization[.worldSensing] == .allowed else {
                    surfaceAuthorizationAllowed = false
                    clearSurfaceGeometry()
                    surfaceDetectionStatus = .unavailable("World sensing is off. Allow it in Settings to snap, or use the default level pitch.")
                    return
                }
                surfaceAuthorizationAllowed = true
                guard !placedPitchAnchorLocally, !isPlacingPitchAnchor, !isRemovingPitchAnchor else {
                    surfaceDetectionStatus = .unavailable("End physical practice before finding a surface.")
                    return
                }
                let planes: PlaneDetectionProvider
                if let existing = planeDetectionProvider, existing.state == .running {
                    planes = existing
                } else {
                    planes = PlaneDetectionProvider(alignments: [.horizontal])
                    planeDetectionProvider = planes
                    // Retain the exact running world provider. ARKit stops only
                    // providers omitted from this array; do not restart it.
                    try await withSessionLifetime { try await session.run([world, planes]) }
                }
                guard surfaceRequestRevision == request, ownsTracking(for: ownerID) else { return }
                clearSurfaceGeometry()
                surfaceDetectionStatus = .scanning
                for anchor in planes.allAnchors { receiveSurface(anchor) }
                surfaceUpdatesTask?.cancel()
                surfaceUpdatesTask = Task { [weak self] in
                    for await update in planes.anchorUpdates {
                        guard let self, !Task.isCancelled, sessionRevision == revision,
                              surfaceRequestRevision == request, ownsTracking(for: ownerID) else { return }
                        switch update.event {
                        case .added, .updated: receiveSurface(update.anchor)
                        case .removed: removeSurface(id: update.anchor.id)
                        @unknown default: break
                        }
                    }
                }
                surfaceEventsTask?.cancel()
                surfaceEventsTask = Task { [weak self] in
                    for await event in session.events {
                        guard let self, !Task.isCancelled, sessionRevision == revision,
                              surfaceRequestRevision == request, ownsTracking(for: ownerID) else { return }
                        switch event {
                        case .authorizationChanged(type: .worldSensing, status: let status) where status != .allowed:
                            surfaceAuthorizationAllowed = false
                            clearSurfaceGeometry()
                            surfaceDetectionStatus = .unavailable("World sensing is off. The pitch keeps its last position.")
                        case .dataProviderStateChanged(let providers, let state, _) where providers.contains(where: { $0 === planes }):
                            if state == .running, surfaceAuthorizationAllowed {
                                surfaceDetectionStatus = .scanning
                                for anchor in planes.allAnchors { receiveSurface(anchor) }
                            } else {
                                clearSurfaceGeometry()
                                surfaceDetectionStatus = .unavailable("Surface tracking paused. Find surfaces again; the pitch keeps its last position.")
                            }
                        default: break
                        }
                    }
                }
            } catch {
                guard sessionRevision == revision, surfaceRequestRevision == request,
                      ownsTracking(for: ownerID) else { return }
                clearSurfaceGeometry()
                surfaceDetectionStatus = error is CancellationError ? .stopped
                    : .unavailable("Surface detection could not start. The pitch keeps its last position.")
            }
        }
        surfaceStartTask = startup
        await startup.value
    }

    /// Stop plane sensing while preserving any running world-tracking provider.
    /// A late stop belonging to an old room cannot change a new room's session.
    func stopSurfaceDetection(for ownerID: UUID) async {
        guard ownsTracking(for: ownerID) else { return }
        if let surfaceStopTask { await surfaceStopTask.value; return }
        invalidateSurfaceScan()
        let pendingStart = surfaceStartTask
        surfaceStartTask = nil
        let revision = sessionRevision, request = surfaceRequestRevision
        let operation = Task { [weak self] in
            await pendingStart?.value
            guard let self, sessionRevision == revision, surfaceRequestRevision == request,
                  ownsTracking(for: ownerID) else { return }
            defer { if surfaceRequestRevision == request { surfaceStopTask = nil } }
            // Physical practice may have begun during authorization. Leave its
            // provider set alone; room teardown will stop the remaining planes.
            guard !placedPitchAnchorLocally, !isPlacingPitchAnchor, !isRemovingPitchAnchor,
                  planeDetectionProvider != nil, let session = arkitSession,
                  let world = worldTrackingProvider else { return }
            planeDetectionProvider = nil
            guard world.state != .stopped else { return }
            try? await withSessionLifetime { try await session.run([world]) }
        }
        surfaceStopTask = operation
        await operation.value
    }

    /// Re-evaluate at the explicit Snap action; a removed plane cannot be
    /// committed from an old UI candidate. This never moves the control bar.
    func snapPitchToSurface(near position: SIMD3<Float>, yawRadians: Float,
                            footprint: SIMD2<Float> = ReplayPitchSurfaceSnap.defaultFootprint,
                            bottomOffset: Float = ReplayPitchSurfaceSnap.defaultBottomOffset,
                            preferredSurfaceID: UUID? = nil) -> ReplayPitchSurfaceSnap.Placement? {
        guard planeDetectionProvider?.state == .running, surfaceAuthorizationAllowed, surfaceDetectionStatus == .ready,
              !placedPitchAnchorLocally, !isPlacingPitchAnchor, !isRemovingPitchAnchor else { return nil }
        return ReplayPitchSurfaceSnap.placement(on: horizontalSurfaces, near: position,
            yawRadians: yawRadians, footprint: footprint, bottomOffset: bottomOffset,
            preferredSurfaceID: preferredSurfaceID)
    }

    private func receiveSurface(_ anchor: PlaneAnchor) {
        guard surfaceAuthorizationAllowed else { return }
        guard let surface = ReplayPitchSurfaceSnap.surface(from: anchor) else {
            removeSurface(id: anchor.id)
            return
        }
        horizontalSurfaces.removeAll { $0.id == anchor.id }
        horizontalSurfaces.append(surface)
        surfaceRevision &+= 1
        surfaceDetectionStatus = .ready
    }

    private func removeSurface(id: UUID) {
        guard horizontalSurfaces.contains(where: { $0.id == id }) else { return }
        horizontalSurfaces.removeAll { $0.id == id }
        surfaceRevision &+= 1
        surfaceDetectionStatus = horizontalSurfaces.isEmpty ? .scanning : .ready
    }

    private func clearSurfaceGeometry() {
        horizontalSurfaces.removeAll()
        surfaceRevision &+= 1
    }

    private func invalidateSurfaceScan() {
        surfaceRequestRevision = UUID()
        surfaceAuthorizationAllowed = false
        surfaceStartTask?.cancel()
        surfaceUpdatesTask?.cancel(); surfaceUpdatesTask = nil
        surfaceEventsTask?.cancel(); surfaceEventsTask = nil
        clearSurfaceGeometry()
        surfaceDetectionStatus = .stopped
    }

    func ownsTracking(for ownerID: UUID) -> Bool {
        trackingOwnerID == ownerID
    }

    /// A room claims tracking before any suspension. A returning room may reuse
    /// a running provider, but never another room's anchor or pending teardown.
    func claimTracking(for ownerID: UUID) {
        if let previous = trackingOwnerID, previous != ownerID {
            invalidateSurfaceScan()
            retireLocallyPlacedPitchAnchor()
        }
        trackingOwnerID = ownerID
        trackingRequestRevision = UUID()
    }

    /// Capture ownership now, not inside a deferred view-cleanup task. A new
    /// owner can reuse tracking while removal finishes; that defeats this stop.
    @discardableResult
    func stopTracking(for ownerID: UUID) -> Task<Void, Never>? {
        guard ownsTracking(for: ownerID) else { return nil }
        trackingOwnerID = nil
        invalidateSurfaceScan()
        trackingRequestRevision = UUID()
        let request = trackingRequestRevision
        let revision = sessionRevision
        let removal = retireLocallyPlacedPitchAnchor()
        return Task { [weak self] in
            await removal?.value
            guard let self, trackingOwnerID == nil,
                  trackingRequestRevision == request,
                  sessionRevision == revision else { return }
            stop()
        }
    }

    /// ARKit calls can finish after stop/restart. Never accept their result in a
    /// different session, even when the underlying provider ignores cancellation.
    func withSessionLifetime<Value>(
        _ operation: () async throws -> Value
    ) async throws -> Value {
        let revision = sessionRevision
        try Task.checkCancellation()
        let outcome: Result<Value, Error>
        do {
            outcome = .success(try await operation())
        } catch {
            outcome = .failure(error)
        }
        // Failure can arrive just as late as success. Check the lifetime before
        // exposing either outcome to a new room/preflight's error presentation.
        try Task.checkCancellation()
        guard sessionRevision == revision else { throw CancellationError() }
        return try outcome.get()
    }

    /// Ending a drill cancels placement intent without stopping world tracking.
    /// In particular, an add that finishes after End drill must not re-place it.
    func withPlacementLifetime<Value>(
        _ operation: () async throws -> Value,
        cleanupOnFailure: () async -> Void = {}
    ) async throws -> Value {
        let revision = sessionRevision
        let intent = placementIntentRevision
        try Task.checkCancellation()
        do {
            let result = try await withSessionLifetime(operation)
            guard placementIntentRevision == intent else { throw CancellationError() }
            return result
        } catch {
            // Cleanup belongs to the original provider/anchor. It may itself
            // suspend across End drill or a restart, so validate again after it.
            await cleanupOnFailure()
            try Task.checkCancellation()
            guard sessionRevision == revision, placementIntentRevision == intent else {
                throw CancellationError()
            }
            throw error
        }
    }

    /// Starts world tracking. Call this only while the app presents a Full Space.
    func start(for ownerID: UUID) async {
        guard !Task.isCancelled else { return }
        claimTracking(for: ownerID)
        if arkitSession != nil {
            // Startup belongs to the coordinator, not the disappearing view's
            // task. Reopening during run() waits for the same provider startup.
            await sessionStartTask?.value
            return
        }
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

        // World tracking alone needs no scene reconstruction or planes.
        await runSessionStartup { try await session.run([provider]) }
    }

    /// One coordinator-owned startup is shared by any returning room. Cancelling
    /// a view waiting on it must not cancel a provider another room now needs.
    func runSessionStartup(_ operation: @escaping @MainActor () async throws -> Void) async {
        if let sessionStartTask {
            await sessionStartTask.value
            return
        }
        let revision = sessionRevision
        let startup = Task { [weak self] in
            guard let self, sessionRevision == revision else { return }
            defer {
                if sessionRevision == revision { sessionStartTask = nil }
            }
            do {
                try await withSessionLifetime(operation)
                if status == .starting { status = .waitingForSharedPitchAnchor }
            } catch {
                guard sessionRevision == revision else { return }
                tearDownSession()
                status = error is CancellationError ? .stopped
                    : .unavailable("World tracking could not start: \(error.localizedDescription)")
            }
        }
        sessionStartTask = startup
        await startup.value
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
        guard !isPlacingPitchAnchor, pitchAnchorRemovalTask == nil else {
            throw CoordinatorError.placementInProgress
        }
        let revision = sessionRevision
        let intent = placementIntentRevision
        isPlacingPitchAnchor = true
        defer {
            if sessionRevision == revision { isPlacingPitchAnchor = false }
        }

        let previousAnchor = pitchAnchor
        let newAnchor = WorldAnchor(
            originFromAnchorTransform: transform
        )

        try await withPlacementLifetime({
            try await provider.addAnchor(newAnchor)
        }, cleanupOnFailure: {
            // Also covers cancellation after a successful add. Keep this await
            // inside the lifetime gate so it cannot publish a stale error.
            try? await provider.removeAnchor(newAnchor)
        })

        recordLocalPlacement(newAnchor)

        if let previousAnchor, previousAnchor.id != newAnchor.id {
            try? await provider.removeAnchor(previousAnchor)
            guard sessionRevision == revision, placementIntentRevision == intent else {
                throw CancellationError()
            }
            sharedAnchorCache.removeValue(forKey: previousAnchor.id)
            if Task.isCancelled {
                await removeLocallyPlacedPitchAnchor()
                throw CancellationError()
            }
        }

        return newAnchor.id
    }

    /// Commits one admitted local anchor, synchronously and without suspension.
    func recordLocalPlacement(_ anchor: WorldAnchor) {
        selectedSharedPitchAnchorID = anchor.id
        sharedAnchorCache[anchor.id] = anchor
        pitchAnchor = anchor
        sharedPitchAnchorID = anchor.id
        pitchOriginTransform = anchor.originFromAnchorTransform
        locallyPlacedPitchAnchorID = anchor.id
        placedPitchAnchorLocally = true
        isPitchAnchorTracked = anchor.isTracked
        horizontalHeadsetPose = nil
        status = .localizingPitchAnchor
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
    func removeLocallyPlacedPitchAnchor(ifMatching expectedID: UUID? = nil) async {
        await retireLocallyPlacedPitchAnchor(ifMatching: expectedID)?.value
    }

    /// Clears ownership synchronously, then removes the captured anchor from its
    /// original provider. Safe to call directly from a view or Store callback.
    @discardableResult
    func retireLocallyPlacedPitchAnchor(ifMatching expectedID: UUID? = nil) -> Task<Void, Never>? {
        // A dismissed UI request may finish after a new one has placed an
        // anchor. Its cleanup owns only the returned ID, not the current drill.
        if let expectedID, locallyPlacedPitchAnchorID != expectedID { return nil }
        // Invalidate even if addAnchor has not returned an ID to publish yet.
        placementIntentRevision = UUID()
        if let pitchAnchorRemovalTask {
            return pitchAnchorRemovalTask
        }
        guard let localID = locallyPlacedPitchAnchorID else { return nil }
        let anchor = sharedAnchorCache[localID]
            ?? (pitchAnchor?.id == localID ? pitchAnchor : nil)
        let provider = worldTrackingProvider
        let revision = sessionRevision

        // Retire app state before asking ARKit to remove it. Otherwise its
        // .removed event can be misreported as unexpected tracking loss.
        sharedAnchorCache.removeValue(forKey: localID)
        locallyPlacedPitchAnchorID = nil
        placedPitchAnchorLocally = false
        if selectedSharedPitchAnchorID == localID {
            selectSharedPitchAnchor(id: nil)
        }

        isRemovingPitchAnchor = true
        let removalTask = Task { [weak self] in
            if let provider, let anchor {
                try? await provider.removeAnchor(anchor)
            }
            if let self, sessionRevision == revision {
                pitchAnchorRemovalTask = nil
                isRemovingPitchAnchor = false
            }
        }
        pitchAnchorRemovalTask = removalTask
        return removalTask
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
        // Invalidate before stopping providers, so delayed completions are stale.
        sessionRevision = UUID()
        invalidateSurfaceScan()
        surfaceStartTask = nil
        surfaceStopTask?.cancel(); surfaceStopTask = nil
        planeDetectionProvider = nil
        trackingOwnerID = nil
        trackingRequestRevision = UUID()
        sessionStartTask?.cancel()
        sessionStartTask = nil
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
        isRemovingPitchAnchor = false
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
                "Wait for the current pitch origin change to finish."
            }
        }
    }
}
