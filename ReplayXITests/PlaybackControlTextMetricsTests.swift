import CoreText
import UIKit
import XCTest
@testable import ReplayXI

/// UIFont/CoreText measures the actual platform font sizes and line advances.
/// It is a text-budget probe, not a SwiftUI render: SF Symbol optical bounds,
/// button padding and SwiftUI compression still need an interactive layout pass.
@MainActor
final class PlaybackControlTextMetricsTests: XCTestCase {
    private let accessibilityCategories: [UIContentSizeCategory] = [
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge
    ]

    func testStandardPresetFitsNormalFixedControlBounds() throws {
        let metric = metrics(for: .large)
        let layout = PlaybackSecondaryControlLayout.resolve(usesAccessibilityText: false)
        try attach([metric], name: "Preset-normal-font-budget")
        XCTAssertFalse(layout.usesAdaptiveRates)
        XCTAssertLessThanOrEqual(metric.standardTextWidth, Double(layout.presetLabelWidth))
        XCTAssertLessThanOrEqual(metric.presetStackLineHeight, Double(layout.presetLabelMinimumHeight))
    }

    func testStandardPresetFitsAccessibilityControlPolicyWithoutShrinking() throws {
        let records = accessibilityCategories.map(metrics)
        let layout = PlaybackSecondaryControlLayout.resolve(usesAccessibilityText: true)
        try attach(records, name: "Preset-accessibility-font-budget")
        for metric in records {
            XCTAssertLessThanOrEqual(
                metric.standardTextWidth, Double(layout.presetLabelWidth),
                "\(metric.category): STANDARD must fit at full font size"
            )
            XCTAssertLessThanOrEqual(
                metric.presetStackLineHeight, Double(layout.presetLabelMinimumHeight),
                "\(metric.category): reserve a headline icon line, caption2 line and 1 pt spacing"
            )
        }
    }

    func testQuarterSpeedFitsNormalWidthAtItsPermittedMinimumScale() throws {
        let metric = metrics(for: .large)
        let layout = PlaybackSecondaryControlLayout.resolve(usesAccessibilityText: false)
        try attach([metric], name: "Speed-normal-font-budget")
        XCTAssertLessThanOrEqual(
            metric.quarterSpeedTextWidth * Double(layout.rateMinimumTextScale),
            Double(layout.rateLabelWidth)
        )
    }

    func testQuarterSpeedFitsAccessibilityPolicyAtFullTextSize() throws {
        let records = accessibilityCategories.map(metrics)
        let layout = PlaybackSecondaryControlLayout.resolve(usesAccessibilityText: true)
        XCTAssertEqual(layout.rateMinimumTextScale, 1)
        try attach(records, name: "Speed-accessibility-font-budget")
        for metric in records {
            XCTAssertLessThanOrEqual(
                metric.quarterSpeedTextWidth, Double(layout.rateLabelWidth),
                "\(metric.category): 0.25× must fit without text shrinking"
            )
            XCTAssertLessThanOrEqual(metric.speedLineHeight, Double(layout.rateLabelMinimumHeight))
        }
    }

    func testEveryRegularTextCategoryFitsItsCurrentSecondaryPolicy() throws {
        let categories: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge
        ]
        let records = categories.map(metrics)
        let layout = PlaybackSecondaryControlLayout.resolve(usesAccessibilityText: false)
        try attach(records, name: "All-regular-font-budgets")
        for metric in records {
            XCTAssertLessThanOrEqual(metric.standardTextWidth, Double(layout.presetLabelWidth), metric.category)
            XCTAssertLessThanOrEqual(metric.presetStackLineHeight, Double(layout.presetLabelMinimumHeight), metric.category)
            XCTAssertLessThanOrEqual(
                metric.quarterSpeedTextWidth * Double(layout.rateMinimumTextScale),
                Double(layout.rateLabelWidth), metric.category
            )
        }
    }

    func testFontProbeMatchesCurrentPresetAndSpeedLabelConstraints() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("ReplayXI/Immersive/FootballImmersiveView.swift"),
            encoding: .utf8
        )
        let rateStart = try XCTUnwrap(source.range(of: "private func playbackRateChoice(")?.lowerBound)
        let presetStart = try XCTUnwrap(source.range(of: "private func controlDeckChoice(")?.lowerBound)
        let presetEnd = try XCTUnwrap(source.range(of: "private var annotationEditShelf:")?.lowerBound)
        let rate = source[rateStart..<presetStart]
        let preset = source[presetStart..<presetEnd]
        XCTAssertTrue(rate.contains(".font(.subheadline.monospacedDigit().weight(.black))"))
        XCTAssertTrue(rate.contains(".minimumScaleFactor(secondaryControlLayout.rateMinimumTextScale)"))
        XCTAssertTrue(rate.contains(".frame(width: secondaryControlLayout.rateLabelWidth)"))
        XCTAssertTrue(rate.contains(".frame(minHeight: secondaryControlLayout.rateLabelMinimumHeight)"))
        XCTAssertTrue(preset.contains("VStack(spacing: 1)"))
        XCTAssertTrue(preset.contains(".font(.headline.weight(.bold))"))
        XCTAssertTrue(preset.contains(".font(.caption2.monospaced().weight(.black))"))
        XCTAssertTrue(preset.contains(".frame(width: secondaryControlLayout.presetLabelWidth)"))
        XCTAssertTrue(preset.contains(".frame(minHeight: secondaryControlLayout.presetLabelMinimumHeight)"))
        XCTAssertFalse(preset.contains("minimumScaleFactor"))
    }

    func testSevenAccessibilityRatesHaveRoomInsideEveryExistingDeckPreset() {
        let controls = PlaybackSecondaryControlLayout.resolve(usesAccessibilityText: true)
        XCTAssertTrue(controls.usesAdaptiveRates)
        let count = CGFloat(ReplayStore.availablePlaybackRates.count)
        let requiredWidth = count * controls.rateGridMinimumCellWidth
            + max(0, count - 1) * PlaybackSecondaryControlLayout.rateGridSpacing
        for preset in PlaybackControlDeckPreset.allCases {
            let deck = PlaybackControlDeckLayout.resolve(preset: preset, usesAccessibilityText: true)
            // Existing outer deck padding: 2×(18+4); secondary shelf: 2×10.
            let availableWidth = deck.contentWidth - 44 - 20
            XCTAssertLessThanOrEqual(requiredWidth, availableWidth, "\(preset)")
        }
    }

    func testRegularWorkspaceRowHasRoomForWiderPresetLabels() {
        let categories: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge
        ]
        let layout = PlaybackSecondaryControlLayout.resolve(usesAccessibilityText: false)
        for category in categories {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
            let caption2 = UIFont.monospacedSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traits).pointSize,
                weight: .black
            )
            let buttonFont = UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).pointSize,
                weight: .semibold
            )
            let headingWidth = max(
                textWidth("WORKSPACE", font: caption2) + 9 * 1.4,
                textWidth("Fixed in the room", font: caption)
            )
            // Budget the native style at 48 pt per button, plus an icon line
            // box and label gap. This verifies allocation, not rendered pixels.
            let presetsWidth = 3 * (Double(layout.presetLabelWidth) + 48) + 2 * 6
            let recenterWidth = textWidth("Place controls here", font: buttonFont)
                + Double(buttonFont.lineHeight) + 8 + 48
            let requiredWidth = headingWidth + presetsWidth + recenterWidth + 3 * 16 + 8
            for preset in PlaybackControlDeckPreset.allCases {
                let deck = PlaybackControlDeckLayout.resolve(preset: preset, usesAccessibilityText: false)
                XCTAssertLessThanOrEqual(requiredWidth, Double(deck.contentWidth - 44 - 20), category.rawValue)
            }
        }
    }

    func testAdaptiveRatesStayInSecondaryShelvesAndBelowTheSettingsHeader() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("ReplayXI/Immersive/FootballImmersiveView.swift"),
            encoding: .utf8
        )
        let choicesStart = try XCTUnwrap(source.range(of: "private func playbackRateChoices(")?.lowerBound)
        let choicesEnd = try XCTUnwrap(source.range(of: "private func timelineStepChoice(")?.lowerBound)
        let choices = source[choicesStart..<choicesEnd]
        XCTAssertTrue(choices.contains("if secondaryControlLayout.usesAdaptiveRates"))
        XCTAssertTrue(choices.contains("LazyVGrid("))
        XCTAssertTrue(choices.contains(".adaptive(minimum: secondaryControlLayout.rateGridMinimumCellWidth)"))
        let settingsStart = try XCTUnwrap(source.range(of: "private var playbackSettingsShelf:")?.lowerBound)
        let settingsEnd = try XCTUnwrap(source.range(of: "private var speedShelfHeader:")?.lowerBound)
        let settings = source[settingsStart..<settingsEnd]
        XCTAssertTrue(settings.contains("timelineStepChoices\n                    }\n                    playbackRateChoices()"))
        let baseStart = try XCTUnwrap(source.range(of: "private var matchPlaybackDeck:")?.lowerBound)
        let baseEnd = try XCTUnwrap(source.range(of: "if isClearAnnotationsPending", range: baseStart..<source.endIndex)?.lowerBound)
        XCTAssertFalse(source[baseStart..<baseEnd].contains("playbackRateChoices"))
    }

    private struct Metrics: Encodable {
        let category: String
        let captionPointSize: Double
        let captionLineHeight: Double
        let headlineIconPointSize: Double
        let headlineIconLineHeight: Double
        let standardTextWidth: Double
        let presetStackLineHeight: Double
        let speedPointSize: Double
        let speedLineHeight: Double
        let quarterSpeedTextWidth: Double
        let legacyQuarterSpeedMinimumWidth: Double
    }

    private func metrics(for category: UIContentSizeCategory) -> Metrics {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let captionSize = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traits).pointSize
        let caption = UIFont.monospacedSystemFont(ofSize: captionSize, weight: .black)
        let headlineSize = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits).pointSize
        let headline = UIFont.systemFont(ofSize: headlineSize, weight: .bold)
        let speedSize = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).pointSize
        let speed = UIFont.monospacedDigitSystemFont(ofSize: speedSize, weight: .black)
        let quarterWidth = textWidth("0.25×", font: speed)
        return Metrics(
            category: category.rawValue,
            captionPointSize: Double(caption.pointSize),
            captionLineHeight: Double(caption.lineHeight),
            headlineIconPointSize: Double(headline.pointSize),
            headlineIconLineHeight: Double(headline.lineHeight),
            standardTextWidth: textWidth("STANDARD", font: caption),
            presetStackLineHeight: Double(headline.lineHeight + caption.lineHeight + 1),
            speedPointSize: Double(speed.pointSize),
            speedLineHeight: Double(speed.lineHeight),
            quarterSpeedTextWidth: quarterWidth,
            legacyQuarterSpeedMinimumWidth: quarterWidth * 0.8
        )
    }

    private func textWidth(_ text: String, font: UIFont) -> Double {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private func attach(_ records: [Metrics], name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(
            data: try encoder.encode(records), uniformTypeIdentifier: "public.json"
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
