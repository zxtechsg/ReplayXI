import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationPoseCopyNative156Tests: XCTestCase {
    func testCopiedArcMatchesNativeSourceThenStaysFixedAcrossViewsAndRewind156() throws {
        let store = ReplayStore()
        store.setViewMode(.tacticalTable, broadcast: false)
        let first = CoachMark(kind: .arc, start: .init(x: -8, z: -10), end: .init(x: -4, z: -8),
            startElevation: 0.5, endElevation: 2,
            curve: .init(bend: 2, lift: 0.5, rollDegrees: 20, bendBearingDegrees: 120),
            label: "Alternative run", revealTime: 0)
        let last = CoachMark(kind: .arc, start: .init(x: -4, z: -7), end: .init(x: 0, z: -3),
            startElevation: 1, endElevation: 3,
            curve: .init(bend: 3, lift: 1, rollDegrees: 50, bendBearingDegrees: 150),
            label: first.label, revealTime: 0)
        var source = first
        source.keyframes = [.init(time: 2, mark: first), .init(time: 6, mark: last)]
        XCTAssertTrue(store.appendRemoteCoachMark(source))
        store.seek(to: 3, broadcast: false)
        let copy = try XCTUnwrap(store.copyCoachMarkPose(id: source.id))
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertNil(copy.keyframes)
        XCTAssertFalse(copy.followsPlayerTracks)
        XCTAssertEqual(store.marks.first { $0.id == source.id }, source)

        for view in [ReplayViewMode.tacticalTable, .firstPerson, .touchline] {
            let root = Entity(), marks = Entity()
            marks.name = "marks-root"
            root.addChild(marks)
            root.addChild(AnnotationSceneAffordance.makeSelectionRoot())
            // Both raised arcs fit without the editable selection's draw
            // reserve. Hidden history intentionally does not animate.
            update(root, store: store, marks: [source, copy], selected: nil, time: 3, view: view)
            let originalPath = try path(source, in: root), copiedPath = try path(copy, in: root)
            let originalArrow = try arrow(source, in: root), copiedArrow = try arrow(copy, in: root)
            let initial = try points(copiedPath, relativeTo: marks)
            assertPoints(try points(originalPath, relativeTo: marks), initial)
            XCTAssertEqual(originalArrow.transform, copiedArrow.transform)
            let mesh = try XCTUnwrap(copiedPath.model?.mesh)
            let arrowTransform = copiedArrow.transform
            let originalTarget = try target(source, in: root), copiedTarget = try target(copy, in: root)
            XCTAssertEqual(originalTarget.children.map(\.transform), copiedTarget.children.map(\.transform))
            let targetTransforms = copiedTarget.children.map(\.transform)

            update(root, store: store, marks: [source, copy], selected: nil, time: 6, view: view)
            XCTAssertNotEqual(try points(originalPath, relativeTo: marks), initial, "The source still animates")
            assertPoints(try points(copiedPath, relativeTo: marks), initial)
            XCTAssertTrue(copiedPath.model?.mesh === mesh, "The fixed copy does not rebuild its mesh")
            XCTAssertEqual(copiedArrow.transform, arrowTransform)
            XCTAssertEqual(copiedTarget.children.map(\.transform), targetTransforms)

            update(root, store: store, marks: [source, copy], selected: nil, time: 3, view: view)
            assertPoints(try points(originalPath, relativeTo: marks), initial)
            assertPoints(try points(copiedPath, relativeTo: marks), initial)
            XCTAssertEqual(originalArrow.transform, arrowTransform)
            XCTAssertEqual(copiedArrow.transform, arrowTransform)
            XCTAssertTrue(copiedPath.model?.mesh === mesh)

            update(root, store: store, marks: [source, copy], selected: copy.id, time: 3, view: view)
            XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "mark-\(source.id.uuidString)")).isEnabled,
                           "Two raised arcs exceed the editable selection's remaining draw budget")
            XCTAssertTrue(try XCTUnwrap(root.findEntity(named: "mark-\(copy.id.uuidString)")).isEnabled)
            assertPoints(try points(copiedPath, relativeTo: marks), initial)
            XCTAssertEqual(copiedArrow.transform, arrowTransform)
            XCTAssertTrue(copiedPath.model?.mesh === mesh)
        }
    }

    private func path(_ mark: CoachMark, in root: Entity) throws -> ModelEntity {
        try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)")?
            .findEntity(named: "annotation-mark-segment-0") as? ModelEntity)
    }

    private func arrow(_ mark: CoachMark, in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)")?
            .findEntity(named: "annotation-mark-arrow"))
    }

    private func target(_ mark: CoachMark, in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)")?
            .findEntity(named: AnnotationSceneAffordance.bodyTargetName))
    }

    private func points(_ model: ModelEntity, relativeTo root: Entity) throws -> [SIMD3<Float>] {
        let part = try XCTUnwrap(model.model?.mesh.contents.models.first?.parts.first)
        return part.positions.elements.map { model.convert(position: $0, to: root) }
    }

    private func assertPoints(_ actual: [SIMD3<Float>], _ expected: [SIMD3<Float>],
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        let maximumError = zip(actual, expected).map { simd_distance($0.0, $0.1) }.max() ?? 0
        XCTAssertLessThanOrEqual(maximumError, 0.00003, file: file, line: line)
    }

    private func update(_ root: Entity, store: ReplayStore, marks: [CoachMark], selected: UUID?,
                        time: TimeInterval, view: ReplayViewMode) {
        PitchSceneFactory.update(root: root, scenario: store.selectedScenario, time: time, viewMode: view,
            perspectiveID: store.activePerspectiveID, marks: marks, selectedAnnotationID: selected,
            selectedAnnotationIsEditable: selected != nil, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil)
    }
}
