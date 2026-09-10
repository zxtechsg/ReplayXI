import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackSceneBudgetTests: XCTestCase {
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
}
