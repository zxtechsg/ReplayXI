import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PitchSceneAthleteBindingCacheTests: XCTestCase {
    override func tearDown() {
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        super.tearDown()
    }

    func testPlayerEntityIndexIsBuiltOnceWhilePoseStorageRefreshesInPlace() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        let initial = PitchSceneFactory.playerSceneCacheDiagnostics(for: root)
        XCTAssertEqual(initial.indexedPlayers, scenario.players.count)
        XCTAssertEqual(initial.entityIndexBuilds, 1)
        XCTAssertEqual(initial.poseRefreshes, 0)

        update(
            root: root,
            scenario: scenario,
            time: 12,
            perspectiveID: scenario.defaultPerspectiveID
        )
        update(
            root: root,
            scenario: scenario,
            time: 13,
            perspectiveID: scenario.defaultPerspectiveID
        )

        let repeated = PitchSceneFactory.playerSceneCacheDiagnostics(for: root)
        XCTAssertEqual(repeated.indexedPlayers, scenario.players.count)
        XCTAssertEqual(
            repeated.entityIndexBuilds,
            1,
            "steady playback must not rebuild the RealityKit player lookup"
        )
        XCTAssertEqual(repeated.poseRefreshes, 2)
    }

    func testPausedPoseReuseInvalidatesForTimeImpactAndIdealTargets() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let time = 12.5
        let player = try XCTUnwrap(scenario.players.first { candidate in
            scenario.formationTargets.contains { $0.playerID == candidate.id }
        })
        func render(_ view: ReplayViewMode = .tacticalTable, ideal: Bool = false,
                    cue: PlayerRagdollCue? = nil, at time: Double = 12.5) {
            PitchSceneFactory.update(root: root, scenario: scenario, time: time,
                viewMode: view, perspectiveID: player.id, marks: scenario.coachMarks,
                showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil,
                showsIdealBranch: ideal, ragdollCue: cue)
        }
        func samples() -> Int { PitchSceneFactory.playerSceneCacheDiagnostics(for: root).poseRefreshes }
        render()
        let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
        let initial = body.transform
        for _ in 0..<60 { render() }
        XCTAssertEqual(samples(), 1, "A held frame must not resample the squad")
        XCTAssertEqual(body.transform, initial)

        let impact = PlayerRagdollCue(playerID: player.id, impactTime: time - 0.5)
        render(cue: impact)
        XCTAssertEqual(samples(), 2)
        XCTAssertEqual(body.position.x, player.presentationPose(at: impact.impactTime).position.x)
        render(cue: impact)
        XCTAssertEqual(samples(), 2)
        render()
        XCTAssertEqual(samples(), 3)
        XCTAssertEqual(body.transform, initial)

        render(.positional, ideal: true)
        XCTAssertEqual(samples(), 4)
        let target = try XCTUnwrap(scenario.formationTargets.first { $0.playerID == player.id })
        XCTAssertEqual(body.position.x, target.position.x)
        XCTAssertEqual(body.position.z, target.position.z)
        render(.positional, ideal: true)
        XCTAssertEqual(samples(), 4)
        render(.positional)
        XCTAssertEqual(samples(), 5)
        render(.positional, at: time + 1)
        XCTAssertEqual(samples(), 6)
        render()
        XCTAssertEqual(samples(), 7)
        XCTAssertEqual(body.transform, initial, "Rewind must restore the exact pose")
    }

    func testSameTimeAndPlayerIDsDoNotReuseReplacedTracks() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.players.first)
        let changed = PlayerTrack(id: player.id, displayName: player.displayName,
            role: player.role, shirtNumber: player.shirtNumber, team: player.team,
            isGoalkeeper: player.isGoalkeeper, keyframes: player.keyframes.map {
                MotionKeyframe(time: $0.time, position: .init(x: $0.position.x + 1, z: $0.position.z),
                    facingDegrees: $0.facingDegrees)
            })
        let replacement = ReplayScenario(id: scenario.id, kind: scenario.kind, title: scenario.title,
            strapline: scenario.strapline, matchContext: scenario.matchContext,
            objective: scenario.objective, coachPrompt: scenario.coachPrompt, proofPoint: scenario.proofPoint,
            duration: scenario.duration, defaultViewMode: scenario.defaultViewMode,
            defaultPerspectiveID: scenario.defaultPerspectiveID, featuredPerspectiveIDs: scenario.featuredPerspectiveIDs,
            players: scenario.players.map { $0.id == player.id ? changed : $0 }, ball: scenario.ball,
            moments: scenario.moments, coachMarks: scenario.coachMarks, formationTargets: scenario.formationTargets)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root: root, scenario: scenario, time: 12, perspectiveID: scenario.defaultPerspectiveID)
        let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
        let original = body.position
        update(root: root, scenario: replacement, time: 12, perspectiveID: scenario.defaultPerspectiveID)
        XCTAssertEqual(PitchSceneFactory.playerSceneCacheDiagnostics(for: root).poseRefreshes, 2)
        XCTAssertEqual(body.position.x, original.x + 1, accuracy: 0.0001)
        update(root: root, scenario: scenario, time: 12, perspectiveID: scenario.defaultPerspectiveID)
        XCTAssertEqual(PitchSceneFactory.playerSceneCacheDiagnostics(for: root).poseRefreshes, 3)
        XCTAssertEqual(body.position, original)
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
