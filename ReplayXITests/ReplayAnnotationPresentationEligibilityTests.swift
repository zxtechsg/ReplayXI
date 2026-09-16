import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAnnotationPresentationEligibilityTests: XCTestCase {
    func testShapePresetIndexMatchesTheActualSceneInBothComparisonStages() throws {
        for stage in ShapeFocusStage.allCases {
            let store = makeShape(stage: stage)
            store.seek(to: 16, broadcast: false)
            let context = presentation(store)
            let indexedIDs = Set(context.orderedReviewMarks(store.marks, in: store.selectedScenario).map(\.id))
            let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
            for mark in store.selectedScenario.coachMarks {
                update(root, from: store, selected: mark)
                let sceneMark = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
                let shouldAppear = stage == .problem && mark.kind == .danger
                XCTAssertEqual(context.isEligible(mark, in: store.selectedScenario), shouldAppear)
                XCTAssertEqual(sceneMark.isEnabled, shouldAppear)
                XCTAssertEqual(indexedIDs.contains(mark.id), sceneMark.isEnabled,
                               "\(stage): the timeline must not offer a preset this scene cannot show")
            }
        }
    }

    func testSelectedProblemPressureClosesInIdealAndDoesNotResurrectOnReturn() throws {
        let store = makeShape(stage: .problem)
        let pressure = try XCTUnwrap(store.selectedScenario.coachMarks.first { $0.kind == .danger })
        var selection: UUID? = pressure.id
        let initialVersion = store.reviewIndexVersion
        let initialContext = presentation(store)
        XCTAssertEqual(reconciled(selection, in: store), pressure.id)

        store.setShapeFocusStage(.ideal, broadcast: false)
        XCTAssertNotEqual(presentation(store), initialContext)
        XCTAssertEqual(store.reviewIndexVersion, initialVersion,
                       "A stage change needs context invalidation, not a mark-metadata update")
        XCTAssertTrue(pressure.isVisible(at: store.playhead), "Time-only cleanup cannot solve this case")
        selection = reconciled(selection, in: store)
        XCTAssertNil(selection)

        store.setShapeFocusStage(.problem, broadcast: false)
        selection = reconciled(selection, in: store)
        XCTAssertNil(selection, "Returning to Problem must not reopen a selection that was closed")
    }

    func testShapeViewChangesReindexPresetsButKeepThePlayerBoundUserMark() throws {
        let store = makeShape(stage: .problem)
        let userMark = try addUserMark(.run, to: store)
        let presetPass = try XCTUnwrap(store.selectedScenario.coachMarks.first { $0.kind == .pass })
        let committedMarks = store.marks
        let committedGeometry = store.presentedCoachMarkGeometry(userMark, at: store.playhead)
        let originalVersion = store.reviewIndexVersion
        store.setViewMode(.tacticalTable, broadcast: false)
        let fullContext = presentation(store)
        XCTAssertEqual(fullContext.orderedReviewMarks(store.marks, in: store.selectedScenario).count,
                       committedMarks.count)
        XCTAssertEqual(reconciled(presetPass.id, in: store), presetPass.id)

        store.setViewMode(.positional, broadcast: false)
        let shapeContext = presentation(store)
        XCTAssertNotEqual(shapeContext, fullContext)
        let shapeIDs = Set(shapeContext.orderedReviewMarks(store.marks, in: store.selectedScenario).map(\.id))
        for preset in store.selectedScenario.coachMarks {
            XCTAssertEqual(shapeIDs.contains(preset.id), preset.kind == .danger)
        }
        XCTAssertTrue(shapeIDs.contains(userMark.id))
        XCTAssertNil(reconciled(presetPass.id, in: store))
        XCTAssertEqual(reconciled(userMark.id, in: store), userMark.id)
        XCTAssertEqual(store.presentedCoachMarkGeometry(userMark, at: store.playhead), committedGeometry)
        XCTAssertEqual(store.marks, committedMarks)
        XCTAssertEqual(store.reviewIndexVersion, originalVersion)

        store.setViewMode(.tacticalTable, broadcast: false)
        XCTAssertEqual(presentation(store).orderedReviewMarks(store.marks, in: store.selectedScenario).count,
                       committedMarks.count)
    }

    func testLogicalPhysicalPlacementHidesIndexedMarksEvenWhenTrackingIsNotReady() throws {
        let store = makeShape(stage: .ideal)
        let userMark = try addUserMark(.run, to: store)
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        store.activateLocalTrianglePreview(anchorID: UUID())
        XCTAssertEqual(store.triangleLockMode, .place)
        let context = presentation(store)
        XCTAssertTrue(context.orderedReviewMarks(store.marks, in: store.selectedScenario).isEmpty)
        for ready in [true, false, true] {
            for mark in store.marks {
                XCTAssertFalse(context.isEligible(mark, in: store.selectedScenario))
            }
            update(root, from: store, selected: userMark, placementReady: ready)
            XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "marks-root")).isEnabled)
            XCTAssertFalse(try XCTUnwrap(root.findEntity(named: AnnotationSceneAffordance.selectionRootName)).isEnabled)
        }
        store.endTrianglePlacement()
        let restoredIDs = presentation(store).orderedReviewMarks(store.marks, in: store.selectedScenario).map(\.id)
        XCTAssertEqual(restoredIDs, [userMark.id])
        XCTAssertTrue(store.marks.contains(userMark))
    }

    func testEveryUserMarkKindAndFutureTimestampStayIndexedWithoutMutatingSavedData() throws {
        for stage in ShapeFocusStage.allCases {
            let store = makeShape(stage: stage)
            var userMarks: [CoachMark] = []
            for kind in CoachMarkKind.allCases {
                userMarks.append(try addUserMark(kind, to: store))
            }
            let committedMarks = store.marks
            XCTAssertTrue(store.saveReview(named: "Eligible user instructions"))
            let saved = try XCTUnwrap(store.savedReviews.first)
            store.seek(to: 0, broadcast: false)
            let context = presentation(store)
            let indexed = Set(context.orderedReviewMarks(store.marks, in: store.selectedScenario).map(\.id))
            for mark in userMarks {
                XCTAssertFalse(mark.isVisible(at: store.playhead))
                XCTAssertTrue(context.isEligible(mark, in: store.selectedScenario))
                XCTAssertTrue(indexed.contains(mark.id), "Future times remain navigable")
                XCTAssertEqual(reconciled(mark.id, in: store), mark.id,
                               "Editable user selection stays available outside its time window")
            }
            XCTAssertEqual(store.marks, committedMarks)
            XCTAssertEqual(store.savedReviews.first, saved)
        }
    }

    func testHeldScrubAndEndpointRejectContextChangesWithoutCancellingTheirTransactions() throws {
        let store = makeShape(stage: .problem)
        let mark = try addUserMark(.run, to: store)
        let context = presentation(store)
        let geometry = store.presentedCoachMarkGeometry(mark, at: store.playhead)
        XCTAssertTrue(store.updateCoachMarkGeometry(
            id: mark.id, start: geometry.start,
            end: PitchPoint(x: geometry.end.x + 0.25, z: geometry.end.z), broadcast: false
        ))
        let preview = store.marks
        store.setShapeFocusStage(.ideal, broadcast: false)
        store.setViewMode(.firstPerson, broadcast: false)
        XCTAssertEqual(presentation(store), context)
        XCTAssertEqual(reconciled(mark.id, in: store), mark.id)
        XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertEqual(store.marks, preview)
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertEqual(store.marks.last, mark)

        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: store.playhead + 0.5))
        let previewTime = store.playhead
        store.setShapeFocusStage(.ideal, broadcast: false)
        store.setViewMode(.tacticalTable, broadcast: false)
        XCTAssertEqual(presentation(store), context)
        XCTAssertEqual(reconciled(mark.id, in: store), mark.id)
        XCTAssertEqual(store.playhead, previewTime)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        store.cancelTimelineScrub()
        XCTAssertEqual(reconciled(mark.id, in: store), mark.id)
        XCTAssertTrue(store.canChangePlaybackView)
    }

    func testHiddenSelectionCleanupDefersDuringScrubThenRechecksWithoutChangingReplayState() throws {
        let store = makeShape(stage: .problem)
        let pressure = try XCTUnwrap(store.selectedScenario.coachMarks.first { $0.kind == .danger })
        var selection: UUID? = pressure.id
        store.setShapeFocusStage(.ideal, broadcast: false)
        let context = presentation(store)
        XCTAssertFalse(context.isEligible(pressure, in: store.selectedScenario))
        let committedTime = store.playhead
        let marks = store.marks
        let version = store.reviewIndexVersion

        // Exercise the observer barrier directly: if another input transaction
        // owns the deck before cleanup runs, selection must wait for release.
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: committedTime + 0.5))
        let previewTime = store.playhead
        XCTAssertFalse(store.canChangePlaybackView)
        selection = reconciled(selection, in: store)
        XCTAssertEqual(selection, pressure.id)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.playhead, previewTime)
        XCTAssertEqual(store.marks, marks)

        store.cancelTimelineScrub()
        XCTAssertTrue(store.canChangePlaybackView)
        selection = reconciled(selection, in: store)
        XCTAssertNil(selection)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.playhead, committedTime)
        XCTAssertEqual(store.marks, marks)
        XCTAssertEqual(store.reviewIndexVersion, version)
        XCTAssertEqual(presentation(store), context)
    }

    func testAllNormalMatchViewsKeepTheFullMarkOrderAndAllCueData() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let userMark = try addUserMark(.run, to: store)
        let expected = store.marks.sorted {
            $0.revealTime == $1.revealTime ? $0.id.uuidString < $1.id.uuidString : $0.revealTime < $1.revealTime
        }
        let cues = store.selectedScenario.moments
        for view in [ReplayViewMode.firstPerson, .tacticalTable, .touchline] {
            store.setViewMode(view, broadcast: false)
            let context = presentation(store)
            XCTAssertEqual(context.orderedReviewMarks(store.marks, in: store.selectedScenario), expected)
            for mark in store.marks {
                XCTAssertTrue(context.isEligible(mark, in: store.selectedScenario))
                XCTAssertEqual(reconciled(mark.id, in: store), mark.id)
            }
            XCTAssertEqual(store.selectedScenario.moments, cues)
            XCTAssertTrue(store.marks.contains(userMark))
        }
    }

    func testSceneAndCommonDeckShareTheContextWithoutCancellingInputOrFilteringCues() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let ui = try String(contentsOf: project.appendingPathComponent("ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let factory = try String(contentsOf: project.appendingPathComponent("ReplayXI/Immersive/PitchSceneFactory.swift"), encoding: .utf8)
        XCTAssertTrue(factory.contains("annotationPresentation.isEligible(mark, in: scenario)"))
        XCTAssertTrue(factory.contains("triangleLockMode: triangleLockMode"))
        XCTAssertTrue(ui.contains(".onChange(of: annotationPresentation)"))
        XCTAssertTrue(ui.contains(".onChange(of: store.canChangePlaybackView)"))
        let index = try slice(ui, after: "private func rebuildReviewIndex()", before: "private func reconcileAnnotationPresentationSelection()")
        XCTAssertTrue(index.contains("annotationPresentation.orderedReviewMarks("))
        XCTAssertTrue(index.contains("store.selectedScenario.moments.map(PlaybackReviewEvent.cue)"))
        let cleanup = try slice(ui, after: "private func reconcileAnnotationPresentationSelection()", before: "private func rebuildTimelineTickClusters(")
        XCTAssertTrue(cleanup.contains("canChangePlaybackView: store.canChangePlaybackView"))
        XCTAssertFalse(cleanup.contains("cancel"))
        XCTAssertFalse(cleanup.contains("store.seek"))
        XCTAssertFalse(cleanup.contains("store.marks ="))
    }

    private func presentation(_ store: ReplayStore) -> PlaybackAnnotationPresentation {
        PlaybackAnnotationPresentation(viewMode: store.viewMode, triangleLockMode: store.triangleLockMode,
                                       showsIdealBranch: store.showsIdealBranch)
    }

    private func reconciled(_ id: UUID?, in store: ReplayStore) -> UUID? {
        presentation(store).reconciledSelection(id, marks: store.marks, scenario: store.selectedScenario,
                                              canChangePlaybackView: store.canChangePlaybackView)
    }

    private func makeShape(stage: ShapeFocusStage) -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "triangle-lock", broadcast: false)
        store.setShapeFocusStage(stage, broadcast: false)
        return store
    }

    private func addUserMark(_ kind: CoachMarkKind, to store: ReplayStore) throws -> CoachMark {
        let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rw"))
        if kind == .playerLabel { return try XCTUnwrap(store.labelPlayer(player.id)) }
        let start = store.presentedPlayerPose(for: player, at: store.playhead).position
        store.beginDrawing(kind)
        XCTAssertNil(store.registerPitchTap(start))
        return try XCTUnwrap(store.registerPitchTap(PitchPoint(x: start.x + 2, z: start.z + 5)))
    }

    private func update(_ root: Entity, from store: ReplayStore, selected: CoachMark, placementReady: Bool = false) {
        PitchSceneFactory.update(
            root: root, scenario: store.selectedScenario, time: store.playhead,
            viewMode: store.viewMode, perspectiveID: store.activePerspectiveID,
            marks: store.marks, selectedAnnotationID: selected.id,
            selectedAnnotationIsEditable: !store.selectedScenario.coachMarks.contains { $0.id == selected.id },
            showsLaneLens: store.showsLaneLens, isDrawing: store.isDrawing,
            positionalOriginTransform: placementReady ? matrix_identity_float4x4 : nil,
            triangleLockMode: store.triangleLockMode, isTrianglePlacementReady: placementReady,
            showsIdealBranch: store.showsIdealBranch
        )
    }

    private func slice(_ source: String, after startMarker: String, before endMarker: String) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker)?.upperBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return source[start..<end]
    }
}
