import XCTest
@testable import ReplayXI

@MainActor
final class AuthoredCoachMarkIDCacheTests: XCTestCase {
    func testCacheTracksScenarioSwitches() {
        let base = DemoScenarios.all[0]
        let firstMark = mark(label: "First authored")
        let secondMark = mark(label: "Second authored")
        let first = scenario(base, id: "first", coachMarks: [firstMark])
        let second = scenario(base, id: "second", coachMarks: [secondMark])
        let store = ReplayStore(scenarios: [first, second])

        XCTAssertFalse(store.removeCoachMark(id: firstMark.id))
        store.selectScenario(id: second.id)
        XCTAssertEqual(store.selectedScenarioIndex, 1)
        XCTAssertFalse(store.removeCoachMark(id: secondMark.id))
    }

    func testUnknownSelectedIDUsesFirstScenarioCache() {
        let base = DemoScenarios.all[0]
        let authored = mark(label: "Fallback authored")
        let first = scenario(base, id: "first", coachMarks: [authored])
        let second = scenario(base, id: "second", coachMarks: [])
        let store = ReplayStore(scenarios: [first, second])
        store.selectedScenarioID = "unknown"

        XCTAssertEqual(store.selectedScenarioIndex, 0)
        XCTAssertEqual(store.selectedScenario.id, first.id)
        XCTAssertFalse(store.removeCoachMark(id: authored.id))
    }

    func testDuplicateScenarioIDsUseFirstMatchingScenarioCache() {
        let base = DemoScenarios.all[0]
        let firstAuthored = mark(label: "First duplicate authored")
        let secondAuthored = mark(label: "Second duplicate authored")
        let first = scenario(base, id: "duplicate", coachMarks: [firstAuthored])
        let second = scenario(base, id: "duplicate", coachMarks: [secondAuthored])
        let store = ReplayStore(scenarios: [first, second])
        store.marks = [firstAuthored, secondAuthored]

        XCTAssertEqual(store.selectedScenarioIndex, 0)
        XCTAssertFalse(store.removeCoachMark(id: firstAuthored.id))
        XCTAssertTrue(store.removeCoachMark(id: secondAuthored.id))
    }

    func testExistingAuthoredMarksRemainProtectedFromRemovalAndClear() {
        let base = DemoScenarios.all[0]
        let authored = mark(label: "Authored")
        let userMark = mark(label: "User")
        let store = ReplayStore(scenarios: [scenario(base, id: "one", coachMarks: [authored])])
        store.marks = [authored, userMark]

        XCTAssertFalse(store.removeCoachMark(id: authored.id))
        store.clearMarks()

        XCTAssertEqual(store.marks, [authored])
    }

    private func scenario(_ source: ReplayScenario, id: String,
                          coachMarks: [CoachMark]) -> ReplayScenario {
        ReplayScenario(
            id: id,
            kind: source.kind,
            title: source.title,
            strapline: source.strapline,
            matchContext: source.matchContext,
            objective: source.objective,
            coachPrompt: source.coachPrompt,
            proofPoint: source.proofPoint,
            duration: source.duration,
            defaultViewMode: source.defaultViewMode,
            defaultPerspectiveID: source.defaultPerspectiveID,
            featuredPerspectiveIDs: source.featuredPerspectiveIDs,
            players: source.players,
            ball: source.ball,
            moments: source.moments,
            coachMarks: coachMarks,
            formationTargets: source.formationTargets
        )
    }

    private func mark(label: String) -> CoachMark {
        CoachMark(kind: .run, start: .zero, end: PitchPoint(x: 4, z: 6), label: label)
    }
}
