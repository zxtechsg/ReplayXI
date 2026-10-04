import Foundation

/// Fictional palettes, not race labels or real-player likenesses. A shared
/// geometry and scale remain identical for both teams. Atlases load once.
enum ReplayTripoAppearance {
    enum Palette: String, CaseIterable, Sendable { case base, light, warm, deep }
    struct Atlas: Sendable {
        let name: String
        let pixelSHA256: String
    }
    static let textureSize = 1_024
    static let additionalBaseRGBABytes = 9 * textureSize * textureSize * 4

    static func palette(for player: PlayerTrack) -> Palette {
        let remainder = (player.shirtNumber % 5 + (player.team == .away ? 2 : 0)) % 5
        let index = (remainder + 5) % 5
        return [.base, .light, .warm, .deep, .warm][index]
    }

    /// Home, away, keeper order, shared with the base kit contract.
    static func atlases(for palette: Palette) -> [Atlas] {
        switch palette {
        case .base: return []
        case .light: return [
            .init(name: "ReplayXITripoHomeLight", pixelSHA256: "979ab7fc4658b598dc2cab6fa336abcaf013200946e0e9d7262261f11170d3c7"),
            .init(name: "ReplayXITripoAwayLight", pixelSHA256: "fe1d5990a4028c02aec8d8d5c847436af49b734155993d6e63f9a135c76e0f4e"),
            .init(name: "ReplayXITripoKeeperLight", pixelSHA256: "2273d47a15dcbd0ca1b6a7550bbad50b8ea6271616ace41dbdfa3812fb8e9f05")]
        case .warm: return [
            .init(name: "ReplayXITripoHomeWarm", pixelSHA256: "34bcbad63361eb67335e051c22550030577fafd1b569c6bed0f385bd162f891d"),
            .init(name: "ReplayXITripoAwayWarm", pixelSHA256: "88ceb81d2a252dad10ea9381b0f2d5a2af76b05a344afc8b2282102aaa5d594d"),
            .init(name: "ReplayXITripoKeeperWarm", pixelSHA256: "bc728312390be19c71162e09e0a0f17957bd34206e38aa5c6d19d656bc880577")]
        case .deep: return [
            .init(name: "ReplayXITripoHomeDeep", pixelSHA256: "7f0f3c4f1f3072c8d142dfb03181a1ef8a0f6a66856816a206b1a31ca8cec1d8"),
            .init(name: "ReplayXITripoAwayDeep", pixelSHA256: "d6f1de7d6b29d91c9df42584bbee6df0fcc52c66099ae4afdc8ed9cb43bb0d6f"),
            .init(name: "ReplayXITripoKeeperDeep", pixelSHA256: "99c96e8308f88fe6e35d46f98a97e5aa854a3fd6acd901b7ec0edea52a1db262")]
        }
    }
}
