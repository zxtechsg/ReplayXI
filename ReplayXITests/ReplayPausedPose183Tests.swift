import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayPausedPose183Tests: XCTestCase {
    func testPausedUpdatesReuseProceduralPosesWithoutChangingScene() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        update(root, scenario, time: 12)
        let before = PitchSceneFactory.proceduralPoseWork(for: root)
        XCTAssertGreaterThan(before.evaluations, 0)
        let expected = snapshot(root)
        for _ in 0..<60 { update(root, scenario, time: 12) }
        let after = PitchSceneFactory.proceduralPoseWork(for: root)
        XCTAssertEqual(after.evaluations, before.evaluations)
        XCTAssertGreaterThanOrEqual(after.cacheHits - before.cacheHits, before.checkpoints * 60)
        assertSnapshot(root, equals: expected)
        XCTAssertLessThanOrEqual(after.checkpoints, 32)

        update(root, scenario, time: 12.1)
        XCTAssertGreaterThan(PitchSceneFactory.proceduralPoseWork(for: root).evaluations, after.evaluations)
        update(root, scenario, time: 12)
        assertSnapshot(root, equals: expected)
    }

    func testRepeatedImpactRebuildsBasePoseInsteadOfAccumulatingBlend() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let cue = PlayerRagdollCue(playerID: scenario.defaultPerspectiveID, impactTime: 11,
            duration: 3, impactDirection: [0.45, 0.89], impulse: 1.1)
        update(root, scenario, time: 12, cue: cue)
        let expected = snapshot(root)
        let before = PitchSceneFactory.proceduralPoseWork(for: root)
        for _ in 0..<20 { update(root, scenario, time: 12, cue: cue) }
        assertSnapshot(root, equals: expected)
        XCTAssertGreaterThan(PitchSceneFactory.proceduralPoseWork(for: root).evaluations, before.evaluations)
        update(root, scenario, time: 12)
        let normal = snapshot(root)
        update(root, scenario, time: 12)
        assertSnapshot(root, equals: normal)
        XCTAssertNotEqual(normal, expected)
    }

    func testSelectionChangesAndRigEvictionDoNotRetainOldCheckpoints() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        for player in scenario.players {
            update(root, scenario, time: 12, perspective: player.id)
            let bindings = PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root)
            let work = PitchSceneFactory.proceduralPoseWork(for: root)
            XCTAssertLessThanOrEqual(work.checkpoints, bindings.cachedBindings)
            XCTAssertLessThanOrEqual(work.checkpoints, 32)
        }
    }

    private func update(_ root: Entity, _ scenario: ReplayScenario, time: TimeInterval,
                        cue: PlayerRagdollCue? = nil, perspective: String? = nil) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time,
            viewMode: .tacticalTable, perspectiveID: perspective ?? scenario.defaultPerspectiveID,
            marks: scenario.coachMarks, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil, ragdollCue: cue)
    }

    private struct Pose: Equatable {
        let transform: Transform
        let joints: [Transform]
        let enabled: Bool
    }

    private func snapshot(_ root: Entity) -> [String: Pose] {
        var result: [String: Pose] = [:]
        func visit(_ entity: Entity, path: String) {
            result[path] = Pose(transform: entity.transform,
                joints: (entity as? ModelEntity)?.jointTransforms ?? [], enabled: entity.isEnabled)
            for (index, child) in entity.children.enumerated() {
                visit(child, path: path + "/\(index):\(child.name)")
            }
        }
        visit(root, path: root.name)
        return result
    }

    private func assertSnapshot(_ root: Entity, equals expected: [String: Pose],
                                file: StaticString = #filePath, line: UInt = #line) {
        let actual = snapshot(root)
        let changed = Set(actual.keys).union(expected.keys).filter { path in
            guard let lhs = actual[path], let rhs = expected[path] else { return true }
            // Native relative-to-parent bounds queries can differ by a few
            // micrometres after root transform publication. Labels are not
            // animation state; every rig/joint still requires exact equality.
            if path.contains("player-labels-root/") {
                return lhs.enabled != rhs.enabled || lhs.joints != rhs.joints
                    || simd_distance(lhs.transform.translation, rhs.transform.translation) > 0.000_01
                    || simd_distance(lhs.transform.scale, rhs.transform.scale) > 0.000_001
                    || simd_distance(lhs.transform.rotation.vector, rhs.transform.rotation.vector) > 0.000_001
            }
            return lhs != rhs
        }.sorted()
        XCTAssertTrue(changed.isEmpty, "Changed nodes (\(changed.count)): \(changed.prefix(6))",
                      file: file, line: line)
        for path in changed.prefix(3) {
            XCTAssertEqual(actual[path], expected[path], path, file: file, line: line)
        }
    }
}
