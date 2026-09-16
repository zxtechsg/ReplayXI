import CoreText
import UIKit
import XCTest
@testable import ReplayXI

/// UIFont and configured SF-symbol size budgets, not a SwiftUI render. The
/// expanded rows use minimum heights, so larger line heights are not failures.
/// Row width probes exclude native button padding and Label's implicit gap.
@MainActor
final class PlaybackViewHUDTextMetricsTests: XCTestCase {
    private let categories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge
    ]

    func testEveryTextSizeHasNativeHeaderAndOverlayMeasurements() throws {
        let records = try categories.map(metrics)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(records), uniformTypeIdentifier: "public.json")
        attachment.name = "View-HUD-all-Dynamic-Type-font-and-symbol-budgets"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(records.count, 12)
        for record in records {
            XCTAssertEqual(record.headerSymbols.count, 5)
            XCTAssertEqual(record.badgeSymbols.count, 3)
            XCTAssertTrue(record.headerSymbols.allSatisfy { $0.width > 0 && $0.height > 0 })
            XCTAssertTrue(record.badgeSymbols.allSatisfy { $0.width > 0 && $0.height > 0 })
        }
    }

    func testCollapsedHeaderSymbolsFitTheirLiveFrames() throws {
        for record in try categories.map(metrics) {
            for symbol in record.headerSymbols {
                let context = "\(record.category): \(symbol.name)"
                XCTAssertLessThanOrEqual(symbol.width, symbol.widthLimit, context)
                XCTAssertLessThanOrEqual(symbol.height, symbol.heightLimit, context)
            }
        }
    }

    func testOverlayBadgeSymbolsFitTheirLiveCircles() throws {
        for record in try categories.map(metrics) {
            for symbol in record.badgeSymbols {
                let context = "\(record.category): \(symbol.name)"
                XCTAssertLessThanOrEqual(symbol.width, symbol.widthLimit, context)
                XCTAssertLessThanOrEqual(symbol.height, symbol.heightLimit, context)
            }
        }
    }

    func testExpandedRowsDoNotExceedEvenTheirUnpaddedWidthBudget() throws {
        for record in try categories.map(metrics) {
            XCTAssertLessThanOrEqual(record.cameraMinimumTextRowWidth,
                record.innerWidth, record.category)
            XCTAssertLessThanOrEqual(record.overlayMinimumContentRowWidth,
                record.innerWidth, record.category)
        }
    }

    func testFullCollapsedHeaderFitsWithAllThreeBadgesAtEveryTextSize() throws {
        for category in categories {
            let record = try metrics(for: category)
            // Exact plain-header frames, four 10 pt gaps, two 5 pt badge
            // gaps and the existing 4 pt minimum spacer. No styled buttons.
            let width = record.headerSymbols[0].widthLimit
                + max(record.maximumModeTitleWidth, record.eyebrowUnwrappedWidth)
                + 3 * record.badgeSymbols[0].widthLimit + 2 * 5
                + record.headerSymbols[3].widthLimit + 4 * 10 + 4
            for preset in PlaybackControlDeckPreset.allCases {
                let layout = PlaybackViewHUDLayout.resolve(preset: preset,
                    usesAccessibilityText: category.isAccessibilityCategory)
                XCTAssertLessThanOrEqual(width, Double(layout.attachmentWidth) - 22,
                    "\(record.category): \(preset)")
            }
        }
    }

    func testProbeMatchesTheLiveHUDFontsAndImageFramePolicy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let hud = try slice(source, after: "private struct PlaybackViewOverlayHUD:",
            before: "private struct ImmersiveControlDeck:")
        let header = try slice(hud, after: "var body: some View", before: "if isExpanded {")
        XCTAssertTrue(header.contains(".font(.headline.weight(.black))"))
        XCTAssertTrue(header.contains(".font(.caption.weight(.black))"))
        XCTAssertTrue(header.contains(".frame(width: symbolLayout.modeIconWidth,"))
        XCTAssertTrue(header.contains(".frame(width: symbolLayout.disclosureIconWidth,"))
        XCTAssertEqual(header.components(separatedBy:
            "height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)").count - 1, 2)
        let badge = try slice(hud, after: "private func compactOverlayBadge(",
            before: "private func compactOverlayBadgeColor(")
        XCTAssertTrue(badge.contains(".font(.caption.weight(.black))"))
        XCTAssertTrue(badge.contains(
            ".frame(width: symbolLayout.overlayBadgeDiameter, height: symbolLayout.overlayBadgeDiameter)"))
        XCTAssertTrue(badge.contains("in: Circle()"))
        XCTAssertTrue(hud.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        XCTAssertTrue(hud.contains(
            "PlaybackViewHUDSymbolLayout.resolve(usesAccessibilityText: dynamicTypeSize.isAccessibilitySize)"))
        let camera = try slice(hud, after: "private func viewChoice(", before: "private func overlayChoice(")
        XCTAssertTrue(hud.contains("[.firstPerson, .tacticalTable, .touchline]"))
        XCTAssertTrue(camera.contains(".font(.subheadline.weight(.bold))"))
        XCTAssertTrue(camera.contains(".minimumScaleFactor(0.72)"))
        XCTAssertTrue(camera.contains("minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget"))
        let overlay = try slice(hud, after: "private func overlayChoice(", before: "private func shortViewTitle(")
        XCTAssertTrue(overlay.contains(".font(.caption.weight(.black))"))
        XCTAssertTrue(overlay.contains(".lineLimit(1)"))
        XCTAssertFalse(overlay.contains("minimumScaleFactor"))
        XCTAssertTrue(overlay.contains("minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget"))
        XCTAssertTrue(hud.contains(".padding(11)"))
    }

    private struct Metrics: Encodable {
        let category: String
        let innerWidth: Double
        let headerSymbols: [SymbolBudget]
        let badgeSymbols: [SymbolBudget]
        let maximumModeTitleWidth: Double
        let eyebrowUnwrappedWidth: Double
        let cameraMinimumTextRowWidth: Double
        let overlayMinimumContentRowWidth: Double
        let overlayCaptionLineHeight: Double
    }

    private struct SymbolBudget: Encodable {
        let name: String
        let width: Double
        let height: Double
        let widthLimit: Double
        let heightLimit: Double
    }

    private func metrics(for category: UIContentSizeCategory) throws -> Metrics {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        func font(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
            UIFont.systemFont(ofSize: UIFont.preferredFont(
                forTextStyle: style, compatibleWith: traits).pointSize, weight: weight)
        }
        let headline = font(.headline, weight: .black)
        let caption = font(.caption1, weight: .black)
        let camera = font(.subheadline, weight: .bold)
        let modeTitle = font(.subheadline, weight: .black)
        let eyebrow = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(
            forTextStyle: .caption2, compatibleWith: traits).pointSize, weight: .black)
        let layout = PlaybackViewHUDLayout.resolve(preset: .standard,
            usesAccessibilityText: category.isAccessibilityCategory)
        let symbolLayout = PlaybackViewHUDSymbolLayout.resolve(
            usesAccessibilityText: category.isAccessibilityCategory)
        func symbol(_ name: String, font: UIFont, width: Double, height: Double) throws -> SymbolBudget {
            let image = try XCTUnwrap(UIImage(systemName: name,
                withConfiguration: UIImage.SymbolConfiguration(font: font)))
            return SymbolBudget(name: name, width: Double(image.size.width),
                height: Double(image.size.height), widthLimit: width, heightLimit: height)
        }
        // Shape's positional view has no View HUD attachment.
        let viewModes: [ReplayViewMode] = [.firstPerson, .tacticalTable, .touchline]
        let modes = try viewModes.map {
            try symbol($0.systemImage, font: headline, width: Double(symbolLayout.modeIconWidth),
                height: Double(PlaybackControlDeckPresentation.minimumSpatialHitTarget))
        }
        let chevrons = try ["chevron.up", "chevron.down"].map {
            try symbol($0, font: caption, width: Double(symbolLayout.disclosureIconWidth),
                height: Double(PlaybackControlDeckPresentation.minimumSpatialHitTarget))
        }
        let badges = try PlaybackOverlayBadge.allCases.map {
            try symbol($0.systemImage, font: caption, width: Double(symbolLayout.overlayBadgeDiameter),
                height: Double(symbolLayout.overlayBadgeDiameter))
        }
        let offSymbol = try symbol("eye.slash", font: caption,
            width: Double(symbolLayout.overlayBadgeDiameter), height: Double(symbolLayout.overlayBadgeDiameter))
        let overlayTitles = ["Marks", "Ball glow", "Lanes"]
        let overlayWidth = zip(overlayTitles, badges).reduce(12.0) { sum, item in
            sum + textWidth(item.0, font: caption) + max(item.1.width, offSymbol.width)
        }
        return Metrics(
            category: category.rawValue, innerWidth: Double(layout.attachmentWidth) - 22,
            headerSymbols: modes + chevrons, badgeSymbols: badges,
            maximumModeTitleWidth: viewModes.map { textWidth($0.title, font: modeTitle) }.max() ?? 0,
            eyebrowUnwrappedWidth: textWidth("VIEW & OVERLAYS", font: eyebrow, tracking: 1.4),
            cameraMinimumTextRowWidth: ["POV", "Tactical", "Touchline"].reduce(12.0) {
                $0 + textWidth($1, font: camera) * 0.72
            },
            overlayMinimumContentRowWidth: overlayWidth,
            overlayCaptionLineHeight: Double(caption.lineHeight)
        )
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
