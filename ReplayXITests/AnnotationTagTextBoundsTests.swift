import RealityKit
import XCTest
@testable import ReplayXI

/// Actual native 3D mesh bounds, not a screenshot or headset-legibility test.
@MainActor
final class AnnotationTagTextBoundsTests: XCTestCase {
    func testCommonFootballLabelsRemainInsideTheirCards() throws {
        try checkTags([
            "RUN · OVERLAP RIGHT", "PASS · SWITCH PLAY", "ATTACK THE WEAK SIDE",
            "HOLD THE LINE", "THIRD-MAN RUN", "#11 · STAY WIDE"
        ], attachmentName: "common")
    }

    func testWideCompactLabelsStayInsideTheirCards() throws {
        try checkTags([
            String(repeating: "W", count: 22), String(repeating: "M", count: 22),
            "RUN · " + String(repeating: "W", count: 16),
            "PASS · " + String(repeating: "W", count: 15)
        ], attachmentName: "wide")
    }

    func testUppercaseExpansionCannotEscapeTheCard() throws {
        // A coach's legal 22-character label can expand when uppercased.
        try checkTags([String(repeating: "ß", count: 22), "Straße · Wechsel links"],
                      attachmentName: "uppercase-expansion")
    }

    func testSceneCompactionStillProducesContainedSelectableCards() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for kind in [CoachMarkKind.run, .pass, .space] {
            let mark = CoachMark(kind: kind, start: .init(x: 18, z: 8), end: .init(x: 24, z: 18),
                                 label: String(repeating: "W", count: 96), revealTime: 0)
            PitchSceneFactory.update(
                root: root, scenario: scenario, time: 1, viewMode: .tacticalTable,
                perspectiveID: scenario.defaultPerspectiveID, marks: [mark],
                showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil
            )
            let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
            let label = try XCTUnwrap(markRoot.findEntity(named: "annotation-label"))
            try assertContained(label, context: kind.rawValue)
            let target = try XCTUnwrap(label.findEntity(named: AnnotationSceneAffordance.labelTargetName))
            XCTAssertNotNil(target.components[InputTargetComponent.self])
            XCTAssertNotNil(target.components[CollisionComponent.self])
            XCTAssertEqual(AnnotationSceneAffordance.targetAncestor(of: target),
                           AnnotationSceneTarget(markID: mark.id, role: .body))
        }
    }

    func testMeasuredCardWidthAlsoSizesItsHitBoxAndSelectionOutline() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for text in [String(repeating: "W", count: 22), String(repeating: "ß", count: 22)] {
            let mark = CoachMark(kind: .space, start: .init(x: 18, z: 8), end: .init(x: 24, z: 18),
                                 label: text, revealTime: 0)
            func update(_ time: Double) {
                PitchSceneFactory.update(
                    root: root, scenario: scenario, time: time, viewMode: .tacticalTable,
                    perspectiveID: scenario.defaultPerspectiveID, marks: [mark],
                    selectedAnnotationID: mark.id, selectedAnnotationIsEditable: true,
                    showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil
                )
            }
            update(1)
            let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
            let label = try XCTUnwrap(markRoot.findEntity(named: "annotation-label"))
            let (board, _) = try bounds(in: label)
            let width = PlaybackSpatialLabels.annotationBoardWidth(in: label, renderedCharacterCount: text.count)
            XCTAssertEqual(width, board.extents.x, accuracy: 0.00001)
            XCTAssertLessThanOrEqual(width, 3.20)
            let target = try XCTUnwrap(label.findEntity(named: AnnotationSceneAffordance.labelTargetName))
            let shape = try XCTUnwrap(target.components[CollisionComponent.self]?.shapes.first)
            XCTAssertEqual(shape.bounds.extents.x, width + 0.30, accuracy: 0.00001)
            let outline = try XCTUnwrap(root.findEntity(named: "annotation-selection-label-outline"))
            XCTAssertTrue(outline.isEnabledInHierarchy)
            XCTAssertEqual(outline.visualBounds(relativeTo: label).extents.x, width + 0.14, accuracy: 0.0001)

            update(3)
            XCTAssertTrue(markRoot.findEntity(named: "annotation-label") === label,
                          "Time-only scene updates reuse the measured card")
            XCTAssertEqual(PlaybackSpatialLabels.annotationBoardWidth(in: label, renderedCharacterCount: 0), width)
        }
    }

    func testWideAsciiKeepsItsFontWhileExpansionUsesABoundedUniformScale() throws {
        let wide = PlaybackSpatialLabels.makeAnnotationTag(text: String(repeating: "W", count: 22), color: .white)
        let wideGlyph = try XCTUnwrap(wide.findEntity(named: "annotation-tag-glyph"))
        XCTAssertEqual(wideGlyph.scale, SIMD3<Float>(repeating: 1))
        let expanded = PlaybackSpatialLabels.makeAnnotationTag(text: String(repeating: "ß", count: 22), color: .white)
        let expandedGlyph = try XCTUnwrap(expanded.findEntity(named: "annotation-tag-glyph"))
        XCTAssertGreaterThan(expandedGlyph.scale.x, 0)
        XCTAssertLessThan(expandedGlyph.scale.x, 1)
        XCTAssertEqual(expandedGlyph.scale.x, expandedGlyph.scale.y)
        XCTAssertEqual(expandedGlyph.scale.y, expandedGlyph.scale.z)
        XCTAssertEqual(PlaybackSpatialLabels.annotationBoardWidth(in: expanded, renderedCharacterCount: 22), 3.20)
    }

    private func checkTags(_ labels: [String], attachmentName: String) throws {
        var records: [[String: Any]] = []
        for text in labels {
            let root = PlaybackSpatialLabels.makeAnnotationTag(text: text, color: .white)
            let (board, glyph) = try bounds(in: root)
            records.append([
                "text": text, "characterCount": text.count, "uppercaseCount": text.uppercased().count,
                "boardWidth": board.extents.x, "glyphWidth": glyph.extents.x,
                "leftInset": glyph.min.x - board.min.x, "rightInset": board.max.x - glyph.max.x,
                "glyphHeight": glyph.extents.y,
            ])
            try assertContained(root, context: text)
        }
        let attachment = XCTAttachment(
            data: try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "AnnotationTag84-\(attachmentName).json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertContained(_ root: Entity, context: String,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let (board, glyph) = try bounds(in: root)
        // The left inset clears the existing accent stripe; the right and
        // vertical insets leave a small readable edge around the glyphs.
        XCTAssertGreaterThanOrEqual(glyph.min.x, board.min.x + 0.12 - 0.0001, context, file: file, line: line)
        XCTAssertLessThanOrEqual(glyph.max.x, board.max.x - 0.08 + 0.0001, context, file: file, line: line)
        XCTAssertGreaterThanOrEqual(glyph.min.y, board.min.y + 0.04 - 0.0001, context, file: file, line: line)
        XCTAssertLessThanOrEqual(glyph.max.y, board.max.y - 0.04 + 0.0001, context, file: file, line: line)
    }

    private func bounds(in root: Entity) throws -> (BoundingBox, BoundingBox) {
        let board = try XCTUnwrap(root.findEntity(named: "annotation-tag-board"))
        let glyph = try XCTUnwrap(root.findEntity(named: "annotation-tag-glyph"))
        return (board.visualBounds(relativeTo: root), glyph.visualBounds(relativeTo: root))
    }
}
