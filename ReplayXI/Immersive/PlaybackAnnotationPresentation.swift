import Foundation

/// View/stage eligibility is separate from a mark's time window or render
/// budget. A timeline can offer a future mark, but not a mark that its current
/// presentation deliberately hides at every timestamp.
struct PlaybackAnnotationPresentation: Equatable, Sendable {
    let viewMode: ReplayViewMode
    let triangleLockMode: TriangleLockMode
    let showsIdealBranch: Bool

    func isEligible(_ mark: CoachMark, in scenario: ReplayScenario) -> Bool {
        guard viewMode == .positional else { return true }
        // Logical placement owns input even while its tracked origin is lost.
        guard triangleLockMode != .place else { return false }
        // Preset pressure belongs to Problem; coach-created marks belong to
        // either visual comparison. Keep this check allocation-free per frame.
        let isPreset = scenario.coachMarks.contains { $0.id == mark.id }
        return !isPreset || (!showsIdealBranch && mark.kind == .danger)
    }

    func orderedReviewMarks(_ marks: [CoachMark], in scenario: ReplayScenario) -> [CoachMark] {
        marks.filter { isEligible($0, in: scenario) }.sorted {
            $0.revealTime == $1.revealTime
                ? $0.id.uuidString < $1.id.uuidString
                : $0.revealTime < $1.revealTime
        }
    }

    func reconciledSelection(
        _ selectedID: UUID?,
        marks: [CoachMark],
        scenario: ReplayScenario,
        canChangePlaybackView: Bool
    ) -> UUID? {
        // A context observer must not close the shelf that owns a hand. The
        // common host rechecks this same policy when the existing gate opens.
        guard canChangePlaybackView, let selectedID else { return selectedID }
        guard let selected = marks.first(where: { $0.id == selectedID }),
              isEligible(selected, in: scenario) else { return nil }
        return selectedID
    }
}
