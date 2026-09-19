import Foundation

/// Local rendering preference, deliberately separate from saved match reviews.
/// Both choices use the same tracks, touches and close-player animation.
enum ReplayPlayerDetail: String, CaseIterable, Sendable {
    case balanced
    case fullSquad

    static let storageKey = "ReplayXI.PlayerDetail"
    static let defaultSelection: Self = .balanced

    static func resolved(_ rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? defaultSelection
    }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .fullSquad: "Full squad"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .balanced: "Lighter player detail. Pauses playback without changing the match."
        case .fullSquad: "Detailed bodies for both teams. Uses more processing power and pauses playback."
        }
    }

    var maximumSkinnedPlayers: Int { self == .fullSquad ? 22 : 4 }
    var allowsFirstPersonLowSkins: Bool { self == .fullSquad }

    func canSelect(from current: Self, canChangePlaybackView: Bool) -> Bool {
        self != current && canChangePlaybackView
    }
}
