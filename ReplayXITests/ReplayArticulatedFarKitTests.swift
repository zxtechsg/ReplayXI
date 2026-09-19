import RealityKit
import CoreGraphics
import ImageIO
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayArticulatedFarKitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
    }
    override func tearDown() {
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        super.tearDown()
    }

    func testMissingAndForcedFailuresKeepFlatFallbackWithoutRetryOrPartialPalettes() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "red-rw"))
        let configuration = ReplayAthleteConfiguration(player: player)
        XCTAssertNil(ReplayArticulatedFarKitProvider.materials(for: configuration))
        XCTAssertEqual(ReplayArticulatedFarKitProvider.preparationCount, 0)
        for forced in [false,true] {
            ReplayArticulatedFarKitProvider.resetForTesting(forceFailure: forced)
            if forced { XCTAssertThrowsError(try ReplayArticulatedFarKitProvider.prewarm()) }
            else { XCTAssertThrowsError(try ReplayArticulatedFarKitProvider.prewarmMissingForTesting()) }
            XCTAssertThrowsError(try ReplayArticulatedFarKitProvider.prewarm())
            XCTAssertNil(ReplayArticulatedFarKitProvider.materials(for: configuration))
            XCTAssertFalse(ReplayArticulatedFarKitProvider.isPrewarmed)
            XCTAssertEqual(ReplayArticulatedFarKitProvider.cachedTextureCount, 0)
            XCTAssertEqual(ReplayArticulatedFarKitProvider.textureLoadCount, 0)
            XCTAssertEqual(ReplayArticulatedFarKitProvider.preparationCount, 1)
            let rig = try ReplayAthleteFactory.make(for: player,lod: .far)
            let torso = try XCTUnwrap(rig.root.findEntity(named: "torso") as? ModelEntity)
            XCTAssertTrue(torso.model?.materials.first is SimpleMaterial)
        }
    }

    func testSixShippingMapsAreSharedForEveryTeamAndNeverReloadDuringMakeOrPose() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        // Material getters may return new Swift wrappers for one shared
        // resource. Semantics150 verifies public equality and mutation aliasing.
        var uniqueTextures: [TextureResource] = []
        var retainedTextures: [TextureResource] = []
        for player in scenario.players {
            let palette = try XCTUnwrap(ReplayArticulatedFarKitProvider.materials(for: .init(player: player)))
            for material in [palette.torso,palette.shorts] {
                let texture = try XCTUnwrap(material.baseColor.texture).resource
                XCTAssertEqual(texture.width,64)
                XCTAssertEqual(texture.height,64)
                if !uniqueTextures.contains(texture) { uniqueTextures.append(texture) }
                retainedTextures.append(texture)
            }
            let rig = try ReplayAthleteFactory.make(for: player,lod: .far)
            XCTAssertEqual(rig.metrics.modelEntities,7)
            for name in ["torso","shorts"] {
                let model = try XCTUnwrap(rig.root.findEntity(named: name) as? ModelEntity)
                let material = try XCTUnwrap(model.model?.materials.first as? PhysicallyBasedMaterial)
                XCTAssertNotNil(material.baseColor.texture)
            }
            for time in [0.0,13.6,17.5,3.0] { ReplayAthleteMotion.update(rig,from: player,at: time) }
            try ReplayArticulatedFarKitProvider.prewarm()
        }
        XCTAssertEqual(uniqueTextures.count,6)
        XCTAssertEqual(retainedTextures.count,44)
        XCTAssertEqual(ReplayArticulatedFarKitProvider.cachedTextureCount,6)
        XCTAssertEqual(ReplayArticulatedFarKitProvider.textureLoadCount,6)
        XCTAssertEqual(ReplayArticulatedFarKitProvider.preparationCount,1)
        XCTAssertEqual(ReplayArticulatedFarKitProvider.decodedTextureBytes,98_304)
    }

    func testPreparedMapsDoNotRepaintLegacyOrNearMidGeometry() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "red-lw"))
        try ReplayArticulatedFarKitProvider.prewarm()
        let customKeeper = ReplayAthleteConfiguration(playerID: "custom-keeper", shirtNumber: 1,
            goalkeeper: true, kit: .replayXI(team: .home, goalkeeper: false, appearanceIndex: 0),
            appearance: .replayXI(index: 0))
        XCTAssertNil(ReplayArticulatedFarKitProvider.materials(for: customKeeper),
                     "A goalkeeper flag must not repaint a custom kit")
        for lod in ReplayAthleteLOD.allCases {
            // A cached kit must not be applied to incompatible old torso UVs.
            let rig = try ReplayAthleteFactory.make(for: player,lod: lod)
            let torso = try XCTUnwrap(rig.root.findEntity(named: "torso") as? ModelEntity)
            XCTAssertTrue(torso.model?.materials.first is SimpleMaterial)
        }
        try ReplayArticulatedFarProvider.prewarm()
        for lod in [ReplayAthleteLOD.near,.mid] {
            let rig = try ReplayAthleteFactory.make(for: player,lod: lod)
            let torso = try XCTUnwrap(rig.root.findEntity(named: "torso") as? ModelEntity)
            XCTAssertTrue(torso.model?.materials.first is SimpleMaterial)
        }
    }

    func testBuiltPNGAndDifferentLosslessEncodingRetainExactPinnedPixels() throws {
        let name = "ReplayXIFarHomeTorso"
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Resources/Players")
            ?? Bundle.main.url(forResource: name, withExtension: "png"))
        let packaged = try Data(contentsOf: url)
        XCTAssertNoThrow(try ReplayArticulatedFarKitProvider.validatePixels(packaged, named: name))
        let pixels = try ReplayArticulatedFarKitProvider.canonicalRGBA(data: packaged,
            expectedSize: 64, maximumEncodedBytes: 16_384)
        XCTAssertEqual(pixels.count, 64 * 64 * 4)
        let encodedAgain = try png(pixels: pixels, size: 64)
        XCTAssertNoThrow(try ReplayArticulatedFarKitProvider.validatePixels(encodedAgain, named: name))
        XCTAssertEqual(try ReplayArticulatedFarKitProvider.canonicalRGBA(data: encodedAgain,
            expectedSize: 64, maximumEncodedBytes: 16_384), pixels)
        var changed = pixels
        changed[0] ^= 1
        XCTAssertThrowsError(try ReplayArticulatedFarKitProvider.validatePixels(try png(pixels: changed,size: 64), named: name)) {
            XCTAssertEqual($0 as? ReplayArticulatedFarKitProvider.PreparationError, .changedResource)
        }
    }

    func testCanonicalDecodeRejectsWrongSizeTransparencyInvalidDataAndOversizedInput() throws {
        let opaque = Data(repeating: 255, count: 64 * 64 * 4)
        var transparent = opaque
        transparent[3] = 0
        for data in [Data(),Data(repeating: 0,count: 16_385),
                     try png(pixels: Data(repeating: 255,count: 63*63*4),size: 63),
                     try png(pixels: transparent,size: 64)] {
            XCTAssertThrowsError(try ReplayArticulatedFarKitProvider.canonicalRGBA(data: data,
                expectedSize: 64, maximumEncodedBytes: 16_384))
        }
        let valid = try png(pixels: opaque,size: 64)
        XCTAssertThrowsError(try ReplayArticulatedFarKitProvider.canonicalRGBA(data: valid,
            expectedSize: 0, maximumEncodedBytes: 16_384))
        XCTAssertThrowsError(try ReplayArticulatedFarKitProvider.canonicalRGBA(data: valid,
            expectedSize: 64, maximumEncodedBytes: 0))
        XCTAssertThrowsError(try ReplayArticulatedFarKitProvider.validatePixels(valid,named: "UnknownKit"))
    }

    private func png(pixels: Data, size: Int) throws -> Data {
        XCTAssertEqual(pixels.count,size*size*4)
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try XCTUnwrap(CGImage(width: size,height: size,bitsPerComponent: 8,bitsPerPixel: 32,
            bytesPerRow: size*4,space: space,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)),
            provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output,"public.png" as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
