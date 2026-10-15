import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAthleteSurfaceTests: XCTestCase {
    func testAscendingAndDescendingLoftsHaveOutwardSideNormalsAndWinding() throws {
        let parts: [ReplayAthleteMeshLibrary.Part] = [.torso, .thigh, .shin, .sleeve, .upperArm, .forearm, .hand]
        for name in parts {
            let asset = try ReplayAthleteMeshLibrary.mesh(for: name, lod: .near)
            let model = try XCTUnwrap(asset.mesh.contents.models.first)
            let part = try XCTUnwrap(model.parts.first)
            let vertices = part.positions.elements
            let normals = try XCTUnwrap(part.normals).elements
            let indices = try XCTUnwrap(part.triangleIndices).elements
            // The first radial vertex is on +X; its outward normal must have
            // positive X even when the profile runs down from a shoulder/hip.
            XCTAssertGreaterThan(normals[0].x, 0.5, "\(name) inward side normal")
            let a = vertices[Int(indices[0])]
            let b = vertices[Int(indices[1])]
            let c = vertices[Int(indices[2])]
            let geometricNormal = simd_normalize(simd_cross(b - a, c - a))
            XCTAssertGreaterThan(geometricNormal.x, 0.5, "\(name) inward triangle winding")
            XCTAssertGreaterThan(simd_dot(normals[0], geometricNormal), 0.6, "\(name) shader and surface disagree")
        }
    }

    func testDescendingLimbCapsFaceAwayFromTheInterior() throws {
        let asset = try ReplayAthleteMeshLibrary.mesh(for: .thigh, lod: .near)
        let model = try XCTUnwrap(asset.mesh.contents.models.first)
        let part = try XCTUnwrap(model.parts.first)
        let normals = try XCTUnwrap(part.normals).elements
        // Five 14-vertex side rings, then a centre and 14 cap vertices at each end.
        XCTAssertEqual(normals[70].y, 1, accuracy: 0.0001)
        XCTAssertEqual(normals[85].y, -1, accuracy: 0.0001)
        let indices = try XCTUnwrap(part.triangleIndices).elements
        let vertices = part.positions.elements
        let sideIndexCount = 4 * 14 * 6
        let capExpectations: [(Int, Float)] = [(0, 1), (3, -1)]
        for (offset, expectedY) in capExpectations {
            let triangle = indices[(sideIndexCount + offset)..<(sideIndexCount + offset + 3)]
            let points = triangle.map { vertices[Int($0)] }
            let normal = simd_normalize(simd_cross(points[1] - points[0], points[2] - points[0]))
            XCTAssertEqual(normal.y, expectedY, accuracy: 0.0001)
        }
    }
}

@MainActor
final class ReplayAthleteHeadTests: XCTestCase {
    override func tearDown() {
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    func testImportedFaceSharesItsMeshAndKeepsTheWorstCaseNearBudget() throws {
        try ReplayAthleteHeadProvider.prewarm()
        XCTAssertTrue(ReplayAthleteHeadProvider.isPrewarmed)
        var heads: [ModelComponent] = []
        for index in 0..<5 {
            let appearance = ReplayAthleteAppearance.replayXI(index: index)
            let configuration = ReplayAthleteConfiguration(
                playerID: "face-\(index)", shirtNumber: 88, goalkeeper: false,
                kit: .replayXI(team: .home, goalkeeper: false, appearanceIndex: index),
                appearance: appearance
            )
            let athlete = try ReplayAthleteFactory.make(configuration: configuration, lod: .near)
            let head = try XCTUnwrap(athlete.root.findEntity(named: "head"))
            heads.append(try XCTUnwrap(head.components[ModelComponent.self]))
            XCTAssertEqual(head.parent?.name, ReplayAthleteJoint.headRoot.rawValue)
            XCTAssertEqual(athlete.metrics.modelEntities, 24)
            XCTAssertTrue(athlete.metrics.fits(ReplayAthleteLOD.near.budget))
            XCTAssertLessThanOrEqual(athlete.metrics.trianglesPerInstance, 6_400)
            XCTAssertNil(athlete.root.findEntity(named: "left-eye"), "eyes are part of the textured face")
            let material = try XCTUnwrap(heads.last?.materials.first as? PhysicallyBasedMaterial)
            XCTAssertNotNil(material.baseColor.texture)
            XCTAssertNotNil(material.normal.texture)
            if index > 0 {
                XCTAssertTrue(heads[index].mesh === heads[0].mesh)
            }
        }
    }

    func testImportedHeadMovesWithTheExistingGazeJointAndRewindsExactly() throws {
        try ReplayAthleteHeadProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .near)
        let head = try XCTUnwrap(rig.root.findEntity(named: "head"))
        ReplayAthleteMotion.update(rig, from: player, at: 12, lookTargetWorldPosition: [-12, 0, 18])
        let first = head.transformMatrix(relativeTo: rig.root)
        ReplayAthleteMotion.update(rig, from: player, at: 18, lookTargetWorldPosition: [12, 0, 18])
        XCTAssertNotEqual(head.transformMatrix(relativeTo: rig.root), first)
        ReplayAthleteMotion.update(rig, from: player, at: 12, lookTargetWorldPosition: [-12, 0, 18])
        XCTAssertEqual(head.transformMatrix(relativeTo: rig.root), first)
        XCTAssertTrue(head.availableAnimations.isEmpty)
    }

    func testPrewarmingFacesKeepsEveryDemoPlayerWithinTheExistingNearBudget() throws {
        try ReplayAthleteHeadProvider.prewarm()
        for scenario in DemoScenarios.all {
            for player in scenario.players {
                let rig = try ReplayAthleteFactory.make(for: player, lod: .near)
                XCTAssertEqual(rig.metrics.modelEntities, 24, player.id)
                XCTAssertTrue(rig.metrics.fits(ReplayAthleteLOD.near.budget), player.id)
            }
        }
    }

    func testTexturedNeckMeetsTheCollarWithoutAnOverlappingPrimitiveShell() throws {
        try ReplayAthleteHeadProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "red-lb"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .near)
        let head = try XCTUnwrap(rig.root.findEntity(named: "head"))
        XCTAssertNil(rig.root.findEntity(named: "neck-shell"))
        XCTAssertEqual(rig.joints[.headRoot].position.y, 0.125, accuracy: 0.0001)
        let component = try XCTUnwrap(head.components[ModelComponent.self])
        let model = try XCTUnwrap(component.mesh.contents.models.first)
        let part = try XCTUnwrap(model.parts.first)
        let vertices = part.positions.elements
        let neckline = vertices.filter {
            abs($0.y - ReplayAthleteHeadNeckSkirt.seatedBoundaryY) < 0.000_001
        }
        XCTAssertGreaterThanOrEqual(neckline.count, 22)
        let spine = rig.joints[.spine]
        for time in [0.0, 5, 12, 13.6, 18, 28] {
            let ball = scenario.ball.pose(at: time)
            ReplayAthleteMotion.update(
                rig, from: player, at: time,
                lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z]
            )
            let transform = head.transformMatrix(relativeTo: spine)
            for vertex in neckline {
                let collarY = (transform * SIMD4<Float>(vertex, 1)).y
                XCTAssertLessThan(collarY, 0.557, "neck edge detached at \(time)s")
                XCTAssertGreaterThan(collarY, 0.40, "neck skirt extends below collar area at \(time)s")
            }
        }
    }

    func testUnpreparedProviderKeepsProceduralFacesAvailable() throws {
        ReplayAthleteHeadProvider.resetForTesting()
        XCTAssertNil(ReplayAthleteHeadProvider.make(appearance: .replayXI(index: 0)))
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .near)
        XCTAssertEqual(rig.metrics.modelEntities, 29)
        XCTAssertNotNil(rig.root.findEntity(named: "left-eye"))
    }
}
