import ARKit
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class LocalPitchSessionLifetimeTests: XCTestCase {
    private enum TestError: Error { case providerFailure }

    func testCurrentSessionAcceptsCompletedOperation() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        let value = try await coordinator.withSessionLifetime { 42 }
        XCTAssertEqual(value, 42)
    }

    func testStopRejectsDelayedCompletionWithoutChangingStoppedState() async {
        let coordinator = LocalPitchAnchorCoordinator()
        do {
            _ = try await coordinator.withSessionLifetime {
                coordinator.stop()
                return UUID()
            }
            XCTFail("A stopped session must reject its old result")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(coordinator.status, .stopped)
        XCTAssertNil(coordinator.sharedPitchAnchorID)
        XCTAssertFalse(coordinator.isPlacingPitchAnchor)
    }

    func testOldCompletionCannotInvalidateNewSessionOperation() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        var freshResult: Int?
        do {
            _ = try await coordinator.withSessionLifetime {
                coordinator.stop()
                freshResult = try await coordinator.withSessionLifetime { 7 }
                return 3
            }
            XCTFail("The old session result must be discarded")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(freshResult, 7)
        let next = try await coordinator.withSessionLifetime { 9 }
        XCTAssertEqual(next, 9)
    }

    func testCancellationIsCheckedAfterProviderReturns() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let started = expectation(description: "Provider call is suspended")
        var resume: CheckedContinuation<Int, Never>?
        let operation = Task { @MainActor in
            try await coordinator.withSessionLifetime {
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        operation.cancel()
        resume?.resume(returning: 5)
        do {
            _ = try await operation.value
            XCTFail("A provider that ignores cancellation must not commit a result")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testProviderFailureRemainsAvailableForErrorMessage() async {
        let coordinator = LocalPitchAnchorCoordinator()
        do {
            try await coordinator.withSessionLifetime { throw TestError.providerFailure }
            XCTFail("Provider failure should propagate")
        } catch {
            XCTAssertTrue(error is TestError)
        }
    }

    func testStoppedSessionSuppressesDelayedProviderFailure() async {
        let coordinator = LocalPitchAnchorCoordinator()
        do {
            _ = try await coordinator.withSessionLifetime {
                coordinator.stop()
                throw TestError.providerFailure
            }
            XCTFail("The old operation must fail")
        } catch {
            XCTAssertTrue(error is CancellationError, "An old provider error must not reopen a new view's error banner")
        }
        XCTAssertEqual(coordinator.status, .stopped)
    }

    func testCancelledTaskSuppressesProviderErrorAfterSuspension() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let started = expectation(description: "Failing provider is suspended")
        var resume: CheckedContinuation<Int, Error>?
        let operation = Task { @MainActor in
            try await coordinator.withSessionLifetime {
                try await withCheckedThrowingContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        operation.cancel()
        resume?.resume(throwing: TestError.providerFailure)
        do {
            _ = try await operation.value
            XCTFail("The cancelled operation must fail")
        } catch {
            XCTAssertTrue(error is CancellationError, "Cancellation must win over a late provider error")
        }
    }

    func testEndedDrillSuppressesDelayedPlacementFailure() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        do {
            _ = try await coordinator.withPlacementLifetime {
                await coordinator.removeLocallyPlacedPitchAnchor()
                throw TestError.providerFailure
            }
            XCTFail("The ended placement must fail")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let next = try await coordinator.withPlacementLifetime { 9 }
        XCTAssertEqual(next, 9, "A new deliberate placement remains available")
    }

    func testCurrentPlacementFailureRunsCleanupAndPreservesTheRealError() async {
        let coordinator = LocalPitchAnchorCoordinator()
        var cleanups = 0
        do {
            try await coordinator.withPlacementLifetime({
                throw TestError.providerFailure
            }, cleanupOnFailure: { cleanups += 1 })
            XCTFail("The current provider error must remain visible")
        } catch {
            XCTAssertTrue(error is TestError)
        }
        XCTAssertEqual(cleanups, 1)
    }

    func testSuccessfulPlacementDoesNotRunFailureCleanup() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        var cleanups = 0
        let result = try await coordinator.withPlacementLifetime({ 7 }, cleanupOnFailure: { cleanups += 1 })
        XCTAssertEqual(result, 7)
        XCTAssertEqual(cleanups, 0)
    }

    func testRetirementAfterSuccessfulAddStillRunsCleanupExactlyOnce() async {
        let coordinator = LocalPitchAnchorCoordinator()
        var cleanups = 0
        do {
            _ = try await coordinator.withPlacementLifetime({
                await coordinator.removeLocallyPlacedPitchAnchor()
                return UUID()
            }, cleanupOnFailure: { cleanups += 1 })
            XCTFail("A completed add with retired intent must not be committed")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(cleanups, 1)
        XCTAssertNil(coordinator.sharedPitchAnchorID)
    }

    func testRestartWhileCleanupIsSuspendedCannotPublishTheOldError() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let started = expectation(description: "Old provider cleanup is suspended")
        var resume: CheckedContinuation<Void, Never>?
        var cleanups = 0
        let operation = Task { @MainActor in
            try await coordinator.withPlacementLifetime({
                throw TestError.providerFailure
            }, cleanupOnFailure: {
                cleanups += 1
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
            })
        }
        await fulfillment(of: [started], timeout: 2)
        guard let resume else { operation.cancel(); return }
        coordinator.stop()
        let fresh = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)
        coordinator.recordLocalPlacement(fresh)
        resume.resume()
        do {
            try await operation.value
            XCTFail("A cleanup completion from the retired session must be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(coordinator.sharedPitchAnchorID, fresh.id)
        XCTAssertTrue(coordinator.placedPitchAnchorLocally)
    }

    func testTaskCancellationDuringCleanupWinsOverTheProviderError() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let started = expectation(description: "Cleanup is suspended")
        var resume: CheckedContinuation<Void, Never>?
        let operation = Task { @MainActor in
            try await coordinator.withPlacementLifetime({
                throw TestError.providerFailure
            }, cleanupOnFailure: {
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
            })
        }
        await fulfillment(of: [started], timeout: 2)
        guard let resume else { operation.cancel(); return }
        operation.cancel()
        resume.resume()
        do {
            try await operation.value
            XCTFail("Cancellation during cleanup must remain intentional cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testEndDrillDuringCleanupDoesNotLeakAnErrorIntoTheNextPreflight() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        let started = expectation(description: "Placement cleanup is suspended")
        var resume: CheckedContinuation<Void, Never>?
        let operation = Task { @MainActor in
            try await coordinator.withPlacementLifetime({
                throw TestError.providerFailure
            }, cleanupOnFailure: {
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
            })
        }
        await fulfillment(of: [started], timeout: 2)
        guard let resume else { operation.cancel(); return }
        await coordinator.removeLocallyPlacedPitchAnchor()
        resume.resume()
        do {
            try await operation.value
            XCTFail("The retired placement must not surface its old provider error")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let fresh = try await coordinator.withPlacementLifetime { 42 }
        XCTAssertEqual(fresh, 42)
    }

    func testPreCancelledPlacementDoesNotCallProviderOrCleanup() async {
        let coordinator = LocalPitchAnchorCoordinator()
        var providerCalls = 0
        var cleanups = 0
        let operation = Task { @MainActor in
            try await coordinator.withPlacementLifetime({
                providerCalls += 1
                return 7
            }, cleanupOnFailure: { cleanups += 1 })
        }
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("A pre-cancelled task must not place anything")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(providerCalls, 0)
        XCTAssertEqual(cleanups, 0)
    }

    func testEndDrillRejectsPendingPlacementWithoutStoppingSession() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        do {
            _ = try await coordinator.withPlacementLifetime {
                // No anchor has been committed yet. Retiring must still cancel
                // this in-flight placement rather than do nothing.
                await coordinator.removeLocallyPlacedPitchAnchor()
                return UUID()
            }
            XCTFail("A late add must not restore the ended drill")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        // Retirement is narrower than session invalidation: other world
        // tracking operations and a deliberately new placement remain valid.
        let value = try await coordinator.withSessionLifetime { 8 }
        XCTAssertEqual(value, 8)
        let newPlacement = try await coordinator.withPlacementLifetime { 9 }
        XCTAssertEqual(newPlacement, 9)
    }

    func testExplicitRetirementClearsPublishedAnchorWithoutUnexpectedLossCallback() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let anchor = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)
        coordinator.recordLocalPlacement(anchor)
        XCTAssertEqual(coordinator.sharedPitchAnchorID, anchor.id)
        XCTAssertTrue(coordinator.placedPitchAnchorLocally)
        XCTAssertNotNil(coordinator.pitchOriginTransform)
        coordinator.onSelectedAnchorRemoved = { _ in
            XCTFail("Explicit retirement is not unexpected tracking loss")
        }

        await coordinator.removeLocallyPlacedPitchAnchor()

        XCTAssertNil(coordinator.sharedPitchAnchorID)
        XCTAssertNil(coordinator.pitchOriginTransform)
        XCTAssertNil(coordinator.horizontalHeadsetPose)
        XCTAssertFalse(coordinator.placedPitchAnchorLocally)
        XCTAssertFalse(coordinator.isPitchAnchorTracked)
        XCTAssertEqual(coordinator.status, .stopped)
        await coordinator.removeLocallyPlacedPitchAnchor()
        XCTAssertNil(coordinator.sharedPitchAnchorID)
    }

    func testCleanupForAnOldAnchorDoesNotRetireNewPlacementOrItsIntent() async throws {
        let coordinator = LocalPitchAnchorCoordinator()
        let old = UUID()
        let current = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)
        coordinator.recordLocalPlacement(current)
        let result = try await coordinator.withPlacementLifetime {
            await coordinator.removeLocallyPlacedPitchAnchor(ifMatching: old)
            return 7
        }
        XCTAssertEqual(result, 7, "An unrelated cleanup must not invalidate current placement intent")
        XCTAssertEqual(coordinator.sharedPitchAnchorID, current.id)
        XCTAssertTrue(coordinator.placedPitchAnchorLocally)
        XCTAssertNotNil(coordinator.pitchOriginTransform)
    }

    func testMatchingCleanupRetiresOnlyItsOwnedAnchor() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let current = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)
        coordinator.recordLocalPlacement(current)
        await coordinator.removeLocallyPlacedPitchAnchor(ifMatching: current.id)
        XCTAssertNil(coordinator.sharedPitchAnchorID)
        XCTAssertNil(coordinator.pitchOriginTransform)
        XCTAssertFalse(coordinator.placedPitchAnchorLocally)
    }

    func testRetirementDuringSuspendedAddRejectsResumedOperation() async {
        let coordinator = LocalPitchAnchorCoordinator()
        let started = expectation(description: "Placement suspended")
        var resume: CheckedContinuation<UUID, Never>?
        let pending = Task { @MainActor in
            try await coordinator.withPlacementLifetime {
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        await coordinator.removeLocallyPlacedPitchAnchor()
        resume?.resume(returning: UUID())
        do {
            _ = try await pending.value
            XCTFail("Retirement must defeat a real delayed completion")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
