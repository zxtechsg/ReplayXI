import SwiftUI

/// Glass is reserved for the control layer; pitch and text remain opaque.
/// Older Macs keep the native material fallback rather than a drawn imitation.
struct CoachGlassSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
