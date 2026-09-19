import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackBarSizeControlVisualTests: XCTestCase {
    func testSizeControlRendersAtRegularAndLargestText() throws {
        for (name, textSize, width) in [
            ("regular", DynamicTypeSize.large, CGFloat(1136)),
            ("large-text", .accessibility5, CGFloat(1316))
        ] {
            let view = PlaybackBarSizeControl(size: .constant(1.25))
                .environment(\.dynamicTypeSize, textSize).environment(\.colorScheme, .dark)
                .padding(24).frame(width: width)
                .background(Color(red: 0.04, green: 0.06, blue: 0.08))
            let host = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 240))
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
            }
            let data = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(data.count, 2048)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "bar-size-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
