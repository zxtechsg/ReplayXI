import Foundation
import Observation

/// Native Slider callbacks have no gesture token. Only an explicit editing
/// start may acquire a Store transaction; binding writes never fall back to seek.
@MainActor @Observable
final class DashboardTimelineScrubController {
    static let step: TimeInterval = 0.1
    private(set) var isPresented = false
    private(set) var isEditing = false
    private(set) var storeScrubID: UUID?
    @ObservationIgnored private var stagedSample: (id: UUID, time: TimeInterval)?

    func appear() { isPresented = true }

    func ownsScrub(in store: ReplayStore) -> Bool {
        storeScrubID != nil && storeScrubID == store.activeTimelineScrubID && store.hasActiveTimelineScrub
    }

    func isEnabled(in store: ReplayStore) -> Bool {
        guard isPresented, !store.isDrawing, !store.hasActiveCoachMarkGeometryPreview else { return false }
        return !store.hasActiveTimelineScrub || ownsScrub(in: store)
    }

    @discardableResult
    func begin(in store: ReplayStore) -> Bool {
        guard isPresented else { return false }
        if isEditing, ownsScrub(in: store) { return true }
        // A disabled Slider may omit editing=false after losing ownership.
        // An explicit new start can recover once the Store is free. Native
        // Slider exposes no identity for distinguishing delayed start events.
        isEditing = true
        storeScrubID = nil
        let initialTime = stagedSample?.time
        stagedSample = nil
        guard store.canChangePlaybackView, !store.hasActiveTimelineScrub,
              store.beginTimelineScrub(), let id = store.activeTimelineScrubID else { return false }
        storeScrubID = id
        if let initialTime { _ = store.previewTimelineScrub(to: initialTime) }
        return true
    }

    @discardableResult
    func valueChanged(to time: TimeInterval, in store: ReplayStore) -> Bool {
        guard isPresented, time.isFinite else { return false }
        if isEditing {
            guard ownsScrub(in: store) else { return false }
            return store.previewTimelineScrub(to: time)
        }
        guard store.canChangePlaybackView else { return false }
        // A tap can deliver its first binding sample just before editing=true.
        // Stage it only within this actor turn. An idle/stale sample itself
        // cannot seek, and cannot be retained for a later physical gesture.
        let id = UUID()
        stagedSample = (id, time)
        Task { @MainActor [weak self] in
            guard self?.stagedSample?.id == id else { return }
            self?.stagedSample = nil
        }
        return false
    }

    @discardableResult
    func finish(in store: ReplayStore) -> Bool {
        let wasEditing = isEditing
        isEditing = false
        stagedSample = nil
        defer { storeScrubID = nil }
        guard isPresented, wasEditing, ownsScrub(in: store) else { return false }
        return store.commitTimelineScrub(to: store.playhead)
    }

    func disappear(in store: ReplayStore) {
        if ownsScrub(in: store) { store.cancelTimelineScrub() }
        isPresented = false
        isEditing = false
        storeScrubID = nil
        stagedSample = nil
    }

    /// VoiceOver has an explicit discrete route; it never relies on an idle
    /// binding setter that could instead be a delayed physical-drag callback.
    @discardableResult
    func adjustDiscrete(direction: Int, in store: ReplayStore) -> Bool {
        guard isPresented, store.canChangePlaybackView,
              store.playhead.isFinite, store.selectedScenario.duration.isFinite, direction != 0 else { return false }
        isEditing = false
        storeScrubID = nil
        stagedSample = nil
        let duration = max(store.selectedScenario.duration, 0)
        let delta = direction > 0 ? Self.step : -Self.step
        let time = min(max(store.playhead + delta, 0), duration)
        guard time != store.playhead else { return false }
        store.seek(to: time, broadcast: false)
        return true
    }
}
