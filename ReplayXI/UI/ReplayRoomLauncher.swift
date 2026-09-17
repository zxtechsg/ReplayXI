import SwiftUI

/// Shared room admission for the dashboard and the video comparison window.
/// One entry path keeps cancellation, physics validation and save handling equal.
@MainActor
enum ReplayRoomLauncher {
    static func prepareVisuals(for scenarios: [ReplayScenario]) throws {
        // Meshes and geometric shirt digits are finite and shared.
        // Warm them before RealityView starts its frame loop so the
        // first close player or impact cue cannot hitch playback.
        try ReplayAthleteFactory.prewarm(
            for: scenarios.flatMap(\.players),
            lods: [.near, .far]
        )
        // An explicit developer opt-in may admit one hash-locked CC0
        // skinned athlete for profiling. The pilot is fail-soft and
        // never blocks the room. It remains separate from the licensed
        // Rocketbox body and the procedural football-action fallback.
        _ = try? ReplayImportedAthleteProvider.prewarm()
        // The licensed single-skeleton body is prepared once before
        // presentation. Failed admission keeps the working fallback.
        do {
            try ReplaySkinnedAthleteProvider.prewarm()
        } catch {
            #if DEBUG
            print("Replay XI skinned-player preparation failed; using standard rig: \(error)")
            #endif
        }
        // Neighbours use the cheaper canonical skin only inside the
        // existing four-player budget. Its complete contact profile
        // and shared kit materials are prepared once, not per frame.
        do {
            try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        } catch {
            #if DEBUG
            print("Replay XI low-detail players unavailable; keeping existing player visuals: \(error)")
            #endif
        }
        // Distant players share one static face and the existing skin
        // palettes. No extra skeleton or per-frame resource load.
        do {
            try ReplayFarAthleteHeadProvider.prewarm()
        } catch {
            #if DEBUG
            print("Replay XI distant-player faces unavailable; keeping standard heads: \(error)")
            #endif
        }
        // Original Blender anatomy bends at knees/elbows while
        // retaining the far family's seven-model budget. Preparation
        // is explicit; a failed asset keeps the established fallback.
        do {
            try ReplayArticulatedFarProvider.prewarm()
        } catch {
            #if DEBUG
            print("Replay XI articulated players unavailable; keeping standard bodies: \(error)")
            #endif
        }
        // Optional original kit maps share six tiny textures across
        // the whole squad. Missing maps retain the solid team colours.
        _ = try? ReplayArticulatedFarKitProvider.prewarm()
        // Optional visual admission; a missing/corrupt asset retains the
        // procedural ball without blocking playback or loading per frame.
        do {
            try ReplayStrategyBallProvider.prewarm()
        } catch {
            #if DEBUG
            print("Replay XI Blender ball unavailable; using standard ball: \(error)")
            #endif
        }
        do {
            try ReplayStrategyPitchProvider.prewarm()
        } catch {
            #if DEBUG
            print("Replay XI Blender pitch unavailable; using standard pitch: \(error)")
            #endif
        }
    }

    static func open(store: ReplayStore, openImmersiveSpace: OpenImmersiveSpaceAction,
                     dismissWindow: DismissWindowAction) {
        guard let requestID = store.beginImmersiveOpen() else { return }
        Task {
            do {
                try prepareVisuals(for: store.scenarios)
            } catch {
                guard store.completeImmersiveOpen(requestID, opened: false) else { return }
                store.statusMessage = "Player renderer could not prepare. Try opening the room again."
                return
            }
            await Task.yield()
            guard store.roomPresentation.isOpeningRequest(requestID) else { return }
            // Prepare only the selected study. The room has its own cancellable
            // admission gate for later switches and restored reviews. Older
            // demonstrations retain their original authored paths.
            store.statusMessage = "Preparing ball physics…"
            let toPrepare = FootballReferenceScenarios.contains(store.selectedScenario)
                ? [store.selectedScenario] : []
            do {
                for scenario in toPrepare {
                    guard store.roomPresentation.isOpeningRequest(requestID) else { return }
                    let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
                        plannedTouches: FootballReferenceScenarios.touches(for: scenario))
                    guard recording.missedTouchCount == 0 else {
                        throw ReplayNativeBallPhysics.Failure.invalidInput
                    }
                }
            } catch {
                guard store.completeImmersiveOpen(requestID, opened: false) else { return }
                store.statusMessage = "Ball physics could not prepare. Please try again."
                return
            }
            guard store.roomPresentation.isOpeningRequest(requestID) else { return }
            store.statusMessage = "Opening spatial replay…"
            let result = await openImmersiveSpace(id: "ReplayRoom", value: requestID)
            guard store.completeImmersiveOpen(requestID, opened: result == .opened) else { return }
            if result == .opened {
                dismissWindow(id: "ReplayDashboard")
            } else {
                store.statusMessage = "The immersive room did not open. Try again."
            }
        }
    }
}
