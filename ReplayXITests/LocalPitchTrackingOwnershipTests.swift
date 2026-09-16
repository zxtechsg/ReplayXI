import ARKit
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class LocalPitchTrackingOwnershipTests: XCTestCase {
    func testRoomOwnsOnlyItsTrackingRequest() {
        let coordinator = LocalPitchAnchorCoordinator()
        let owner = UUID()
        coordinator.claimTracking(for: owner)
        XCTAssertTrue(coordinator.ownsTracking(for: owner))
        XCTAssertFalse(coordinator.ownsTracking(for: UUID()))
        coordinator.stop()
        XCTAssertFalse(coordinator.ownsTracking(for: owner))
    }

    func testOldRoomCannotRetireNewRoomsAnchorOrPlacementIntent() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        let oldRoom = UUID()
        let newRoom = UUID()
        coordinator.claimTracking(for: oldRoom)
        coordinator.claimTracking(for: newRoom)
        let current = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)
        coordinator.recordLocalPlacement(current)

        let result = try await coordinator.withPlacementLifetime {
            XCTAssertNil(coordinator.stopTracking(for: oldRoom))
            return 7
        }

        XCTAssertEqual(result, 7)
        XCTAssertTrue(coordinator.ownsTracking(for: newRoom))
        XCTAssertEqual(coordinator.sharedPitchAnchorID, current.id)
    }

    func testCloseRetiresAnchorSynchronouslyBeforeItsTaskStarts() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let room = UUID()
        coordinator.claimTracking(for: room)
        coordinator.recordLocalPlacement(WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4))
        let cleanup = coordinator.stopTracking(for: room)

        XCTAssertNotNil(cleanup)
        XCTAssertFalse(coordinator.ownsTracking(for: room))
        XCTAssertNil(coordinator.sharedPitchAnchorID)
        XCTAssertFalse(coordinator.placedPitchAnchorLocally)
        XCTAssertTrue(coordinator.isRemovingPitchAnchor, "Placement stays gated until captured removal finishes")
        XCTAssertNil(coordinator.stopTracking(for: room), "Duplicate teardown must be inert")
        await cleanup?.value
        XCTAssertEqual(coordinator.status, .stopped)
        XCTAssertFalse(coordinator.isRemovingPitchAnchor)
    }

    func testReopenBeforeCleanupRunsKeepsNewAnchorAndSessionLifetime() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        let oldRoom = UUID()
        let newRoom = UUID()
        coordinator.claimTracking(for: oldRoom)
        coordinator.recordLocalPlacement(WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4))
        let cleanup = coordinator.stopTracking(for: oldRoom)
        // Neither deferred cleanup nor physical anchor removal has run yet.
        coordinator.claimTracking(for: newRoom)
        let current = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)
        coordinator.recordLocalPlacement(current)

        let value = try await coordinator.withSessionLifetime {
            await cleanup?.value
            return 42
        }

        XCTAssertEqual(value, 42)
        XCTAssertTrue(coordinator.ownsTracking(for: newRoom))
        XCTAssertEqual(coordinator.sharedPitchAnchorID, current.id)
        XCTAssertTrue(coordinator.placedPitchAnchorLocally)
    }

    func testSameRoomReturningToPositioningDefeatsItsEarlierStop() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        let room = UUID()
        coordinator.claimTracking(for: room)
        let cleanup = coordinator.stopTracking(for: room)
        coordinator.claimTracking(for: room)
        let current = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)
        coordinator.recordLocalPlacement(current)

        _ = try await coordinator.withSessionLifetime { await cleanup?.value }

        XCTAssertTrue(coordinator.ownsTracking(for: room))
        XCTAssertEqual(coordinator.sharedPitchAnchorID, current.id)
    }

    func testLatestUnclaimedStopActuallyInvalidatesSession() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let room = UUID()
        coordinator.claimTracking(for: room)
        do {
            try await coordinator.withSessionLifetime {
                await coordinator.stopTracking(for: room)?.value
            }
            XCTFail("An unclaimed stopped session must invalidate pending work")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(coordinator.status, .stopped)
        XCTAssertFalse(coordinator.ownsTracking(for: room))
    }

    func testSeveralRetiredRoomsCannotStopTheLatestOwner() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        var cleanups: [Task<Void, Never>] = []
        for _ in 0..<4 {
            let room = UUID()
            coordinator.claimTracking(for: room)
            coordinator.recordLocalPlacement(WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4))
            if let cleanup = coordinator.stopTracking(for: room) { cleanups.append(cleanup) }
        }
        let latest = UUID()
        coordinator.claimTracking(for: latest)
        let current = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)
        coordinator.recordLocalPlacement(current)
        try await coordinator.withSessionLifetime {
            for cleanup in cleanups { await cleanup.value }
        }
        XCTAssertTrue(coordinator.ownsTracking(for: latest))
        XCTAssertEqual(coordinator.sharedPitchAnchorID, current.id)
    }

    func testChangingOwnerRetiresOldAnchorAndPendingPlacementImmediately() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let oldRoom = UUID()
        let newRoom = UUID()
        coordinator.claimTracking(for: oldRoom)
        coordinator.recordLocalPlacement(WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4))
        do {
            try await coordinator.withPlacementLifetime {
                coordinator.claimTracking(for: newRoom)
            }
            XCTFail("A replacement room cannot adopt an old room's pending placement")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(coordinator.ownsTracking(for: newRoom))
        XCTAssertNil(coordinator.sharedPitchAnchorID)
        XCTAssertFalse(coordinator.placedPitchAnchorLocally)
        await coordinator.stopTracking(for: newRoom)?.value
    }

    func testCancelledViewTaskCannotClaimTracking() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let currentRoom = UUID()
        let cancelledRoom = UUID()
        coordinator.claimTracking(for: currentRoom)
        let task = Task { @MainActor in await coordinator.start(for: cancelledRoom) }
        task.cancel()
        await task.value
        XCTAssertTrue(coordinator.ownsTracking(for: currentRoom))
        XCTAssertFalse(coordinator.ownsTracking(for: cancelledRoom))
    }

    func testCancelledWaiterDoesNotCancelOwnedAnchorCleanup() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let room = UUID()
        coordinator.claimTracking(for: room)
        coordinator.recordLocalPlacement(WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4))
        let cleanup = coordinator.stopTracking(for: room)
        let waiter = Task { await cleanup?.value }
        waiter.cancel()
        await waiter.value
        XCTAssertEqual(coordinator.status, .stopped)
        XCTAssertNil(coordinator.sharedPitchAnchorID)
    }

    func testCancellingOldViewDoesNotCancelSharedProviderStartup() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let oldRoom = UUID()
        let newRoom = UUID()
        coordinator.claimTracking(for: oldRoom)
        let started = expectation(description: "Provider startup suspended")
        var resume: CheckedContinuation<Void, Never>?
        var providerWasCancelled = false
        let oldView = Task { @MainActor in
            await coordinator.runSessionStartup {
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
                providerWasCancelled = Task.isCancelled
            }
        }
        await fulfillment(of: [started], timeout: 2)
        oldView.cancel()
        coordinator.claimTracking(for: newRoom)
        resume?.resume()
        await oldView.value

        XCTAssertFalse(providerWasCancelled)
        XCTAssertTrue(coordinator.ownsTracking(for: newRoom))
    }

    func testReturningRoomWaitsForExistingStartupWithoutStartingAnotherProvider() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let started = expectation(description: "One startup suspended")
        let waiting = expectation(description: "Returning room is waiting")
        var resume: CheckedContinuation<Void, Never>?
        var duplicateCalls = 0
        var returned = false
        let first = Task { @MainActor in
            await coordinator.runSessionStartup {
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { @MainActor in
            waiting.fulfill()
            await coordinator.runSessionStartup { duplicateCalls += 1 }
            returned = true
        }
        await fulfillment(of: [waiting], timeout: 2)
        XCTAssertFalse(returned)
        resume?.resume()
        await first.value
        await second.value
        XCTAssertTrue(returned)
        XCTAssertEqual(duplicateCalls, 0)
    }

    func testStoppedStartupCannotRetireNewOwnerOrPublishItsError() async {
        enum ProviderError: Error { case stopped }
        let coordinator = LocalPitchAnchorCoordinator()
        coordinator.claimTracking(for: UUID())
        let started = expectation(description: "Old startup suspended")
        var resume: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            await coordinator.runSessionStartup {
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
                throw ProviderError.stopped
            }
        }
        await fulfillment(of: [started], timeout: 2)
        coordinator.stop()
        let newRoom = UUID()
        coordinator.claimTracking(for: newRoom)
        let current = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)
        coordinator.recordLocalPlacement(current)
        await coordinator.runSessionStartup {}
        resume?.resume()
        await first.value
        XCTAssertTrue(coordinator.ownsTracking(for: newRoom))
        XCTAssertEqual(coordinator.sharedPitchAnchorID, current.id)
        XCTAssertEqual(coordinator.status, .localizingPitchAnchor)
    }
}
