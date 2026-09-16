import CoreGraphics
import Foundation
import ImageIO
import Metal
import RealityKit

/// Test-only offscreen pixels. A Metal _srgb format specifies the transfer
/// curve, not the gamut; calibration must identify the latter before PNG export.
@MainActor
enum ReplayRealityRendererAudit {
    enum Failure: Error {
        case unsupported(String)
    }

    struct Frame {
        let width: Int
        let height: Int
        let bgra: [UInt8]

        func rgba(x: Int, y: Int, topFirst: Bool) -> [UInt8] {
            let row = topFirst ? y : height - 1 - y
            let offset = (row * width + x) * 4
            return [bgra[offset + 2], bgra[offset + 1], bgra[offset], bgra[offset + 3]]
        }

        func topFirstRGBA(_ topFirst: Bool) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: bgra.count)
            for y in 0..<height {
                let rawRow = topFirst ? y : height - 1 - y
                for x in 0..<width {
                    let source = (rawRow * width + x) * 4
                    let destination = (y * width + x) * 4
                    result[destination] = bgra[source + 2]
                    result[destination + 1] = bgra[source + 1]
                    result[destination + 2] = bgra[source]
                    result[destination + 3] = bgra[source + 3]
                }
            }
            return result
        }
    }

    enum Gamut: String, CaseIterable, Encodable {
        case sRGB
        case displayP3 = "Display P3"

        var colourSpace: CGColorSpace? {
            CGColorSpace(name: self == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3)
        }
    }

    struct Calibration: Encodable {
        let gamut: Gamut
        let rawRowsAreTopFirst: Bool
        let maximumChannelError: Int
    }

    struct CalibrationProbe: Encodable {
        let pixelFormat = "bgra8Unorm_srgb"
        let rawTopFirstSamples: [[UInt8]]
        let rawBottomFirstSamples: [[UInt8]]
        let candidates: [Calibration]
    }

    static let swatches: [[UInt8]] = [
        [255, 0, 0], [0, 255, 0],
        [0, 0, 255], [0, 255, 255],
        [128, 128, 128], [51, 128, 204],
        [255, 255, 255], [255, 128, 0]
    ]

    static func swatchPosition(_ index: Int) -> SIMD3<Float> {
        [index % 2 == 0 ? -0.8 : 0.8, 1.2 - Float(index / 2) * 0.8, 0]
    }

    static func makeTexture(size: Int) throws -> any MTLTexture {
        guard (64...512).contains(size), let device = MTLCreateSystemDefaultDevice() else {
            throw Failure.unsupported("No Metal device or invalid audit dimensions")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: size, height: size, mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Failure.unsupported("Offscreen target allocation failed")
        }
        return texture
    }

    static func read(_ texture: any MTLTexture) throws -> Frame {
        guard texture.pixelFormat == .bgra8Unorm_srgb,
              texture.storageMode == .shared,
              (64...512).contains(texture.width), (64...512).contains(texture.height) else {
            throw Failure.unsupported("Unrecognised offscreen target")
        }
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            texture.getBytes(buffer.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return Frame(width: texture.width, height: texture.height, bgra: bytes)
    }

    static func probe(_ frame: Frame) throws -> CalibrationProbe {
        guard let sourceSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw Failure.unsupported("sRGB source colour space unavailable")
        }
        func samples(topFirst: Bool) -> [[UInt8]] {
            swatches.indices.map { index in
                let position = swatchPosition(index)
                // 90-degree vertical FOV, square output, camera two metres
                // from z=0: the full image spans four metres in X and Y.
                let x = Int((0.5 + position.x / 4) * Float(frame.width))
                let y = Int((0.5 - position.y / 4) * Float(frame.height))
                return frame.rgba(x: x, y: y, topFirst: topFirst)
            }
        }
        let top = samples(topFirst: true)
        let bottom = samples(topFirst: false)
        var candidates: [Calibration] = []
        for gamut in Gamut.allCases {
            guard let destinationSpace = gamut.colourSpace else {
                throw Failure.unsupported("Candidate colour space unavailable")
            }
            var expected: [[UInt8]] = []
            for swatch in swatches {
                let components = swatch.map { CGFloat($0) / 255 } + [1]
                guard let source = CGColor(colorSpace: sourceSpace, components: components),
                      let converted = source.converted(to: destinationSpace, intent: .defaultIntent, options: nil),
                      let channels = converted.components, channels.count == 4,
                      channels.allSatisfy({ $0.isFinite }) else {
                    throw Failure.unsupported("Calibration colour conversion failed")
                }
                expected.append(channels.map { UInt8((min(max($0, 0), 1) * 255).rounded()) })
            }
            for topFirst in [true, false] {
                let observed = topFirst ? top : bottom
                var maximumError = 0
                for index in swatches.indices {
                    for channel in 0..<4 {
                        maximumError = max(maximumError, abs(Int(observed[index][channel]) - Int(expected[index][channel])))
                    }
                }
                candidates.append(Calibration(gamut: gamut, rawRowsAreTopFirst: topFirst,
                    maximumChannelError: maximumError))
            }
        }
        return CalibrationProbe(rawTopFirstSamples: top, rawBottomFirstSamples: bottom, candidates: candidates)
    }

    static func png(_ frame: Frame, calibration: Calibration) throws -> Data {
        guard calibration.maximumChannelError <= 4, let space = calibration.gamut.colourSpace else {
            throw Failure.unsupported("PNG export requires verified row/channel/gamut calibration")
        }
        let rgba = frame.topFirstRGBA(calibration.rawRowsAreTopFirst)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: frame.width, height: frame.height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.width * 4,
                space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw Failure.unsupported("Calibrated image creation failed")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
            throw Failure.unsupported("PNG encoder unavailable")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), data.length <= 2 * 1024 * 1024 else {
            throw Failure.unsupported("PNG encoding failed or exceeded its audit bound")
        }
        return data as Data
    }
}
