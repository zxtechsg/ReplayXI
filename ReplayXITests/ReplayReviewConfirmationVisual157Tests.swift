import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

/// The actual library's fixed sheet and scrolling confirmation, captured at
/// the target and at the action row. No immersive glass or mocked controls.
@MainActor
final class ReplayReviewConfirmationVisual157Tests: XCTestCase {
    func testLongNamedDeleteAndLoadTargetsAndButtonsAtDefaultAndLargestText() throws {
        for largest in [false, true] {
            for deletes in [false, true] { try capture(largest: largest, deletes: deletes) }
        }
    }

    private func capture(largest: Bool, deletes: Bool) throws {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first)
        let store = ReplayStore(scenarios: FootballReferenceScenarios.all)
        store.prepareForLocalExperience()
        store.selectScenario(id: scenario.id)
        store.seek(to: 5.125, broadcast: false)
        let name = String(repeating: "Long review ", count: 4) + "final moment"
        XCTAssertEqual(name.count, ReplayReviewLibrary.maximumNameLength)
        XCTAssertTrue(store.saveReview(named: name))
        let review = try XCTUnwrap(store.savedReviews.first)
        let before = store.makeSnapshot(), reviews = store.savedReviews
        let request: ReplayReviewConfirmationRequest = deletes ? .delete(review.id) : .restore(review)
        let layout = ReplayReviewLibraryLayout.resolve(usesAccessibilityText: largest)
        let library = ReplayReviewLibraryView.showingConfirmationForTesting(request)
            .environment(store).environment(\.colorScheme, .dark)
            .dynamicTypeSize(largest ? .accessibility5 : .large)
        let fittingHost = UIHostingController(rootView: library)
        let fitting = fittingHost.sizeThatFits(in: CGSize(width: layout.sheetWidth - 32, height: 2000))
        XCTAssertLessThanOrEqual(fitting.height + 32, layout.sheetHeight,
                                "Long target content must scroll, not expand the sheet")
        let view = library.padding(16)
            .frame(width: layout.sheetWidth, height: layout.sheetHeight, alignment: .topLeading)
            .background(ReplayTheme.navy)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: layout.sheetWidth, height: layout.sheetHeight))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        let scroll = try XCTUnwrap(verticalScroll(in: host.view))
        XCTAssertEqual(scroll.bounds.height, layout.contentHeight, accuracy: 1)
        XCTAssertGreaterThan(scroll.contentSize.height, 0)
        let namePrefix = "ReviewTarget157-\(deletes ? "delete" : "load")-\(largest ? "AX5" : "default")"
        try attach(host: host, name: namePrefix + "-target")
        let bottom = max(-scroll.adjustedContentInset.top,
                         scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(scroll.contentOffset.y, bottom, accuracy: 1)
        XCTAssertGreaterThanOrEqual(scroll.contentOffset.y + scroll.bounds.height,
                                    scroll.contentSize.height - 1, "Both 60pt actions must remain reachable by scrolling")
        try attach(host: host, name: namePrefix + "-actions")
        XCTAssertEqual(store.makeSnapshot(), before)
        XCTAssertEqual(store.savedReviews, reviews)
    }

    private func verticalScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.bounds.height > 100 { return scroll }
        return view.subviews.lazy.compactMap { self.verticalScroll(in: $0) }.first
    }

    private func attach<Content: View>(host: UIHostingController<Content>, name: String) throws {
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(try brightPixels(image), 1_000, "A blank image cannot establish readable target identity")
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways
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
