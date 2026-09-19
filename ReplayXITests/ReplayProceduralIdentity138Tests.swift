import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayProceduralIdentity138Tests: XCTestCase {
    func testFallbackModelsUseUnitRotationsAndPreserveTheirLocalAxes() throws {
        resetImportedParts()
        defer { resetImportedParts() }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        var receipt: [[String: Any]] = []
        for id in ["navy-rw", "red-lb"] {
            let player = try XCTUnwrap(scenario.player(id: id))
            for lod in ReplayAthleteLOD.allCases {
                let rig = try ReplayAthleteFactory.make(for: player, lod: lod)
                let parent = Entity()
                parent.transform = Transform(scale: [0.3, 0.3, 0.3],
                    rotation: simd_quatf(angle: 0.47, axis: [0, 1, 0]), translation: [2, 1, -3])
                parent.addChild(rig.root)
                let models = descendants(rig.root).filter { $0.components[ModelComponent.self] != nil }
                let invalid = models.filter { abs(simd_length($0.orientation.vector) - 1) > 0.0001 }
                XCTAssertTrue(invalid.isEmpty, "\(id) \(lod): non-unit models \(invalid.map(\.name))")
                XCTAssertTrue(rig.metrics.fits(lod.budget))

                for name in ["torso", "shorts", lod == .far ? "left-leg" : "left-boot"] {
                    let model = try XCTUnwrap(rig.root.findEntity(named: name))
                    let origin = model.convert(position: .zero, to: model.parent)
                    let end = model.convert(position: [0, 0, 0.1], to: model.parent)
                    let worldOrigin = model.convert(position: .zero, to: nil)
                    let worldEnd = model.convert(position: [0, 0, 0.1], to: nil)
                    let column = model.transform.matrix.columns.2
                    let matrixSpan = simd_length(SIMD3<Float>(column.x, column.y, column.z))
                    receipt.append(["player": id, "lod": String(describing: lod), "part": name,
                        "quaternionNorm": simd_length(model.orientation.vector),
                        "matrixForwardSpan": matrixSpan, "expectedScaleZ": model.scale.z,
                        "parentForwardSpan": simd_distance(origin, end),
                        "worldForwardSpan": simd_distance(worldOrigin, worldEnd)])
                    XCTAssertEqual(simd_length(model.orientation.act([0, 0, 1])), 1, accuracy: 0.0001)
                    XCTAssertEqual(matrixSpan, abs(model.scale.z), accuracy: 0.0001)
                    XCTAssertEqual(simd_distance(origin, end), abs(model.scale.z) * 0.1, accuracy: 0.0001)
                    XCTAssertGreaterThan(simd_distance(worldOrigin, worldEnd), 0.001)
                }
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: receipt,
            options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-ProceduralIdentity138.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFallbackAnimationKeepsUnitRotationsAndRewindsExactlyForBothTeams() throws {
        resetImportedParts()
        defer { resetImportedParts() }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        for id in ["navy-rw", "red-lb"] {
            let player = try XCTUnwrap(scenario.player(id: id))
            for lod in ReplayAthleteLOD.allCases {
                let rig = try ReplayAthleteFactory.make(for: player, lod: lod)
                var original: [Transform]?
                for time: TimeInterval in [6.75, 7.05, 3, 6.75] {
                    let ball = scenario.ball.pose(at: time)
                    ReplayAthleteMotion.update(rig, from: player, at: time,
                        lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z])
                    let nodes = descendants(rig.root)
                    let invalid = nodes.filter { abs(simd_length($0.orientation.vector) - 1) > 0.0001 }
                    XCTAssertTrue(invalid.isEmpty, "\(id) \(lod) \(time): \(invalid.map(\.name))")
                    let transforms = nodes.map(\.transform)
                    if let original, time == 6.75 { XCTAssertEqual(transforms, original) }
                    if original == nil { original = transforms }
                }
            }
        }
    }

    private func descendants(_ root: Entity) -> [Entity] {
        [root] + root.children.flatMap { descendants($0) }
    }

    private func resetImportedParts() {
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
    }
}
