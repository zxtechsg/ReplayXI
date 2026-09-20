import RealityKit
import simd
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
        XCTAssertEqual(edited.curve, .init(bend: -3, lift: 2,
            bendBearingDegrees: original.resolvedCurve.bendBearingDegrees))
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
        for curve in [CoachMarkCurve(bend: .nan, lift: 1), .init(bend: 13, lift: 0), .init(bend: 1, lift: -1),
                      .init(bend: 2, lift: 0, rollDegrees: .nan), .init(bend: 2, lift: 0, rollDegrees: 181)] {
            let invalid = CoachMark(kind: .arc, start: .zero, end: .init(x: 5, z: 5), curve: curve, label: "Bad")
            XCTAssertFalse(ReplayStore.isValidReviewMark(invalid, for: store.selectedScenario))
        }
        let nonArc = CoachMark(kind: .pass, start: .zero, end: .init(x: 5, z: 5), curve: .init(bend: 1, lift: 1), label: "Wrong")
        XCTAssertFalse(ReplayStore.isValidReviewMark(nonArc, for: store.selectedScenario))
    }

    func testOldBendLiftPayloadPreservesEveryCurveSampleExactly() throws {
        let legacy = try JSONDecoder().decode(CoachMarkCurve.self, from: Data("{\"bend\":3,\"lift\":2}".utf8))
        XCTAssertEqual(legacy.rollDegrees, 0)
        let mark = CoachMark(kind: .arc, start: .init(x: -8, z: -10), end: .init(x: 4, z: 6),
                            curve: legacy, label: "Legacy")
        let start = SIMD3<Float>(-8, 0, -10)
        let end = SIMD3<Float>(4, 0, 6)
        // Independent original, unrotated formula, far from clipping bounds.
        let control = SIMD3<Float>(-2 - 16.0 / 20 * 6, 4, -2 + 12.0 / 20 * 6)
        XCTAssertEqual(legacy.controlPoint(for: mark), control)
        for index in 0...32 {
            let t = Float(index) / 32
            let expected = (1 - t) * (1 - t) * start + 2 * (1 - t) * t * control + t * t * end
            XCTAssertEqual(legacy.point(at: t, for: mark), expected)
        }
        let encoded = try JSONEncoder().encode(legacy)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("rollDegrees"))
    }

    func testRightAngleRotatesTheArcUprightWithoutMovingEndpoints() {
        let mark = CoachMark(kind: .arc, start: .init(x: -10, z: 0), end: .init(x: 10, z: 0),
                            curve: .init(bend: 3, lift: 0, rollDegrees: 90), label: "Loft")
        let midpoint = mark.resolvedCurve.point(at: 0.5, for: mark)
        XCTAssertEqual(midpoint.x, 0, accuracy: 0.000_01)
        XCTAssertEqual(midpoint.y, 3, accuracy: 0.000_01)
        XCTAssertEqual(midpoint.z, 0, accuracy: 0.000_01)
        XCTAssertEqual(mark.resolvedCurve.point(at: 0, for: mark), SIMD3<Float>(-10, 0, 0))
        XCTAssertEqual(mark.resolvedCurve.point(at: 1, for: mark), SIMD3<Float>(10, 0, 0))
    }

    func testAngleUsesTheActualElevatedChordNotWorldUpOrTheViewer() {
        let curve = CoachMarkCurve(bend: 1, lift: 0.2, rollDegrees: 35)
        let mark = CoachMark(kind: .arc, start: .init(x: -4, z: -3), end: .init(x: 4, z: 3),
                            startElevation: 1.2, endElevation: 2.2, curve: curve, label: "Raised")
        let start = SIMD3<Float>(-4, 1.2, -3)
        let end = SIMD3<Float>(4, 2.2, 3)
        let axis = simd_normalize(end - start)
        let offset = SIMD3<Float>(-1.2, 0.4, 1.6)
        let angle: Float = -35 * .pi / 180
        // Rodrigues is independent of the quaternion implementation.
        let expectedOffset = offset * cos(angle) + simd_cross(axis, offset) * sin(angle)
            + axis * simd_dot(axis, offset) * (1 - cos(angle))
        let actual = curve.controlPoint(for: mark) - (start + end) * 0.5
        XCTAssertLessThan(simd_distance(actual, expectedOffset), 0.000_01)
        XCTAssertEqual(simd_length(actual), simd_length(offset), accuracy: 0.000_01)
        XCTAssertEqual(simd_dot(actual, axis), simd_dot(offset, axis), accuracy: 0.000_01)
        XCTAssertEqual(curve.point(at: 0, for: mark), start)
        XCTAssertEqual(curve.point(at: 1, for: mark), end)
    }

    func testRotatedCurvesRemainFiniteAbovePitchAndWithinPitchEdges() {
        for degrees in stride(from: Float(-180), through: 180, by: 15) {
            let curve = CoachMarkCurve(bend: 12, lift: 4, rollDegrees: degrees)
            let mark = CoachMark(kind: .arc, start: .init(x: 33, z: 48), end: .init(x: 34, z: 52),
                                curve: curve, label: "Bounded")
            for index in 0...32 {
                let point = curve.point(at: Float(index) / 32, for: mark)
                XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite)
                XCTAssertTrue((-34...34).contains(point.x))
                XCTAssertTrue((-52.5...52.5).contains(point.z))
                XCTAssertTrue((0...12).contains(point.y))
            }
        }
        let raised = CoachMark(kind: .arc, start: .init(x: -3, z: 0), end: .init(x: 3, z: 0),
                              startElevation: 4, endElevation: 4,
                              curve: .init(bend: 1, lift: 0, rollDegrees: -90), label: "Dip")
        XCTAssertEqual(raised.resolvedCurve.point(at: 0.5, for: raised).y, 3, accuracy: 0.000_01)
    }

    func testAmountScalesTheOriginalOffsetAndAngleRoundTripsInSavedMarks() throws {
        let original = CoachMarkCurve(bend: 3, lift: 2, rollDegrees: 40)
        let adjusted = original.adjusting(amountDelta: 1, angleDelta: 5)
        XCTAssertEqual(adjusted.amount, original.amount + 1, accuracy: 0.000_01)
        XCTAssertEqual(adjusted.bend / adjusted.lift, 1.5, accuracy: 0.000_01)
        XCTAssertEqual(adjusted.rollDegrees, 45)
        let store = ReplayStore()
        let mark = try makeArc(store)
        let token = UUID()
        XCTAssertTrue(store.previewCoachMarkCurve(id: mark.id, gestureID: token, curve: adjusted))
        XCTAssertTrue(store.commitCoachMarkCurvePreview(id: mark.id, gestureID: token))
        let restored = try JSONDecoder().decode(SavedReplayState.self, from: JSONEncoder().encode(store.makeSavedReviewState()))
        var expected = adjusted
        expected.bendBearingDegrees = mark.resolvedCurve.bendBearingDegrees
        XCTAssertEqual(restored.marks.first(where: { $0.id == mark.id })?.resolvedCurve, expected)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first(where: { $0.id == mark.id }), mark)
    }

    func testRotationInvalidatesNativeMeshAndUpdatesCurvedPicking() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let id = UUID()
        func update(angle: Float) {
            let arc = CoachMark(id: id, kind: .arc, start: .init(x: -10, z: 0), end: .init(x: 10, z: 0),
                                curve: .init(bend: 3, lift: 0, rollDegrees: angle), label: "Rotate")
            PitchSceneFactory.update(root: root, scenario: scenario, time: 0,
                viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
                marks: [arc], showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
        }
        update(angle: 0)
        let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(id.uuidString)"))
        let path = try XCTUnwrap(markRoot.findEntity(named: "annotation-mark-segment-0") as? ModelEntity)
        let flatMesh = try XCTUnwrap(path.model?.mesh)
        let picker = try XCTUnwrap(markRoot.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
        let flatPickY = picker.children[8].position.y
        update(angle: 90)
        let uprightMesh = try XCTUnwrap(path.model?.mesh)
        XCTAssertFalse(uprightMesh === flatMesh)
        XCTAssertGreaterThan(uprightMesh.bounds.extents.y, 2.9)
        XCTAssertGreaterThan(picker.children[8].position.y, flatPickY + 2.8)
        update(angle: 90)
        XCTAssertTrue(path.model?.mesh === uprightMesh, "No per-frame rebuild of the rotated mesh")
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
