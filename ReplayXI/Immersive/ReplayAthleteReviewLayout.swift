import Foundation

/// One scale policy for the athlete and its independent identity tag. Keeping
/// these together prevents a review-sized body from growing through its label.
enum ReplayAthleteReviewLayout {
    /// Conservative pitch-local head envelope for the bundled grounded rigs,
    /// including their appearance scales and locomotion. It stays constant as
    /// heads turn: labels must not bob with animation or query mesh bounds each
    /// frame. This is a presentation allowance, not a human-height claim.
    static let headClearanceEnvelope: Float = 2.30

    static func focusScale(
        viewMode: ReplayViewMode,
        isSelected: Bool,
        isFeatured: Bool,
        isShapeRole: Bool,
        isPhysicalDrill: Bool = false
    ) -> Float {
        switch viewMode {
        case .firstPerson:
            1
        case .tacticalTable:
            isSelected ? 3.15 : (isFeatured ? 2.05 : 1.40)
        case .touchline:
            isSelected ? 1.9 : (isFeatured ? 1.4 : 1.08)
        case .positional:
            isPhysicalDrill ? 1 : (isShapeRole ? 3.05 : 2.65)
        }
    }

    static func minimumTagHeight(athleteScale: Float, labelScale: Float) -> Float {
        // The selected outline is the tallest visible tag piece (0.38 m).
        // Reserve its lower half even for compact tags; selection then changes
        // neither tag height nor its minimum clearance.
        headClearanceEnvelope * athleteScale + 0.19 * labelScale + 0.10
    }
}
