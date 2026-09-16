import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayLowDetailSceneAdmissionTests: XCTestCase {
    private var roots: [Entity] = []

    override func setUp() {
        super.setUp()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
    }

    override func tearDown() {
        for root in roots {
            for child in Array(root.children) { child.removeFromParent() }
        }
        roots.removeAll()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func prepare(low: Bool = true, kind: ExperienceKind = .squadReplay) throws -> (ReplayScenario, Entity) {
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled,
                      "This test covers the default skin path, not the opt-in legacy pilot")
        try ReplaySkinnedAthleteProvider.prewarm()
        if low { try ReplaySkinnedAthleteProvider.prewarmLowDetail() }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: kind))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        roots.append(root)
        return (scenario, root)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: Double = 12,
                        view: ReplayViewMode = .tacticalTable, perspective: String? = nil,
                        cue: PlayerRagdollCue? = nil, marks: [CoachMark]? = nil,
                        selectedMark: UUID? = nil) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
                                 perspectiveID: perspective ?? scenario.defaultPerspectiveID,
                                 marks: marks ?? scenario.coachMarks, selectedAnnotationID: selectedMark,
                                 selectedAnnotationIsEditable: selectedMark != nil,
                                 showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil,
                                 ragdollCue: cue)
    }

    private func skins(_ root: Entity) -> [String: ReplaySkinnedAthleteInstance] {
        PitchSceneFactory.skinnedAthletesForTesting(in: root)
    }

    private func details(_ root: Entity) -> [String: ReplaySkinnedAthleteProvider.Detail] {
        skins(root).mapValues(\.detail)
    }

    private func playerEntity(_ id: String, root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: "player-\(id)"))
    }

    func testNearOnlyPreparationKeepsExistingAdmissionUntilExplicitLowWarm() throws {
        let (scenario, root) = try prepare(low: false)
        update(root, scenario: scenario)
        XCTAssertEqual(details(root), [scenario.defaultPerspectiveID: .near])
        XCTAssertFalse(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        update(root, scenario: scenario)
        XCTAssertEqual(skins(root).count, 4)
        XCTAssertEqual(details(root).values.filter { $0 == .lowDetail }.count, 3)
        XCTAssertEqual(details(root)[scenario.defaultPerspectiveID], .near)
        XCTAssertEqual(ReplaySkinnedAthleteProvider.maximumConcurrentInstances, 4)
        XCTAssertEqual(PitchSceneFactory.firstPersonDetailedRigLimit, 2)
    }

    func testSpareSkinsReuseRootsAndDoNotAllocateProceduralNearRigs() throws {
        let (scenario, root) = try prepare()
        update(root, scenario: scenario)
        let first = skins(root)
        XCTAssertEqual(first.count, 4)
        let attempts = ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount
        XCTAssertEqual(attempts, 3)
        let bindings = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
        XCTAssertEqual(bindings.cachedBindings, scenario.players.count + 1)
        for (id, skin) in first where skin.detail == .lowDetail {
            let body = try playerEntity(id, root: root)
            XCTAssertNil(body.children.first { $0.name == "full-rig" })
            XCTAssertFalse(try XCTUnwrap(body.children.first { $0.name == "table-marker" }).isEnabled)
            XCTAssertTrue(skin.root.isEnabled)
            XCTAssertEqual(skin.model.model?.mesh.contents.models.flatMap { Array($0.parts) }
                .reduce(0, { $0 + $1.positions.count }), ReplaySkinnedAthleteProvider.lowSkinVertices)
        }
        for view in [ReplayViewMode.tacticalTable, .touchline, .tacticalTable] {
            update(root, scenario: scenario, view: view)
            XCTAssertEqual(Set(skins(root).keys), Set(first.keys))
            for (id, skin) in first { XCTAssertTrue(skins(root)[id] === skin) }
        }
        XCTAssertEqual(ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount, attempts)
        XCTAssertEqual(PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root), bindings)
    }

    func testSelectingLowPlayerPromotesItBeforeRosterIterationAndReturnsExactly() throws {
        let (scenario, root) = try prepare()
        update(root, scenario: scenario)
        let first = skins(root)
        let original = try XCTUnwrap(first[scenario.defaultPerspectiveID])
        let firstPose = original.model.jointTransforms
        let firstNumber = original.back.transform
        let low = try XCTUnwrap(first.values.filter { $0.detail == .lowDetail }.sorted { $0.playerID < $1.playerID }.first)
        update(root, scenario: scenario, perspective: low.playerID)
        XCTAssertNil(low.root.parent)
        XCTAssertNil(original.root.parent)
        XCTAssertEqual(details(root)[low.playerID], .near)
        XCTAssertEqual(skins(root).count, 4)
        update(root, scenario: scenario)
        let returned = try XCTUnwrap(skins(root)[scenario.defaultPerspectiveID])
        XCTAssertEqual(returned.detail, .near)
        XCTAssertEqual(returned.model.jointTransforms, firstPose)
        XCTAssertEqual(returned.back.transform, firstNumber)
        for player in [try XCTUnwrap(scenario.players.last), try XCTUnwrap(scenario.players.first)] {
            update(root, scenario: scenario, perspective: player.id)
            XCTAssertEqual(details(root)[player.id], .near)
            XCTAssertEqual(skins(root).count, 4)
        }
    }

    func testImpactPromotionKeepsCapAndUpdatesTheHiddenQueryBody() throws {
        let (scenario, root) = try prepare()
        update(root, scenario: scenario)
        let previous = try XCTUnwrap(skins(root).values.first { $0.detail == .lowDetail })
        let cue = PlayerRagdollCue(playerID: previous.playerID, impactTime: 11.5, duration: 3)
        update(root, scenario: scenario, cue: cue)
        XCTAssertNil(previous.root.parent)
        XCTAssertEqual(details(root)[previous.playerID], .near)
        XCTAssertEqual(details(root).values.filter { $0 == .near }.count, 2)
        XCTAssertEqual(details(root).values.filter { $0 == .lowDetail }.count, 2)
        XCTAssertEqual(skins(root).count, 4)
        let body = try playerEntity(previous.playerID, root: root)
        let rig = try XCTUnwrap(body.findEntity(named: "full-rig"))
        let queryBody = try XCTUnwrap(rig.findEntity(named: "body-root"))
        let firstTransform = queryBody.transform
        XCTAssertNotNil(rig.findEntity(named: "ragdoll-physics-active"))
        XCTAssertFalse(try XCTUnwrap(rig.findEntity(named: "left-thigh")).isEnabled)
        update(root, scenario: scenario, time: 13, cue: cue)
        XCTAssertNotEqual(queryBody.transform, firstTransform)
        update(root, scenario: scenario, cue: cue)
        XCTAssertEqual(queryBody.transform, firstTransform)
        update(root, scenario: scenario, time: cue.endTime + 0.1, cue: cue)
        XCTAssertEqual(skins(root).count, 4)
        XCTAssertEqual(details(root).values.filter { $0 == .near }.count, 1)
    }

    func testPOVAndShapeNeverKeepExtraLowsAndWearerStaysHidden() throws {
        let (scenario, root) = try prepare()
        update(root, scenario: scenario)
        let lows = skins(root).values.filter { $0.detail == .lowDetail }
        update(root, scenario: scenario, view: .firstPerson)
        for low in lows { XCTAssertNil(low.root.parent) }
        XCTAssertTrue(details(root).values.allSatisfy { $0 == .near })
        XCTAssertEqual(skins(root).count, PitchSceneFactory.firstPersonDetailedRigLimit)
        XCTAssertNil(skins(root)[scenario.defaultPerspectiveID])
        let wearer = try playerEntity(scenario.defaultPerspectiveID, root: root)
        XCTAssertFalse(try XCTUnwrap(wearer.findEntity(named: "interaction-target")).isEnabled)
        update(root, scenario: scenario, view: .touchline)
        XCTAssertEqual(skins(root).count, 4)
        let (shape, shapeRoot) = try prepare(kind: .shapeLab)
        update(shapeRoot, scenario: shape, view: .positional)
        XCTAssertEqual(skins(shapeRoot).count, 4)
        XCTAssertTrue(details(shapeRoot).values.allSatisfy { $0 == .near })
    }

    func testLowCloneFailureShowsFarImmediatelyWithoutRetryOrBlockingNearPromotion() throws {
        let (scenario, root) = try prepare()
        ReplaySkinnedAthleteProvider.setLowDetailMakeFailureForTesting(true)
        update(root, scenario: scenario)
        XCTAssertEqual(details(root), [scenario.defaultPerspectiveID: .near])
        XCTAssertEqual(ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount, 3)
        let presentation = ReplayPlayerPresentation(scenario: scenario, viewMode: .tacticalTable)
        let expected = ReplayLowDetailAdmissionPolicy.resolve(
            previous: .init(), scenarioID: scenario.id, scenarioKind: scenario.kind,
            viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
            posesByPlayerID: presentation.poses(in: scenario, at: 12),
            nearPlayerIDs: [scenario.defaultPerspectiveID], maximumTotal: 4, lowDetailIsReady: true)
        for id in expected.playerIDs {
            let body = try playerEntity(id, root: root)
            XCTAssertTrue(try XCTUnwrap(body.findEntity(named: "table-marker")).isEnabled)
            XCTAssertNil(body.findEntity(named: ReplaySkinnedAthleteProvider.visualRootName))
        }
        update(root, scenario: scenario)
        XCTAssertEqual(ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount, 3)
        let rejectedLow = try XCTUnwrap(expected.playerIDs.first)
        update(root, scenario: scenario, perspective: rejectedLow)
        XCTAssertEqual(details(root)[rejectedLow], .near, "A failed low variant must not poison a near request")
        ReplaySkinnedAthleteProvider.setLowDetailMakeFailureForTesting(false)
        update(root, scenario: scenario, view: .firstPerson)
        let attemptsBeforeReturn = ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount
        update(root, scenario: scenario)
        XCTAssertEqual(skins(root).count, 4)
        XCTAssertEqual(ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount, attemptsBeforeReturn + 3)
    }

    func testLowPoseAndJerseyNumbersReturnExactlyAfterSeekAndPOVEviction() throws {
        let (scenario, root) = try prepare()
        update(root, scenario: scenario)
        let initial = skins(root).filter { $0.value.detail == .lowDetail }
        let joints = initial.mapValues { $0.model.jointTransforms }
        let fronts = initial.mapValues { $0.front.transform }
        let backs = initial.mapValues { $0.back.transform }
        let positions = try initial.mapValues { try playerEntity($0.playerID, root: root).transform }
        for time in [18.0, 3.0, 14.0] { update(root, scenario: scenario, time: time) }
        update(root, scenario: scenario, view: .firstPerson)
        update(root, scenario: scenario)
        let returned = skins(root).filter { $0.value.detail == .lowDetail }
        XCTAssertEqual(Set(returned.keys), Set(initial.keys))
        for (id, skin) in returned {
            XCTAssertEqual(skin.model.jointTransforms, joints[id])
            XCTAssertEqual(skin.front.transform, fronts[id])
            XCTAssertEqual(skin.back.transform, backs[id])
            XCTAssertEqual(try playerEntity(id, root: root).transform, positions[id])
        }
    }

    func testLosingOptionalLowPreparationReleasesOnlyLowsAndRestoresFar() throws {
        let (scenario, root) = try prepare()
        update(root, scenario: scenario)
        let previous = skins(root)
        let near = try XCTUnwrap(previous[scenario.defaultPerspectiveID])
        ReplaySkinnedAthleteProvider.resetLowDetailForTesting()
        update(root, scenario: scenario)
        XCTAssertEqual(details(root), [scenario.defaultPerspectiveID: .near])
        XCTAssertTrue(skins(root)[scenario.defaultPerspectiveID] === near)
        for (id, skin) in previous where skin.detail == .lowDetail {
            XCTAssertNil(skin.root.parent)
            XCTAssertTrue(try XCTUnwrap(playerEntity(id, root: root).findEntity(named: "table-marker")).isEnabled)
        }
    }

    func testLowAdmissionLeavesTrackPickingAndAnnotationOriginsUnchanged() throws {
        let (scenario, root) = try prepare(low: false)
        let id = scenario.defaultPerspectiveID
        let mark = CoachMark(kind: .run, start: .zero, end: PitchPoint(x: 2, z: 4),
                             label: "Track run", startTrackAnchor: .init(playerID: id))
        update(root, scenario: scenario, marks: [mark])
        let body = try playerEntity(id, root: root)
        let target = try XCTUnwrap(body.findEntity(named: "interaction-target"))
        let before = body.transform
        let targetBefore = target.transform
        let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        let markBefore = markRoot.transform
        let arrow = try XCTUnwrap(markRoot.findEntity(named: "annotation-mark-arrow"))
        let arrowBefore = arrow.transform
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        update(root, scenario: scenario, marks: [mark])
        XCTAssertEqual(skins(root).count, 4)
        XCTAssertEqual(body.transform, before)
        XCTAssertTrue(target === body.findEntity(named: "interaction-target"))
        XCTAssertTrue(target.isEnabled)
        XCTAssertEqual(target.transform, targetBefore)
        XCTAssertNotNil(target.components[CollisionComponent.self])
        XCTAssertNotNil(target.components[InputTargetComponent.self])
        XCTAssertTrue(markRoot === root.findEntity(named: "mark-\(mark.id.uuidString)"))
        XCTAssertEqual(markRoot.transform, markBefore)
        XCTAssertEqual(arrow.transform, arrowBefore)
        update(root, scenario: scenario, marks: [mark], selectedMark: mark.id)
        XCTAssertFalse(target.isEnabled, "Existing annotation handle acquisition still owns picking")
        update(root, scenario: scenario, marks: [mark])
        XCTAssertTrue(target.isEnabled)
    }
}
