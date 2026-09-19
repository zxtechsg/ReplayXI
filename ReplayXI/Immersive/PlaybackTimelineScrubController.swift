import CoreGraphics
import Foundation
import Observation

/// An end callback may finish this rail's live transaction, never start one
/// or take over a replacement scrub owned by another control surface.
@MainActor @Observable
final class PlaybackTimelineScrubController {
    private(set) var state: PlaybackTimelineScrub.GestureState?
    private(set) var storeScrubID: UUID?

    private func ownsScrub(in store: ReplayStore) -> Bool {
        storeScrubID != nil && storeScrubID == store.activeTimelineScrubID && store.hasActiveTimelineScrub
    }

    @discardableResult
    func preview(in store: ReplayStore, startLocation: CGFloat, railWidth: CGFloat,
                 translation: CGSize) -> Bool {
        guard valid(railWidth: railWidth, translation: translation), startLocation.isFinite,
              !store.isDrawing, !store.hasActiveCoachMarkGeometryPreview else {
            cancel(in: store)
            return false
        }
        let previous: PlaybackTimelineScrub.GestureState
        if let state {
            guard ownsScrub(in: store) else { reset(); return false }
            previous = state
        } else {
            guard !store.hasActiveTimelineScrub, store.beginTimelineScrub(),
                  let id = store.activeTimelineScrubID else { return false }
            storeScrubID = id
            previous = PlaybackTimelineScrub.begin(atRailLocation: startLocation,
                duration: store.selectedScenario.duration, railWidth: railWidth)
        }
        let updated = PlaybackTimelineScrub.update(previous, duration: store.selectedScenario.duration,
            railWidth: railWidth, horizontalTranslation: translation.width, verticalTranslation: translation.height)
        guard store.previewTimelineScrub(to: updated.time) else { cancel(in: store); return false }
        state = updated
        return true
    }

    @discardableResult
    func finish(in store: ReplayStore, railWidth: CGFloat, translation: CGSize) -> Bool {
        // The Store may already have cancelled this rail during exit or a
        // scenario transition. A late/duplicate end must leave it untouched.
        guard let state, ownsScrub(in: store) else { reset(); return false }
        guard valid(railWidth: railWidth, translation: translation),
              !store.isDrawing, !store.hasActiveCoachMarkGeometryPreview else {
            cancel(in: store)
            return false
        }
        let final = PlaybackTimelineScrub.update(state, duration: store.selectedScenario.duration,
            railWidth: railWidth, horizontalTranslation: translation.width, verticalTranslation: translation.height)
        defer { reset() }
        return store.commitTimelineScrub(to: final.time)
    }

    func cancel(in store: ReplayStore) {
        if ownsScrub(in: store) { store.cancelTimelineScrub() }
        reset()
    }

    private func reset() {
        state = nil
        storeScrubID = nil
    }

    private func valid(railWidth: CGFloat, translation: CGSize) -> Bool {
        railWidth.isFinite && railWidth > 0 && translation.width.isFinite && translation.height.isFinite
    }
}
