import SwiftUI

/// Wearer-local graphics preference. This never changes a saved review,
/// player track, contact recording or annotation.
struct PlaybackPlayerDetailControl: View {
    @Environment(ReplayStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var rawValue: String

    private var selection: ReplayPlayerDetail { .resolved(rawValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                heading
                choices
            } else {
                HStack(spacing: 16) {
                    heading
                    choices
                    Spacer(minLength: 0)
                }
            }
            Text("Full squad: more detail, more processing.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heading: some View {
        Label("Player detail", systemImage: "person.3")
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var choices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { choiceButtons }
            VStack(alignment: .leading, spacing: 10) { choiceButtons }
        }
    }

    private var choiceButtons: some View {
        ForEach(ReplayPlayerDetail.allCases, id: \.rawValue) { detail in
                let selected = detail == selection
                Button {
                    _ = Self.select(detail, rawValue: $rawValue, store: store)
                } label: {
                    Label(detail.title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 140, minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(selected ? ReplayTheme.cyan : .white.opacity(0.10))
                .foregroundStyle(selected ? Color.black : Color.white)
                .disabled(!store.canChangePlaybackView)
                .accessibilityLabel("\(detail.title) player detail")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(selected ? "Selected" : store.canChangePlaybackView
                    ? detail.accessibilityHint : "Finish or cancel the current gesture first")
                .accessibilityIdentifier("playback-player-detail-\(detail.rawValue)")
                .help(selected ? "Selected" : detail.accessibilityHint)
        }
    }

    /// Shared by touch and accessibility activation. Recheck ownership here,
    /// rather than trusting a possibly stale enabled SwiftUI button.
    @discardableResult
    static func select(_ detail: ReplayPlayerDetail, rawValue: Binding<String>, store: ReplayStore) -> Bool {
        guard store.selectedScenario.kind != .shapeLab,
              detail.canSelect(from: .resolved(rawValue.wrappedValue),
                               canChangePlaybackView: store.canChangePlaybackView) else { return false }
        store.setPlaying(false, broadcast: false)
        rawValue.wrappedValue = detail.rawValue
        return true
    }
}
