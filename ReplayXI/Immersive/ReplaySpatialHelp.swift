import SwiftUI

#if DEBUG
private struct SpatialHelpSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    /// UIKit captures cannot render compositor hover phases. Hide tooltip
    /// overlays for layout-only captures; this is never enabled by app UI.
    var hidesSpatialHelpForSnapshot: Bool {
        get { self[SpatialHelpSnapshotKey.self] }
        set { self[SpatialHelpSnapshotKey.self] = newValue }
    }
}
#endif

/// The compositor handles gaze feedback. No gaze state enters the app.
private struct ReplaySpatialHelp: ViewModifier {
    let text: String
    @Namespace private var group
    #if DEBUG
    @Environment(\.hidesSpatialHelpForSnapshot) private var snapshot
    #endif

    func body(content: Content) -> some View {
        content
            .hoverEffect(.highlight, in: HoverEffectGroup(group))
            .overlay(alignment: .top) {
                tooltip
                    #if DEBUG
                    .opacity(snapshot ? 0 : 1)
                    #endif
            }
            .accessibilityHint(text)
    }

    private var tooltip: some View {
        Text(text)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
                    .alignmentGuide(.top) { $0[.bottom] + 12 }
                    .hoverEffect(in: HoverEffectGroup(group)) { effect, active, _ in
                        effect.animation(.easeOut(duration: 0.15).delay(active ? 0.35 : 0)) {
                            $0.opacity(active ? 1 : 0)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
    }
}

extension View {
    func spatialHelp(_ text: String) -> some View {
        modifier(ReplaySpatialHelp(text: text))
    }
}
