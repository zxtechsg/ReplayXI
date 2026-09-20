import Dispatch
import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

/// Cold label-construction attribution only. No renderer or physics bake.
@MainActor
final class PlaybackPlayerLabelCollision157Tests: XCTestCase {
    private struct Node: Codable, Equatable {
        let path: String
        let transform: [Float]
        let enabled: Bool
        let modelBounds: [Float]?
        let materialCount: Int
        let collisionBounds: [[Float]]
        let collisionIsStatic: Bool?
        let collisionMode: String?
        let collisionGroup: UInt32?
        let collisionMask: UInt32?
        let inputTypes: UInt32?
        let inputEnabled: Bool?
        let hover: Bool
        let accessibilityElement: Bool?
        let accessibilityLabel: String?
        let accessibilityValue: String?
    }

    private struct RootRow: Codable {
        let scenario: String
        let ordinalInTest: Int
        let ordinalInScenario: Int
        let players: Int
        let labelRootNanoseconds: UInt64
        let collision: PlaybackSpatialLabels.PlayerLabelCollisionWork
        let nestedCollisionSharePercent: Double
        let textCacheCountBefore: Int
        let text: PlaybackSpatialLabels.TextCenteringWork
        let entities: Int
        let models: Int
        let colliders: Int
        let inputTargets: Int
        let hoverTargets: Int
        let exactGraphMatchesFirstInScenario: Bool
    }

    private struct Report: Codable {
        let scope: String
        let ownership: String
        let rows: [RootRow]
        let firstGraphsByScenario: [String: [Node]]
    }

    func testRecordsTwentyFreshLabelRootsAndExactCollisionContracts() throws {
        let scenarios = FootballReferenceScenarios.all
        XCTAssertEqual(scenarios.count, 5)
        var rows: [RootRow] = []
        var firstGraphs: [String: [Node]] = [:]
        var firstShape: ShapeResource?
        for scenario in scenarios {
            XCTAssertEqual(scenario.players.count, 22)
            XCTAssertEqual(Set(scenario.players.map(\.team)), Set([FootballTeam.home, .away]))
            for ordinal in 1...4 {
                PlaybackSpatialLabels.resetPlayerLabelCollisionWorkForTesting()
                PlaybackSpatialLabels.resetTextCenteringWorkForTesting()
                let cacheBefore = PlaybackSpatialLabels.cachedTextMeshCount
                let start = DispatchTime.now().uptimeNanoseconds
                let root = PlaybackSpatialLabels.makePlayerLabels(for: scenario)
                let elapsed = DispatchTime.now().uptimeNanoseconds - start
                let collision = PlaybackSpatialLabels.playerLabelCollisionWork
                let text = PlaybackSpatialLabels.textCenteringWork
                // Oracles, traversal, serialization and cleanup are untimed.
                // This independent public shape is not an app generation request.
                let oracle = CollisionComponent(shapes: [.generateBox(size: [1.02, 0.40, 0.10])], isStatic: false)
                try assertContracts(root, scenario: scenario, oracle: oracle)
                let shape = try XCTUnwrap(root.children.first?.components[CollisionComponent.self]?.shapes.first)
                if let firstShape { XCTAssertEqual(shape, firstShape, "Public resource equality across roots") }
                else { firstShape = shape }
                let graph = snapshot(root)
                if let first = firstGraphs[scenario.id] { XCTAssertEqual(graph, first) }
                else { firstGraphs[scenario.id] = graph }
                XCTAssertLessThanOrEqual(collision.generationCalls, rows.isEmpty ? 1 : 0,
                    "Only the first process use can generate; resetting counters must not evict the shared shape")
                if collision.generationCalls == 0 { XCTAssertEqual(collision.generationNanoseconds, 0) }
                XCTAssertLessThanOrEqual(collision.generationNanoseconds, elapsed)
                XCTAssertEqual(text.cacheHits + text.cacheMisses, 2 * scenario.players.count)
                if ordinal > 1 {
                    XCTAssertEqual(text.cacheHits, 44)
                    XCTAssertEqual(text.cacheMisses, 0)
                }
                XCTAssertEqual(graph.count, 133)
                XCTAssertEqual(graph.filter { $0.modelBounds != nil }.count, 110)
                XCTAssertEqual(graph.reduce(0) { $0 + $1.materialCount }, 110)
                XCTAssertEqual(graph.filter { !$0.collisionBounds.isEmpty }.count, 22)
                XCTAssertEqual(graph.filter { $0.inputTypes != nil }.count, 22)
                XCTAssertEqual(graph.filter(\.hover).count, 22)
                rows.append(RootRow(scenario: scenario.id, ordinalInTest: rows.count + 1,
                    ordinalInScenario: ordinal, players: scenario.players.count,
                    labelRootNanoseconds: elapsed, collision: collision,
                    nestedCollisionSharePercent: 100 * Double(collision.generationNanoseconds) / Double(max(elapsed, 1)),
                    textCacheCountBefore: cacheBefore, text: text,
                    entities: graph.count, models: graph.filter { $0.modelBounds != nil }.count,
                    colliders: graph.filter { !$0.collisionBounds.isEmpty }.count,
                    inputTargets: graph.filter { $0.inputTypes != nil }.count,
                    hoverTargets: graph.filter(\.hover).count,
                    exactGraphMatchesFirstInScenario: graph == firstGraphs[scenario.id]))
                for child in Array(root.children) { child.removeFromParent() }
            }
        }
        XCTAssertEqual(rows.count, 20)
        XCTAssertLessThanOrEqual(rows.reduce(0) { $0 + $1.collision.generationCalls }, 1)
        let report = Report(
            scope: "Native test-process CPU, compiler/runtime flags supplied by runner. Five actual rosters x four fresh label roots; times cover makePlayerLabels only. Nested box generation includes DEBUG clock overhead and is already inside root time. Ordinals mean first observed/repeated within this test, not guaranteed process-cold frameworks/assets; text-cache state is reported. Bounds oracle, assertions, census, snapshots, serialization and teardown are untimed. No renderer, physics bake, complete match root, warm-update timing, private allocation/GPU identity, headset or FPS claim; no elapsed-time pass threshold.",
            ownership: "One immutable static player-label shape; independently owned collision components and transforms. Counters reset observations only. Public resource equality is checked within and across roots, not private allocation identity.",
            rows: rows, firstGraphsByScenario: firstGraphs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-PlayerLabelCollision157-TwentyRoots.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testViewAndInputTransitionsRetainCollisionBoundsWithoutNewGeneration() throws {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first)
        let root = Entity()
        let labels = PlaybackSpatialLabels.makePlayerLabels(for: scenario)
        root.addChild(labels)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let oracle = CollisionComponent(shapes: [.generateBox(size: [1.02, 0.40, 0.10])], isStatic: false)
        PlaybackSpatialLabels.resetPlayerLabelCollisionWorkForTesting()
        let poses = Dictionary(uniqueKeysWithValues: scenario.players.map { ($0.id, $0.presentationPose(at: 3)) })
        for view: ReplayViewMode in [.tacticalTable, .firstPerson, .touchline, .tacticalTable] {
            for acceptsInput in [false, true] {
                PlaybackSpatialLabels.updatePlayerLabels(in: root, scenario: scenario, posesByPlayerID: poses,
                    viewMode: view, perspectiveID: scenario.defaultPerspectiveID, acceptsInput: acceptsInput)
                try assertContracts(labels, scenario: scenario, oracle: oracle, acceptsInput: acceptsInput,
                                    initialGraph: false)
                let previous = snapshot(labels)
                PlaybackSpatialLabels.updatePlayerLabels(in: root, scenario: scenario, posesByPlayerID: poses,
                    viewMode: view, perspectiveID: scenario.defaultPerspectiveID, acceptsInput: acceptsInput)
                XCTAssertEqual(snapshot(labels), previous)
            }
        }
        XCTAssertEqual(PlaybackSpatialLabels.playerLabelCollisionWork, .init())
    }

    private func assertContracts(_ root: Entity, scenario: ReplayScenario, oracle: CollisionComponent,
                                 acceptsInput: Bool = true, initialGraph: Bool = true) throws {
        XCTAssertEqual(root.name, "player-labels-root")
        XCTAssertEqual(root.children.map(\.name), scenario.players.map { "player-label-\($0.id)" })
        let expectedBounds = try XCTUnwrap(oracle.shapes.first).bounds
        let firstShape = try XCTUnwrap(root.children.first?.components[CollisionComponent.self]?.shapes.first)
        for player in scenario.players {
            let tag = try XCTUnwrap(root.findEntity(named: "player-label-\(player.id)"))
            XCTAssertEqual(tag.children.map(\.name),
                ["selected-outline", "label-board", "team-strip", "label-glyph", "compact-label-glyph"])
            if initialGraph { XCTAssertEqual(tag.transform, .identity) }
            let input = tag.components[InputTargetComponent.self]
            XCTAssertEqual(input != nil, acceptsInput)
            if acceptsInput { XCTAssertEqual(input, InputTargetComponent(allowedInputTypes: .all)) }
            XCTAssertNotNil(tag.components[HoverEffectComponent.self])
            let accessibility = try XCTUnwrap(tag.components[AccessibilityComponent.self])
            XCTAssertFalse(accessibility.isAccessibilityElement)
            XCTAssertEqual(accessibility.label, LocalizedStringResource(
                stringLiteral: "Number \(player.shirtNumber), \(player.displayName)"))
            XCTAssertEqual(accessibility.value, LocalizedStringResource(stringLiteral: player.role))
            let collision = try XCTUnwrap(tag.components[CollisionComponent.self])
            XCTAssertEqual(collision.shapes.count, 1)
            XCTAssertEqual(collision.shapes.first, firstShape)
            XCTAssertEqual(collision.isStatic, oracle.isStatic)
            XCTAssertEqual(collision.mode, oracle.mode)
            XCTAssertEqual(collision.filter, oracle.filter)
            let bounds = try XCTUnwrap(collision.shapes.first).bounds
            XCTAssertEqual(bounds.center, expectedBounds.center)
            XCTAssertEqual(bounds.extents, expectedBounds.extents)
            XCTAssertEqual(bounds.center, .zero)
            XCTAssertEqual(bounds.extents.x, 1.02, accuracy: 0.000001)
            XCTAssertEqual(bounds.extents.y, 0.40, accuracy: 0.000001)
            XCTAssertEqual(bounds.extents.z, 0.10, accuracy: 0.000001)
        }
    }

    private func snapshot(_ root: Entity) -> [Node] {
        func bounds(_ value: BoundingBox) -> [Float] {
            [value.center.x, value.center.y, value.center.z, value.extents.x, value.extents.y, value.extents.z]
        }
        var rows: [Node] = []
        func visit(_ entity: Entity, path: String) {
            let t = entity.transform
            let model = entity.components[ModelComponent.self]
            let collision = entity.components[CollisionComponent.self]
            let input = entity.components[InputTargetComponent.self]
            let accessibility = entity.components[AccessibilityComponent.self]
            rows.append(Node(path: path,
                transform: [t.translation.x, t.translation.y, t.translation.z,
                    t.rotation.vector.x, t.rotation.vector.y, t.rotation.vector.z, t.rotation.vector.w,
                    t.scale.x, t.scale.y, t.scale.z], enabled: entity.isEnabled,
                modelBounds: model.map { bounds($0.mesh.bounds) }, materialCount: model?.materials.count ?? 0,
                collisionBounds: collision?.shapes.map { bounds($0.bounds) } ?? [],
                collisionIsStatic: collision?.isStatic,
                collisionMode: collision.map { String(describing: $0.mode) },
                collisionGroup: collision?.filter.group.rawValue, collisionMask: collision?.filter.mask.rawValue,
                inputTypes: input?.allowedInputTypes.rawValue, inputEnabled: input?.isEnabled,
                hover: entity.components[HoverEffectComponent.self] != nil,
                accessibilityElement: accessibility?.isAccessibilityElement,
                accessibilityLabel: accessibility?.label.map { String(localized: $0) },
                accessibilityValue: accessibility?.value.map { String(localized: $0) }))
            for child in entity.children { visit(child, path: path + "/" + child.name) }
        }
        visit(root, path: root.name)
        return rows
    }
}
