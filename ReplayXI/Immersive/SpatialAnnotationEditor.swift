import SwiftUI

/// Live headset editing. Fine timing and pose management belong on Mac.
struct SpatialAnnotationEditor: View {
    @Environment(ReplayStore.self) private var store
    let mark: CoachMark
    let onTimeline: () -> Void
    let onAdjust: () -> Void
    let onActions: () -> Void
    let onClose: () -> Void

    private var editable: Bool {
        store.localRole == .coach && !store.selectedScenario.coachMarks.contains(where: { $0.id == mark.id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Label(mark.label, systemImage: mark.kind.systemImage).font(.headline)
                Spacer()
                action("All marks", "list.bullet", onTimeline)
                action("Close", "xmark", onClose)
            }
            if editable {
                Text("Edits are saved at \(store.playhead.formatted(.number.precision(.fractionLength(2))))s. Use Mac coach for fine timing.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if mark.kind.requiresTwoPitchPoints {
                    Text(mark.kind == .arc
                        ? "Drag an end onto a player to follow them. Drag away to release. Drag the cyan point to bend the curve in 3D."
                        : "Drag an end onto a player to follow them. Drag it away to release.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { edits }
                    VStack(alignment: .leading, spacing: 12) { edits }
                }
            } else {
                Text("Match overlay · use More to make an editable copy.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.localRole == .coach { action("More", "ellipsis", onActions) }
            }
            HStack {
                Label("Starts \(time(mark.revealTime))", systemImage: "play.fill")
                Spacer()
                Text(mark.hideTime.map { "Ends \(time($0))" } ?? "Visible until replay ends")
            }.font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(ReplayTheme.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .disabled(!store.canChangePlaybackView)
    }

    @ViewBuilder private var edits: some View {
        action("Start here", "play.fill") { _ = store.startCoachMarkHere(id: mark.id) }
            .spatialHelp("Show this mark from the current replay time")
        action("End here", "stop.fill") { _ = store.endCoachMarkHere(id: mark.id) }
            .disabled(store.playhead <= mark.revealTime)
            .spatialHelp("Hide from this time; keep earlier playback")
        if mark.kind.requiresTwoPitchPoints {
            action("Shape & height", "move.3d", onAdjust)
                .spatialHelp("Move endpoints or bend the curve left, right, up and down")
        }
        action("More", "ellipsis", onActions)
            .spatialHelp("Copy this pose or delete the mark everywhere")
    }

    private func action(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline)
                .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                .padding(.horizontal, 8)
        }.buttonStyle(.bordered)
    }

    private func time(_ value: TimeInterval) -> String {
        value.formatted(.number.precision(.fractionLength(2))) + "s"
    }
}

struct SpatialAnnotationTracks: View {
    @Environment(ReplayStore.self) private var store
    let marks: [CoachMark]
    let onSelect: (CoachMark) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Annotations", systemImage: "pencil.tip").font(.headline)
                Spacer()
                Button(action: onClose) {
                    Label("Close", systemImage: "xmark").frame(minHeight: 80)
                }.buttonStyle(.bordered)
            }
            Text("Select a mark to edit. Fine timeline editing is on Mac coach.")
                .font(.subheadline).foregroundStyle(.secondary)
            if marks.isEmpty {
                Label("Use the pen to add a mark.", systemImage: "pencil.tip")
                    .foregroundStyle(.secondary).frame(height: 80)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(marks) { mark in
                            Button { onSelect(mark) } label: {
                                HStack {
                                    Label(mark.label, systemImage: mark.kind.systemImage).font(.headline)
                                    Spacer()
                                    Text(mark.isVisible(at: store.playhead) ? "Visible now" : "Hidden now")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                }.padding(.horizontal, 14).frame(minHeight: 80)
                            }.buttonStyle(.bordered)
                        }
                    }
                }.frame(height: min(CGFloat(marks.count) * 94, 282))
            }
        }
        .padding(18)
        .background(ReplayTheme.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .disabled(!store.canChangePlaybackView)
    }
}
