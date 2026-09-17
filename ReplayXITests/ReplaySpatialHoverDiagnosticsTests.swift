import RealityKit
import XCTest
@testable import ReplayXI

/// Structural diagnostics only. These tests do not synthesize system gaze or
/// claim that RealityKit renders a hover effect on a device. JSON attachments
/// distinguish reachable model components from the original collision owner.
@MainActor
final class ReplaySpatialHoverDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
    }

    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    func testPlayerBodyHierarchyAndJerseyPositiveControl() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario)
        var records: [[String: Any]] = []

        for player in scenario.players {
            let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            let target = try XCTUnwrap(body.findEntity(named: "interaction-target"))
            XCTAssertTrue(target.parent === body, "The body capsule remains the original hit owner")
            assertInputTarget(target)
            XCTAssertTrue(target.isEnabledInHierarchy)
            XCTAssertGreaterThan(visibleModels(in: body).count, 0, player.id)
            records.append(record(target, scope: root, semanticID: player.id, role: "player-body"))

            let tag = try XCTUnwrap(root.findEntity(named: "player-label-\(player.id)"))
            assertInputTarget(tag)
            XCTAssertGreaterThan(inheritedModels(for: tag).count, 0,
                                 "Positive control: number-tag visuals are descendants of their hover owner")
            records.append(record(tag, scope: root, semanticID: player.id, role: "jersey-control"))
        }
        try attach(records, name: "ReplayXI-Hover81-PlayerHierarchy")
    }

    func testAnnotationBodiesCardsAndRingSegmentsKeepMarkIdentity() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        var records: [[String: Any]] = []

        for kind in CoachMarkKind.allCases {
            let mark = CoachMark(
                kind: kind, start: PitchPoint(x: 18, z: 8),
                end: PitchPoint(x: 24, z: 18), label: "Hover diagnostic \(kind.rawValue)",
                revealTime: 8, hideTime: 18,
                playerID: kind == .playerLabel ? scenario.defaultPerspectiveID : nil
            )
            update(root, scenario: scenario, marks: [mark])
            let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
            XCTAssertTrue(markRoot.isEnabledInHierarchy)
            XCTAssertGreaterThan(visibleModels(in: markRoot).count, 0)
            let body = try XCTUnwrap(markRoot.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
            let card = try XCTUnwrap(markRoot.findEntity(named: AnnotationSceneAffordance.labelTargetName))
            let bodyTargets = descendants(of: body).filter { $0.components[CollisionComponent.self] != nil }
            let expectedBodyTargets: Int = switch kind {
            case .space: AnnotationSceneAffordance.spaceTargetSegmentCount
            case .arc: 16
            default: 1
            }
            XCTAssertEqual(bodyTargets.count, expectedBodyTargets)

            for target in bodyTargets + [card] {
                assertInputTarget(target)
                XCTAssertTrue(target.isEnabledInHierarchy)
                XCTAssertEqual(AnnotationSceneAffordance.targetAncestor(of: target),
                               AnnotationSceneTarget(markID: mark.id, role: .body))
                records.append(record(target, scope: root, semanticID: kind.rawValue,
                                      role: target === card ? "annotation-card" : "annotation-body"))
            }
        }
        try attach(records, name: "ReplayXI-Hover81-AnnotationHierarchy")
    }

    func testDecisionSlotsKeepReceiverIdentityAndVisibleGeometry() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let snapshot = try XCTUnwrap(scenario.decisionReview(at: 14.1, playerID: "navy-rw"))
        XCTAssertFalse(snapshot.passingOptions.isEmpty)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, decision: snapshot)
        let options = try XCTUnwrap(root.findEntity(named: DecisionOptionSceneOverlay.rootName))
        var records: [[String: Any]] = []
        var count = 0

        for (index, slot) in options.children.enumerated() where slot.isEnabledInHierarchy {
            let receiver = snapshot.passingOptions[index].receiverID
            let target = try XCTUnwrap(slot.children.first { $0.name.hasPrefix("decision-option-hit-target") })
            assertInputTarget(target)
            XCTAssertTrue(target.parent === slot)
            XCTAssertEqual(DecisionOptionSceneOverlay.playerIDAncestor(of: target), receiver)
            XCTAssertGreaterThan(visibleModels(in: slot).count, 0)
            records.append(record(target, scope: root, semanticID: receiver, role: "decision-option"))
            count += 1
        }
        XCTAssertEqual(count, min(snapshot.passingOptions.count, DecisionOptionSceneOverlay.maximumVisibleOptions))
        try attach(records, name: "ReplayXI-Hover81-DecisionHierarchy")
    }

    func testExistingEndpointHandlesAreHierarchicalPositiveControls() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = CoachMark(kind: .run, start: PitchPoint(x: 18, z: 8),
                             end: PitchPoint(x: 24, z: 18), label: "Handle control", revealTime: 8)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [mark], selected: mark.id, editable: true)
        let selection = try XCTUnwrap(root.findEntity(named: AnnotationSceneAffordance.selectionRootName))
        var records: [[String: Any]] = []

        for (prefix, role) in [("annotation-target-start-", AnnotationSceneTargetRole.start),
                               ("annotation-target-end-", AnnotationSceneTargetRole.end)] {
            let handle = try XCTUnwrap(descendants(of: selection).first { $0.name.hasPrefix(prefix) })
            assertInputTarget(handle)
            XCTAssertTrue(handle.isEnabledInHierarchy)
            XCTAssertEqual(AnnotationSceneAffordance.targetAncestor(of: handle),
                           AnnotationSceneTarget(markID: mark.id, role: role))
            XCTAssertGreaterThan(inheritedModels(for: handle).count, 0)
            records.append(record(handle, scope: root, semanticID: role.rawValue, role: "handle-control"))
        }
        let player = try XCTUnwrap(root.findEntity(named: "player-\(scenario.defaultPerspectiveID)"))
        XCTAssertFalse(try XCTUnwrap(player.findEntity(named: "interaction-target")).isEnabled)
        try attach(records, name: "ReplayXI-Hover81-HandleHierarchy")
    }

    func testGroupAPIFixtureChangesOnlyHoverComponentsNotHitOwnership() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario)
        let player = try XCTUnwrap(root.findEntity(named: "player-\(scenario.defaultPerspectiveID)"))
        let target = try XCTUnwrap(player.findEntity(named: "interaction-target"))
        let visual = try XCTUnwrap(visibleModels(in: player).first)
        XCTAssertNil(visual.components[InputTargetComponent.self])
        XCTAssertNil(visual.components[CollisionComponent.self])
        let entities = descendants(of: root)
        var before: [EntityState] = []
        for entity in entities { before.append(EntityState(entity)) }
        let group = HoverEffectComponent.GroupID()
        let otherGroup = HoverEffectComponent.GroupID()
        XCTAssertNotEqual(group, otherGroup)
        let effect = HoverEffectComponent(.highlight(.default, groupID: group))

        // This deliberately exercises component storage only. The SDK exposes
        // no supported API here to synthesize a system hover activation.
        target.components.set(effect)
        visual.components.set(effect)

        XCTAssertEqual(target.components[HoverEffectComponent.self]?.hoverEffect.groupID, group)
        XCTAssertEqual(visual.components[HoverEffectComponent.self]?.hoverEffect.groupID, group)
        XCTAssertEqual(groupLinkedModels(for: target, scope: root).map(ObjectIdentifier.init),
                       [ObjectIdentifier(visual)])
        XCTAssertEqual(descendants(of: root).map(ObjectIdentifier.init), entities.map(ObjectIdentifier.init))
        for state in before {
            XCTAssertEqual(state.entity.name, state.name)
            XCTAssertTrue(state.entity.parent === state.parent)
            XCTAssertEqual(state.entity.transform, state.transform)
            XCTAssertEqual(state.entity.components[InputTargetComponent.self], state.input)
            XCTAssertEqual(state.entity.components[CollisionComponent.self], state.collision)
            XCTAssertTrue(state.entity.components[ModelComponent.self]?.mesh === state.mesh)
        }
        try attach([record(target, scope: root, semanticID: scenario.defaultPerspectiveID,
                           role: "api-fixture-not-render-validation")], name: "ReplayXI-Hover81-GroupAPIFixture")
    }

    @MainActor
    private struct EntityState {
        let entity: Entity
        let name: String
        let parent: Entity?
        let transform: Transform
        let input: InputTargetComponent?
        let collision: CollisionComponent?
        let mesh: MeshResource?

        init(_ entity: Entity) {
            self.entity = entity
            name = entity.name
            parent = entity.parent
            transform = entity.transform
            input = entity.components[InputTargetComponent.self]
            collision = entity.components[CollisionComponent.self]
            mesh = entity.components[ModelComponent.self]?.mesh
        }
    }

    private func assertInputTarget(_ target: Entity, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(target.components[InputTargetComponent.self], file: file, line: line)
        XCTAssertNotNil(target.components[CollisionComponent.self], file: file, line: line)
        XCTAssertNotNil(target.components[HoverEffectComponent.self], file: file, line: line)
    }

    private func descendants(of root: Entity) -> [Entity] {
        var result = [root]
        for child in root.children { result.append(contentsOf: descendants(of: child)) }
        return result
    }

    private func visibleModels(in root: Entity) -> [Entity] {
        descendants(of: root).filter { $0.isEnabledInHierarchy && $0.components[ModelComponent.self] != nil }
    }

    private func hoverOwner(of entity: Entity) -> Entity? {
        var cursor: Entity? = entity
        while let current = cursor {
            if current.components[HoverEffectComponent.self] != nil { return current }
            cursor = current.parent
        }
        return nil
    }

    private func inheritedModels(for target: Entity) -> [Entity] {
        guard let owner = hoverOwner(of: target),
              owner.components[HoverEffectComponent.self]?.hoverEffect.groupID == nil else { return [] }
        return visibleModels(in: owner).filter { hoverOwner(of: $0) === owner }
    }

    private func groupLinkedModels(for target: Entity, scope: Entity) -> [Entity] {
        guard let owner = hoverOwner(of: target),
              let group = owner.components[HoverEffectComponent.self]?.hoverEffect.groupID else { return [] }
        return visibleModels(in: scope).filter {
            $0.components[HoverEffectComponent.self]?.hoverEffect.groupID == group
        }
    }

    private func record(_ target: Entity, scope: Entity, semanticID: String, role: String) -> [String: Any] {
        let inherited = inheritedModels(for: target)
        let grouped = groupLinkedModels(for: target, scope: scope)
        return [
            "semanticID": semanticID, "role": role, "target": target.name,
            "parent": target.parent?.name ?? "", "hoverOwner": hoverOwner(of: target)?.name ?? "",
            "targetEnabled": target.isEnabledInHierarchy,
            "hasInput": target.components[InputTargetComponent.self] != nil,
            "collisionShapes": target.components[CollisionComponent.self]?.shapes.count ?? 0,
            "targetDescendantModels": visibleModels(in: target).map(\.name),
            "hierarchicallyLinkedModels": inherited.map(\.name),
            "groupLinkedModels": grouped.map(\.name),
            "linkedVisibleModelCount": inherited.count + grouped.count,
            "runtimeHoverWasActivated": false,
        ]
    }

    private func attach(_ records: [[String: Any]], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "scope": "Structural component graph only; no system hover or rendered effect tested",
            "samples": records,
        ], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name + ".json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, marks: [CoachMark] = [],
                        selected: UUID? = nil, editable: Bool = false,
                        decision: ReplayDecisionSnapshot? = nil) {
        PitchSceneFactory.update(
            root: root, scenario: scenario, time: 14.1, viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID, marks: marks,
            selectedAnnotationID: selected, selectedAnnotationIsEditable: editable,
            decisionSnapshot: decision, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil
        )
    }
}
