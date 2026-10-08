import SwiftUI

/// The third point is pitch-relative XYZ; the pad edits X/Z, height edits Y.
/// A pad drag is one cancellable Store transaction, not an Undo per sample.
struct AnnotationArcPointEditor: View {
    @Environment(ReplayStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let markID: UUID
    let color: Color
    @State private var session: Session?
    @GestureState private var dragging = false

    private struct Session {
        let token: UUID
        let mark: CoachMark
        let origin: SIMD3<Float>
    }

    private var displayedMark: CoachMark? {
        guard let mark = store.marks.first(where: { $0.id == markID && $0.kind == .arc }) else { return nil }
        let pose = mark.sampled(at: store.playhead)
        let geometry = store.presentedCoachMarkGeometry(mark, at: store.playhead)
        return CoachMark(id: mark.id, kind: .arc, start: geometry.start, end: geometry.end,
            startElevation: pose.startElevation, endElevation: pose.endElevation,
            curve: store.editableCoachMarkCurve(mark, at: store.playhead),
            label: mark.label, revealTime: mark.revealTime)
    }

    private var enabled: Bool {
        store.pendingAnnotationTimingEditID == nil && (session.map {
            store.isCoachMarkCurvePreviewOwner(id: markID, gestureID: $0.token)
        } ?? store.canChangePlaybackView)
    }

    var body: some View {
        if let mark = displayedMark {
            let point = mark.resolvedCurve.controlPoint(for: mark)
            let layout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Third point", systemImage: "move.3d").font(.headline).foregroundStyle(color)
                    Text("Pinch CURVE and move in 3D").font(.caption).foregroundStyle(.secondary)
                    Text("X \(metres(point.x)) · Z \(metres(point.z))").font(.caption.monospacedDigit())
                }.frame(maxWidth: 240, alignment: .leading)
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(color.opacity(0.1))
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").foregroundStyle(color)
                }
                .frame(width: 100, height: 100)
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { preview($0.translation) }
                    .onEnded {
                        preview($0.translation)
                        if let session { _ = store.commitCoachMarkCurvePreview(id: markID, gestureID: session.token) }
                        session = nil
                    })
                .allowsHitTesting(enabled)
                .opacity(enabled ? 1 : 0.4)
                .accessibilityLabel("Move the third arc point across the pitch")
                .accessibilityAction(named: "Left") { nudge([-0.25, 0, 0]) }
                .accessibilityAction(named: "Right") { nudge([0.25, 0, 0]) }
                .accessibilityAction(named: "Forward") { nudge([0, 0, -0.25]) }
                .accessibilityAction(named: "Back") { nudge([0, 0, 0.25]) }
                VStack(spacing: 8) {
                    Text("Height \(metres(point.y)) m").font(.caption.monospacedDigit())
                    HStack {
                        Button { nudge([0, -0.25, 0]) } label: { Image(systemName: "arrow.down").frame(minWidth: 48, minHeight: 48) }
                            .accessibilityLabel("Lower third arc point")
                        Button { nudge([0, 0.25, 0]) } label: { Image(systemName: "arrow.up").frame(minWidth: 48, minHeight: 48) }
                            .accessibilityLabel("Raise third arc point")
                    }.buttonStyle(.bordered).tint(color).disabled(!enabled || session != nil)
                }
            }
            .onDisappear { cancel() }
            .onChange(of: store.selectedScenarioID) { _, _ in cancel() }
            .onChange(of: enabled) { _, canEdit in
                if !canEdit { cancel() }
            }
            .onChange(of: dragging) { _, active in
                guard !active, let token = session?.token else { return }
                Task { @MainActor in
                    await Task.yield()
                    if session?.token == token, !dragging { cancel() }
                }
            }
        }
    }

    private func preview(_ translation: CGSize) {
        guard enabled, translation.width.isFinite, translation.height.isFinite,
              let mark = displayedMark else { return }
        let active = session ?? Session(token: UUID(), mark: mark,
            origin: mark.resolvedCurve.controlPoint(for: mark))
        let x = min(max(Float(translation.width) / 24, -12), 12)
        let z = min(max(Float(translation.height) / 24, -12), 12)
        let point = bounded(active.origin + SIMD3<Float>(x, 0, z))
        let curve = active.mark.resolvedCurve.settingControlPoint(point, for: active.mark)
        if store.previewCoachMarkCurve(id: markID, gestureID: active.token, curve: curve) { session = active }
        else { cancel() }
    }

    private func nudge(_ delta: SIMD3<Float>) {
        guard enabled, session == nil, let mark = displayedMark else { return }
        _ = store.updateCoachMarkArcControlPoint(id: markID,
            point: bounded(mark.resolvedCurve.controlPoint(for: mark) + delta))
    }

    private func cancel() {
        if let session { _ = store.cancelCoachMarkCurvePreview(id: markID, gestureID: session.token) }
        session = nil
    }

    private func bounded(_ p: SIMD3<Float>) -> SIMD3<Float> {
        [min(max(p.x, -34), 34), min(max(p.y, 0), 12), min(max(p.z, -52.5), 52.5)]
    }
    private func metres(_ v: Float) -> String { v.formatted(.number.precision(.fractionLength(1))) }
}
