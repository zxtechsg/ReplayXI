import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class KeyframedAnnotationDrawBudgetTests: XCTestCase {
    private struct Frame: Codable {
        let mode: String
        let time: TimeInterval
        let admittedMarks: Int
        let enabledMarkModels: Int
        let enabledSelectionModels: Int
        let sampledUnfocusedCost: Int
        let selectionReserve: Int
    }

    private struct Report: Codable {
        let frames: [Frame]
        let qualification: String
    }

    func testFourZonesRespectActualModelBudgetAtRaisedAndInterpolatedTimesAndRewind() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let marks = fourKeyframedZones()
        XCTAssertTrue(marks.allSatisfy { $0.hasValidKeyframes(duration: scenario.duration) })
        let root = annotationRoot()
        update(root, scenario: scenario, marks: marks, time: 0)
        let originals = try marks.map { try markEntity($0, in: root) }
        var frames: [Frame] = []
        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        for time in [0.0, 1, 2, 3, 4, 3, 2, 1, 0] {
            update(root, scenario: scenario, marks: marks, time: time)
            let frame = try frame(root, marks: marks, time: time, mode: "normal", reserve: 0)
            frames.append(frame)
            let raised = time > 0 && time < 4
            let expectedAdmission = raised ? 3 : 4
            XCTAssertEqual(frame.admittedMarks, expectedAdmission, "time \(time)")
            XCTAssertEqual(frame.enabledMarkModels, expectedAdmission * (raised ? 6 : 4), "time \(time)")
            XCTAssertLessThanOrEqual(frame.enabledMarkModels, PlaybackSceneRenderBudget.normalAnnotationDrawLimit,
                                     "Real enabled annotation models at time \(time)")
            for (index, mark) in marks.enumerated() {
                let entity = try markEntity(mark, in: root)
                XCTAssertTrue(entity === originals[index], "Admission changes must retain the cached tree")
                XCTAssertEqual(entity.isEnabled, index < expectedAdmission,
                               "Equal reveal times keep authored priority order")
                guard entity.isEnabled else { continue }
                for endpoint in ["start", "end"] {
                    XCTAssertEqual(try child("annotation-mark-\(endpoint)-elevation-guide", in: entity).isEnabled,
                                   raised, "A newly admitted mark must catch up after reverse seek")
                }
            }
        }
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.markTreeBuilds, 0)
        attach(frames, name: "ReplayXI-KeyframedAnnotationDrawBudget-Normal.json")
    }

    func testSelectedEditableAndReadOnlyReservesUseTheCurrentElevatedPose() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let marks = fourKeyframedZones()
        let root = annotationRoot()
        let selected = marks[0]
        var frames: [Frame] = []
        for editable in [true, false] {
            let reserve = editable ? PlaybackSceneRenderBudget.selectedEditableOverlayDraws
                : PlaybackSceneRenderBudget.selectedReadOnlyOverlayDraws
            for time in [0.0, 1, 2, 3, 4, 2, 0] {
                update(root, scenario: scenario, marks: marks, time: time,
                       selected: selected.id, editable: editable)
                let frame = try frame(root, marks: marks, time: time,
                                      mode: editable ? "selected_editable" : "selected_read_only", reserve: reserve)
                frames.append(frame)
                let raised = time > 0 && time < 4
                let expectedAdmission = editable ? (raised ? 2 : 3) : (raised ? 3 : 4)
                XCTAssertEqual(frame.admittedMarks, expectedAdmission, "editable \(editable), time \(time)")
                XCTAssertTrue(try markEntity(selected, in: root).isEnabled)
                XCTAssertLessThanOrEqual(frame.sampledUnfocusedCost + reserve,
                                         PlaybackSceneRenderBudget.selectedAnnotationSystemDrawLimit,
                                         "The conservative reservation must use sampled elevations")
                XCTAssertLessThanOrEqual(frame.enabledMarkModels + frame.enabledSelectionModels,
                                         PlaybackSceneRenderBudget.selectedAnnotationSystemDrawLimit)
            }
        }
        // Editable selection can intentionally outlive In/Out, without allowing
        // unrelated hidden history to occupy the remaining scene budget.
        update(root, scenario: scenario, marks: marks, time: 9, selected: selected.id, editable: true)
        let outside = try frame(root, marks: marks, time: 9, mode: "editable_outside_window",
                                reserve: PlaybackSceneRenderBudget.selectedEditableOverlayDraws)
        XCTAssertEqual(outside.admittedMarks, 1)
        XCTAssertTrue(try markEntity(selected, in: root).isEnabled)
        XCTAssertLessThanOrEqual(outside.enabledMarkModels + outside.enabledSelectionModels,
                                 PlaybackSceneRenderBudget.selectedAnnotationSystemDrawLimit)
        frames.append(outside)
        attach(frames, name: "ReplayXI-KeyframedAnnotationDrawBudget-Selected.json")
    }

    func testDecisionBudgetUsesSampledCostAndRetainsSelectionPriority() {
        let marks = fourKeyframedZones()
        let priority = PlaybackSceneRenderBudget.priorityIndices(for: marks)
        for mode in 0..<3 {
            let selected = mode == 0 ? nil : marks[3].id
            let editable = mode == 1
            let reserve = selected == nil ? 0 : (editable
                ? PlaybackSceneRenderBudget.selectedEditableOverlayDraws
                : PlaybackSceneRenderBudget.selectedReadOnlyOverlayDraws)
            for time in [0.0, 1, 2, 3, 4, 2, 0] {
                let visible = PlaybackSceneRenderBudget.visibleAnnotationIDs(
                    in: marks, priorityIndices: priority, at: time, selectedID: selected,
                    selectedIsEditable: editable, decisionReviewIsVisible: true
                )
                let raised = time > 0 && time < 4
                let expectedCount = raised ? 2 : 3
                XCTAssertEqual(visible.count, expectedCount)
                if let selected { XCTAssertTrue(visible.contains(selected)) }
                let cost = marks.reduce(0) { result, mark in
                    result + (visible.contains(mark.id)
                        ? PlaybackSceneRenderBudget.estimatedDraws(for: mark.sampled(at: time)) : 0)
                }
                XCTAssertLessThanOrEqual(cost, PlaybackSceneRenderBudget.decisionAnnotationDrawLimit)
                XCTAssertLessThanOrEqual(cost + reserve, PlaybackSceneRenderBudget.selectedAnnotationSystemDrawLimit)
            }
        }
    }

    func testTimedCostPreservesStaticKindsAndSingleGuideThreshold() {
        for kind in CoachMarkKind.allCases {
            let mark = CoachMark(kind: kind, start: .zero, end: .init(x: 3, z: 4),
                                 startElevation: 2, endElevation: 2, label: "Static")
            XCTAssertEqual(PlaybackSceneRenderBudget.estimatedDraws(for: mark, at: 2),
                           PlaybackSceneRenderBudget.estimatedDraws(for: mark))
        }
        var ground = CoachMark(kind: .run, start: .zero, end: .init(x: 3, z: 4), label: "One guide")
        let raised = CoachMark(id: ground.id, kind: .run, start: ground.start, end: ground.end,
                               startElevation: 2, label: ground.label)
        ground.keyframes = [.init(time: 0, mark: ground), .init(time: 2, mark: raised),
                            .init(time: 4, mark: ground)]
        for (time, cost) in [(0.0, 5), (0.0005, 5), (0.002, 6), (2.0, 6), (4.0, 5), (5.0, 5)] {
            XCTAssertEqual(PlaybackSceneRenderBudget.estimatedDraws(for: ground, at: time), cost)
        }
    }

    private func frame(_ root: Entity, marks: [CoachMark], time: TimeInterval,
                       mode: String, reserve: Int) throws -> Frame {
        let marksRoot = try child("marks-root", in: root)
        let visibleIDs = Set(try marks.filter { try markEntity($0, in: root).isEnabled }.map(\.id))
        // Independent of admission: sample each authored mark before using the
        // established static model-cost function. Do not reuse its base pose.
        let cost = marks.reduce(0) { result, mark in
            result + (visibleIDs.contains(mark.id)
                ? PlaybackSceneRenderBudget.estimatedDraws(for: mark.sampled(at: time)) : 0)
        }
        return Frame(mode: mode, time: time, admittedMarks: visibleIDs.count,
                     enabledMarkModels: enabledModelCount(in: marksRoot),
                     enabledSelectionModels: enabledModelCount(in: try child(AnnotationSceneAffordance.selectionRootName, in: root)),
                     sampledUnfocusedCost: cost, selectionReserve: reserve)
    }

    private func enabledModelCount(in entity: Entity) -> Int {
        guard entity.isEnabled else { return 0 }
        return (entity.components[ModelComponent.self] == nil ? 0 : 1)
            + entity.children.reduce(0) { $0 + enabledModelCount(in: $1) }
    }

    private func fourKeyframedZones() -> [CoachMark] {
        (0..<4).map { index in
            let start = PitchPoint(x: Float(index) * 7 - 14, z: 0)
            let end = PitchPoint(x: start.x + 3, z: 0)
            var ground = CoachMark(kind: .space, start: start, end: end,
                                   label: "Zone \(index)", revealTime: 0, hideTime: 8)
            let raised = CoachMark(id: ground.id, kind: .space, start: start, end: end,
                                   startElevation: 2, endElevation: 2,
                                   label: ground.label, revealTime: 0, hideTime: 8)
            ground.keyframes = [.init(time: 0, mark: ground), .init(time: 2, mark: raised),
                                .init(time: 4, mark: ground)]
            return ground
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
                        selected: UUID? = nil, editable: Bool = false) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: .tacticalTable,
                                 perspectiveID: scenario.defaultPerspectiveID, marks: marks,
                                 selectedAnnotationID: selected, selectedAnnotationIsEditable: editable,
                                 showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
    }

    private func markEntity(_ mark: CoachMark, in root: Entity) throws -> Entity {
        try child("mark-\(mark.id.uuidString)", in: root)
    }

    private func child(_ name: String, in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: name))
    }

    private func attach(_ frames: [Frame], name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let report = Report(frames: frames,
                            qualification: "Native RealityKit enabled ModelComponent counts plus admission and conservative reservation costs. These are model counts, not measured GPU draw calls, CPU timings or headset FPS.")
        guard let data = try? encoder.encode(report) else {
            XCTFail("Could not encode annotation budget evidence")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
