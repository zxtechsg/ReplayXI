import Foundation

/// Saved positions and player tracking are mutually exclusive motion sources.
/// Reflect the Store's rule before inviting an action it cannot perform.
enum AnnotationTrackingPolicy {
    static let keyframeHint = "Open Timing and choose Freeze here before following a player."

    static func canSetTracking(_ mark: CoachMark, canChangePlaybackView: Bool) -> Bool {
        canChangePlaybackView && mark.kind.requiresTwoPitchPoints && !mark.hasKeyframes
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
        if mark.hasKeyframes { return keyframeHint }
        return canChangePlaybackView
            ? "Keeps both annotation points at their current offsets from this player"
            : "Finish or cancel the current gesture first"
    }
}
