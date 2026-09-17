import RealityKit

/// Collision-only proxies for the original Blender strategy pitch goals.
/// Net panels are damped solid contact surfaces, not a cloth simulation.
@MainActor
enum ReplayNativeBallPhysicsGoals {
    static func install(in root: Entity, ballGroup: CollisionGroup, obstacleGroup: CollisionGroup) {
        let frameMaterial = PhysicsMaterialResource.generate(staticFriction: 0.25, dynamicFriction: 0.20,
                                                            restitution: 0.62)
        let netMaterial = PhysicsMaterialResource.generate(staticFriction: 0.95, dynamicFriction: 0.90,
                                                          restitution: 0.04)
        func box(name: String, size: SIMD3<Float>, position: SIMD3<Float>, material: PhysicsMaterialResource) {
            let entity = ModelEntity()
            entity.name = name
            let shape = ShapeResource.generateBox(size: size)
            entity.position = position
            entity.components.set(CollisionComponent(shapes: [shape], mode: .default,
                                                    filter: .init(group: obstacleGroup, mask: ballGroup)))
            entity.components.set(PhysicsBodyComponent(shapes: [shape], mass: 1,
                                                       material: material, mode: .static))
            root.addChild(entity)
        }
        for sign: Float in [-1, 1] {
            let prefix = sign > 0 ? "native-north-goal" : "native-south-goal"
            let goalZ = sign * 52.5
            let middleZ = sign * 53.6
            let backZ = sign * 54.7
            // Blender cylinders have .06 m radius, .12 m diameter. Boxes are
            // a deliberately conservative low-cost collision approximation.
            for x: Float in [-3.72, 3.72] {
                box(name: "\(prefix)-post-\(x)", size: [0.12, 2.50, 0.12],
                    position: [x, 1.25, goalZ], material: frameMaterial)
            }
            box(name: "\(prefix)-bar", size: [7.56, 0.12, 0.12],
                position: [0, 2.50, goalZ], material: frameMaterial)
            box(name: "\(prefix)-back-net", size: [7.36, 2.28, 0.035],
                position: [0, 1.20, backZ], material: netMaterial)
            for x: Float in [-3.68, 3.68] {
                box(name: "\(prefix)-side-net-\(x)", size: [0.035, 2.28, 2.20],
                    position: [x, 1.20, middleZ], material: netMaterial)
            }
            // Native scene uses a slightly sloping top net. The average plane
            // is conservative and bounded; no moving fabric is implied.
            box(name: "\(prefix)-top-net", size: [7.36, 0.035, 2.20],
                position: [0, 2.40, middleZ], material: netMaterial)
        }
    }
}
