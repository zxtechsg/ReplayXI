import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PitchSceneAthleteBindingCacheTests: XCTestCase {
    override func tearDown() {
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        super.tearDown()
    }

    func testRepeatedSquadUpdatesReuseFactoryBindingsAndDetachInvalidatesNearRig() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        let initial = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
        XCTAssertEqual(initial.cachedBindings, scenario.players.count)
        XCTAssertEqual(initial.hierarchyResolutions, 0)
        XCTAssertEqual(initial.invalidations, 0)

        update(
            root: root,
            scenario: scenario,
            time: 12,
            perspectiveID: scenario.defaultPerspectiveID
        )
        let firstUpdate = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
        XCTAssertEqual(firstUpdate.cachedBindings, scenario.players.count + 1)
        XCTAssertEqual(firstUpdate.hierarchyResolutions, 0)
        let animatedJoint = try XCTUnwrap(
            root.findEntity(named: "player-red-lb")?
                .findEntity(named: "table-marker")?
                .findEntity(named: "left-shoulder")
        )
        let firstOrientation = animatedJoint.orientation.vector

        update(
            root: root,
            scenario: scenario,
            time: 13,
            perspectiveID: scenario.defaultPerspectiveID
        )
        let repeatedUpdate = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
        XCTAssertNotEqual(animatedJoint.orientation.vector, firstOrientation)
        XCTAssertEqual(repeatedUpdate.hierarchyResolutions, 0)

        let temporaryPerspective = try XCTUnwrap(
            scenario.players.first { $0.id != scenario.defaultPerspectiveID }
        )
        update(
            root: root,
            scenario: scenario,
            time: 13,
            perspectiveID: temporaryPerspective.id
        )
        let temporaryRig = try XCTUnwrap(
            root.findEntity(named: "player-\(temporaryPerspective.id)")?
                .children.first { $0.name == "full-rig" }
        )
        XCTAssertTrue(
            PitchSceneFactory.hasCachedProceduralAthleteBinding(
                for: temporaryRig,
                in: root
            )
        )

        update(
            root: root,
            scenario: scenario,
            time: 13,
            perspectiveID: scenario.defaultPerspectiveID
        )
        let afterDetach = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
        XCTAssertNil(temporaryRig.parent)
        XCTAssertFalse(
            PitchSceneFactory.hasCachedProceduralAthleteBinding(
                for: temporaryRig,
                in: root
            )
        )
        XCTAssertEqual(afterDetach.invalidations, repeatedUpdate.invalidations + 1)
        XCTAssertEqual(afterDetach.hierarchyResolutions, 0)
    }

    func testImportedAthleteSkipsHiddenProceduralMotionAndRagdollFallbackIsImmediateAndDeterministic() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: scenario.defaultPerspectiveID))
        let supportedTime: TimeInterval = 11.8
        let secondSupportedTime: TimeInterval = 12.0
        XCTAssertTrue(player.locomotion(at: supportedTime).state.supportsImportedRunClip)
        XCTAssertTrue(player.locomotion(at: secondSupportedTime).state.supportsImportedRunClip)
        _ = try ReplayImportedAthleteProvider.prewarm(in: .main, featureEnabled: true)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        update(
            root: root,
            scenario: scenario,
            time: supportedTime,
            perspectiveID: player.id
        )
        let playerEntity = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
        let fullRig = try XCTUnwrap(
            playerEntity.children.first { $0.name == "full-rig" }
        )
        let body = try XCTUnwrap(fullRig.findEntity(named: "body-root"))
        let torso = try XCTUnwrap(fullRig.findEntity(named: "torso") as? ModelEntity)
        let bindPosition = body.position
        let bindOrientation = body.orientation.vector

        let importedVisual = try XCTUnwrap(
            playerEntity.children.first {
                $0.name == ReplayImportedAthleteProvider.visualRootName
            }
        )
        XCTAssertTrue(importedVisual.isEnabled)
        XCTAssertFalse(torso.isEnabled)

        update(
            root: root,
            scenario: scenario,
            time: secondSupportedTime,
            perspectiveID: player.id
        )
        XCTAssertEqual(body.position, bindPosition)
        XCTAssertEqual(body.orientation.vector, bindOrientation)
        XCTAssertTrue(importedVisual.isEnabled)
        XCTAssertFalse(torso.isEnabled)

        let cue = PlayerRagdollCue(
            playerID: player.id,
            impactTime: 11,
            duration: 3,
            impactDirection: SIMD2<Float>(0.45, 0.89),
            impulse: 1.1
        )
        update(
            root: root,
            scenario: scenario,
            time: secondSupportedTime,
            perspectiveID: player.id,
            ragdollCue: cue
        )

        XCTAssertNil(
            playerEntity.children.first {
                $0.name == ReplayImportedAthleteProvider.visualRootName
            }
        )
        XCTAssertTrue(torso.isEnabled)
        XCTAssertNotEqual(body.position, bindPosition)
        let fallbackPosition = body.position
        let fallbackOrientation = body.orientation.vector
        let beforeRepeat = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)

        update(
            root: root,
            scenario: scenario,
            time: secondSupportedTime,
            perspectiveID: player.id,
            ragdollCue: cue
        )
        let repeatedFallback = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
        XCTAssertEqual(body.position, fallbackPosition)
        XCTAssertEqual(body.orientation.vector, fallbackOrientation)
        XCTAssertEqual(
            repeatedFallback.cachedBindings,
            beforeRepeat.cachedBindings
        )
        XCTAssertEqual(repeatedFallback.hierarchyResolutions, 0)
    }

    private func update(
        root: Entity,
        scenario: ReplayScenario,
        time: TimeInterval,
        perspectiveID: String,
        ragdollCue: PlayerRagdollCue? = nil
    ) {
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: time,
            viewMode: .tacticalTable,
            perspectiveID: perspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil,
            ragdollCue: ragdollCue
        )
    }
}
