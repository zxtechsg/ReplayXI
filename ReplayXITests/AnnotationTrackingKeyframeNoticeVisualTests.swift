import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTrackingKeyframeNoticeVisualTests: XCTestCase {
    func testNativeKeyframeNoticeIsCompact() throws {
        try capture(width: 1000, typeSize: .large, maximumHeight: 240, name: "tracking-keyframe-notice")
    }

    func testLargestTextKeyframeNoticeWrapsWithoutTruncating() throws {
        try capture(width: 900, typeSize: .accessibility5, maximumHeight: 700,
                    name: "tracking-keyframe-notice-largest-text")
    }

    private func capture(width: CGFloat, typeSize: DynamicTypeSize, maximumHeight: CGFloat, name: String) throws {
        let view = AnnotationTrackingKeyframeNotice(keyCount: 2, color: ReplayTheme.orange,
                                                   isEnabled: true, editKeys: {})
            .environment(\.colorScheme, .dark).dynamicTypeSize(typeSize)
            .padding(24).frame(width: width)
            .background(Color(red: 0.04, green: 0.06, blue: 0.08))
            .fixedSize(horizontal: false, vertical: true)
        let host = UIHostingController(rootView: view)
        let size = host.sizeThatFits(in: CGSize(width: width, height: 1200))
        XCTAssertGreaterThan(size.height, 80)
        XCTAssertLessThanOrEqual(size.height, maximumHeight)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: ceil(size.height)))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
