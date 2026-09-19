import Foundation

/// Event chips may retain a value from before a retime, erase or review load.
/// Resolve the current ID before changing either transport or chip selection.
@MainActor
enum PlaybackAnnotationEventNavigation {
    @discardableResult
    static func jump(to markID: UUID, in store: ReplayStore) -> Bool {
        guard store.canChangePlaybackView,
              let mark = store.marks.first(where: { $0.id == markID }),
              mark.revealTime.isFinite, store.selectedScenario.duration.isFinite,
              store.selectedScenario.duration >= 0,
              (0...store.selectedScenario.duration).contains(mark.revealTime)
        else { return false }
        // No suspension between admission and the Store's guarded operations.
        // Preserve event-rail transport semantics, including local player seeks.
        store.setPlaying(false, broadcast: false)
        store.seek(to: mark.revealTime, broadcast: store.localRole == .coach)
        return store.playhead == mark.revealTime && !store.isPlaying
    }
}
