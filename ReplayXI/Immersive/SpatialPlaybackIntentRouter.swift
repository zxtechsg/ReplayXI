import Foundation

/// Pure gesture-distance policy shared by the spatial interaction layer and
/// tests. The system tap recognizer can yield to `DragGesture` after only a few
/// millimetres of hand drift; a short spatial drag should therefore retain the
/// semantic tap the wearer intended, while a deliberate movement remains a
/// stroke or endpoint edit.
enum SpatialPlaybackIntentRouter {
    static let maximumRecoveredTapTravelMetres: Float = 0.45

    static func shouldRecoverTapIntent(
        from start: PitchPoint,
        to end: PitchPoint
    ) -> Bool {
        guard start.x.isFinite,
              start.z.isFinite,
              end.x.isFinite,
              end.z.isFinite else { return false }
        return ReplayGeometry.distance(start, end) <= maximumRecoveredTapTravelMetres
    }
}
