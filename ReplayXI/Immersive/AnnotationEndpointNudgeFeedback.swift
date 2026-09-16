import Foundation

/// Bridges the Store's atomic edit result to visible and assistive feedback.
@MainActor
enum AnnotationEndpointNudgeFeedback {
    static func apply(
        in store: ReplayStore,
        id: UUID,
        endpoint: CoachMarkEndpoint,
        by requestedDelta: PitchPoint
    ) -> PitchPoint? {
        let sampleTime = store.playhead
        let before = store.marks.first { $0.id == id }.map {
            store.presentedCoachMarkGeometry($0, at: sampleTime)
        }
        guard store.nudgeCoachMarkEndpoint(
            id: id, endpoint: endpoint, by: requestedDelta
        ) else { return nil }
        guard let before, let updated = store.marks.first(where: { $0.id == id }) else { return nil }
        // Read live, presented endpoints: tracked marks may have moved since
        // authoring, and a permitted step may stop partway at a touchline.
        let after = store.presentedCoachMarkGeometry(updated, at: sampleTime)
        let start = endpoint == .start ? before.start : before.end
        let end = endpoint == .start ? after.start : after.end
        return PitchPoint(x: end.x - start.x, z: end.z - start.z)
    }
}
