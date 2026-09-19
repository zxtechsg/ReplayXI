import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayKeyframedAnnotationPresentationTests: XCTestCase {
    func testArcLabelsHandlesHitTargetsGuidesAndSelectionFollowSampledElevationAndRoll() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedMark(kind: .arc)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for time in [2.0, 4, 6, 4, 2] {
            update(root, scenario: scenario, mark: mark, time: time, selected: true, editable: true)
            let pose = mark.sampled(at: time)
            let markRoot = try entity("mark-\(mark.id.uuidString)", in: root)
            let selection = try entity(AnnotationSceneAffordance.selectionRootName, in: root)
            let lift = AnnotationSceneAffordance.selectionLift(for: .tacticalTable)
            try assertHandle(.start, mark: pose, selection: selection, lift: lift)
            try assertHandle(.end, mark: pose, selection: selection, lift: lift)

            let arrow = try entity("annotation-mark-arrow", in: markRoot)
            assertVector(arrow.position, pose.resolvedCurve.point(at: 1, for: pose, baseY: 0.12))
            assertVector(arrow.orientation.act([0, 1, 0]), simd_normalize(pose.resolvedCurve.endTangent(for: pose)))
            for (name, point, elevation) in [
                ("start", pose.start, pose.resolvedStartElevation),
                ("end", pose.end, pose.resolvedEndElevation)
            ] {
                let guide = try entity("annotation-mark-\(name)-elevation-guide", in: markRoot)
                XCTAssertTrue(guide.isEnabled)
                assertVector(guide.position, [point.x, (elevation + 0.10) / 2, point.z])
                XCTAssertEqual(guide.scale.y, elevation + 0.10, accuracy: 0.0001)
            }

            let label = try entity("annotation-label", in: markRoot)
            let anchor = pose.resolvedCurve.point(at: 0.70, for: pose)
            let direction = SIMD2<Float>(pose.end.x - pose.start.x, pose.end.z - pose.start.z)
            let normal = SIMD2<Float>(-direction.y, direction.x) / simd_length(direction)
            assertVector(label.position, [anchor.x + normal.x * 0.65, anchor.y + 0.78,
                                          anchor.z + normal.y * 0.65])
            let target = try entity(AnnotationSceneAffordance.bodyTargetName, in: markRoot)
            for index in [0, 8, 15] {
                let segment = target.children[index]
                let a = pose.resolvedCurve.point(at: Float(index) / 16, for: pose, baseY: 0.17)
                let b = pose.resolvedCurve.point(at: Float(index + 1) / 16, for: pose, baseY: 0.17)
                assertVector(segment.position, (a + b) / 2)
                XCTAssertEqual(segment.scale.z, simd_distance(a, b) + 0.12, accuracy: 0.0001)
            }
            let rail = try XCTUnwrap(selection.findEntity(named: "annotation-selection-rail") as? ModelEntity)
            let mesh = try XCTUnwrap(rail.model).mesh
            let model = try XCTUnwrap(mesh.contents.models.first)
            let part = try XCTUnwrap(model.parts.first)
            let vertices = Array(part.positions.elements)
            XCTAssertEqual(vertices.count, (CoachMarkCurve.segmentCount + 1) * 6)
            for ring in [0, 16, 32] {
                let centre = vertices[(ring * 6)..<((ring + 1) * 6)].reduce(SIMD3<Float>.zero, +) / 6
                assertVector(rail.convert(position: centre, to: selection),
                             pose.resolvedCurve.point(at: Float(ring) / 32, for: pose, baseY: lift))
            }
        }
    }

    func testZoneSelectionKeepsKeyedRadiusInEveryViewInsteadOfScalingItsArea() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedMark(kind: .space)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for view in [ReplayViewMode.tacticalTable, .firstPerson, .touchline] {
            for time in [2.0, 4, 6, 2] {
                update(root, scenario: scenario, mark: mark, time: time, selected: true, editable: true, view: view)
                let pose = mark.sampled(at: time)
                let selection = try entity(AnnotationSceneAffordance.selectionRootName, in: root)
                let ring = try entity("annotation-selection-zone", in: selection)
                let radius = ReplayGeometry.distance(pose.start, pose.end)
                XCTAssertEqual(ring.scale.x, radius, accuracy: 0.0001)
                XCTAssertEqual(ring.scale.z, radius, accuracy: 0.0001)
                assertVector(ring.position, [pose.start.x,
                    pose.resolvedStartElevation + AnnotationSceneAffordance.selectionLift(for: view), pose.start.z])
                let handle = try entity("annotation-target-end-\(mark.id.uuidString)", in: selection)
                XCTAssertEqual(simd_distance(SIMD2(handle.position.x, handle.position.z),
                                            SIMD2(ring.position.x, ring.position.z)), radius, accuracy: 0.0001)
                let base = try entity("annotation-mark-space", in: try entity("mark-\(mark.id.uuidString)", in: root))
                XCTAssertEqual(base.scale.x, ring.scale.x, accuracy: 0.0001)
                XCTAssertEqual(base.scale.z, ring.scale.z, accuracy: 0.0001)
            }
        }
    }

    func testCrossingEndpointKeysKeepStraightRailsAndHitTargetsFiniteAndRecoverOnSeek() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for kind in [CoachMarkKind.run, .pass, .danger] {
            let first = CoachMark(kind: kind, start: .init(x: -2, z: 0), end: .init(x: 2, z: 0),
                                  startElevation: 1, endElevation: 1, label: "Crossing", revealTime: 0)
            var mark = CoachMark(id: first.id, kind: kind, start: first.end, end: first.start,
                                 startElevation: 1, endElevation: 1, label: first.label, revealTime: 0)
            mark.keyframes = [.init(time: 2, mark: first), .init(time: 6, mark: mark)]
            XCTAssertTrue(mark.hasValidKeyframes(duration: scenario.duration))
            update(root, scenario: scenario, mark: mark, time: 2, selected: true, editable: true)
            let markRoot = try entity("mark-\(mark.id.uuidString)", in: root)
            let rail = try entity("annotation-mark-segment-0", in: markRoot)
            let original = rail.transform
            update(root, scenario: scenario, mark: mark, time: 4, selected: true, editable: true)
            let target = try entity(AnnotationSceneAffordance.bodyTargetName, in: markRoot)
            let selectedPath = try entity("annotation-selection-path", in: root)
            for item in [rail, target, selectedPath] {
                XCTAssertTrue(item.orientation.vector.x.isFinite)
                XCTAssertTrue(item.orientation.vector.y.isFinite)
                XCTAssertTrue(item.orientation.vector.z.isFinite)
                XCTAssertTrue(item.orientation.vector.w.isFinite)
                XCTAssertEqual(item.orientation.vector, simd_quatf().vector)
                XCTAssertGreaterThan(item.scale.z, 0)
            }
            XCTAssertFalse(try entity("annotation-mark-arrow", in: markRoot).isEnabled)
            update(root, scenario: scenario, mark: mark, time: 2, selected: true, editable: true)
            XCTAssertEqual(rail.transform, original)
            XCTAssertTrue(try entity("annotation-mark-arrow", in: markRoot).isEnabled)
        }
    }

    func testVisibilityWindowHidesAllPresentationAndEditableSelectionUsesCurrentPose() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = animatedMark(kind: .arc)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for (time, visible) in [(1.99, false), (2.0, true), (6.99, true), (7.0, false), (4.0, true)] {
            update(root, scenario: scenario, mark: mark, time: time, selected: true, editable: false)
            let markRoot = try entity("mark-\(mark.id.uuidString)", in: root)
            XCTAssertEqual(markRoot.isEnabled, visible)
            XCTAssertEqual(try entity("annotation-label", in: markRoot).isEnabled, visible)
            XCTAssertEqual(try entity(AnnotationSceneAffordance.selectionRootName, in: root).isEnabled, visible)
            if visible {
                let arrow = try entity("annotation-mark-arrow", in: markRoot)
                assertVector(arrow.position, mark.sampled(at: time).resolvedCurve.point(at: 1, for: mark.sampled(at: time), baseY: 0.12))
            }
        }
        update(root, scenario: scenario, mark: mark, time: 8, selected: true, editable: true)
        let selection = try entity(AnnotationSceneAffordance.selectionRootName, in: root)
        XCTAssertTrue(selection.isEnabled, "Editing outside In/Out intentionally keeps the mark available")
        try assertHandle(.end, mark: mark.sampled(at: 8), selection: selection,
                         lift: AnnotationSceneAffordance.selectionLift(for: .tacticalTable))
    }

    private func animatedMark(kind: CoachMarkKind) -> CoachMark {
        let first = CoachMark(kind: kind, start: .init(x: -8, z: -10), end: .init(x: 4, z: -4),
                              startElevation: 0.2, endElevation: kind == .space ? 0.2 : 0.4,
                              curve: kind == .arc ? .init(bend: 2, lift: 1, rollDegrees: -20) : nil,
                              label: "Keyed shape", revealTime: 2, hideTime: 7)
        var last = CoachMark(id: first.id, kind: kind, start: .init(x: -4, z: -6), end: .init(x: 8, z: 2),
                             startElevation: 1, endElevation: kind == .space ? 1 : 2,
                             curve: kind == .arc ? .init(bend: 4, lift: 2, rollDegrees: 80) : nil,
                             label: first.label, revealTime: 2, hideTime: 7)
        last.keyframes = [.init(time: 2, mark: first), .init(time: 6, mark: last)]
        return last
    }

    private func assertHandle(_ endpoint: CoachMarkEndpoint, mark: CoachMark, selection: Entity, lift: Float) throws {
        let isStart = endpoint == .start
        let handle = try entity("annotation-target-\(isStart ? "start" : "end")-\(mark.id.uuidString)", in: selection)
        let point = isStart ? mark.start : mark.end
        let elevation = isStart ? mark.resolvedStartElevation : mark.resolvedEndElevation
        assertVector(handle.position, [point.x, lift + elevation, point.z])
    }

    private func entity(_ name: String, in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: name))
    }

    private func assertVector(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.0002, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.0002, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.0002, file: file, line: line)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, mark: CoachMark, time: TimeInterval,
                        selected: Bool, editable: Bool, view: ReplayViewMode = .tacticalTable) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
                                 perspectiveID: scenario.defaultPerspectiveID, marks: [mark],
                                 selectedAnnotationID: selected ? mark.id : nil,
                                 selectedAnnotationIsEditable: editable,
                                 showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
    }
}
