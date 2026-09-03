import XCTest
@testable import ReplayXI

final class SpatialPlaybackIntentRouterTests: XCTestCase {
    func testShortGestureDriftRecoversTapIntent() {
        let start = PitchPoint(x: 12, z: -4)
        XCTAssertTrue(
            SpatialPlaybackIntentRouter.shouldRecoverTapIntent(
                from: start,
                to: PitchPoint(x: 12.25, z: -3.82)
            )
        )
        XCTAssertTrue(
            SpatialPlaybackIntentRouter.shouldRecoverTapIntent(
                from: start,
                to: PitchPoint(
                    x: start.x + SpatialPlaybackIntentRouter.maximumRecoveredTapTravelMetres,
                    z: start.z
                )
            )
        )
    }

    func testDeliberateOrMalformedTravelNeverBecomesATap() {
        let start = PitchPoint(x: 12, z: -4)
        XCTAssertFalse(
            SpatialPlaybackIntentRouter.shouldRecoverTapIntent(
                from: start,
                to: PitchPoint(x: 13.2, z: -4)
            )
        )
        XCTAssertFalse(
            SpatialPlaybackIntentRouter.shouldRecoverTapIntent(
                from: PitchPoint(x: .nan, z: 0),
                to: PitchPoint(x: 0, z: 0)
            )
        )
        XCTAssertFalse(
            SpatialPlaybackIntentRouter.shouldRecoverTapIntent(
                from: PitchPoint(x: 0, z: 0),
                to: PitchPoint(x: .infinity, z: 0)
            )
        )
    }
}
