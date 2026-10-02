import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackSpatialWorkspaceTests: XCTestCase {
    func testRecenterMovesExistingPanelsWithoutRebuildingTheirContent() {
        let original = PlaybackAttachmentPlacement.makeAnchor(revision: 0)
        let panel = Entity()
        panel.name = "coach-console"
        panel.position = [0.1, -0.5, -1.2]
        panel.scale = [1.1, 1.1, 1.1]
        original.addChild(panel)
        let transform = panel.transform

        let replacement = PlaybackAttachmentPlacement.recenteredAnchor(from: original, revision: 1)

        XCTAssertTrue(panel.parent === replacement)
        XCTAssertEqual(panel.transform, transform)
        XCTAssertTrue(original.children.isEmpty)
        XCTAssertEqual(replacement.anchoring.trackingMode, .once)
        XCTAssertFalse(PlaybackAttachmentPlacement.needsRecenter(replacement, revision: 1))
        XCTAssertTrue(PlaybackAttachmentPlacement.needsRecenter(replacement, revision: 2))
    }

    func testReplayChangesDoNotMoveOrRecenterWorkspace() {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let workspace = PlaybackAttachmentPlacement.makeAnchor(revision: 0)
        workspace.position = [2, 1.7, -3]
        let transform = workspace.transform
        for player in store.selectedScenario.players {
            store.openLocalPlayerPOV(player.id)
            store.seek(to: 14)
            store.setViewMode(.tacticalTable)
            XCTAssertEqual(workspace.transform, transform)
            XCTAssertFalse(PlaybackAttachmentPlacement.needsRecenter(workspace, revision: 0))
        }
    }

    func testRecenterCannotMoveControlsDuringAnyOwnedGesture() {
        for drawing in [false, true] {
            for scrubbing in [false, true] {
                for editing in [false, true] {
                    XCTAssertEqual(
                        PlaybackAttachmentPlacement.canRecenter(
                            isDrawing: drawing, isScrubbing: scrubbing, isEditingGeometry: editing
                        ),
                        !(drawing || scrubbing || editing)
                    )
                }
            }
        }
    }

    func testBothProductModesKeepHonestNamesAndStableSaveIdentifiers() {
        XCTAssertEqual(ReplayAppMode.situationRoleplay.title, "Strategy analysis")
        XCTAssertEqual(ReplayAppMode.situationRoleplay.rawValue, "situationRoleplay")
        XCTAssertEqual(ReplayAppMode.matchReplay.title, "Match replay")
        XCTAssertEqual(ReplayAppMode.matchReplay.subtitle, "Match studies with 3D annotations")
        XCTAssertTrue(CityLiverpoolReferenceScenarios.all.allSatisfy {
            $0.proofPoint.contains("Not recovered tracking")
        })
    }
}
