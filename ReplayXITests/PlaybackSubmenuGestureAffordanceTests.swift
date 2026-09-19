import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackSubmenuGestureAffordanceTests: XCTestCase {
    func testRosterShirtsShareTheExistingPOVGateAndExplainBlockedGestures() throws {
        let source = try immersiveSource()
        let button = try slice(source, after: "private func perspectivePlayerButton(", before: "private var playerGridInstruction:")
        XCTAssertTrue(button.contains(".disabled(playerControlIsDisabled)"))
        XCTAssertTrue(button.contains(".accessibilityHint(playerPOVAccessibilityHint)"))
        let hint = try slice(source, after: "private var playerPOVAccessibilityHint:", before: "private func teamAccent(")
        XCTAssertTrue(hint.contains("playerControlIsDisabled"))
        XCTAssertTrue(hint.contains("Finish or cancel the current gesture first"))
        let callback = try slice(source, after: "private func openPlayerPOV(", before: "private func annotationColor(")
        assertGate("guard !playerControlIsDisabled else { return }", precedes: "inlinePanel = nil", in: callback)
    }

    func testLabelChoicesUseOwnershipBeforeEnablingOrCallingStore() throws {
        let source = try immersiveSource()
        let label = try slice(source, after: "private func annotationLabelShelf(", before: "private var unavailableInlineShelf:")
        XCTAssertTrue(label.contains(".disabled(isSelected || !store.canChangePlaybackView)"))
        XCTAssertTrue(label.contains(".accessibilityHint(store.canChangePlaybackView"))
        XCTAssertTrue(label.contains("Finish or cancel the current gesture first"))
        assertGate("guard store.canChangePlaybackView else { return }",
                   precedes: "store.updateCoachMarkLabel", in: label)
    }

    func testFollowPitchAndPlayerChoicesUseTheSameOwnershipGate() throws {
        let source = try immersiveSource()
        let shelf = try slice(source, after: "private func annotationTrackingShelf(", before: "private func annotationTrackingTeamRow(")
        XCTAssertTrue(shelf.contains(".disabled(isFixedToPitch || !annotationTrackingIsEnabled(mark))"))
        XCTAssertTrue(shelf.contains(".accessibilityHint(store.canChangePlaybackView"))
        XCTAssertTrue(shelf.contains("Finish or cancel the current gesture first"))
        let button = try slice(source, after: "private func annotationTrackingPlayerButton(", before: "private func annotationTrackingPlayerID(")
        XCTAssertTrue(button.contains(".disabled(!annotationTrackingIsEnabled(mark))"))
        XCTAssertTrue(button.contains(".accessibilityHint(AnnotationTrackingPolicy.playerHint(mark,"))
        XCTAssertTrue(button.contains("canChangePlaybackView: store.canChangePlaybackView"))
        let callback = try slice(source, after: "private func setAnnotationTracking(", before: "private func annotationLabelShelf(")
        assertGate("guard annotationTrackingIsEnabled(mark) else { return }",
                   precedes: "store.setCoachMarkTracking", in: callback)
    }

    func testHeldScrubRejectsPOVLabelAndTrackingWithoutLosingCommitOrCancel() throws {
        for scenarioID in ["real-world-match-replay", "triangle-lock"] {
            for commits in [false, true] {
                let (store, mark) = try makeMark(scenarioID: scenarioID)
                store.setPlaying(true, broadcast: false)
                XCTAssertTrue(store.beginTimelineScrub())
                XCTAssertTrue(store.previewTimelineScrub(to: 12))
                assertCompetingActionsAreRejected(in: store, mark: mark)
                XCTAssertTrue(store.hasActiveTimelineScrub)
                XCTAssertTrue(store.previewTimelineScrub(to: 13))
                if commits {
                    XCTAssertTrue(store.commitTimelineScrub(to: 14))
                    XCTAssertEqual(store.playhead, 14)
                } else {
                    store.cancelTimelineScrub()
                    XCTAssertEqual(store.playhead, 5)
                }
                XCTAssertTrue(store.canChangePlaybackView)
                XCTAssertTrue(store.isPlaying)
                XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
            }
        }
    }

    func testDirectAndJoystickOwnersKeepTheirPreviewUntilTheirOwnFinish() throws {
        for joystick in [false, true] {
            for commits in [false, true] {
                let (store, mark) = try makeMark()
                let gestureID = UUID()
                let movement = PitchPoint(x: 0.5, z: -0.25)
                let endpoint = PitchPoint(x: mark.end.x + movement.x, z: mark.end.z + movement.z)
                if joystick {
                    XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                        gestureID: gestureID, cumulativeDelta: movement))
                } else {
                    XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id, start: mark.start,
                        end: endpoint, broadcast: false))
                }
                let preview = store.marks
                let owner = store.activeCoachMarkEndpointPreviewOwner
                assertCompetingActionsAreRejected(in: store, mark: mark)
                XCTAssertEqual(store.marks, preview)
                XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner, owner)
                if joystick {
                    if commits {
                        XCTAssertEqual(store.commitCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID), movement)
                    } else {
                        XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID))
                    }
                } else if commits {
                    XCTAssertTrue(store.commitCoachMarkGeometryPreview(id: mark.id, start: mark.start, end: endpoint))
                } else {
                    XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
                }
                XCTAssertTrue(store.canChangePlaybackView)
                if commits {
                    XCTAssertTrue(store.undoAnnotationEdit())
                }
                XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
            }
        }
    }

    func testNormalOpponentPOVLabelAndTrackingRemainAvailableAndUndoExactly() throws {
        let (store, mark) = try makeMark()
        let opponent = try XCTUnwrap(store.selectedScenario.awayPlayers.first)
        let baseline = store.marks
        XCTAssertTrue(store.canChangePlaybackView)
        store.openLocalPlayerPOV(opponent.id)
        XCTAssertEqual(store.viewMode, .firstPerson)
        XCTAssertEqual(store.activePerspectiveID, opponent.id)
        XCTAssertEqual(store.playhead, 5)
        XCTAssertTrue(store.updateCoachMarkLabel(id: mark.id, label: "Switch play"))
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline)
        XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: opponent.id))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }?.startTrackAnchor?.playerID, opponent.id)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, baseline)
        XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: opponent.id))
        let tracked = store.marks
        XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: nil))
        XCTAssertFalse(try XCTUnwrap(store.marks.first { $0.id == mark.id }).followsPlayerTracks)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, tracked)
    }

    func testOwningRailAndRosterCloseKeepTheirSeparateNonmutatingRoutes() throws {
        let source = try immersiveSource()
        let rail = try slice(source, after: "private var timelineControlsAreDisabled:", before: "private var rateControlsAreDisabled:")
        XCTAssertTrue(rail.contains("store.isDrawing || store.hasActiveCoachMarkGeometryPreview"))
        XCTAssertFalse(rail.contains("canChangePlaybackView"))
        XCTAssertTrue(rail.contains("store.hasActiveTimelineScrub"))
        XCTAssertTrue(rail.contains("timelineScrubController.storeScrubID != store.activeTimelineScrubID"),
                      "A foreign rail may block input, but this rail must retain its own drag")
        let roster = try slice(source, after: "private var playerPOVGrid:", before: "private func perspectiveTeamRow(")
        let close = try slice(roster, after: "Button {", before: "Image(systemName: \"person.crop.rectangle.stack.fill\")")
        XCTAssertTrue(close.contains("showsPlayerGrid = false"))
        XCTAssertFalse(close.contains(".disabled("))
    }

    private func assertCompetingActionsAreRejected(in store: ReplayStore, mark: CoachMark,
                                                  file: StaticString = #filePath, line: UInt = #line) {
        let marks = store.marks
        let snapshot = store.makeSnapshot()
        let mode = store.viewMode
        let perspective = store.activePerspectiveID
        let undo = store.annotationUndoTitle
        let redo = store.annotationRedoTitle
        XCTAssertFalse(store.canChangePlaybackView, file: file, line: line)
        store.openLocalPlayerPOV("red-lb")
        XCTAssertFalse(store.updateCoachMarkLabel(id: mark.id, label: "Switch play"), file: file, line: line)
        XCTAssertFalse(store.setCoachMarkTracking(id: mark.id, playerID: "red-lb"), file: file, line: line)
        XCTAssertFalse(store.setCoachMarkTracking(id: mark.id, playerID: nil), file: file, line: line)
        XCTAssertEqual(store.marks, marks, file: file, line: line)
        XCTAssertEqual(store.makeSnapshot(), snapshot, file: file, line: line)
        XCTAssertEqual(store.viewMode, mode, file: file, line: line)
        XCTAssertEqual(store.activePerspectiveID, perspective, file: file, line: line)
        XCTAssertEqual(store.annotationUndoTitle, undo, file: file, line: line)
        XCTAssertEqual(store.annotationRedoTitle, redo, file: file, line: line)
    }

    private func makeMark(scenarioID: String = "real-world-match-replay") throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        XCTAssertFalse(store.reviewLibrary.usesDisk)
        store.selectScenario(id: scenarioID)
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let created = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 12)))
        if created.followsPlayerTracks {
            XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil))
        }
        return (store, try XCTUnwrap(store.marks.first { $0.id == created.id }))
    }

    private func assertGate(_ gate: String, precedes effect: String, in source: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let gateIndex = source.range(of: gate)?.lowerBound
        let effectIndex = source.range(of: effect)?.lowerBound
        XCTAssertNotNil(gateIndex, file: file, line: line)
        XCTAssertNotNil(effectIndex, file: file, line: line)
        if let gateIndex, let effectIndex { XCTAssertLessThan(gateIndex, effectIndex, file: file, line: line) }
    }

    private func immersiveSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let deck = try XCTUnwrap(source.range(of: "private struct ImmersiveControlDeck:")?.lowerBound)
        return String(source[deck...])
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
