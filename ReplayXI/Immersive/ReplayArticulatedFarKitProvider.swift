import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import RealityKit
import UIKit

/// Six original 64 px maps, shared across every far athlete. Only explicit
/// room preparation decodes textures; posing and rig creation never load them.
@MainActor
enum ReplayArticulatedFarKitProvider {
    static let decodedTextureBytes = 6 * 64 * 64 * 4 // Base levels; mip/cache overhead is extra.
    struct Materials { let torso: PhysicallyBasedMaterial; let shorts: PhysicallyBasedMaterial }
    enum PreparationError: Error, Equatable { case missingResource, changedResource, invalidTexture, previousFailure, forcedFailure }
    // Xcode may recompress PNGs. Pin their canonical opaque sRGB RGBA pixels,
    // not a particular lossless container encoding. Source byte hashes remain
    // in PLAYER124_ASSET_MANIFEST.json for authoring provenance.
    private static let pixelHashes: [String: String] = [
        "ReplayXIFarHomeTorso": "336d665269a23450f332029953272b3388cbdd16eece89105587b788ffc6d246",
        "ReplayXIFarHomeShorts": "dc546e92eeb5997280af9f32d15c66fd1cb6183e8760c18033e86ab504b27945",
        "ReplayXIFarAwayTorso": "b988e65354b28673d4ed3ba7479f42a37556552ea24e245a146f89ccac912d34",
        "ReplayXIFarAwayShorts": "1c62f90ae3524ebca6f0e4de7eb4a9a4504b111a242bd728ceac36add5a6a5b6",
        "ReplayXIFarKeeperTorso": "f06be7728f8cfc1645071039b54c191e45575a16715c1801bd53057a68ae7fed",
        "ReplayXIFarKeeperShorts": "315f68b0724f05a64660518214ceb8e0a7f7b997d71127b6337302af9cb90be0"
    ]
    private static var palettes: [String: Materials] = [:]
    private static var attempted = false
    static var isPrewarmed: Bool { palettes.count == 3 }

    static func prewarm(in bundle: Bundle = .main) throws {
        try prepare { name in
            guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Resources/Players")
                ?? bundle.url(forResource: name, withExtension: "png") else { throw PreparationError.missingResource }
            return url
        }
    }

    private static func prepare(resolve: (String) throws -> URL) throws {
        guard !isPrewarmed else { return }
        guard !attempted else { throw PreparationError.previousFailure }
        attempted = true
        #if DEBUG
        preparationCount += 1
        if forcesFailure { throw PreparationError.forcedFailure }
        #endif
        var prepared: [String: Materials] = [:]
        for team in ["Home","Away","Keeper"] {
            var materials: [PhysicallyBasedMaterial] = []
            for part in ["Torso","Shorts"] {
                let name = "ReplayXIFar\(team)\(part)"
                let url = try resolve(name)
                let metadata = try url.resourceValues(forKeys: [.isRegularFileKey,.fileSizeKey])
                guard metadata.isRegularFile == true, let bytes = metadata.fileSize, (1...16_384).contains(bytes)
                else { throw PreparationError.changedResource }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                try validatePixels(data, named: name)
                let texture = try TextureResource.load(contentsOf: url)
                guard texture.width == 64, texture.height == 64 else { throw PreparationError.invalidTexture }
                #if DEBUG
                textureLoadCount += 1
                #endif
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: .white, texture: .init(texture))
                material.roughness = .init(floatLiteral: 0.84)
                material.metallic = .init(floatLiteral: 0)
                materials.append(material)
            }
            prepared[team] = Materials(torso: materials[0], shorts: materials[1])
        }
        palettes = prepared
    }

    static func validatePixels(_ data: Data, named name: String) throws {
        guard let expected = pixelHashes[name] else { throw PreparationError.changedResource }
        let pixels = try canonicalRGBA(data: data, expectedSize: 64, maximumEncodedBytes: 16_384)
        guard SHA256.hash(data: pixels).map({ String(format: "%02x", $0) }).joined() == expected
        else { throw PreparationError.changedResource }
    }

    /// Exact, bounded comparison basis shared with native asset tests. Decode
    /// metadata before allocating pixels; require one opaque 8-bit PNG and
    /// rasterise into declared sRGB/RGBA order without resizing/interpolation.
    static func canonicalRGBA(data: Data, expectedSize: Int, maximumEncodedBytes: Int) throws -> Data {
        guard (1...1_024).contains(expectedSize), (1...4_194_304).contains(maximumEncodedBytes),
              !data.isEmpty, data.count <= maximumEncodedBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png", CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width == expectedSize, height == expectedSize,
              (properties[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width, image.height == height, image.bitsPerComponent == 8,
              let colourSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { throw PreparationError.invalidTexture }
        var pixels = Data(count: width * height * 4)
        try pixels.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: colourSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw PreparationError.invalidTexture }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard stride(from: 3, to: pixels.count, by: 4).allSatisfy({ pixels[$0] == 255 })
        else { throw PreparationError.invalidTexture }
        return pixels
    }

    static func materials(for configuration: ReplayAthleteConfiguration) -> Materials? {
        guard isPrewarmed else { return nil }
        if configuration.goalkeeper {
            let keeper = ReplayAthleteKit.replayXI(team: .home, goalkeeper: true, appearanceIndex: 0)
            guard configuration.kit.shirt == keeper.shirt, configuration.kit.shorts == keeper.shorts,
                  configuration.kit.trim == keeper.trim else { return nil }
            return palettes["Keeper"]
        }
        let home = ReplayAthleteKit.replayXI(team: .home, goalkeeper: false, appearanceIndex: 0)
        let away = ReplayAthleteKit.replayXI(team: .away, goalkeeper: false, appearanceIndex: 0)
        // Unknown custom kits keep their own flat colours, never an arbitrary
        // team texture. Palette choice is independent of skin and shirt number.
        if configuration.kit.shirt == home.shirt, configuration.kit.shorts == home.shorts,
           configuration.kit.trim == home.trim { return palettes["Home"] }
        if configuration.kit.shirt == away.shirt, configuration.kit.shorts == away.shorts,
           configuration.kit.trim == away.trim { return palettes["Away"] }
        return nil
    }

    #if DEBUG
    private(set) static var preparationCount = 0
    private(set) static var textureLoadCount = 0
    private static var forcesFailure = false
    static var cachedTextureCount: Int { palettes.count * 2 }
    static func prewarmMissingForTesting() throws {
        try prepare { _ in throw PreparationError.missingResource }
    }
    static func resetForTesting(forceFailure: Bool = false) {
        palettes = [:]; attempted = false; forcesFailure = forceFailure
        preparationCount = 0; textureLoadCount = 0
    }
    #endif
}
