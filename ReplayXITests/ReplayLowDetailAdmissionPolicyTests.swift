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
        cap: Int = 4,
        allowsFirstPerson: Bool = false,
        allowsShapeReplay: Bool = false
    ) -> Policy.State {
        Policy.resolve(previous: previous, scenarioID: scenarioID, scenarioKind: kind,
                       viewMode: view, perspectiveID: selected, posesByPlayerID: poses(distances),
                       nearPlayerIDs: near, maximumTotal: cap, lowDetailIsReady: ready,
                       allowsFirstPerson: allowsFirstPerson, allowsShapeReplay: allowsShapeReplay)
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

    func testCapacityExpansionThenShrinkSelectsClosestInsteadOfPreviousStickyMember() {
        let initial = resolve()
        let crossed: [String: Float] = ["selected": 0, "a": 1, "b": 2, "c": 3, "d": 2.9]
        let sticky = resolve(initial, distances: crossed)
        XCTAssertEqual(sticky.playerIDs, ["a", "b", "c"])
        XCTAssertLessThan(crossed["c"]! - crossed["d"]!, Policy.switchMargin)

        let expanded = resolve(sticky, distances: crossed, cap: 5)
        XCTAssertEqual(Set(expanded.playerIDs), ["a", "b", "c", "d"])
        XCTAssertEqual(expanded.context, sticky.context)
        let shrunk = resolve(expanded, distances: crossed)
        XCTAssertEqual(shrunk.playerIDs, ["a", "b", "d"])
        XCTAssertEqual(shrunk.context, sticky.context)
        XCTAssertNotEqual(shrunk.playerIDs, sticky.playerIDs)
        XCTAssertEqual(resolve(resolve(shrunk, distances: crossed, cap: 5), distances: crossed), shrunk)
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

    func testPOVExperimentFillsSquadButNeverAdmitsWearerOrNearSubjectsTwice() {
        let squad = Dictionary(uniqueKeysWithValues: (0..<22).map { ("p\($0)", Float($0)) })
        let near: Set<String> = ["p1", "p2"]
        let admitted = resolve(distances: squad, near: near, view: .firstPerson,
                               selected: "p0", cap: 22, allowsFirstPerson: true)
        XCTAssertEqual(admitted.playerIDs.count, 19)
        XCTAssertEqual(Set(admitted.playerIDs).count, 19)
        XCTAssertTrue(Set(admitted.playerIDs).isDisjoint(with: near.union(["p0"])))
        XCTAssertEqual(resolve(admitted, distances: squad, near: near, view: .firstPerson,
                               selected: "p0", cap: 22), Policy.State())
        XCTAssertTrue(resolve(distances: squad, near: near, kind: .shapeLab, view: .firstPerson,
                              selected: "p0", cap: 22, allowsFirstPerson: true).playerIDs.isEmpty)
        XCTAssertTrue(resolve(distances: squad, near: near, view: .positional,
                              selected: "p0", cap: 22, allowsFirstPerson: true).playerIDs.isEmpty)
        XCTAssertTrue(resolve(distances: squad, near: near, view: .firstPerson,
                              selected: "p0", ready: false, cap: 22,
                              allowsFirstPerson: true).playerIDs.isEmpty)
    }

    func testShippingDefaultCoversBothTeamsAcrossReplayViewsAndPOVChanges() {
        let squad = Dictionary(uniqueKeysWithValues: ["home", "away"].flatMap { team in
            (1...11).map { ("\(team)-\($0)", Float($0) * (team == "home" ? 1 : -1)) }
        })
        let detail = ReplayPlayerDetail.defaultSelection
        XCTAssertEqual(detail, .fullSquad)
        var state = Policy.State()
        for selected in ["home-1", "away-11", "home-1"] {
            for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson] {
                let near: Set<String> = view == .firstPerson
                    ? Set(squad.keys.filter { $0 != selected }.sorted().prefix(2)) : [selected]
                // The selected first-person body uses a separate admission
                // slot, never one of the visible neighbour slots.
                let ownerSlots = view == .firstPerson ? 1 : 0
                state = resolve(state, distances: squad, near: near, view: view,
                    selected: selected, cap: detail.maximumSkinnedPlayers - ownerSlots,
                    allowsFirstPerson: detail.allowsFirstPersonLowSkins)
                let admitted = Set(state.playerIDs).union(near)
                XCTAssertEqual(admitted.count + ownerSlots, 22)
                XCTAssertEqual(admitted.union([selected]), Set(squad.keys))
                XCTAssertTrue(Set(state.playerIDs).isDisjoint(with: near))
                XCTAssertEqual(state.playerIDs, state.playerIDs.sorted())
                if view == .firstPerson { XCTAssertFalse(admitted.contains(selected)) }
                XCTAssertEqual(state, resolve(state, distances: squad, near: near, view: view,
                    selected: selected, cap: detail.maximumSkinnedPlayers - ownerSlots,
                    allowsFirstPerson: detail.allowsFirstPersonLowSkins))
            }
        }
    }

    func testFullSquadFastPathNeverAdmitsInvalidTracksOrExceedsHardCap() {
        var squad = Dictionary(uniqueKeysWithValues: (0..<30).map { ("p\($0)", Float($0)) })
        let oversized = resolve(distances: squad, near: ["p0"], selected: "p0", cap: 1_000)
        XCTAssertEqual(oversized.playerIDs.count, 21)
        XCTAssertEqual(Set(oversized.playerIDs).count, 21)
        squad = ["p0": 0, "p1": 1, "p2": .infinity, "p3": .nan]
        XCTAssertEqual(resolve(distances: squad, near: ["p0"], selected: "p0", cap: 22).playerIDs, ["p1"])
    }

    func testUnchangedFullSquadReusesArrayStorageAndRevalidatesEveryMember() {
        let squad = Dictionary(uniqueKeysWithValues: (0..<22).map { ("p\($0)", Float($0)) })
        let initial = resolve(distances: squad, near: ["p0"], selected: "p0", cap: 22)
        func buffer(_ ids: [String]) -> UInt {
            ids.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        }
        for _ in 0..<32 {
            let repeated = resolve(initial, distances: squad, near: ["p0"], selected: "p0", cap: 22)
            XCTAssertEqual(repeated, initial)
            XCTAssertEqual(buffer(repeated.playerIDs), buffer(initial.playerIDs),
                           "No new membership Array or sort is needed for an unchanged full squad")
        }
        var invalid = squad
        invalid["p10"] = .nan
        XCTAssertFalse(resolve(initial, distances: invalid, near: ["p0"], selected: "p0", cap: 22)
            .playerIDs.contains("p10"))
        let duplicate = Policy.State(context: initial.context,
            playerIDs: Array(repeating: "p1", count: initial.playerIDs.count))
        XCTAssertEqual(resolve(duplicate, distances: squad, near: ["p0"], selected: "p0", cap: 22), initial)
        let unsorted = Policy.State(context: initial.context, playerIDs: Array(initial.playerIDs.reversed()))
        XCTAssertEqual(resolve(unsorted, distances: squad, near: ["p0"], selected: "p0", cap: 22), initial)
    }

    func testShapeReplayUsesExplicitSquadOptInWithoutAllocatingHiddenPositioningPlayers() {
        for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson] {
            let admitted = resolve(kind: .shapeLab, view: view, cap: 22,
                allowsFirstPerson: true, allowsShapeReplay: true)
            XCTAssertEqual(Set(admitted.playerIDs), ["a", "b", "c", "d"])
            XCTAssertTrue(resolve(kind: .shapeLab, view: view, cap: 22,
                allowsFirstPerson: true).playerIDs.isEmpty)
        }
        XCTAssertTrue(resolve(kind: .shapeLab, view: .positional, cap: 22,
            allowsFirstPerson: true, allowsShapeReplay: true).playerIDs.isEmpty)
        XCTAssertTrue(resolve(kind: .shapeLab, ready: false, cap: 22,
            allowsShapeReplay: true).playerIDs.isEmpty)
    }
}
