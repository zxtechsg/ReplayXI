import SwiftUI

/// The selected tool owns its timeline. Secondary edits expand in place.
struct SpatialAnnotationEditor: View {
    @Environment(ReplayStore.self) private var store
    let mark: CoachMark
    let onTimeline: () -> Void
    let onAdjust: () -> Void
    let onActions: () -> Void
    let onClose: () -> Void
    @State private var linking: CoachMarkElevationTarget?

    private var editable: Bool {
        store.localRole == .coach && !store.selectedScenario.coachMarks.contains(where: { $0.id == mark.id })
    }
    private var currentKey: CoachMarkKeyframe? {
        mark.keyframes?.first { abs($0.time - store.playhead) < CoachMark.keyframeTimeTolerance }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            SpatialAnnotationTimeline(mark: mark)
            HStack {
                Text(String(format: "%.2f", mark.revealTime))
                Spacer()
                if mark.hasKeyframes {
                    Label("\(mark.keyframes?.count ?? 0)", systemImage: "diamond.fill")
                        .foregroundStyle(ReplayTheme.cyan)
                } else if mark.followsPlayerTracks {
                    Image(systemName: "link").foregroundStyle(ReplayTheme.cyan)
                }
                Spacer()
                Text(mark.hideTime.map { String(format: "%.2f", $0) } ?? "End")
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            if let linking { playerLinks(linking) }
        }
        .padding(12)
        .background(ReplayTheme.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 17))
        .onChange(of: mark.id) { _, _ in linking = nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            action("timeline.selection", "All annotation tracks", onTimeline)
            Label(mark.label, systemImage: mark.kind.systemImage)
                .font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if editable, mark.kind.requiresTwoPitchPoints {
                action("diamond", "Save position at this time") {
                    _ = store.captureCoachMarkKeyframe(id: mark.id)
                }
                .disabled(mark.followsPlayerTracks || !mark.canRecordPose(at: store.playhead))
                action("diamond.slash", "Delete position at this time") {
                    if let key = currentKey { _ = store.removeCoachMarkKeyframe(id: mark.id, at: key.time) }
                }
                .disabled(currentKey == nil)
                endpointButton(.start)
                endpointButton(.end)
                action("slider.horizontal.3", "Adjust shape and height", onAdjust)
            }
            if store.localRole == .coach {
                action("ellipsis", "Annotation actions", onActions)
            }
            action("xmark", "Close annotation", onClose)
        }
        .disabled(!store.canChangePlaybackView)
    }

    private func endpointButton(_ endpoint: CoachMarkElevationTarget) -> some View {
        let start = endpoint == .start
        let anchor = start ? mark.startTrackAnchor : mark.endTrackAnchor
        let player = anchor.flatMap { store.selectedScenario.player(id: $0.playerID) }
        return Button {
            linking = linking == endpoint ? nil : endpoint
        } label: {
            HStack(spacing: 4) {
                Image(systemName: start ? "circle.lefthalf.filled" : "circle.righthalf.filled")
                if let player { Text("\(player.shirtNumber)").font(.caption.monospacedDigit()) }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(anchor == nil ? .white : ReplayTheme.cyan)
        .help("\(start ? "Origin" : "End") · \(player.map { "#\($0.shirtNumber)" } ?? "fixed to pitch")")
        .accessibilityLabel("Link \(start ? "origin" : "end") to a player")
        .accessibilityValue(player.map { "#\($0.shirtNumber) \($0.displayName)" } ?? "Pitch fixed")
    }

    @ViewBuilder
    private func playerLinks(_ endpoint: CoachMarkElevationTarget) -> some View {
        if mark.hasKeyframes {
            HStack {
                Text("Saved poses keep their motion.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Freeze here") { _ = store.freezeCoachMarkKeyframes(id: mark.id) }
                    .help("Freeze the current pose before linking. Undo restores the keys.")
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Button {
                        _ = store.setCoachMarkEndpointTracking(id: mark.id, endpoint: endpoint, playerID: nil)
                        linking = nil
                    } label: {
                        Image(systemName: "pin.fill").frame(width: 44, height: 44)
                    }
                    .help("Keep this endpoint fixed to the pitch")
                    .accessibilityLabel("Pitch fixed")
                    ForEach(store.selectedScenario.players) { player in
                        Button {
                            _ = store.setCoachMarkEndpointTracking(id: mark.id, endpoint: endpoint,
                                                                  playerID: player.id)
                            linking = nil
                        } label: {
                            Text("#\(player.shirtNumber)")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .frame(minWidth: 48, minHeight: 44)
                        }
                        .tint(player.team == .home ? ReplayTheme.cyan : ReplayTheme.orange)
                        .help("\(player.displayName) · \(player.positionCode)")
                        .accessibilityLabel("Link to #\(player.shirtNumber), \(player.displayName)")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func action(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 60, height: 60)
        }
        .buttonStyle(.bordered).help(help).accessibilityLabel(help)
    }
}

struct SpatialAnnotationTracks: View {
    @Environment(ReplayStore.self) private var store
    let marks: [CoachMark]
    let onSelect: (CoachMark) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "timeline.selection").foregroundStyle(ReplayTheme.cyan)
                Text("Annotations").font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "0 — %.2fs", store.selectedScenario.duration))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.bordered).help("Close timeline").accessibilityLabel("Close timeline")
                    .disabled(!store.canChangePlaybackView)
            }
            if marks.isEmpty {
                Image(systemName: "pencil.and.outline").foregroundStyle(.secondary).frame(height: 48)
                    .accessibilityLabel("Draw a mark to add a track")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(marks) { mark in
                            SpatialAnnotationTimeline(mark: mark, showsTitle: true) { onSelect(mark) }
                        }
                    }
                }
                .frame(height: min(CGFloat(marks.count) * 88, 264))
            }
        }
        .padding(12)
        .background(ReplayTheme.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 17))
    }
}
