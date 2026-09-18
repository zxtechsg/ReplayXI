import SwiftUI

/// Draft fields do not pollute Undo or autosave on every slider sample.
struct AnnotationTimingEditor: View {
    @Environment(ReplayStore.self) private var store
    let markID: UUID
    let color: Color
    var adjustPose: () -> Void = {}
    @State private var start: Double = 0
    @State private var end: Double = 1
    @State private var throughEnd = false
    private var mark: CoachMark? { store.marks.first { $0.id == markID } }
    private var duration: Double { store.selectedScenario.duration }
    private var valid: Bool {
        CoachMarkTimingPolicy.windowFits(revealTime: start,
            displayDuration: throughEnd ? nil : end - start, replayDuration: duration)
            && (throughEnd || end - start >= 0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("In / Out", systemImage: "timer").font(.headline).foregroundStyle(color)
                Spacer()
                Toggle("To end", isOn: $throughEnd).toggleStyle(.button)
                Button("Apply") {
                    _ = store.setCoachMarkWindow(id: markID, start: start, end: throughEnd ? nil : end)
                }.buttonStyle(.borderedProminent).tint(color).disabled(!valid || !store.canChangePlaybackView)
            }
            timeRow("In", value: $start)
            if !throughEnd { timeRow("Out", value: $end) }
            if !valid { Text("Choose a window of 0.5–30 seconds within the replay.").font(.caption).foregroundStyle(.orange) }
            if let mark {
                HStack {
                    Text("Move window").font(.caption)
                    Button("−1s") { shift(mark, by: -1) }
                        .disabled(!canShift(mark, by: -1))
                    Button("+1s") { shift(mark, by: 1) }
                        .disabled(!canShift(mark, by: 1))
                    Spacer()
                    Text(mark.isVisible(at: store.playhead) ? "Visible now" : "Hidden now")
                        .font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.bordered)
                if mark.kind != .playerLabel {
                    Divider()
                    HStack {
                        Label("Position keys", systemImage: "diamond").font(.headline)
                        Button("Adjust pose", action: adjustPose)
                            .disabled(!store.canChangePlaybackView)
                        Button {
                            _ = store.captureCoachMarkKeyframe(id: markID)
                        } label: { Label("Add at playhead", systemImage: "plus.diamond") }
                        .disabled(!store.canChangePlaybackView || mark.followsPlayerTracks
                                  || (mark.keyframes?.count ?? 0) >= CoachMark.maximumKeyframes)
                        Spacer()
                        Text("\(stamp(store.playhead))").monospacedDigit()
                    }
                    Text(mark.followsPlayerTracks ? "Switch to Fixed before adding position keys."
                        : "Add a key, seek, then adjust the annotation. Movement is saved at that time.")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(mark.keyframes ?? [], id: \.time) { key in
                                HStack(spacing: 2) {
                                    Button(stamp(key.time)) { store.setPlaying(false); store.seek(to: key.time) }
                                        .accessibilityLabel("Go to annotation keyframe at \(stamp(key.time))")
                                    Button {
                                        _ = store.removeCoachMarkKeyframe(id: markID, at: key.time)
                                    } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44) }
                                    .accessibilityLabel("Remove keyframe at \(stamp(key.time))")
                                }.buttonStyle(.bordered)
                            }
                        }
                    }.disabled(!store.canChangePlaybackView)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: markID) { _, _ in reload() }
        .onChange(of: mark?.revealTime) { _, _ in reload() }
        .onChange(of: mark?.hideTime) { _, _ in reload() }
    }

    private func timeRow(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline.weight(.bold)).frame(width: 36)
            Slider(value: value, in: 0...max(duration, 0.1), step: 0.1).tint(color)
                .accessibilityLabel("Annotation \(title) time")
            TextField("Seconds", value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder).frame(width: 100).monospacedDigit()
                .accessibilityLabel("Exact \(title) time in seconds")
            Button("Now") { value.wrappedValue = store.playhead }
                .accessibilityLabel("Set \(title) to playhead")
            Button { store.setPlaying(false); store.seek(to: value.wrappedValue) } label: {
                Image(systemName: "forward.frame").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Preview \(title) time")
        }.disabled(!store.canChangePlaybackView)
    }

    private func stamp(_ t: Double) -> String {
        String(format: "%02d:%04.1f", Int(max(t, 0)) / 60, max(t, 0).truncatingRemainder(dividingBy: 60))
    }
    private func reload() {
        guard let mark else { return }
        start = mark.revealTime; end = min(mark.hideTime ?? duration, duration)
        throughEnd = mark.hideTime == nil
    }
    private func canShift(_ mark: CoachMark, by delta: Double) -> Bool {
        store.canChangePlaybackView && CoachMarkTimingPolicy.windowFits(revealTime: mark.revealTime + delta,
            displayDuration: mark.hideTime.map { $0 - mark.revealTime }, replayDuration: duration)
            && (mark.keyframes ?? []).allSatisfy { (0...duration).contains($0.time + delta) }
    }
    private func shift(_ mark: CoachMark, by delta: Double) {
        _ = store.retimeCoachMark(id: markID, to: mark.revealTime + delta)
    }
}
