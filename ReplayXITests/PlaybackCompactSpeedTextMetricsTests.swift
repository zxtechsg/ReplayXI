import CoreText
import UIKit
import XCTest
@testable import ReplayXI

/// The compact speed control shows only its useful numeric value. These are
/// native font budgets, not proof of SwiftUI compression or rendered padding.
@MainActor
final class PlaybackCompactSpeedTextMetricsTests: XCTestCase {
    private let categories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge
    ]

    func testEveryTextSizeHasNativeCompactSpeedMeasurements() throws {
        let records = categories.map(metrics)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(records), uniformTypeIdentifier: "public.json")
        attachment.name = "Compact-Speed-all-rates-and-Dynamic-Type-font-budgets"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(records.count, 12)
        for record in records {
            XCTAssertEqual(record.rates.map(\.rate), ReplayStore.availablePlaybackRates)
            XCTAssertGreaterThan(record.minimumStackHeight, 0)
        }
    }

    func testEveryRateFitsThePermittedMinimumWidth() {
        for record in categories.map(metrics) {
            for rate in record.rates {
                XCTAssertLessThanOrEqual(rate.minimumWidth, record.widthLimit,
                    "\(record.category): \(rate.title), at the allowed 0.8 scale")
            }
        }
    }

    func testTheSingleRateLineFitsThePermittedMinimumHeight() {
        for record in categories.map(metrics) {
            XCTAssertEqual(record.minimumStackHeight,
                record.rateLineHeight * record.minimumScale)
            XCTAssertLessThanOrEqual(record.minimumStackHeight, record.heightLimit, record.category)
        }
    }

    func testRegularSizesKeepOriginalBoundsAndFitThePermittedScale() {
        for category in categories where !category.isAccessibilityCategory {
            let record = metrics(for: category)
            XCTAssertEqual(record.widthLimit, 74)
            XCTAssertEqual(record.heightLimit, 80)
            XCTAssertEqual(record.minimumScale, 0.8)
            for rate in record.rates {
                XCTAssertLessThanOrEqual(rate.minimumWidth, record.widthLimit,
                    "\(record.category): \(rate.title)")
            }
            XCTAssertLessThanOrEqual(record.minimumStackHeight, record.heightLimit, record.category)
        }
    }

    func testProbeMatchesTheActualCompactSpeedFontScaleFrameAndAction() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let button = try slice(source, after: "private var compactSpeedControlButton:",
            before: "private func annotationEditButton(")
        XCTAssertTrue(button.contains("Text(rateLabel(store.playbackRate))"))
        XCTAssertTrue(button.contains(".font(.headline.monospacedDigit().weight(.bold))"))
        XCTAssertFalse(button.contains("Text(\"Speed\")"))
        XCTAssertFalse(button.contains("VStack(spacing: 1)"))
        XCTAssertTrue(button.contains(".spatialHelp(\"Playback speed · "))
        XCTAssertTrue(button.contains(".lineLimit(1)"))
        XCTAssertTrue(button.contains(".minimumScaleFactor(0.8)"))
        XCTAssertTrue(button.contains(".frame(width: primaryControlLayout.speedLabelWidth,"))
        XCTAssertTrue(button.contains("height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)"))
        XCTAssertTrue(button.contains("toggleInlinePanel(.playbackSpeed)"))
        XCTAssertTrue(button.contains(".disabled(rateControlsAreDisabled)"))
        XCTAssertTrue(button.contains(".accessibilityValue(rateLabel(store.playbackRate))"))
        let formatter = try slice(source, after: "private func rateLabel(_ rate: Double)",
            before: "private struct PerspectiveMatrixPanel:")
        XCTAssertTrue(formatter.contains("rate == rate.rounded()"))
        XCTAssertTrue(formatter.contains("Int(rate)"))
        XCTAssertTrue(formatter.contains(".number.precision(.fractionLength(0...2))"))
    }

    func testNarrowAXWidthPreservesTheNormalButtonAndEveryMainRowPreset() {
        let regular = PlaybackPrimaryControlLabelLayout.resolve(usesAccessibilityText: false)
        let accessible = PlaybackPrimaryControlLabelLayout.resolve(usesAccessibilityText: true)
        XCTAssertEqual(regular.speedLabelWidth, 74)
        XCTAssertEqual(accessible.speedLabelWidth, 80)
        let fixedTransport = 3 * PlaybackControlDeckPresentation.minimumSpatialHitTarget + 64
        let compactLabels = accessible.speedLabelWidth + accessible.playerLabelWidth
            + accessible.drawLabelWidth + accessible.toolsLabelWidth
        // Existing Loop 83 allocation: eight style reserves and row gaps,
        // plus the unchanged 230 pt minimum rail. Not rendered button padding.
        // The scrubber now has its own full-width row.
        let row = fixedTransport + compactLabels + 8 * 48 + 8 * 8
        for preset in PlaybackControlDeckPreset.allCases {
            let deck = PlaybackControlDeckLayout.resolve(preset: preset, usesAccessibilityText: true)
            XCTAssertLessThanOrEqual(row, deck.contentWidth - 44)
        }
    }

    private struct Metrics: Encodable {
        let category: String
        let rateFontPointSize: Double
        let rateLineHeight: Double
        let minimumScale: Double
        let fullStackHeight: Double
        let minimumStackHeight: Double
        let widthLimit: Double
        let heightLimit: Double
        let rates: [RateBudget]
    }

    private struct RateBudget: Encodable {
        let rate: Double
        let title: String
        let fullWidth: Double
        let minimumWidth: Double
    }

    private func metrics(for category: UIContentSizeCategory) -> Metrics {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let rateFont = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(
            forTextStyle: .headline, compatibleWith: traits).pointSize, weight: .bold)
        let minimumScale = 0.8
        let layout = PlaybackPrimaryControlLabelLayout.resolve(
            usesAccessibilityText: category.isAccessibilityCategory)
        let lineHeights = Double(rateFont.lineHeight)
        let rates = ReplayStore.availablePlaybackRates.map { rate in
            // Same formatter as the source-checked private view method; this
            // probe checks font budgets, not a replacement rendering path.
            let title = rate == rate.rounded()
                ? "\(Int(rate))×"
                : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
            let width = textWidth(title, font: rateFont)
            return RateBudget(rate: rate, title: title, fullWidth: width,
                minimumWidth: width * minimumScale)
        }
        return Metrics(category: category.rawValue,
            rateFontPointSize: Double(rateFont.pointSize), rateLineHeight: Double(rateFont.lineHeight),
            minimumScale: minimumScale,
            fullStackHeight: lineHeights, minimumStackHeight: lineHeights * minimumScale,
            widthLimit: Double(layout.speedLabelWidth),
            heightLimit: Double(PlaybackControlDeckPresentation.minimumSpatialHitTarget),
            rates: rates)
    }

    private func textWidth(_ text: String, font: UIFont) -> Double {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
            attributes: [.font: font]) as CFAttributedString)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
