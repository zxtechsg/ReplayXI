import Network
import XCTest
@testable import ReplayXICoachMac

@MainActor
final class CoachDiscovery185Tests: XCTestCase {
    func testDeniedBonjourPermissionIsActionable() {
        let message = ReplayXIMacLink.discoveryFailure(.dns(-65570))
        XCTAssertTrue(message.contains("Local Network blocked"))
        XCTAssertTrue(message.contains("Privacy & Security"))
        XCTAssertTrue(message.contains("Rescan"))
    }

    func testOtherDiscoveryErrorsAreNotMisreportedAsCertificateFailure() {
        let message = ReplayXIMacLink.discoveryFailure(.posix(.ENETDOWN))
        XCTAssertTrue(message.contains("Wi-Fi"))
        XCTAssertFalse(message.lowercased().contains("certificate"))
    }

    func testSharedConnectionDefaultFindsHeadsetsWithoutReadingProtectedSourceFiles() {
        // Both SwiftUI bindings use this single key/default. Runtime tests must
        // not open source files in Documents and trigger a macOS privacy prompt.
        XCTAssertEqual(ReplayXIMacLink.connectionTargetKey, "ReplayXI.coachConnectionTarget.v2")
        XCTAssertEqual(ReplayXIMacLink.defaultConnectionTarget, "headset")
    }
}
