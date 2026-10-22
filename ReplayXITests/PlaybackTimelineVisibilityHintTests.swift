import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackTimelineVisibilityHintTests: XCTestCase {
    private let hint = "Marks may be hidden. Select one here to show it."

    func testHintUsesTheCachedMarkCountOnlyInsideTimeline() throws {
        let source = try editorSource()
        let strip = try XCTUnwrap(source.components(separatedBy: "struct SpatialAnnotationTracks: View").last)
        XCTAssertEqual(source.components(separatedBy: hint).count - 1, 1)
        XCTAssertTrue(strip.contains("if store.selectedScenario.kind == .realWorldReplay,"))
        XCTAssertTrue(strip.contains("marks.count > 1"))
        XCTAssertTrue(strip.contains("Text(\"\(hint)\")"))
        XCTAssertFalse(strip.contains("visibleAnnotationIDs"))
        XCTAssertFalse(strip.contains("isVisible(at:"))
        XCTAssertFalse(strip.contains("PlaybackSceneRenderBudget"))
        XCTAssertTrue(strip.contains("SpatialAnnotationTimeline(mark: mark, showsTitle: true)"))
        let host = try immersiveSource()
        XCTAssertTrue(host.contains("SpatialAnnotationTracks(marks: orderedMarks"))
        XCTAssertFalse(host.contains("private var annotationEventRow:"))
        XCTAssertFalse(host.contains("private func eventPageButton("))
    }

    func testHintGrowsVerticallyAboveTheLazyTrackList() throws {
        let source = try immersiveSource()
        let editor = try editorSource()
        let strip = try slice(editor, after: "if store.selectedScenario.kind == .realWorldReplay,",
                              before: "if marks.isEmpty")
        XCTAssertTrue(strip.contains(".font(.caption)"))
        XCTAssertTrue(strip.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertFalse(strip.contains("lineLimit"))
        XCTAssertFalse(strip.contains("minimumScaleFactor"))
        XCTAssertFalse(strip.contains("height:"))
        XCTAssertTrue(editor.contains("LazyVStack(spacing: 4)"))
        XCTAssertTrue(editor.contains("ForEach(marks)"))
        XCTAssertTrue(editor.contains(".frame(height: min(CGFloat(marks.count) * 88, 264))"))
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
