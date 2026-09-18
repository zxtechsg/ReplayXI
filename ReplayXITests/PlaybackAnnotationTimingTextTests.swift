import CoreText
import UIKit
import XCTest
@testable import ReplayXI

/// Measures native text advances. This is not a rendered SwiftUI layout test.
@MainActor
final class PlaybackAnnotationTimingTextTests: XCTestCase {
    private let regular: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge
    ]
    private let accessibility: [UIContentSizeCategory] = [
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge
    ]

    func testEveryRegularDurationLabelFitsAtItsPermittedMinimumScale() throws {
        try checkText(regular, usesAccessibilityText: false)
    }

    func testAccessibilityDurationLabelsFitEvenAtTheirPermittedMinimumScale() throws {
        try checkText(accessibility, usesAccessibilityText: true)
    }

    func testAccessibilityChoicesPreserveRequestedTextSizeAndCanWrap() {
        let layout = PlaybackAnnotationTimingLayout.resolve(usesAccessibilityText: true)
        XCTAssertEqual(layout.minimumTextScale, 1, "Large-text users should not lose their requested text size")
        XCTAssertTrue(layout.usesAdaptiveChoices, "A secondary shelf can wrap rather than compress the choices")
        for preset in PlaybackControlDeckPreset.allCases {
            let deck = PlaybackControlDeckLayout.resolve(preset: preset, usesAccessibilityText: true)
            let availableWidth = deck.contentWidth - 44 - 20
            let fiveCells = 5 * layout.gridMinimumCellWidth + 4 * PlaybackAnnotationTimingLayout.gridSpacing
            XCTAssertLessThanOrEqual(fiveCells, availableWidth,
                                     "Every duration has a full-size cell inside \(preset); smaller surfaces can wrap")
        }
    }

    func testRegularDurationLabelBudgetsRemainCompact() {
        let layout = PlaybackAnnotationTimingLayout.resolve(usesAccessibilityText: false)
        XCTAssertFalse(layout.usesAdaptiveChoices)
        XCTAssertEqual(layout.timedLabelWidth, 66)
        XCTAssertEqual(layout.throughEndLabelWidth, 104)
        XCTAssertEqual(layout.labelMinimumHeight, 52)
        XCTAssertEqual(layout.minimumTextScale, 0.78)
    }

    func testTimingEditorUsesExactFieldsAndSharedWindowValidation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/AnnotationTimingEditor.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("CoachMarkTimingPolicy.windowFits"))
        XCTAssertTrue(source.contains("TextField(\"Seconds\""))
        XCTAssertTrue(source.contains(".disabled(!valid || !store.canChangePlaybackView)"))
        XCTAssertTrue(source.contains("store.setCoachMarkWindow"))
    }

    private func checkText(_ categories: [UIContentSizeCategory], usesAccessibilityText: Bool) throws {
        let layout = PlaybackAnnotationTimingLayout.resolve(usesAccessibilityText: usesAccessibilityText)
        var records: [[String: Any]] = []
        for category in categories {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let size = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).pointSize
            let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .black)
            for label in ["3s", "5s", "8s", "12s", "TO END"] {
                let attributed = NSAttributedString(string: label, attributes: [.font: font])
                let measuredWidth = CTLineGetTypographicBounds(
                    CTLineCreateWithAttributedString(attributed as CFAttributedString), nil, nil, nil
                )
                let neededWidth = measuredWidth * Double(layout.minimumTextScale)
                let neededHeight = Double(font.lineHeight * layout.minimumTextScale)
                let availableWidth = Double(layout.labelWidth(throughEnd: label == "TO END"))
                XCTAssertLessThanOrEqual(neededWidth, availableWidth, "\(category.rawValue): \(label)")
                XCTAssertLessThanOrEqual(neededHeight, Double(layout.labelMinimumHeight), "\(category.rawValue): \(label)")
                records.append(["category": category.rawValue, "label": label,
                                "pointSize": size, "textWidth": measuredWidth, "lineHeight": font.lineHeight,
                                "minimumScale": layout.minimumTextScale, "minimumWidth": neededWidth,
                                "availableWidth": availableWidth, "availableHeight": layout.labelMinimumHeight])
            }
        }
        let attachment = XCTAttachment(
            data: try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "AnnotationDuration-\(usesAccessibilityText ? "AX" : "regular")-font-budget.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
