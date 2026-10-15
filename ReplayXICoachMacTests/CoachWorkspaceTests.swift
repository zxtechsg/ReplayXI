import XCTest
@testable import ReplayXICoachMac

final class CoachWorkspaceTests: XCTestCase {
    func testVisibilityMatchesInclusiveStartExclusiveEnd() {
        var mark = fixture
        XCTAssertFalse(CoachWorkspace.isVisible(mark, at: 6.999))
        XCTAssertTrue(CoachWorkspace.isVisible(mark, at: 7))
        XCTAssertTrue(CoachWorkspace.isVisible(mark, at: 19.999))
        XCTAssertFalse(CoachWorkspace.isVisible(mark, at: 20))
        mark.hideAt = nil
        XCTAssertTrue(CoachWorkspace.isVisible(mark, at: 60))
    }

    func testSearchCombinesNameNumberAndTeamWithoutCaseOrAccentSensitivity() {
        let values = ["José Left winger", "#7", "home"]
        XCTAssertTrue(CoachWorkspace.matches("  JOSE 7 home  ", values: values))
        XCTAssertTrue(CoachWorkspace.matches(" ", values: values))
        XCTAssertFalse(CoachWorkspace.matches("7 away", values: values))
        XCTAssertFalse(CoachWorkspace.matches("#9", values: values))
    }

    func testVisibilityWindowRejectsInvalidOrInvertedTimes() {
        XCTAssertTrue(CoachWorkspace.validWindow(show: 0, hide: 60, duration: 60))
        XCTAssertTrue(CoachWorkspace.validWindow(show: 7, hide: nil, duration: 60))
        for (show, hide, duration) in [(7.0, 7.0, 60.0), (7, 6, 60), (-1, 7, 60),
            (7, 61, 60), (61, 62, 60), (0, 1, -1), (Double.nan, 8, 60),
            (7, Double.infinity, 60), (7, 8, Double.infinity)] {
            XCTAssertFalse(CoachWorkspace.validWindow(show: show, hide: hide, duration: duration))
        }
    }

    func testClockCarriesRoundingAcrossMinuteBoundary() {
        XCTAssertEqual(CoachWorkspace.clock(0), "00:00.0")
        XCTAssertEqual(CoachWorkspace.clock(59.96), "01:00.0")
        XCTAssertEqual(CoachWorkspace.clock(75.2), "01:15.2")
        XCTAssertEqual(CoachWorkspace.clock(-2), "00:00.0")
        XCTAssertEqual(CoachWorkspace.clock(.nan), "—")
        XCTAssertEqual(CoachWorkspace.clock(.greatestFiniteMagnitude), "—")
        XCTAssertEqual(CoachWorkspace.clock(-Double.greatestFiniteMagnitude), "00:00.0")
    }

    private var fixture: ReplayXIWireMark {
        .init(id: UUID(), kind: "arc", start: .init(x: -20, z: -28), end: .init(x: 8, z: 18),
            startHeight: 0.5, endHeight: 1.2, label: "Curved overlap", showAt: 7, hideAt: 20,
            keyframes: [7, 12, 18], authored: false, controlPoint: .init(x: -23, y: 3.2, z: 4),
            encodedMark: Data("{}".utf8))
    }
}
