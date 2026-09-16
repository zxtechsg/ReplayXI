import CoreGraphics

/// Large-text drawing keeps the instruction above its five tools instead of
/// compressing both into one row. Normal controls retain their existing size.
struct PlaybackDrawToolLayout: Equatable, Sendable {
    let usesStackedShelves: Bool
    let labelWidth: CGFloat
    let labelMinimumHeight: CGFloat
    let instructionMinimumScale: CGFloat
    let cancelLabelWidth: CGFloat
    let cancelLabelMinimumHeight: CGFloat

    static let drawingInstructionWidth: CGFloat = 190
    static let idleInstructionWidth: CGFloat = 180

    static func resolve(usesAccessibilityText: Bool) -> PlaybackDrawToolLayout {
        PlaybackDrawToolLayout(
            usesStackedShelves: usesAccessibilityText,
            labelWidth: usesAccessibilityText ? 88 : 70,
            labelMinimumHeight: usesAccessibilityText ? 84 : 48,
            instructionMinimumScale: usesAccessibilityText ? 1 : 0.72,
            cancelLabelWidth: usesAccessibilityText ? 60 : 28,
            cancelLabelMinimumHeight: usesAccessibilityText ? 60 : 48
        )
    }
}
