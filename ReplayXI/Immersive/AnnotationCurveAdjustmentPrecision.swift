/// A single step policy for the pad, +/- buttons and VoiceOver actions.
struct AnnotationCurveAdjustmentPrecision {
    let fine: Bool

    var distanceStep: Float { fine ? 0.05 : 0.25 }
    var angleStep: Float { fine ? 1 : 5 }

    func verticalStep(isAngle: Bool) -> Float {
        isAngle ? angleStep : distanceStep
    }

    var distanceHint: String { fine ? "Five-centimetre step" : "Quarter-metre step" }
    var angleHint: String { fine ? "One-degree step" : "Five-degree step" }

    func padHint(isAngle: Bool) -> String {
        if isAngle {
            let steps = fine ? "Five-centimetre and one-degree steps." : "Quarter-metre and five-degree steps."
            return "Drag sideways for curve, up or down for angle. \(steps) The arc stays above the pitch."
        }
        let steps = fine ? "Five-centimetre steps." : "Quarter-metre steps."
        return "Drag sideways to bend, up to lift. \(steps) The rotation angle is preserved."
    }
}
