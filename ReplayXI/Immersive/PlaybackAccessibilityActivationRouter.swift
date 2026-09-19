import Foundation
import RealityKit

/// The scene's actual accessibility event path, kept separate from SwiftUI so
/// semantic actions can be exercised with the same Store and RealityKit targets.
@MainActor
enum PlaybackAccessibilityActivationRouter {
    static func handle(
        _ event: AccessibilityEvents.Activate,
        store: ReplayStore,
        roomPresentationID: UUID,
        hasActiveDrawingStroke: Bool,
        selectAnnotation: (UUID) -> Void
    ) {
        guard store.roomPresentation.acceptsInteraction(for: roomPresentationID) else { return }
        guard PlaybackSpatialInteractionPolicy.acceptsPitchInteraction(
            hasActiveEndpointPreview: store.hasActiveCoachMarkGeometryPreview,
            hasActiveTimelineScrub: store.hasActiveTimelineScrub
        ) else { return }

        let entity = event.entity
        // A semantic event can retain a target from an earlier presentation.
        // Never let it interrupt a held stroke or address a hidden/old scene.
        guard !hasActiveDrawingStroke,
              entity.isEnabledInHierarchy,
              belongsToCurrentMatch(entity, scenarioID: store.selectedScenarioID)
        else { return }
        if let annotationTarget = AnnotationSceneAffordance.targetAncestor(of: entity) {
            guard !store.isDrawing,
                  let mark = store.marks.first(where: { $0.id == annotationTarget.markID })
            else { return }
            selectAnnotation(annotationTarget.markID)
            selectSpatialAnnotation(mark, in: store)
            return
        }

        guard let playerID = playerIDAncestor(of: entity),
              store.selectedScenario.player(id: playerID) != nil else { return }
        if store.isDrawing {
            // Label is an atomic, one-player action. Other tools keep their
            // spatial stroke/two-point owner and must not switch the POV.
            guard store.selectedTool == .playerLabel else { return }
            store.labelPlayer(playerID)
            return
        }
        store.openLocalPlayerPOV(playerID)
    }

    private static func belongsToCurrentMatch(_ entity: Entity, scenarioID: String) -> Bool {
        let expectedName = "match-root-\(scenarioID)"
        var cursor: Entity? = entity
        while let current = cursor {
            if current.name.hasPrefix("match-root-") {
                return current.name == expectedName
            }
            cursor = current.parent
        }
        return false
    }

    static func playerIDAncestor(of entity: Entity) -> String? {
        if let decisionPlayerID = DecisionOptionSceneOverlay.playerIDAncestor(of: entity) {
            return decisionPlayerID
        }
        var cursor: Entity? = entity
        while let current = cursor {
            let labelPrefix = "player-label-"
            if current.name.hasPrefix(labelPrefix) {
                return String(current.name.dropFirst(labelPrefix.count))
            }
            let prefix = "player-"
            if current.name.hasPrefix(prefix) {
                return String(current.name.dropFirst(prefix.count))
            }
            cursor = current.parent
        }
        return nil
    }

    /// Select the pose the user actually hit. Seeking to In would move an
    /// animated mark underneath the next edit and modify the wrong timestamp.
    /// Authored overlays retain their existing review-from-In action.
    static func selectSpatialAnnotation(_ mark: CoachMark, in store: ReplayStore) {
        guard store.canChangePlaybackView,
              let current = store.marks.first(where: { $0.id == mark.id }) else { return }
        let isCoachAnimation = current.hasAnimatedGeometry
            && !store.selectedScenario.coachMarks.contains { $0.id == current.id }
        guard isCoachAnimation else {
            reviewAnnotation(current, in: store)
            return
        }
        if store.localRole == .player {
            _ = store.beginLocalReview(at: store.playhead)
        } else {
            store.setPlaying(false, broadcast: store.localRole == .coach)
        }
    }

    static func reviewAnnotation(_ mark: CoachMark, in store: ReplayStore) {
        // Keep existing local/shared transport semantics for annotation review.
        if store.localRole == .player {
            _ = store.beginLocalReview(at: mark.revealTime)
            return
        }
        store.setPlaying(false, broadcast: false)
        store.seek(to: mark.revealTime, broadcast: store.localRole == .coach)
    }
}
