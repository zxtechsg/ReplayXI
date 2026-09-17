import CoreGraphics

/// Six tools get a separate row from the instruction at every text size.
/// Existing label/hit sizes are kept instead of squeezing in a sixth tool.
struct PlaybackDrawToolLayout: Equatable, Sendable {
    let usesStackedShelves: Bool
    let labelWidth: CGFloat
    let labelMinimumHeight: CGFloat
    let instructionMinimumScale: CGFloat
    let cancelLabelWidth: CGFloat
    let cancelLabelMinimumHeight: CGFloat

    static let drawingInstructionWidth: CGFloat = 190
    static let idleInstructionWidth: CGFloat = 180
    static let toolCount = 6

    static func resolve(usesAccessibilityText: Bool) -> PlaybackDrawToolLayout {
        PlaybackDrawToolLayout(
            usesStackedShelves: true,
            labelWidth: usesAccessibilityText ? 88 : 70,
            labelMinimumHeight: usesAccessibilityText ? 84 : 48,
            instructionMinimumScale: 1,
            cancelLabelWidth: usesAccessibilityText ? 60 : 28,
            cancelLabelMinimumHeight: usesAccessibilityText ? 60 : 48
        )
    }
}
