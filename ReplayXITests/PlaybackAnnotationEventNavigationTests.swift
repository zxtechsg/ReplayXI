import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackAnnotationEventNavigationTests: XCTestCase {
    func testRetainedEventUsesCurrentInAfterRetimeAndWindowEdit() throws {
        let fixture = try Fixture()
        let retained = fixture.retainedAction(for: fixture.created)
        // Old chips captured the whole value and sought created.revealTime (2)
        // even after the index was invalidated by an edit in the same UI pass.
        XCTAssertTrue(fixture.store.retimeCoachMark(id: fixture.created.id, to: 8))
        fixture.store.seek(to: 12, broadcast: false)
        fixture.store.setPlaying(true, broadcast: false)
        let marks = fixture.store.marks

        XCTAssertTrue(retained())

        XCTAssertEqual(fixture.created.revealTime, 2, "This callback still retains the old event value")
        XCTAssertEqual(fixture.store.playhead, 8)
        XCTAssertFalse(fixture.store.isPlaying)
        XCTAssertEqual(fixture.selection, fixture.created.id)
        XCTAssertTrue(fixture.showsAnnotations)
        XCTAssertFalse(fixture.showsDecisions)
        XCTAssertEqual(fixture.store.marks, marks)
        XCTAssertTrue(fixture.store.setCoachMarkWindow(id: fixture.created.id, start: 4, end: 14))
        fixture.store.seek(to: 12, broadcast: false)
        XCTAssertTrue(retained())
        XCTAssertEqual(fixture.store.playhead, 4)
    }

    func testRetainedDeletedEventCannotPauseSeekSelectOrChangeVisibilityAndUndoRevivesIt() throws {
        let fixture = try Fixture()
        let retained = fixture.retainedAction(for: fixture.created)
        XCTAssertTrue(fixture.store.removeCoachMark(id: fixture.created.id))
        fixture.store.seek(to: 12, broadcast: false)
        fixture.store.setPlaying(true, broadcast: false)
        let before = fixture.snapshot
        var packets = 0
        fixture.store.onBroadcastSnapshot = { _ in packets += 1 }

        XCTAssertFalse(retained())

        XCTAssertEqual(fixture.snapshot, before)
        XCTAssertEqual(packets, 0)
        XCTAssertTrue(fixture.store.undoAnnotationEdit())
        XCTAssertTrue(retained())
        XCTAssertEqual(fixture.store.playhead, fixture.created.revealTime)
        XCTAssertEqual(fixture.selection, fixture.created.id)
    }

    func testRetainedEventCannotTakeOverTimelineScrub() throws {
        let fixture = try Fixture()
        let retained = fixture.retainedAction(for: fixture.created)
        fixture.store.seek(to: 12, broadcast: false)
        fixture.store.setPlaying(true, broadcast: false)
        XCTAssertTrue(fixture.store.beginTimelineScrub())
        XCTAssertTrue(fixture.store.previewTimelineScrub(to: 7))
        let owner = fixture.store.activeTimelineScrubID
        let before = fixture.snapshot

        XCTAssertFalse(retained())

        XCTAssertEqual(fixture.snapshot, before)
        XCTAssertEqual(fixture.store.activeTimelineScrubID, owner)
        XCTAssertTrue(fixture.store.commitTimelineScrub(to: 9))
        XCTAssertEqual(fixture.store.playhead, 9)
        XCTAssertTrue(fixture.store.isPlaying)
        XCTAssertTrue(retained())
        XCTAssertEqual(fixture.store.playhead, 2)
    }

    func testRetainedEventCannotInterruptJoystickDirectHandleOrDrawing() throws {
        let fixture = try Fixture()
        let retained = fixture.retainedAction(for: fixture.created)
        fixture.store.seek(to: 6, broadcast: false)
        let joystick = UUID()
        XCTAssertNotNil(fixture.store.previewCoachMarkEndpoint(
            id: fixture.created.id, endpoint: .end, gestureID: joystick,
            cumulativeDelta: .init(x: 1, z: 0)))
        var before = fixture.snapshot
        XCTAssertFalse(retained())
        XCTAssertEqual(fixture.snapshot, before)
        XCTAssertTrue(fixture.store.hasActiveCoachMarkEndpointPreview)
        XCTAssertTrue(fixture.store.cancelCoachMarkEndpointPreview(id: fixture.created.id, gestureID: joystick))

        let handle = UUID()
        XCTAssertTrue(fixture.store.previewCoachMarkHandle(id: fixture.created.id, endpoint: .end,
            gestureID: handle, point: .init(x: -14, z: -13)))
        before = fixture.snapshot
        XCTAssertFalse(retained())
        XCTAssertEqual(fixture.snapshot, before)
        XCTAssertTrue(fixture.store.hasActiveCoachMarkGeometryPreview)
        XCTAssertTrue(fixture.store.cancelCoachMarkHandlePreview(id: fixture.created.id, gestureID: handle))

        fixture.store.beginDrawing(.pass)
        XCTAssertNil(fixture.store.registerPitchTap(.init(x: -20, z: -30)))
        before = fixture.snapshot
        XCTAssertFalse(retained())
        XCTAssertEqual(fixture.snapshot, before)
        XCTAssertTrue(fixture.store.isDrawing)
        XCTAssertEqual(fixture.store.pendingDrawStart, .init(x: -20, z: -30))
        fixture.store.cancelDrawing()
        XCTAssertTrue(retained())
    }

    func testAuthoredAndCoachEventsKeepTheirExistingRoleAndLocalSeekSemantics() throws {
        for role in [SquadRole.coach, .player] {
            for shared in [false, true] {
                let fixture = try Fixture()
                let authored = try XCTUnwrap(fixture.store.selectedScenario.coachMarks.first)
                fixture.store.localRole = role
                fixture.store.setCollaborationActive(shared)
                var packets: [SharedPlaybackSnapshot] = []
                fixture.store.onBroadcastSnapshot = { packets.append($0) }
                for mark in [authored, fixture.created] {
                    fixture.store.seek(to: 12, broadcast: false)
                    fixture.store.setPlaying(true, broadcast: false)
                    let marks = fixture.store.marks
                    let followsCoach = fixture.store.followsCoach
                    let localPause = fixture.store.isLocallyPaused
                    let previousPackets = packets.count

                    XCTAssertTrue(fixture.retainedAction(for: mark)())

                    XCTAssertEqual(fixture.store.playhead, mark.revealTime)
                    XCTAssertFalse(fixture.store.isPlaying)
                    XCTAssertEqual(fixture.selection, mark.id)
                    XCTAssertEqual(fixture.store.marks, marks)
                    XCTAssertEqual(fixture.store.followsCoach, followsCoach)
                    XCTAssertEqual(fixture.store.isLocallyPaused, localPause,
                                   "Event jumps do not opt into spatial AX comfort review")
                    XCTAssertEqual(packets.count - previousPackets, role == .coach ? 1 : 0)
                    if role == .coach { XCTAssertEqual(packets.last?.playhead, mark.revealTime) }
                }
            }
        }
    }

    func testTimingDraftRouteProtectionKeepsBothDraftsWhileReviewSeekRemainsAllowed() throws {
        let fixture = try Fixture()
        XCTAssertTrue(fixture.store.captureCoachMarkKeyframe(id: fixture.created.id))
        let current = try XCTUnwrap(fixture.store.marks.first { $0.id == fixture.created.id })
        let session = AnnotationTimingDraftSession()
        XCTAssertTrue(session.begin(mark: current, scenarioID: fixture.store.selectedScenarioID,
            duration: fixture.store.selectedScenario.duration, store: fixture.store))
        session.window.startText = "1"
        XCTAssertTrue(session.position.select(2))
        session.position.text = "3"
        let source = AnnotationTimingDeckRoute(selection: current.id, panel: .annotationDuration(current.id),
            showsTools: false, showsPlayers: false, showsEvents: false, showsDecisions: false,
            showsDrawing: false, showsClear: false, showsAnnotations: true)
        var navigation = AnnotationTimingNavigationGate()
        navigation.observeDraft(isDirty: session.hasUnsavedChanges, route: source)
        let authored = try XCTUnwrap(fixture.store.selectedScenario.coachMarks.first)
        let marks = fixture.store.marks

        XCTAssertTrue(fixture.retainedAction(for: authored)())
        var attempted = source
        attempted.selection = fixture.selection
        XCTAssertEqual(navigation.protect(attempted), source)
        navigation.keepEditing()

        XCTAssertEqual(fixture.store.playhead, authored.revealTime, "Seeking during timing edits remains supported")
        XCTAssertEqual(fixture.store.pendingAnnotationTimingEditID, current.id)
        XCTAssertEqual(navigation.protectedRoute, source)
        XCTAssertNil(navigation.request)
        XCTAssertEqual(session.markID, current.id)
        XCTAssertEqual(session.window.startText, "1")
        XCTAssertEqual(session.position.text, "3")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(fixture.store.marks, marks)
        session.releaseOwnership()
    }

    func testRetainedPreviousScenarioEventCannotChangeTheCurrentReview() throws {
        let fixture = try Fixture()
        let retained = fixture.retainedAction(for: fixture.created)
        let other = try XCTUnwrap(fixture.store.scenarios.first { $0.id != fixture.store.selectedScenarioID })
        fixture.store.selectScenario(id: other.id, broadcast: false)
        XCTAssertFalse(fixture.store.marks.contains { $0.id == fixture.created.id })
        fixture.store.seek(to: 6, broadcast: false)
        fixture.store.setPlaying(true, broadcast: false)
        let before = fixture.snapshot

        XCTAssertFalse(retained())

        XCTAssertEqual(fixture.snapshot, before)
    }

    private struct Snapshot: Equatable {
        let saved: SavedReplayState
        let marks: [CoachMark]
        let playhead: TimeInterval
        let isPlaying: Bool
        let isDrawing: Bool
        let selected: UUID?
        let showsAnnotations: Bool
        let showsDecisions: Bool
    }

    @MainActor
    private final class Fixture {
        let store: ReplayStore
        let created: CoachMark
        var selection: UUID?
        var showsAnnotations = false
        var showsDecisions = true

        init() throws {
            let store = ReplayStore()
            store.prepareForLocalExperience()
            store.seek(to: 2, broadcast: false)
            store.beginDrawing(.arc)
            XCTAssertNil(store.registerPitchTap(.init(x: -20, z: -20)))
            let mark = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
            if mark.followsPlayerTracks {
                XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: nil))
            }
            self.store = store
            created = try XCTUnwrap(store.marks.first { $0.id == mark.id })
            selection = store.selectedScenario.coachMarks.first?.id
        }

        var snapshot: Snapshot {
            .init(saved: store.makeSavedReviewState(), marks: store.marks,
                  playhead: store.playhead, isPlaying: store.isPlaying, isDrawing: store.isDrawing,
                  selected: selection, showsAnnotations: showsAnnotations, showsDecisions: showsDecisions)
        }

        /// Mirrors the event-chip action's retained value and admission order.
        /// Source wiring tests require the real button to gate these UI writes.
        func retainedAction(for mark: CoachMark) -> () -> Bool {
            {
                guard PlaybackAnnotationEventNavigation.jump(to: mark.id, in: self.store) else { return false }
                self.showsAnnotations = true
                self.selection = mark.id
                self.showsDecisions = false
                return true
            }
        }
    }
}
