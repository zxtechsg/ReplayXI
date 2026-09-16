import CoreGraphics

/// Label budgets for annotation duration choices, separate from transport.
/// Large-text choices get their own adaptive row, preserving the requested
/// font size rather than competing with the shelf header and current length.
struct PlaybackAnnotationTimingLayout: Equatable, Sendable {
    let usesAdaptiveChoices: Bool
    let timedLabelWidth: CGFloat
    let throughEndLabelWidth: CGFloat
    let labelMinimumHeight: CGFloat
    let minimumTextScale: CGFloat

    static let gridSpacing: CGFloat = 8
    var gridMinimumCellWidth: CGFloat { max(timedLabelWidth, throughEndLabelWidth) + 48 }

    func labelWidth(throughEnd: Bool) -> CGFloat {
        throughEnd ? throughEndLabelWidth : timedLabelWidth
    }

    static func resolve(usesAccessibilityText: Bool) -> PlaybackAnnotationTimingLayout {
        PlaybackAnnotationTimingLayout(
            usesAdaptiveChoices: usesAccessibilityText,
            timedLabelWidth: usesAccessibilityText ? 80 : 66,
            throughEndLabelWidth: usesAccessibilityText ? 128 : 104,
            labelMinimumHeight: usesAccessibilityText ? 64 : 52,
            minimumTextScale: usesAccessibilityText ? 1 : 0.78
        )
    }
}
