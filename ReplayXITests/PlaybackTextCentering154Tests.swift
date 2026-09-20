import Foundation
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackTextCentering154Tests: XCTestCase {
    func testAllFiveRostersKeepExactNativeGlyphPlacementAndTagContracts() throws {
        XCTAssertEqual(FootballReferenceScenarios.all.count, 5)
        PlaybackSpatialLabels.resetTextCenteringWorkForTesting()
        for scenario in FootballReferenceScenarios.all {
            let root = PlaybackSpatialLabels.makePlayerLabels(for: scenario)
            XCTAssertEqual(root.name, "player-labels-root")
            XCTAssertEqual(root.children.count, scenario.players.count)
            XCTAssertEqual(Set(scenario.players.map(\.team)), Set([FootballTeam.home, .away]))
            for player in scenario.players {
                let tag = try XCTUnwrap(root.findEntity(named: "player-label-\(player.id)"))
                XCTAssertEqual(Set(tag.children.map(\.name)),
                    Set(["selected-outline", "label-board", "team-strip", "label-glyph", "compact-label-glyph"]))
                XCTAssertEqual(tag.transform, .identity)
                XCTAssertNotNil(tag.components[InputTargetComponent.self])
                XCTAssertNotNil(tag.components[HoverEffectComponent.self])
                let accessibility = try XCTUnwrap(tag.components[AccessibilityComponent.self])
                XCTAssertFalse(accessibility.isAccessibilityElement)
                let collision = try XCTUnwrap(tag.components[CollisionComponent.self])
                XCTAssertEqual(collision.shapes.count, 1)
                let extent = try XCTUnwrap(collision.shapes.first).bounds.extents
                XCTAssertEqual(extent.x, 1.02, accuracy: 0.000001)
                XCTAssertEqual(extent.y, 0.40, accuracy: 0.000001)
                XCTAssertEqual(extent.z, 0.10, accuracy: 0.000001)
                let full = try model("label-glyph", in: tag)
                let compact = try model("compact-label-glyph", in: tag)
                try assertCentered(full, expectedScale: 1, z: 0.025)
                try assertCentered(compact, expectedScale: 1, z: 0.026)
                XCTAssertTrue(full.isEnabled)
                XCTAssertFalse(compact.isEnabled)
                XCTAssertFalse(try XCTUnwrap(tag.findEntity(named: "selected-outline")).isEnabled)
                XCTAssertEqual(try model("team-strip", in: tag).position, [-0.405, 0, 0.025])
            }
            for child in Array(root.children) { child.removeFromParent() }
        }
        let work = PlaybackSpatialLabels.textCenteringWork
        XCTAssertEqual(work.cacheHits + work.cacheMisses,
                       FootballReferenceScenarios.all.reduce(0) { $0 + 2 * $1.players.count })
        XCTAssertEqual(work.nativeCenteringBoundsQueries, work.cacheMisses)
        XCTAssertLessThanOrEqual(PlaybackSpatialLabels.cachedTextMeshCount,
                                 PlaybackSpatialLabels.maximumCachedTextMeshes)
    }

    func testImmediateFullSquadRepeatAvoidsAll44CenteringQueries() throws {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first)
        XCTAssertEqual(scenario.players.count, 22)
        let first = PlaybackSpatialLabels.makePlayerLabels(for: scenario)
        PlaybackSpatialLabels.resetTextCenteringWorkForTesting()
        let repeated = PlaybackSpatialLabels.makePlayerLabels(for: scenario)
        let work = PlaybackSpatialLabels.textCenteringWork
        XCTAssertEqual(work.cacheHits, 44)
        XCTAssertEqual(work.cacheMisses, 0)
        XCTAssertEqual(work.nativeCenteringBoundsQueries, 0)
        for player in scenario.players {
            let previous = try XCTUnwrap(first.findEntity(named: "player-label-\(player.id)"))
            let current = try XCTUnwrap(repeated.findEntity(named: "player-label-\(player.id)"))
            XCTAssertFalse(previous === current)
            for name in ["label-glyph", "compact-label-glyph"] {
                let a = try model(name, in: previous), b = try model(name, in: current)
                XCTAssertFalse(a === b)
                XCTAssertEqual(a.transform, b.transform)
                XCTAssertTrue(try XCTUnwrap(a.model).mesh === XCTUnwrap(b.model).mesh)
                try assertCentered(b, expectedScale: 1, z: name == "label-glyph" ? 0.025 : 0.026)
            }
        }
        let attachment = XCTAttachment(data: try JSONEncoder().encode(work), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-TextCentering154-WarmSquadCalls.json"
        attachment.lifetime = .keepAlways; add(attachment)
        for root in [first, repeated] {
            for child in Array(root.children) { child.removeFromParent() }
        }
    }

    func testExisting64EntryLRUEvictsOffsetsWithMeshesAndRetainsRecentlyUsedKeys() throws {
        let prefix = "CENTER154-\(UUID().uuidString)-"
        let limit = PlaybackSpatialLabels.maximumCachedTextMeshes
        XCTAssertEqual(limit, 64)
        let oldest = PlaybackSpatialLabels.makeAnnotationTag(text: prefix + "0", color: .white)
        let oldestPosition = try model("annotation-tag-glyph", in: oldest).position
        for index in 1..<limit {
            let tag = PlaybackSpatialLabels.makeAnnotationTag(text: prefix + String(index), color: .white)
            try assertAnnotation(tag, text: prefix + String(index))
            XCTAssertLessThanOrEqual(PlaybackSpatialLabels.cachedTextMeshCount, limit)
        }
        PlaybackSpatialLabels.resetTextCenteringWorkForTesting()
        // Refresh zero before adding the 65th key: one, not zero, must leave.
        let hot = PlaybackSpatialLabels.makeAnnotationTag(text: prefix + "0", color: .cyan)
        XCTAssertEqual(try model("annotation-tag-glyph", in: hot).position, oldestPosition)
        _ = PlaybackSpatialLabels.makeAnnotationTag(text: prefix + String(limit), color: .white)
        _ = PlaybackSpatialLabels.makeAnnotationTag(text: prefix + "0", color: .white)
        let revisited = PlaybackSpatialLabels.makeAnnotationTag(text: prefix + "1", color: .white)
        try assertAnnotation(revisited, text: prefix + "1")
        let work = PlaybackSpatialLabels.textCenteringWork
        XCTAssertEqual(work.cacheHits, 2)
        XCTAssertEqual(work.cacheMisses, 2)
        XCTAssertEqual(work.nativeCenteringBoundsQueries, 2)
        XCTAssertEqual(PlaybackSpatialLabels.cachedTextMeshCount, limit)
    }

    func testEmptyWideAndUppercaseExpandedAnnotationHelpersKeepExactCenteringAndSizing() throws {
        // Empty text is accepted by this rendering helper, although coach-mark
        // authoring rejects empty labels. Do not change either contract here.
        for text in ["", " ", "RUN · OVERLAP", String(repeating: "W", count: 22), String(repeating: "ß", count: 22)] {
            let first = PlaybackSpatialLabels.makeAnnotationTag(text: text, color: .red)
            PlaybackSpatialLabels.resetTextCenteringWorkForTesting()
            let repeated = PlaybackSpatialLabels.makeAnnotationTag(text: text, color: .blue)
            XCTAssertEqual(PlaybackSpatialLabels.textCenteringWork.cacheHits, 1)
            XCTAssertEqual(PlaybackSpatialLabels.textCenteringWork.cacheMisses, 0)
            XCTAssertEqual(PlaybackSpatialLabels.textCenteringWork.nativeCenteringBoundsQueries, 0)
            try assertAnnotation(first, text: text)
            try assertAnnotation(repeated, text: text)
            XCTAssertEqual(try model("annotation-tag-glyph", in: first).transform,
                           try model("annotation-tag-glyph", in: repeated).transform)
            let accent = try XCTUnwrap(try model("annotation-tag-accent", in: repeated).model?.materials.first as? UnlitMaterial)
            assertRGBA(accent.color.tint, equals: .blue)
        }
    }

    private func model(_ name: String, in root: Entity) throws -> ModelEntity {
        try XCTUnwrap(root.findEntity(named: name) as? ModelEntity)
    }

    /// Fresh unparented native measurement, independent of the cached offset.
    private func boundsOracle(_ glyph: ModelEntity) throws -> BoundingBox {
        let model = try XCTUnwrap(glyph.model)
        let fresh = ModelEntity(mesh: model.mesh, materials: model.materials)
        return fresh.visualBounds(relativeTo: fresh)
    }

    private func assertCentered(_ glyph: ModelEntity, expectedScale: Float, z: Float,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let bounds = try boundsOracle(glyph)
        XCTAssertEqual(glyph.position, [-bounds.center.x * expectedScale, -bounds.center.y * expectedScale, z],
                       file: file, line: line)
        XCTAssertEqual(glyph.scale, SIMD3<Float>(repeating: expectedScale), file: file, line: line)
        XCTAssertEqual(glyph.orientation.vector, SIMD4<Float>(0, 0, 0, 1), file: file, line: line)
        let material = try XCTUnwrap(glyph.model?.materials.first as? UnlitMaterial, file: file, line: line)
        assertRGBA(material.color.tint, equals: .white, file: file, line: line)
        XCTAssertFalse(material.program.descriptor.applyPostProcessToneMap, file: file, line: line)
    }

    /// RealityKit may return an RGB wrapper for UIKit's grayscale white or
    /// named blue. Compare successfully converted colour values, not wrappers.
    private func assertRGBA(_ actual: UIColor, equals expected: UIColor,
                            file: StaticString = #filePath, line: UInt = #line) {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        guard actual.getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea) else {
            XCTFail("Both material colours must convert to RGBA", file: file, line: line)
            return
        }
        for (value, reference) in zip([ar, ag, ab, aa], [er, eg, eb, ea]) {
            XCTAssertTrue(value.isFinite && reference.isFinite, file: file, line: line)
            XCTAssertEqual(value, reference, accuracy: 0.000001, file: file, line: line)
        }
    }

    private func assertAnnotation(_ root: Entity, text: String,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(Set(root.children.map(\.name)),
            Set(["annotation-tag-board", "annotation-tag-accent", "annotation-tag-glyph"]), file: file, line: line)
        let glyph = try model("annotation-tag-glyph", in: root)
        let bounds = try boundsOracle(glyph)
        let padding: Float = 0.24
        let estimate = min(max(Float(text.count) * 0.088, 1.18), 3.20)
        let width = min(max(estimate, bounds.extents.x + padding), 3.20)
        let scale = min(Float(1), (width - padding) / max(bounds.extents.x, 0.000001),
                        0.24 / max(bounds.extents.y, 0.000001))
        try assertCentered(glyph, expectedScale: scale, z: 0.025, file: file, line: line)
        XCTAssertEqual(try model("annotation-tag-board", in: root).scale.x, width / 1.18, file: file, line: line)
        XCTAssertEqual(try model("annotation-tag-accent", in: root).position,
                       [-(width / 2) + 0.065, 0, 0.025], file: file, line: line)
        XCTAssertEqual(PlaybackSpatialLabels.annotationBoardWidth(in: root, renderedCharacterCount: text.count),
                       width, file: file, line: line)
    }
}
