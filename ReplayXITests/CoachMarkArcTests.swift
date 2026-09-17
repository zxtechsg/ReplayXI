import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkArcTests: XCTestCase {
    func testTwoPointsCreateBendAndPreserveBothEndpoints() throws {
        let store = ReplayStore()
        let mark = try makeArc(store)
        XCTAssertEqual(mark.kind, .arc)
        XCTAssertGreaterThan(mark.resolvedCurve.bend, 0)
        XCTAssertFalse(store.isDrawing)
        let start = mark.resolvedCurve.point(at: 0, for: mark)
        let end = mark.resolvedCurve.point(at: 1, for: mark)
        XCTAssertEqual(start, SIMD3<Float>(mark.start.x, 0, mark.start.z))
        XCTAssertEqual(end, SIMD3<Float>(mark.end.x, 0, mark.end.z))
        let midpoint = mark.resolvedCurve.point(at: 0.5, for: mark)
        XCTAssertGreaterThan(midpoint.x, mark.start.x)
        XCTAssertEqual(midpoint.z, (mark.start.z + mark.end.z) / 2, accuracy: 0.0001)
    }

    func testCurveLiftAndBendAreBoundedSmoothGeometry() {
        let mark = CoachMark(kind: .arc, start: PitchPoint(x: -10, z: 0),
                             end: PitchPoint(x: 10, z: 0), curve: .init(bend: 3, lift: 2), label: "Arc")
        XCTAssertEqual(mark.resolvedCurve.point(at: 0.5, for: mark), SIMD3<Float>(0, 2, 3))
        let edge = CoachMark(kind: .arc, start: PitchPoint(x: 34, z: 50),
                             end: PitchPoint(x: 34, z: 52), curve: .init(bend: -12, lift: 4), label: "Edge")
        for index in 0...100 {
            let point = edge.resolvedCurve.point(at: Float(index) / 100, for: edge)
            XCTAssertLessThanOrEqual(abs(point.x), 34)
            XCTAssertLessThanOrEqual(abs(point.z), 52.5)
            XCTAssertTrue((0...4).contains(point.y))
        }
    }

    func testCurvePreviewMasksSavedStateCancelsExactlyAndRejectsStaleInput() throws {
        let store = ReplayStore()
        let original = try makeArc(store)
        let token = UUID()
        XCTAssertTrue(store.previewCoachMarkCurve(id: original.id, gestureID: token, curve: .init(bend: -3, lift: 2)))
        XCTAssertTrue(store.isCoachMarkCurvePreviewOwner(id: original.id, gestureID: token))
        XCTAssertEqual(store.makeSavedReviewState().marks.first(where: { $0.id == original.id }), original)
        XCTAssertFalse(store.previewCoachMarkCurve(id: original.id, gestureID: UUID(), curve: .init(bend: 1, lift: 1)))
        XCTAssertFalse(store.updateCoachMarkGeometry(id: original.id, start: original.start, end: original.end))
        XCTAssertTrue(store.cancelCoachMarkCurvePreview(id: original.id, gestureID: token))
        XCTAssertEqual(store.marks.first(where: { $0.id == original.id }), original)
        XCTAssertFalse(store.previewCoachMarkCurve(id: original.id, gestureID: token, curve: .init(bend: 4, lift: 1)))
        XCTAssertFalse(store.commitCoachMarkCurvePreview(id: original.id, gestureID: token))
    }

    func testCommitIsOneUndoStepAndCurveSurvivesOtherEdits() throws {
        let store = ReplayStore()
        let original = try makeArc(store)
        let token = UUID()
        for index in 1...10 {
            XCTAssertTrue(store.previewCoachMarkCurve(id: original.id, gestureID: token,
                curve: .init(bend: -Float(index) * 0.3, lift: Float(index) * 0.2)))
        }
        XCTAssertTrue(store.commitCoachMarkCurvePreview(id: original.id, gestureID: token))
        let edited = try XCTUnwrap(store.marks.first(where: { $0.id == original.id }))
        XCTAssertEqual(edited.curve, .init(bend: -3, lift: 2))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first(where: { $0.id == original.id }), original)
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.first(where: { $0.id == original.id }), edited)
        XCTAssertTrue(store.retimeCoachMark(id: original.id, to: 2))
        XCTAssertTrue(store.setCoachMarkTracking(id: original.id, playerID: "navy-rw"))
        XCTAssertTrue(store.nudgeCoachMarkElevation(id: original.id, target: .both, by: 0.5))
        XCTAssertEqual(store.marks.first(where: { $0.id == original.id })?.curve, edited.curve)
        let roundTrip = try JSONDecoder().decode(SavedReplayState.self, from: JSONEncoder().encode(store.makeSavedReviewState()))
        XCTAssertEqual(roundTrip.marks.first(where: { $0.id == original.id })?.curve, edited.curve)
    }

    func testLegacyPayloadAndInvalidCurveValidation() throws {
        let data = Data("""
        {"id":"AAAAAAAA-0000-4000-8000-000000000901","kind":"run","start":{"x":1,"z":2},
        "end":{"x":5,"z":8},"label":"Overlap","revealTime":3,"author":"Coach"}
        """.utf8)
        XCTAssertNil(try JSONDecoder().decode(CoachMark.self, from: data).curve)
        let store = ReplayStore()
        for curve in [CoachMarkCurve(bend: .nan, lift: 1), .init(bend: 13, lift: 0), .init(bend: 1, lift: -1)] {
            let invalid = CoachMark(kind: .arc, start: .zero, end: .init(x: 5, z: 5), curve: curve, label: "Bad")
            XCTAssertFalse(ReplayStore.isValidReviewMark(invalid, for: store.selectedScenario))
        }
        let nonArc = CoachMark(kind: .pass, start: .zero, end: .init(x: 5, z: 5), curve: .init(bend: 1, lift: 1), label: "Wrong")
        XCTAssertFalse(ReplayStore.isValidReviewMark(nonArc, for: store.selectedScenario))
    }

    func testNativeArcUsesOneMeshAndCurvedPickingWithUnchangedMeshReuse() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let arc = CoachMark(kind: .arc, start: .init(x: -10, z: -10), end: .init(x: 10, z: -10),
                            curve: .init(bend: 4, lift: 1), label: "Around defender")
        func update() {
            PitchSceneFactory.update(root: root, scenario: scenario, time: 0,
                viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
                marks: [arc], showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
        }
        update()
        let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(arc.id.uuidString)"))
        let path = try XCTUnwrap(markRoot.findEntity(named: "annotation-mark-segment-0") as? ModelEntity)
        let mesh = try XCTUnwrap(path.model?.mesh)
        XCTAssertNil(markRoot.findEntity(named: "annotation-mark-segment-1"))
        XCTAssertGreaterThan(mesh.bounds.extents.z, 3.9)
        XCTAssertGreaterThan(mesh.bounds.extents.y, 0.9)
        let picker = try XCTUnwrap(markRoot.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
        XCTAssertEqual(picker.children.count, 16)
        XCTAssertGreaterThan(picker.children[8].position.z, -6.1)
        update()
        XCTAssertTrue(path.model?.mesh === mesh)
        XCTAssertEqual(PlaybackSceneRenderBudget.estimatedDraws(for: arc), 5)
    }

    func testPlayerBoundTranslationReusesMeshButShapeAndPitchEdgeChangesRebuildIt() throws {
        let path = ModelEntity(mesh: .generateSphere(radius: 0.1), materials: [UnlitMaterial(color: .white)])
        func mark(start: PitchPoint, end: PitchPoint, bend: Float = 3) -> CoachMark {
            CoachMark(kind: .arc, start: start, end: end, curve: .init(bend: bend, lift: 1), label: "Arc")
        }
        let original = mark(start: .init(x: -10, z: 0), end: .init(x: 10, z: 0))
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: original))
        let mesh = try XCTUnwrap(path.model?.mesh)
        let translated = mark(start: .init(x: -5, z: 2), end: .init(x: 15, z: 2))
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: translated))
        XCTAssertTrue(path.model?.mesh === mesh)
        XCTAssertEqual(path.position, SIMD3<Float>(5, 0, 2))
        let straightMesh = MeshResource.generateBox(size: 1)
        AnnotationArcMesh.reset(path, mesh: straightMesh)
        XCTAssertTrue(path.model?.mesh === straightMesh)
        XCTAssertEqual(path.position, .zero, "Switching back to a straight highlight must clear arc placement")
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: original))
        let rewoundMesh = try XCTUnwrap(path.model?.mesh)
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: translated))
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: original))
        XCTAssertTrue(path.model?.mesh === rewoundMesh)
        XCTAssertEqual(path.position, .zero, "Rewind restores the original transform, not a cumulative shift")
        let stretched = mark(start: original.start, end: .init(x: 14, z: 0))
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: stretched))
        XCTAssertFalse(path.model?.mesh === rewoundMesh)
        XCTAssertEqual(path.position, .zero)

        let nearEdge = mark(start: .init(x: -10, z: 48), end: .init(x: 10, z: 48))
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: nearEdge))
        let edgeMesh = try XCTUnwrap(path.model?.mesh)
        let atEdge = mark(start: .init(x: -10, z: 50), end: .init(x: 10, z: 50))
        XCTAssertTrue(AnnotationArcMesh.update(path, mark: atEdge))
        XCTAssertFalse(path.model?.mesh === edgeMesh, "Pitch-clamped control geometry is not a pure translation")
        XCTAssertEqual(path.position, .zero)
    }

    private func makeArc(_ store: ReplayStore) throws -> CoachMark {
        store.beginDrawing(.arc)
        XCTAssertNil(store.registerPitchTap(.init(x: -15, z: 15)))
        return try XCTUnwrap(store.registerPitchTap(.init(x: -15, z: -5)))
    }
}
