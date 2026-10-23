import Foundation
import simd

/// Wearer-local placement only. The stable room anchor and pitch never move.
/// Drag values are cumulative, so every preview starts from one checkpoint.
struct PlaybackWorkspaceMove: Equatable {
    private(set) var offset: SIMD3<Float> = .zero
    private(set) var owner: UUID?
    private var checkpoint: SIMD3<Float>?
    private var rejectsCurrentGesture = false

    var isActive: Bool { checkpoint != nil }

    mutating func prepare(at savedOffset: SIMD3<Float>) {
        guard !isActive, !rejectsCurrentGesture else { return }
        offset = Self.clamped(savedOffset)
    }

    @discardableResult
    mutating func preview(
        roomID: UUID,
        cumulativeTranslation: SIMD3<Float>,
        isAllowed: Bool
    ) -> Bool {
        guard owner == nil || owner == roomID else { return false }
        guard !rejectsCurrentGesture else { return false }
        guard isAllowed, Self.isFinite(cumulativeTranslation) else {
            cancel(rejectCurrentGesture: true)
            return false
        }
        if checkpoint == nil {
            checkpoint = offset
            owner = roomID
        }
        guard owner == roomID, let checkpoint else { return false }
        offset = Self.clamped(checkpoint + cumulativeTranslation)
        return true
    }

    @discardableResult
    mutating func commit(roomID: UUID) -> Bool {
        guard owner == roomID, checkpoint != nil else { return false }
        checkpoint = nil
        owner = nil
        rejectsCurrentGesture = false
        return true
    }

    mutating func cancel(rejectCurrentGesture: Bool = false) {
        if let checkpoint { offset = checkpoint }
        checkpoint = nil
        owner = nil
        rejectsCurrentGesture = rejectCurrentGesture
    }

    mutating func reset(to offset: SIMD3<Float> = .zero) {
        cancel()
        self.offset = Self.clamped(offset)
    }

    /// Bounds keep the workspace reachable, including the nearest preset.
    /// The 0.4 m forward allowance leaves its console at least 0.54 m ahead.
    static func clamped(_ offset: SIMD3<Float>) -> SIMD3<Float> {
        guard isFinite(offset) else { return .zero }
        return SIMD3(
            min(max(offset.x, -1.2), 1.2),
            min(max(offset.y, -0.75), 0.75),
            min(max(offset.z, -1), 0.4)
        )
    }

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
