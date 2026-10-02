import ARKit
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class LocalPitchSurfaceLifecycleTests: XCTestCase {
    func testExplicitSurfaceRequestCannotReplaceActivePhysicalPractice() async {
        let coordinator = LocalPitchAnchorCoordinator(), owner = UUID()
        coordinator.claimTracking(for: owner)
        let anchor = WorldAnchor(originFromAnchorTransform: matrix_identity_float4x4)
        coordinator.recordLocalPlacement(anchor)
        let oldStatus = coordinator.status
        await coordinator.startSurfaceDetection(for: UUID())
        XCTAssertTrue(coordinator.ownsTracking(for: owner))
        XCTAssertEqual(coordinator.sharedPitchAnchorID, anchor.id)
        XCTAssertEqual(coordinator.status, oldStatus)
        XCTAssertTrue(coordinator.placedPitchAnchorLocally)
        XCTAssertFalse(coordinator.isRunning, "Rejected scan must not start an ARKit session")
        guard case .unavailable = coordinator.surfaceDetectionStatus else { return XCTFail("Expected practice gate") }
    }

    func testCancelledScanDoesNotClaimSessionOrAskForAuthorization() async {
        let coordinator = LocalPitchAnchorCoordinator(), owner = UUID()
        let task = Task { @MainActor in await coordinator.startSurfaceDetection(for: owner) }
        task.cancel()
        await task.value
        XCTAssertFalse(coordinator.ownsTracking(for: owner))
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(coordinator.surfaceDetectionStatus, .stopped)
        XCTAssertTrue(coordinator.horizontalSurfaces.isEmpty)
    }

    func testStaleStopCannotChangeCurrentRoomAndNoScanCannotSnap() async {
        let coordinator = LocalPitchAnchorCoordinator(), owner = UUID()
        coordinator.claimTracking(for: owner)
        let revision = coordinator.surfaceRevision
        await coordinator.stopSurfaceDetection(for: UUID())
        XCTAssertTrue(coordinator.ownsTracking(for: owner))
        XCTAssertEqual(coordinator.surfaceRevision, revision)
        XCTAssertNil(coordinator.snapPitchToSurface(near: .zero, yawRadians: 0))
        await coordinator.stopSurfaceDetection(for: owner)
        XCTAssertTrue(coordinator.ownsTracking(for: owner), "Plane stop does not own world-tracking teardown")
        XCTAssertGreaterThan(coordinator.surfaceRevision, revision)
        XCTAssertEqual(coordinator.surfaceDetectionStatus, .stopped)
    }
}
