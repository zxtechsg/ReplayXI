import Foundation

/// Shared by the map, timeline and inspector. Keep Mac timing semantics in
/// step with CoachMark: the show boundary is inclusive; hide is exclusive.
enum CoachWorkspace {
    static func isVisible(_ mark: ReplayXIWireMark, at time: Double) -> Bool {
        mark.showAt <= time && (mark.hideAt.map { time < $0 } ?? true)
    }

    static func matches(_ query: String, values: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let haystack = values.joined(separator: " ")
        return words.allSatisfy { haystack.localizedStandardContains(String($0)) }
    }

    static func adjacentKey(in keys: [Double], at time: Double, forward: Bool) -> Double? {
        let sorted = keys.filter(\.isFinite).sorted()
        return forward ? sorted.first { $0 > time + 0.001 } : sorted.last { $0 < time - 0.001 }
    }

    static func timelineTime(x: Double, width: Double, duration: Double) -> Double {
        guard x.isFinite, width.isFinite, width > 0, duration.isFinite, duration > 0 else { return 0 }
        return min(max(x / width, 0), 1) * duration
    }

    static func validWindow(show: Double, hide: Double?, duration: Double) -> Bool {
        guard show.isFinite, duration.isFinite, duration >= 0,
              (0...duration).contains(show) else { return false }
        return hide.map {
            let span = $0 - show
            return $0.isFinite && span >= 0.5 - 0.000_001 && span <= 30 + 0.000_001 && $0 <= duration
        } ?? true
    }

    static func clock(_ time: Double) -> String {
        // Reject corrupt/unbounded wire values before Double -> Int conversion.
        guard time.isFinite, time < 1_000_000_000 else { return "—" }
        let tenths = Int((max(0, time) * 10).rounded())
        return String(format: "%02d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }

    static func symbol(for kind: String) -> String {
        switch kind {
        case "pass": "arrow.up.forward"
        case "arc": "arrow.turn.up.right"
        case "space": "square.dashed"
        case "danger": "exclamationmark.triangle"
        case "playerLabel": "person.text.rectangle"
        default: "figure.run"
        }
    }

    static func title(for kind: String) -> String {
        switch kind {
        case "danger": "Pressure"
        case "playerLabel": "Player label"
        default: kind.capitalized
        }
    }
}
