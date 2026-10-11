import Foundation
import Observation

/// An ephemeral comparison, not a generated scenario or part of saved reviews.
/// Capture values so changing the dashboard cannot silently pair another play
/// with a video that is already open.
@MainActor
@Observable
final class ReplayConversionPreviewSession {
    struct Capture: Identifiable, Sendable {
        let id = UUID()
        let scenario: ReplayScenario
        let marks: [CoachMark]
        let perspectiveID: String
        let reference: ReplayVideoReference?
    }

    static let windowID = "ReplayVideoComparison"
    private(set) var capture: Capture?
    private(set) var playhead: TimeInterval = 0
    var isPlaying = false
    var playbackRate: Double = 1
    @ObservationIgnored private var presentedMatchingRoom = false

    func capture(scenario: ReplayScenario, marks: [CoachMark],
                 playhead: TimeInterval, perspectiveID: String) {
        presentedMatchingRoom = false
        capture = Capture(scenario: scenario, marks: marks,
            perspectiveID: scenario.player(id: perspectiveID) == nil
                ? scenario.defaultPerspectiveID : perspectiveID,
            reference: ReplayReferenceLibrary.reference(for: scenario.id))
        isPlaying = false
        playbackRate = 1
        seek(to: playhead)
    }

    /// Room callbacks can finish in either order. Retain its final clock only
    /// after the whole presentation has closed, including rooms opened from
    /// somewhere other than this comparison window.
    func reconcileRoomClock(isPresenting: Bool, scenarioID: String,
                            roomPlayhead: TimeInterval) {
        let matches = capture?.scenario.id == scenarioID
        if isPresenting {
            if isPlaying { isPlaying = false }
            if matches { presentedMatchingRoom = true }
        } else {
            if presentedMatchingRoom && matches { seek(to: roomPlayhead) }
            presentedMatchingRoom = false
        }
    }

    func seek(to time: TimeInterval) {
        let duration = max(0, capture?.scenario.duration ?? 0)
        playhead = time.isFinite ? min(max(time, 0), duration) : 0
    }

    func togglePlayback() {
        guard let capture, capture.scenario.duration > 0 else { return }
        if !isPlaying, playhead >= capture.scenario.duration { seek(to: 0) }
        isPlaying.toggle()
    }

    func advance(by elapsed: TimeInterval) {
        guard isPlaying, elapsed.isFinite, elapsed > 0,
              playbackRate.isFinite, playbackRate > 0,
              let capture else { return }
        // Resume never jumps through a whole clip after the window was inactive.
        seek(to: playhead + min(elapsed, 0.1) * min(playbackRate, 4))
        if playhead >= capture.scenario.duration { isPlaying = false }
    }
}

enum ReplayReferenceRoomClockPolicy {
    static func matches(isPresenting: Bool, scenarioID: String,
                        captureScenarioID: String?) -> Bool {
        isPresenting && captureScenarioID == scenarioID
    }

    static func canCalibrate(isPresenting: Bool, isTransitioning: Bool,
                             matchesCapture: Bool) -> Bool {
        !isPresenting || (!isTransitioning && matchesCapture)
    }
}

/// Two human-matched moments align a local clip to an authored replay. This is
/// a time calibration only: it never changes tracks or claims video conversion.
struct ReplayReferenceTimeAlignment: Equatable, Sendable {
    struct Anchor: Equatable, Sendable {
        let replay: TimeInterval
        let video: TimeInterval
    }

    let start: Anchor
    let end: Anchor
    let videoDuration: TimeInterval
    var rate: Double { (end.video - start.video) / (end.replay - start.replay) }

    init?(start: Anchor, end: Anchor, videoDuration: TimeInterval) {
        guard videoDuration.isFinite, videoDuration > 0,
              start.replay.isFinite, end.replay.isFinite,
              start.video.isFinite, end.video.isFinite,
              start.replay >= 0, end.replay - start.replay >= 0.1,
              start.video >= 0, end.video <= videoDuration,
              end.video - start.video >= 0.1 else { return nil }
        let ratio = (end.video - start.video) / (end.replay - start.replay)
        guard (0.25...4).contains(ratio) else { return nil }
        self.start = start
        self.end = end
        self.videoDuration = videoDuration
    }

    func videoTime(for replayTime: TimeInterval) -> TimeInterval? {
        guard replayTime.isFinite else { return nil }
        let time = start.video + (replayTime - start.replay) * rate
        guard time >= 0, time <= videoDuration else { return nil }
        return time
    }
}

/// All strings interpolated into the player document are restricted before use.
/// The app identity follows YouTube's documented native-WebView requirement.
enum ReplayReferenceEmbed {
    static func clientOrigin(bundleID: String) -> URL? {
        let normalized = bundleID.lowercased()
        guard !normalized.isEmpty,
              normalized.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-").contains($0)
              }) else { return nil }
        return URL(string: "https://\(normalized)")
    }

    static func accepts(videoID: String) -> Bool {
        videoID.count == 11 && videoID.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
                .contains($0)
        }
    }

    static func errorMessage(code: Int) -> String {
        switch code {
        case 100: "This video is unavailable."
        case 101, 150: "The publisher does not allow embedded playback."
        case 153: "YouTube could not verify this player."
        case 2: "This video reference is invalid."
        default: "The video could not play here."
        }
    }
}
