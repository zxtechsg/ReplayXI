import XCTest
@testable import ReplayXI

@MainActor
final class ReplayVideoReferenceTests: XCTestCase {
    func testSourceURLPointsToTheVideoAndStartTimestamp() throws {
        let reference = makeReference(start: 2_205, end: 2_220)
        let components = try XCTUnwrap(URLComponents(url: reference.sourceURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.youtube.com")
        XCTAssertEqual(components.path, "/watch")
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "v", value: "RgqKdplLIk4"),
            URLQueryItem(name: "t", value: "2205s")
        ])
    }

    func testRangeFormatsMinuteAndHourWindowsWithoutLocaleDependentDates() {
        XCTAssertEqual(makeReference(start: 0, end: 9).timeRangeLabel, "0:00–0:09")
        XCTAssertEqual(makeReference(start: 59, end: 61).timeRangeLabel, "0:59–1:01")
        XCTAssertEqual(makeReference(start: 2_205, end: 2_220).timeRangeLabel, "36:45–37:00")
        XCTAssertEqual(makeReference(start: 5_439, end: 5_460).timeRangeLabel, "1:30:39–1:31:00")
        XCTAssertEqual(makeReference(start: 7_779, end: 7_800).timeRangeLabel, "2:09:39–2:10:00")
    }

    func testSourceWindowNeverProducesNegativeOrReversedTimestamps() {
        let negative = makeReference(start: -5, end: -2)
        XCTAssertEqual(negative.startSeconds, 0)
        XCTAssertEqual(negative.endSeconds, 0)
        XCTAssertEqual(negative.timeRangeLabel, "0:00–0:00")
        let reversed = makeReference(start: 30, end: 20)
        XCTAssertEqual(reversed.endSeconds, 30)
        XCTAssertEqual(reversed.timeRangeLabel, "0:30–0:30")
    }

    func testVideoIDCannotInjectAdditionalURLQueryFields() throws {
        let reference = ReplayVideoReference(matchTitle: "Test", shortLabel: "Test",
            videoID: "test&list=other#fragment", startSeconds: 12, endSeconds: 18,
            reconstructionNote: "Authored reconstruction.")
        let components = try XCTUnwrap(URLComponents(url: reference.sourceURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.count, 2)
        XCTAssertEqual(components.queryItems?.first?.value, "test&list=other#fragment")
        XCTAssertNil(components.fragment)
    }

    func testProvenanceIdentityIncludesTheWindowAndReconstructionNote() {
        let reference = makeReference(start: 10, end: 20)
        XCTAssertEqual(reference, makeReference(start: 10, end: 20))
        XCTAssertNotEqual(reference, makeReference(start: 10, end: 21))
        XCTAssertEqual(Set([reference, reference]).count, 1)
        XCTAssertTrue(reference.reconstructionNote.contains("inferred"))
    }

    func testAllFiveFeaturedSourcesHaveExplicitUncertaintyAndVerifiedAngleLinks() throws {
        XCTAssertEqual(FootballReferenceScenarios.all.count, 5)
        for scenario in FootballReferenceScenarios.all {
            let reference = try XCTUnwrap(ReplayReferenceLibrary.reference(for: scenario.id))
            XCTAssertTrue(reference.reconstructionNote.contains("inferred"))
            XCTAssertTrue(reference.reconstructionNote.contains("not measured tracking"))
            XCTAssertGreaterThan(reference.endSeconds, reference.startSeconds)
            for angle in reference.alternateAngles {
                XCTAssertFalse(angle.title.isEmpty)
                XCTAssertGreaterThan(angle.startSeconds, 0)
                let url = try XCTUnwrap(URLComponents(url: reference.sourceURL(at: angle.startSeconds),
                                                     resolvingAgainstBaseURL: false))
                XCTAssertEqual(url.queryItems?.first?.value, reference.videoID)
                XCTAssertEqual(url.queryItems?.last?.value, "\(angle.startSeconds)s")
            }
        }
        XCTAssertTrue(DemoScenarios.all.allSatisfy { ReplayReferenceLibrary.reference(for: $0.id) == nil })
    }

    private func makeReference(start: Int, end: Int) -> ReplayVideoReference {
        ReplayVideoReference(matchTitle: "Argentina v France · 2022 final",
            shortLabel: "ARG–FRA · 36′", videoID: "RgqKdplLIk4",
            startSeconds: start, endSeconds: end,
            reconstructionNote: "Off-camera movement is inferred, not measured tracking.")
    }
}
