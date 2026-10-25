import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayPresentedPlayerAlignmentTests: XCTestCase {
    private func focusScenario() throws -> ReplayScenario {
        try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
    }

    private func assertXZ(
        _ actual: SIMD3<Float>, _ expected: PitchPoint,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.000_1, file: file, line: line)
    }

    func testImpactPresentationSharesHeldPositionRecoveryAndExactRewind() throws {
        let scenario = try focusScenario()
        let player = try XCTUnwrap(scenario.player(id: "red-lb"))
        let cue = try XCTUnwrap(PlayerRagdollCue.authoredDemo(for: scenario))
        let context = ReplayPlayerPresentation(scenario: scenario, viewMode: .tacticalTable)
        let held = context.pose(for: player, at: 15.5)
        let raw = player.presentationPose(at: 15.5)
        XCTAssertGreaterThan(ReplayGeometry.distance(held.position, raw.position), 6.6)
        XCTAssertEqual(held, player.presentationPose(at: cue.impactTime))

        let recovering = context.pose(for: player, at: 16)
        let expected = player.presentationPose(at: cue.impactTime).position.interpolated(
            to: player.presentationPose(at: 16).position,
            fraction: cue.telemetryRelease(at: 16)
        )
        XCTAssertEqual(recovering.position, expected)
        XCTAssertEqual(context.pose(for: player, at: cue.endTime), player.presentationPose(at: cue.endTime))
        XCTAssertEqual(context.pose(for: player, at: 15.5), held)
        XCTAssertEqual(context.pose(for: player, at: 12), player.presentationPose(at: 12))
    }

    func testPOVRemainsUprightUnlessImpactIsExplicitlyRequested() throws {
        let scenario = try focusScenario()
        let player = try XCTUnwrap(scenario.player(id: "red-lb"))
        let cue = try XCTUnwrap(PlayerRagdollCue.authoredDemo(for: scenario))
        let normal = ReplayPlayerPresentation(scenario: scenario, viewMode: .firstPerson)
        let explicit = ReplayPlayerPresentation(
            scenario: scenario, viewMode: .firstPerson, impactCue: cue
        )
        XCTAssertNil(normal.impactCue)
        XCTAssertEqual(normal.pose(for: player, at: 15), player.presentationPose(at: 15))
        XCTAssertEqual(explicit.pose(for: player, at: 15), player.presentationPose(at: cue.impactTime))
        for unaffected in scenario.players where unaffected.id != player.id {
            XCTAssertEqual(explicit.pose(for: unaffected, at: 15), unaffected.presentationPose(at: 15))
        }
    }

    func testSceneBodyNumberPlayerLabelAndRunStayTogetherThroughImpactAndRewind() throws {
        let scenario = try focusScenario()
        let player = try XCTUnwrap(scenario.player(id: "red-lb"))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let origin = player.presentationPose(at: 13).position
        let offset = PitchPoint(x: -3, z: 4)
        let run = CoachMark(
            kind: .run, start: origin,
            end: PitchPoint(x: origin.x + offset.x, z: origin.z + offset.z),
            label: "Recover inside", revealTime: 12,
            startTrackAnchor: CoachMarkTrackAnchor(playerID: player.id),
            endTrackAnchor: CoachMarkTrackAnchor(playerID: player.id, offset: offset)
        )
        let label = CoachMark(
            kind: .playerLabel, start: origin, end: origin,
            label: "#3 Left back", revealTime: 12, playerID: player.id
        )
        let context = ReplayPlayerPresentation(scenario: scenario, viewMode: .tacticalTable)
        var retainedSegment: Entity?
        for time in [13.0, 14.5, 15.5, 16.0, 16.35, 12.0, 15.5] {
            PitchSceneFactory.update(
                root: root, scenario: scenario, time: time,
                viewMode: .tacticalTable, perspectiveID: player.id,
                marks: [run, label], showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: nil
            )
            let expected = context.pose(for: player, at: time).position
            let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            let number = try XCTUnwrap(root.findEntity(named: "player-label-\(player.id)"))
            assertXZ(body.position, expected)
            XCTAssertFalse(number.isEnabled, "The named coach card replaces the ordinary number tag")

            let labelRoot = try XCTUnwrap(root.findEntity(named: "mark-\(label.id.uuidString)"))
            let labelCard = try XCTUnwrap(labelRoot.findEntity(named: "annotation-label"))
            assertXZ(labelCard.position, expected)
            let runRoot = try XCTUnwrap(root.findEntity(named: "mark-\(run.id.uuidString)"))
            let arrow = try XCTUnwrap(runRoot.findEntity(named: "annotation-mark-arrow"))
            assertXZ(arrow.position, PitchPoint(x: expected.x + offset.x, z: expected.z + offset.z))
            let segment = try XCTUnwrap(runRoot.findEntity(named: "annotation-mark-segment-0"))
            assertXZ(segment.position, PitchPoint(x: expected.x + offset.x / 2, z: expected.z + offset.z / 2))
            if let retainedSegment { XCTAssertTrue(retainedSegment === segment) }
            retainedSegment = segment
        }
    }

    func testIdealShapeNumbersFollowTheDisplayedTargetsAndReturnToProblem() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for ideal in [false, true, false] {
            let time = ideal ? ShapeFocusStage.ideal.referenceTime : ShapeFocusStage.problem.referenceTime
            let context = ReplayPlayerPresentation(
                scenario: scenario, viewMode: .positional, showsIdealBranch: ideal
            )
            PitchSceneFactory.update(
                root: root, scenario: scenario, time: time,
                viewMode: .positional, perspectiveID: scenario.defaultPerspectiveID,
                marks: scenario.coachMarks, showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: nil, showsIdealBranch: ideal
            )
            for target in scenario.formationTargets {
                let player = try XCTUnwrap(scenario.player(id: target.playerID))
                let expected = context.pose(for: player, at: time).position
                let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
                let number = try XCTUnwrap(root.findEntity(named: "player-label-\(player.id)"))
                XCTAssertTrue(body.isEnabled)
                XCTAssertTrue(number.isEnabled)
                assertXZ(body.position, expected)
                assertXZ(number.position, expected)
                if ideal { XCTAssertEqual(expected, target.position) }
            }
        }
    }

    private func impactStore() -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "everyone-with-seven", broadcast: false)
        store.setViewMode(.tacticalTable, broadcast: false)
        store.seek(to: 15, broadcast: false)
        return store
    }

    private func drawImpactRun(in store: ReplayStore) throws -> CoachMark {
        let player = try XCTUnwrap(store.selectedScenario.player(id: "red-lb"))
        let origin = store.presentedPlayerPose(for: player, at: store.playhead).position
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(origin))
        let created = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: origin.x - 3, z: origin.z + 4)))
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: player.id))
        return try XCTUnwrap(store.marks.first { $0.id == created.id })
    }

    func testNewLabelsAndRunSnapToFallenPlayerInsteadOfUprightTelemetry() throws {
        let store = impactStore()
        let player = try XCTUnwrap(store.selectedScenario.player(id: "red-lb"))
        let origin = store.presentedPlayerPose(for: player, at: store.playhead).position
        XCTAssertGreaterThan(ReplayGeometry.distance(origin, player.presentationPose(at: 15).position), 5)
        let label = try XCTUnwrap(store.labelPlayer(player.id))
        XCTAssertEqual(label.start, origin)
        XCTAssertEqual(store.presentedCoachMarkGeometry(label, at: 15).start, origin)
        let run = try drawImpactRun(in: store)
        XCTAssertEqual(run.startTrackAnchor, CoachMarkTrackAnchor(playerID: player.id))
        XCTAssertEqual(run.endTrackAnchor?.playerID, player.id)
        XCTAssertEqual(store.presentedCoachMarkGeometry(run, at: 15).start, origin)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertTrue(store.saveReview(named: "Impact marks"))
        let savedID = try XCTUnwrap(store.savedReviews.first?.id)
        store.seek(to: 20)
        XCTAssertTrue(store.restoreSavedReview(id: savedID))
        XCTAssertEqual(store.presentedCoachMarkGeometry(run, at: store.playhead).start, origin)
    }

    func testImpactTrackingToggleAndDirectHandleEditKeepDisplayedEndpoints() throws {
        let store = impactStore()
        let run = try drawImpactRun(in: store)
        let before = store.presentedCoachMarkGeometry(run, at: 15)
        XCTAssertTrue(store.setCoachMarkTracking(id: run.id, playerID: nil))
        var current = try XCTUnwrap(store.marks.first { $0.id == run.id })
        XCTAssertEqual(current.start, before.start)
        XCTAssertEqual(current.end, before.end)
        XCTAssertTrue(store.setCoachMarkTracking(id: run.id, playerID: "red-lb"))
        current = try XCTUnwrap(store.marks.first { $0.id == run.id })
        XCTAssertEqual(store.presentedCoachMarkGeometry(current, at: 15), before)

        let newEnd = PitchPoint(x: before.end.x - 0.5, z: before.end.z + 0.5)
        XCTAssertTrue(store.updateCoachMarkGeometry(
            id: run.id, start: before.start, end: newEnd, broadcast: false
        ))
        XCTAssertTrue(store.updateCoachMarkGeometry(
            id: run.id, start: before.start, end: newEnd, broadcast: true
        ))
        current = try XCTUnwrap(store.marks.first { $0.id == run.id })
        XCTAssertEqual(store.presentedCoachMarkGeometry(current, at: 15).end, newEnd)
        XCTAssertTrue(store.undoAnnotationEdit())
        current = try XCTUnwrap(store.marks.first { $0.id == run.id })
        XCTAssertEqual(store.presentedCoachMarkGeometry(current, at: 15), before)
    }

    func testImpactJoystickCommitUsesPresentedBaselineAndPreservesTracking() throws {
        let store = impactStore()
        let run = try drawImpactRun(in: store)
        let before = store.presentedCoachMarkGeometry(run, at: 15)
        let gesture = UUID()
        let delta = PitchPoint(x: -0.5, z: 0.5)
        XCTAssertNotNil(store.previewCoachMarkEndpoint(
            id: run.id, endpoint: .end, gestureID: gesture, cumulativeDelta: delta
        ))
        XCTAssertNotNil(store.commitCoachMarkEndpointPreview(id: run.id))
        let after = try XCTUnwrap(store.marks.first { $0.id == run.id })
        XCTAssertEqual(after.startTrackAnchor?.playerID, "red-lb")
        let resolved = store.presentedCoachMarkGeometry(after, at: 15)
        XCTAssertEqual(resolved.start, before.start)
        XCTAssertEqual(resolved.end.x, before.end.x + delta.x, accuracy: 0.000_1)
        XCTAssertEqual(resolved.end.z, before.end.z + delta.z, accuracy: 0.000_1)
    }

    func testImpactSidelineRunCanBeEditedSavedAndRestored() throws {
        let store = impactStore()
        let player = try XCTUnwrap(store.selectedScenario.player(id: "red-lb"))
        let origin = store.presentedPlayerPose(for: player, at: 15).position
        store.beginDrawing(.run)
        _ = store.registerPitchTap(origin)
        let created = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 33.5, z: 29)))
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: player.id))
        let mark = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertGreaterThan(
            mark.resolvedGeometry(in: store.selectedScenario, at: 15).end.x,
            ReplayStore.pitchHalfWidth,
            "This is the raw-telemetry validation edge; the displayed mark remains in bounds"
        )
        XCTAssertEqual(store.presentedCoachMarkGeometry(mark, at: 15).end.x, 33.5)
        XCTAssertTrue(ReplayStore.isValidReviewMark(mark, for: store.selectedScenario))
        XCTAssertTrue(store.nudgeCoachMarkEndpoint(
            id: mark.id, endpoint: .end, by: PitchPoint(x: -0.25, z: 0)
        ))
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertTrue(store.saveReview(named: "Sideline impact run"))
        let savedID = try XCTUnwrap(store.savedReviews.first?.id)
        store.seek(to: 20)
        XCTAssertTrue(store.restoreSavedReview(id: savedID))
        let restored = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(store.presentedCoachMarkGeometry(restored, at: 15).end.x, 33.25)
    }

    func testIdealShapeBoundRunCanBeSavedAtThePitchBoundary() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "triangle-lock", broadcast: false)
        store.setShapeFocusStage(.ideal, broadcast: false)
        let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
        let origin = store.presentedPlayerPose(for: player, at: store.playhead).position
        store.beginDrawing(.run)
        _ = store.registerPitchTap(origin)
        let created = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: origin.x, z: 52)))
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: player.id))
        let mark = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertGreaterThan(
            mark.resolvedGeometry(in: store.selectedScenario, at: store.playhead).end.z,
            ReplayStore.pitchHalfLength
        )
        XCTAssertEqual(store.presentedCoachMarkGeometry(mark, at: store.playhead).end.z, 52)
        XCTAssertTrue(ReplayStore.isValidReviewMark(mark, for: store.selectedScenario))
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertTrue(store.saveReview(named: "Ideal shape boundary"))
    }

    func testUnlinkingImpactBoundaryRunLaterPreservesSaveableHistory() throws {
        let store = impactStore()
        let player = try XCTUnwrap(store.selectedScenario.player(id: "red-lb"))
        let origin = store.presentedPlayerPose(for: player, at: 15).position
        store.beginDrawing(.run)
        _ = store.registerPitchTap(origin)
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: 33.5, z: 29)))
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: player.id))
        let original = try XCTUnwrap(store.marks.first { $0.id == created.id })
        let earlier = store.presentedCoachMarkGeometry(original, at: 15)

        store.seek(to: 15.5, broadcast: false)
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil))
        let unlinked = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertFalse(unlinked.followsPlayerTracks)
        XCTAssertTrue(unlinked.sampled(at: 15).followsPlayerTracks)
        XCTAssertEqual(store.presentedCoachMarkGeometry(unlinked, at: 15), earlier)
        XCTAssertTrue(ReplayStore.isValidReviewMark(unlinked, for: store.selectedScenario))
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertTrue(store.saveReview(named: "Unlinked impact boundary"))
        try assertDiskRoundTrip(store, mark: unlinked)
    }

    func testUnlinkingIdealBoundaryRunLaterPreservesSaveableHistory() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "triangle-lock", broadcast: false)
        store.setShapeFocusStage(.ideal, broadcast: false)
        let revealTime = store.playhead
        let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
        let origin = store.presentedPlayerPose(for: player, at: revealTime).position
        store.beginDrawing(.run)
        _ = store.registerPitchTap(origin)
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: origin.x, z: 52)))
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: player.id))
        store.seek(to: revealTime + 0.5, broadcast: false)
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil))
        let unlinked = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertFalse(unlinked.followsPlayerTracks)
        XCTAssertTrue(unlinked.sampled(at: revealTime).followsPlayerTracks)
        XCTAssertTrue(ReplayStore.isValidReviewMark(unlinked, for: store.selectedScenario))
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertTrue(store.saveReview(named: "Unlinked ideal boundary"))
        try assertDiskRoundTrip(store, mark: unlinked)
    }

    func testIdealPlayerLabelValidationKeepsItsAttachedIdentity() throws {
        let source = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let target = try XCTUnwrap(source.formationTargets.first)
        let original = try XCTUnwrap(source.player(id: target.playerID))
        // A raw track outside the pitch must still use the exact authored
        // ideal target for its label, never a position supplied by the mark.
        let player = PlayerTrack(id: original.id, displayName: original.displayName,
            role: original.role, shirtNumber: original.shirtNumber, team: original.team,
            isGoalkeeper: original.isGoalkeeper,
            keyframes: [.init(time: 0, position: .init(x: 35, z: 0), facingDegrees: 0)])
        let scenario = ReplayScenario(id: source.id, kind: source.kind, title: source.title,
            strapline: source.strapline, matchContext: source.matchContext, objective: source.objective,
            coachPrompt: source.coachPrompt, proofPoint: source.proofPoint, duration: source.duration,
            defaultViewMode: source.defaultViewMode, defaultPerspectiveID: player.id,
            featuredPerspectiveIDs: [player.id], players: [player], ball: source.ball,
            moments: [], coachMarks: [], formationTargets: source.formationTargets)
        let label = CoachMark(kind: .playerLabel, start: target.position, end: target.position,
            label: "Authored target", revealTime: 0, playerID: player.id)
        XCTAssertGreaterThan(label.resolvedGeometry(in: scenario, at: 0).start.x, ReplayStore.pitchHalfWidth)
        XCTAssertTrue(ReplayStore.isValidReviewMark(label, for: scenario))
    }

    private func assertDiskRoundTrip(_ store: ReplayStore, mark: CoachMark) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("reviews.json")
        let library = ReplayReviewLibrary(scenarios: store.scenarios, fileURL: url)
        XCTAssertTrue(library.save(named: "Unlinked history", state: store.makeSavedReviewState()))
        let reopened = ReplayReviewLibrary(scenarios: store.scenarios, fileURL: url)
        let saved = try XCTUnwrap(reopened.savedReviews.first)
        XCTAssertEqual(saved.state.marks.first { $0.id == mark.id }, mark)
        let restored = ReplayStore(scenarios: store.scenarios, reviewLibrary: reopened)
        XCTAssertTrue(restored.restoreSavedReview(id: saved.id))
        let restoredMark = try XCTUnwrap(restored.marks.first { $0.id == mark.id })
        XCTAssertEqual(restoredMark, mark)
        for time in [mark.revealTime, store.playhead] {
            XCTAssertEqual(restored.presentedCoachMarkGeometry(restoredMark, at: time),
                           store.presentedCoachMarkGeometry(mark, at: time))
        }
    }

    func testAuthoredPresentationNeverAdmitsInvalidIdentityOrUnboundedOffsets() throws {
        let scenario = try focusScenario()
        let player = try XCTUnwrap(scenario.player(id: "red-lb"))
        let context = ReplayPlayerPresentation(scenario: scenario, viewMode: .tacticalTable)
        let origin = context.pose(for: player, at: 15).position

        func mark(offset: PitchPoint, playerID: String = "red-lb", time: TimeInterval = 15) -> CoachMark {
            CoachMark(
                kind: .run, start: origin, end: PitchPoint(x: 33.5, z: 29),
                label: "Boundary", revealTime: time,
                startTrackAnchor: CoachMarkTrackAnchor(playerID: "red-lb"),
                endTrackAnchor: CoachMarkTrackAnchor(playerID: playerID, offset: offset)
            )
        }
        for invalid in [
            PitchPoint(x: .nan, z: 0),
            PitchPoint(x: .infinity, z: 0),
            PitchPoint(x: 0, z: -.infinity),
            PitchPoint(x: ReplayStore.pitchHalfWidth * 2 + 0.01, z: 0),
            PitchPoint(x: 0, z: ReplayStore.pitchHalfLength * 2 + 0.01),
            PitchPoint(x: 8, z: 0), // Finite but off pitch in every allowed context.
        ] {
            XCTAssertFalse(ReplayStore.isValidReviewMark(mark(offset: invalid), for: scenario))
        }
        let legalOffset = PitchPoint(x: 33.5 - origin.x, z: 29 - origin.z)
        XCTAssertFalse(ReplayStore.isValidReviewMark(
            mark(offset: legalOffset, playerID: "missing-player"), for: scenario
        ))
        XCTAssertFalse(ReplayStore.isValidReviewMark(
            mark(offset: legalOffset, time: .nan), for: scenario
        ))
        let cue = try XCTUnwrap(PlayerRagdollCue.authoredDemo(for: scenario))
        XCTAssertFalse(ReplayStore.isValidReviewMark(
            mark(offset: legalOffset, time: cue.endTime), for: scenario
        ), "An inactive contact must not supply an alternative validation origin")
        let uncuedScenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        XCTAssertFalse(ReplayStore.isValidReviewMark(mark(offset: legalOffset), for: uncuedScenario))
    }

    func testLegacyRawTelemetryAcceptanceAndStoredFallbackBoundsArePreserved() throws {
        let scenario = try focusScenario()
        let player = try XCTUnwrap(scenario.player(id: "red-lb"))
        let raw = player.presentationPose(at: 15).position
        let legacy = CoachMark(
            kind: .run, start: raw, end: PitchPoint(x: -33.5, z: raw.z),
            label: "Legacy telemetry", revealTime: 15,
            startTrackAnchor: CoachMarkTrackAnchor(playerID: player.id),
            endTrackAnchor: CoachMarkTrackAnchor(
                playerID: player.id, offset: PitchPoint(x: -33.5 - raw.x, z: 0)
            )
        )
        let context = ReplayPlayerPresentation(scenario: scenario, viewMode: .tacticalTable)
        XCTAssertLessThan(legacy.resolvedGeometry(
            in: scenario, at: 15, presentedPlayerPoses: context.poses(in: scenario, at: 15)
        ).end.x, -ReplayStore.pitchHalfWidth)
        XCTAssertTrue(ReplayStore.isValidReviewMark(legacy, for: scenario))

        let outsideFallback = CoachMark(
            kind: .run, start: raw, end: PitchPoint(x: 999, z: 0),
            label: "Invalid fallback", revealTime: 15,
            startTrackAnchor: CoachMarkTrackAnchor(playerID: player.id),
            endTrackAnchor: CoachMarkTrackAnchor(playerID: player.id)
        )
        XCTAssertFalse(ReplayStore.isValidReviewMark(outsideFallback, for: scenario))
    }
}
