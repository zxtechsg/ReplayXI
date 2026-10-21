import CoreText
import UIKit
import XCTest
@testable import ReplayXI

/// UIFont and configured SF-symbol size budgets, not a SwiftUI render. The
/// icon rows use minimum heights; width probes exclude native button padding.
@MainActor
final class PlaybackViewHUDTextMetricsTests: XCTestCase {
    private let categories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge
    ]

    func testEveryTextSizeHasNativeHeaderAndToolIconMeasurements() throws {
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
            XCTAssertEqual(record.expandedSymbols.count, 13)
            XCTAssertTrue(record.headerSymbols.allSatisfy { $0.width > 0 && $0.height > 0 })
            XCTAssertTrue(record.badgeSymbols.allSatisfy { $0.width > 0 && $0.height > 0 })
            XCTAssertTrue(record.expandedSymbols.allSatisfy { $0.width > 0 && $0.height > 0 })
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

    func testExpandedToolIconsFitTheirThreeColumnCellsAndHitTargetHeight() throws {
        for record in try categories.map(metrics) {
            for symbol in record.expandedSymbols {
                let context = "\(record.category): \(symbol.name)"
                XCTAssertLessThanOrEqual(symbol.width, symbol.widthLimit, context)
                XCTAssertLessThanOrEqual(symbol.height, symbol.heightLimit, context)
            }
        }
    }

    func testFullCollapsedHeaderFitsWithAllThreeBadgesAtEveryTextSize() throws {
        for category in categories {
            let record = try metrics(for: category)
            // Five header children in POV: view icon, POV text, badge row,
            // zero-minimum spacer, chevron. Other views omit the short text.
            let width = record.headerSymbols[0].widthLimit
                + record.povLabelWidth
                + 3 * record.badgeSymbols[0].widthLimit + 2 * 5
                + record.headerSymbols[3].widthLimit + 4 * 8
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
        let hud = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/PlaybackViewOverlayHUD.swift"), encoding: .utf8)
        let header = try slice(hud, after: "var body: some View", before: "if isExpanded {")
        XCTAssertTrue(header.contains(".font(.headline.weight(.black))"))
        XCTAssertTrue(header.contains(".font(.caption.weight(.black))"))
        XCTAssertTrue(header.contains(".frame(width: symbolLayout.modeIconWidth,"))
        XCTAssertTrue(header.contains(".frame(width: symbolLayout.disclosureIconWidth,"))
        XCTAssertEqual(header.components(separatedBy:
            "height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)").count - 1, 2)
        XCTAssertTrue(header.contains("Text(\"POV\")"))
        XCTAssertFalse(header.contains("Eyebrow(text: \"View & Overlays\""))
        XCTAssertFalse(header.contains("Text(store.viewMode.title)"))
        XCTAssertEqual(hud.components(separatedBy:
            ".fixedSize(horizontal: !isExpanded, vertical: false)").count - 1, 2,
            "Both glass and screenshot paths must hug collapsed icon controls.")
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
        XCTAssertTrue(camera.contains("Image(systemName: mode.systemImage)"))
        XCTAssertTrue(camera.contains(".font(.title3.weight(.bold))"))
        XCTAssertFalse(camera.contains("Text("))
        XCTAssertTrue(camera.contains("minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget"))
        let overlay = try slice(hud, after: "private func overlayChoice(", before: "\n}")
        XCTAssertTrue(overlay.contains("Image(systemName: systemImage)"))
        XCTAssertTrue(overlay.contains(".font(.title3.weight(.bold))"))
        let overlayButtonLabel = try slice(overlay, after: "return Button(action: action) {",
            before: ".buttonStyle(.borderedProminent)")
        XCTAssertFalse(overlayButtonLabel.contains("Label("))
        XCTAssertFalse(overlay.contains("minimumScaleFactor"))
        XCTAssertTrue(overlay.contains("minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget"))
        XCTAssertTrue(hud.contains("Stadium: hides passthrough. Stay seated or planted"))
        XCTAssertTrue(hud.contains("Surface pitch fixed. Reset its surface placement"))
        let shelf = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/PlaybackViewShelf.swift"), encoding: .utf8)
        XCTAssertTrue(shelf.contains("Image(systemName: section.systemImage)"))
        XCTAssertTrue(shelf.contains(".frame(maxWidth: .infinity, minHeight: 60)"))
        XCTAssertFalse(shelf.contains("Text(section.title)"))
        XCTAssertTrue(shelf.contains(".accessibilityLabel(\"\\(section.title) controls\")"))
        XCTAssertTrue(hud.contains(".padding(11)"))
    }

    private struct Metrics: Encodable {
        let category: String
        let innerWidth: Double
        let headerSymbols: [SymbolBudget]
        let badgeSymbols: [SymbolBudget]
        let expandedSymbols: [SymbolBudget]
        let povLabelWidth: Double
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
        let pov = font(.caption1, weight: .bold)
        let tool = font(.title3, weight: .bold)
        let shelf = font(.title3, weight: .semibold)
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
        let cellWidth = (Double(layout.attachmentWidth) - 22 - 2 * 6) / 3
        let targetHeight = Double(PlaybackControlDeckPresentation.minimumSpatialHitTarget)
        let toolSymbols = try (viewModes.map(\.systemImage) + PlaybackOverlayBadge.allCases.map(\.systemImage))
            .map { try symbol($0, font: tool, width: cellWidth, height: targetHeight) }
        let shelfSymbols = try (PlaybackViewShelf.allCases.map(\.systemImage)
            + ReplayEnvironmentMode.allCases.map(\.systemImage) + ["sportscourt", "viewfinder"])
            .map { try symbol($0, font: shelf, width: cellWidth, height: targetHeight) }
        return Metrics(
            category: category.rawValue, innerWidth: Double(layout.attachmentWidth) - 22,
            headerSymbols: modes + chevrons, badgeSymbols: badges,
            expandedSymbols: toolSymbols + shelfSymbols,
            povLabelWidth: textWidth("POV", font: pov)
        )
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
