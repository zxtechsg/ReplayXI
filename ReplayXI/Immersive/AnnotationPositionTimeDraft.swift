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
