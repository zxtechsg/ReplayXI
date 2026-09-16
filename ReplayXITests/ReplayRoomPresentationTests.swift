import XCTest
@testable import ReplayXI

@MainActor
final class ReplayRoomPresentationTests: XCTestCase {
    func testOpeningIsExclusiveAndOwnsOneRequest() throws {
        var room = ReplayRoomPresentation()
        XCTAssertFalse(room.isBusy)
        let id = try XCTUnwrap(room.beginOpening())
        XCTAssertTrue(room.isBusy)
        XCTAssertTrue(room.isOpening)
        XCTAssertFalse(room.isOpen)
        XCTAssertTrue(room.owns(id))
        XCTAssertFalse(room.owns(UUID()))
        XCTAssertNil(room.beginOpening())
        XCTAssertFalse(room.beginClosing(id))
    }

    func testOpenCompletionBeforeAppearanceUsesTheSameRequest() throws {
        var room = ReplayRoomPresentation()
        let id = try XCTUnwrap(room.beginOpening())
        XCTAssertTrue(room.completeOpening(id, opened: true))
        XCTAssertTrue(room.isOpen)
        XCTAssertFalse(room.isVisible)
        XCTAssertEqual(room.didAppear(id), id)
        XCTAssertTrue(room.isVisible)
        XCTAssertFalse(room.isOpening)
    }

    func testAppearanceBeforeOpenCompletionDoesNotInvalidateTheResult() throws {
        var room = ReplayRoomPresentation()
        let id = try XCTUnwrap(room.beginOpening())
        XCTAssertEqual(room.didAppear(id), id)
        XCTAssertTrue(room.completeOpening(id, opened: true))
        XCTAssertTrue(room.isVisible)
        XCTAssertTrue(room.isOpen)
        XCTAssertFalse(room.completeOpening(id, opened: false), "A duplicate result cannot close the room")
    }

    func testFailedOpenReleasesItsRequestForRetry() throws {
        var room = ReplayRoomPresentation()
        let first = try XCTUnwrap(room.beginOpening())
        XCTAssertTrue(room.completeOpening(first, opened: false))
        XCTAssertEqual(room, ReplayRoomPresentation())
        let second = try XCTUnwrap(room.beginOpening())
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(room.completeOpening(first, opened: true))
        XCTAssertTrue(room.isOpeningRequest(second))
    }

    func testSystemDisappearanceDefeatsLateOpenSuccess() throws {
        var room = ReplayRoomPresentation()
        let first = try XCTUnwrap(room.beginOpening())
        XCTAssertEqual(room.didAppear(first), first)
        XCTAssertTrue(room.didDisappear(first))
        XCTAssertFalse(room.isBusy)
        XCTAssertFalse(room.completeOpening(first, opened: true))
        XCTAssertFalse(room.isOpen)
        let second = try XCTUnwrap(room.beginOpening())
        XCTAssertFalse(room.completeOpening(first, opened: false))
        XCTAssertTrue(room.isOpeningRequest(second))
    }

    func testExplicitCloseWaitsForDismissalAfterDisappearance() throws {
        var room = ReplayRoomPresentation()
        let id = try openVisibleRoom(&room)
        XCTAssertTrue(room.beginClosing(id))
        XCTAssertFalse(room.beginClosing(id), "Repeated Exit must not call dismissal again")
        XCTAssertTrue(room.didDisappear(id))
        XCTAssertFalse(room.isOpen, "Child controls must see a genuinely closed view")
        XCTAssertFalse(room.isVisible)
        XCTAssertTrue(room.isClosing)
        XCTAssertTrue(room.isBusy)
        XCTAssertNil(room.beginOpening(), "Do not overlap a pending system dismiss call")
        XCTAssertTrue(room.completeClosing(id))
        XCTAssertEqual(room, ReplayRoomPresentation())
        XCTAssertNotNil(room.beginOpening())
    }

    func testExplicitCloseWaitsForDisappearanceAfterDismissal() throws {
        var room = ReplayRoomPresentation()
        let id = try openVisibleRoom(&room)
        XCTAssertTrue(room.beginClosing(id))
        XCTAssertTrue(room.completeClosing(id))
        XCTAssertTrue(room.isOpen)
        XCTAssertTrue(room.isClosing)
        XCTAssertNil(room.beginOpening())
        XCTAssertTrue(room.didDisappear(id))
        XCTAssertEqual(room, ReplayRoomPresentation())
    }

    func testLateOpenResultCannotReverseClosing() throws {
        var room = ReplayRoomPresentation()
        let id = try XCTUnwrap(room.beginOpening())
        XCTAssertEqual(room.didAppear(id), id)
        XCTAssertTrue(room.beginClosing(id))
        let closing = room
        XCTAssertFalse(room.completeOpening(id, opened: true))
        XCTAssertFalse(room.completeOpening(id, opened: false))
        XCTAssertEqual(room, closing)
    }

    func testWrongOwnerEventsCannotChangeAnyPresentationPhase() throws {
        var room = ReplayRoomPresentation()
        let id = try XCTUnwrap(room.beginOpening())
        let wrong = UUID()
        for phase in 0..<3 {
            let before = room
            XCTAssertFalse(room.completeOpening(wrong, opened: false))
            XCTAssertFalse(room.beginClosing(wrong))
            XCTAssertFalse(room.didDisappear(wrong))
            XCTAssertFalse(room.completeClosing(wrong))
            XCTAssertEqual(room, before)
            XCTAssertNil(room.didAppear(wrong))
            if phase == 0 { XCTAssertEqual(room.didAppear(id), id) }
            if phase == 1 { XCTAssertTrue(room.beginClosing(id)) }
        }
    }

    func testOldCloseAndDisappearanceCannotCloseAReopenedRoom() throws {
        var room = ReplayRoomPresentation()
        let old = try openVisibleRoom(&room)
        XCTAssertTrue(room.beginClosing(old))
        XCTAssertTrue(room.didDisappear(old))
        XCTAssertTrue(room.completeClosing(old))
        let current = try openVisibleRoom(&room)
        let before = room
        XCTAssertFalse(room.didDisappear(old))
        XCTAssertFalse(room.completeClosing(old))
        XCTAssertFalse(room.completeOpening(old, opened: true))
        XCTAssertEqual(room, before)
        XCTAssertTrue(room.owns(current))
    }

    func testAppearCannotInventAnOpenOrReverseAClosingRoom() throws {
        var room = ReplayRoomPresentation()
        XCTAssertNil(room.didAppear(UUID()))
        let id = try openVisibleRoom(&room)
        XCTAssertTrue(room.beginClosing(id))
        XCTAssertNil(room.didAppear(id))
        XCTAssertTrue(room.isClosing)
    }

    func testContradictoryFailureCannotEraseVisibleRoom() throws {
        var room = ReplayRoomPresentation()
        let id = try XCTUnwrap(room.beginOpening())
        XCTAssertEqual(room.didAppear(id), id)
        XCTAssertFalse(room.completeOpening(id, opened: false))
        XCTAssertTrue(room.isVisible)
        XCTAssertTrue(room.completeOpening(id, opened: true))
    }

    func testOnlyVisibleCurrentRoomAcceptsGesturesAndAccessibilityActions() throws {
        var room = ReplayRoomPresentation()
        let id = try XCTUnwrap(room.beginOpening())
        XCTAssertFalse(room.acceptsInteraction(for: id))
        XCTAssertTrue(room.completeOpening(id, opened: true))
        XCTAssertFalse(room.acceptsInteraction(for: id))
        XCTAssertEqual(room.didAppear(id), id)
        XCTAssertTrue(room.acceptsInteraction(for: id))
        XCTAssertFalse(room.acceptsInteraction(for: UUID()))
        XCTAssertTrue(room.beginClosing(id))
        XCTAssertFalse(room.acceptsInteraction(for: id))
        XCTAssertTrue(room.didDisappear(id))
        XCTAssertFalse(room.acceptsInteraction(for: id))
    }

    func testStoreExitRollsBackScrubBeforeDisappearanceAndCannotBeRepeated() throws {
        let store = ReplayStore()
        let id = try XCTUnwrap(store.beginImmersiveOpen())
        XCTAssertEqual(store.immersiveRoomDidAppear(id), id)
        XCTAssertTrue(store.completeImmersiveOpen(id, opened: true))
        store.playhead = 5
        store.isPlaying = true
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 9))

        XCTAssertTrue(store.beginImmersiveClose(id))
        XCTAssertFalse(store.beginImmersiveClose(id))
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.playhead, 5)
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.isClosingImmersive)
        XCTAssertTrue(store.immersiveRoomDidDisappear(id))
        XCTAssertFalse(store.isImmersiveOpen)
        XCTAssertTrue(store.isRoomPresentationBusy)
        store.completeImmersiveClose(id)
        XCTAssertFalse(store.isRoomPresentationBusy)
    }

    func testStaleDisappearanceDoesNotPauseOrCancelNewRoomsScrub() throws {
        let store = ReplayStore()
        let old = try XCTUnwrap(store.beginImmersiveOpen())
        XCTAssertEqual(store.immersiveRoomDidAppear(old), old)
        XCTAssertTrue(store.immersiveRoomDidDisappear(old))
        let current = try XCTUnwrap(store.beginImmersiveOpen())
        XCTAssertEqual(store.immersiveRoomDidAppear(current), current)
        XCTAssertTrue(store.completeImmersiveOpen(current, opened: true))
        store.playhead = 5
        store.isPlaying = true
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 9))

        XCTAssertFalse(store.immersiveRoomDidDisappear(old))
        XCTAssertFalse(store.beginImmersiveClose(old))
        store.completeImmersiveClose(old)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.playhead, 9)
        XCTAssertTrue(store.isImmersiveOpen)
        XCTAssertTrue(store.commitTimelineScrub(to: 10))
        XCTAssertTrue(store.isPlaying)
    }

    func testSystemDismissalPausesAndLateOpenResultCannotReopenStore() throws {
        let store = ReplayStore()
        let id = try XCTUnwrap(store.beginImmersiveOpen())
        XCTAssertEqual(store.immersiveRoomDidAppear(id), id)
        store.isPlaying = true
        XCTAssertTrue(store.immersiveRoomDidDisappear(id))
        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(store.isImmersiveOpen)
        XCTAssertFalse(store.completeImmersiveOpen(id, opened: true))
        XCTAssertFalse(store.isRoomPresentationBusy)
    }

    private func openVisibleRoom(_ room: inout ReplayRoomPresentation) throws -> UUID {
        let id = try XCTUnwrap(room.beginOpening())
        XCTAssertEqual(room.didAppear(id), id)
        XCTAssertTrue(room.completeOpening(id, opened: true))
        return id
    }
}
