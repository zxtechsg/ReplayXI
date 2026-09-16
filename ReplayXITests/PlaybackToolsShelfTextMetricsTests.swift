import CoreText
import UIKit
import XCTest
@testable import ReplayXI

/// Native text and SF-symbol budgets, not rendered SwiftUI bounds. A zero
/// Label gap is deliberately generous. Edit's minimum also scales its icon,
/// so a failure does not depend on how Label propagates minimumScaleFactor.
@MainActor
final class PlaybackToolsShelfTextMetricsTests: XCTestCase {
    private let categories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge
    ]

    func testEveryTextSizeHasNativeToolsLabelMeasurements() throws {
        let records = try categories.map(metrics)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(records), uniformTypeIdentifier: "public.json")
        attachment.name = "Tools-shelf-all-Dynamic-Type-font-and-symbol-budgets"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(records.count, 12)
        for record in records {
            XCTAssertEqual(record.tools.count, 5)
            XCTAssertTrue(record.tools.allSatisfy { $0.textWidth > 0 && $0.symbolWidth > 0 })
        }
    }

    func testLabelsFitTheirMostGenerousPermittedWidthAtEveryTextSize() throws {
        for record in try categories.map(metrics) {
            for tool in record.tools {
                XCTAssertLessThanOrEqual(tool.generousMinimumWidth, tool.widthLimit,
                    "\(record.category): \(tool.title), zero Label gap and permitted scaling")
            }
        }
    }

    func testRegularTextCategoriesFitTheExistingCompactLabelWidths() throws {
        for category in categories where !category.isAccessibilityCategory {
            let record = try metrics(for: category)
            for tool in record.tools {
                XCTAssertLessThanOrEqual(tool.generousMinimumWidth, tool.widthLimit,
                    "\(record.category): \(tool.title)")
            }
        }
    }

    func testHorizontalLabelsFitTheirExistingHeightBudget() throws {
        for record in try categories.map(metrics) {
            for tool in record.tools {
                XCTAssertLessThanOrEqual(tool.fullHeight, tool.heightLimit,
                    "\(record.category): \(tool.title)")
            }
        }
    }

    func testProbeMatchesTheLiveToolFontsFramesAndPermittedScale() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let fixtures: [(start: String, end: String, title: String, symbol: String, weight: String, key: String)] = [
            ("private var annotationEventsButton:", "private var decisionReviewButton:",
                "Timeline", "list.bullet.rectangle.fill", "black", "timeline"),
            ("private var decisionReviewButton:", "private var annotationEventStrip:",
                "Decisions", "eye.fill", "black", "decisions"),
            ("private var settingsToolButton:", "private func inlinePanelShelf(",
                "Settings", "slider.horizontal.3", "black", "settings"),
            ("private var playbackToolsShelf:", "private var settingsToolButton:",
                "Reviews", "bookmark", "bold", "reviews"),
            ("private func annotationEditButton(compact:", "private var playbackToolsShelf:",
                "Edit marks", "eraser.fill", "black", "edit")
        ]
        for fixture in fixtures {
            let button = try slice(source, after: fixture.start, before: fixture.end)
            XCTAssertTrue(button.contains("Label(\"\(fixture.title)\", systemImage: \"\(fixture.symbol)\")"))
            XCTAssertTrue(button.contains(".font(.subheadline.weight(.\(fixture.weight)))"))
            XCTAssertTrue(button.contains(".lineLimit(1)"))
            XCTAssertTrue(button.contains(
                ".frame(width: toolsShelfLayout.labelWidth(for: .\(fixture.key)),"))
            XCTAssertTrue(button.contains("height: toolsShelfLayout.fixedLabelHeight)"))
            XCTAssertTrue(button.contains(".frame(minHeight: toolsShelfLayout.labelMinimumHeight)"))
            if fixture.title == "Edit marks" {
                XCTAssertTrue(button.contains(".minimumScaleFactor(toolsShelfLayout.editMinimumTextScale)"))
            } else {
                XCTAssertFalse(button.contains("minimumScaleFactor"))
            }
        }
        let shelf = try slice(source, after: "private var playbackToolsShelf:", before: "private var settingsToolButton:")
        XCTAssertTrue(shelf.contains("if toolsShelfLayout.usesAdaptiveGrid"))
        XCTAssertTrue(shelf.contains("LazyVGrid("))
        XCTAssertTrue(shelf.contains(".adaptive(minimum: toolsShelfLayout.gridMinimumCellWidth)"))
        XCTAssertTrue(shelf.contains("spacing: PlaybackToolsShelfLayout.gridSpacing"))
        XCTAssertTrue(shelf.contains("PlaybackToolsShelfLayout.resolve(usesAccessibilityText: dynamicTypeSize.isAccessibilitySize)"))
        XCTAssertEqual(shelf.components(separatedBy: "playbackToolsChoices").count - 1, 3,
            "Both layouts share one set of unchanged choices")
    }

    func testNormalShelfFramesAndEditScaleStayUnchanged() {
        let layout = PlaybackToolsShelfLayout.resolve(usesAccessibilityText: false)
        XCTAssertFalse(layout.usesAdaptiveGrid)
        XCTAssertEqual(layout.headingWidth, 108)
        XCTAssertEqual(layout.fixedLabelHeight, 60)
        XCTAssertEqual(layout.labelMinimumHeight, 60)
        XCTAssertEqual(layout.editMinimumTextScale, 0.78)
        let widths: [(PlaybackToolsShelfLayout.Tool, CGFloat)] = [
            (.timeline, 126), (.decisions, 132), (.settings, 126), (.reviews, 126), (.edit, 124)
        ]
        for (tool, width) in widths {
            XCTAssertEqual(layout.labelWidth(for: tool), width)
        }
    }

    func testAccessibilityFullLabelsAndAdaptiveGridFitEveryPreset() throws {
        let layout = PlaybackToolsShelfLayout.resolve(usesAccessibilityText: true)
        XCTAssertTrue(layout.usesAdaptiveGrid)
        XCTAssertNil(layout.fixedLabelHeight)
        XCTAssertEqual(layout.editMinimumTextScale, 1)
        for category in categories where category.isAccessibilityCategory {
            let record = try metrics(for: category)
            for tool in record.tools {
                XCTAssertLessThanOrEqual(tool.fullContentWidth + Double(PlaybackToolsShelfLayout.labelSpacingAllowance),
                    tool.widthLimit, "\(record.category): \(tool.title), full font plus Label-gap allowance")
            }
            XCTAssertLessThanOrEqual(record.toolsHeadingFullWidth, Double(layout.headingWidth), record.category)
        }
        for preset in PlaybackControlDeckPreset.allCases {
            let deck = PlaybackControlDeckLayout.resolve(preset: preset, usesAccessibilityText: true)
            let available = Double(deck.contentWidth) - 44 - 20
            let spacing = Double(PlaybackToolsShelfLayout.gridSpacing)
            let cell = Double(layout.gridMinimumCellWidth)
            let columns = min(5, Int((available + spacing) / (cell + spacing)))
            XCTAssertGreaterThanOrEqual(columns, 4)
            guard columns > 0 else { continue }
            XCTAssertLessThanOrEqual(Double(columns) * cell + Double(columns - 1) * spacing, available)
            XCTAssertLessThanOrEqual((5 + columns - 1) / columns, 2)
            // AX header is a separate row. The 48 pt style allowance is an
            // allocation reserve, not measured native button padding.
            let header = 60 + 48 + Double(layout.headingWidth) + 10 + 6
            XCTAssertLessThanOrEqual(header, available)
        }
    }

    private struct Metrics: Encodable {
        let category: String
        let tools: [ToolBudget]
        let toolsHeadingFullWidth: Double
        let toolsShelfInnerWidth: Double
    }

    private struct ToolBudget: Encodable {
        let title: String
        let textWidth: Double
        let symbolWidth: Double
        let symbolHeight: Double
        let fontLineHeight: Double
        let minimumScale: Double
        let fullContentWidth: Double
        let textOnlyScaledWidth: Double
        let generousMinimumWidth: Double
        let fullHeight: Double
        let widthLimit: Double
        let heightLimit: Double
    }

    private func metrics(for category: UIContentSizeCategory) throws -> Metrics {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let size = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).pointSize
        let black = UIFont.systemFont(ofSize: size, weight: .black)
        let bold = UIFont.systemFont(ofSize: size, weight: .bold)
        let eyebrow = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(
            forTextStyle: .caption2, compatibleWith: traits).pointSize, weight: .black)
        let layout = PlaybackToolsShelfLayout.resolve(usesAccessibilityText: category.isAccessibilityCategory)
        let specs: [(title: String, symbol: String, font: UIFont, tool: PlaybackToolsShelfLayout.Tool)] = [
            ("Timeline", "list.bullet.rectangle.fill", black, .timeline),
            ("Decisions", "eye.fill", black, .decisions),
            ("Settings", "slider.horizontal.3", black, .settings),
            ("Reviews", "bookmark", bold, .reviews),
            ("Edit marks", "eraser.fill", black, .edit)
        ]
        let tools = try specs.map { spec in
            let image = try XCTUnwrap(UIImage(systemName: spec.symbol,
                withConfiguration: UIImage.SymbolConfiguration(font: spec.font)))
            let text = textWidth(spec.title, font: spec.font)
            let symbol = Double(image.size.width)
            let scale = spec.tool == .edit ? Double(layout.editMinimumTextScale) : 1
            return ToolBudget(title: spec.title, textWidth: text, symbolWidth: symbol,
                symbolHeight: Double(image.size.height), fontLineHeight: Double(spec.font.lineHeight),
                minimumScale: scale, fullContentWidth: text + symbol,
                textOnlyScaledWidth: text * scale + symbol,
                generousMinimumWidth: (text + symbol) * scale,
                fullHeight: Double(max(spec.font.lineHeight, image.size.height)),
                widthLimit: Double(layout.labelWidth(for: spec.tool)),
                heightLimit: Double(layout.labelMinimumHeight))
        }
        let deck = PlaybackControlDeckLayout.resolve(preset: .standard,
            usesAccessibilityText: category.isAccessibilityCategory)
        return Metrics(category: category.rawValue, tools: tools,
            toolsHeadingFullWidth: max(textWidth("PLAYBACK", font: eyebrow, tracking: 1.4),
                textWidth("TOOLS", font: black)),
            toolsShelfInnerWidth: Double(deck.contentWidth) - 44 - 20)
    }

    private func textWidth(_ text: String, font: UIFont, tracking: Double = 0) -> Double {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
            attributes: [.font: font, .kern: tracking]) as CFAttributedString)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
