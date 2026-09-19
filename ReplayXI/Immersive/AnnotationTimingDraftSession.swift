import Foundation
import Observation

/// Owned by the control deck, not a disposable drawer. A drawer can retract or
/// briefly remount without losing text that has not been applied to the replay.
@MainActor
@Observable
final class AnnotationTimingDraftSession {
    private(set) var markID: UUID?
    private(set) var scenarioID: String?
    private var baseline: CoachMark?
    @ObservationIgnored private weak var boundStore: ReplayStore?
    var window = AnnotationTimingDraft() { didSet { synchronizeOwnership() } }
    var position = AnnotationPositionTimeDraft() { didSet { synchronizeOwnership() } }

    var windowIsDirty: Bool { baseline.map { window.differs(from: $0) } ?? false }
    var hasUnsavedChanges: Bool { windowIsDirty || position.isDirty }

    @discardableResult
    func begin(mark: CoachMark, scenarioID: String, duration: TimeInterval, store: ReplayStore? = nil) -> Bool {
        if markID == mark.id, self.scenarioID == scenarioID {
            if let store { boundStore = store }
            refreshWindow(mark: mark, duration: duration)
            return true
        }
        guard !hasUnsavedChanges else { return false }
        releaseOwnership()
        boundStore = store
        self.markID = mark.id
        self.scenarioID = scenarioID
        baseline = mark
        window = AnnotationTimingDraft(mark: mark, duration: duration)
        position.clear()
        return true
    }

    func refreshWindow(mark: CoachMark, duration: TimeInterval) {
        guard markID == mark.id else { return }
        let keepDraft = windowIsDirty
        baseline = mark
        if !keepDraft { window = AnnotationTimingDraft(mark: mark, duration: duration) }
        synchronizeOwnership()
    }

    func resetWindow(mark: CoachMark, duration: TimeInterval) {
        guard markID == mark.id else { return }
        baseline = mark
        window = AnnotationTimingDraft(mark: mark, duration: duration)
    }

    func canApply(in store: ReplayStore) -> Bool {
        guard hasUnsavedChanges, store.canChangePlaybackView, store.localRole == .coach,
              store.triangleLockMode != .place, scenarioID == store.selectedScenarioID,
              let markID, let mark = store.marks.first(where: { $0.id == markID }),
              store.pendingAnnotationTimingEditID == nil || store.pendingAnnotationTimingEditID == markID,
              !store.selectedScenario.coachMarks.contains(where: { $0.id == markID }) else { return false }
        if windowIsDirty, window.validationMessage(duration: store.selectedScenario.duration) != nil { return false }
        if position.isDirty {
            guard let from = position.selectedTime, let to = AnnotationTimestamp.parse(position.text),
                  mark.canRetimeKeyframe(from: from, to: to, duration: store.selectedScenario.duration) else { return false }
        }
        return true
    }

    @discardableResult
    func apply(in store: ReplayStore) -> Bool {
        guard canApply(in: store), let markID else { return false }
        let positionTime = position.isDirty ? AnnotationTimestamp.parse(position.text) : nil
        guard store.applyCoachMarkTimingDraft(id: markID,
            windowStart: windowIsDirty ? window.start : nil,
            windowEnd: windowIsDirty && !window.throughEnd ? window.end : nil,
            keyframeFrom: position.isDirty ? position.selectedTime : nil,
            keyframeTo: positionTime) else { return false }
        if let positionTime { position.acceptCommittedTime(positionTime) }
        if let current = store.marks.first(where: { $0.id == markID }) {
            resetWindow(mark: current, duration: store.selectedScenario.duration)
        }
        return !hasUnsavedChanges
    }

    func discard(in store: ReplayStore) {
        if scenarioID == store.selectedScenarioID, let markID,
           let current = store.marks.first(where: { $0.id == markID }) {
            resetWindow(mark: current, duration: store.selectedScenario.duration)
        } else if let baseline {
            // Even if a system transition removed the source, Discard must not
            // write a draft onto a different scenario or make a new annotation.
            window = AnnotationTimingDraft(mark: baseline, duration: max(baseline.hideTime ?? baseline.revealTime, 0))
        }
        position.reset()
    }

    /// Input bindings publish synchronously; a navigation request in the same
    /// main-actor turn cannot race the next SwiftUI observation/layout pass.
    private func synchronizeOwnership() {
        guard let boundStore, let markID else { return }
        _ = boundStore.setAnnotationTimingDraftPending(id: markID, isPending: hasUnsavedChanges)
    }

    func releaseOwnership() {
        if let boundStore, let markID {
            _ = boundStore.setAnnotationTimingDraftPending(id: markID, isPending: false)
        }
        boundStore = nil
    }
}

struct AnnotationTimingDeckRoute: Equatable {
    var selection: UUID?
    var panel: PlaybackInlinePanel?
    var showsTools: Bool
    var showsPlayers: Bool
    var showsEvents: Bool
    var showsDecisions: Bool
    var showsDrawing: Bool
    var showsClear: Bool
    var showsAnnotations: Bool
}

enum AnnotationTimingNavigationRequest: Equatable {
    case route(AnnotationTimingDeckRoute)
    case exit
    /// Domain actions are rejected before mutation; resolve, then retry them.
    case retryExternalAction
}

struct AnnotationTimingNavigationGate {
    private(set) var protectedRoute: AnnotationTimingDeckRoute?
    private(set) var request: AnnotationTimingNavigationRequest?

    mutating func observeDraft(isDirty: Bool, route: AnnotationTimingDeckRoute) {
        if isDirty {
            if protectedRoute == nil { protectedRoute = route }
        } else {
            protectedRoute = nil
        }
    }

    /// Preserve the first intended destination while SwiftUI reconciles the
    /// rollback's individual bindings. Intermediate routes must not replace it.
    mutating func protect(_ attempted: AnnotationTimingDeckRoute) -> AnnotationTimingDeckRoute? {
        guard let protectedRoute, attempted != protectedRoute else { return nil }
        if request == nil { request = .route(attempted) }
        return protectedRoute
    }

    mutating func ask(_ requested: AnnotationTimingNavigationRequest) {
        if request == nil { request = requested }
    }

    mutating func keepEditing() { request = nil }

    mutating func consume() -> AnnotationTimingNavigationRequest? {
        defer { request = nil; protectedRoute = nil }
        return request
    }
}
