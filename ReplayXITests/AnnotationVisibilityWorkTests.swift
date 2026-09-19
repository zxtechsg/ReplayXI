import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationVisibilityWorkTests: XCTestCase {
    private struct Phase: Codable {
        let name: String
        let samples: Int
        let changedFlags: Int
        let work: PitchSceneFactory.AnnotationSceneWorkCounters
    }

    private struct Report: Codable {
        let marks: Int
        let phases: [Phase]
        let qualification: String
    }

    func testMaximumHistoryCapturesPausedAndReverseVisibilityWorkAgainstFlagChanges() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let marks = history(count: ReplayStore.maximumSharedCoachMarks)
        XCTAssertEqual(marks.count, 128)
        let root = annotationRoot()
        update(root, scenario: scenario, marks: marks, time: 1)
        let flags = try visibilityEntities(root, marks: marks)
        XCTAssertEqual(flags.count, 1 + marks.count * 4)
        let original = flags.map(\.isEnabled)
        XCTAssertEqual(original.filter { $0 }.count, 1, "Only the containing marks root is enabled")

        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        for _ in 0..<60 { update(root, scenario: scenario, marks: marks, time: 1) }
        let paused = PitchSceneFactory.annotationSceneWork
        XCTAssertEqual(flags.map(\.isEnabled), original)
        XCTAssertEqual(paused.visibilityWriteRequests, 60 * flags.count)
        XCTAssertEqual(paused.visibilityPropertyWrites, 0)
        XCTAssertEqual(paused.markTreeBuilds, 0)

        let times: [TimeInterval] = [9, 10, 11, 19, 20, 19, 10, 9]
        var changed = 0
        var previous = original
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        for time in times {
            update(root, scenario: scenario, marks: marks, time: time)
            let current = flags.map(\.isEnabled)
            changed += zip(previous, current).filter { $0.0 != $0.1 }.count
            previous = current
            let isVisible = time >= 10 && time < 20
            let expected = Set(isVisible ? Array(0..<3) : [])
            try assertVisibility(root, marks: marks, admitted: expected, captions: expected, input: expected)
        }
        let moving = PitchSceneFactory.annotationSceneWork
        XCTAssertGreaterThan(changed, 0)
        XCTAssertEqual(moving.visibilityWriteRequests, times.count * flags.count)
        XCTAssertEqual(moving.visibilityPropertyWrites, changed,
                       "Only observed flag transitions need a RealityKit property write")
        XCTAssertEqual(moving.markTreeBuilds, 0)
        XCTAssertEqual(flags.map(\.isEnabled), original)
        let finalEntities = try visibilityEntities(root, marks: marks)
        XCTAssertTrue(zip(flags, finalEntities).allSatisfy { $0.0 === $0.1 })
        attach(Report(marks: marks.count, phases: [
            Phase(name: "60_paused_hidden_updates", samples: 60, changedFlags: 0, work: paused),
            Phase(name: "forward_reverse_reveal_boundaries", samples: times.count, changedFlags: changed, work: moving)
        ], qualification: "DEBUG annotation visibility requests and requested RealityKit property writes only. Flag changes are counted independently from actual entities. Not engine-internal work, allocation counts or headset FPS."))
    }

    func testPOVCaptionsSelectionAndDrawingRetainTheirActualVisibilityRules() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let marks = history(count: 4)
        let root = annotationRoot()
        update(root, scenario: scenario, marks: marks, time: 10)
        try assertVisibility(root, marks: marks, admitted: [0, 1, 2], captions: [0, 1, 2], input: [0, 1, 2])
        update(root, scenario: scenario, marks: marks, time: 10, view: .firstPerson)
        try assertVisibility(root, marks: marks, admitted: [0, 1, 2], captions: [0, 1], input: [0, 1, 2])
        update(root, scenario: scenario, marks: marks, time: 10, selected: marks[2].id)
        try assertVisibility(root, marks: marks, admitted: [0, 1, 2], captions: [2], input: [2])
        update(root, scenario: scenario, marks: marks, time: 10, selected: marks[2].id, editable: true)
        try assertVisibility(root, marks: marks, admitted: [0, 2], captions: [2], input: [])
        update(root, scenario: scenario, marks: marks, time: 10, selected: marks[2].id,
               editable: true, drawing: true)
        try assertVisibility(root, marks: marks, admitted: [0, 1, 2], captions: [0, 1, 2], input: [])
        update(root, scenario: scenario, marks: marks, time: 25, selected: marks[2].id, editable: true)
        try assertVisibility(root, marks: marks, admitted: [2], captions: [2], input: [])
        update(root, scenario: scenario, marks: marks, time: 25, selected: marks[2].id)
        try assertVisibility(root, marks: marks, admitted: [], captions: [], input: [])
        update(root, scenario: scenario, marks: marks, time: 10)
        try assertVisibility(root, marks: marks, admitted: [0, 1, 2], captions: [0, 1, 2], input: [0, 1, 2])
    }

    func testExternalFlagChangesAreRepairedFromActualEntitiesWithoutTreeReplacement() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let marks = history(count: 4)
        let root = annotationRoot()
        update(root, scenario: scenario, marks: marks, time: 10)
        let entities = try visibilityEntities(root, marks: marks)
        let expected = entities.map(\.isEnabled)
        for entity in entities { entity.isEnabled.toggle() }
        XCTAssertEqual(zip(expected, entities.map(\.isEnabled)).filter { $0.0 != $0.1 }.count, entities.count)
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        update(root, scenario: scenario, marks: marks, time: 10)
        XCTAssertEqual(entities.map(\.isEnabled), expected)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.visibilityWriteRequests, entities.count)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.visibilityPropertyWrites, entities.count)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.markTreeBuilds, 0)
        XCTAssertTrue(zip(entities, try visibilityEntities(root, marks: marks)).allSatisfy { $0.0 === $0.1 })
    }

    private func visibilityEntities(_ root: Entity, marks: [CoachMark]) throws -> [Entity] {
        var result = [try child("marks-root", in: root)]
        for mark in marks {
            let entity = try child("mark-\(mark.id.uuidString)", in: root)
            result.append(entity)
            result.append(try child(AnnotationSceneAffordance.bodyTargetName, in: entity))
            result.append(try child(AnnotationSceneAffordance.labelTargetName, in: entity))
            result.append(try child("annotation-label", in: entity))
        }
        return result
    }

    private func assertVisibility(_ root: Entity, marks: [CoachMark], admitted: Set<Int>,
                                  captions: Set<Int>, input: Set<Int>) throws {
        XCTAssertTrue(try child("marks-root", in: root).isEnabled)
        for (index, mark) in marks.enumerated() {
            let entity = try child("mark-\(mark.id.uuidString)", in: root)
            XCTAssertEqual(entity.isEnabled, admitted.contains(index), "mark \(index)")
            XCTAssertEqual(try child("annotation-label", in: entity).isEnabled, captions.contains(index), "caption \(index)")
            XCTAssertEqual(try child(AnnotationSceneAffordance.bodyTargetName, in: entity).isEnabled,
                           input.contains(index), "body target \(index)")
            XCTAssertEqual(try child(AnnotationSceneAffordance.labelTargetName, in: entity).isEnabled,
                           input.contains(index), "label target \(index)")
        }
    }

    private func history(count: Int) -> [CoachMark] {
        (0..<count).map { index in
            let start = PitchPoint(x: -30 + Float(index % 16) * 3, z: -40 + Float(index / 16) * 4)
            return CoachMark(kind: .run, start: start, end: .init(x: start.x + 2, z: start.z + 3),
                             label: "History", revealTime: 10, hideTime: 20)
        }
    }

    private func annotationRoot() -> Entity {
        let root = Entity()
        let marks = Entity()
        marks.name = "marks-root"
        root.addChild(marks)
        root.addChild(AnnotationSceneAffordance.makeSelectionRoot())
        return root
    }

    private func update(_ root: Entity, scenario: ReplayScenario, marks: [CoachMark], time: TimeInterval,
                        view: ReplayViewMode = .tacticalTable, selected: UUID? = nil,
                        editable: Bool = false, drawing: Bool = false) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
                                 perspectiveID: scenario.defaultPerspectiveID, marks: marks,
                                 selectedAnnotationID: selected, selectedAnnotationIsEditable: editable,
                                 showsLaneLens: false, isDrawing: drawing, positionalOriginTransform: nil)
    }

    private func child(_ name: String, in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: name))
    }

    private func attach(_ report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return XCTFail("Visibility report could not encode") }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-AnnotationVisibilityWork.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
