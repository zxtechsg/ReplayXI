import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewName162Tests: XCTestCase {
    func testInputValidationMatchesSaveAndRenameWithoutTruncatingNames() throws {
        let store = ReplayStore()
        XCTAssertTrue(store.saveReview(named: "Original"))
        let original = try XCTUnwrap(store.savedReviews.first)
        let state = store.makeSavedReviewState()
        for invalid in ["", " \n\t ", String(repeating: "x", count: 61), "Run\npass", "Run\tpass"] {
            XCTAssertNotNil(ReplayReviewLibrary.nameValidationMessage(invalid))
            XCTAssertNotNil(ReplayReviewNameEditPolicy.blockReason(name: invalid, renaming: nil, in: store))
            XCTAssertNotNil(ReplayReviewNameEditPolicy.blockReason(name: invalid, renaming: original.id, in: store))
            XCTAssertFalse(store.saveReview(named: invalid, state: state))
            XCTAssertFalse(store.renameSavedReview(id: original.id, name: invalid))
            XCTAssertEqual(store.savedReviews, [original])
        }
        // Character count, not UTF-8 length; trim without cutting user content.
        let valid = String(repeating: "⚽️", count: 60)
        XCTAssertNil(ReplayReviewNameEditPolicy.blockReason(name: "  \(valid) \n", renaming: nil, in: store))
        XCTAssertTrue(store.saveReview(named: "  \(valid) \n", state: state))
        XCTAssertEqual(store.savedReviews.first?.name, valid)
        XCTAssertEqual(store.savedReviews.first?.state, state)
        XCTAssertTrue(store.renameSavedReview(id: original.id, name: "  Final pass  "))
        XCTAssertEqual(store.savedReviews.first { $0.id == original.id }?.name, "Final pass")
    }

    func testRenameUsesLiveIdentityButIsNotBlockedByNewSaveCapacityOrScrubbing() throws {
        let store = ReplayStore()
        for i in 0..<ReplayReviewLibrary.maximumSavedReviews {
            XCTAssertTrue(store.saveReview(named: "Review \(i)"))
        }
        let id = try XCTUnwrap(store.savedReviews.first?.id)
        XCTAssertNotNil(ReplayReviewNameEditPolicy.blockReason(name: "New", renaming: nil, in: store))
        XCTAssertNil(ReplayReviewNameEditPolicy.blockReason(name: "Renamed", renaming: id, in: store))
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertNil(ReplayReviewNameEditPolicy.blockReason(name: "Renamed", renaming: id, in: store))
        XCTAssertTrue(store.renameSavedReview(id: id, name: "Renamed"))
        XCTAssertTrue(store.hasActiveTimelineScrub)
        store.cancelTimelineScrub()
        XCTAssertTrue(store.deleteSavedReview(id: id))
        XCTAssertEqual(ReplayReviewNameEditPolicy.blockReason(name: "Renamed", renaming: id, in: store),
                       "This saved review is no longer available.")
    }

    func testReadOnlyDiagnosticRemainsAuthoritative() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReviewName162-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reviews.json")
        let bytes = Data("{\"version\":999}".utf8)
        try bytes.write(to: url)
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)
        for id in [nil, UUID()] as [UUID?] {
            XCTAssertEqual(ReplayReviewNameEditPolicy.blockReason(name: "", renaming: id, in: store),
                           "Saves need a newer app version")
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testInvalidNameFormFitsAndKeepsActionsReachableAtDefaultAndLargestText() throws {
        for largest in [false, true] {
            let store = ReplayStore()
            let state = store.makeSavedReviewState()
            let layout = ReplayReviewLibraryLayout.resolve(usesAccessibilityText: largest)
            let content = ReplayReviewLibraryView.namingForTesting(String(repeating: "Long name ", count: 7), state: state)
                .environment(store).environment(\.colorScheme, .dark)
                .dynamicTypeSize(largest ? .accessibility5 : .large)
            let sizing = UIHostingController(rootView: content)
            let size = sizing.sizeThatFits(in: CGSize(width: layout.sheetWidth - 32, height: 2000))
            XCTAssertLessThanOrEqual(size.height + 32, layout.sheetHeight)
            let host = UIHostingController(rootView: content.padding(16)
                .frame(width: layout.sheetWidth, height: layout.sheetHeight, alignment: .topLeading)
                .background(ReplayTheme.navy))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: layout.sheetWidth, height: layout.sheetHeight)
            window.rootViewController = host; window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            host.view.frame = window.bounds; host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.view.layoutIfNeeded()
            let scroll = try XCTUnwrap(verticalScroll(in: host.view))
            XCTAssertEqual(scroll.bounds.height, layout.contentHeight, accuracy: 1)
            let bottom = max(-scroll.adjustedContentInset.top,
                             scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            XCTAssertGreaterThanOrEqual(scroll.contentOffset.y + scroll.bounds.height, scroll.contentSize.height - 1)
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
            attachment.name = "ReviewName162-\(largest ? "AX5" : "default")"; attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(store.savedReviews.isEmpty)
            XCTAssertEqual(store.makeSavedReviewState(), state)
        }
    }

    private func verticalScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.bounds.height > 100 { return scroll }
        return view.subviews.lazy.compactMap { self.verticalScroll(in: $0) }.first
    }
}
