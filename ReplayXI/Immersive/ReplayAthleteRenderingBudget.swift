import Foundation

enum ReplayAthleteRenderingSpace: Sendable {
    case shared
    case full

    /// Apple's published RealityKit targets are whole-scene targets, not a
    /// licence for the player system to consume the entire envelope.
    var appleGuidance: ReplayAthleteSceneLimits {
        switch self {
        case .shared:
            ReplayAthleteSceneLimits(
                maximumDrawCalls: 250,
                maximumVertices: 250_000,
                maximumTriangles: 250_000
            )
        case .full:
            ReplayAthleteSceneLimits(
                maximumDrawCalls: 500,
                maximumVertices: 500_000,
                maximumTriangles: 500_000
            )
        }
    }
}

struct ReplayAthleteSceneLimits: Equatable, Sendable {
    let maximumDrawCalls: Int
    let maximumVertices: Int
    let maximumTriangles: Int
}

/// Conservative athlete-only upper bound. A ModelEntity can produce one or
/// more GPU draws depending on materials and renderer batching, so the
/// `drawCalls` field deliberately assumes one draw per single-material model.
/// The complete pitch, labels and annotations must be measured separately in
/// RealityKit Trace; this type never claims that athlete headroom is scene fit.
struct ReplayAthleteSceneMetrics: Equatable, Sendable {
    var drawCalls: Int = 0
    var vertices: Int = 0
    var triangles: Int = 0

    mutating func include(_ instance: ReplayAthleteBuildMetrics) {
        drawCalls += instance.modelEntities
        vertices += instance.verticesPerInstance
        triangles += instance.trianglesPerInstance
    }

    mutating func include(lod: ReplayAthleteLOD, count: Int) {
        let boundedCount = max(count, 0)
        drawCalls += lod.budget.maximumModelEntities * boundedCount
        vertices += lod.budget.maximumVerticesPerInstance * boundedCount
        triangles += lod.budget.maximumTrianglesPerInstance * boundedCount
    }

    func fitsWithin(_ limits: ReplayAthleteSceneLimits) -> Bool {
        drawCalls <= limits.maximumDrawCalls
            && vertices <= limits.maximumVertices
            && triangles <= limits.maximumTriangles
    }

    func remainingWithin(_ limits: ReplayAthleteSceneLimits) -> ReplayAthleteSceneMetrics {
        ReplayAthleteSceneMetrics(
            drawCalls: max(limits.maximumDrawCalls - drawCalls, 0),
            vertices: max(limits.maximumVertices - vertices, 0),
            triangles: max(limits.maximumTriangles - triangles, 0)
        )
    }
}

struct ReplayAthleteDeploymentPlan: Equatable, Sendable {
    let nearPlayers: Int
    let midPlayers: Int
    let farPlayers: Int

    var playerCount: Int { nearPlayers + midPlayers + farPlayers }

    var athleteOnlyUpperBound: ReplayAthleteSceneMetrics {
        var metrics = ReplayAthleteSceneMetrics()
        metrics.include(lod: .near, count: nearPlayers)
        metrics.include(lod: .mid, count: midPlayers)
        metrics.include(lod: .far, count: farPlayers)
        return metrics
    }

    /// One close subject in Shared Space retains at least 74 conservative draw
    /// slots for the pitch, sparse identity tags and active annotations.
    static let sharedSpaceXI = ReplayAthleteDeploymentPlan(
        nearPlayers: 1,
        midPlayers: 0,
        farPlayers: 21
    )

    /// Full Space can retain four detailed subjects while remaining below half
    /// Apple's whole-scene draw-call target on the conservative athlete bound.
    static let fullSpaceXI = ReplayAthleteDeploymentPlan(
        nearPlayers: 4,
        midPlayers: 0,
        farPlayers: 18
    )
}
