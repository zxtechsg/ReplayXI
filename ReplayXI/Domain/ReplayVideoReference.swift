import Foundation

/// Provenance for an authored reconstruction, separate from saved replay state.
/// A source link is evidence for the visible action, not measured player tracking.
struct ReplayVideoReference: Hashable, Sendable {
    let matchTitle: String
    let shortLabel: String
    let videoID: String
    let startSeconds: Int
    let endSeconds: Int
    let reconstructionNote: String
    let alternateAngles: [ReplayVideoReferenceAngle]

    init(matchTitle: String, shortLabel: String, videoID: String,
         startSeconds: Int, endSeconds: Int, reconstructionNote: String,
         alternateAngles: [ReplayVideoReferenceAngle] = []) {
        self.matchTitle = matchTitle
        self.shortLabel = shortLabel
        self.videoID = videoID
        self.startSeconds = max(0, startSeconds)
        self.endSeconds = max(self.startSeconds, endSeconds)
        self.reconstructionNote = reconstructionNote
        self.alternateAngles = alternateAngles
    }

    /// YouTube's watch-page timestamp opens the beginning of the source window.
    /// The end is a review guide, not a claim that the external player will stop.
    var sourceURL: URL {
        sourceURL(at: startSeconds)
    }

    func sourceURL(at seconds: Int) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [
            URLQueryItem(name: "v", value: videoID),
            URLQueryItem(name: "t", value: "\(max(0, seconds))s")
        ]
        return components.url!
    }

    var timeRangeLabel: String {
        "\(Self.timestamp(startSeconds))–\(Self.timestamp(endSeconds))"
    }

    private static func timestamp(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        let remainder = seconds % 60
        let paddedSeconds = remainder < 10 ? "0\(remainder)" : "\(remainder)"
        guard hours > 0 else { return "\(minutes):\(paddedSeconds)" }
        let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        return "\(hours):\(paddedMinutes):\(paddedSeconds)"
    }
}

struct ReplayVideoReferenceAngle: Hashable, Sendable {
    let title: String
    let startSeconds: Int
}
