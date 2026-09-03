import Foundation
import RealityKit
import Testing

private final class ImportedPlayerAssetBundleToken {}

@MainActor
struct ImportedPlayerAssetTests {
    @Test
    func styledFootballerLoadsWithOpaqueSkinnedKitAndSeekableSprint() throws {
        let fixtureBundle = Bundle(for: ImportedPlayerAssetBundleToken.self)
        let assetURL = try #require(
            fixtureBundle.url(
                forResource: "ReplayXIPlayerKit",
                withExtension: "usdz",
                subdirectory: "Fixtures/Generated"
            ) ?? fixtureBundle.url(forResource: "ReplayXIPlayerKit", withExtension: "usdz")
        )

        let player = try Entity.load(contentsOf: assetURL)
        for shellName in [
            "ReplayXI_Jersey",
            "ReplayXI_Shorts",
            "ReplayXI_Socks",
            "ReplayXI_Boots",
            "ReplayXI_Trim",
        ] {
            #expect(player.findEntity(named: shellName) != nil)
        }

        let sprint = try #require(player.availableAnimations.last)
        let controller = player.playAnimation(
            sprint.repeat(),
            transitionDuration: 0,
            startsPaused: true
        )
        controller.time = 0.42
        #expect(controller.isValid)
        #expect(controller.isPaused)
        #expect(controller.time > 0.4)
    }

    @Test
    func cc0SprintAssetLoadsWithAnimation() throws {
        let fixtureBundle = Bundle(for: ImportedPlayerAssetBundleToken.self)
        let assetURL = try #require(
            fixtureBundle.url(
                forResource: "ReplayXIPlayerSprint",
                withExtension: "usdz",
                subdirectory: "Fixtures/ThirdParty/Quaternius"
            ) ?? fixtureBundle.url(forResource: "ReplayXIPlayerSprint", withExtension: "usdz")
        )

        let player = try Entity.load(contentsOf: assetURL)

        let sprint = try #require(player.availableAnimations.last)
        print(
            "ReplayXIPlayerSprint animations: "
                + player.availableAnimations.map { $0.name ?? "<unnamed>" }.joined(separator: ", ")
        )
        #expect(player.availableAnimations.isEmpty == false)
        _ = player.playAnimation(sprint.repeat(), transitionDuration: 0, startsPaused: true)
        let bounds = player.visualBounds(relativeTo: nil).extents
        #expect(bounds.y > 1.5)
        #expect(bounds.y < 3.5)
    }
}
