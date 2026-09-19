import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

/// Native screenshots of the actual POV controls, isolated from spatial glass
/// which UIKit's snapshot renderer cannot capture. Not headset/gaze testing.
@MainActor
final class PlaybackPOVControlsVisual145Tests: XCTestCase {
    func testBothNumberTenPOVsRenderInCompactAndLargestTextRoster() throws {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-81-volley-v2" })
        for team in FootballTeam.allCases {
            let player = try XCTUnwrap(scenario.players.first { $0.team == team && $0.shirtNumber == 10 })
            for large in [false, true] {
                let store = ReplayStore(scenarios: [scenario])
                store.prepareForLocalExperience()
                store.seek(to: 3)
                store.openLocalPlayerPOV(player.id)
                let width = PlaybackControlDeckLayout.resolve(preset: .standard,
                    usesAccessibilityText: large).contentWidth
                let height: CGFloat = large ? 1050 : 600
                let view = playbackPOVControlsForTesting(width: width, showsRoster: large)
                    .environment(store).environment(\.colorScheme, .dark)
                    .dynamicTypeSize(large ? .accessibility5 : .large)
                    .frame(width: width, height: height, alignment: .top)
                    .background(Color(red: 0.04, green: 0.06, blue: 0.08))
                let host = UIHostingController(rootView: view)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
                window.rootViewController = host
                window.isHidden = false
                defer { window.isHidden = true; window.rootViewController = nil }
                host.view.frame = window.bounds
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.08))
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                XCTAssertGreaterThan(try brightPixels(image), 1_000,
                    "An empty native snapshot is not visual validation")
                let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
                attachment.name = "POV145-\(team.rawValue)-10-\(large ? "AX5-roster" : "compact")"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTAssertEqual(store.playhead, 3)
                XCTAssertEqual(store.activePerspectiveID, player.id)
                XCTAssertFalse(store.isPlaying)
                XCTAssertEqual(store.marks, scenario.coachMarks)
            }
        }
    }

    private func brightPixels(_ image: UIImage) throws -> Int {
        let source = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                width: source.width, height: source.height, bitsPerComponent: 8,
                bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        }
        return stride(from: 0, to: bytes.count, by: 4).reduce(0) {
            $0 + (max(bytes[$1], bytes[$1 + 1], bytes[$1 + 2]) > 120 ? 1 : 0)
        }
    }
}
