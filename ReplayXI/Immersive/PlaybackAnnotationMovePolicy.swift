import Foundation

/// Availability of the selected annotation's MOVE timestamp action.
/// The Store still owns timing validation and commits the actual edit.
@MainActor
enum PlaybackAnnotationMovePolicy {
    static func canMove(
        _ mark: CoachMark,
        to time: TimeInterval,
        in store: ReplayStore
    ) -> Bool {
        guard store.canChangePlaybackView else { return false }
        guard time.isFinite,
              store.selectedScenario.duration.isFinite,
              (0...store.selectedScenario.duration).contains(time),
              abs(mark.revealTime - time) >= 0.05,
              mark.canShiftKeyframes(by: time - mark.revealTime, duration: store.selectedScenario.duration)
        else { return false }
        return CoachMarkTimingPolicy.windowFits(
            revealTime: time, displayDuration: mark.hideTime.map { $0 - mark.revealTime },
            replayDuration: store.selectedScenario.duration
        )
    }
}
