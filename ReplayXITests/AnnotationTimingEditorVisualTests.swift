import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTimingEditorVisualTests: XCTestCase {
    func testNativeTimingEditorRenders() throws {
        let store = ReplayStore()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        let view = AnnotationTimingEditor(markID: mark.id, color: ReplayTheme.cyan)
            .environment(store).environment(\.colorScheme, .dark)
            .padding(24).frame(width: 1136)
            .background(Color(red: 0.04, green: 0.06, blue: 0.08))
        // ImageRenderer cannot render platform-backed sliders/text fields.
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1136, height: 520))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        XCTAssertEqual(image.size.width, 1136, accuracy: 1)
        let data = try XCTUnwrap(image.pngData())
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "annotation-timestamp-editor"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
