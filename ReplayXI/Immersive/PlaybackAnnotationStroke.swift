import Foundation

/// Pure state for the native gaze/pinch-drag annotation shortcut.
///
/// SwiftUI owns gesture recognition and RealityKit owns coordinate conversion;
/// this value owns only pitch-space validation, clamping, the useful-distance
/// gate, and the exactly-once release decision. The existing two-tap workflow
/// remains available when a drag ends inside the gate.
struct PlaybackAnnotationStroke: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case active
        case finished
    }

    /// visionOS 26's documented entity-drag workaround: distances are in the
    /// supplied spatial coordinate system, and 0.001 local units avoids the
    /// unitless default threshold that can make a pitch drag unreachable.
    static let entityGestureMinimumDistance: CGFloat = 0.001
    static let minimumPathLength = CoachMarkGeometryPolicy.minimumDirectionalLength
    static let minimumZoneRadius = CoachMarkGeometryPolicy.minimumZoneRadius

    /// Flattens a native spatial gesture sample onto the authored pitch plane.
    /// Keeping this projection pure makes clamping and malformed-input behavior
    /// deterministic outside of RealityView gesture delivery.
    static func projectedPitchPoint(_ point: SIMD3<Float>) -> PitchPoint? {
        guard point.x.isFinite, point.z.isFinite else { return nil }
        return ReplayStore.clampedPitchPoint(
            PitchPoint(x: point.x, z: point.z)
        )
    }

    let kind: CoachMarkKind
    let start: PitchPoint
    private(set) var end: PitchPoint
    private(set) var phase: Phase = .active

    init?(kind: CoachMarkKind, start: PitchPoint) {
        guard kind.requiresTwoPitchPoints,
              start.x.isFinite,
              start.z.isFinite else { return nil }
        let clampedStart = ReplayStore.clampedPitchPoint(start)
        self.kind = kind
        self.start = clampedStart
        end = clampedStart
    }

    var distance: Float {
        ReplayGeometry.distance(start, end)
    }

    var isReadyToCommit: Bool {
        guard phase == .active else { return false }
        return distance >= minimumDistance
    }

    var previewEnd: PitchPoint? {
        guard phase == .active, distance > 0.05 else { return nil }
        return end
    }

    @discardableResult
    mutating func update(to point: PitchPoint) -> Bool {
        guard phase == .active,
              point.x.isFinite,
              point.z.isFinite else { return false }
        end = ReplayStore.clampedPitchPoint(point)
        return true
    }

    /// Returns a commit endpoint at most once. A short release intentionally
    /// returns nil so the already placed start can continue as a two-tap draft.
    mutating func finish(at point: PitchPoint) -> PitchPoint? {
        guard phase == .active else { return nil }
        guard update(to: point) else {
            phase = .finished
            return nil
        }
        let endpoint = isReadyToCommit ? end : nil
        phase = .finished
        return endpoint
    }

    mutating func cancel() {
        phase = .finished
    }

    private var minimumDistance: Float {
        kind == .space ? Self.minimumZoneRadius : Self.minimumPathLength
    }
}
