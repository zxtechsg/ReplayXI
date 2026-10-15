import Foundation

/// Local rendering preference, deliberately separate from saved match reviews.
/// Both choices use the same tracks, touches and close-player animation.
enum ReplayPlayerDetail: String, CaseIterable, Sendable {
    case balanced
    case fullSquad

    // Start existing installations on consistent squad assets too. The old
    // preference implicitly defaulted to four skins; retain a new, explicit
    // lightweight choice without carrying that mixed-body default forward.
    static let storageKey = "ReplayXI.PlayerDetail.v2"
    static let defaultSelection: Self = .fullSquad
    static let maximumSquadSize = 22

    static func resolved(_ rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? defaultSelection
    }

    var title: String {
        switch self {
        case .balanced: "Lightweight"
        case .fullSquad: "Full squad"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .balanced: "Fewer detailed players. Uses less processing power and pauses playback."
        case .fullSquad: "Consistent detailed bodies for both teams, with simpler meshes at a distance. Pauses playback."
        }
    }

    var maximumSkinnedPlayers: Int { self == .fullSquad ? Self.maximumSquadSize : 4 }
    var allowsFirstPersonLowSkins: Bool { self == .fullSquad }
    var allowsShapeReplayLowSkins: Bool { self == .fullSquad }

    func canSelect(from current: Self, canChangePlaybackView: Bool) -> Bool {
        self != current && canChangePlaybackView
    }
}
