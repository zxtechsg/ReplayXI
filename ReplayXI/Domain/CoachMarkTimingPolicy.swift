import Foundation

/// Authoring-time bounds. Older saved windows may extend past the clip and
/// remain readable; new/retimed windows must fit the replay being edited.
enum CoachMarkTimingPolicy {
    static let preferredDuration: TimeInterval = 8
    static let minimumEditableDuration: TimeInterval = 0.5
    static let maximumDuration: TimeInterval = 30
    private static let roundingTolerance: TimeInterval = 0.000_001

    /// Decimal endpoints can subtract just below 0.5 or above 30. Allow only
    /// arithmetic roundoff at those operands, never a UI-step-sized tolerance.
    static func meetsMinimumEditableDuration(revealTime: TimeInterval, hideTime: TimeInterval) -> Bool {
        let duration = hideTime - revealTime
        guard revealTime.isFinite, hideTime.isFinite, duration.isFinite, duration > 0 else { return false }
        return duration >= minimumEditableDuration
            || minimumEditableDuration - duration <= durationRoundoff(revealTime: revealTime,
                hideTime: hideTime, duration: duration)
    }

    static func fitsMaximumDuration(revealTime: TimeInterval, displayDuration: TimeInterval) -> Bool {
        let hideTime = revealTime + displayDuration
        guard revealTime.isFinite, hideTime.isFinite, displayDuration.isFinite,
              displayDuration > 0 else { return false }
        return displayDuration <= maximumDuration
            || displayDuration - maximumDuration <= durationRoundoff(revealTime: revealTime,
                hideTime: hideTime, duration: displayDuration)
    }

    private static func durationRoundoff(revealTime: TimeInterval, hideTime: TimeInterval,
                                         duration: TimeInterval) -> TimeInterval {
        2 * max(revealTime.ulp, max(hideTime.ulp, duration.ulp))
    }

    static func windowFits(
        revealTime: TimeInterval,
        displayDuration: TimeInterval?,
        replayDuration: TimeInterval
    ) -> Bool {
        guard revealTime.isFinite, replayDuration.isFinite, replayDuration >= 0,
              (0...replayDuration).contains(revealTime) else { return false }
        guard let displayDuration else { return true }
        let remaining = replayDuration - revealTime
        return fitsMaximumDuration(revealTime: revealTime, displayDuration: displayDuration)
            && remaining > 0 && revealTime + displayDuration > revealTime
            && displayDuration <= remaining + roundingTolerance
    }

    /// The tail of a clip is "To end", including its final paused frame. A
    /// finite hide time at exactly that frame would make the new mark vanish.
    static func defaultHideTime(revealTime: TimeInterval, replayDuration: TimeInterval) -> TimeInterval? {
        guard windowFits(revealTime: revealTime, displayDuration: nil, replayDuration: replayDuration),
              preferredDuration < replayDuration - revealTime - roundingTolerance else { return nil }
        return revealTime + preferredDuration
    }
}
