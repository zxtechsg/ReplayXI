import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackPlayerLabelWorkTests: XCTestCase {
    private struct Phase: Codable {
        let name: String
        let samples: Int
        let changedLabelTransforms: Int
        let work: PlaybackSpatialLabels.UpdateWork
    }

    private struct Report: Codable {
        let players: Int
        let phases: [Phase]
        let qualification: String
    }

    private struct Snapshot: Equatable {
        let transform: Transform
        let enabled: Bool
        let outline: Bool
        let fullGlyph: Bool
        let compactGlyph: Bool
        let boardTransform: Transform
        let boardEnabled: Bool
        let stripTransform: Transform
        let stripEnabled: Bool
        let acceptsInput: Bool
    }

    func testPausedAndForwardReversePlaybackCaptureRequestedLabelWrites() throws {
        let (scenario, root) = try fixture()
        XCTAssertEqual(scenario.players.count, 22)
        update(root, scenario: scenario, time: 4)
        let baseline = try snapshots(root, scenario: scenario)
        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        for _ in 0..<60 { update(root, scenario: scenario, time: 4) }
        let paused = PlaybackSpatialLabels.updateWork
        XCTAssertEqual(paused.visitedPlayerLabels, 60 * scenario.players.count)
        XCTAssertEqual(paused.transformWrites, 0)
        XCTAssertEqual(paused.stylePropertyWrites, 0)
        XCTAssertEqual(paused.visibilityWrites, 0)
        XCTAssertEqual(paused.inputComponentWrites, 0)
        XCTAssertEqual(try snapshots(root, scenario: scenario), baseline)

        let forwardTimes: [TimeInterval] = (1...30).map { 4.0 + Double($0) / 30.0 }
        let reverseTimes: [TimeInterval] = (0..<30).reversed().map { 4.0 + Double($0) / 30.0 }
        let times = forwardTimes + reverseTimes
        var last = baseline
        var changed = 0
        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        for time in times {
            update(root, scenario: scenario, time: time)
            try assertPositionsAndFacing(root, scenario: scenario, time: time, view: .tacticalTable,
                                         perspective: scenario.defaultPerspectiveID)
            let current = try snapshots(root, scenario: scenario)
            changed += zip(last, current).filter { $0.0.transform != $0.1.transform }.count
            last = current
        }
        let moving = PlaybackSpatialLabels.updateWork
        XCTAssertGreaterThan(changed, 0)
        XCTAssertEqual(moving.transformWrites, changed, "One combined write for each actual transform change")
        XCTAssertEqual(moving.stylePropertyWrites, 0)
        XCTAssertEqual(moving.visibilityWrites, 0)
        XCTAssertEqual(last, baseline)
        let report = Report(players: scenario.players.count, phases: [
            Phase(name: "60_paused_updates", samples: 60, changedLabelTransforms: 0, work: paused),
            Phase(name: "60_forward_reverse_updates", samples: times.count,
                  changedLabelTransforms: changed, work: moving)
        ], qualification: "DEBUG requested RealityKit property/component writes from the player-tag layer only. Not internal engine work, allocations, CPU time or headset FPS. Poses and tag states are verified independently; no timing threshold.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Cycle137-PlayerLabelWork.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPOVSelectionAndFocusSwitchesRetainBillboardsAndCorrectTagStyle() throws {
        let (scenario, root) = try fixture()
        for perspective in [scenario.defaultPerspectiveID, "red-lb", "navy-rb"] {
            for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson, .positional, .tacticalTable] {
                update(root, scenario: scenario, time: 8, view: view, perspective: perspective)
                try assertPositionsAndFacing(root, scenario: scenario, time: 8, view: view, perspective: perspective)
                for player in scenario.players {
                    let tag = try label(player.id, in: root)
                    if view == .firstPerson, player.id == perspective { XCTAssertFalse(tag.isEnabled) }
                    guard tag.isEnabled else { continue }
                    let compact = (view == .tacticalTable || view == .touchline) && player.id != perspective
                    XCTAssertEqual(try child("selected-outline", in: tag).isEnabled, player.id == perspective)
                    XCTAssertEqual(try child("compact-label-glyph", in: tag).isEnabled, compact)
                    XCTAssertEqual(try child("label-glyph", in: tag).isEnabled, !compact)
                    XCTAssertEqual(try child("label-board", in: tag).isEnabled, !compact)
                    XCTAssertEqual(try child("team-strip", in: tag).isEnabled, !compact)
                }
                let settled = try snapshots(root, scenario: scenario)
                update(root, scenario: scenario, time: 8, view: view, perspective: perspective)
                XCTAssertEqual(try snapshots(root, scenario: scenario), settled)
            }
        }
        let focused: Set<String> = [scenario.defaultPerspectiveID, "red-lb"]
        update(root, scenario: scenario, time: 8, focused: focused)
        for player in scenario.players {
            XCTAssertEqual(try label(player.id, in: root).isEnabled, focused.contains(player.id))
        }
        update(root, scenario: scenario, time: 9, focused: nil)
        XCTAssertTrue(try snapshots(root, scenario: scenario).allSatisfy(\.enabled))
        try assertPositionsAndFacing(root, scenario: scenario, time: 9, view: .tacticalTable,
                                     perspective: scenario.defaultPerspectiveID)
    }

    func testHiddenTagsCatchUpAndInputReturnsAfterAnnotationEditing() throws {
        let (scenario, root) = try fixture()
        update(root, scenario: scenario, time: 4)
        let before = try snapshots(root, scenario: scenario)
        update(root, scenario: scenario, time: 12, enabled: [], acceptsInput: false)
        for player in scenario.players {
            let tag = try label(player.id, in: root)
            XCTAssertFalse(tag.isEnabled)
            XCTAssertNil(tag.components[InputTargetComponent.self])
        }
        update(root, scenario: scenario, time: 12, acceptsInput: true)
        let after = try snapshots(root, scenario: scenario)
        XCTAssertNotEqual(before.map(\.transform), after.map(\.transform))
        XCTAssertTrue(after.allSatisfy { $0.enabled && $0.acceptsInput })
        try assertPositionsAndFacing(root, scenario: scenario, time: 12, view: .tacticalTable,
                                     perspective: scenario.defaultPerspectiveID)
    }

    func testActualEntityMutationsClonesAndDetachedParentsAreNotHiddenByCaching() throws {
        let (scenario, root) = try fixture()
        update(root, scenario: scenario, time: 4)
        let baseline = try snapshots(root, scenario: scenario)
        let original = try label(scenario.defaultPerspectiveID, in: root)
        let labelsRoot = try child("player-labels-root", in: root)
        let clone = original.clone(recursive: true)
        original.removeFromParent()
        labelsRoot.addChild(clone)
        try perturb(clone)
        let detachedOriginal = original.transform
        update(root, scenario: scenario, time: 4)
        XCTAssertEqual(try snapshots(root, scenario: scenario), baseline)
        XCTAssertEqual(original.transform, detachedOriginal)
        labelsRoot.removeFromParent()
        try perturb(clone)
        let changed = clone.transform
        update(root, scenario: scenario, time: 4)
        XCTAssertEqual(clone.transform, changed, "A detached label hierarchy is not the active scene")
        root.addChild(labelsRoot)
        update(root, scenario: scenario, time: 4)
        XCTAssertEqual(try snapshots(root, scenario: scenario), baseline)
    }

    func testParentPitchTransformDoesNotDoubleApplyTagScaleOrBillboardPosition() throws {
        let (scenario, root) = try fixture()
        update(root, scenario: scenario, time: 4)
        let before = try snapshots(root, scenario: scenario)
        root.transform = Transform(scale: SIMD3<Float>(repeating: 0.025),
                                   rotation: simd_quatf(angle: 0.4, axis: [0, 1, 0]),
                                   translation: [2, 1, -3])
        update(root, scenario: scenario, time: 4)
        XCTAssertEqual(try snapshots(root, scenario: scenario), before)
        let tag = try label(scenario.defaultPerspectiveID, in: root)
        assertVector(tag.position(relativeTo: nil), root.convert(position: tag.position, to: nil))
    }

    func testEquivalentQuaternionSignsSkipWritesButTinyActualChangesAreRestored() throws {
        let (scenario, root) = try fixture()
        update(root, scenario: scenario, time: 4)
        let tag = try label(scenario.defaultPerspectiveID, in: root)
        let expected = tag.transform
        // These are the same rotation, not a reason to resubmit the component.
        for player in scenario.players {
            let identity = try label(player.id, in: root)
            identity.orientation = simd_quatf(vector: -identity.orientation.vector)
        }
        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        update(root, scenario: scenario, time: 4)
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.transformWrites, 0)
        try assertPositionsAndFacing(root, scenario: scenario, time: 4, view: .tacticalTable,
                                     perspective: scenario.defaultPerspectiveID)

        tag.position.x += 0.0001
        XCTAssertNotEqual(tag.position, expected.translation)
        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        update(root, scenario: scenario, time: 4)
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.transformWrites, 1)
        XCTAssertEqual(tag.position, expected.translation)

        tag.orientation = simd_quatf(angle: 0.0001, axis: [0, 1, 0]) * expected.rotation
        XCTAssertNotEqual(tag.orientation.vector, expected.rotation.vector)
        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        update(root, scenario: scenario, time: 4)
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.transformWrites, 1)
        assertVector(tag.orientation.act([0, 0, 1]), expected.rotation.act([0, 0, 1]))

        tag.scale.x += 0.0001
        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        update(root, scenario: scenario, time: 4)
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.transformWrites, 1)
        XCTAssertEqual(tag.scale, expected.scale)
        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        update(root, scenario: scenario, time: 4)
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.transformWrites, 0)
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.stylePropertyWrites, 0)
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.visibilityWrites, 0)
    }

    private func fixture() throws -> (ReplayScenario, Entity) {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = Entity()
        root.addChild(PlaybackSpatialLabels.makePlayerLabels(for: scenario))
        return (scenario, root)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: TimeInterval,
                        view: ReplayViewMode = .tacticalTable, perspective: String? = nil,
                        focused: Set<String>? = nil, enabled: Set<String>? = nil, acceptsInput: Bool = true) {
        let poses = Dictionary(uniqueKeysWithValues: scenario.players.map { ($0.id, $0.presentationPose(at: time)) })
        PlaybackSpatialLabels.updatePlayerLabels(in: root, scenario: scenario, posesByPlayerID: poses,
                                                  viewMode: view, perspectiveID: perspective ?? scenario.defaultPerspectiveID,
                                                  enabledPlayerIDs: enabled, focusedPlayerIDs: focused,
                                                  acceptsInput: acceptsInput)
    }

    private func snapshots(_ root: Entity, scenario: ReplayScenario) throws -> [Snapshot] {
        try scenario.players.map { player in
            let tag = try label(player.id, in: root)
            let board = try child("label-board", in: tag)
            let strip = try child("team-strip", in: tag)
            return Snapshot(transform: tag.transform, enabled: tag.isEnabled,
                            outline: try child("selected-outline", in: tag).isEnabled,
                            fullGlyph: try child("label-glyph", in: tag).isEnabled,
                            compactGlyph: try child("compact-label-glyph", in: tag).isEnabled,
                            boardTransform: board.transform, boardEnabled: board.isEnabled,
                            stripTransform: strip.transform, stripEnabled: strip.isEnabled,
                            acceptsInput: tag.components[InputTargetComponent.self] != nil)
        }
    }

    private func perturb(_ tag: Entity) throws {
        tag.transform = Transform(scale: [8, 7, 6], rotation: simd_quatf(angle: 1.3, axis: [1, 0, 0]), translation: [99, 88, 77])
        tag.isEnabled = false
        tag.components.remove(InputTargetComponent.self)
        for name in ["selected-outline", "label-glyph", "compact-label-glyph", "label-board", "team-strip"] {
            let part = try child(name, in: tag)
            part.isEnabled.toggle()
        }
        try child("label-board", in: tag).scale.x = 4
        try child("team-strip", in: tag).position.x = 4
    }

    private func assertPositionsAndFacing(_ root: Entity, scenario: ReplayScenario, time: TimeInterval,
                                          view: ReplayViewMode, perspective: String) throws {
        let observer: PitchPoint = switch view {
        case .tacticalTable: .init(x: 0, z: 100)
        case .touchline: .init(x: -70, z: 0)
        case .positional: .zero
        case .firstPerson: try XCTUnwrap(scenario.player(id: perspective)).presentationPose(at: time).position
        }
        for player in scenario.players {
            let tag = try label(player.id, in: root)
            guard tag.isEnabled else { continue }
            let point = player.presentationPose(at: time).position
            XCTAssertEqual(tag.position.x, point.x, accuracy: 0.0001)
            XCTAssertEqual(tag.position.z, point.z, accuracy: 0.0001)
            let direction = SIMD3<Float>(observer.x - point.x, 0, observer.z - point.z)
            if simd_length_squared(direction) > 0.000001 {
                assertVector(tag.orientation.act([0, 0, 1]), simd_normalize(direction))
            }
        }
    }

    private func label(_ id: String, in root: Entity) throws -> Entity { try child("player-label-\(id)", in: root) }
    private func child(_ name: String, in root: Entity) throws -> Entity { try XCTUnwrap(root.findEntity(named: name)) }
    private func assertVector(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.0001, file: file, line: line)
    }
}
