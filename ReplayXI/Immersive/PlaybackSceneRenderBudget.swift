import Foundation

/// Deterministic admission control for independently rendered coach marks.
/// Shared playback can retain 128 annotations for history and collaboration,
/// but only a small, relevant set should occupy the GPU or the user's view at
/// one instant.
enum PlaybackSceneRenderBudget {
    static let normalAnnotationDrawLimit = 18
    // One selected press/danger annotation costs eleven draws by itself. Keep
    // the focused-review envelope large enough to preserve that selected mark
    // while still admitting no unrelated geometry beside it.
    static let decisionAnnotationDrawLimit = 11
    static let selectedEditableOverlayDraws = 11
    static let selectedReadOnlyOverlayDraws = 4
    static let selectedAnnotationSystemDrawLimit = 22

    static func estimatedDraws(for kind: CoachMarkKind) -> Int {
        switch kind {
        case .run, .pass:
            5 // board + accent + glyph + path + arrow
        case .danger:
            11 // board + accent + glyph + seven dashes + arrow
        case .space:
            4 // board + accent + glyph + one batched ring
        case .playerLabel:
            6 // board + accent + glyph + ring + inset + tether
        }
    }

    /// Computes stable recency once when annotation identity/timing changes.
    /// The original index is the deterministic tie break, so no UUID strings
    /// are created in the playback path.
    static func priorityIndices(for marks: [CoachMark]) -> [Int] {
        marks.indices.sorted { lhs, rhs in
            let lhsTime = marks[lhs].revealTime
            let rhsTime = marks[rhs].revealTime
            return lhsTime == rhsTime ? lhs < rhs : lhsTime > rhsTime
        }
    }

    /// Selected content always wins. Remaining visible marks arrive in cached
    /// recency order and are greedily packed into the conservative envelope.
    static func visibleAnnotationIDs(
        in marks: [CoachMark],
        priorityIndices: [Int],
        at time: TimeInterval,
        selectedID: UUID?,
        selectedIsEditable: Bool,
        decisionReviewIsVisible: Bool
    ) -> Set<UUID> {
        let baseDrawLimit = decisionReviewIsVisible
            ? decisionAnnotationDrawLimit
            : normalAnnotationDrawLimit
        let selectionReserve: Int = if selectedID == nil {
            0
        } else if selectedIsEditable {
            selectedEditableOverlayDraws
        } else {
            selectedReadOnlyOverlayDraws
        }
        let drawLimit = min(
            baseDrawLimit,
            max(selectedAnnotationSystemDrawLimit - selectionReserve, 0)
        )
        guard drawLimit > 0 else { return [] }

        var result: Set<UUID> = []
        result.reserveCapacity(5)
        var consumedDraws = 0

        if let selectedID,
           let selected = marks.first(where: { $0.id == selectedID }),
           selected.isVisible(at: time) || selectedIsEditable {
            result.insert(selectedID)
            consumedDraws += estimatedDraws(for: selected.kind)
        }

        for index in priorityIndices {
            guard marks.indices.contains(index) else { continue }
            let mark = marks[index]
            guard mark.id != selectedID, mark.isVisible(at: time) else { continue }
            let cost = estimatedDraws(for: mark.kind)
            guard consumedDraws + cost <= drawLimit else { continue }
            result.insert(mark.id)
            consumedDraws += cost
        }
        return result
    }

    static func estimatedAnnotationDraws(
        for marks: [CoachMark],
        visibleIDs: Set<UUID>
    ) -> Int {
        marks.reduce(into: 0) { total, mark in
            guard visibleIDs.contains(mark.id) else { return }
            total += estimatedDraws(for: mark.kind)
        }
    }
}
