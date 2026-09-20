import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

/// Native captures of the shipped shelf, not a drawing of the controls or a
/// claim of headset/gaze activation. No spatial glass is involved.
@MainActor
final class AnnotationActionsVisual156Tests: XCTestCase {
    func testAuthoredAndCoachActionsAtDefaultAndLargestText() throws {
        for authored in [false, true] {
            for largest in [false, true] {
                try capture(authored: authored, largest: largest, showsCopy: true)
            }
        }
    }

    func testPlayerLabelShelfKeepsEraseWithoutCopy() throws {
        try capture(authored: false, largest: false, showsCopy: false)
    }

    func testCopyFailureFeedbackFitsLargestText() throws {
        try capture(authored: false, largest: true, showsCopy: true,
                    feedback: "Choose a pose large enough to copy")
    }

    private func capture(authored: Bool, largest: Bool, showsCopy: Bool, feedback: String? = nil) throws {
        let width = PlaybackControlDeckLayout.resolve(preset: .standard,
            usesAccessibilityText: largest).contentWidth
        let view = AnnotationActionsShelf(color: ReplayTheme.cyan, isAuthored: authored,
            showsCopy: showsCopy, canCopy: showsCopy, canErase: !authored, canClose: true, feedback: feedback,
            close: {}, copy: {}, erase: {})
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(largest ? .accessibility5 : .large)
            .controlSize(.extraLarge)
            .padding(24).frame(width: width)
            .background(Color(red: 0.04, green: 0.06, blue: 0.08))
            .fixedSize(horizontal: false, vertical: true)
        let host = UIHostingController(rootView: view)
        let size = host.sizeThatFits(in: CGSize(width: width, height: 1200))
        XCTAssertEqual(size.width, width, accuracy: 0.5)
        XCTAssertGreaterThan(size.height, 140)
        XCTAssertLessThan(size.height, largest ? 650 : 380)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: ceil(size.height)))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(try brightPixels(image), 1_000, "A blank capture is not visual evidence")
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = "Actions156-\(authored ? "MATCH" : "Coach")-\(showsCopy ? "spatial" : "label")-\(largest ? "AX5" : "default")\(feedback == nil ? "" : "-failure")"
        attachment.lifetime = .keepAlways
        add(attachment)
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
