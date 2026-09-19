import SwiftUI

/// A route to the existing timing editor, never an implicit destructive freeze.
struct AnnotationTrackingKeyframeNotice: View {
    let keyCount: Int
    let color: Color
    let isEnabled: Bool
    let editKeys: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                explanation
                editButton
            }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 12) {
                explanation
                editButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(keyCount) saved \(keyCount == 1 ? "position" : "positions")", systemImage: "diamond")
                .font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text(AnnotationTrackingPolicy.keyframeHint)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var editButton: some View {
        Button(action: editKeys) {
            Label("Edit keys", systemImage: "timer")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
        }
        .buttonStyle(.borderedProminent).tint(color)
        .disabled(!isEnabled)
        .accessibilityLabel("Edit annotation position keys")
        .accessibilityHint(isEnabled
            ? "Opens Timing for this annotation. No saved positions are changed."
            : "Finish or cancel the current gesture first")
    }
}
