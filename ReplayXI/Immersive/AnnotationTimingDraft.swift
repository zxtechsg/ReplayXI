import Foundation

/// Keep typed text separate from replay state, including temporarily invalid input.
/// Applying must never silently use the last successfully parsed field value.
struct AnnotationTimingDraft: Equatable {
    var startText = "0"
    var endText = "1"
    var throughEnd = false

    init() {}

    init(mark: CoachMark, duration: TimeInterval) {
        startText = AnnotationTimestamp.editable(mark.revealTime)
        endText = AnnotationTimestamp.editable(min(mark.hideTime ?? duration, duration))
        throughEnd = mark.hideTime == nil
    }

    var start: TimeInterval? { AnnotationTimestamp.parse(startText) }
    var end: TimeInterval? { AnnotationTimestamp.parse(endText) }

    func validationMessage(duration: TimeInterval) -> String? {
        guard let start, throughEnd || end != nil else { return "Use seconds or m:ss, e.g. 12.5 or 1:12.5." }
        guard duration.isFinite, duration >= 0, (0...duration).contains(start),
              throughEnd || end.map({ (0...duration).contains($0) }) == true else {
            return "Keep In and Out inside this replay."
        }
        if !throughEnd, let end {
            guard end - start >= 0.5 else { return "Out must be at least 0.5 seconds after In." }
            guard end - start <= CoachMarkTimingPolicy.maximumDuration else {
                return "Use a window up to 30 seconds, or choose To end."
            }
        }
        return nil
    }

    func differs(from mark: CoachMark) -> Bool {
        guard let start else { return true }
        if abs(start - mark.revealTime) > 0.000_001 { return true }
        if throughEnd { return mark.hideTime != nil }
        guard let end, let hideTime = mark.hideTime else { return true }
        return abs(end - hideTime) > 0.000_001
    }
}

enum AnnotationTimestamp {
    /// Decimal seconds and minute:second timestamps. Reject partial or non-finite
    /// strings rather than clamping a mistyped value into an unrelated timestamp.
    static func parse(_ text: String) -> TimeInterval? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !input.isEmpty, input.count <= 32 else { return nil }
        let fields = input.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 1 || fields.count == 2,
              let secondsText = fields.last, !secondsText.isEmpty,
              secondsText.allSatisfy({ $0.isNumber || $0 == "." }),
              let seconds = Double(secondsText), seconds.isFinite, seconds >= 0 else { return nil }
        guard fields.count == 2 else { return seconds }
        guard !fields[0].isEmpty, fields[0].allSatisfy(\.isNumber),
              let minutes = Double(fields[0]), minutes.isFinite, seconds < 60 else { return nil }
        let result = minutes * 60 + seconds
        return result.isFinite ? result : nil
    }

    static func editable(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "" }
        var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), time)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    static func display(_ time: TimeInterval, fractionalDigits: Int = 1) -> String {
        let digits = min(max(fractionalDigits, 1), 6)
        let scale = [10, 100, 1_000, 10_000, 100_000, 1_000_000][digits - 1]
        // Round before splitting so 59.99 displays as 01:00.0, never 00:60.0.
        let rounded = (time * Double(scale)).rounded()
        guard time.isFinite, time >= 0, rounded.isFinite, rounded < Double(Int.max) else { return "—" }
        let units = Int(rounded)
        func padded(_ value: Int, to width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(padded(units / scale / 60, to: 2)):\(padded((units / scale) % 60, to: 2)).\(padded(units % scale, to: digits))"
    }
}

/// Saved positions can be closer than a tenth of a second. Use the least
/// precision that distinguishes them, computed only when their times change.
struct AnnotationKeyTimeLabels {
    private var labels: [TimeInterval: String] = [:]

    init(times: [TimeInterval] = []) {
        let valid = Set(times.filter { $0.isFinite && $0 >= 0 })
        for digits in 1...6 {
            labels = Dictionary(uniqueKeysWithValues: valid.map {
                ($0, AnnotationTimestamp.display($0, fractionalDigits: digits))
            })
            if Set(labels.values).count == valid.count { break }
        }
    }

    func label(at time: TimeInterval) -> String {
        labels[time] ?? AnnotationTimestamp.display(time)
    }
}
