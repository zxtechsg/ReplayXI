import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackSceneBudgetTests: XCTestCase {
    func testDenseMaximumKeyframesMatchLegacyAdmissionWithFewerSamples() {
        let marks = denseKeyframedMarks(count: ReplayStore.maximumSharedCoachMarks)
        XCTAssertEqual(marks.count, 128)
        XCTAssertTrue(marks.allSatisfy { $0.keyframes?.count == CoachMark.maximumKeyframes })
        XCTAssertTrue(CoachMarkKind.allCases.allSatisfy {
            PlaybackSceneRenderBudget.estimatedDraws(for: $0) >= 4
        })
        let priority = PlaybackSceneRenderBudget.priorityIndices(for: marks)
        let allowed = Set(marks.enumerated().compactMap { index, mark in
            index.isMultiple(of: 3) ? nil : mark.id
        })
        let variants: [(selectedID: UUID?, editable: Bool, decision: Bool, filtered: Bool)] = [
            (nil, false, false, false),
            (marks[127].id, true, false, false),
            (marks[127].id, false, true, false),
            (marks[127].id, true, false, true),
        ]
        for variant in variants {
            let isEligible: (CoachMark) -> Bool = { !variant.filtered || allowed.contains($0.id) }
            // The return journey also checks held final keys and hide windows.
            for time in [0.0, 7.75, 15.5, 31.5, 15.5, 7.75, 0.0] {
                let baseline = legacyAdmission(in: marks, priority: priority, at: time,
                    selectedID: variant.selectedID, editable: variant.editable,
                    decision: variant.decision, isEligible: isEligible)
                var samples = 0
                let actual = PlaybackSceneRenderBudget.visibleAnnotationIDs(
                    in: marks, priorityIndices: priority, at: time,
                    selectedID: variant.selectedID, selectedIsEditable: variant.editable,
                    decisionReviewIsVisible: variant.decision,
                    sampledDrawCost: { mark, sampleTime in
                        samples += 1
                        return PlaybackSceneRenderBudget.estimatedDraws(for: mark, at: sampleTime)
                    }, isEligible: isEligible
                )
                XCTAssertEqual(actual, baseline.ids, "time \(time), variant \(variant)")
                XCTAssertLessThan(samples, baseline.samples,
                    "Dense history should stop sampling once no mark can fit")
            }
        }
    }

    func testBaseCostRejectsKeyedDangerBeforeInterpolatingIt() {
        let marks = denseKeyframedMarks(count: 32, kinds: [.danger])
        let priority = PlaybackSceneRenderBudget.priorityIndices(for: marks)
        var samples = 0
        let actual = PlaybackSceneRenderBudget.visibleAnnotationIDs(
            in: marks, priorityIndices: priority, at: 15.5,
            selectedID: nil, selectedIsEditable: false, decisionReviewIsVisible: false,
            sampledDrawCost: { mark, time in
                samples += 1
                return PlaybackSceneRenderBudget.estimatedDraws(for: mark, at: time)
            }
        )
        let baseline = legacyAdmission(in: marks, priority: priority, at: 15.5,
            selectedID: nil, editable: false, decision: false, isEligible: { _ in true })
        XCTAssertEqual(actual, baseline.ids)
        XCTAssertEqual(samples, 1)
        XCTAssertEqual(baseline.samples, marks.count)
    }

    func testEverySelectedAnnotationKindFitsTheFocusedSystemEnvelope() {
        for kind in CoachMarkKind.allCases {
            let selected = CoachMark(
                kind: kind,
                start: PitchPoint(x: 0, z: 0),
                end: PitchPoint(x: 4, z: 6),
                label: "Selected \(kind.title)",
                revealTime: 0,
                hideTime: 8
            )
            let context = CoachMark(
                kind: .space,
                start: PitchPoint(x: 8, z: 8),
                end: PitchPoint(x: 11, z: 8),
                label: "Context",
                revealTime: 0,
                hideTime: 8
            )
            let marks = [selected, context]
            let visible = PlaybackSceneRenderBudget.visibleAnnotationIDs(
                in: marks,
                priorityIndices: PlaybackSceneRenderBudget.priorityIndices(for: marks),
                at: 1,
                selectedID: selected.id,
                selectedIsEditable: true,
                decisionReviewIsVisible: true
            )
            let admittedDraws = PlaybackSceneRenderBudget.estimatedAnnotationDraws(
                for: marks,
                visibleIDs: visible
            )

            XCTAssertTrue(visible.contains(selected.id), kind.title)
            XCTAssertLessThanOrEqual(
                admittedDraws + PlaybackSceneRenderBudget.selectedEditableOverlayDraws,
                PlaybackSceneRenderBudget.selectedAnnotationSystemDrawLimit,
                kind.title
            )
        }
    }

    func testArbitraryAnnotationTextMeshCacheRemainsBounded() {
        for index in 0..<(PlaybackSpatialLabels.maximumCachedTextMeshes + 24) {
            _ = PlaybackSpatialLabels.makeAnnotationTag(
                text: "CACHE \(index)",
                color: .white
            )
        }

        XCTAssertLessThanOrEqual(
            PlaybackSpatialLabels.cachedTextMeshCount,
            PlaybackSpatialLabels.maximumCachedTextMeshes
        )
    }

    func testElevatedAnnotationBudgetMatchesRenderedModels() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for kind in CoachMarkKind.allCases {
            for elevation in [Float(0), Float(2)] {
                let mark = CoachMark(
                    kind: kind,
                    start: PitchPoint(x: 0, z: 0),
                    end: PitchPoint(x: 4, z: 6),
                    startElevation: elevation,
                    endElevation: elevation,
                    label: "Render budget",
                    revealTime: 0
                )
                update(root: root, scenario: scenario, marks: [mark])
                let markRoot = try XCTUnwrap(
                    root.findEntity(named: "mark-\(mark.id.uuidString)")
                )
                XCTAssertEqual(
                    enabledModelCount(in: markRoot),
                    PlaybackSceneRenderBudget.estimatedDraws(for: mark),
                    "\(kind.title), elevation \(elevation)"
                )
            }
        }
    }

    func testDenseElevatedMarksStayInsideActualSceneEnvelope() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let marks = (0..<12).map { index in
            CoachMark(
                kind: .space,
                start: PitchPoint(x: Float(index), z: 0),
                end: PitchPoint(x: Float(index) + 3, z: 0),
                startElevation: 2,
                endElevation: 2,
                label: "Elevated zone",
                revealTime: 0
            )
        }
        update(root: root, scenario: scenario, marks: marks)
        let marksRoot = try XCTUnwrap(root.findEntity(named: "marks-root"))

        XCTAssertEqual(marksRoot.children.filter(\.isEnabled).count, 3)
        XCTAssertLessThanOrEqual(
            enabledModelCount(in: marksRoot),
            PlaybackSceneRenderBudget.normalAnnotationDrawLimit
        )
    }

    func testElevatedSelectedPressFitsIncludingSpatialHandles() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let selected = CoachMark(
            kind: .danger,
            start: PitchPoint(x: 0, z: 0),
            end: PitchPoint(x: 4, z: 6),
            startElevation: 1,
            endElevation: 3,
            label: "Press above pitch",
            revealTime: 0
        )
        update(root: root, scenario: scenario, marks: [selected], selectedID: selected.id)
        let marksRoot = try XCTUnwrap(root.findEntity(named: "marks-root"))
        let selection = try XCTUnwrap(
            root.findEntity(named: AnnotationSceneAffordance.selectionRootName)
        )

        XCTAssertTrue(selection.isEnabled)
        XCTAssertLessThanOrEqual(
            enabledModelCount(in: marksRoot) + enabledModelCount(in: selection),
            PlaybackSceneRenderBudget.selectedAnnotationSystemDrawLimit
        )
    }

    private func update(
        root: Entity,
        scenario: ReplayScenario,
        marks: [CoachMark],
        selectedID: UUID? = nil
    ) {
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 1,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: marks,
            selectedAnnotationID: selectedID,
            selectedAnnotationIsEditable: selectedID != nil,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
    }

    private func enabledModelCount(in entity: Entity) -> Int {
        guard entity.isEnabled else { return 0 }
        return (entity.components[ModelComponent.self] == nil ? 0 : 1)
            + entity.children.reduce(0) { $0 + enabledModelCount(in: $1) }
    }

    private func denseKeyframedMarks(
        count: Int,
        kinds: [CoachMarkKind] = [.run, .pass, .arc, .danger, .space]
    ) -> [CoachMark] {
        (0..<count).map { index in
            let kind = kinds[index % kinds.count]
            let reveal = Double(index % 4) * 0.5
            let hide: TimeInterval? = index.isMultiple(of: 9) ? 20 : nil
            let label = "Keyed \(index)"
            let frames = (0..<CoachMark.maximumKeyframes).map { frame in
                let drift = Float(frame) * 0.004
                let start = PitchPoint(x: -28 + Float(index % 12) * 3 + drift,
                                       z: -40 + Float(index / 12) * 3)
                let end = PitchPoint(x: start.x + 3, z: start.z + 5)
                let elevation: Float = frame.isMultiple(of: 3) ? 0 : 1
                let pose = CoachMark(kind: kind, start: start, end: end,
                    startElevation: elevation,
                    endElevation: kind == .space ? elevation : (frame.isMultiple(of: 2) ? 0 : 1),
                    curve: kind == .arc ? CoachMarkCurve(bend: 0.5, lift: 0.4, rollDegrees: 12) : nil,
                    label: label, revealTime: reveal, hideTime: hide)
                return CoachMarkKeyframe(time: Double(frame) * 0.5, mark: pose)
            }
            let first = frames[0]
            return CoachMark(kind: kind, start: first.start, end: first.end,
                startElevation: first.startElevation, endElevation: first.endElevation,
                curve: first.curve, label: label, revealTime: reveal, hideTime: hide,
                keyframes: frames)
        }
    }

    /// The prior admission loop is the test oracle, including full sampling
    /// after the budget is packed. Keep it independent from the new guards.
    private func legacyAdmission(
        in marks: [CoachMark], priority: [Int], at time: TimeInterval,
        selectedID: UUID?, editable: Bool, decision: Bool,
        isEligible: (CoachMark) -> Bool
    ) -> (ids: Set<UUID>, samples: Int) {
        let selected = selectedID.flatMap { id in
            marks.first { $0.id == id && isEligible($0) && ($0.isVisible(at: time) || editable) }
        }
        let baseLimit = decision ? PlaybackSceneRenderBudget.decisionAnnotationDrawLimit
            : PlaybackSceneRenderBudget.normalAnnotationDrawLimit
        let reserve = selected == nil ? 0 : (editable
            ? PlaybackSceneRenderBudget.selectedEditableOverlayDraws
            : PlaybackSceneRenderBudget.selectedReadOnlyOverlayDraws)
        let limit = min(baseLimit, max(PlaybackSceneRenderBudget.selectedAnnotationSystemDrawLimit - reserve, 0))
        guard limit > 0 else { return ([], 0) }
        var ids: Set<UUID> = []
        var consumed = 0
        var samples = 0
        if let selected {
            ids.insert(selected.id)
            samples += 1
            consumed += PlaybackSceneRenderBudget.estimatedDraws(for: selected, at: time)
        }
        for index in priority {
            guard marks.indices.contains(index) else { continue }
            let mark = marks[index]
            guard mark.id != selected?.id, isEligible(mark), mark.isVisible(at: time) else { continue }
            samples += 1
            let cost = PlaybackSceneRenderBudget.estimatedDraws(for: mark, at: time)
            guard consumed + cost <= limit else { continue }
            ids.insert(mark.id)
            consumed += cost
        }
        return (ids, samples)
    }
}
