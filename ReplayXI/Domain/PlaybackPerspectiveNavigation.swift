import Foundation

/// Resolves roster navigation without mutating the current camera first.
///
/// Callers must hand the returned ID to `openLocalPlayerPOV(_:)` as a single
/// transition. Mutating `localPerspectiveID` before that call can make an
/// adjacent selection look idempotent and bypass collaboration comfort state.
enum PlaybackPerspectiveNavigation {
    static func adjacentPlayerID(
        in players: [PlayerTrack],
        activeID: String,
        localFallbackID: String,
        offset: Int
    ) -> String? {
        guard !players.isEmpty else { return nil }
        let currentIndex = players.firstIndex { $0.id == activeID }
            ?? players.firstIndex { $0.id == localFallbackID }
            ?? players.startIndex
        let count = players.count
        let wrappedIndex = (currentIndex + offset % count + count) % count
        return players[wrappedIndex].id
    }
}
