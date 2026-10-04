import CryptoKit
import Foundation

@main
enum AuditPolish170Pixels {
    static func main() throws {
        for path in CommandLine.arguments.dropFirst() {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let pixels = try ReplayTexturePixels.rgbaPNG(bytes, size: 1_024,
                maximumEncodedBytes: 12 * 1_024 * 1_024)
            let hash = SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined()
            print("\(URL(fileURLWithPath: path).lastPathComponent) \(hash)")
        }
    }
}
