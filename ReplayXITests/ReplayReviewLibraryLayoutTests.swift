import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewLibraryLayoutTests: XCTestCase {
    func testAccessibilitySheetAndScrollableBodyHaveSeparateBudgets() {
        let regular = ReplayReviewLibraryLayout.resolve(usesAccessibilityText: false)
        let large = ReplayReviewLibraryLayout.resolve(usesAccessibilityText: true)
        XCTAssertEqual(regular.sheetWidth, 820)
        XCTAssertGreaterThan(large.sheetWidth, regular.sheetWidth)
        XCTAssertGreaterThan(large.sheetHeight, 390, "Former fixed sheet cannot accommodate the large-text layout")
        XCTAssertGreaterThan(large.contentHeight, 190, "Large-text rows need more than the former list height")
        for layout in [regular, large] {
            XCTAssertGreaterThan(layout.sheetHeight - layout.contentHeight, 180)
            XCTAssertLessThanOrEqual(layout.contentHeight, 380)
        }
    }

    func testLibraryRemainsInlineAndKeepsSnapshotAtRequest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/UI/ReplayReviewLibraryView.swift"), encoding: .utf8)
        for modal in [".sheet(", ".popover(", ".alert(", "Menu {"] {
            XCTAssertFalse(source.contains(modal), modal)
        }
        XCTAssertTrue(source.contains("pendingSaveState = store.makeSavedReviewState()"))
        XCTAssertTrue(source.contains("store.saveReview(named: reviewName, state: pendingSaveState)"))
        XCTAssertTrue(source.contains(".disabled(!store.canSaveReview || action != nil)"),
                      "A second Save request must not replace the moment while naming the first")
        XCTAssertTrue(source.contains(".id(action == nil)"), "Confirmations open at the scroll top")
        XCTAssertTrue(source.contains(".frame(height: layout.contentHeight)"))
        XCTAssertFalse(source.contains(".frame(height: 190)"))
        let dashboard = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/UI/ReplayDashboardView.swift"), encoding: .utf8)
        XCTAssertTrue(dashboard.contains("width: libraryLayout.sheetWidth, height: libraryLayout.sheetHeight"))
    }

    func testNativeRegularLibraryFitsAndRenders() throws {
        try renderLibrary(typeSize: .large, blocked: false, name: "review-library-regular")
    }

    func testNativeLargestTextLibraryFitsAndRenders() throws {
        try renderLibrary(typeSize: .accessibility5, blocked: false, name: "review-library-largest-text")
    }

    func testNativeLargestTextSaveBlockReasonStaysInsideSheet() throws {
        try renderLibrary(typeSize: .accessibility5, blocked: true, name: "review-library-largest-text-blocked")
    }

    func testNativeLoadAndDeleteConfirmationsWrapAtLargestText() throws {
        for destructive in [false, true] {
            let view = ReplayReviewInlineConfirmation(
                title: destructive ? "Delete this saved review?" : "Load this review?",
                detail: destructive ? "The current replay and last session are kept."
                    : "Replaces your current marks and view. Save a copy first to keep them.",
                button: destructive ? "Delete" : "Load paused", destructive: destructive,
                cancel: {}, confirm: {})
                .buttonStyle(.bordered).controlSize(.large)
                .dynamicTypeSize(.accessibility5).padding(20)
                .background(ReplayTheme.navy).environment(\.colorScheme, .dark)
            let host = UIHostingController(rootView: view)
            let fitting = host.sizeThatFits(in: CGSize(width: 500, height: 2000))
            XCTAssertTrue(fitting.height.isFinite)
            XCTAssertGreaterThan(fitting.height, 100)
            XCTAssertLessThanOrEqual(fitting.width, 500)
            try capture(host, size: CGSize(width: 500, height: ceil(fitting.height)),
                        name: destructive ? "review-delete-confirmation-largest-text" : "review-load-confirmation-largest-text")
        }
    }

    private func renderLibrary(typeSize: DynamicTypeSize, blocked: Bool, name: String) throws {
        let store = ReplayStore()
        store.seek(to: 5)
        XCTAssertTrue(store.saveReview(named: "Overlapping right back — switch, cross and far-post movement"))
        if blocked { store.beginDrawing(.arc) }
        let layout = ReplayReviewLibraryLayout.resolve(usesAccessibilityText: typeSize.isAccessibilitySize)
        let library = ReplayReviewLibraryView(close: {})
            .environment(store).dynamicTypeSize(typeSize).environment(\.colorScheme, .dark)
        let fittingHost = UIHostingController(rootView: library)
        let fitting = fittingHost.sizeThatFits(in: CGSize(width: layout.sheetWidth - 32, height: 2000))
        XCTAssertTrue(fitting.height.isFinite)
        XCTAssertLessThanOrEqual(fitting.height + 32, layout.sheetHeight,
                                "Header and scrolling region must fit the dashboard sheet")
        let view = library.padding(16)
            .frame(width: layout.sheetWidth, height: layout.sheetHeight, alignment: .topLeading)
            .background(ReplayTheme.navy)
        try capture(UIHostingController(rootView: view),
                    size: CGSize(width: layout.sheetWidth, height: layout.sheetHeight), name: name)
    }

    private func capture<Content: View>(_ host: UIHostingController<Content>, size: CGSize, name: String) throws {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
