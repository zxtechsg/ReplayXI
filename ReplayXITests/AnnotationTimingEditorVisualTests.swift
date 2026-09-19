import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTimingEditorVisualTests: XCTestCase {
    func testNativeTimingEditorRenders() throws {
        try renderEditor(width: 1136, height: 700, typeSize: .large, name: "annotation-timestamp-editor")
    }

    func testLargestTextTimingEditorUsesBoundedScrollablePanel() throws {
        // The image covers the panel's top state, not controls below the scroll fold.
        try renderEditor(width: 900, height: 1100, typeSize: .accessibility5,
                         name: "annotation-timestamp-editor-largest-text-top")
    }

    private func renderEditor(width: CGFloat, height: CGFloat, typeSize: DynamicTypeSize, name: String) throws {
        let store = ReplayStore()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        let view = AnnotationTimingEditor(markID: mark.id, color: ReplayTheme.cyan)
            .environment(store).environment(\.colorScheme, .dark)
            .dynamicTypeSize(typeSize)
            .padding(24).frame(width: width)
            .background(Color(red: 0.04, green: 0.06, blue: 0.08))
            .frame(maxHeight: .infinity, alignment: .top)
        // ImageRenderer cannot render platform-backed sliders/text fields.
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Geometry observation updates the viewport after its first intrinsic
        // layout. Drain one turn before capturing the settled, compact panel.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        XCTAssertEqual(image.size.width, width, accuracy: 1)
        let data = try XCTUnwrap(image.pngData())
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
