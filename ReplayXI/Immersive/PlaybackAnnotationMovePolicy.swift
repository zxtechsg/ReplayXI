import Foundation

/// Availability of the selected annotation's MOVE timestamp action.
/// The Store still owns timing validation and commits the actual edit.
@MainActor
enum PlaybackAnnotationMovePolicy {
    enum BlockReason: Equatable {
        case activeGesture
        case invalidTime
        case currentTime
        case positionKeyBounds
        case visibilityWindow

        var guidance: String {
            switch self {
            case .activeGesture:
                "Finish or cancel the current gesture first"
            case .invalidTime:
                "Choose a valid time inside this replay"
            case .currentTime:
                "Choose a time at least 0.05 seconds from the annotation's current In time"
            case .positionKeyBounds:
                "A saved position would leave the replay. Adjust its time in Timing, or choose a smaller shift. Shortening In/Out does not move position keys."
            case .visibilityWindow:
                "The visibility window does not fit. Adjust In/Out or choose a different time."
            }
        }
    }

    static func canMove(
        _ mark: CoachMark,
        to time: TimeInterval,
        in store: ReplayStore
    ) -> Bool {
        blockReason(mark, to: time, in: store) == nil
    }

    /// Explain the same first failing condition used by availability. In/Out
    /// and saved-position bounds are independent; one cannot repair the other.
    static func blockReason(_ mark: CoachMark, to time: TimeInterval, in store: ReplayStore) -> BlockReason? {
        guard store.canChangePlaybackView else { return .activeGesture }
        let duration = store.selectedScenario.duration
        guard time.isFinite, mark.revealTime.isFinite, duration.isFinite, duration >= 0,
              (0...duration).contains(time) else { return .invalidTime }
        guard abs(mark.revealTime - time) >= 0.05 else { return .currentTime }
        guard mark.canShiftKeyframes(by: time - mark.revealTime, duration: duration)
        else { return .positionKeyBounds }
        guard CoachMarkTimingPolicy.windowFits(
            revealTime: time, displayDuration: mark.hideTime.map { $0 - mark.revealTime },
            replayDuration: duration
        ) else { return .visibilityWindow }
        return nil
    }

    static func guidance(_ mark: CoachMark, to time: TimeInterval, in store: ReplayStore) -> String {
        blockReason(mark, to: time, in: store)?.guidance
            ?? "Shifts In/Out and every saved position time by the same amount"
    }

    /// Reuses the existing compact hint slot, without adding a shelf or changing
    /// control sizes. Full remediation is available as help and an AX hint.
    static func compactHint(_ mark: CoachMark, to time: TimeInterval, in store: ReplayStore) -> String {
        blockReason(mark, to: time, in: store) == .positionKeyBounds ? "CHECK KEYS" : "SCRUB ABOVE"
    }
}
