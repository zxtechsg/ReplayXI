import CryptoKit
import Foundation

// Build with ReplayTexturePixels.swift, then pass square PNG paths. This uses
// the same native decoder as the app, including colour space and channel order.
@main
enum ReplayTextureAudit {
    static func main() throws {
        for path in CommandLine.arguments.dropFirst() {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let rgba = try ReplayTexturePixels.rgbaPNG(data, size: 2_048, maximumEncodedBytes: 12 * 1_024 * 1_024)
            func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
            let row: [String: Any] = ["file": path, "bytes": data.count, "fileSHA256": hash(data),
                                      "opaqueSRGBRGBA8SHA256": hash(rgba), "dimensions": [2_048, 2_048]]
            print(String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), as: UTF8.self))
        }
    }
}
