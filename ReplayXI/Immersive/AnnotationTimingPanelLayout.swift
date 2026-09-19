import Foundation

enum AnnotationTimingPanelLayout {
    static func height(contentHeight: CGFloat?, usesAccessibilityText: Bool) -> CGFloat {
        let cap: CGFloat = usesAccessibilityText ? 620 : 520
        guard let contentHeight, contentHeight.isFinite, contentHeight > 0 else { return cap }
        // Round up so fractional text baselines never produce a clipped last row.
        return min(ceil(contentHeight), cap)
    }
}
