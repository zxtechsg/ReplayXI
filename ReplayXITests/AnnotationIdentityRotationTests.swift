import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationIdentityRotationTests: XCTestCase {
    func testPlayerLabelTargetResetPreservesUnitAxesAndWorldPosition() {
        let root = Entity()
        let stage = transformedParent(of: root)
        let mark = CoachMark(kind: .playerLabel, start: .init(x: 6, z: 8),
                             end: .init(x: 6, z: 8), label: "Player")
        let target = AnnotationSceneAffordance.makeBodyTarget(for: mark)
        root.addChild(target)
        assertIdentityAxes(target, at: [6, 2.2, 8], in: root, stage: stage)
        target.orientation = simd_quatf(angle: 0.8, axis: [0, 1, 0])
        AnnotationSceneAffordance.configureBodyTarget(target, for: mark, labelPosition: [-3, 4, 7])
        assertIdentityAxes(target, at: [-3, 4, 7], in: root, stage: stage)
    }

    func testSpaceTargetParentPreservesCircumferenceAndTangentLengthsInWorldSpace() {
        let root = Entity()
        let stage = transformedParent(of: root)
        let original = CoachMark(kind: .space, start: .init(x: 18, z: 12), end: .init(x: 22, z: 12),
                                 startElevation: 1, endElevation: 1, label: "Space")
        let body = AnnotationSceneAffordance.makeBodyTarget(for: original)
        root.addChild(body)
        for radius: Float in [4, 9, 4] {
            let mark = CoachMark(id: original.id, kind: .space, start: original.start,
                                 end: .init(x: original.start.x + radius, z: original.start.z),
                                 startElevation: 1, endElevation: 1, label: original.label)
            AnnotationSceneAffordance.configureBodyTarget(body, for: mark, labelPosition: nil)
            let centre = SIMD3<Float>(18, 1.16, 12)
            assertIdentityAxes(body, at: centre, in: root, stage: stage)
            XCTAssertEqual(body.children.count, AnnotationSceneAffordance.spaceTargetSegmentCount)
            let length = 2 * Float.pi * radius / 12 * 0.74
            for (index, segment) in body.children.enumerated() {
                assertUnitRotation(segment)
                let angle = Float(index) / 12 * 2 * Float.pi
                let position = centre + SIMD3<Float>(sin(angle) * radius, 0, cos(angle) * radius)
                assertWorldPoint(segment, local: .zero, expectedInRoot: position, root: root, stage: stage)
                let tangent = SIMD3<Float>(cos(angle), 0, -sin(angle))
                assertWorldPoint(segment, local: [0, 0, 1], expectedInRoot: position + tangent * length,
                                 root: root, stage: stage)
            }
        }
    }

    func testCrossingKeysKeepVisibleRailsHitTargetsAndSelectedHandlesUsableInWorldSpace() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = annotationRoot()
        let stage = transformedParent(of: root)
        for kind in [CoachMarkKind.run, .pass, .danger] {
            let first = CoachMark(kind: kind, start: .init(x: -2, z: 0), end: .init(x: 2, z: 0),
                                  startElevation: 1, endElevation: 1, label: "Crossing", revealTime: 0)
            var mark = CoachMark(id: first.id, kind: kind, start: first.end, end: first.start,
                                 startElevation: 1, endElevation: 1, label: first.label, revealTime: 0)
            mark.keyframes = [.init(time: 2, mark: first), .init(time: 6, mark: mark)]
            for time in [2.0, 4, 6, 2] {
                update(root, scenario: scenario, mark: mark, time: time, selected: true)
                let pose = mark.sampled(at: time)
                let markRoot = try entity("mark-\(mark.id.uuidString)", in: root)
                let target = try entity(AnnotationSceneAffordance.bodyTargetName, in: markRoot)
                let selection = try entity(AnnotationSceneAffordance.selectionRootName, in: root)
                let path = try entity("annotation-selection-path", in: selection)
                var items = [target, path]
                for index in 0..<(kind == .danger ? 7 : 1) {
                    items.append(try entity("annotation-mark-segment-\(index)", in: markRoot))
                }
                for item in items {
                    assertUnitRotation(item)
                    if time == 4 {
                        assertIdentityAxes(item, at: item.position, in: root, stage: stage)
                        XCTAssertGreaterThan(item.scale.z, 0)
                    }
                }
                for (part, point) in [("start", pose.start), ("end", pose.end)] {
                    let handle = try entity("annotation-target-\(part)-\(mark.id.uuidString)", in: selection)
                    assertUnitRotation(handle)
                    let position = SIMD3<Float>(point.x,
                        AnnotationSceneAffordance.selectionLift(for: .tacticalTable) + 1, point.z)
                    assertWorldPoint(handle, local: .zero, expectedInRoot: position, root: root, stage: stage)
                }
                XCTAssertEqual(try entity("annotation-mark-arrow", in: markRoot).isEnabled, time != 4)
            }
        }
    }

    func testElevatedGuideKeepsFullVerticalExtentAfterGroundHideAndViewChanges() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = annotationRoot()
        let stage = transformedParent(of: root)
        let id = UUID()
        for view in [ReplayViewMode.tacticalTable, .firstPerson, .touchline] {
            for elevation: Float in [0.5, 2, 0, 1] {
                let mark = CoachMark(id: id, kind: .arc, start: .init(x: -3, z: -2), end: .init(x: 5, z: 4),
                                     startElevation: elevation, endElevation: elevation,
                                     curve: .init(bend: 2, lift: 1), label: "Elevated", revealTime: 0)
                update(root, scenario: scenario, mark: mark, time: 4, view: view)
                let markRoot = try entity("mark-\(mark.id.uuidString)", in: root)
                for (name, point) in [("start", mark.start), ("end", mark.end)] {
                    let guide = try entity("annotation-mark-\(name)-elevation-guide", in: markRoot)
                    XCTAssertEqual(guide.isEnabled, elevation > 0)
                    guard guide.isEnabled else { continue }
                    assertUnitRotation(guide)
                    assertWorldPoint(guide, local: [0, -0.5, 0],
                                     expectedInRoot: [point.x, 0, point.z], root: root, stage: stage)
                    assertWorldPoint(guide, local: [0, 0.5, 0],
                                     expectedInRoot: [point.x, elevation + 0.10, point.z], root: root, stage: stage)
                }
            }
        }
    }

    func testDraftSpaceRetainsWorldRadiusAcrossToolSwitchesAndCancellation() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let stage = transformedParent(of: root)
        let start = PitchPoint(x: 2, z: 3)
        let end = PitchPoint(x: 7, z: 3)
        for kind in [CoachMarkKind.run, .space, .pass, .space] {
            renderDraft(root, scenario: scenario, start: start, end: end, kind: kind)
            let zone = try entity("annotation-draft-stroke-zone", in: root)
            XCTAssertEqual(zone.isEnabled, kind == .space)
            guard kind == .space else { continue }
            assertIdentityAxes(zone, at: [2, 0.078, 3], in: root, stage: stage)
            XCTAssertEqual(zone.scale.x, 5, accuracy: 0.0001)
            XCTAssertEqual(zone.scale.z, 5, accuracy: 0.0001)
        }
        renderDraft(root, scenario: scenario, start: start, end: nil, kind: .space)
        XCTAssertFalse(try entity("annotation-draft-stroke", in: root).isEnabled)
        renderDraft(root, scenario: scenario, start: start, end: end, kind: .space)
        assertIdentityAxes(try entity("annotation-draft-stroke-zone", in: root),
                           at: [2, 0.078, 3], in: root, stage: stage)
    }

    private func assertIdentityAxes(_ item: Entity, at position: SIMD3<Float>, in root: Entity,
                                    stage: Entity, file: StaticString = #filePath, line: UInt = #line) {
        assertUnitRotation(item, file: file, line: line)
        assertWorldPoint(item, local: .zero, expectedInRoot: position, root: root, stage: stage,
                         file: file, line: line)
        for axis: SIMD3<Float> in [[1, 0, 0], [0, 1, 0], [0, 0, 1]] {
            assertVector(item.orientation.act(axis), axis, file: file, line: line)
            assertWorldPoint(item, local: axis, expectedInRoot: position + axis * item.scale,
                             root: root, stage: stage, file: file, line: line)
        }
    }

    private func assertUnitRotation(_ item: Entity, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(simd_length(item.orientation.vector), 1, accuracy: 0.00002, file: file, line: line)
    }

    private func assertWorldPoint(_ item: Entity, local: SIMD3<Float>, expectedInRoot: SIMD3<Float>,
                                 root: Entity, stage: Entity, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(root.parent === stage, file: file, line: line)
        // Compute the known parent chain independently of the target's matrix.
        let expected = stage.transform.matrix * root.transform.matrix
            * SIMD4<Float>(expectedInRoot.x, expectedInRoot.y, expectedInRoot.z, 1)
        assertVector(item.convert(position: local, to: nil), [expected.x, expected.y, expected.z],
                     file: file, line: line)
    }

    private func transformedParent(of root: Entity) -> Entity {
        let stage = Entity()
        stage.transform = Transform(scale: [0.4, 0.7, 0.55],
                                    rotation: simd_quatf(angle: 0.6, axis: simd_normalize([1, 2, 0.5])),
                                    translation: [2, 1, -3])
        stage.addChild(root)
        return stage
    }

    private func annotationRoot() -> Entity {
        let root = Entity()
        let marks = Entity()
        marks.name = "marks-root"
        root.addChild(marks)
        root.addChild(AnnotationSceneAffordance.makeSelectionRoot())
        return root
    }

    private func entity(_ name: String, in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: name))
    }

    private func update(_ root: Entity, scenario: ReplayScenario, mark: CoachMark, time: TimeInterval,
                        selected: Bool = false, view: ReplayViewMode = .tacticalTable) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
                                 perspectiveID: scenario.defaultPerspectiveID, marks: [mark],
                                 selectedAnnotationID: selected ? mark.id : nil, selectedAnnotationIsEditable: selected,
                                 showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
    }

    private func renderDraft(_ root: Entity, scenario: ReplayScenario, start: PitchPoint,
                             end: PitchPoint?, kind: CoachMarkKind) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: 8, viewMode: .tacticalTable,
                                 perspectiveID: scenario.defaultPerspectiveID, marks: [],
                                 showsLaneLens: false, isDrawing: true, draftStart: start, draftEnd: end,
                                 draftKind: kind, positionalOriginTransform: nil)
    }

    private func assertVector(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.0001, file: file, line: line)
    }
}
