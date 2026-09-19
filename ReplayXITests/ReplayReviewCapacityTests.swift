import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewCapacityTests: XCTestCase {
    func testKeyframeHeavyLibraryReportsItsLimitAndPreservesTheLastSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayCapacity-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reviews.json")
        let store = ReplayStore()
        let base = store.makeSavedReviewState()
        let prototype = CoachMark(kind: .arc, start: .init(x: 0, z: 0), end: .init(x: 8, z: 10),
            curve: .init(bend: 2, lift: 1), label: "Saved run")
        let frames = (0..<CoachMark.maximumKeyframes).map {
            CoachMarkKeyframe(time: Double($0) * store.selectedScenario.duration / 63, mark: prototype)
        }
        let marks = (0..<ReplayStore.maximumSharedCoachMarks).map { _ in
            CoachMark(kind: .arc, start: prototype.start, end: prototype.end,
                curve: prototype.curve, label: prototype.label, keyframes: frames)
        }
        var scenarios = base.marksByScenario
        scenarios[base.scenarioID] = marks
        let heavy = SavedReplayState(scenarioID: base.scenarioID, playhead: base.playhead,
            playbackRate: base.playbackRate, viewMode: base.viewMode, perspectiveID: base.perspectiveID,
            showsLaneLens: base.showsLaneLens, shapeFocusStage: base.shapeFocusStage, marksByScenario: scenarios)
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: url)
        XCTAssertTrue(library.accepts(heavy))
        XCTAssertTrue(library.autosave(base))
        var hitByteLimit = false
        for index in 0..<ReplayReviewLibrary.maximumSavedReviews {
            let before = library.savedReviews
            let bytes = try Data(contentsOf: url)
            if !library.save(named: "Keyed review \(index)", state: heavy) {
                hitByteLimit = true
                XCTAssertLessThan(before.count, ReplayReviewLibrary.maximumSavedReviews)
                XCTAssertEqual(library.status, "Review library full. Delete a saved review or reduce annotations.")
                XCTAssertEqual(library.savedReviews, before)
                XCTAssertEqual(try Data(contentsOf: url), bytes)
                XCTAssertEqual(library.autosavedReview?.state, base)
                XCTAssertFalse(library.isReadOnly)
                break
            }
        }
        XCTAssertTrue(hitByteLimit, "Exercise the byte cap, not only the review-count cap")
        let reopened = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: url)
        XCTAssertEqual(reopened.savedReviews, library.savedReviews)
        let oldest = try XCTUnwrap(reopened.savedReviews.last)
        XCTAssertTrue(reopened.delete(id: oldest.id))
        XCTAssertTrue(reopened.save(named: "After freeing space", state: heavy))
    }
}
