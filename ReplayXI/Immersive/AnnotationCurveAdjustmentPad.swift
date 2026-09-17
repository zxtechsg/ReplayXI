import SwiftUI

struct AnnotationCurveAdjustmentPad: View {
    @Environment(ReplayStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let markID: UUID
    let color: Color
    let onCommit: () -> Void
    @State private var controller = AnnotationCurveAdjustmentController()
    @GestureState private var dragIsActive = false

    private var isEnabled: Bool { controller.isEnabled(in: store, markID: markID) }
    private var curve: CoachMarkCurve {
        store.marks.first(where: { $0.id == markID })?.resolvedCurve ?? CoachMarkCurve(bend: 0, lift: 0)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    instructions
                    HStack(spacing: 20) { pad; nudgeControls; Spacer(minLength: 0) }
                }
            } else {
                HStack(spacing: 20) {
                    instructions
                    pad
                    nudgeControls
                    Spacer(minLength: 0)
                }
            }
        }
        .onDisappear { controller.cancel(in: store) }
        .onChange(of: markID) { _, _ in controller.cancel(in: store) }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled, controller.isActive {
                controller.cancel(in: store, rejectCurrentGesture: true)
            }
        }
        .onChange(of: dragIsActive) { wasActive, active in
            if wasActive, !active { controller.cancel(in: store) }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Curve", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
            Text("Sideways: bend. Up: lift.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bend \(metres(curve.bend)) · Lift \(metres(curve.lift))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 24).stroke(color.opacity(0.4), lineWidth: 1.5)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 88)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 88, height: 1)
            Image(systemName: "arrow.up").offset(y: -48)
            Image(systemName: "arrow.down").offset(y: 48)
            Image(systemName: "arrow.left").offset(x: -48)
            Image(systemName: "arrow.right").offset(x: 48)
            Circle().fill(color.gradient).frame(width: 44, height: 44)
                .offset(controller.sample.knobOffset)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white.opacity(0.65))
        .frame(width: 140, height: 140)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .gesture(DragGesture(minimumDistance: 0)
            .updating($dragIsActive) { _, active, _ in active = true }
            .onChanged { value in
                _ = controller.preview(in: store, markID: markID, translation: value.translation)
            }
            .onEnded { value in
                if controller.finish(in: store, markID: markID, translation: value.translation) { onCommit() }
            })
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Adjust arc bend and lift")
        .accessibilityValue("Bend \(metres(curve.bend)), lift \(metres(curve.lift))")
        .accessibilityHint(isEnabled
            ? "Drag sideways to bend the arc; drag up to lift it. Quarter-metre steps."
            : "Finish or cancel the current gesture first")
        .accessibilityAction(named: "Decrease bend") { nudge(bend: -0.25, lift: 0) }
        .accessibilityAction(named: "Increase bend") { nudge(bend: 0.25, lift: 0) }
        .accessibilityAction(named: "Lower arc") { nudge(bend: 0, lift: -0.25) }
        .accessibilityAction(named: "Lift arc") { nudge(bend: 0, lift: 0.25) }
    }

    private var nudgeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            nudgeRow(title: "Bend", bend: 0.25, lift: 0)
            nudgeRow(title: "Lift", bend: 0, lift: 0.25)
        }
    }

    private func nudgeRow(title: String, bend: Float, lift: Float) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
                .frame(minWidth: 64, alignment: .leading)
            nudgeButton(title: title, bend: -bend, lift: -lift, symbol: "minus")
            nudgeButton(title: title, bend: bend, lift: lift, symbol: "plus")
        }
    }

    private func nudgeButton(title: String, bend: Float, lift: Float, symbol: String) -> some View {
        Button { nudge(bend: bend, lift: lift) } label: {
            Image(systemName: symbol).font(.headline.weight(.bold))
                .frame(minWidth: 60, minHeight: 60)
        }
        .buttonStyle(.bordered)
        .tint(color)
        .disabled(!controller.canNudge(in: store, markID: markID, bend: bend, lift: lift))
        .accessibilityLabel("\(symbol == "minus" ? "Decrease" : "Increase") arc \(title.lowercased())")
        .accessibilityHint("Quarter-metre step")
    }

    private func nudge(bend: Float, lift: Float) {
        if controller.nudge(in: store, markID: markID, bend: bend, lift: lift) { onCommit() }
    }

    private func metres(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(2))) + " m"
    }
}
