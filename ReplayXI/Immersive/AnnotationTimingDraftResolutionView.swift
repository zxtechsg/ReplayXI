import SwiftUI

/// An in-place decision, never a modal presentation in immersive space.
struct AnnotationTimingDraftResolutionView: View {
    let canApply: Bool
    let needsRetry: Bool
    let keepEditing: () -> Void
    let discard: () -> Void
    let apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Unsaved timing", systemImage: "pencil.and.outline")
                .font(.headline).foregroundStyle(ReplayTheme.orange)
            Text(needsRetry ? "Apply or discard, then retry that action."
                 : "Apply or discard before leaving this annotation.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { actions }
            }
            if !canApply {
                Text("Keep editing, or discard these changes.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Keep editing", action: keepEditing).frame(minHeight: 52)
        Button("Discard", role: .destructive, action: discard).frame(minHeight: 52)
            .accessibilityHint("Discards only typed timing changes. Saved annotations stay unchanged.")
        Button("Apply changes", action: apply).frame(minHeight: 52)
            .buttonStyle(.borderedProminent).tint(ReplayTheme.orange).disabled(!canApply)
    }
}
