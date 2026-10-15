import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

final class ReplayPlayerDetailTests: XCTestCase {
    func testRawPreferenceDefaultsAndCapacities() {
        XCTAssertEqual(ReplayPlayerDetail.defaultSelection, .fullSquad)
        XCTAssertEqual(ReplayPlayerDetail.storageKey, "ReplayXI.PlayerDetail.v2")
        for value in ReplayPlayerDetail.allCases {
            XCTAssertEqual(ReplayPlayerDetail.resolved(value.rawValue), value)
        }
        for raw in ["", "future", "FULLSQUAD", "full-squad"] {
            XCTAssertEqual(ReplayPlayerDetail.resolved(raw), .fullSquad)
        }
        XCTAssertEqual(ReplayPlayerDetail.balanced.maximumSkinnedPlayers, 4)
        XCTAssertFalse(ReplayPlayerDetail.balanced.allowsFirstPersonLowSkins)
        XCTAssertFalse(ReplayPlayerDetail.balanced.allowsShapeReplayLowSkins)
        XCTAssertEqual(ReplayPlayerDetail.fullSquad.maximumSkinnedPlayers, 22)
        XCTAssertTrue(ReplayPlayerDetail.fullSquad.allowsFirstPersonLowSkins)
        XCTAssertTrue(ReplayPlayerDetail.fullSquad.allowsShapeReplayLowSkins)
        XCTAssertEqual(ReplayPlayerDetail.maximumSquadSize, 22)
    }

    func testSameChoiceAndBlockedPlaybackViewCannotChangePreference() {
        // The caller supplies its active-edit/view permission. This pure model
        // test does not claim to exercise gesture ownership in PlaybackStore.
        for current in ReplayPlayerDetail.allCases {
            for target in ReplayPlayerDetail.allCases {
                for permitted in [false, true] {
                    XCTAssertEqual(target.canSelect(from: current, canChangePlaybackView: permitted),
                                   permitted && target != current)
                }
            }
        }
    }
}

/// Shipping preference path only: the old DEBUG experiment stays off.
@MainActor
final class ReplayPlayerDetailSceneTests: XCTestCase {
    private typealias Skin = ReplaySkinnedAthleteInstance
    private struct Context {
        let scenario: ReplayScenario
        let recording: ReplayNativeBallPhysics.Recording
    }
    private struct Pose: Equatable {
        let detail: ReplaySkinnedAthleteProvider.Detail
        let joints: [Transform]
        let front: Transform
        let back: Transform
        init(_ skin: Skin) {
            detail = skin.detail; joints = skin.model.jointTransforms
            front = skin.front.transform; back = skin.back.transform
        }
    }
    private final class WeakRoot {
        weak var value: Entity?
        init(_ value: Entity) { self.value = value }
    }
    private final class WeakSkin {
        weak var value: Skin?
        init(_ value: Skin) { self.value = value }
    }
    private var roots: [WeakRoot] = []
    private var retainedSkinChecks: [WeakSkin] = []

    override func setUp() {
        super.setUp()
        PitchSceneFactory.fullSquadSkinsForTesting = false
        resetProviders()
    }

    override func tearDown() {
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        if let scenario = FootballReferenceScenarios.all.first(where: { $0.id == "final-108-rebound-v2" }) {
            // Cold cache creation prunes released scene owners and their skins.
            let empty = Entity(), marks = Entity()
            marks.name = "marks-root"; empty.addChild(marks)
            PitchSceneFactory.update(root: empty, scenario: scenario, time: 0, viewMode: .firstPerson,
                perspectiveID: "arg-23", marks: [], showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: nil)
            for child in Array(empty.children) { child.removeFromParent() }
        }
        XCTAssertTrue(roots.allSatisfy { $0.value == nil })
        XCTAssertTrue(retainedSkinChecks.allSatisfy { $0.value == nil })
        roots.removeAll(); retainedSkinChecks.removeAll()
        resetProviders()
        super.tearDown()
    }

    func testExplicitFullSquadInThreeViewsReturnsToBalancedWithoutChangingSceneInputs() async throws {
        let context = try await prepare()
        let mark = CoachMark(kind: .run, start: .zero, end: PitchPoint(x: 8, z: 32), label: "Detail check",
                             startTrackAnchor: .init(playerID: "arg-10"))
        for view in [ReplayViewMode.tacticalTable, .firstPerson, .touchline] {
            try withScene(context) { root in
                update(root, context, view: view, detail: .balanced, marks: [mark])
                let balanced = try census(root, context, view: view, expected: view == .firstPerson ? 2 : 4)
                let bodyTransforms = try transforms(root, context)
                let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
                let arrow = try XCTUnwrap(markRoot.findEntity(named: "annotation-mark-arrow"))
                let annotationBefore = [markRoot.transform, arrow.transform]

                PitchSceneFactory.resetAnnotationSceneWorkForTesting()
                update(root, context, view: view, detail: .fullSquad, marks: [mark])
                let full = try census(root, context, view: view, expected: view == .firstPerson ? 21 : 22)
                assertTransition(balanced, full)
                XCTAssertEqual(try transforms(root, context), bodyTransforms)
                XCTAssertTrue(markRoot === root.findEntity(named: "mark-\(mark.id.uuidString)"))
                XCTAssertEqual([markRoot.transform, arrow.transform], annotationBefore)
                XCTAssertEqual(PitchSceneFactory.annotationSceneWork.markTreeBuilds, 0)
                XCTAssertEqual(PitchSceneFactory.annotationSceneWork.semanticRevisions, 0)
                let saved = full.mapValues(Pose.init)

                update(root, context, view: view, detail: .balanced, marks: [mark])
                let returned = try census(root, context, view: view, expected: view == .firstPerson ? 2 : 4)
                assertTransition(full, returned)
                for (id, skin) in balanced { XCTAssertTrue(returned[id] === skin) }
                XCTAssertEqual(try transforms(root, context), bodyTransforms)
                XCTAssertEqual([markRoot.transform, arrow.transform], annotationBefore)

                update(root, context, view: view, detail: .fullSquad, marks: [mark])
                XCTAssertEqual(skins(root).mapValues(Pose.init), saved)
                update(root, context, time: 1.2, view: view, detail: .fullSquad, marks: [mark])
                update(root, context, view: view, detail: .fullSquad, marks: [mark])
                XCTAssertEqual(skins(root).mapValues(Pose.init), saved)
                XCTAssertEqual(try transforms(root, context), bodyTransforms)
                XCTAssertEqual([markRoot.transform, arrow.transform], annotationBefore)
            }
        }
    }

    func testPausedFullSquadAnnotationSelectionAndEndpointEditKeepPickingOwnership() async throws {
        let context = try await prepare()
        let mark = CoachMark(kind: .run, start: .zero, end: PitchPoint(x: 8, z: 32), label: "Paused edit",
                             startTrackAnchor: .init(playerID: "arg-10"))
        try withScene(context) { root in
            update(root, context, view: .tacticalTable, detail: .fullSquad, marks: [mark])
            let initial = try census(root, context, view: .tacticalTable, expected: 22)
            let target = try XCTUnwrap(root.findEntity(named: "player-arg-13")?.findEntity(named: "interaction-target"))
            let bodyBefore = try transforms(root, context)
            XCTAssertTrue(target.isEnabledInHierarchy)
            update(root, context, view: .tacticalTable, detail: .fullSquad, marks: [mark], selected: mark.id)
            XCTAssertFalse(target.isEnabledInHierarchy)
            let selection = try XCTUnwrap(root.findEntity(named: AnnotationSceneAffordance.selectionRootName))
            let end = try XCTUnwrap(selection.findEntity(named: "annotation-target-end-\(mark.id.uuidString)"))
            XCTAssertTrue(selection.isEnabledInHierarchy)
            XCTAssertTrue(end.isEnabledInHierarchy)
            XCTAssertNotNil(end.components[CollisionComponent.self])
            XCTAssertNotNil(end.components[InputTargetComponent.self])
            XCTAssertEqual(AnnotationSceneAffordance.targetAncestor(of: end), .init(markID: mark.id, role: .end))
            let before = end.position
            let edited = CoachMark(id: mark.id, kind: mark.kind, start: mark.start,
                end: PitchPoint(x: mark.end.x + 2, z: mark.end.z + 3), label: mark.label,
                startTrackAnchor: mark.startTrackAnchor)
            update(root, context, view: .tacticalTable, detail: .fullSquad, marks: [edited], selected: mark.id)
            XCTAssertEqual(end.position.x, before.x + 2, accuracy: 0.0001)
            XCTAssertEqual(end.position.z, before.z + 3, accuracy: 0.0001)
            XCTAssertFalse(target.isEnabledInHierarchy)
            XCTAssertEqual(try transforms(root, context), bodyBefore)
            assertTransition(initial, skins(root))

            // Paused redraw/quality propagation must not steal active endpoint
            // picking. The UI permission gate is tested separately above.
            update(root, context, view: .tacticalTable, detail: .balanced, marks: [edited], selected: mark.id)
            XCTAssertFalse(target.isEnabledInHierarchy)
            XCTAssertTrue(end.isEnabledInHierarchy)
            update(root, context, view: .tacticalTable, detail: .fullSquad, marks: [edited])
            XCTAssertTrue(target.isEnabledInHierarchy)
            XCTAssertFalse(selection.isEnabledInHierarchy)
            _ = try census(root, context, view: .tacticalTable, expected: 22)
        }
    }

    func testExplicitFullSquadWithoutLowPreparationKeepsNearAndVisibleFarFallback() async throws {
        let context = try await prepare(low: false)
        for view in [ReplayViewMode.tacticalTable, .firstPerson, .touchline] {
            ReplaySkinnedAthleteProvider.resetLowDetailForTesting()
            try withScene(context) { root in
                update(root, context, view: view, detail: .fullSquad)
                let near = try census(root, context, view: view, expected: view == .firstPerson ? 2 : 1)
                XCTAssertTrue(near.values.allSatisfy { $0.detail == .near })
                let before = try transforms(root, context)
                try ReplaySkinnedAthleteProvider.prewarmLowDetail()
                update(root, context, view: view, detail: .fullSquad)
                let prepared = try census(root, context, view: view, expected: view == .firstPerson ? 21 : 22)
                assertTransition(near, prepared)
                XCTAssertEqual(try transforms(root, context), before)
            }
        }
    }

    private func prepare(low: Bool = true) async throws -> Context {
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled, "Default native skin path only")
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        try ReplaySkinnedAthleteProvider.prewarm()
        if low { try ReplaySkinnedAthleteProvider.prewarmLowDetail() }
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
            plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        XCTAssertEqual(recording.samples.count, 841)
        XCTAssertEqual(recording.missedTouchCount, 0)
        return Context(scenario: scenario, recording: recording)
    }

    private func withScene<T>(_ context: Context, body: (Entity) throws -> T) rethrows -> T {
        let root = PitchSceneFactory.makeMatchRoot(for: context.scenario, nativeRecording: context.recording)
        roots.append(WeakRoot(root))
        defer { for child in Array(root.children) { child.removeFromParent() } }
        return try body(root)
    }

    private func update(_ root: Entity, _ context: Context, time: Double = 0.3, view: ReplayViewMode,
                        detail: ReplayPlayerDetail, marks: [CoachMark] = [], selected: UUID? = nil) {
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        PitchSceneFactory.update(root: root, scenario: context.scenario, time: time, viewMode: view,
            perspectiveID: "arg-23", marks: marks, selectedAnnotationID: selected,
            selectedAnnotationIsEditable: selected != nil, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil, playerDetail: detail)
        XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: root) === context.recording)
        let sample = context.recording.sample(at: time)
        XCTAssertEqual(root.findEntity(named: "ball")?.position,
                       [sample.position.x, max(sample.position.y, 0.11), sample.position.z])
        XCTAssertEqual(root.findEntity(named: "ball")?.orientation.vector, sample.orientation.vector)
        for skin in skins(root).values where !retainedSkinChecks.contains(where: { $0.value === skin }) {
            retainedSkinChecks.append(WeakSkin(skin))
        }
    }

    private func skins(_ root: Entity) -> [String: Skin] { PitchSceneFactory.skinnedAthletesForTesting(in: root) }

    private func transforms(_ root: Entity, _ context: Context) throws -> [String: Transform] {
        try Dictionary(uniqueKeysWithValues: context.scenario.players.map { player in
            (player.id, try XCTUnwrap(root.findEntity(named: "player-\(player.id)")).transform)
        })
    }

    private func census(_ root: Entity, _ context: Context, view: ReplayViewMode, expected: Int) throws -> [String: Skin] {
        let admitted = skins(root)
        XCTAssertEqual(admitted.count, expected)
        if view == .firstPerson {
            XCTAssertEqual(admitted.values.filter { $0.detail == .near }.count, 2)
            XCTAssertNil(admitted["arg-23"])
        }
        for player in context.scenario.players {
            let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            let far = try XCTUnwrap(body.children.first { $0.name == "table-marker" })
            let full = body.children.first { $0.name == "full-rig" }
            let attached = body.children.filter { $0.name == ReplaySkinnedAthleteProvider.visualRootName }
            XCTAssertEqual(attached.count, admitted[player.id] == nil ? 0 : 1)
            if view == .firstPerson && player.id == "arg-23" {
                XCTAssertTrue(attached.isEmpty)
                XCTAssertNil(full)
                XCTAssertFalse(far.isEnabledInHierarchy)
                XCTAssertFalse(try XCTUnwrap(body.findEntity(named: "interaction-target")).isEnabledInHierarchy)
                continue
            }
            let visible = [admitted[player.id]?.model.isEnabledInHierarchy == true,
                           models(far).contains { $0.isEnabledInHierarchy },
                           full.map { models($0).contains { $0.isEnabledInHierarchy } } ?? false]
            XCTAssertEqual(visible.filter { $0 }.count, 1, player.id)
            if let skin = admitted[player.id] {
                XCTAssertTrue(skin.root.parent === body)
                XCTAssertTrue(skin.model.isEnabledInHierarchy)
                XCTAssertFalse(far.isEnabledInHierarchy)
            }
        }
        return admitted
    }

    private func models(_ root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? []) + root.children.flatMap { models($0) }
    }

    private func assertTransition(_ before: [String: Skin], _ after: [String: Skin]) {
        for (id, old) in before {
            if let current = after[id], current.detail == old.detail { XCTAssertTrue(current === old, id) }
            else { XCTAssertNil(old.root.parent, id) }
        }
    }

    private func resetProviders() {
        ReplayTripoAthleteProvider.resetForTesting()
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
    }
}
