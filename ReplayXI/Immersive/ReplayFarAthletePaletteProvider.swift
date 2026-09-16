import CoreGraphics
import Foundation
import Metal
import RealityKit
import UIKit
import simd

/// Original, tiny colour strips for the existing far-limb silhouettes.
/// Prepared during rig setup/prewarm, never by the playback pose loop.
@MainActor
enum ReplayFarAthletePaletteProvider {
    static let stripWidth = 1
    static let stripHeight = 64
    static let maximumPaletteCount = 32

    enum Limb: CaseIterable, Equatable, Sendable {
        case leg, arm

        var lowerY: Float { self == .leg ? -0.82 : -0.58 }
        var upperY: Float { 0.02 }
    }

    struct Materials {
        let leg: SimpleMaterial
        let arm: SimpleMaterial
    }

    private struct Colour: Hashable {
        let red: UInt8, green: UInt8, blue: UInt8

        init?(_ source: ReplayAthleteColor) {
            guard source.red.isFinite, source.green.isFinite, source.blue.isFinite,
                  source.alpha.isFinite, source.alpha == 1 else { return nil }
            func byte(_ value: Float) -> UInt8 {
                UInt8((min(max(value, 0), 1) * 255).rounded())
            }
            red = byte(source.red)
            green = byte(source.green)
            blue = byte(source.blue)
        }

        var rgba: [UInt8] { [red, green, blue, 255] }
    }

    private struct Palette: Hashable {
        let shirt: Colour, shorts: Colour, skin: Colour
        let socks: Colour, boots: Colour, glove: Colour
        let goalkeeper: Bool

        init?(_ configuration: ReplayAthleteConfiguration) {
            guard let shirt = Colour(configuration.kit.shirt),
                  let shorts = Colour(configuration.kit.shorts),
                  let skin = Colour(configuration.appearance.skin),
                  let socks = Colour(configuration.kit.socks),
                  let boots = Colour(configuration.kit.boots),
                  let glove = Colour(configuration.kit.trim) else { return nil }
            self.shirt = shirt
            self.shorts = shorts
            self.skin = skin
            self.socks = socks
            self.boots = boots
            self.glove = glove
            goalkeeper = configuration.goalkeeper
        }

        func colour(at y: Float, for limb: Limb) -> Colour {
            switch limb {
            case .leg:
                if y > -0.12 { return shorts }
                if y > -0.40 { return skin }
                if y > -0.75 { return socks }
                return boots
            case .arm:
                if goalkeeper { return y > -0.50 ? shirt : glove }
                return y > -0.15 ? shirt : skin
            }
        }
    }

    private enum Entry {
        case ready(Materials)
        case unavailable
    }

    private enum PreparationError: Error {
        case invalidImage
        case unsupportedTexture
        case forcedTestFailure
    }

    private static var entries: [Palette: Entry] = [:]

    #if DEBUG
    private(set) static var preparationAttemptCount = 0
    private(set) static var textureCreationCount = 0
    private static var forcesFailureForTesting = false

    static var cachedPaletteCount: Int { entries.count }
    static var preparedPaletteCount: Int {
        entries.values.reduce(0) { count, entry in
            if case .ready = entry { return count + 1 }
            return count
        }
    }
    static var cachedTextureCount: Int { preparedPaletteCount * 2 }

    static func resetForTesting(forceFailure: Bool = false) {
        entries.removeAll()
        preparationAttemptCount = 0
        textureCreationCount = 0
        forcesFailureForTesting = forceFailure
    }
    #endif

    static func prewarm(for players: [PlayerTrack]) {
        for player in players { _ = materials(for: ReplayAthleteConfiguration(player: player)) }
    }

    static func textureCoordinate(for position: SIMD3<Float>, limb: Limb) -> SIMD2<Float> {
        guard position.y.isFinite else { return [0.5, 0.5] }
        let fraction = min(max((limb.upperY - position.y) / (limb.upperY - limb.lowerY), 0), 1)
        // Generated mesh UVs address native image row 0 at the limb top.
        // Half-texel insets avoid wrapping/blending the two end colours.
        return [0.5, (0.5 + fraction * Float(stripHeight - 1)) / Float(stripHeight)]
    }

    static func materials(for configuration: ReplayAthleteConfiguration) -> Materials? {
        guard let palette = Palette(configuration) else { return nil }
        if let entry = entries[palette] {
            if case .ready(let materials) = entry { return materials }
            return nil
        }
        guard entries.count < maximumPaletteCount else { return nil }
        // Failures reserve a bounded slot too, so repeated setup cannot retry
        // the same broken resource or expose a half-prepared pair of strips.
        entries[palette] = .unavailable
        #if DEBUG
        preparationAttemptCount += 1
        #endif
        do {
            let leg = try makeTexture(palette: palette, limb: .leg)
            let arm = try makeTexture(palette: palette, limb: .arm)
            let materials = Materials(
                leg: makeMaterial(texture: leg, roughness: 0.88),
                arm: makeMaterial(texture: arm, roughness: 0.84)
            )
            entries[palette] = .ready(materials)
            return materials
        } catch {
            return nil
        }
    }

    private static func makeTexture(palette: Palette, limb: Limb) throws -> TextureResource {
        #if DEBUG
        if forcesFailureForTesting { throw PreparationError.forcedTestFailure }
        #endif
        var bytes: [UInt8] = []
        bytes.reserveCapacity(stripHeight * 4)
        for row in 0..<stripHeight {
            let fraction = Float(row) / Float(stripHeight - 1)
            let y = limb.upperY - fraction * (limb.upperY - limb.lowerY)
            bytes.append(contentsOf: palette.colour(at: y, for: limb).rgba)
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: stripWidth, height: stripHeight,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                  space: space,
                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                                    CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else { throw PreparationError.invalidImage }
        let texture = try TextureResource(
            image: image,
            options: .init(semantic: .color, compression: .none, mipmapsMode: .allocateAndGenerateAll)
        )
        #if DEBUG
        textureCreationCount += 1
        #endif
        guard texture.width == stripWidth, texture.height == stripHeight,
              [MTLPixelFormat.rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb]
                .contains(texture.pixelFormat) else { throw PreparationError.unsupportedTexture }
        return texture
    }

    private static func makeMaterial(texture: TextureResource, roughness: Float) -> SimpleMaterial {
        let descriptor = MTLSamplerDescriptor()
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.normalizedCoordinates = true
        let sampler = MaterialParameters.Texture.Sampler(descriptor)
        var material = SimpleMaterial(color: .white, roughness: .float(roughness), isMetallic: false)
        material.color = .init(tint: .white, texture: .init(texture, sampler: sampler))
        return material
    }
}
