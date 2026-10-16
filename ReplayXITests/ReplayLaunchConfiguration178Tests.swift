import XCTest
@testable import ReplayXI

@MainActor
final class ReplayLaunchConfiguration178Tests: XCTestCase {
    private let oldDemoFlags = ["ReplayXI", "--replayxi-player-pov", "--replayxi-autostart",
                                "--replayxi-coach-mark", "--replayxi-saved-reviews"]

    func testStaleFlagsCannotAutoEnterPOVOrDisablePersistentReviews() {
        let launch = ReplayLaunchConfiguration(arguments: oldDemoFlags, environment: [:],
            hasXCTestRuntime: false, isDebugBuild: true)
        XCTAssertTrue(launch.automationArguments.isEmpty)
        XCTAssertFalse(launch.usesTransientReviews)
    }

    func testExplicitDebugDemoRemainsIsolatedAndAvailable() {
        let launch = ReplayLaunchConfiguration(arguments: oldDemoFlags + ["--replayxi-demo"], environment: [:],
            hasXCTestRuntime: false, isDebugBuild: true)
        XCTAssertTrue(launch.automationArguments.contains("--replayxi-autostart"))
        XCTAssertTrue(launch.usesTransientReviews)
        XCTAssertFalse(launch.automationArguments.contains("ReplayXI"))
    }

    func testTestHostNeverAutoOpensEvenWithDemoFlagsAndNeverWritesRealSaves() {
        for environment in [["XCTestConfigurationFilePath": "test.xctestconfiguration"],
                            ["XCTestBundlePath": "test.xctest"]] {
            let launch = ReplayLaunchConfiguration(arguments: oldDemoFlags + ["--replayxi-demo"],
                environment: environment, hasXCTestRuntime: false, isDebugBuild: true)
            XCTAssertTrue(launch.automationArguments.isEmpty)
            XCTAssertTrue(launch.usesTransientReviews)
        }
        let runtime = ReplayLaunchConfiguration(arguments: oldDemoFlags + ["--replayxi-demo"],
            environment: [:], hasXCTestRuntime: true, isDebugBuild: true)
        XCTAssertTrue(runtime.automationArguments.isEmpty)
        XCTAssertTrue(runtime.usesTransientReviews)
    }

    func testReleaseIgnoresAllDebugRoutesWithoutDiscardingUserSaves() {
        let launch = ReplayLaunchConfiguration(arguments: oldDemoFlags + ["--replayxi-demo"], environment: [:],
            hasXCTestRuntime: false, isDebugBuild: false)
        XCTAssertTrue(launch.automationArguments.isEmpty)
        XCTAssertFalse(launch.usesTransientReviews)
    }

    func testReopenedDashboardConsumesNoSecondAutoEntryOrDraft() {
        let launch = ReplayLaunchConfiguration(arguments: oldDemoFlags + ["--replayxi-demo"], environment: [:],
            hasXCTestRuntime: false, isDebugBuild: true)
        let session = ReplayLaunchSession(configuration: launch)
        XCTAssertNotNil(session.consumeArguments(for: "dashboard"))
        XCTAssertNil(session.consumeArguments(for: "dashboard"))
        XCTAssertNotNil(session.consumeArguments(for: "saved-review-sheet"))
        XCTAssertNil(session.consumeArguments(for: "saved-review-sheet"))
    }

    func testUnknownReplayFlagDoesNotDisableReviewPersistence() {
        let launch = ReplayLaunchConfiguration(arguments: ["--replayxi-unknown"], environment: [:],
            hasXCTestRuntime: false, isDebugBuild: true)
        XCTAssertFalse(launch.usesTransientReviews)
        XCTAssertTrue(launch.automationArguments.isEmpty)
    }
}
