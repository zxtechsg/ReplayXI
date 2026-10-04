import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackViewShelfVisual170Tests: XCTestCase {
    func testRoomFixedHUDSectionsFitRegularAndLargestTextWithoutChangingReplay() throws {
        for largest in [false, true] {
            for section in PlaybackViewShelf.allCases {
                let store = ReplayStore(scenarios: FootballReferenceScenarios.all)
                store.seek(to: 4.5)
                let saved = store.makeSavedReviewState()
                var recentered = false
                let content = PlaybackViewOverlayHUD(showsPlaybackAnnotations: .constant(true),
                    emphasizesBall: .constant(true), recenterControls: { recentered = true },
                    initialSection: section, initiallyExpanded: true, usesSpatialGlass: false)
                    .environment(store)
                    .environment(\.colorScheme, .dark)
                    .dynamicTypeSize(largest ? .accessibility5 : .large)
                    .fixedSize(horizontal: false, vertical: true)
                try capture(content, width: largest ? 500 : 420,
                    label: "hud-\(section.rawValue)-\(largest ? "AX5" : "regular")")
                XCTAssertFalse(recentered)
                XCTAssertEqual(store.makeSavedReviewState(), saved)
            }
        }
    }

    func testSourcePanelFitsRegularAndLargestText() throws {
        let reference = try XCTUnwrap(ReplayReferenceLibrary.reference(for: "final-36-counter-v2"))
        for largest in [false, true] {
            try capture(ReplayVideoReferenceDetails(reference: reference, fixedWidth: nil)
                .environment(\.colorScheme, .dark)
                .dynamicTypeSize(largest ? .accessibility5 : .large)
                .fixedSize(horizontal: false, vertical: true),
                width: largest ? 500 : 420, label: "source-\(largest ? "AX5" : "regular")")
        }
    }

    func testThreeOverlayControlsFitPassingLanesWithoutChangingSavedReview() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .passingChannels))
        for largest in [false, true] {
            let store = ReplayStore(scenarios: [scenario])
            store.seek(to: 13.6)
            let saved = store.makeSavedReviewState()
            try capture(PlaybackViewOverlayHUD(showsPlaybackAnnotations: .constant(true),
                emphasizesBall: .constant(true), recenterControls: {},
                initialSection: .overlays, initiallyExpanded: true, usesSpatialGlass: false)
                .environment(store)
                .environment(\.colorScheme, .dark)
                .dynamicTypeSize(largest ? .accessibility5 : .large)
                .fixedSize(horizontal: false, vertical: true),
                width: largest ? 500 : 420,
                label: "hud-three-overlays-\(largest ? "AX5" : "regular")")
            XCTAssertEqual(store.makeSavedReviewState(), saved)
        }
    }

    private func capture<V: View>(_ content: V, width: CGFloat, label: String) throws {
        let fittingHost = UIHostingController(rootView: content)
        let fitting = fittingHost.sizeThatFits(in: CGSize(width: width, height: 2_000))
        XCTAssertTrue(fitting.width.isFinite && fitting.height.isFinite)
        XCTAssertLessThanOrEqual(fitting.width, width + 0.5, label)
        XCTAssertGreaterThan(fitting.height, 80, label)
        XCTAssertLessThan(fitting.height, 1_300, label)
        let canvas = CGSize(width: width + 32, height: ceil(fitting.height) + 32)
        let host = UIHostingController(rootView: content.frame(width: width, alignment: .topLeading)
            .padding(16).background(Color(red: 0.04, green: 0.06, blue: 0.08)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKey = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: canvas)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKey?.makeKey() }
        host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(try brightPixelCount(image), 500, "\(label): blank captures are not UI evidence")
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = "ReplayXI-UI170-\(label).png"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func brightPixelCount(_ image: UIImage) throws -> Int {
        let source = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: source.width,
                height: source.height, bitsPerComponent: 8, bytesPerRow: source.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        }
        var count = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            if max(bytes[index], max(bytes[index + 1], bytes[index + 2])) > 100 { count += 1 }
        }
        return count
    }
}
