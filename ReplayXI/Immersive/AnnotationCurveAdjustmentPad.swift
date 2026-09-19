import SwiftUI

struct AnnotationCurveAdjustmentPad: View {
    @Environment(ReplayStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let markID: UUID
    let color: Color
    let onCommit: () -> Void
    @State private var controller = AnnotationCurveAdjustmentController()
    @State private var mode: AnnotationCurveAdjustmentController.Mode = .shape
    @State private var fine = false
    @GestureState private var dragIsActive = false

    private var isEnabled: Bool { controller.isEnabled(in: store, markID: markID) }
    private var precision: AnnotationCurveAdjustmentPrecision { .init(fine: fine) }
    private var curve: CoachMarkCurve {
        store.marks.first(where: { $0.id == markID })?.sampled(at: store.playhead).resolvedCurve ?? CoachMarkCurve(bend: 0, lift: 0)
    }
    private var isLimitedByPitch: Bool {
        guard let mark = store.marks.first(where: { $0.id == markID }) else { return false }
        return curve.isLimitedByPitch(for: mark.sampled(at: store.playhead))
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
            Label("3D curve", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
            HStack(spacing: 6) {
                ForEach(AnnotationCurveAdjustmentController.Mode.allCases) { choice in
                    Button { mode = choice } label: {
                        Label(choice.rawValue, systemImage: choice.symbol).font(.title3.weight(.semibold))
                            .frame(minWidth: 52, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .tint(mode == choice ? color : .white.opacity(0.65))
                    .disabled(controller.isActive)
                    .help(choice == .shape ? "Curve amount and angle" : "Bend and lift offsets")
                    .accessibilityLabel(choice == .shape ? "Curve amount and angle" : "Bend and lift offsets")
                    .accessibilityAddTraits(mode == choice ? .isSelected : [])
                }
            }
            Toggle("Fine · 5 cm / 1°", isOn: $fine)
                .toggleStyle(.button).disabled(controller.isActive)
            Text("\(mode.horizontalTitle) ↔\u{FE0E}  \(mode.verticalTitle) ↕\u{FE0E}")
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if isLimitedByPitch {
                Label("Pitch limit", systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Curve clipped to the pitch or floor. Raise the endpoints for a downward arc.")
                    .accessibilityHint("Raise the endpoints for a downward arc, or reduce the curve near the touchline.")
            }
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
                _ = controller.preview(in: store, markID: markID, translation: value.translation, mode: mode, fine: fine)
            }
            .onEnded { value in
                if controller.finish(in: store, markID: markID, translation: value.translation, mode: mode, fine: fine) { onCommit() }
            })
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode == .shape ? "Adjust arc curve amount and angle" : "Adjust arc bend and lift")
        .accessibilityValue(mode == .shape
            ? "Curve \(metres(curve.amount)), angle \(degrees(curve.rollDegrees))"
            : "Bend \(metres(curve.bend)), lift \(metres(curve.lift))")
        .accessibilityHint(isEnabled
            ? precision.padHint(isAngle: mode == .shape)
            : "Finish or cancel the current gesture first")
        .accessibilityAction(named: "Decrease curve") { adjust(mode: .shape, horizontal: -precision.distanceStep, vertical: 0) }
        .accessibilityAction(named: "Increase curve") { adjust(mode: .shape, horizontal: precision.distanceStep, vertical: 0) }
        .accessibilityAction(named: "Rotate arc clockwise") { adjust(mode: .shape, horizontal: 0, vertical: -precision.angleStep) }
        .accessibilityAction(named: "Rotate arc anticlockwise") { adjust(mode: .shape, horizontal: 0, vertical: precision.angleStep) }
        .accessibilityAction(named: "Decrease bend") { nudge(bend: -precision.distanceStep, lift: 0) }
        .accessibilityAction(named: "Increase bend") { nudge(bend: precision.distanceStep, lift: 0) }
        .accessibilityAction(named: "Lower arc") { nudge(bend: 0, lift: -precision.distanceStep) }
        .accessibilityAction(named: "Lift arc") { nudge(bend: 0, lift: precision.distanceStep) }
    }

    private var nudgeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            nudgeRow(title: mode.horizontalTitle,
                value: metres(mode == .shape ? curve.amount : curve.bend), horizontal: precision.distanceStep, vertical: 0)
            nudgeRow(title: mode.verticalTitle,
                value: mode == .shape ? degrees(curve.rollDegrees) : metres(curve.lift),
                horizontal: 0, vertical: precision.verticalStep(isAngle: mode == .shape))
        }
    }

    private func nudgeRow(title: String, value: String, horizontal: Float, vertical: Float) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold))
                Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
            }
            .frame(minWidth: 72, alignment: .leading)
            nudgeButton(title: title, horizontal: -horizontal, vertical: -vertical, symbol: "minus")
            nudgeButton(title: title, horizontal: horizontal, vertical: vertical, symbol: "plus")
        }
    }

    private func nudgeButton(title: String, horizontal: Float, vertical: Float, symbol: String) -> some View {
        Button { adjust(mode: mode, horizontal: horizontal, vertical: vertical) } label: {
            Image(systemName: symbol).font(.headline.weight(.bold))
                .frame(minWidth: 60, minHeight: 60)
        }
        .buttonStyle(.bordered)
        .tint(color)
        .disabled(!controller.canAdjust(in: store, markID: markID, mode: mode,
                                       horizontal: horizontal, vertical: vertical))
        .accessibilityLabel("\(symbol == "minus" ? "Decrease" : "Increase") arc \(title.lowercased())")
        .accessibilityHint(mode == .shape && vertical != 0 ? precision.angleHint : precision.distanceHint)
        .help("\(symbol == "minus" ? "Decrease" : "Increase") \(title.lowercased())")
    }

    private func nudge(bend: Float, lift: Float) {
        adjust(mode: .offset, horizontal: bend, vertical: lift)
    }

    private func adjust(mode: AnnotationCurveAdjustmentController.Mode, horizontal: Float, vertical: Float) {
        if controller.adjust(in: store, markID: markID, mode: mode, horizontal: horizontal, vertical: vertical) {
            onCommit()
        }
    }

    private func metres(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(2))) + " m"
    }

    private func degrees(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "°"
    }
}
