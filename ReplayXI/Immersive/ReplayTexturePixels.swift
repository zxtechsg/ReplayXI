import CoreGraphics
import Foundation
import ImageIO

/// Stable pixel identity across Xcode's lossless PNG packaging. Dimensions
/// and encoded bytes are checked before allocation; output is opaque sRGB RGBA8.
enum ReplayTexturePixels {
    enum Failure: Error { case invalidTexture }

    static func rgbaPNG(_ data: Data, size: Int, maximumEncodedBytes: Int) throws -> Data {
        guard (1...2_048).contains(size), (1...12 * 1_024 * 1_024).contains(maximumEncodedBytes),
              !data.isEmpty, data.count <= maximumEncodedBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png", CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              properties[kCGImagePropertyPixelWidth as String] as? Int == size,
              properties[kCGImagePropertyPixelHeight as String] as? Int == size,
              (properties[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == size, image.height == size, image.bitsPerComponent == 8,
              let colourSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { throw Failure.invalidTexture }
        var pixels = Data(count: size * size * 4)
        try pixels.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4, space: colourSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw Failure.invalidTexture }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        guard stride(from: 3, to: pixels.count, by: 4).allSatisfy({ pixels[$0] == 255 })
        else { throw Failure.invalidTexture }
        return pixels
    }
}
