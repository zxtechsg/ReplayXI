import CoreGraphics
import Foundation
import Observation

/// One curve pad owns one Store token. Every drag sample is an absolute change
/// from its captured curve, never from the last preview rendered by SwiftUI.
@MainActor @Observable
final class AnnotationCurveAdjustmentController {
    struct Transaction: Equatable {
        let markID: UUID
        let gestureID: UUID
        let baseline: CoachMarkCurve
    }

    private(set) var transaction: Transaction?
    private(set) var sample = AnnotationJoystickMath.Sample.zero
    private(set) var lastAction: String?
    private var lastRequestedCurve: CoachMarkCurve?
    private var rejectsCurrentGesture = false
    var isActive: Bool { transaction != nil }
    static let step: Float = 0.25

    func isEnabled(in store: ReplayStore, markID: UUID) -> Bool {
        guard !store.hasActiveTimelineScrub, !store.isDrawing,
              store.marks.contains(where: { $0.id == markID && $0.kind == .arc }) else { return false }
        if let transaction {
            return transaction.markID == markID && store.isCoachMarkCurvePreviewOwner(
                id: markID, gestureID: transaction.gestureID)
        }
        return store.canChangePlaybackView
    }

    @discardableResult
    func preview(in store: ReplayStore, markID: UUID, translation: CGSize) -> Bool {
        guard !rejectsCurrentGesture else { return false }
        guard translation.width.isFinite, translation.height.isFinite,
              isEnabled(in: store, markID: markID),
              let mark = store.marks.first(where: { $0.id == markID }) else {
            cancel(in: store, rejectCurrentGesture: true)
            return false
        }
        sample = AnnotationJoystickMath.sample(for: translation)
        let baseline = transaction?.baseline ?? mark.resolvedCurve
        let curve = CoachMarkCurve(
            bend: baseline.bend + Float(sample.steps.x) * Self.step,
            lift: baseline.lift - Float(sample.steps.y) * Self.step
        ).clamped()
        if transaction == nil, curve == baseline { return true }
        if transaction != nil, curve == lastRequestedCurve { return true }
        let proposed = transaction ?? Transaction(markID: markID, gestureID: UUID(), baseline: baseline)
        guard store.previewCoachMarkCurve(id: markID, gestureID: proposed.gestureID, curve: curve) else {
            cancel(in: store, rejectCurrentGesture: true)
            return false
        }
        transaction = proposed
        lastRequestedCurve = curve
        lastAction = nil
        return true
    }

    @discardableResult
    func finish(in store: ReplayStore, markID: UUID, translation: CGSize) -> Bool {
        // An end callback may arrive after interruption or disappearance.
        // It can finish its live token, never acquire a new edit by itself.
        guard let activeTransaction = transaction, activeTransaction.markID == markID,
              store.isCoachMarkCurvePreviewOwner(id: markID, gestureID: activeTransaction.gestureID) else {
            cancel(in: store)
            return false
        }
        guard preview(in: store, markID: markID, translation: translation),
              let transaction, transaction.markID == markID,
              store.isCoachMarkCurvePreviewOwner(id: markID, gestureID: transaction.gestureID) else {
            cancel(in: store)
            return false
        }
        let committed = store.commitCoachMarkCurvePreview(id: markID, gestureID: transaction.gestureID)
        if !committed {
            _ = store.cancelCoachMarkCurvePreview(id: markID, gestureID: transaction.gestureID)
        }
        reset()
        lastAction = committed ? "Curve updated" : "Adjustment cancelled"
        return committed
    }

    func cancel(in store: ReplayStore, rejectCurrentGesture: Bool = false) {
        if let transaction {
            _ = store.cancelCoachMarkCurvePreview(id: transaction.markID, gestureID: transaction.gestureID)
            lastAction = "Adjustment cancelled"
        }
        reset()
        rejectsCurrentGesture = rejectCurrentGesture
    }

    func canNudge(in store: ReplayStore, markID: UUID, bend: Float, lift: Float) -> Bool {
        guard !isActive, store.canChangePlaybackView,
              let mark = store.marks.first(where: { $0.id == markID }), mark.kind == .arc else { return false }
        let curve = mark.resolvedCurve
        return CoachMarkCurve(bend: curve.bend + bend, lift: curve.lift + lift).clamped() != curve
    }

    @discardableResult
    func nudge(in store: ReplayStore, markID: UUID, bend: Float, lift: Float) -> Bool {
        guard canNudge(in: store, markID: markID, bend: bend, lift: lift),
              store.nudgeCoachMarkCurve(id: markID, bendDelta: bend, liftDelta: lift) else { return false }
        lastAction = "Curve updated"
        return true
    }

    private func reset() {
        transaction = nil
        lastRequestedCurve = nil
        rejectsCurrentGesture = false
        sample = .zero
    }
}
