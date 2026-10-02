import Foundation

/// Both modes enter the same spatial tools. Admission never changes a draft,
/// the selected study, or the playback clock while an interaction owns them.
@MainActor
enum ReplayAnnotationEntryPolicy {
    static func navigationBlockReason(in store: ReplayStore) -> String? {
        if store.hasActiveTimelineScrub { return "Finish the timeline drag first." }
        if store.hasActiveCoachMarkGeometryPreview { return "Finish the annotation adjustment first." }
        if store.pendingAnnotationTimingEditID != nil { return "Apply or discard annotation timing changes first." }
        if store.isDrawing { return "Finish or cancel the current annotation first." }
        if store.triangleLockMode == .place { return "End physical placement first." }
        if store.isRoomPresentationBusy {
            return store.isImmersiveOpen
                ? "Annotation tools are in the open room."
                : "Wait for the room transition to finish."
        }
        return nil
    }

    static func blockReason(in store: ReplayStore) -> String? {
        if let reason = navigationBlockReason(in: store) { return reason }
        if store.localRole != .coach { return "Only the coach can add annotations." }
        return nil
    }
}
