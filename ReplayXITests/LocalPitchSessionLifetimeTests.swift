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
}
