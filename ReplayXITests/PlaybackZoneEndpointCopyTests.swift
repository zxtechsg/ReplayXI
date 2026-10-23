import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackZoneEndpointCopyTests: XCTestCase {
    func testZoneJoysticksNameTheCentreAndEdgeOfTheActualCircle() throws {
        let source = try deckSource()
        let shelf = try slice(source, after: "private func annotationGeometryShelf(",
                              before: "private func annotationElevationControls(")
        XCTAssertTrue(shelf.contains("title: annotationStartPointTitle(for: mark.kind)"))
        XCTAssertTrue(shelf.contains("accessibilityTarget: annotationStartPointAccessibilityTarget(for: mark.kind)"))
        XCTAssertTrue(source.contains("kind == .space ? \"CENTRE\" : \"START\""))
        XCTAssertTrue(source.contains("kind == .space ? \"zone centre\" : \"start point\""))
        let endTitle = try slice(source, after: "private func annotationEndPointTitle(",
                                 before: "private func annotationJoystickIsEnabled(")
        XCTAssertTrue(endTitle.contains("case .space: \"EDGE\""))
        XCTAssertTrue(endTitle.contains("case .run, .pass, .arc, .danger: \"ARROW TIP\""))
        XCTAssertTrue(endTitle.contains("case .playerLabel: \"PLAYER\""))
        let endTarget = try slice(source, after: "private func annotationEndPointAccessibilityTarget(",
                                  before: "private func annotationLabelShelf(")
        XCTAssertTrue(endTarget.contains("kind == .space ? \"zone edge\" : \"arrow point\""))
        XCTAssertFalse(endTarget.contains("opposite corner"))
    }

    func testActiveJoystickActionsAndMovementFeedbackUseTheSameKindAwareNames() throws {
        let source = try deckSource()
        let actions = try slice(source, after: "private func annotationEndpointGeometryRow(",
                                before: "private func annotationElevationControls(")
        XCTAssertTrue(actions.contains("nudgeAnnotation(mark, endpoint: .start, x: x, z: z)"))
        XCTAssertTrue(actions.contains("nudgeAnnotation(mark, endpoint: .end, x: x, z: z)"))
        XCTAssertTrue(actions.contains("accessibilityTarget: annotationStartPointAccessibilityTarget(for: mark.kind)"))
        XCTAssertTrue(actions.contains("accessibilityTarget: annotationEndPointAccessibilityTarget(for: mark.kind)"))
        XCTAssertTrue(source.contains("case .start: kind == .space ? \"zone centre\" : \"start\""))
        XCTAssertTrue(source.contains("case .end: kind == .space ? \"zone edge\" : \"arrow point\""))
        let nudge = try slice(source, after: "private func nudgeAnnotation(",
                              before: "private func nudgeAnnotationElevation(")
        let commit = try slice(source, after: "private func commitAnnotationPreview(",
                               before: "private func isCoachCreated(")
        for callback in [nudge, commit] {
            XCTAssertTrue(callback.contains("annotationMovementTargetName(endpoint, kind: mark.kind).uppercased()"))
            XCTAssertTrue(callback.contains("hypot(appliedDelta.x, appliedDelta.z)"))
            XCTAssertTrue(callback.contains("return appliedDelta"))
        }
    }

    func testZoneEdgeChangesTheCircularRadiusAndUndoRestoresTheSameSceneRing() throws {
        let (store, mark) = try makeZone()
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        update(root, store: store)
        let ring = try ring(mark.id, in: root)
        let mesh = try XCTUnwrap(ring.model?.mesh)
        assertRing(ring, matches: mark)
        XCTAssertEqual(ring.scale.x, 4, accuracy: 0.000_1)
        XCTAssertNil(root.findEntity(named: "mark-\(mark.id.uuidString)")?.findEntity(named: "annotation-mark-arrow"))
        let baseline = store.marks
        XCTAssertTrue(store.nudgeCoachMarkEndpoint(id: mark.id, endpoint: .end,
                                                  by: PitchPoint(x: 0.5, z: 0)))
        let changed = try current(mark.id, in: store)
        XCTAssertEqual(changed.start, mark.start, "The centre stays fixed when steering the edge")
        XCTAssertEqual(changed.end, PitchPoint(x: mark.end.x + 0.5, z: mark.end.z))
        update(root, store: store)
        XCTAssertTrue(try self.ring(mark.id, in: root) === ring)
        XCTAssertTrue(ring.model?.mesh === mesh)
        assertRing(ring, matches: changed)
        XCTAssertEqual(ring.scale.x, 4.5, accuracy: 0.000_1)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline)
        update(root, store: store)
        assertRing(ring, matches: mark)
        XCTAssertEqual(ring.scale.x, 4, accuracy: 0.000_1)
    }

    func testZoneCentreMovesOnlyItsEndpointWithoutPromisingFixedRadiusTranslation() throws {
        let (store, mark) = try makeZone()
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        update(root, store: store)
        let ring = try ring(mark.id, in: root)
        let baseline = store.marks
        XCTAssertTrue(store.nudgeCoachMarkEndpoint(id: mark.id, endpoint: .start,
                                                  by: PitchPoint(x: 0, z: 0.5)))
        let changed = try current(mark.id, in: store)
        XCTAssertEqual(changed.end, mark.end)
        XCTAssertEqual(changed.start, PitchPoint(x: mark.start.x, z: mark.start.z + 0.5))
        update(root, store: store)
        assertRing(ring, matches: changed)
        XCTAssertGreaterThan(ring.scale.x, 4, "Moving only the centre can also change radius")
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline)
        update(root, store: store)
        assertRing(ring, matches: mark)
    }

    private func assertRing(_ ring: ModelEntity, matches mark: CoachMark,
                            file: StaticString = #filePath, line: UInt = #line) {
        let radius = ReplayGeometry.distance(mark.start, mark.end)
        XCTAssertEqual(ring.position.x, mark.start.x, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(ring.position.z, mark.start.z, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(ring.position.y, 0.072, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(ring.scale.x, radius, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(ring.scale.z, radius, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(ring.scale.y, 1, accuracy: 0.000_1, file: file, line: line)
    }

    private func makeZone() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        XCTAssertFalse(store.reviewLibrary.usesDisk)
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.space)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -20, z: -20)))
        let created = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: -16, z: -20)))
        if created.followsPlayerTracks {
            XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil))
        }
        return (store, try current(created.id, in: store))
    }

    private func current(_ id: UUID, in store: ReplayStore) throws -> CoachMark {
        try XCTUnwrap(store.marks.first { $0.id == id })
    }

    private func update(_ root: Entity, store: ReplayStore) {
        PitchSceneFactory.update(root: root, scenario: store.selectedScenario, time: store.playhead,
            viewMode: .tacticalTable, perspectiveID: store.activePerspectiveID,
            marks: store.marks, showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
    }

    private func ring(_ id: UUID, in root: Entity) throws -> ModelEntity {
        let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(id.uuidString)"))
        return try XCTUnwrap(markRoot.findEntity(named: "annotation-mark-space") as? ModelEntity)
    }

    private func deckSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private struct ImmersiveControlDeck:")?.lowerBound)
        return String(source[start...])
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
