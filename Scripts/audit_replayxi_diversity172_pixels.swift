import CryptoKit
import Foundation

// Compile with ReplayTexturePixels.swift. The app uses this exact decoder.
@main
enum AuditReplayXIDiversity172Pixels {
    static func main() throws {
        for path in CommandLine.arguments.dropFirst() {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let rgba = try ReplayTexturePixels.rgbaPNG(bytes, size: 1_024,
                maximumEncodedBytes: 12 * 1_024 * 1_024)
            func sha(_ data: Data) -> String {
                SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
            let row: [String: Any] = ["file": path, "fileSHA256": sha(bytes),
                                      "opaqueSRGBRGBA8SHA256": sha(rgba),
                                      "dimensions": [1_024, 1_024]]
            let encoded = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            print(String(decoding: encoded, as: UTF8.self))
        }
    }
}
