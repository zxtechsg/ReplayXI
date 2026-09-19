import Foundation

/// Separate from In/Out: moving a saved position must not apply or reset the
/// visibility draft, and selecting another position must not discard typed text.
struct AnnotationPositionTimeDraft: Equatable {
    private(set) var selectedTime: TimeInterval?
    var text = ""

    var isDirty: Bool {
        guard let selectedTime else { return false }
        guard let destination = AnnotationTimestamp.parse(text) else { return true }
        return abs(destination - selectedTime) >= CoachMark.keyframeTimeTolerance
    }

    /// Nudge the text, not the replay. Invalid input is never replaced by the
    /// last valid time, and a replay edge is never silently clamped.
    func nudgedTime(by delta: TimeInterval, duration: TimeInterval) -> TimeInterval? {
        guard selectedTime != nil, delta.isFinite, abs(delta) >= CoachMark.keyframeTimeTolerance,
              duration.isFinite, duration >= 0,
              let current = AnnotationTimestamp.parse(text), (0...duration).contains(current) else { return nil }
        // Match the exact field's six-digit precision. This prevents repeated
        // decimal steps from drifting just beyond an otherwise valid edge.
        let destination = ((current + delta) * 1_000_000).rounded() / 1_000_000
        guard destination.isFinite, (0...duration).contains(destination),
              abs(destination - current) >= CoachMark.keyframeTimeTolerance else { return nil }
        return destination
    }

    @discardableResult
    mutating func nudge(by delta: TimeInterval, duration: TimeInterval) -> Bool {
        guard let destination = nudgedTime(by: delta, duration: duration) else { return false }
        text = AnnotationTimestamp.editable(destination)
        return true
    }

    func validationMessage(for mark: CoachMark, duration: TimeInterval) -> String? {
        guard let selectedTime,
              mark.keyframes?.contains(where: { abs($0.time - selectedTime) < CoachMark.keyframeTimeTolerance }) == true
        else { return "Select a saved position." }
        guard let destination = AnnotationTimestamp.parse(text) else {
            return "Use seconds or m:ss, e.g. 12.5 or 1:12.5."
        }
        guard duration.isFinite, duration >= 0, (0...duration).contains(destination) else {
            return "Keep the position time inside this replay."
        }
        guard isDirty else { return nil }
        return mark.canRetimeKeyframe(from: selectedTime, to: destination, duration: duration)
            ? nil : "A position is already saved at this time."
    }

    @discardableResult
    mutating func select(_ time: TimeInterval) -> Bool {
        guard !isDirty, time.isFinite, time >= 0 else { return false }
        acceptCommittedTime(time)
        return true
    }

    mutating func reset() {
        if let selectedTime {
            text = AnnotationTimestamp.editable(selectedTime)
        } else {
            text = ""
        }
    }

    mutating func acceptCommittedTime(_ time: TimeInterval) {
        selectedTime = time
        text = AnnotationTimestamp.editable(time)
    }

    mutating func clear() {
        selectedTime = nil
        text = ""
    }
}

enum AnnotationTimingEditPolicy {
    static func canLeaveEditor(windowIsDirty: Bool, positionIsDirty: Bool) -> Bool {
        !windowIsDirty && !positionIsDirty
    }

    static func visibilityLabel(for mark: CoachMark, at time: TimeInterval) -> String {
        mark.isVisible(at: time) ? "Inside In/Out" : "Outside In/Out"
    }

    static let outsideWindowHint = "Shown for editing. Close annotation to preview In/Out."
}
