import XCTest
@testable import ReplayXI

final class ReplayEnvironmentMode169Tests: XCTestCase {
    func testReplayCanChooseStadiumOrPassthrough() {
        XCTAssertEqual(ReplayEnvironmentMode.defaultSelection, .stadium)
        XCTAssertEqual(ReplayEnvironmentMode.effective("stadium", isPhysicalPractice: false), .stadium)
        XCTAssertEqual(ReplayEnvironmentMode.effective("room", isPhysicalPractice: false), .room)
    }

    func testPhysicalPracticeAndInvalidPreferencesKeepPassthrough() {
        for raw in ["stadium", "room", "unknown", ""] {
            XCTAssertEqual(ReplayEnvironmentMode.effective(raw, isPhysicalPractice: true), .room)
        }
        XCTAssertEqual(ReplayEnvironmentMode.effective("unknown", isPhysicalPractice: false), .room)
        // Resolving a safety override is pure; replay can still use its choice.
        XCTAssertEqual(ReplayEnvironmentMode.effective("stadium", isPhysicalPractice: false), .stadium)
    }
}
