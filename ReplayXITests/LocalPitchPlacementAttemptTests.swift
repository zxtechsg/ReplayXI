import Foundation
import XCTest
@testable import ReplayXI

final class LocalPitchPlacementAttemptTests: XCTestCase {
    func testOnlyOneAttemptCanOwnThePreflight() throws {
        var attempt = LocalPitchPlacementAttempt()
        XCTAssertFalse(attempt.isPending)
        let request = try XCTUnwrap(attempt.begin())
        XCTAssertTrue(attempt.isPending)
        XCTAssertTrue(attempt.owns(request))
        XCTAssertNil(attempt.begin(), "A second tap before the provider starts must not place twice")
        XCTAssertEqual(attempt.id, request)
    }

    func testCancelledAttemptCannotFinishOrClaimAReopenedPreflight() throws {
        var attempt = LocalPitchPlacementAttempt()
        let old = try XCTUnwrap(attempt.begin())
        attempt.cancel()
        let fresh = try XCTUnwrap(attempt.begin())
        XCTAssertNotEqual(old, fresh)
        XCTAssertFalse(attempt.owns(old))
        XCTAssertFalse(attempt.finish(old))
        XCTAssertEqual(attempt.id, fresh, "Old cleanup must not clear a new task's handle")
        XCTAssertTrue(attempt.finish(fresh))
        XCTAssertFalse(attempt.isPending)
    }

    func testFinishingOnlyReleasesTheMatchingAttempt() throws {
        var attempt = LocalPitchPlacementAttempt()
        let request = try XCTUnwrap(attempt.begin())
        XCTAssertFalse(attempt.finish(UUID()))
        XCTAssertTrue(attempt.owns(request))
        XCTAssertTrue(attempt.finish(request))
        XCTAssertFalse(attempt.finish(request))
        XCTAssertNotNil(attempt.begin())
    }

    func testRepeatedCancellationDoesNotLeaveThePanelBusy() throws {
        var attempt = LocalPitchPlacementAttempt()
        attempt.cancel()
        for _ in 0..<20 {
            let request = try XCTUnwrap(attempt.begin())
            attempt.cancel()
            attempt.cancel()
            XCTAssertFalse(attempt.isPending)
            XCTAssertFalse(attempt.owns(request))
        }
    }
}
