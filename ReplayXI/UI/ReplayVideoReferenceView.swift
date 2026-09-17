import SwiftUI

/// A single quiet source affordance; explanatory copy stays behind the popover.
struct ReplayVideoReferenceButton: View {
    let reference: ReplayVideoReference
    @State private var showsReference = false

    var body: some View {
        Button {
            showsReference = true
        } label: {
            Label(reference.shortLabel, systemImage: "play.rectangle")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(ReplayTheme.cyan)
                .background(ReplayTheme.cyan.opacity(0.09), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Video reference: \(reference.matchTitle)")
        .accessibilityValue(reference.timeRangeLabel)
        .accessibilityHint("Shows the source clip and reconstruction details.")
        .popover(isPresented: $showsReference, arrowEdge: .bottom) {
            ReplayVideoReferenceDetails(reference: reference)
        }
        .onChange(of: reference) { _, _ in showsReference = false }
    }
}

private struct ReplayVideoReferenceDetails: View {
    let reference: ReplayVideoReference

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Video reference", systemImage: "play.rectangle")
                .font(.headline)
            Text(reference.matchTitle)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: reference.sourceURL) {
                HStack(spacing: 10) {
                    Text("Watch \(reference.timeRangeLabel)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Watch source video, \(reference.matchTitle), \(reference.timeRangeLabel)")
            .accessibilityHint("Opens YouTube at the beginning of this clip.")
            ForEach(reference.alternateAngles, id: \.self) { angle in
                Link(destination: reference.sourceURL(at: angle.startSeconds)) {
                    Label(angle.title, systemImage: "video")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityHint("Opens an alternate broadcast replay angle. Replay speed may differ from live play.")
            }
            Divider()
            Text(reference.reconstructionNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 350, alignment: .leading)
    }
}
