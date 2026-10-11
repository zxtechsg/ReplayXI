import Foundation

/// Deterministic admission control for independently rendered coach marks.
/// Shared playback can retain 128 annotations for history and collaboration,
/// but only a small, relevant set should occupy the GPU or the user's view at
/// one instant.
enum PlaybackSceneRenderBudget {
    static let normalAnnotationDrawLimit = 18
    // Every mark kind costs at least four draws, even before keyed elevation
    // guides are counted. Keep this in sync with estimatedDraws(for:).
    private static let minimumAnnotationDraws = 4
    // An elevated press/danger mark includes two ground tethers. Reserve room
    // for all thirteen draws so the selected mark remains complete.
    static let decisionAnnotationDrawLimit = 13
    static let selectedEditableOverlayDraws = 11
    static let selectedReadOnlyOverlayDraws = 4
    static let selectedAnnotationSystemDrawLimit = 24

    static func estimatedDraws(for kind: CoachMarkKind) -> Int {
        switch kind {
        case .run, .pass, .arc:
            5 // board + accent + glyph + path + arrow
        case .danger:
            11 // board + accent + glyph + seven dashes + arrow
        case .space:
            4 // board + accent + glyph + one batched ring
        case .playerLabel:
            6 // board + accent + glyph + ring + inset + tether
        }
    }

    static func estimatedDraws(for mark: CoachMark) -> Int {
        let base = estimatedDraws(for: mark.kind)
        guard mark.kind != .playerLabel else { return base }
        return base
            + (mark.resolvedStartElevation > 0.001 ? 1 : 0)
            + (mark.resolvedEndElevation > 0.001 ? 1 : 0)
    }

    /// Admission must count the guides rendered at this timestamp, not the
    /// saved base pose. Reuse the renderer's absolute keyframe sampler so
    /// interpolation, held endpoints and reverse seeks share its threshold.
    static func estimatedDraws(for mark: CoachMark, at time: TimeInterval) -> Int {
        guard mark.hasKeyframes else { return estimatedDraws(for: mark) }
        return estimatedDraws(for: mark.sampled(at: time))
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
        decisionReviewIsVisible: Bool,
        sampledDrawCost: (CoachMark, TimeInterval) -> Int = {
            PlaybackSceneRenderBudget.estimatedDraws(for: $0, at: $1)
        },
        isEligible: (CoachMark) -> Bool = { _ in true }
    ) -> Set<UUID> {
        // Presentation-hidden marks must not reserve either geometry or
        // selection draws. Keep the cached priority indices over all history;
        // a mode-specific predicate avoids building a filtered array per frame.
        let selected = selectedID.flatMap { id in
            marks.first {
                $0.id == id && isEligible($0)
                    && ($0.isVisible(at: time) || selectedIsEditable)
            }
        }
        let baseDrawLimit = decisionReviewIsVisible
            ? decisionAnnotationDrawLimit
            : normalAnnotationDrawLimit
        let selectionReserve: Int = if selected == nil {
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

        if let selected {
            result.insert(selected.id)
            consumedDraws += sampledDrawCost(selected, time)
        }

        for index in priorityIndices {
            // No remaining kind can fit. In a dense keyed history this avoids
            // sampling the many unseen 64-key tracks after admission fills.
            guard drawLimit - consumedDraws >= minimumAnnotationDraws else { break }
            guard marks.indices.contains(index) else { continue }
            let mark = marks[index]
            guard mark.id != selected?.id,
                  isEligible(mark),
                  mark.isVisible(at: time) else { continue }
            // Keyframes may add guides but never reduce the kind's base cost.
            // Do not interpolate a track that cannot fit even at ground level.
            guard estimatedDraws(for: mark.kind) <= drawLimit - consumedDraws else { continue }
            let cost = sampledDrawCost(mark, time)
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
            total += estimatedDraws(for: mark)
        }
    }
}
