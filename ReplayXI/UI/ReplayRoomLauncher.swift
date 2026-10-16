import SwiftUI

/// Shared room admission for the dashboard and the video comparison window.
/// One entry path keeps cancellation, physics validation and save handling equal.
@MainActor
enum ReplayRoomLauncher {
    enum OpenResult: Equatable { case opened, cancelled, failed }
    private enum PreparationFailure: Error { case players, ball }
    private struct PendingOpen {
        let requestID: UUID
        let task: Task<Void, Never>
        var isPreparing = true
    }
    private static var pendingOpens: [ObjectIdentifier: PendingOpen] = [:]
    static func prepareVisuals(
        for scenarios: [ReplayScenario],
        shouldContinue: () -> Bool = { true },
        progress: (String) -> Void = { _ in }
    ) async throws {
        try await ReplayVisualPreparation.run(shouldContinue: shouldContinue, progress: progress) { step in
            switch step {
            case .environment: ReplayStadiumEnvironment.prewarm()
            case .stadium: prepareOptional("stadium") { try ReplayStadiumAssetProvider.prewarm() }
            case .athleteMeshes:
                // Keep fallback/impact meshes ready, but only this scenario's
                // shirt numbers and palettes. No per-player rigs are built.
                try ReplayAthleteFactory.prewarm(
                    for: scenarios.flatMap(\.players),
                    lods: [.near, .far]
                )
            case .importedPilot: prepareOptional("imported pilot") { _ = try ReplayImportedAthleteProvider.prewarm() }
            case .tripoPlayers:
                prepareOptional("Tripo players") { try ReplayTripoAthleteProvider.prewarm() }
            case .fallbackPlayers:
                if !ReplayTripoAthleteProvider.isPrewarmed {
                    prepareOptional("fallback players") {
                        try ReplaySkinnedAthleteProvider.prewarm()
                        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
                    }
                }
            case .farHeads: prepareOptional("distant heads") { try ReplayFarAthleteHeadProvider.prewarm() }
            case .articulatedBodies:
                prepareOptional("articulated bodies") { try ReplayArticulatedFarProvider.prewarm() }
            case .farKits: prepareOptional("distant kits") { try ReplayArticulatedFarKitProvider.prewarm() }
            case .ball: prepareOptional("ball") { try ReplayStrategyBallProvider.prewarm() }
            case .pitch: prepareOptional("pitch") { try ReplayStrategyPitchProvider.prewarm() }
            }
        }
    }

    private static func prepareOptional(_ name: String, _ prepare: () throws -> Void) {
        do { try prepare() } catch {
            #if DEBUG
            print("Replay XI \(name) unavailable; keeping fallback: \(error)")
            #endif
        }
    }

    static func open(
        store: ReplayStore, openImmersiveSpace: OpenImmersiveSpaceAction,
        dismissWindow: DismissWindowAction,
        annotationEntry: ReplayAnnotationEntrySession? = nil
    ) {
        let scenario = store.selectedScenario
        begin(
            store: store, annotationEntry: annotationEntry,
            prepare: { requestID in
                do {
                    try await prepareVisuals(
                        for: [scenario],
                        shouldContinue: {
                            store.roomPresentation.isOpeningRequest(requestID)
                                && store.selectedScenarioID == scenario.id
                        }, progress: { store.statusMessage = $0 })
                } catch is CancellationError { throw CancellationError() } catch { throw PreparationFailure.players }
                try Task.checkCancellation()
                if FootballReferenceScenarios.contains(scenario) {
                    store.statusMessage = "Preparing ball physics…"
                    do {
                        let recording = try await ReplayNativeBallPhysics.prewarm(
                            track: scenario.ball,
                            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario)
                        )
                        guard NativeReplaySceneAdmission.isUsable(recording) else {
                            throw PreparationFailure.ball
                        }
                    } catch is CancellationError { throw CancellationError() } catch { throw PreparationFailure.ball }
                }
            },
            openRoom: { requestID in
                switch await openImmersiveSpace(id: "ReplayRoom", value: requestID) {
                case .opened: .opened
                case .userCancelled: .cancelled
                case .error: .failed
                @unknown default: .failed
                }
            }, didOpen: { dismissWindow(id: "ReplayDashboard") })
    }

    /// Only pending preparation is cancellable here. Once the system is
    /// presenting its room, its result/appearance callbacks retain ownership.
    static func canCancelPendingOpen(for store: ReplayStore) -> Bool {
        guard let pending = pendingOpens[ObjectIdentifier(store)] else { return false }
        return pending.isPreparing && store.roomPresentation.isOpeningRequest(pending.requestID)
    }

    @discardableResult
    static func cancelPendingOpen(for store: ReplayStore) -> Bool {
        let key = ObjectIdentifier(store)
        guard canCancelPendingOpen(for: store), let pending = pendingOpens[key]
        else { return false }
        pending.task.cancel()
        guard store.completeImmersiveOpen(pending.requestID, opened: false) else { return false }
        store.statusMessage = "Opening cancelled"
        return true
    }

    /// Closure-based system boundary also lets lifecycle tests prove stale
    /// completions cannot reopen a room or dismiss a newer dashboard.
    @discardableResult
    static func begin(
        store: ReplayStore, annotationEntry: ReplayAnnotationEntrySession? = nil,
        prepare: @escaping @MainActor (UUID) async throws -> Void,
        openRoom: @escaping @MainActor (UUID) async -> OpenResult,
        didOpen didOpenCallback: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>? {
        if annotationEntry != nil, let reason = ReplayAnnotationEntryPolicy.blockReason(in: store) {
            store.statusMessage = reason
            return nil
        }
        guard let requestID = store.beginImmersiveOpen() else { return nil }
        let key = ObjectIdentifier(store)
        let scenarioID = store.selectedScenarioID
        annotationEntry?.request(roomID: requestID, scenarioID: scenarioID)
        let task = Task { @MainActor in
            var didOpen = false
            defer {
                if !didOpen { annotationEntry?.cancel(roomID: requestID) }
                if pendingOpens[key]?.requestID == requestID { pendingOpens[key] = nil }
            }
            do {
                try Task.checkCancellation()
                try await prepare(requestID)
                try Task.checkCancellation()
            } catch is CancellationError {
                if store.completeImmersiveOpen(requestID, opened: false) {
                    store.statusMessage = "Opening cancelled"
                }
                return
            } catch {
                guard store.completeImmersiveOpen(requestID, opened: false) else { return }
                switch error {
                case PreparationFailure.players:
                    store.statusMessage = "Player renderer could not prepare. Try opening the room again."
                case PreparationFailure.ball:
                    store.statusMessage = "Ball physics could not prepare. Please try again."
                default:
                    store.statusMessage = "Replay could not prepare. Please try again."
                }
                return
            }
            guard store.roomPresentation.isOpeningRequest(requestID) else { return }
            guard store.selectedScenarioID == scenarioID else {
                _ = store.completeImmersiveOpen(requestID, opened: false)
                store.statusMessage = "Replay changed. Open the room again."
                return
            }
            pendingOpens[key]?.isPreparing = false
            store.statusMessage = "Opening spatial replay…"
            let result = await openRoom(requestID)
            guard store.completeImmersiveOpen(requestID, opened: result == .opened) else { return }
            if result == .opened {
                didOpen = true
                didOpenCallback()
            } else {
                store.statusMessage =
                    result == .cancelled
                    ? "Opening cancelled"
                    : "The immersive room did not open. Try again."
            }
        }
        pendingOpens[key] = PendingOpen(requestID: requestID, task: task)
        return task
    }
}
