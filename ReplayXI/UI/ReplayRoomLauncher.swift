import SwiftUI

/// Shared room admission for the dashboard and the video comparison window.
/// One entry path keeps cancellation, physics validation and save handling equal.
@MainActor
enum ReplayRoomLauncher {
    static func prepareVisuals(for scenarios: [ReplayScenario]) throws {
        ReplayStadiumEnvironment.prewarm()
        // The supplied bowl is optional; missing or changed scenery keeps the
        // low-cost local fallback without blocking replay or annotations.
        _ = try? ReplayStadiumAssetProvider.prewarm()
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
        // Admit the new FBX-derived players only as a complete, hash-checked
        // near/low set. Missing or incompatible assets retain the old renderer.
        do {
            try ReplayTripoAthleteProvider.prewarm()
        } catch {
            #if DEBUG
            print("Replay XI Tripo players unavailable; using existing players: \(error)")
            #endif
        }
        if !ReplayTripoAthleteProvider.isPrewarmed {
            do {
                try ReplaySkinnedAthleteProvider.prewarm()
                try ReplaySkinnedAthleteProvider.prewarmLowDetail()
            } catch {
                #if DEBUG
                print("Replay XI skinned-player preparation failed; using standard rig: \(error)")
                #endif
            }
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
                     dismissWindow: DismissWindowAction,
                     annotationEntry: ReplayAnnotationEntrySession? = nil) {
        if annotationEntry != nil, let reason = ReplayAnnotationEntryPolicy.blockReason(in: store) {
            store.statusMessage = reason
            return
        }
        guard let requestID = store.beginImmersiveOpen() else { return }
        annotationEntry?.request(roomID: requestID, scenarioID: store.selectedScenarioID)
        Task {
            var didOpen = false
            defer {
                if !didOpen { annotationEntry?.cancel(roomID: requestID) }
            }
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
                didOpen = true
                dismissWindow(id: "ReplayDashboard")
            } else {
                store.statusMessage = "The immersive room did not open. Try again."
            }
        }
    }
}
