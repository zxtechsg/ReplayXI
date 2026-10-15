import Foundation

/// Actors remain human-sized in pitch coordinates in every review view.
/// Selection belongs to rings/tags, never a bigger body or collision envelope.
enum ReplayAthleteReviewLayout {
    /// Cold-start fallback only. A live rig supplies its posed crown height so
    /// the visible number remains close to that player, including when bent.
    static let headClearanceEnvelope: Float = 2.05
    static let tagHeadGap: Float = 0.07

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

    static func minimumTagHeight(
        athleteScale: Float, labelScale: Float,
        headTop: Float? = nil, tagLocalBottom: Float = -0.19
    ) -> Float {
        let crown = headTop.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            ?? headClearanceEnvelope * athleteScale
        // Reserve only the part of the visible tag below its origin. Compact
        // numbers have no card or selected outline, so they need less lift.
        return crown + tagHeadGap - min(tagLocalBottom, 0) * labelScale
    }
}
