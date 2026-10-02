import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTimingEditorVisualTests: XCTestCase {
    func testNativeTimingEditorRenders() throws {
        try renderEditor(width: 1136, height: 700, typeSize: .large, name: "annotation-timestamp-editor-close-header")
    }

    func testLargestTextTimingEditorUsesBoundedScrollablePanel() throws {
        // The image covers the panel's top state, not controls below the scroll fold.
        try renderEditor(width: 900, height: 1100, typeSize: .accessibility5,
                         name: "annotation-timestamp-editor-largest-text-close-header")
    }

    func testCloseHeaderRemainsAvailableWithBothTimingDraftsPending() throws {
        try renderEditor(width: 1136, height: 900, typeSize: .large,
                         name: "annotation-timestamp-editor-pending-drafts-close-header", pendingDrafts: true)
    }

    func testOutsideWindowEditorExplainsSelectionPreview() throws {
        try renderEditor(width: 1136, height: 700, typeSize: .large,
                         name: "annotation-timestamp-editor-outside-window", previewTime: 11)
    }

    func testClosePositionTimesRemainReadable() throws {
        try renderEditor(width: 1136, height: 700, typeSize: .large,
                         name: "annotation-timestamp-editor-close-keys", extraKeyTimes: [2.01, 2.04],
                         selectedKeyTime: 2, revealSelectedKey: true)
    }

    func testSelectedKeyNudgesFitLargestTextAndExplainCollision() throws {
        try renderEditor(width: 900, height: 1500, typeSize: .accessibility5,
                         name: "annotation-position-nudges-largest-text", extraKeyTimes: [3],
                         selectedKeyTime: 2, positionText: "3", revealSelectedKey: true)
    }

    func testSelectedKeyNudgesFitRegularTextWithPendingDraft() throws {
        try renderEditor(width: 1136, height: 900, typeSize: .large,
                         name: "annotation-position-nudges-pending", selectedKeyTime: 2, positionText: "2.1")
    }

    private func renderEditor(width: CGFloat, height: CGFloat, typeSize: DynamicTypeSize, name: String,
                              previewTime: TimeInterval? = nil, extraKeyTimes: [TimeInterval] = [],
                              pendingDrafts: Bool = false, selectedKeyTime: TimeInterval? = nil,
                              positionText: String? = nil, revealSelectedKey: Bool = false) throws {
        let store = ReplayStore()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        for time in extraKeyTimes {
            store.seek(to: time)
            XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        }
        if let previewTime {
            store.seek(to: previewTime)
            XCTAssertFalse(mark.isVisible(at: store.playhead))
        }
        let session = AnnotationTimingDraftSession()
        if pendingDrafts || selectedKeyTime != nil {
            let current = try XCTUnwrap(store.marks.first { $0.id == mark.id })
            XCTAssertTrue(session.begin(mark: current, scenarioID: store.selectedScenarioID,
                                        duration: store.selectedScenario.duration, store: store))
            if pendingDrafts { session.window.startText = "1" }
            XCTAssertTrue(session.position.select(selectedKeyTime ?? 2))
            if pendingDrafts { session.position.text = "3" }
            if let positionText { session.position.text = positionText }
            XCTAssertEqual(session.hasUnsavedChanges, pendingDrafts || positionText != nil)
            XCTAssertTrue(store.canChangePlaybackView, "Close stays available with unsaved drafts")
        }
        defer { session.releaseOwnership() }
        let view = AnnotationTimingEditor(markID: mark.id, color: ReplayTheme.cyan,
                                          draftSession: pendingDrafts || selectedKeyTime != nil ? session : nil)
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
        if revealSelectedKey {
            func verticalScroll(in view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView,
                   scroll.contentSize.height > scroll.bounds.height + 1 { return scroll }
                return view.subviews.lazy.compactMap { verticalScroll(in: $0) }.first
            }
            let scroll = try XCTUnwrap(verticalScroll(in: host.view))
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
            host.view.layoutIfNeeded()
        }
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
