import AVKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct ReplayReferenceSourceVideo: View {
    let reference: ReplayVideoReference?
    @State private var source: Source = .none
    @State private var showsImporter = false
    @State private var embedReady = false
    @State private var embedError: String?
    @State private var embedAttempt = UUID()
    @State private var local = ReplayLocalReferencePlayer()
    @State private var localLoadTask: Task<Void, Never>?
    @State private var isVisible = false
    private enum Source { case none, official, local }

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
                Text("Your clip is a reference only. The 3D demo is unchanged.")
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
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            localLoadTask?.cancel()
            localLoadTask = nil
            local.clear()
        }
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
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?

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

    func clear() {
        generation = UUID()
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
