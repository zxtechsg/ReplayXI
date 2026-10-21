import RealityKit

/// Render callbacks and tracking tasks share one reference. Replacing the
/// entity must not mutate SwiftUI State from RealityView's synchronous update.
@MainActor
final class ReplayMatchSceneReference {
    var root: Entity?
}
