import CryptoKit
import RealityKit
import XCTest
@testable import ReplayXI

private final class RocketboxQualificationBundleToken {}

@MainActor
final class ReplayImportedAthleteProviderTests: XCTestCase {
    override func tearDown() {
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        super.tearDown()
    }

    func testFeatureGateHasExplicitOverridePrecedenceAndSafeReleaseDefault() {
        XCTAssertTrue(
            ReplayImportedAthleteFeatureGate.resolvedValue(
                environmentValue: "ON",
                userDefaultsValue: false,
                debugDefault: false
            )
        )
        XCTAssertFalse(
            ReplayImportedAthleteFeatureGate.resolvedValue(
                environmentValue: "0",
                userDefaultsValue: true,
                debugDefault: true
            )
        )
        XCTAssertTrue(
            ReplayImportedAthleteFeatureGate.resolvedValue(
                environmentValue: "not-a-switch",
                userDefaultsValue: true,
                debugDefault: false
            )
        )
        XCTAssertFalse(
            ReplayImportedAthleteFeatureGate.resolvedValue(
                environmentValue: nil,
                userDefaultsValue: nil,
                debugDefault: false
            )
        )
    }

    /// A local, opt-in admission probe for the pinned Microsoft Rocketbox
    /// build. The fixture is never checked in or copied to the application
    /// bundle: qualification temporarily places the exact candidate in the
    /// XCTest bundle as `ReplayXIRocketboxQualification.usdz`, runs only this
    /// test in the visionOS simulator, and then deletes the staging copy.
    func testTransientRocketboxCandidateLoadsAndExposesFiniteSeekableAnimationResources() throws {
        let fixtureBundle = Bundle(for: RocketboxQualificationBundleToken.self)
        guard let url = fixtureBundle.url(
            forResource: "ReplayXIRocketboxQualification",
            withExtension: "usdz",
            subdirectory: "Fixtures/Qualification"
        ) ?? fixtureBundle.url(
            forResource: "ReplayXIRocketboxQualification",
            withExtension: "usdz"
        ) else {
            throw XCTSkip("Transient Rocketbox qualification fixture is not staged")
        }

        let payload = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
        let expectedDigest = "e338d6a3a4547920a658fea6f9240cefbb0c10c58d4049854ffd0d27b7edd76f"
        guard digest == expectedDigest else {
            XCTFail("Transient Rocketbox fixture failed its SHA-256 identity gate")
            return
        }
        guard payload.count == 3_439_236 else {
            XCTFail("Transient Rocketbox fixture failed its byte-count identity gate")
            return
        }

        let athlete = try Entity.load(contentsOf: url)
        let bounds = athlete.visualBounds(relativeTo: nil)
        XCTAssertTrue(bounds.min.allFinite)
        XCTAssertTrue(bounds.max.allFinite)
        XCTAssertGreaterThan(bounds.extents.y, 1.7)
        XCTAssertLessThan(bounds.extents.y, 2.1)
        // RealityKit coalesces the two USD Mesh prims into one ModelEntity and
        // exposes two finite resources for the one audited UsdSkel clip.
        XCTAssertEqual(recursiveModelCount(in: athlete), 1)
        XCTAssertEqual(athlete.availableAnimations.count, 2)

        let controllers = athlete.availableAnimations.map {
            athlete.playAnimation($0, transitionDuration: 0, startsPaused: true)
        }
        XCTAssertEqual(controllers.count, 2)
        for controller in controllers {
            XCTAssertTrue(controller.isValid)
            XCTAssertTrue(controller.isPaused)
            XCTAssertEqual(controller.duration, 0.6, accuracy: 0.01)
        }

        let sampleTimes = [0.001, 0.15, 0.30, 0.45, 0.599]
        var observedTimes: [[TimeInterval]] = []
        for controller in controllers {
            var controllerTimes: [TimeInterval] = []
            for sampleTime in sampleTimes {
                controller.time = sampleTime
                controller.pause()
                controllerTimes.append(controller.time)
                XCTAssertTrue(controller.isValid)
                XCTAssertTrue(controller.isPaused)
            }
            for (expected, observed) in zip(sampleTimes, controllerTimes) {
                XCTAssertEqual(observed, expected, accuracy: 0.002)
            }
            observedTimes.append(controllerTimes)
        }

        print(
            "Rocketbox RealityKit qualification: bytes=\(payload.count) "
                + "sha256=\(digest) models=\(recursiveModelCount(in: athlete)) "
                + "animations=\(athlete.availableAnimations.count) "
                + "durations=\(controllers.map(\.duration)) bounds=\(bounds.extents) "
                + "seekTimes=\(observedTimes)"
        )
    }

    func testBundledPilotIsHashLockedAnimatedAndWithinNearFieldContract() throws {
        let url = try XCTUnwrap(ReplayImportedAthleteProvider.resourceURL(in: .main))
        let facts = try ReplayImportedAthleteProvider.prewarm(
            contentsOf: url,
            featureEnabled: true
        )

        XCTAssertEqual(facts.sha256, ReplayImportedAthleteProvider.expectedSHA256)
        XCTAssertEqual(facts.bytes, ReplayImportedAthleteProvider.expectedBytes)
        // The source-level USD audit has eight Mesh prims and three animation
        // sources. RealityKit coalesces those into three ModelEntity subclasses
        // and exposes two playable resources on the loaded root.
        XCTAssertEqual(facts.modelEntities, 3)
        XCTAssertEqual(facts.animationTracks, 2)
        XCTAssertGreaterThan(facts.sourceHeight, 1.5)
        XCTAssertLessThan(facts.sourceHeight, 2.2)
        XCTAssertEqual(facts.decodedTextureBytes, 21_495_808)
        XCTAssertEqual(ReplayImportedAthleteProvider.maximumConcurrentNearFieldInstances, 1)
    }

    func testNearFieldCloneHasTeamKitNumbersAndSeekableAnimationTracks() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        _ = try ReplayImportedAthleteProvider.prewarm(in: .main, featureEnabled: true)

        let instance = try ReplayImportedAthleteProvider.makeNearFieldVisual(
            for: player,
            at: 4.25
        )
        XCTAssertEqual(instance.root.name, ReplayImportedAthleteProvider.visualRootName)
        XCTAssertEqual(instance.playerID, player.id)
        for (index, shellName) in ReplayImportedAthleteProvider.requiredKitShellNames.enumerated() {
            let marker = try XCTUnwrap(instance.root.findEntity(named: shellName))
            XCTAssertNil(marker.components[ModelComponent.self])
            let component = try XCTUnwrap(ReplayImportedAthleteProvider.modelComponent(
                inKitShellNamed: shellName,
                of: instance.root
            ))
            let materialSlot = try XCTUnwrap(
                ReplayImportedAthleteProvider.materialSlot(inKitShellNamed: shellName)
            )
            XCTAssertEqual(materialSlot, index + 1)
            XCTAssertEqual(component.materials.count, 6)
            XCTAssertTrue(
                component.materials[materialSlot] is SimpleMaterial,
                "Kit override did not reach \(shellName)'s coalesced material slot"
            )
        }
        let bodyComponent = try XCTUnwrap(ReplayImportedAthleteProvider.modelComponent(
            inKitShellNamed: "ReplayXI_Jersey",
            of: instance.root
        ))
        XCTAssertTrue(bodyComponent.materials[0] is PhysicallyBasedMaterial)
        XCTAssertNotNil(instance.root.findEntity(named: "imported-shirt-number"))
        XCTAssertNotNil(instance.root.findEntity(named: "imported-chest-number"))
        XCTAssertEqual(instance.animationControllers.count, 2)
        XCTAssertTrue(instance.animationControllers.allSatisfy(\.isValid))
        XCTAssertTrue(instance.animationControllers.allSatisfy(\.isPaused))

        let bounds = instance.root.visualBounds(relativeTo: instance.root)
        XCTAssertGreaterThan(bounds.extents.y, 1.65)
        XCTAssertLessThan(bounds.extents.y, 2.05)

        instance.seek(toNormalizedClipPhase: 0.375)
        let firstTimes = instance.animationControllers.map(\.time)
        instance.seek(toNormalizedClipPhase: 1.375)
        XCTAssertEqual(instance.normalizedClipPhase, 0.375, accuracy: 0.000_001)
        for (first, wrapped) in zip(firstTimes, instance.animationControllers.map(\.time)) {
            XCTAssertEqual(first, wrapped, accuracy: 0.000_001)
        }
    }

    func testClonesShareImportedMeshesButOwnAnimationControllers() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let home = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let away = try XCTUnwrap(scenario.player(id: "red-lb"))
        _ = try ReplayImportedAthleteProvider.prewarm(in: .main, featureEnabled: true)

        let first = try ReplayImportedAthleteProvider.makeNearFieldVisual(for: home)
        let second = try ReplayImportedAthleteProvider.makeNearFieldVisual(for: away)
        let firstJersey = try XCTUnwrap(
            ReplayImportedAthleteProvider.modelComponent(
                inKitShellNamed: "ReplayXI_Jersey",
                of: first.root
            )
        )
        let secondJersey = try XCTUnwrap(
            ReplayImportedAthleteProvider.modelComponent(
                inKitShellNamed: "ReplayXI_Jersey",
                of: second.root
            )
        )

        XCTAssertTrue(firstJersey.mesh === secondJersey.mesh)
        XCTAssertFalse(first.animationControllers[0] === second.animationControllers[0])
    }

    func testDisabledOrInvalidSlotFailsBeforeCreatingRuntimeVisual() throws {
        let url = try XCTUnwrap(ReplayImportedAthleteProvider.resourceURL(in: .main))
        XCTAssertThrowsError(
            try ReplayImportedAthleteProvider.prewarm(contentsOf: url, featureEnabled: false)
        ) { error in
            XCTAssertEqual(error as? ReplayImportedAthleteError, .featureDisabled)
        }

        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        _ = try ReplayImportedAthleteProvider.prewarm(
            contentsOf: url,
            featureEnabled: true
        )
        XCTAssertThrowsError(
            try ReplayImportedAthleteProvider.makeNearFieldVisual(for: player, slot: 1)
        ) { error in
            XCTAssertEqual(error as? ReplayImportedAthleteError, .invalidSlot(1))
        }
    }

    func testPitchSceneMovesTheSingleImportedPilotWithFocusedPlayer() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let first = try XCTUnwrap(scenario.player(id: scenario.defaultPerspectiveID))
        let second = try XCTUnwrap(
            scenario.players.first(where: { $0.id != first.id })
        )
        _ = try ReplayImportedAthleteProvider.prewarm(in: .main, featureEnabled: true)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        func update(focus playerID: String) {
            PitchSceneFactory.update(
                root: root,
                scenario: scenario,
                time: 2,
                viewMode: .tacticalTable,
                perspectiveID: playerID,
                marks: scenario.coachMarks,
                showsLaneLens: false,
                isDrawing: false,
                positionalOriginTransform: nil
            )
        }

        update(focus: first.id)
        let firstEntity = try XCTUnwrap(root.findEntity(named: "player-\(first.id)"))
        XCTAssertNotNil(firstEntity.findEntity(named: ReplayImportedAthleteProvider.visualRootName))
        XCTAssertEqual(importedVisualCount(in: root), 1)

        update(focus: second.id)
        let secondEntity = try XCTUnwrap(root.findEntity(named: "player-\(second.id)"))
        XCTAssertNil(firstEntity.findEntity(named: ReplayImportedAthleteProvider.visualRootName))
        XCTAssertNotNil(secondEntity.findEntity(named: ReplayImportedAthleteProvider.visualRootName))
        XCTAssertEqual(importedVisualCount(in: root), 1)
    }

    func testImportedRunPilotYieldsToProceduralPoseForIdleAndCutStates() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: scenario.defaultPerspectiveID))
        let supportedTime: TimeInterval = 11.8
        XCTAssertTrue(player.locomotion(at: supportedTime).state.supportsImportedRunClip)
        XCTAssertEqual(player.locomotion(at: scenario.duration).state, .idle)
        _ = try ReplayImportedAthleteProvider.prewarm(in: .main, featureEnabled: true)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        func update(at time: TimeInterval) {
            PitchSceneFactory.update(
                root: root,
                scenario: scenario,
                time: time,
                viewMode: .tacticalTable,
                perspectiveID: player.id,
                marks: scenario.coachMarks,
                showsLaneLens: false,
                isDrawing: false,
                positionalOriginTransform: nil
            )
        }

        update(at: supportedTime)
        let playerEntity = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
        let imported = try XCTUnwrap(
            playerEntity.findEntity(named: ReplayImportedAthleteProvider.visualRootName)
        )
        let proceduralTorso = try XCTUnwrap(
            playerEntity.findEntity(named: "full-rig")?.findEntity(named: "torso")
        )
        XCTAssertTrue(imported.isEnabled)
        XCTAssertFalse(proceduralTorso.isEnabled)

        update(at: scenario.duration)
        XCTAssertTrue(
            playerEntity.findEntity(named: ReplayImportedAthleteProvider.visualRootName) === imported,
            "Changing motion state must not clone the imported visual"
        )
        XCTAssertFalse(imported.isEnabled)
        XCTAssertTrue(proceduralTorso.isEnabled)

        update(at: supportedTime)
        XCTAssertTrue(imported.isEnabled)
        XCTAssertFalse(proceduralTorso.isEnabled)
    }

    private func importedVisualCount(in entity: Entity) -> Int {
        (entity.name == ReplayImportedAthleteProvider.visualRootName ? 1 : 0)
            + entity.children.reduce(0) { $0 + importedVisualCount(in: $1) }
    }

    private func recursiveModelCount(in entity: Entity) -> Int {
        (entity is ModelEntity ? 1 : 0)
            + entity.children.reduce(0) { $0 + recursiveModelCount(in: $1) }
    }

}

private extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
