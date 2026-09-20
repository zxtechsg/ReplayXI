import SwiftUI

/// ID-bound routes keep delayed callbacks and selection observers from moving
/// an action onto another mark. Domain eligibility remains owned by the Store.
enum PlaybackAnnotationActionsRoute {
    static func accessibilityHint(isSpatial: Bool, isAuthored: Bool) -> String {
        if !isSpatial { return "Opens Erase for this label" }
        return isAuthored ? "Opens Copy pose here. The match annotation stays unchanged."
            : "Opens Copy pose here and Erase"
    }

    static func panelAfterSelectionChange(_ panel: PlaybackInlinePanel?, selectedID: UUID?) -> PlaybackInlinePanel? {
        if let selectedID, panel?.annotationID == selectedID { return panel }
        return selectedID == nil && panel == .annotationEdit ? panel : nil
    }

    static func keepsSelectedInsertion(insertedID: UUID, selectedID: UUID?, panel: PlaybackInlinePanel?) -> Bool {
        selectedID == insertedID && panel?.annotationID == insertedID
    }

    static func permitsAction(id: UUID, selectedID: UUID?, panel: PlaybackInlinePanel?, timingIsDirty: Bool) -> Bool {
        !timingIsDirty && selectedID == id && panel == .annotationActions(id)
    }

    static func destination(id: UUID, from route: AnnotationTimingDeckRoute) -> AnnotationTimingDeckRoute {
        var result = route
        result.selection = id
        result.panel = PlaybackInlinePanel.toggled(current: route.panel, candidate: .annotationActions(id))
        result.showsTools = false
        result.showsPlayers = false
        result.showsEvents = false
        result.showsDecisions = false
        result.showsDrawing = false
        result.showsClear = false
        result.showsAnnotations = true
        return result
    }

    @MainActor
    static func copyPose(id: UUID, selectedID: UUID?, panel: PlaybackInlinePanel?, timingIsDirty: Bool,
                         in store: ReplayStore, onFailure: (String) -> Void = { _ in }) -> CoachMark? {
        guard permitsAction(id: id, selectedID: selectedID, panel: panel, timingIsDirty: timingIsDirty) else { return nil }
        guard let copied = store.copyCoachMarkPose(id: id) else {
            onFailure(store.statusMessage)
            return nil
        }
        return copied
    }
}

struct AnnotationActionsFeedback: Equatable {
    let sourceID: UUID
    let message: String
}

/// Real in-deck submenu; isolated for native text/layout captures.
struct AnnotationActionsShelf: View {
    static let copyHint = "Creates a fixed copy at the current time, without tracking or position keys."
    let color: Color
    let isAuthored: Bool
    let showsCopy: Bool
    let canCopy: Bool
    let canErase: Bool
    let canClose: Bool
    var feedback: String? = nil
    let close: () -> Void
    let copy: () -> Void
    let erase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .frame(minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                               minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                }
                .buttonStyle(.bordered)
                .disabled(!canClose)
                .accessibilityLabel("Close annotation actions")
                Text("Annotation actions").font(.headline).foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isAuthored { StatusPill(text: "MATCH", systemImage: "lock.fill", color: .secondary) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 12) { actions }
            }
            if showsCopy {
                if let feedback {
                    Label(feedback, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(Self.copyHint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actions: some View {
        if showsCopy {
            Button(action: copy) {
                Label("Copy pose here", systemImage: "plus.square.on.square")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
            }
            .buttonStyle(.borderedProminent).tint(color)
            .disabled(!canCopy)
            .accessibilityHint(Self.copyHint)
        }
        if !isAuthored {
            Button(role: .destructive, action: erase) {
                Label("Erase", systemImage: "eraser.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
            }
            .buttonStyle(.bordered)
            .disabled(!canErase)
            .accessibilityLabel("Delete annotation")
            .accessibilityHint("Erases this annotation and opens Undo")
        }
    }
}
