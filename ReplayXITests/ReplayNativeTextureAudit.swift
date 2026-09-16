import CoreGraphics
import Foundation
import Metal
import RealityKit

/// Test-only readback of the texture actually attached to a native material.
/// Never used by playback; unsupported/compressed resources fail explicitly.
@MainActor
enum ReplayNativeTextureAudit {
    struct Snapshot: Encodable, Equatable {
        let width: Int
        let height: Int
        let pixelFormat: String
        let colourSpace: String
        let origin = "top-left"
        let rgba8: [UInt8]
    }

    enum AuditError: Error {
        case unsupportedResource, unsupportedFormat, noMetalDevice, allocationFailed
    }

    static func capture(_ resource: TextureResource) throws -> Snapshot {
        guard resource.textureType == .type2D, resource.arrayLength == 1,
              resource.semantic == .color,
              (1...256).contains(resource.width), (1...256).contains(resource.height),
              resource.width * resource.height <= 4096 else {
            throw AuditError.unsupportedResource
        }
        let format: String
        let isSRGB: Bool
        switch resource.pixelFormat {
        case .rgba8Unorm_srgb: (format, isSRGB) = ("rgba8Unorm_srgb", true)
        case .bgra8Unorm_srgb: (format, isSRGB) = ("bgra8Unorm_srgb", true)
        case .rgba8Unorm: (format, isSRGB) = ("rgba8Unorm", false)
        case .bgra8Unorm: (format, isSRGB) = ("bgra8Unorm", false)
        default: throw AuditError.unsupportedFormat
        }
        guard let device = MTLCreateSystemDefaultDevice() else { throw AuditError.noMetalDevice }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: resource.width,
            height: resource.height, mipmapped: resource.mipmapLevelCount > 1)
        descriptor.mipmapLevelCount = resource.mipmapLevelCount
        descriptor.storageMode = .shared
        // RealityKit's public copy API requires a shader-write destination.
        // A float destination avoids a second 8-bit quantisation of linear
        // values. Colour resources use Display P3 primaries on visionOS;
        // an _srgb pixel format describes the transfer curve, not the gamut.
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw AuditError.allocationFailed
        }
        try resource.copy(to: texture)
        var linear = [Float](repeating: 0, count: resource.width * resource.height * 4)
        linear.withUnsafeMutableBytes { buffer in
            texture.getBytes(buffer.baseAddress!, bytesPerRow: resource.width * 4 * MemoryLayout<Float>.stride,
                from: MTLRegionMake2D(0, 0, resource.width, resource.height), mipmapLevel: 0)
        }
        guard linear.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw AuditError.unsupportedResource
        }
        for offset in stride(from: 3, to: linear.count, by: 4) where linear[offset] != 1 {
            throw AuditError.unsupportedResource
        }
        let bytes: [UInt8] = linear.enumerated().map { offset, value in
            let encoded: Float
            if isSRGB && offset % 4 != 3 {
                encoded = value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
            } else {
                encoded = value
            }
            return UInt8((min(max(encoded, 0), 1) * 255).rounded())
        }
        return Snapshot(width: resource.width, height: resource.height,
            pixelFormat: format, colourSpace: isSRGB ? "Display P3" : "Linear DCI-P3 D65", rgba8: bytes)
    }

    static func linearSRGBTint(_ colour: CGColor) throws -> [Float] {
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let converted = colour.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count == 4 else {
            throw AuditError.unsupportedResource
        }
        let values = components.map(Float.init)
        // Native colour-space round trips can put white a few Float32 ULPs
        // beyond one. Canonicalise only that bounded conversion roundoff.
        let roundoff = 8 * Float.ulpOfOne
        guard values.allSatisfy({ $0.isFinite && $0 >= -roundoff && $0 <= 1 + roundoff }),
              abs(values[3] - 1) <= roundoff else {
            throw AuditError.unsupportedResource
        }
        return values.map { min(max($0, 0), 1) }
    }
}
