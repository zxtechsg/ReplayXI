import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackTimelineVisibilityHintTests: XCTestCase {
    private let hint = "Select a mark to edit. Fine timeline editing is on Mac coach."

    func testListShowsVisibilityAndRoutesFineEditingToMac() throws {
        let source = try editorSource()
        let strip = try XCTUnwrap(source.components(separatedBy: "struct SpatialAnnotationTracks: View").last)
        XCTAssertTrue(strip.contains(hint))
        XCTAssertTrue(strip.contains("Visible now"))
        XCTAssertTrue(strip.contains("Hidden now"))
        XCTAssertTrue(strip.contains("mark.isVisible(at: store.playhead)"))
        XCTAssertFalse(strip.contains("SpatialAnnotationTimeline("))
        XCTAssertTrue(try immersiveSource().contains("SpatialAnnotationTracks(marks: orderedMarks"))
    }

    func testListKeepsLargeTargetsAndThreeVisibleRows() throws {
        let editor = try editorSource()
        XCTAssertTrue(editor.contains("LazyVStack(spacing: 10)"))
        XCTAssertTrue(editor.contains("ForEach(marks)"))
        XCTAssertTrue(editor.contains(".frame(minHeight: 80)"))
        XCTAssertTrue(editor.contains(".frame(height: min(CGFloat(marks.count) * 94, 282))"))
        let source = try immersiveSource()
        let attachment = try slice(source, after: "Attachment(id: \"coach-console\")",
            before: "if store.selectedScenario.kind != .shapeLab")
        XCTAssertTrue(attachment.contains(".frame(width: controlDeckLayout.attachmentWidth)"))
        XCTAssertFalse(attachment.contains("height:"))
    }

    /// UIKit's native caption metrics are a text-budget diagnostic, not a
    /// SwiftUI attachment render or a headset comfort measurement.
    func testNativeCaptionCanWrapAtEveryTextSizeAndDeckPreset() {
        let categories: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge,
            .extraExtraLarge, .extraExtraExtraLarge, .accessibilityMedium,
            .accessibilityLarge, .accessibilityExtraLarge,
            .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge
        ]
        var measurements: [String] = []
        for category in categories {
            let font = UIFont.preferredFont(forTextStyle: .caption1,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
            for preset in PlaybackControlDeckPreset.allCases {
                let layout = PlaybackControlDeckLayout.resolve(
                    preset: preset, usesAccessibilityText: category.isAccessibilityCategory)
                // Match deck has 44 pt horizontal padding; the shelf has 20.
                let width = layout.contentWidth - 64
                let attributes: [NSAttributedString.Key: Any] = [.font: font]
                let bounds = (hint as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes, context: nil)
                XCTAssertGreaterThan(width, 0)
                XCTAssertTrue(bounds.height.isFinite)
                XCTAssertGreaterThan(bounds.height, 0)
                XCTAssertLessThanOrEqual(bounds.width, width + 1)
                for word in hint.split(separator: " ") {
                    XCTAssertLessThanOrEqual((String(word) as NSString).size(withAttributes: attributes).width,
                                             width, "An unbreakable word must not overflow")
                }
                measurements.append("\(category.rawValue) / \(preset.rawValue): \(width) pt width; \(bounds.height) pt text height")
            }
        }
        let attachment = XCTAttachment(string: measurements.joined(separator: "\n"))
        attachment.name = "Timeline hint native caption sizes — intrinsic height"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(measurements.count, 36)
    }

    private func immersiveSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
    }

    private func editorSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/SpatialAnnotationEditor.swift"), encoding: .utf8)
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
