import CoreText
import UIKit
import XCTest
@testable import ReplayXI

/// Native font/SF-symbol budgets, not a SwiftUI render. Full-font misses and
/// permitted-minimum misses are separate: a label that can shrink is not proof
/// of visible clipping. System button padding/compression needs interactive QA.
@MainActor
final class PlaybackRosterTextMetricsTests: XCTestCase {
    private let categories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge
    ]

    func testEveryTextSizeHasNativeRosterAndCompactButtonMeasurements() throws {
        let records = try categories.map(metrics)
        try attach(records)
        XCTAssertEqual(records.count, 12)
        for record in records {
            XCTAssertTrue(record.rosterFullHeight.isFinite)
            XCTAssertGreaterThan(record.rosterMinimumHeight, 0)
            XCTAssertEqual(record.compactButtons.count, 3)
            XCTAssertTrue(record.compactButtons.allSatisfy { $0.symbolHeight > 0 })
        }
    }

    func testRosterFullTextFitsTheLiveHeightPolicyAtEverySize() throws {
        for record in try categories.map(metrics) {
            XCTAssertLessThanOrEqual(record.rosterFullHeight, record.rosterHeightLimit,
                "\(record.category): full number + role line heights, without shrinking")
        }
    }

    func testRosterStillFitsItsExplicitlyPermittedMinimumFontBudget() throws {
        for record in try categories.map(metrics) {
            XCTAssertLessThanOrEqual(record.rosterMinimumHeight, record.rosterHeightLimit, record.category)
            XCTAssertLessThanOrEqual(record.maximumShirtWidth, record.rosterWidthLimit, record.category)
            XCTAssertLessThanOrEqual(record.maximumRoleWidth * record.roleMinimumScale,
                record.rosterWidthLimit, record.category)
        }
    }

    func testCompactPOVToolsAndDrawFitTheirCurrentPermittedBudgets() throws {
        for record in try categories.map(metrics) {
            for button in record.compactButtons {
                let context = "\(record.category): \(button.name)"
                XCTAssertLessThanOrEqual(button.minimumStackHeight, button.heightLimit, context)
                XCTAssertLessThanOrEqual(button.minimumTextWidth, button.widthLimit, context)
                XCTAssertLessThanOrEqual(button.symbolWidth, button.widthLimit, context)
            }
        }
    }

    func testProbeMatchesTheLiveTwoLineLabelAndFramePolicy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let roster = try slice(source, after: "private func perspectivePlayerButton(_ player: PlayerTrack)",
            before: "private var playerGridInstruction:")
        XCTAssertTrue(roster.contains("VStack(spacing: 0)"))
        XCTAssertTrue(roster.contains(".font(.subheadline.monospacedDigit().weight(.black))"))
        XCTAssertTrue(roster.contains(".font(.caption2.monospaced().weight(.black))"))
        XCTAssertTrue(roster.contains(".minimumScaleFactor(primaryControlLayout.rosterRoleMinimumTextScale)"))
        XCTAssertTrue(roster.contains(".frame(width: primaryControlLayout.rosterLabelWidth)"))
        XCTAssertTrue(roster.contains(".frame(minHeight: primaryControlLayout.rosterLabelMinimumHeight)"))

        for (start, end, width, minimumScale) in [
            ("private var playbackToolsButton:", "private var compactPlayerControlButton:", "toolsLabelWidth", ""),
            ("private var compactPlayerControlButton:", "private var activePlayerCompactLabel:", "playerLabelWidth", ".minimumScaleFactor(primaryControlLayout.playerMinimumTextScale)"),
            ("private var annotationToolsButton:", "private var controlDeckPreset:", "drawLabelWidth", "")
        ] {
            let button = try slice(source, after: start, before: end)
            if width == "playerLabelWidth" {
                XCTAssertTrue(button.contains("VStack(spacing: 1)"))
                XCTAssertTrue(button.contains(".font(.caption.monospaced().weight(.black))"))
            } else {
                XCTAssertFalse(button.contains("Text("))
                XCTAssertTrue(button.contains(".font(.title2.weight(.semibold))"))
                XCTAssertTrue(button.contains(".help("))
                XCTAssertTrue(button.contains(".accessibilityLabel("))
            }
            XCTAssertTrue(button.contains(".frame(width: primaryControlLayout.\(width))"))
            XCTAssertTrue(button.contains(".frame(minHeight: primaryControlLayout.compactLabelMinimumHeight)"))
            if minimumScale.isEmpty {
                XCTAssertFalse(button.contains("minimumScaleFactor"))
            } else {
                XCTAssertTrue(button.contains(minimumScale))
            }
        }
    }

    func testRegularLayoutStaysCompactAndAccessibilityLabelsDoNotShrink() {
        let regular = PlaybackPrimaryControlLabelLayout.resolve(usesAccessibilityText: false)
        XCTAssertEqual(regular.speedLabelWidth, 74)
        XCTAssertEqual(regular.playerLabelWidth, 116)
        XCTAssertEqual(regular.toolsLabelWidth, 78)
        XCTAssertEqual(regular.drawLabelWidth, 76)
        XCTAssertEqual(regular.compactLabelMinimumHeight, 60)
        XCTAssertEqual(regular.playerMinimumTextScale, 0.82)
        XCTAssertEqual(regular.rosterLabelWidth, 72)
        XCTAssertEqual(regular.rosterLabelMinimumHeight, 60)
        XCTAssertEqual(regular.rosterRoleMinimumTextScale, 0.75)
        let accessible = PlaybackPrimaryControlLabelLayout.resolve(usesAccessibilityText: true)
        XCTAssertEqual(accessible.speedLabelWidth, 80)
        XCTAssertEqual(accessible.playerMinimumTextScale, 1)
        XCTAssertEqual(accessible.rosterRoleMinimumTextScale, 1)
    }

    func testExpandedControlsRetainTheTimelineAndBothCompleteRosterRows() {
        let regular = PlaybackPrimaryControlLabelLayout.resolve(usesAccessibilityText: false)
        let accessible = PlaybackPrimaryControlLabelLayout.resolve(usesAccessibilityText: true)
        let hitTarget = PlaybackControlDeckPresentation.minimumSpatialHitTarget
        let fixedTransportLabels = 3 * hitTarget + 64 // Exit, previous, play, next.
        let compactLabels = accessible.speedLabelWidth + accessible.playerLabelWidth
            + accessible.drawLabelWidth + accessible.toolsLabelWidth
        // Eight styled buttons, eight row gaps and the live rail's 230 pt
        // minimum. The 48 pt/style reserve is allocation, not a render measure.
        let accessibleRowBudget = fixedTransportLabels + compactLabels + 8 * 48 + 8 * 8 + 230
        let growth = accessible.speedLabelWidth + accessible.playerLabelWidth
            + accessible.toolsLabelWidth + accessible.drawLabelWidth
            - regular.speedLabelWidth - regular.playerLabelWidth
            - regular.toolsLabelWidth - regular.drawLabelWidth
        for preset in PlaybackControlDeckPreset.allCases {
            let regularDeck = PlaybackControlDeckLayout.resolve(preset: preset, usesAccessibilityText: false)
            let accessibleDeck = PlaybackControlDeckLayout.resolve(preset: preset, usesAccessibilityText: true)
            XCTAssertLessThanOrEqual(accessibleRowBudget, accessibleDeck.contentWidth - 44)
            XCTAssertLessThanOrEqual(growth, accessibleDeck.contentWidth - regularDeck.contentWidth,
                "Normal sizing is unchanged; AX control growth stays within the existing extra deck width")
            for (labels, deck) in [(regular, regularDeck), (accessible, accessibleDeck)] {
                let rosterRowBudget = 72 + 11 * labels.rosterLabelWidth + 11 * 6
                XCTAssertLessThanOrEqual(rosterRowBudget, deck.contentWidth - 44 - 20)
            }
        }
    }

    private struct Metrics: Encodable {
        let category: String
        let shirtLineHeight: Double
        let roleLineHeight: Double
        let rosterFullHeight: Double
        let rosterMinimumHeight: Double
        let rosterWidthLimit: Double
        let rosterHeightLimit: Double
        let roleMinimumScale: Double
        let maximumShirtWidth: Double
        let maximumRoleWidth: Double
        let compactButtons: [CompactBudget]
    }

    private struct CompactBudget: Encodable {
        let name: String
        let widthLimit: Double
        let heightLimit: Double
        let captionLineHeight: Double
        let symbolWidth: Double
        let symbolHeight: Double
        let fullTextWidth: Double
        let minimumTextWidth: Double
        let fullStackHeight: Double
        let minimumStackHeight: Double
    }

    private func metrics(for category: UIContentSizeCategory) throws -> Metrics {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let layout = PlaybackPrimaryControlLabelLayout.resolve(
            usesAccessibilityText: category.isAccessibilityCategory)
        let shirt = UIFont.monospacedDigitSystemFont(ofSize:
            UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).pointSize, weight: .black)
        let role = UIFont.monospacedSystemFont(ofSize:
            UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traits).pointSize, weight: .black)
        let caption = UIFont.monospacedSystemFont(ofSize:
            UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits).pointSize, weight: .black)
        let headlineSize = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits).pointSize
        let players = DemoScenarios.all.flatMap(\.players)
        let shirtWidths = Set(players.map { "#\($0.shirtNumber)" }).map { width($0, font: shirt) }
        let roleWidths = Set(players.map(\.positionCode)).map { width($0, font: role) }

        func compact(_ name: String, symbol: String, weight: UIFont.Weight,
                     widthLimit: Double, minimumScale: Double, iconOnly: Bool = false) throws -> CompactBudget {
            let iconSize = iconOnly
                ? UIFont.preferredFont(forTextStyle: .title2, compatibleWith: traits).pointSize : headlineSize
            let font = UIFont.systemFont(ofSize: iconSize, weight: weight)
            let image = try XCTUnwrap(UIImage(systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(font: font)))
            let textWidth = iconOnly ? 0 : width(name, font: caption)
            let textHeight = iconOnly ? 0 : Double(caption.lineHeight)
            let gap: Double = iconOnly ? 0 : 1
            return CompactBudget(
                name: name, widthLimit: widthLimit,
                heightLimit: Double(layout.compactLabelMinimumHeight),
                captionLineHeight: textHeight,
                symbolWidth: Double(image.size.width), symbolHeight: Double(image.size.height),
                fullTextWidth: textWidth, minimumTextWidth: textWidth * minimumScale,
                fullStackHeight: Double(image.size.height) + textHeight + gap,
                minimumStackHeight: Double(image.size.height) + textHeight * minimumScale + gap
            )
        }

        return Metrics(
            category: category.rawValue,
            shirtLineHeight: Double(shirt.lineHeight), roleLineHeight: Double(role.lineHeight),
            rosterFullHeight: Double(shirt.lineHeight + role.lineHeight),
            rosterMinimumHeight: Double(shirt.lineHeight) + Double(role.lineHeight) * Double(layout.rosterRoleMinimumTextScale),
            rosterWidthLimit: Double(layout.rosterLabelWidth),
            rosterHeightLimit: Double(layout.rosterLabelMinimumHeight),
            roleMinimumScale: Double(layout.rosterRoleMinimumTextScale),
            maximumShirtWidth: shirtWidths.max() ?? 0,
            maximumRoleWidth: roleWidths.max() ?? 0,
            compactButtons: [
                try compact("POV PLAYER", symbol: "person.crop.rectangle.stack.fill", weight: .bold,
                    widthLimit: Double(layout.playerLabelWidth), minimumScale: Double(layout.playerMinimumTextScale)),
                try compact("TOOLS", symbol: "square.grid.2x2.fill", weight: .semibold,
                    widthLimit: Double(layout.toolsLabelWidth), minimumScale: 1, iconOnly: true),
                try compact("DRAW", symbol: "pencil.and.outline", weight: .semibold,
                    widthLimit: Double(layout.drawLabelWidth), minimumScale: 1, iconOnly: true)
            ]
        )
    }

    private func width(_ text: String, font: UIFont) -> Double {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font]) as CFAttributedString)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private func attach(_ records: [Metrics]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(records), uniformTypeIdentifier: "public.json")
        attachment.name = "Roster-and-compact-all-Dynamic-Type-font-budgets"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
