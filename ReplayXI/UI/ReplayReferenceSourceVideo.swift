import AVKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct ReplayReferenceSourceVideo: View {
    @Environment(ReplayConversionPreviewSession.self) private var session
    @Environment(ReplayStore.self) private var store
    let reference: ReplayVideoReference?
    @State private var source: Source = .none
    @State private var showsImporter = false
    @State private var embedReady = false
    @State private var embedError: String?
    @State private var embedAttempt = UUID()
    @State private var local = ReplayLocalReferencePlayer()
    @State private var localLoadTask: Task<Void, Never>?
    @State private var isVisible = false
    @State private var showsAlignmentHelp = false
    private enum Source { case none, official, local }

    private var roomIsPresenting: Bool {
        store.isImmersiveOpen || store.isOpeningImmersive || store.isClosingImmersive
    }

    private var roomIsTransitioning: Bool {
        store.isOpeningImmersive || store.isClosingImmersive
    }

    private var roomMatchesCapture: Bool {
        ReplayReferenceRoomClockPolicy.matches(
            isPresenting: roomIsPresenting,
            scenarioID: store.selectedScenarioID,
            captureScenarioID: session.capture?.scenario.id
        )
    }

    private var canMatchTimes: Bool {
        ReplayReferenceRoomClockPolicy.canCalibrate(
            isPresenting: roomIsPresenting,
            isTransitioning: roomIsTransitioning,
            matchesCapture: roomMatchesCapture
        )
    }

    private var replayTime: TimeInterval { roomMatchesCapture ? store.playhead : session.playhead }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Source video", systemImage: "film")
                    .font(.headline)
                Spacer()
                Button { showsImporter = true } label: {
                    Label("Choose clip", systemImage: "folder")
                }
                .accessibilityHint("Open a local video. It will not be converted or uploaded.")
            }
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.black)
                switch source {
                case .none: consent
                case .official:
                    if let reference {
                        ReplayYouTubePlayer(reference: reference, onReady: {
                            embedReady = true
                            embedError = nil
                        }, onFailure: { embedError = $0 })
                        .id(embedAttempt)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        if !embedReady, embedError == nil {
                            ProgressView("Loading source…").allowsHitTesting(false)
                        }
                        if let embedError { sourceError(embedError) }
                    }
                case .local:
                    if let player = local.player, local.error == nil {
                        VideoPlayer(player: player)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .allowsHitTesting(!local.isTimelineLinked)
                    } else if let error = local.error {
                        sourceError(error)
                    } else {
                        ProgressView("Opening clip…")
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            if source == .local {
                Text(local.filename).font(.subheadline).lineLimit(1).truncationMode(.middle)
                if local.player != nil { alignmentControls }
                Text("Time matching only · No video conversion")
                    .font(.caption).foregroundStyle(.secondary)
                if reference != nil {
                    Button("Use official reference") {
                        localLoadTask?.cancel()
                        source = .none
                        local.clear()
                    }
                        .buttonStyle(.bordered)
                }
            } else if let reference {
                HStack(alignment: .firstTextBaseline) {
                    Text(reference.shortLabel).font(.subheadline.weight(.semibold))
                    Spacer()
                    Link(destination: reference.sourceURL) {
                        Label(reference.timeRangeLabel, systemImage: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open official source, \(reference.timeRangeLabel)")
                }
                Text("Video and replay have separate timelines.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.movie]) { result in
            guard isVisible else { return }
            switch result {
            case .success(let url):
                localLoadTask?.cancel()
                source = .local
                localLoadTask = Task { await local.open(url) }
            case .failure(let error):
                guard (error as NSError).code != NSUserCancelledError else { return }
                local.reportImportError()
                source = .local
            }
        }
        .task(id: embedAttempt) {
            guard source == .official else { return }
            try? await Task.sleep(for: .seconds(18))
            guard !Task.isCancelled, source == .official, !embedReady, embedError == nil else { return }
            embedError = "The source is taking too long to load."
        }
        .onAppear { isVisible = true; syncLocalVideo() }
        .onChange(of: session.playhead) { _, _ in syncLocalVideo() }
        .onChange(of: session.isPlaying) { _, _ in syncLocalVideo() }
        .onChange(of: session.playbackRate) { _, _ in syncLocalVideo() }
        .onChange(of: local.isTimelineLinked) { _, _ in syncLocalVideo() }
        .onChange(of: store.playhead) { _, _ in if roomMatchesCapture { syncLocalVideo() } }
        .onChange(of: store.isPlaying) { _, _ in if roomMatchesCapture { syncLocalVideo() } }
        .onChange(of: store.playbackRate) { _, _ in if roomMatchesCapture { syncLocalVideo() } }
        .onChange(of: store.isImmersiveOpen) { _, _ in syncLocalVideo() }
        .onChange(of: roomIsPresenting) { _, _ in syncLocalVideo() }
        .onChange(of: roomIsTransitioning) { _, _ in syncLocalVideo() }
        .onChange(of: store.selectedScenarioID) { _, _ in syncLocalVideo() }
        .onDisappear {
            isVisible = false
            localLoadTask?.cancel()
            localLoadTask = nil
            local.clear()
            source = .none
        }
    }

    private var alignmentControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    pauseReplay()
                    local.setAlignmentStart(replayTime: replayTime)
                } label: {
                    Label("Match A", systemImage: local.alignmentStart == nil ? "1.circle" : "1.circle.fill")
                }
                .disabled(local.isTimelineLinked || local.isSeeking || !canMatchTimes)
                Button {
                    pauseReplay()
                    local.setAlignmentEnd(replayTime: replayTime)
                } label: {
                    Label("Match B", systemImage: local.alignment == nil ? "2.circle" : "2.circle.fill")
                }
                .disabled(local.alignmentStart == nil || local.isTimelineLinked || local.isSeeking || !canMatchTimes)
                Toggle("Link", isOn: $local.isTimelineLinked)
                    .toggleStyle(.button)
                    .disabled(local.alignment == nil)
                    .accessibilityHint("Use the 3D timeline to control both views after matching two moments.")
                Button { showsAlignmentHelp.toggle() } label: {
                    Image(systemName: "info.circle").frame(width: 28, height: 28)
                }
                    .accessibilityLabel("Time match help and reset")
                    .popover(isPresented: $showsAlignmentHelp) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Match two moments").font(.headline)
                            Text("Pause both views at the same moment. Tap A.\nChoose a later moment in both. Tap B.\nTurn on Link, then use the 3D timeline.")
                                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            Button("Reset time match", role: .destructive) {
                                local.resetAlignment()
                                showsAlignmentHelp = false
                            }
                        }.padding(22).frame(width: 340)
                    }
            }
            .buttonStyle(.bordered)
            Text(local.alignmentMessage ?? (local.isTimelineLinked
                ? "Linked · Replay controls both views"
                : local.alignment == nil ? "Match two moments, then link timelines" : "Time match ready"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func syncLocalVideo() {
        guard isVisible else { return }
        // Reconcile before reading session.playhead. The child and parent
        // onChange callbacks have no guaranteed order at final room close.
        session.reconcileRoomClock(isPresenting: roomIsPresenting,
            scenarioID: store.selectedScenarioID, roomPlayhead: store.playhead)
        guard source == .local else { return }
        guard canMatchTimes else {
            local.suspendLink(message: roomMatchesCapture
                ? "Wait for the room transition to finish."
                : "Return to this study to link its video.")
            return
        }
        local.synchronize(replayTime: replayTime,
                          playing: roomMatchesCapture ? store.isPlaying : session.isPlaying,
                          replayRate: roomMatchesCapture ? store.playbackRate : session.playbackRate)
    }

    private func pauseReplay() {
        session.isPlaying = false
        if roomMatchesCapture { store.setPlaying(false, broadcast: false) }
    }

    private var consent: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle").font(.system(size: 38))
            if reference != nil {
                Button("Load official video") {
                    embedReady = false
                    embedError = nil
                    source = .official
                    embedAttempt = UUID()
                }
                .buttonStyle(.borderedProminent)
                Text("Streams from YouTube. Your clips stay local.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Choose a local clip") { showsImporter = true }
                    .buttonStyle(.borderedProminent)
                Text("No official source is attached to this demo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private func sourceError(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.title)
            Text(message).multilineTextAlignment(.center)
            HStack {
                if source == .official, let reference {
                    Button("Retry") {
                        embedError = nil
                        embedReady = false
                        embedAttempt = UUID()
                    }
                    Link("Open source", destination: reference.sourceURL)
                }
                Button("Choose clip") { showsImporter = true }
            }
            .buttonStyle(.bordered)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Security-scoped access lasts only while this source window owns the clip.
/// Imported media never enters the review JSON or leaves the device.
@MainActor
@Observable
final class ReplayLocalReferencePlayer {
    private(set) var player: AVPlayer?
    private(set) var filename = "Local clip"
    private(set) var error: String?
    private(set) var duration: TimeInterval = 0
    private(set) var alignmentStart: ReplayReferenceTimeAlignment.Anchor?
    private(set) var alignment: ReplayReferenceTimeAlignment?
    private(set) var alignmentMessage: String?
    private(set) var isSeeking = false
    var isTimelineLinked = false {
        didSet {
            if oldValue, !isTimelineLinked {
                player?.pause()
                pendingSeek = nil
            }
        }
    }
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var pendingSeek: TimeInterval?

    func open(_ url: URL) async {
        guard !Task.isCancelled else { return }
        clear()
        let request = generation
        filename = url.lastPathComponent
        guard url.isFileURL else { error = "Choose a video stored in Files."; return }
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        do {
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration).seconds
            guard request == generation else { return }
            guard !Task.isCancelled else { releaseAccess(); return }
            guard playable, duration.isFinite, duration > 0 else {
                error = "This clip cannot play. Try an MP4 or MOV video."
                releaseAccess()
                return
            }
            let item = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: item)
            self.duration = duration
            itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let failed = item.status == .failed
                Task { @MainActor [weak self] in
                    guard let self, request == self.generation, failed else { return }
                    self.clear()
                    self.error = "This clip could not play. Try another video."
                }
            }
        } catch {
            guard request == generation else { return }
            self.error = "Clip unavailable. Check file access or choose another video."
            releaseAccess()
        }
    }

    func reportImportError() {
        clear()
        error = "The clip could not open. Please choose it again."
    }

    func setAlignmentStart(replayTime: TimeInterval) {
        guard let player, replayTime.isFinite, replayTime >= 0 else { return }
        guard !isSeeking else { alignmentMessage = "Wait for the clip to finish seeking."; return }
        player.pause()
        let time = player.currentTime().seconds
        guard time.isFinite, time >= 0, time <= duration else { return }
        resetAlignment()
        alignmentStart = .init(replay: replayTime, video: time)
    }

    func setAlignmentEnd(replayTime: TimeInterval) {
        guard let player, let start = alignmentStart else { return }
        guard !isSeeking else { alignmentMessage = "Wait for the clip to finish seeking."; return }
        player.pause()
        guard let map = ReplayReferenceTimeAlignment(start: start,
            end: .init(replay: replayTime, video: player.currentTime().seconds),
            videoDuration: duration) else {
            alignmentMessage = "Choose a later moment in both views (0.25–4× time scale)."
            return
        }
        alignment = map
        alignmentMessage = nil
    }

    func resetAlignment() {
        if isTimelineLinked { player?.pause() }
        isTimelineLinked = false
        alignmentStart = nil
        alignment = nil
        alignmentMessage = nil
        pendingSeek = nil
    }

    func synchronize(replayTime: TimeInterval, playing: Bool, replayRate: Double) {
        guard let player else { return }
        guard isTimelineLinked, let alignment else { return }
        guard let target = alignment.videoTime(for: replayTime), replayRate.isFinite,
              (0.1...4).contains(replayRate * alignment.rate) else {
            player.pause()
            alignmentMessage = alignment.videoTime(for: replayTime) == nil
                ? "Outside this clip" : "Use a slower replay speed to link video."
            return
        }
        alignmentMessage = nil
        let current = player.currentTime().seconds
        // AVPlayer runs between updates. Only correct meaningful drift; scrub
        // seeks coalesce while one decoder seek is in flight.
        if !current.isFinite || abs(current - target) > (playing ? 0.18 : 0.025) {
            seekVideo(to: target)
        }
        if playing {
            let rate = Float(replayRate * alignment.rate)
            if player.rate != rate { player.rate = rate }
        } else { player.pause() }
    }

    func suspendLink(message: String) {
        guard isTimelineLinked else { return }
        pendingSeek = nil
        player?.pause()
        alignmentMessage = message
    }

    private func seekVideo(to time: TimeInterval) {
        guard let player else { return }
        if isSeeking { pendingSeek = time; return }
        isSeeking = true
        let request = generation
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, request == self.generation else { return }
                self.isSeeking = false
                if let next = self.pendingSeek {
                    self.pendingSeek = nil
                    self.seekVideo(to: next)
                }
            }
        }
    }

    func clear() {
        generation = UUID()
        resetAlignment()
        duration = 0
        isSeeking = false
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        itemObservation?.invalidate()
        itemObservation = nil
        error = nil
        releaseAccess()
    }

    private func releaseAccess() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}
