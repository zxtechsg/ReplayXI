import Foundation

/// Actors remain human-sized in pitch coordinates in every review view.
/// Selection belongs to rings/tags, never a bigger body or collision envelope.
enum ReplayAthleteReviewLayout {
    /// Conservative pitch-local head envelope for the bundled grounded rigs,
    /// including their appearance scales and locomotion. It stays constant as
    /// heads turn: labels must not bob with animation or query mesh bounds each
    /// frame. This is a presentation allowance, not a human-height claim.
    static let headClearanceEnvelope: Float = 2.05

    static func focusScale(
        viewMode: ReplayViewMode,
        isSelected: Bool,
        isFeatured: Bool,
        isShapeRole: Bool,
        isPhysicalDrill: Bool = false
    ) -> Float {
        // Keep the call contract shared with tag placement. View transforms
        // scale the whole pitch; a featured home player must not grow relative
        // to an opponent, the ball, a passing lane or the wearer's viewpoint.
        1
    }

    static func minimumTagHeight(athleteScale: Float, labelScale: Float) -> Float {
        // The selected outline is the tallest visible tag piece (0.38 m).
        // Reserve its lower half even for compact tags; selection then changes
        // neither tag height nor its minimum clearance.
        headClearanceEnvelope * athleteScale + 0.19 * labelScale + 0.15
    }
}
