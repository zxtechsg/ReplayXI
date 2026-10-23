import Foundation

/// Timed tracking changes preserve the earlier saved poses.
enum AnnotationTrackingPolicy {
    static let keyframeHint = "Linking a player is saved at this replay time; earlier poses are kept."

    static func canSetTracking(_ mark: CoachMark, canChangePlaybackView: Bool) -> Bool {
        canChangePlaybackView && mark.kind.requiresTwoPitchPoints
    }

    static func keyframeStatus(_ mark: CoachMark) -> String? {
        guard mark.hasKeyframes else { return nil }
        let count = mark.keyframes?.count ?? 0
        return "\(count) POSITION \(count == 1 ? "KEY" : "KEYS")"
    }

    static func keyframeAccessibilityValue(_ mark: CoachMark) -> String? {
        guard mark.hasKeyframes else { return nil }
        let count = mark.keyframes?.count ?? 0
        return "\(count) saved \(count == 1 ? "position" : "positions"), controlled by timestamps"
    }

    static func playerHint(_ mark: CoachMark, canChangePlaybackView: Bool) -> String {
        if canChangePlaybackView && mark.hasKeyframes { return keyframeHint }
        return canChangePlaybackView
            ? "Keeps both annotation points at their current offsets from this player"
            : "Finish or cancel the current gesture first"
    }
}
