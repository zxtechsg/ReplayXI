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
        let controlOrigin: SIMD3<Float>?
        let controlStart: SIMD3<Float>?
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
        if let active, !ownsStorePreview(active, in: store) {
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
            active = Active(gestureID: gestureID, source: sample, latestTime: sample.time,
                            controlOrigin: nil, controlStart: nil)
        }
        return true
    }

    @discardableResult
    func preview(_ sample: AnnotationHandleInputSample, controlLocation: SIMD3<Float>,
                 startLocation: SIMD3<Float>,
                 in store: ReplayStore) -> Bool {
        guard sample.isFinite, let gestureID = sample.gestureID,
              sample.target.role == .control,
              Self.finite(controlLocation), Self.finite(startLocation) else { return false }
        if let active, !ownsStorePreview(active, in: store) {
            retire(active.gestureID)
        }
        guard !finishedGestures.contains(gestureID),
              latestRetiredTime.map({ sample.time >= $0 }) ?? true else { return false }
        if let active {
            guard admits(sample, for: active, allowsResetToken: false) else { return false }
        }
        guard let mark = store.marks.first(where: { $0.id == sample.target.markID }),
              mark.kind == .arc else { return false }
        let controlOrigin = active?.controlOrigin ?? displayedControlPoint(for: mark, in: store)
        let controlStart = active?.controlStart ?? startLocation
        let controlPoint = controlOrigin + controlLocation - controlStart
        let curve = curve(for: controlPoint, mark: mark, in: store)
        guard store.previewCoachMarkCurve(id: mark.id, gestureID: gestureID, curve: curve) else {
            return false
        }
        if var current = active {
            current.latestTime = sample.time
            active = current
        } else {
            active = Active(gestureID: gestureID, source: sample, latestTime: sample.time,
                            controlOrigin: controlOrigin, controlStart: controlStart)
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
    func finish(_ sample: AnnotationHandleInputSample, controlLocation: SIMD3<Float>?,
                in store: ReplayStore) -> Bool {
        guard let active, active.source.target.role == .control,
              admits(sample, for: active, allowsResetToken: true) else { return false }
        self.active?.latestTime = sample.time
        defer { retire(active.gestureID) }
        guard let controlLocation, Self.finite(controlLocation),
              let controlOrigin = active.controlOrigin,
              let controlStart = active.controlStart,
              let mark = store.marks.first(where: { $0.id == active.source.target.markID }),
              mark.kind == .arc else {
            _ = store.cancelCoachMarkCurvePreview(id: active.source.target.markID,
                                                  gestureID: active.gestureID)
            return false
        }
        let controlPoint = controlOrigin + controlLocation - controlStart
        let curve = curve(for: controlPoint, mark: mark, in: store)
        guard store.previewCoachMarkCurve(id: mark.id, gestureID: active.gestureID,
                                         curve: curve) else {
            _ = store.cancelCoachMarkCurvePreview(id: mark.id, gestureID: active.gestureID)
            return false
        }
        return store.commitCoachMarkCurvePreview(id: mark.id, gestureID: active.gestureID)
    }

    @discardableResult
    func cancel(in store: ReplayStore, gestureID: UUID) -> Bool {
        guard let active, active.gestureID == gestureID else { return false }
        let cancelled = active.source.target.role == .control
            ? store.cancelCoachMarkCurvePreview(id: active.source.target.markID, gestureID: gestureID)
            : store.cancelCoachMarkHandlePreview(id: active.source.target.markID, gestureID: gestureID)
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

    private func ownsStorePreview(_ active: Active, in store: ReplayStore) -> Bool {
        active.source.target.role == .control
            ? store.isCoachMarkCurvePreviewOwner(id: active.source.target.markID,
                                                gestureID: active.gestureID)
            : store.isCoachMarkHandlePreviewOwner(id: active.source.target.markID,
                                                 gestureID: active.gestureID)
    }

    private func curve(for point: SIMD3<Float>, mark: CoachMark,
                       in store: ReplayStore) -> CoachMarkCurve {
        let pose = mark.sampled(at: store.playhead)
        let geometry = store.presentedCoachMarkGeometry(mark, at: store.playhead)
        let displayed = CoachMark(id: mark.id, kind: .arc,
                                  start: geometry.start, end: geometry.end,
                                  startElevation: pose.startElevation,
                                  endElevation: pose.endElevation,
                                  curve: pose.curve, label: mark.label,
                                  revealTime: mark.revealTime)
        return store.editableCoachMarkCurve(mark, at: store.playhead)
            .settingControlPoint(point, for: displayed)
    }

    private func displayedControlPoint(for mark: CoachMark,
                                       in store: ReplayStore) -> SIMD3<Float> {
        let pose = mark.sampled(at: store.playhead)
        let geometry = store.presentedCoachMarkGeometry(mark, at: store.playhead)
        let displayed = CoachMark(id: mark.id, kind: .arc,
                                  start: geometry.start, end: geometry.end,
                                  startElevation: pose.startElevation,
                                  endElevation: pose.endElevation,
                                  curve: pose.curve, label: mark.label,
                                  revealTime: mark.revealTime)
        return displayed.resolvedCurve.controlPoint(for: displayed)
    }

    private static func finite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private func retire(_ gestureID: UUID) {
        guard let active, active.gestureID == gestureID else { return }
        latestRetiredTime = max(latestRetiredTime ?? active.latestTime, active.latestTime)
        self.active = nil
        finishedGestures.append(gestureID)
        if finishedGestures.count > 128 { finishedGestures.removeFirst() }
    }
}
