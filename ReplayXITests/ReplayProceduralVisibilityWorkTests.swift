import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayProceduralVisibilityWorkTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
    }

    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
        super.tearDown()
    }

    func testUnchangedProceduralPresentationDoesNotRewriteMeshVisibility() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, time: 1)
        XCTAssertGreaterThan(PitchSceneFactory.proceduralVisibilityModelWrites, 0)
        let rig = try fullRig(in: root, playerID: scenario.defaultPerspectiveID)
        let originalModels = models(in: rig)
        XCTAssertFalse(originalModels.isEmpty)
        for time in [2.0, 4, 3, 1] {
            PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
            update(root, scenario: scenario, time: time)
            assertNoRepeatedVisibilityWork("procedural at \(time)")
            XCTAssertEqual(models(in: rig).map(ObjectIdentifier.init),
                           originalModels.map(ObjectIdentifier.init))
            XCTAssertTrue(originalModels.allSatisfy(\.isEnabled))
        }
    }

    func testStableSkinAndImpactDoNotRewriteHiddenFallbackMeshes() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let cue = PlayerRagdollCue(playerID: scenario.defaultPerspectiveID, impactTime: 13.55, duration: 2.8)
        update(root, scenario: scenario, time: 1, cue: cue)
        let rig = try fullRig(in: root, playerID: scenario.defaultPerspectiveID)
        let fallback = models(in: rig)
        XCTAssertFalse(fallback.isEmpty)
        let skin = try XCTUnwrap(root.findEntity(named: "player-\(scenario.defaultPerspectiveID)")?
            .findEntity(named: ReplaySkinnedAthleteProvider.visualRootName))
        for time in [2.0, 13.8, 14.1, 15.2, 1] {
            PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
            update(root, scenario: scenario, time: time, cue: cue)
            assertNoRepeatedVisibilityWork("skin at \(time)")
            XCTAssertTrue(skin.isEnabled)
            XCTAssertEqual(models(in: rig).map(ObjectIdentifier.init),
                           fallback.map(ObjectIdentifier.init),
                           "Impact may add a query marker, but no rendering descendants")
            XCTAssertTrue(fallback.allSatisfy { !$0.isEnabled })
            XCTAssertTrue(rig.isEnabled, "Query joints stay alive under the skin")
        }
    }

    func testShapeComparisonRetainsVisibilityWithoutRepeatedHierarchyWalks() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, time: 14, view: .positional)
        XCTAssertGreaterThan(PitchSceneFactory.proceduralVisibilityModelWrites, 0)
        for (time, ideal) in [(16.0, true), (14, false), (16, true)] {
            PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
            update(root, scenario: scenario, time: time, view: .positional, ideal: ideal)
            assertNoRepeatedVisibilityWork("Shape at \(time), ideal \(ideal)")
            assertActualMeshVisibility(in: root, scenario: scenario)
        }
    }

    func testChangingSubjectRestoresFallbackAndCanHideItAgain() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, time: 1)
        let firstRig = try fullRig(in: root, playerID: scenario.defaultPerspectiveID)
        XCTAssertTrue(models(in: firstRig).allSatisfy { !$0.isEnabled })

        // Existing instances own their prepared data, but an unprepared next
        // subject must use the procedural fallback. No production gate changes.
        ReplaySkinnedAthleteProvider.resetForTesting()
        PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
        update(root, scenario: scenario, time: 1, perspective: "navy-rb")
        XCTAssertGreaterThan(PitchSceneFactory.proceduralVisibilityModelWrites, 0)
        XCTAssertTrue(models(in: firstRig).allSatisfy(\.isEnabled))
        assertActualMeshVisibility(in: root, scenario: scenario)

        try ReplaySkinnedAthleteProvider.prewarm()
        PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
        update(root, scenario: scenario, time: 1)
        XCTAssertGreaterThan(PitchSceneFactory.proceduralVisibilityModelWrites, 0)
        XCTAssertTrue(models(in: firstRig).allSatisfy { !$0.isEnabled })
        assertActualMeshVisibility(in: root, scenario: scenario)
        PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
        update(root, scenario: scenario, time: 2)
        assertNoRepeatedVisibilityWork("restored subject")
    }

    func testFreshRootsAndPOVNeighboursDoNotInheritAnotherRigsVisibility() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        for perspective in [scenario.defaultPerspectiveID, "navy-rb", "red-lb"] {
            let root = PitchSceneFactory.makeMatchRoot(for: scenario)
            PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
            update(root, scenario: scenario, time: 1, view: .firstPerson, perspective: perspective)
            XCTAssertGreaterThan(PitchSceneFactory.proceduralVisibilityModelWrites, 0)
            assertActualMeshVisibility(in: root, scenario: scenario)
            PitchSceneFactory.resetProceduralVisibilityWorkForTesting()
            update(root, scenario: scenario, time: 1, view: .firstPerson, perspective: perspective)
            assertNoRepeatedVisibilityWork("POV \(perspective)")
            assertActualMeshVisibility(in: root, scenario: scenario)
        }
    }

    private func assertNoRepeatedVisibilityWork(_ context: String,
                                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(PitchSceneFactory.proceduralVisibilityNodeVisits, 0, context, file: file, line: line)
        XCTAssertEqual(PitchSceneFactory.proceduralVisibilityModelWrites, 0, context, file: file, line: line)
    }

    private func assertActualMeshVisibility(in root: Entity, scenario: ReplayScenario,
                                           file: StaticString = #filePath, line: UInt = #line) {
        for player in scenario.players {
            guard let entity = root.findEntity(named: "player-\(player.id)"),
                  let rig = entity.children.first(where: { $0.name == "full-rig" }) else { continue }
            let usesSkin = entity.children.contains {
                $0.name == ReplaySkinnedAthleteProvider.visualRootName && $0.isEnabled
            }
            for model in models(in: rig) {
                XCTAssertEqual(model.isEnabled, !usesSkin, "\(player.id): \(model.name)", file: file, line: line)
            }
        }
    }

    private func fullRig(in root: Entity, playerID: String) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: "player-\(playerID)")?
            .children.first(where: { $0.name == "full-rig" }))
    }

    private func models(in root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? [])
            + root.children.flatMap { models(in: $0) }
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: TimeInterval,
                        view: ReplayViewMode = .tacticalTable, ideal: Bool = false,
                        perspective: String? = nil, cue: PlayerRagdollCue? = nil) {
        PitchSceneFactory.update(
            root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: perspective ?? scenario.defaultPerspectiveID,
            marks: scenario.coachMarks, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil, showsIdealBranch: ideal, ragdollCue: cue
        )
    }
}
