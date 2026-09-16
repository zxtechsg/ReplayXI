import XCTest
@testable import ReplayXI

final class ReplayLowDetailAdmissionPolicyTests: XCTestCase {
    private typealias Policy = ReplayLowDetailAdmissionPolicy

    private func poses(_ distances: [String: Float]) -> [String: PlayerPose] {
        distances.mapValues { PlayerPose(position: PitchPoint(x: $0, z: 0), facingDegrees: 0) }
    }

    private func resolve(
        _ previous: Policy.State = .init(),
        distances: [String: Float] = ["selected": 0, "a": 1, "b": 2, "c": 3, "d": 4],
        near: Set<String> = ["selected"],
        kind: ExperienceKind = .squadReplay,
        view: ReplayViewMode = .tacticalTable,
        selected: String = "selected",
        scenarioID: String = "match",
        ready: Bool = true,
        cap: Int = 4
    ) -> Policy.State {
        Policy.resolve(previous: previous, scenarioID: scenarioID, scenarioKind: kind,
                       viewMode: view, perspectiveID: selected, posesByPlayerID: poses(distances),
                       nearPlayerIDs: near, maximumTotal: cap, lowDetailIsReady: ready)
    }

    func testFillsOnlySpareSlotsAndExcludesNearImpactSubjects() {
        XCTAssertEqual(resolve().playerIDs, ["a", "b", "c"])
        XCTAssertEqual(resolve(near: ["selected", "a"]).playerIDs, ["b", "c"])
        XCTAssertTrue(resolve(near: ["selected", "a", "b", "c"]).playerIDs.isEmpty)
        XCTAssertTrue(resolve(cap: 0).playerIDs.isEmpty)
        XCTAssertTrue(resolve(cap: -1).playerIDs.isEmpty)
    }

    func testEqualDistanceUsesTrackIdentityRatherThanDictionaryOrder() {
        let first = resolve(distances: ["selected": 0, "z": 1, "c": -1, "b": 1, "a": -1])
        let reordered = resolve(distances: ["a": -1, "b": 1, "c": -1, "z": 1, "selected": 0])
        XCTAssertEqual(first.playerIDs, ["a", "b", "c"])
        XCTAssertEqual(first, reordered)
    }

    func testCrossingNeighbourRetainsMembershipUntilClearChallenger() {
        let initial = resolve()
        let close = resolve(initial, distances: ["selected": 0, "a": 1, "b": 2, "c": 3, "d": 2.9])
        XCTAssertEqual(close.playerIDs, initial.playerIDs)
        let clear = resolve(close, distances: ["selected": 0, "a": 1, "b": 2, "c": 3, "d": 1.5])
        XCTAssertEqual(Set(clear.playerIDs), ["a", "b", "d"])
        XCTAssertEqual(Policy.switchMargin, 1.25)
        XCTAssertEqual(resolve(clear, distances: ["selected": 0, "a": 1, "b": 2, "c": 1.6, "d": 1.5]), clear)
    }

    func testNearPromotionShrinksMembershipBeforeAnyNewAllocation() {
        let initial = resolve()
        let promoted = resolve(initial, near: ["selected", "a"])
        XCTAssertEqual(Set(promoted.playerIDs), ["b", "c"])
        XCTAssertFalse(promoted.playerIDs.contains("a"))
        let shrunk = resolve(initial, near: ["selected", "d"])
        XCTAssertEqual(shrunk.playerIDs, ["a", "b"])
    }

    func testViewTransitionsPreserveEligibleContextButSelectionAndMatchResetIt() {
        let initial = resolve()
        let crossed = ["selected": Float(0), "a": 1, "b": 2, "c": 3, "d": 2.9]
        XCTAssertEqual(resolve(initial, distances: crossed, view: .touchline), initial)
        XCTAssertEqual(resolve(initial, distances: crossed, scenarioID: "other").playerIDs, ["a", "b", "d"])
        let changed = resolve(initial, distances: crossed, near: ["d"], selected: "d")
        XCTAssertEqual(changed.context?.perspectiveID, "d")
        XCTAssertEqual(changed.playerIDs, ["c", "b", "a"])
    }

    func testPOVShapePositioningAndUnpreparedProviderNeverAddLows() {
        let initial = resolve()
        for mode in [ReplayViewMode.firstPerson, .positional] {
            XCTAssertEqual(resolve(initial, view: mode), Policy.State())
        }
        for mode in ReplayViewMode.allCases {
            XCTAssertEqual(resolve(initial, kind: .shapeLab, view: mode), Policy.State())
        }
        XCTAssertEqual(resolve(initial, ready: false), Policy.State())
        let returned = resolve(resolve(initial, view: .firstPerson),
                               distances: ["selected": 0, "a": 1, "b": 2, "c": 3, "d": 2.9])
        XCTAssertEqual(returned.playerIDs, ["a", "b", "d"])
    }

    func testMissingOrNonfiniteTracksCannotConsumeAnExtraSlot() {
        XCTAssertTrue(resolve(distances: ["a": 1]).playerIDs.isEmpty)
        XCTAssertTrue(resolve(distances: ["selected": .nan, "a": 1]).playerIDs.isEmpty)
        let valid = resolve(distances: ["selected": 0, "a": 1, "b": .infinity, "c": .nan])
        XCTAssertEqual(valid.playerIDs, ["a"])
        let stale = Policy.State(context: valid.context, playerIDs: ["gone", "a", "a"])
        XCTAssertEqual(resolve(stale).playerIDs, ["a", "b", "c"])
    }
}
