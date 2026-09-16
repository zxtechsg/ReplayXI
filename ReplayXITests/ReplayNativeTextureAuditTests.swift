import CoreGraphics
import RealityKit
import UIKit
import XCTest

@MainActor
final class ReplayNativeTextureAuditTests: XCTestCase {
    func testReadbackPreservesDistinctRowsAndColourChannels() throws {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                             0, 0, 255, 255, 31, 79, 151, 255]
        let texture = try makeTexture(width: 2, height: 2, bytes: bytes)
        let actual = try ReplayNativeTextureAudit.capture(texture)
        XCTAssertEqual(actual.width, 2)
        XCTAssertEqual(actual.height, 2)
        XCTAssertEqual(actual.origin, "top-left")
        XCTAssertEqual(actual.colourSpace, "Display P3")
        XCTAssertEqual(actual.rgba8, bytes)
    }

    func testSRGBImportIsReportedAsConvertedNativeP3InsteadOfMislabeledSourceBytes() throws {
        let input: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                             0, 0, 255, 255, 31, 79, 151, 255]
        let texture = try makeTexture(width: 2, height: 2, bytes: input,
                                      colourSpaceName: CGColorSpace.sRGB)
        let actual = try ReplayNativeTextureAudit.capture(texture)
        XCTAssertEqual(actual.colourSpace, "Display P3")
        XCTAssertNotEqual(actual.rgba8, input)
        let source = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let destination = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        for offset in stride(from: 0, to: input.count, by: 4) {
            let components = input[offset..<(offset + 4)].map { CGFloat($0) / 255 }
            let colour = try XCTUnwrap(CGColor(colorSpace: source, components: components))
            let converted = try XCTUnwrap(colour.converted(to: destination, intent: .defaultIntent, options: nil))
            let expected = try XCTUnwrap(converted.components)
            for channel in 0..<4 {
                // The loaded texture quantises a colour-managed value to 8 bits.
                // Core Graphics is an independent reference, within one code value.
                XCTAssertEqual(Double(actual.rgba8[offset + channel]),
                               Double(expected[channel] * 255), accuracy: 1)
            }
        }
    }

    func testMipmappedOneColumnStripKeepsAllBasePixels() throws {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64 * 4)
        for row in 0..<64 {
            let red = UInt8(row * 4)
            let green = UInt8(255 - row * 4)
            bytes.append(contentsOf: [red, green, 37, 255])
        }
        let texture = try makeTexture(width: 1, height: 64, bytes: bytes)
        XCTAssertEqual(texture.mipmapLevelCount, 7)
        let actual = try ReplayNativeTextureAudit.capture(texture)
        XCTAssertEqual(actual.width, 1)
        XCTAssertEqual(actual.height, 64)
        XCTAssertEqual(actual.rgba8, bytes)
    }

    func testReadbackRejectsOversizedTexturesBeforeCopy() throws {
        let texture = try makeTexture(width: 257, height: 1,
            bytes: [UInt8](repeating: 255, count: 257 * 4))
        XCTAssertThrowsError(try ReplayNativeTextureAudit.capture(texture)) { error in
            guard case ReplayNativeTextureAudit.AuditError.unsupportedResource = error else {
                return XCTFail("Expected bounded resource rejection, got \(error)")
            }
        }
    }

    func testReadbackDoesNotGuessColourSpaceForRawResources() throws {
        let texture = try makeTexture(width: 1, height: 1, bytes: [10, 20, 30, 255], semantic: .raw)
        XCTAssertThrowsError(try ReplayNativeTextureAudit.capture(texture)) { error in
            guard case ReplayNativeTextureAudit.AuditError.unsupportedResource = error else {
                return XCTFail("Expected explicit semantic rejection, got \(error)")
            }
        }
    }

    func testReadbackRejectsTransparencyInsteadOfRenderingItAsOpaque() throws {
        let texture = try makeTexture(width: 1, height: 1, bytes: [32, 16, 0, 128])
        XCTAssertThrowsError(try ReplayNativeTextureAudit.capture(texture)) { error in
            guard case ReplayNativeTextureAudit.AuditError.unsupportedResource = error else {
                return XCTFail("Expected explicit opacity rejection, got \(error)")
            }
        }
    }

    func testNativeMaterialTintIsExplicitlyConvertedToLinearSRGB() throws {
        let material = SimpleMaterial(color: UIColor(red: 0.5, green: 0.25, blue: 0, alpha: 1),
                                      roughness: 0.8, isMetallic: false)
        let tint = try ReplayNativeTextureAudit.linearSRGBTint(material.color.tint.cgColor)
        for (actual, expected) in zip(tint, [Float(0.21404114), 0.05087609, 0, 1]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000001)
        }
        let white = SimpleMaterial(color: .white, roughness: 0.8, isMetallic: false)
        let canonical = try ReplayNativeTextureAudit.linearSRGBTint(white.color.tint.cgColor)
        XCTAssertTrue(canonical.allSatisfy { (0...1).contains($0) })
        for value in canonical { XCTAssertEqual(value, 1, accuracy: 0.000001) }
    }

    func testTintConversionRejectsHDRAndTransparencyRatherThanClampingThem() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        for components: [CGFloat] in [[1.01, 0, 0, 1], [-0.01, 0, 0, 1], [0.2, 0.3, 0.4, 0.5]] {
            let colour = try XCTUnwrap(CGColor(colorSpace: space, components: components))
            XCTAssertThrowsError(try ReplayNativeTextureAudit.linearSRGBTint(colour))
        }
    }

    private func makeTexture(width: Int, height: Int, bytes: [UInt8],
                             semantic: TextureResource.Semantic = .color,
                             colourSpaceName: CFString = CGColorSpace.displayP3) throws -> TextureResource {
        XCTAssertEqual(bytes.count, width * height * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let colourSpace = try XCTUnwrap(CGColorSpace(name: colourSpaceName))
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)
        let image = try XCTUnwrap(CGImage(width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: colourSpace, bitmapInfo: bitmapInfo, provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        return try TextureResource(image: image, options: .init(
            semantic: semantic, compression: .none, mipmapsMode: .allocateAndGenerateAll))
    }
}
