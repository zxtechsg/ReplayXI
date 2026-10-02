import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayStadiumEnvironmentTests: XCTestCase {
    func testLocalGeometryHasBoundedDrawsTrianglesAndExplicitProvenance() throws {
        let geometry = ReplayStadiumEnvironment.geometry
        XCTAssertEqual(geometry.structure.triangleCount, 2_016)
        XCTAssertEqual(geometry.seats.triangleCount, 3_584)
        XCTAssertEqual(geometry.roof.triangleCount, 256)
        XCTAssertEqual(geometry.lights.triangleCount, 288)
        XCTAssertEqual(geometry.sky.triangleCount, 960)
        XCTAssertEqual(geometry.ground.triangleCount, 2)
        XCTAssertEqual(geometry.triangleCount, 7_106)
        XCTAssertLessThanOrEqual(geometry.triangleCount, ReplayStadiumEnvironment.maximumTriangles)

        ReplayStadiumEnvironment.prewarm()
        XCTAssertTrue(ReplayStadiumEnvironment.preparationSucceeded)
        let stadium = ReplayStadiumEnvironment.makeStadium()
        let sky = ReplayStadiumEnvironment.makeSkyRoot()
        XCTAssertEqual(stadium.name, ReplayStadiumEnvironment.stadiumRootName)
        XCTAssertEqual(sky.name, ReplayStadiumEnvironment.skyRootName)
        let models = allModels(in: stadium) + allModels(in: sky)
        XCTAssertEqual(models.count, 6)
        XCTAssertEqual(models.reduce(0) { $0 + ($1.model?.materials.count ?? 0) }, 6)
        for root in [stadium, sky] {
            let provenance = try XCTUnwrap(root.components[ReplayStadiumEnvironment.Provenance.self])
            XCTAssertEqual(provenance.source, "Local procedural stadium")
        }
        XCTAssertEqual(models.reduce(0) { total, model in
            total + (model.model?.mesh.contents.models.reduce(0) { count, mesh in
                count + mesh.parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 }
            } ?? 0)
        }, geometry.triangleCount)
    }

    func testEveryStadiumTriangleLeavesClearFieldAndOpenRoofCentre() {
        let geometry = ReplayStadiumEnvironment.geometry
        for mesh in geometry.stadium {
            for index in stride(from: 0, to: mesh.indices.count, by: 3) {
                let triangle = (index..<(index + 3)).map { mesh.positions[Int(mesh.indices[$0])] }
                // Checking every triangle against a common exterior half-plane
                // catches bridges over the field that vertex-only checks miss.
                let outside = triangle.allSatisfy { $0.x >= ReplayStadiumEnvironment.clearHalfWidth - 0.0001 }
                    || triangle.allSatisfy { $0.x <= -ReplayStadiumEnvironment.clearHalfWidth + 0.0001 }
                    || triangle.allSatisfy { $0.z >= ReplayStadiumEnvironment.clearHalfLength - 0.0001 }
                    || triangle.allSatisfy { $0.z <= -ReplayStadiumEnvironment.clearHalfLength + 0.0001 }
                XCTAssertTrue(outside, "A stadium triangle must never span the existing pitch")
            }
            XCTAssertTrue(mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            XCTAssertTrue(mesh.positions.allSatisfy { $0.y >= -0.026 && $0.y <= 24 })
        }
        XCTAssertTrue(geometry.roof.positions.allSatisfy {
            let beyond = SIMD2<Float>(max(0, abs($0.x) - ReplayStadiumEnvironment.clearHalfWidth),
                                      max(0, abs($0.z) - ReplayStadiumEnvironment.clearHalfLength))
            return simd_length(beyond) >= 19.999
        }, "The high roof keeps a wide opening above the pitch")
        XCTAssertTrue(geometry.ground.positions.allSatisfy { $0.y == ReplayStadiumEnvironment.groundY })
        XCTAssertLessThan(ReplayStadiumEnvironment.groundY, -0.04)
    }

    func testSkyIsYUpInwardFacingAndEnclosesRoomBackdrop() {
        let sky = ReplayStadiumEnvironment.geometry.sky
        XCTAssertEqual(sky.positions.first?.y, ReplayStadiumEnvironment.skyRadius)
        XCTAssertEqual(sky.positions.last?.y, -ReplayStadiumEnvironment.skyRadius)
        XCTAssertEqual(sky.textureCoordinates.count, sky.positions.count)
        for (position, normal) in zip(sky.positions, sky.normals) {
            XCTAssertEqual(simd_length(position), ReplayStadiumEnvironment.skyRadius, accuracy: 0.0001)
            XCTAssertLessThan(simd_dot(position, normal), -249)
        }
        for index in stride(from: 0, to: sky.indices.count, by: 3) {
            let a = sky.positions[Int(sky.indices[index])]
            let b = sky.positions[Int(sky.indices[index + 1])]
            let c = sky.positions[Int(sky.indices[index + 2])]
            XCTAssertGreaterThan(simd_dot(simd_cross(b - a, c - a), -(a + b + c)), 0)
        }
        for position in ReplayStadiumEnvironment.geometry.ground.positions {
            XCTAssertLessThan(simd_length(position), ReplayStadiumEnvironment.skyRadius)
        }
    }

    func testTealTierFrontsFaceThePitchAtStandingHeadHeight() {
        let seats = ReplayStadiumEnvironment.geometry.seats
        let eye = SIMD3<Float>(0, 1.7, 8)
        var fronts = 0
        for index in stride(from: 0, to: seats.indices.count, by: 3) {
            let ids = (index..<(index + 3)).map { Int(seats.indices[$0]) }
            let normal = seats.normals[ids[0]]
            guard abs(normal.y) < 0.01 else { continue }
            fronts += 1
            let centre = ids.reduce(SIMD3<Float>.zero) { $0 + seats.positions[$1] } / 3
            XCTAssertGreaterThan(simd_dot(normal, eye - centre), 0,
                                 "A tier needs a visible seat-coloured front when its top faces away")
        }
        XCTAssertEqual(fronts, 1_792)
    }

    func testEnvironmentCannotReceiveHitsOrParticipateInPhysics() {
        let roots = [ReplayStadiumEnvironment.makeSkyRoot(), ReplayStadiumEnvironment.makeStadium()]
        for root in roots {
            for entity in allEntities(in: root) {
                XCTAssertFalse(entity.components.has(CollisionComponent.self))
                XCTAssertFalse(entity.components.has(InputTargetComponent.self))
                XCTAssertFalse(entity.components.has(PhysicsBodyComponent.self))
                XCTAssertFalse(entity.components.has(PhysicsMotionComponent.self))
                XCTAssertFalse(entity.components.has(DirectionalLightComponent.self))
                XCTAssertFalse(entity.components.has(PointLightComponent.self))
                XCTAssertFalse(entity.components.has(SpotLightComponent.self))
            }
        }
    }

    func testReplayLightingIsTwoFixedShadowFreeNoninteractiveLights() throws {
        let root = ReplayStadiumEnvironment.makeReplayLighting()
        XCTAssertEqual(root.name, ReplayStadiumEnvironment.lightingRootName)
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.position, .zero)
        XCTAssertEqual(root.scale, SIMD3<Float>(repeating: 1))
        let key = try XCTUnwrap(root.findEntity(named: "stadium-key") as? DirectionalLight)
        let fill = try XCTUnwrap(root.findEntity(named: "stadium-fill") as? DirectionalLight)
        XCTAssertEqual(key.light.intensity, 2_200)
        XCTAssertEqual(fill.light.intensity, 500)
        XCTAssertFalse(key.components.has(DirectionalLightComponent.Shadow.self))
        XCTAssertFalse(fill.components.has(DirectionalLightComponent.Shadow.self))
        XCTAssertEqual(allEntities(in: root).filter { $0.components.has(DirectionalLightComponent.self) }.count, 2)
        for entity in allEntities(in: root) {
            XCTAssertFalse(entity.components.has(ModelComponent.self), "Lighting must not change scenery draw budgets")
            XCTAssertFalse(entity.components.has(CollisionComponent.self))
            XCTAssertFalse(entity.components.has(InputTargetComponent.self))
            XCTAssertFalse(entity.components.has(PhysicsBodyComponent.self))
            XCTAssertFalse(entity.components.has(PhysicsMotionComponent.self))
            XCTAssertFalse(entity.components.has(PointLightComponent.self))
            XCTAssertFalse(entity.components.has(SpotLightComponent.self))
            XCTAssertTrue(entity.availableAnimations.isEmpty)
        }
        let other = ReplayStadiumEnvironment.makeReplayLighting()
        root.isEnabled = false
        root.position = [4, 2, -6]
        XCTAssertTrue(other.isEnabled)
        XCTAssertEqual(other.position, .zero)
    }

    func testNewInstancesReuseResourcesAndKeepIndependentVisibilityAndTransforms() throws {
        let stadium = ReplayStadiumEnvironment.makeStadium()
        let otherStadium = ReplayStadiumEnvironment.makeStadium()
        let sky = ReplayStadiumEnvironment.makeSkyRoot()
        let otherSky = ReplayStadiumEnvironment.makeSkyRoot()
        for (first, second) in [(stadium, otherStadium), (sky, otherSky)] {
            XCTAssertFalse(first === second)
            for (a, b) in zip(allModels(in: first), allModels(in: second)) {
                XCTAssertTrue(try XCTUnwrap(a.model?.mesh) === XCTUnwrap(b.model?.mesh))
            }
            first.isEnabled = false
            first.position = [4, 2, -6]
            XCTAssertTrue(second.isEnabled)
            XCTAssertEqual(second.position, .zero)
        }
        let skyMaterial = try XCTUnwrap(allModels(in: sky).first?.model?.materials.first as? UnlitMaterial)
        let otherMaterial = try XCTUnwrap(allModels(in: otherSky).first?.model?.materials.first as? UnlitMaterial)
        let texture = try XCTUnwrap(skyMaterial.color.texture?.resource)
        let otherTexture = try XCTUnwrap(otherMaterial.color.texture?.resource)
        // Material readback can return a new Swift wrapper on visionOS. Public
        // resource equality (covered by TextureResourceSemantics150) tests the
        // shared resource, not wrapper or private GPU-allocation identity.
        XCTAssertEqual(texture, otherTexture)
        XCTAssertEqual(texture.width, ReplayStadiumEnvironment.skyTextureWidth)
        XCTAssertEqual(texture.height, ReplayStadiumEnvironment.skyTextureHeight)
        let expectedMeshes = allModels(in: otherStadium).compactMap { $0.model?.mesh }
        for enabled in [false, true, false, true] {
            otherStadium.isEnabled = enabled
            XCTAssertTrue(zip(expectedMeshes, allModels(in: otherStadium)).allSatisfy { $0 === $1.model?.mesh })
        }
    }

    private func allModels(in entity: Entity) -> [ModelEntity] {
        allEntities(in: entity).compactMap { $0 as? ModelEntity }
    }

    private func allEntities(in entity: Entity) -> [Entity] {
        [entity] + entity.children.flatMap { allEntities(in: $0) }
    }
}
