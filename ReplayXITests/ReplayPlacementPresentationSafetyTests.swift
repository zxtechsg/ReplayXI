import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayPlacementPresentationSafetyTests: XCTestCase {
    private func placedStore() -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "triangle-lock", broadcast: false)
        store.setShapeFocusStage(.ideal, broadcast: false)
        store.activateLocalTrianglePreview(anchorID: UUID())
        return store
    }

    private func update(
        _ root: Entity,
        from store: ReplayStore,
        placementReady: Bool
    ) {
        PitchSceneFactory.update(
            root: root, scenario: store.selectedScenario, time: store.playhead,
            viewMode: store.viewMode, perspectiveID: store.activePerspectiveID,
            marks: store.marks, showsLaneLens: store.showsLaneLens,
            isDrawing: store.isDrawing,
            positionalOriginTransform: placementReady ? matrix_identity_float4x4 : nil,
            triangleLockMode: store.triangleLockMode,
            isTrianglePlacementReady: placementReady,
            showsIdealBranch: store.showsIdealBranch
        )
    }

    func testTappingFallbackPlayerCannotEscapePhysicalPlacementIntoPOV() throws {
        let store = placedStore()
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        update(root, from: store, placementReady: false)
        let fallback = try XCTUnwrap(root.findEntity(named: "player-navy-rb"))
        XCTAssertTrue(fallback.isEnabled, "Tracking loss exposes the safe ideal overview")
        let previousPerspective = store.localPerspectiveID
        let anchor = store.sharedPitchAnchorID

        // Both a player-body tap and short-drag recovery call this Store route.
        store.openLocalPlayerPOV("navy-rb")

        XCTAssertEqual(store.viewMode, .positional)
        XCTAssertEqual(store.localPerspectiveID, previousPerspective)
        XCTAssertEqual(store.sharedPitchAnchorID, anchor)
        XCTAssertEqual(store.triangleLockMode, .place)
        XCTAssertTrue(store.hasLocallyAcknowledgedTrianglePlacement)
        XCTAssertFalse(store.isPlaying)
    }

    func testEveryCameraModeEntryPointHonoursPhysicalPlacementLock() {
        let store = placedStore()
        for mode in [ReplayViewMode.firstPerson, .tacticalTable, .touchline] {
            store.setViewMode(mode)
            XCTAssertEqual(store.viewMode, .positional)
        }
        store.broadcastPerspective("navy-rb")
        XCTAssertEqual(store.viewMode, .positional)
        XCTAssertFalse(store.coachLockEnabled)
        XCTAssertNil(store.coachFocusPerspectiveID)
        XCTAssertEqual(store.triangleLockMode, .place)
    }

    func testReadyLostReadyAndEndUseTheSameSceneAndInputOrigins() throws {
        let store = placedStore()
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        for ready in [true, false, true, false] {
            update(root, from: store, placementReady: ready)
            for target in store.selectedScenario.formationTargets {
                let track = try XCTUnwrap(store.selectedScenario.player(id: target.playerID))
                let entity = try XCTUnwrap(root.findEntity(named: "player-\(target.playerID)"))
                let inputOrigin = store.presentedPlayerPose(for: track, at: store.playhead).position
                XCTAssertEqual(entity.position.x, inputOrigin.x, accuracy: 0.000_1)
                XCTAssertEqual(entity.position.z, inputOrigin.z, accuracy: 0.000_1)
                XCTAssertEqual(entity.isEnabled, !ready)
            }
        }
        store.endTrianglePlacement()
        update(root, from: store, placementReady: false)
        XCTAssertEqual(store.viewMode, .positional)
        XCTAssertEqual(store.triangleLockMode, .visualise)
        for target in store.selectedScenario.formationTargets {
            let track = try XCTUnwrap(store.selectedScenario.player(id: target.playerID))
            let entity = try XCTUnwrap(root.findEntity(named: "player-\(target.playerID)"))
            let inputOrigin = store.presentedPlayerPose(for: track, at: store.playhead).position
            XCTAssertEqual(inputOrigin, target.position)
            XCTAssertEqual(entity.position.x, inputOrigin.x, accuracy: 0.000_1)
            XCTAssertEqual(entity.position.z, inputOrigin.z, accuracy: 0.000_1)
        }
    }

    func testStationSelectionStaysAvailableWithoutChangingCameraMode() {
        let store = placedStore()
        for target in store.selectedScenario.formationTargets {
            store.setLocalPerspective(target.playerID, entersLocalReview: false)
            XCTAssertEqual(store.localPerspectiveID, target.playerID)
            XCTAssertEqual(store.viewMode, .positional)
            XCTAssertEqual(store.triangleLockMode, .place)
        }
        store.endTrianglePlacement()
        store.openLocalPlayerPOV("navy-rb")
        XCTAssertEqual(store.viewMode, .firstPerson, "POV becomes available after End drill")
    }

    func testActiveImpactViewSwitchesKeepInputAndScenePositionsAligned() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "everyone-with-seven", broadcast: false)
        store.seek(to: 15, broadcast: false)
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        let subject = try XCTUnwrap(store.selectedScenario.player(id: "red-lb"))
        for mode in [ReplayViewMode.tacticalTable, .touchline, .firstPerson, .tacticalTable] {
            store.setViewMode(mode, broadcast: false)
            update(root, from: store, placementReady: false)
            let body = try XCTUnwrap(root.findEntity(named: "player-red-lb"))
            let inputOrigin = store.presentedPlayerPose(for: subject, at: 15).position
            XCTAssertEqual(body.position.x, inputOrigin.x, accuracy: 0.000_1)
            XCTAssertEqual(body.position.z, inputOrigin.z, accuracy: 0.000_1)
            if mode == .firstPerson {
                XCTAssertEqual(inputOrigin, subject.presentationPose(at: 15).position)
            }
        }
    }
}
