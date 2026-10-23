import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayShapeAnnotationVisibilityTests: XCTestCase {
    func testEveryUserMarkKindIsVisibleAndEditableInBothTabletopStages() throws {
        for stage in ShapeFocusStage.allCases {
            for kind in CoachMarkKind.allCases {
                let store = makeStore(stage: stage)
                let mark = try addMark(kind, to: store)
                let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
                for selected in [false, true] {
                    update(root, from: store, selectedID: selected ? mark.id : nil)
                    let marks = try XCTUnwrap(root.findEntity(named: "marks-root"))
                    let rendered = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
                    XCTAssertTrue(marks.isEnabled, "\(stage) \(kind)")
                    XCTAssertTrue(rendered.isEnabled, "\(stage) \(kind)")
                    XCTAssertTrue(try XCTUnwrap(rendered.findEntity(named: "annotation-label")).isEnabled)
                    XCTAssertEqual(try XCTUnwrap(root.findEntity(
                        named: AnnotationSceneAffordance.selectionRootName
                    )).isEnabled, selected)
                }
            }
        }
    }

    func testPhysicalStationsHideMarksAndRestoreThemAfterEndDrill() throws {
        let store = makeStore(stage: .ideal)
        let mark = try addMark(.run, to: store)
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        store.activateLocalTrianglePreview(anchorID: UUID())
        for placementReady in [true, false, true] {
            update(root, from: store, selectedID: mark.id, placementReady: placementReady)
            XCTAssertEqual(store.triangleLockMode, .place)
            XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "marks-root")).isEnabled,
                           "Tracking loss must not expose annotation geometry during a physical drill")
            XCTAssertFalse(try XCTUnwrap(root.findEntity(
                named: AnnotationSceneAffordance.selectionRootName
            )).isEnabled, "Tracking loss must not reopen direct annotation editing")
        }
        store.endTrianglePlacement()
        update(root, from: store, selectedID: mark.id)
        XCTAssertTrue(try XCTUnwrap(root.findEntity(named: "marks-root")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(root.findEntity(
            named: AnnotationSceneAffordance.selectionRootName
        )).isEnabled)
    }

    func testTimedMarkHidesAndReturnsOnRewindWithoutRebuildingItsEntity() throws {
        let store = makeStore(stage: .ideal)
        let mark = try addMark(.run, to: store)
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        update(root, from: store)
        let rendered = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        XCTAssertTrue(rendered.isEnabled)
        store.seek(to: mark.revealTime + 8, broadcast: false)
        XCTAssertTrue(store.endCoachMarkHere(id: mark.id))
        update(root, from: store)
        XCTAssertFalse(rendered.isEnabled)
        store.seek(to: mark.revealTime, broadcast: false)
        update(root, from: store)
        XCTAssertTrue(rendered.isEnabled)
        XCTAssertTrue(rendered === root.findEntity(named: "mark-\(mark.id.uuidString)"))
    }

    func testSelectingHiddenPresetCannotBringProblemGraphicsIntoIdeal() throws {
        let store = makeStore(stage: .ideal)
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        for preset in store.selectedScenario.coachMarks {
            update(root, from: store, selectedID: preset.id)
            XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "marks-root")).isEnabled)
            XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "mark-\(preset.id.uuidString)")).isEnabled)
            XCTAssertFalse(try XCTUnwrap(root.findEntity(
                named: AnnotationSceneAffordance.selectionRootName
            )).isEnabled)
        }
    }

    func testUserRunAndItsSelectionStayVisibleInIdealWhileAuthoredMarksStayHidden() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "triangle-lock", broadcast: false)
        store.setShapeFocusStage(.ideal, broadcast: false)
        let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rw"))
        let start = store.presentedPlayerPose(for: player, at: store.playhead).position
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(start))
        let userRun = try XCTUnwrap(store.registerPitchTap(
            PitchPoint(x: start.x + 2, z: start.z + 5)
        ))
        XCTAssertTrue(store.saveReview(named: "Ideal teaching run"))
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)

        for selectedID in [nil, userRun.id] as [UUID?] {
            PitchSceneFactory.update(
                root: root, scenario: store.selectedScenario, time: store.playhead,
                viewMode: store.viewMode, perspectiveID: store.activePerspectiveID,
                marks: store.marks,
                selectedAnnotationID: selectedID,
                selectedAnnotationIsEditable: selectedID != nil,
                showsLaneLens: store.showsLaneLens,
                isDrawing: store.isDrawing,
                positionalOriginTransform: nil,
                triangleLockMode: store.triangleLockMode,
                showsIdealBranch: store.showsIdealBranch
            )

            let marks = try XCTUnwrap(root.findEntity(named: "marks-root"))
            XCTAssertTrue(marks.isEnabled, "User-authored marks are valid in Ideal")
            XCTAssertTrue(try XCTUnwrap(
                root.findEntity(named: "mark-\(userRun.id.uuidString)")
            ).isEnabled)
            let selection = try XCTUnwrap(root.findEntity(
                named: AnnotationSceneAffordance.selectionRootName
            ))
            XCTAssertEqual(selection.isEnabled, selectedID != nil)
            for authored in store.selectedScenario.coachMarks {
                XCTAssertFalse(try XCTUnwrap(
                    root.findEntity(named: "mark-\(authored.id.uuidString)")
                ).isEnabled, "The old problem overlays must not return in Ideal")
            }
        }
    }

    private func makeStore(stage: ShapeFocusStage) -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "triangle-lock", broadcast: false)
        store.setShapeFocusStage(stage, broadcast: false)
        return store
    }

    private func addMark(_ kind: CoachMarkKind, to store: ReplayStore) throws -> CoachMark {
        let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rw"))
        if kind == .playerLabel { return try XCTUnwrap(store.labelPlayer(player.id)) }
        let start = store.presentedPlayerPose(for: player, at: store.playhead).position
        store.beginDrawing(kind)
        XCTAssertNil(store.registerPitchTap(start))
        return try XCTUnwrap(store.registerPitchTap(PitchPoint(x: start.x + 2, z: start.z + 5)))
    }

    private func update(
        _ root: Entity, from store: ReplayStore,
        selectedID: UUID? = nil, placementReady: Bool = false
    ) {
        PitchSceneFactory.update(
            root: root, scenario: store.selectedScenario, time: store.playhead,
            viewMode: store.viewMode, perspectiveID: store.activePerspectiveID,
            marks: store.marks, selectedAnnotationID: selectedID,
            selectedAnnotationIsEditable: selectedID != nil,
            showsLaneLens: store.showsLaneLens, isDrawing: store.isDrawing,
            positionalOriginTransform: placementReady ? matrix_identity_float4x4 : nil,
            triangleLockMode: store.triangleLockMode,
            isTrianglePlacementReady: placementReady,
            showsIdealBranch: store.showsIdealBranch
        )
    }
}
