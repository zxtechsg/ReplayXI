import Foundation

/// Authoring-time bounds. Older saved windows may extend past the clip and
/// remain readable; new/retimed windows must fit the replay being edited.
enum CoachMarkTimingPolicy {
    static let preferredDuration: TimeInterval = 8
    static let maximumDuration: TimeInterval = 30
    private static let roundingTolerance: TimeInterval = 0.000_001

    static func windowFits(
        revealTime: TimeInterval,
        displayDuration: TimeInterval?,
        replayDuration: TimeInterval
    ) -> Bool {
        guard revealTime.isFinite, replayDuration.isFinite, replayDuration >= 0,
              (0...replayDuration).contains(revealTime) else { return false }
        guard let displayDuration else { return true }
        let remaining = replayDuration - revealTime
        return displayDuration.isFinite && displayDuration > 0 && displayDuration <= maximumDuration
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
