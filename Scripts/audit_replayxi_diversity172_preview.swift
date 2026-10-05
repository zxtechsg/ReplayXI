import CoreGraphics
import Foundation
import ImageIO

// Compare matched 800x800 preview renders under identical camera and light.
@main
enum AuditReplayXIDiversity172Preview {
    struct Rect { let name: String; let x: Int; let y: Int; let width: Int; let height: Int }

    static func pixels(_ path: String) throws -> [UInt8] {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == 800, image.height == 800,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw NSError(domain: "preview", code: 1)
        }
        var data = [UInt8](repeating: 0, count: 800 * 800 * 4)
        let valid = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 800, height: 800,
                bitsPerComponent: 8, bytesPerRow: 800 * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                    CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 800, height: 800))
            return true
        }
        if !valid { throw NSError(domain: "preview", code: 2) }
        return data
    }

    static func main() throws {
        guard CommandLine.arguments.count >= 3 else {
            throw NSError(domain: "usage: audit ORIGINAL KIT...", code: 3)
        }
        let source = try pixels(CommandLine.arguments[1])
        let regions = [Rect(name: "face", x: 375, y: 108, width: 50, height: 62),
                       Rect(name: "hair", x: 381, y: 78, width: 42, height: 28),
                       Rect(name: "leftForearm", x: 90, y: 197, width: 150, height: 28),
                       Rect(name: "rightForearm", x: 560, y: 197, width: 150, height: 28),
                       Rect(name: "leftKnee", x: 316, y: 493, width: 38, height: 43),
                       Rect(name: "rightKnee", x: 447, y: 493, width: 38, height: 43)]
        for path in CommandLine.arguments.dropFirst(2) {
            let target = try pixels(path)
            var result: [String: Double] = [:]
            for rect in regions {
                var delta = 0
                var count = 0
                for displayedY in rect.y..<(rect.y + rect.height) {
                    let row = 799 - displayedY
                    for x in rect.x..<(rect.x + rect.width) {
                        let offset = (row * 800 + x) * 4
                        for channel in 0..<3 {
                            delta += abs(Int(source[offset + channel]) - Int(target[offset + channel]))
                            count += 1
                        }
                    }
                }
                result[rect.name] = Double(delta) / Double(count)
            }
            let row: [String: Any] = ["file": path, "meanAbsoluteRGBError8Bit": result]
            print(String(decoding: try JSONSerialization.data(withJSONObject: row,
                options: [.sortedKeys]), as: UTF8.self))
        }
    }
}
