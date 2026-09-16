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
