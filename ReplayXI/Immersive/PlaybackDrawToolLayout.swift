import CoreGraphics

/// Six tools get a separate row from the instruction at every text size.
/// Text stays visible and the pinch target stays large.
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
            labelWidth: usesAccessibilityText ? 144 : 120,
            labelMinimumHeight: usesAccessibilityText ? 96 : 80,
            instructionMinimumScale: 1,
            cancelLabelWidth: 80,
            cancelLabelMinimumHeight: usesAccessibilityText ? 96 : 80
        )
    }
}
