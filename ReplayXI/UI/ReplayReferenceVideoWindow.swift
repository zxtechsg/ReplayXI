import SwiftUI

/// The source and the real 3D scene share one comparison window. Entering the
/// immersive room releases the miniature renderer while keeping video visible.
struct ReplayReferenceVideoWindow: View {
    @Environment(ReplayConversionPreviewSession.self) private var session
    @Environment(ReplayStore.self) private var store
    @Environment(ReplayAnnotationEntrySession.self) private var annotationEntry: ReplayAnnotationEntrySession?
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var framing = ReplayComparisonPitchFraming.play
    @State private var hasRequestedRoom = false

    private var roomIsPresenting: Bool {
        store.isImmersiveOpen || store.isOpeningImmersive || store.isClosingImmersive
    }

    var body: some View {
        Group {
            if let capture = session.capture {
                comparison(capture)
            } else {
                ContentUnavailableView("Choose a match study", systemImage: "film.stack",
                    description: Text("Open Video → Replay from a study in the dashboard."))
            }
        }
        .frame(minWidth: 1_120, minHeight: 680)
        .background(.black.opacity(0.76))
        .preferredColorScheme(.dark)
        .onChange(of: roomIsPresenting) { _, isPresenting in
            if isPresenting { session.isPlaying = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.isPlaying = false }
        }
        .onDisappear { session.isPlaying = false }
        .task(id: session.isPlaying && !roomIsPresenting && scenePhase == .active) {
            guard session.isPlaying, !roomIsPresenting, scenePhase == .active else { return }
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .nanoseconds(33_333_333))
                guard !Task.isCancelled else { return }
                let now = clock.now
                session.advance(by: ReplayPresentationClock.seconds(previous.duration(to: now)))
                previous = now
            }
        }
    }

    private func comparison(_ capture: ReplayConversionPreviewSession.Capture) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text("VIDEO → REPLAY").font(.caption.monospaced().weight(.bold))
                        Text("Concept demo").font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(ReplayTheme.signal.opacity(0.15), in: Capsule())
                    }
                    Text(capture.scenario.title).font(.title2.weight(.bold)).lineLimit(2)
                    Text("Authored 3D · Manual comparison · No automatic conversion")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    dismissWindow(id: ReplayConversionPreviewSession.windowID)
                } label: {
                    Image(systemName: "xmark").frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Close comparison")
            }

            HStack(alignment: .top, spacing: 24) {
                ReplayReferenceSourceVideo(reference: capture.reference)
                    .id(capture.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Authored 3D replay", systemImage: "cube.transparent")
                            .font(.headline)
                        Spacer()
                        Text("Not time-aligned").font(.caption).foregroundStyle(.secondary)
                    }
                    if roomIsPresenting {
                        VStack(spacing: 16) {
                            Image(systemName: "vision.pro").font(.system(size: 42))
                            Text("3D room active").font(.title3.weight(.semibold))
                            Text("Move this video window beside the pitch.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("POVs and annotation tools are in the room.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Picker("Replay framing", selection: $framing) {
                            ForEach(ReplayComparisonPitchFraming.allCases) { framing in
                                Text(framing.rawValue).tag(framing)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityHint("Fixed play area or the complete pitch. The view does not follow a head.")
                        ReplayComparisonPitchView(capture: capture, playhead: session.playhead, framing: framing)
                            .id(capture.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(ReplayTheme.pitch.opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 18))
                        transport(duration: capture.scenario.duration)
                        Button {
                            enterRoom(capture)
                        } label: {
                            Label("Enter 3D · Player POVs", systemImage: "vision.pro")
                                .frame(maxWidth: .infinity).padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)
                        .disabled(ReplayAnnotationEntryPolicy.navigationBlockReason(in: store) != nil)
                        if annotationEntry != nil {
                            Button {
                                enterRoom(capture, annotating: true)
                            } label: {
                                Label("Annotate in 3D", systemImage: "pencil.and.outline")
                                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ReplayTheme.orange)
                            .foregroundStyle(.black)
                            .disabled(ReplayAnnotationEntryPolicy.blockReason(in: store) != nil)
                            .accessibilityHint("Opens drawing tools at the paused 3D replay time. Marks are saved on the replay, not the video.")
                        }
                        Text(ReplayAnnotationEntryPolicy.navigationBlockReason(in: store)
                            ?? "Timed marks are saved on the 3D replay. Source video is separate.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if hasRequestedRoom {
                            Text(store.statusMessage)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            Text("Player positions and off-camera movement are reconstructed, not measured tracking.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
    }

    private func transport(duration: TimeInterval) -> some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { session.playhead }, set: { session.seek(to: $0) }),
                   in: 0...max(duration, 0.001)) { Text("3D replay time") } onEditingChanged: { editing in
                if editing { session.isPlaying = false }
            }
                .tint(ReplayTheme.signal)
                .accessibilityValue("\(session.playhead.formatted(.number.precision(.fractionLength(1)))) seconds")
            HStack(spacing: 14) {
                Button { session.seek(to: 0); session.isPlaying = false } label: {
                    Image(systemName: "backward.end.fill").frame(width: 26, height: 26)
                }.accessibilityLabel("Restart 3D replay")
                Button { session.togglePlayback() } label: {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 26, height: 26)
                }.accessibilityLabel(session.isPlaying ? "Pause 3D replay" : "Play 3D replay")
                Text("\(session.playhead, specifier: "%.1f") / \(duration, specifier: "%.1f") s")
                    .font(.subheadline.monospacedDigit())
                Spacer()
                Menu {
                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { rate in
                        Button("\(rate.formatted())×") { session.playbackRate = rate }
                    }
                } label: {
                    Text("\(session.playbackRate.formatted())×").font(.subheadline.monospacedDigit())
                }
                .accessibilityLabel("3D replay speed, \(session.playbackRate.formatted()) times")
            }
            .buttonStyle(.bordered)
        }
    }

    private func enterRoom(_ capture: ReplayConversionPreviewSession.Capture, annotating: Bool = false) {
        guard !annotating || annotationEntry != nil else { return }
        let blockReason = annotating
            ? ReplayAnnotationEntryPolicy.blockReason(in: store)
            : ReplayAnnotationEntryPolicy.navigationBlockReason(in: store)
        guard blockReason == nil else { return }
        session.isPlaying = false
        store.selectScenario(id: capture.scenario.id, broadcast: false)
        guard store.selectedScenarioID == capture.scenario.id else { return }
        store.seek(to: session.playhead, broadcast: false)
        store.setLocalPerspective(capture.perspectiveID)
        // Preserve live/saved annotations. The read-only capture must never
        // replace edits made after the comparison window was opened.
        hasRequestedRoom = true
        ReplayRoomLauncher.open(store: store, openImmersiveSpace: openImmersiveSpace,
                                dismissWindow: dismissWindow,
                                annotationEntry: annotating ? annotationEntry : nil)
    }
}
