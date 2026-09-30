import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackPlayerLabelIndex162Tests: XCTestCase {
    func testUpdateUsesConstructionIndexAndHandlesAppendedChildren() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        XCTAssertEqual(scenario.players.count, 22)
        let root = Entity()
        let labels = PlaybackSpatialLabels.makePlayerLabels(for: scenario)
        root.addChild(labels)
        // Appended children do not shift the construction-time indices.
        labels.addChild(Entity())
        let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
            ($0.id, $0.presentationPose(at: 4))
        })

        for _ in 0..<3 {
            PlaybackSpatialLabels.resetUpdateWorkForTesting()
            PlaybackSpatialLabels.updatePlayerLabels(in: root, scenario: scenario,
                posesByPlayerID: poses, viewMode: .tacticalTable,
                perspectiveID: scenario.defaultPerspectiveID)

            XCTAssertEqual(PlaybackSpatialLabels.updateWork.playerLabelIndexedLookups, 22)
            XCTAssertEqual(PlaybackSpatialLabels.updateWork.playerLabelFallbackInspections, 0)
            XCTAssertEqual(PlaybackSpatialLabels.updateWork.visitedPlayerLabels, 22)
            for player in scenario.players {
                let label = try XCTUnwrap(labels.children.first {
                    $0.name == "player-label-\(player.id)"
                })
                let pose = try XCTUnwrap(poses[player.id])
                XCTAssertEqual(label.position.x, pose.position.x)
                XCTAssertEqual(label.position.z, pose.position.z)
            }
        }
    }

    func testStaleIndicesFallbackAfterChildReordering() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = Entity()
        let labels = PlaybackSpatialLabels.makePlayerLabels(for: scenario)
        root.addChild(labels)
        let first = try XCTUnwrap(labels.children.first)
        first.removeFromParent()
        labels.addChild(first)
        let expectedIndexedLookups = scenario.players.enumerated().filter { index, player in
            labels.children.indices.contains(index)
                && labels.children[index].name == "player-label-\(player.id)"
        }.count
        let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
            ($0.id, $0.presentationPose(at: 4))
        })

        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        PlaybackSpatialLabels.updatePlayerLabels(in: root, scenario: scenario,
            posesByPlayerID: poses, viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID)

        XCTAssertEqual(PlaybackSpatialLabels.updateWork.visitedPlayerLabels, 22)
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.playerLabelIndexedLookups,
                       expectedIndexedLookups)
        XCTAssertGreaterThan(PlaybackSpatialLabels.updateWork.playerLabelFallbackInspections, 0)
        for player in scenario.players {
            let label = try XCTUnwrap(labels.children.first {
                $0.name == "player-label-\(player.id)"
            })
            let pose = try XCTUnwrap(poses[player.id])
            XCTAssertEqual(label.position.x, pose.position.x)
            XCTAssertEqual(label.position.z, pose.position.z)
        }
    }

    func testRemovedLabelIsSkippedAfterStaleIndexFallback() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = Entity()
        let labels = PlaybackSpatialLabels.makePlayerLabels(for: scenario)
        root.addChild(labels)
        let removedPlayer = scenario.players[5]
        let removedLabel = try XCTUnwrap(labels.children.first {
            $0.name == "player-label-\(removedPlayer.id)"
        })
        removedLabel.removeFromParent()
        let remainingPlayers = scenario.players.filter { $0.id != removedPlayer.id }
        let expectedIndexedLookups = scenario.players.enumerated().filter { index, player in
            labels.children.indices.contains(index)
                && labels.children[index].name == "player-label-\(player.id)"
        }.count
        let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
            ($0.id, $0.presentationPose(at: 4))
        })

        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        PlaybackSpatialLabels.updatePlayerLabels(in: root, scenario: scenario,
            posesByPlayerID: poses, viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID)

        XCTAssertEqual(PlaybackSpatialLabels.updateWork.visitedPlayerLabels, 21)
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.playerLabelIndexedLookups,
                       expectedIndexedLookups)
        XCTAssertGreaterThan(PlaybackSpatialLabels.updateWork.playerLabelFallbackInspections, 0)
        XCTAssertNil(labels.children.first { $0.name == "player-label-\(removedPlayer.id)" })
        for player in remainingPlayers {
            let label = try XCTUnwrap(labels.children.first {
                $0.name == "player-label-\(player.id)"
            })
            let pose = try XCTUnwrap(poses[player.id])
            XCTAssertEqual(label.position.x, pose.position.x)
            XCTAssertEqual(label.position.z, pose.position.z)
        }
    }
}
