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
                .frame(minHeight: 60)
                .foregroundStyle(ReplayTheme.cyan)
                .background(ReplayTheme.cyan.opacity(0.09), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Video reference: \(reference.matchTitle)")
        .accessibilityValue(reference.timeRangeLabel)
        .accessibilityHint("Shows the source clip and reconstruction details.")
        .popover(isPresented: $showsReference, arrowEdge: .bottom) {
            ReplayVideoReferenceDetails(reference: reference)
        }
        .onChange(of: reference) { _, _ in showsReference = false }
    }
}

struct ReplayVideoReferenceDetails: View {
    let reference: ReplayVideoReference
    var fixedWidth: CGFloat? = 350
    @State private var showsDetails = false

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
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Watch source video, \(reference.matchTitle), \(reference.timeRangeLabel)")
            .accessibilityHint("Opens YouTube at the beginning of this clip.")
            ForEach(reference.alternateAngles, id: \.self) { angle in
                Link(destination: reference.sourceURL(at: angle.startSeconds)) {
                    Label(angle.title, systemImage: "video")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                }
                .accessibilityHint("Opens an alternate broadcast replay angle. Replay speed may differ from live play.")
            }
            Divider()
            Text("Authored 3D replay. Unseen motion is estimated.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { showsDetails.toggle() } label: {
                Label("Reconstruction details", systemImage: showsDetails ? "chevron.up" : "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityHint(showsDetails ? "Hides the reconstruction notes" : "Shows the reconstruction notes")
            if showsDetails {
                Text(reference.reconstructionNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Marks are saved on the 3D replay, not the source video.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(width: fixedWidth, alignment: .leading)
        .onChange(of: reference) { _, _ in showsDetails = false }
    }
}
