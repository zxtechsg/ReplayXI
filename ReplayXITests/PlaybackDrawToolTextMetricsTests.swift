import CoreText
import UIKit
import XCTest
@testable import ReplayXI

/// Actual platform font and SF-symbol budgets, not a rendered SwiftUI layout.
/// Button style padding cannot enlarge the fixed frame inside the label.
@MainActor
final class PlaybackDrawToolTextMetricsTests: XCTestCase {
    private let categories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge
    ]
    private let tools: [(CoachMarkKind, String)] = [
        (.run, "RUN"), (.pass, "PASS"), (.danger, "PRESS"), (.space, "ZONE"), (.playerLabel, "LABEL")
    ]

    func testEveryDrawToolHasFiniteNativeMeasurementsAtEveryTextSize() throws {
        let records = try categories.flatMap(metrics)
        XCTAssertEqual(records.count, 60)
        XCTAssertTrue(records.allSatisfy {
            $0.textWidth > 0 && $0.symbolWidth > 0 && $0.stackHeight > 0
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(records), uniformTypeIdentifier: "public.json")
        attachment.name = "Draw-tools-all-Dynamic-Type-font-and-symbol-budgets"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDrawToolContentFitsItsLiveWidthAtEveryTextSize() throws {
        for metric in try categories.flatMap(metrics) {
            XCTAssertLessThanOrEqual(max(metric.textWidth, metric.symbolWidth), metric.widthLimit,
                "\(metric.category): \(metric.title)")
        }
    }

    func testDrawToolContentFitsItsLiveHeightAtEveryTextSize() throws {
        for metric in try categories.flatMap(metrics) {
            XCTAssertLessThanOrEqual(metric.stackHeight, metric.heightLimit,
                "\(metric.category): \(metric.title)")
        }
    }

    func testDefaultTextSizeFitsTheExistingDrawLabels() throws {
        for metric in try metrics(for: .large) {
            XCTAssertLessThanOrEqual(max(metric.textWidth, metric.symbolWidth), 70)
            XCTAssertLessThanOrEqual(metric.stackHeight, 48)
        }
    }

    func testRegularPolicyPreservesExistingCompactSizes() {
        let layout = PlaybackDrawToolLayout.resolve(usesAccessibilityText: false)
        XCTAssertFalse(layout.usesStackedShelves)
        XCTAssertEqual(layout.labelWidth, 70)
        XCTAssertEqual(layout.labelMinimumHeight, 48)
        XCTAssertEqual(layout.instructionMinimumScale, 0.72)
        XCTAssertEqual(layout.cancelLabelWidth, 28)
        XCTAssertEqual(layout.cancelLabelMinimumHeight, 48)
        XCTAssertEqual(PlaybackDrawToolLayout.drawingInstructionWidth, 190)
        XCTAssertEqual(PlaybackDrawToolLayout.idleInstructionWidth, 180)
    }

    func testBothToolRowsFitTheExistingDeckWidthAtEveryTextSize() {
        for category in categories {
            let layout = PlaybackDrawToolLayout.resolve(usesAccessibilityText: category.isAccessibilityCategory)
            for preset in PlaybackControlDeckPreset.allCases {
                let deck = PlaybackControlDeckLayout.resolve(preset: preset,
                    usesAccessibilityText: category.isAccessibilityCategory)
                // Reserve 48 pt native button-style allowance per button.
                // These are allocations, not rendered SwiftUI measurements.
                let toolWidths = 5 * (layout.labelWidth + 48)
                if layout.usesStackedShelves {
                    XCTAssertEqual(layout.instructionMinimumScale, 1)
                    XCTAssertLessThanOrEqual(toolWidths + 5 * 10, deck.contentWidth - 32)
                    XCTAssertLessThanOrEqual(toolWidths + 5 * 9, deck.contentWidth - 44 - 24)
                } else {
                    let timestamp = timestampWidth(for: category)
                    let drawing = layout.cancelLabelWidth + 48
                        + PlaybackDrawToolLayout.drawingInstructionWidth + toolWidths
                        + CGFloat(timestamp) + 60 + 48 + 9 * 10 + 6
                    XCTAssertLessThanOrEqual(drawing, deck.contentWidth - 32, category.rawValue)
                    let idle = PlaybackDrawToolLayout.idleInstructionWidth + toolWidths
                        + 60 + 48 + 7 * 9 + 6
                    XCTAssertLessThanOrEqual(idle, deck.contentWidth - 44 - 24, category.rawValue)
                }
            }
        }
    }

    func testDrawingInstructionsFitEvenTheirBestCaseShrunkWidth() throws {
        let instructions = [
            ("PINCH PLAYER", "person.crop.circle.badge.plus"),
            ("RELEASE TO SAVE", "checkmark.circle.fill"),
            ("DRAG FARTHER", "arrow.up.right"),
            ("PINCH + DRAG", "hand.draw.fill"),
            ("PINCH END · OR TAP", "2.circle.fill")
        ]
        for category in categories {
            let layout = PlaybackDrawToolLayout.resolve(usesAccessibilityText: category.isAccessibilityCategory)
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(
                forTextStyle: .subheadline, compatibleWith: traits).pointSize, weight: .black)
            for (title, symbol) in instructions {
                let image = try XCTUnwrap(UIImage(systemName: symbol,
                    withConfiguration: UIImage.SymbolConfiguration(font: font)))
                let line = CTLineCreateWithAttributedString(NSAttributedString(
                    string: title, attributes: [.font: font]) as CFAttributedString)
                // A conservative lower bound: omit Label's implicit gap and
                // even allow the image to shrink with the text. Failure still
                // means the existing fixed label cannot fit on one line.
                let minimumWidth = (CTLineGetTypographicBounds(line, nil, nil, nil)
                    + Double(image.size.width)) * Double(layout.instructionMinimumScale)
                for preset in PlaybackControlDeckPreset.allCases {
                    let deck = PlaybackControlDeckLayout.resolve(preset: preset,
                        usesAccessibilityText: category.isAccessibilityCategory)
                    let available = layout.usesStackedShelves
                        ? Double(deck.contentWidth - 32 - (layout.cancelLabelWidth + 48) - (60 + 48) - 3 * 10)
                            - timestampWidth(for: category) - 12 // Extra allowance for the Label gap.
                        : Double(PlaybackDrawToolLayout.drawingInstructionWidth)
                    XCTAssertLessThanOrEqual(minimumWidth, available,
                        "\(category.rawValue): \(title), \(preset)")
                }
            }
        }
    }

    func testProbeMatchesLiveSharedDrawToolLabelFontsAndFrames() throws {
        let source = try immersiveSource()
        let tool = try slice(source, after: "private func annotationToolButton(", before: "private var orderedMarks:")
        XCTAssertTrue(tool.contains("VStack(spacing: 1)"))
        XCTAssertTrue(tool.contains(".font(.headline.weight(.bold))"))
        XCTAssertTrue(tool.contains(".font(.caption2.monospaced().weight(.black))"))
        XCTAssertTrue(tool.contains(".frame(width: drawToolLayout.labelWidth)"))
        XCTAssertTrue(tool.contains(".frame(minHeight: drawToolLayout.labelMinimumHeight)"))
        XCTAssertFalse(tool.contains("minimumScaleFactor"))
        let shelves = try slice(source, after: "private var annotationDrawingShelf:", before: "private var povStatusChip:")
        for title in ["Run", "Pass", "Press", "Zone", "Label"] {
            XCTAssertEqual(shelves.components(separatedBy: "label: \"\(title)\"").count - 1, 1)
        }
        XCTAssertEqual(shelves.components(separatedBy: "if drawToolLayout.usesStackedShelves").count - 1, 2)
        XCTAssertEqual(shelves.split(separator: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces) == "annotationToolChoices"
        }.count, 4)
        XCTAssertTrue(shelves.contains(".minimumScaleFactor(drawToolLayout.instructionMinimumScale)"))
        XCTAssertTrue(shelves.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(shelves.contains("store.cancelDrawing()"))
        XCTAssertTrue(tool.contains("store.beginDrawing(kind)"))
        XCTAssertTrue(tool.contains("showsPlaybackAnnotations = true"))
    }

    private struct Metric: Encodable {
        let category: String
        let title: String
        let textWidth: Double
        let symbolWidth: Double
        let stackHeight: Double
        let widthLimit: Double
        let heightLimit: Double
    }

    private func metrics(for category: UIContentSizeCategory) throws -> [Metric] {
        let layout = PlaybackDrawToolLayout.resolve(usesAccessibilityText: category.isAccessibilityCategory)
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let caption = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(
            forTextStyle: .caption2, compatibleWith: traits).pointSize, weight: .black)
        let headline = UIFont.systemFont(ofSize: UIFont.preferredFont(
            forTextStyle: .headline, compatibleWith: traits).pointSize, weight: .bold)
        return try tools.map { kind, title in
            let image = try XCTUnwrap(UIImage(systemName: kind.systemImage,
                withConfiguration: UIImage.SymbolConfiguration(font: headline)))
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: title, attributes: [.font: caption]) as CFAttributedString)
            return Metric(category: category.rawValue, title: title,
                textWidth: CTLineGetTypographicBounds(line, nil, nil, nil),
                symbolWidth: Double(image.size.width),
                stackHeight: Double(image.size.height + caption.lineHeight) + 1,
                widthLimit: Double(layout.labelWidth), heightLimit: Double(layout.labelMinimumHeight))
        }
    }

    private func timestampWidth(for category: UIContentSizeCategory) -> Double {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(
            forTextStyle: .subheadline, compatibleWith: traits).pointSize, weight: .black)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "00:00", attributes: [.font: font]) as CFAttributedString)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private func immersiveSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
