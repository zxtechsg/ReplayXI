import Foundation
import Observation

struct AnnotationHandleInputSample {
    let gestureID: UUID?
    let target: AnnotationSceneTarget
    let sourceID: ObjectIdentifier
    let startLocation: SIMD3<Double>
    let time: Date

    var isFinite: Bool {
        startLocation.x.isFinite && startLocation.y.isFinite && startLocation.z.isFinite
            && time.timeIntervalSinceReferenceDate.isFinite
    }
}

/// Store generations provide strict ownership. Native DragGesture supplies no
/// event ID, so nil-token ends also require the captured source/start/time gate.
@MainActor @Observable
final class AnnotationHandleDragController {
    private struct Active {
        let gestureID: UUID
        let source: AnnotationHandleInputSample
        var latestTime: Date
    }
    private var active: Active?
    @ObservationIgnored private var finishedGestures: [UUID] = []
    @ObservationIgnored private var latestRetiredTime: Date?
    var target: AnnotationSceneTarget? { active?.source.target }
    var gestureID: UUID? { active?.gestureID }

    @discardableResult
    func preview(_ sample: AnnotationHandleInputSample, point: PitchPoint, in store: ReplayStore) -> Bool {
        guard sample.isFinite, let gestureID = sample.gestureID,
              sample.target.role == .start || sample.target.role == .end else { return false }
        if let active, !store.isCoachMarkHandlePreviewOwner(id: active.source.target.markID, gestureID: active.gestureID) {
            // Authority may cancel A before its view receives cleanup. Retire
            // local A without touching a different Store owner, then admit B.
            retire(active.gestureID)
        }
        guard !finishedGestures.contains(gestureID),
              latestRetiredTime.map({ sample.time >= $0 }) ?? true else { return false }
        if let active {
            guard admits(sample, for: active, allowsResetToken: false) else { return false }
        }
        let endpoint: CoachMarkEndpoint = sample.target.role == .start ? .start : .end
        guard store.previewCoachMarkHandle(id: sample.target.markID, endpoint: endpoint,
            gestureID: gestureID, point: point) else { return false }
        if var current = active {
            current.latestTime = sample.time
            active = current
        } else {
            active = Active(gestureID: gestureID, source: sample, latestTime: sample.time)
        }
        return true
    }

    @discardableResult
    func finish(_ sample: AnnotationHandleInputSample, point: PitchPoint?, in store: ReplayStore) -> Bool {
        guard let active, admits(sample, for: active, allowsResetToken: true) else { return false }
        self.active?.latestTime = sample.time
        defer { retire(active.gestureID) }
        guard let point else {
            _ = store.cancelCoachMarkHandlePreview(id: active.source.target.markID, gestureID: active.gestureID)
            return false
        }
        return store.commitCoachMarkHandlePreview(id: active.source.target.markID,
            gestureID: active.gestureID, point: point)
    }

    @discardableResult
    func cancel(in store: ReplayStore, gestureID: UUID) -> Bool {
        guard let active, active.gestureID == gestureID else { return false }
        let cancelled = store.cancelCoachMarkHandlePreview(id: active.source.target.markID, gestureID: gestureID)
        retire(gestureID)
        return cancelled
    }

    func cancelCurrent(in store: ReplayStore) {
        if let gestureID { _ = cancel(in: store, gestureID: gestureID) }
    }

    /// GestureState can reset before onEnded. Give that final sample one actor
    /// turn, then roll back a missing end. Captured A cannot cancel a newer B.
    func scheduleInterruptedCleanup(in store: ReplayStore, gestureID: UUID) {
        Task { @MainActor [weak self, weak store] in
            await Task.yield()
            guard let self, let store else { return }
            _ = self.cancel(in: store, gestureID: gestureID)
        }
    }

    private func admits(_ sample: AnnotationHandleInputSample, for active: Active, allowsResetToken: Bool) -> Bool {
        sample.isFinite
            && (sample.gestureID == active.gestureID || (allowsResetToken && sample.gestureID == nil))
            && sample.target == active.source.target
            && sample.sourceID == active.source.sourceID
            && sample.startLocation == active.source.startLocation
            && sample.time >= active.latestTime
    }

    private func retire(_ gestureID: UUID) {
        guard let active, active.gestureID == gestureID else { return }
        latestRetiredTime = max(latestRetiredTime ?? active.latestTime, active.latestTime)
        self.active = nil
        finishedGestures.append(gestureID)
        if finishedGestures.count > 128 { finishedGestures.removeFirst() }
    }
}
