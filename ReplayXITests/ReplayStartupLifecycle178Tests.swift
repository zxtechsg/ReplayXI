import XCTest
@testable import ReplayXI

@MainActor
final class ReplayStartupLifecycle178Tests: XCTestCase {
    private enum TestFailure: Error { case expected }

    func testVisualPreparationKeepsEveryResourceFamilyInOrder() async throws {
        var performed: [ReplayVisualPreparation.Step] = []
        var messages: [String] = []
        try await ReplayVisualPreparation.run(progress: { messages.append($0) }) { performed.append($0) }
        XCTAssertEqual(performed, ReplayVisualPreparation.Step.allCases)
        XCTAssertEqual(messages, performed.map(\.label))
    }

    func testCancelledAdmissionStopsBeforeAnyResourcesLoad() async {
        var loads = 0
        do {
            try await ReplayVisualPreparation.run(shouldContinue: { false }) { _ in loads += 1 }
            XCTFail("Cancelled admission must stop")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(loads, 0)
    }

    func testChangedAdmissionStopsBetweenResourceFamilies() async {
        var performed: [ReplayVisualPreparation.Step] = []
        do {
            try await ReplayVisualPreparation.run(shouldContinue: { performed.count < 2 }) {
                performed.append($0)
            }
            XCTFail("Changed admission must stop")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(performed, Array(ReplayVisualPreparation.Step.allCases.prefix(2)))
    }

    func testResourceErrorDoesNotRunLaterStages() async {
        var performed: [ReplayVisualPreparation.Step] = []
        do {
            try await ReplayVisualPreparation.run {
                performed.append($0)
                if $0 == .athleteMeshes { throw TestFailure.expected }
            }
            XCTFail("Required resource failure must propagate")
        } catch { XCTAssertTrue(error is TestFailure) }
        XCTAssertEqual(performed.last, .athleteMeshes)
    }

    func testFailedPreparationReleasesRoomAndAnnotationRequestForRetry() async throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let annotation = ReplayAnnotationEntrySession()
        var opened = 0, dismissed = 0
        let first = try XCTUnwrap(ReplayRoomLauncher.begin(store: store, annotationEntry: annotation,
            prepare: { _ in throw TestFailure.expected },
            openRoom: { _ in opened += 1; return .opened }, didOpen: { dismissed += 1 }))
        await first.value
        XCTAssertFalse(store.isRoomPresentationBusy)
        XCTAssertNil(annotation.pending)
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(dismissed, 0)
        let retry = try XCTUnwrap(ReplayRoomLauncher.begin(store: store, prepare: { _ in },
            openRoom: { _ in opened += 1; return .opened }, didOpen: { dismissed += 1 }))
        await retry.value
        XCTAssertTrue(store.isImmersiveOpen)
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(dismissed, 1)
    }

    func testPreparationCanCancelAndNewEntryCannotBeClobberedByOldCleanup() async throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let annotation = ReplayAnnotationEntrySession()
        let started = expectation(description: "Preparation started")
        var openCalls = 0
        let first = try XCTUnwrap(ReplayRoomLauncher.begin(store: store, annotationEntry: annotation,
            prepare: { _ in started.fulfill(); try await Task.sleep(for: .seconds(5)) },
            openRoom: { _ in openCalls += 1; return .opened }, didOpen: {}))
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(ReplayRoomLauncher.canCancelPendingOpen(for: store))
        XCTAssertTrue(ReplayRoomLauncher.cancelPendingOpen(for: store))
        XCTAssertFalse(store.isRoomPresentationBusy)
        let second = try XCTUnwrap(ReplayRoomLauncher.begin(store: store, annotationEntry: annotation,
            prepare: { _ in }, openRoom: { _ in openCalls += 1; return .opened }, didOpen: {}))
        await first.value
        await second.value
        XCTAssertTrue(store.isImmersiveOpen)
        XCTAssertEqual(openCalls, 1)
        XCTAssertEqual(annotation.pending?.roomID, store.roomPresentation.requestID)
        XCTAssertFalse(ReplayRoomLauncher.cancelPendingOpen(for: store))
    }

    func testCancellationDoesNotStealAnIssuedSystemOpen() async throws {
        let store = ReplayStore()
        var attemptedCancellation = true
        let task = try XCTUnwrap(ReplayRoomLauncher.begin(store: store, prepare: { _ in },
            openRoom: { _ in
                XCTAssertFalse(ReplayRoomLauncher.canCancelPendingOpen(for: store))
                attemptedCancellation = ReplayRoomLauncher.cancelPendingOpen(for: store)
                return .opened
            }, didOpen: {}))
        await task.value
        XCTAssertFalse(attemptedCancellation)
        XCTAssertTrue(store.isImmersiveOpen)
    }

    func testSystemCancelledOpenKeepsDashboardAndCanRetry() async throws {
        let store = ReplayStore()
        var dismissals = 0
        let task = try XCTUnwrap(ReplayRoomLauncher.begin(store: store, prepare: { _ in },
            openRoom: { _ in .cancelled }, didOpen: { dismissals += 1 }))
        await task.value
        XCTAssertEqual(store.statusMessage, "Opening cancelled")
        XCTAssertFalse(store.isRoomPresentationBusy)
        XCTAssertEqual(dismissals, 0)
        XCTAssertFalse(ReplayRoomLauncher.cancelPendingOpen(for: store))
    }

    func testChangedScenarioDuringPreparationDoesNotOpenTheWrongRoom() async throws {
        let store = ReplayStore()
        let alternate = try XCTUnwrap(store.scenarios.first { $0.id != store.selectedScenarioID })
        var opens = 0
        let task = try XCTUnwrap(ReplayRoomLauncher.begin(store: store,
            prepare: { _ in store.selectScenario(id: alternate.id, broadcast: false) },
            openRoom: { _ in opens += 1; return .opened }, didOpen: {}))
        await task.value
        XCTAssertEqual(opens, 0)
        XCTAssertFalse(store.isRoomPresentationBusy)
        XCTAssertEqual(store.selectedScenarioID, alternate.id)
    }

    func testExclusiveOpenAndLateDisappearanceCannotDismissDashboardTwice() async throws {
        let store = ReplayStore()
        var dismissals = 0
        let task = try XCTUnwrap(ReplayRoomLauncher.begin(store: store, prepare: { _ in },
            openRoom: { requestID in
                XCTAssertEqual(store.immersiveRoomDidAppear(requestID), requestID)
                XCTAssertTrue(store.immersiveRoomDidDisappear(requestID))
                return .opened
            }, didOpen: { dismissals += 1 }))
        XCTAssertNil(ReplayRoomLauncher.begin(store: store, prepare: { _ in },
            openRoom: { _ in .opened }, didOpen: {}))
        await task.value
        XCTAssertEqual(dismissals, 0)
        XCTAssertFalse(store.isRoomPresentationBusy)
    }
}
