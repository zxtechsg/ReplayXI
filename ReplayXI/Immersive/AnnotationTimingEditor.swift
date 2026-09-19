import SwiftUI

/// Draft fields do not pollute Undo or autosave on every slider sample.
struct AnnotationTimingEditor: View {
    @Environment(ReplayStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let markID: UUID
    let color: Color
    var draftSession: AnnotationTimingDraftSession? = nil
    var adjustPose: () -> Void = {}
    @State private var localSession = AnnotationTimingDraftSession()
    @State private var keyTimeLabels = AnnotationKeyTimeLabels()
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case inTime, outTime, positionTime }
    @State private var measuredContentHeight: CGFloat?
    @ScaledMetric(relativeTo: .body) private var fieldWidth = 130.0

    private var mark: CoachMark? { store.marks.first { $0.id == markID } }
    private var session: AnnotationTimingDraftSession { draftSession ?? localSession }
    private var draft: AnnotationTimingDraft {
        get { session.window }
        nonmutating set { session.window = newValue }
    }
    private var positionDraft: AnnotationPositionTimeDraft {
        get { session.position }
        nonmutating set { session.position = newValue }
    }
    private var draftBinding: Binding<AnnotationTimingDraft> {
        Binding(get: { draft }, set: { draft = $0 })
    }
    private var positionBinding: Binding<AnnotationPositionTimeDraft> {
        Binding(get: { positionDraft }, set: { positionDraft = $0 })
    }
    private var duration: Double { store.selectedScenario.duration }
    private var canEdit: Bool {
        store.canChangePlaybackView && store.localRole == .coach && store.triangleLockMode != .place
            && (store.pendingAnnotationTimingEditID == nil || store.pendingAnnotationTimingEditID == markID)
            && mark != nil && !store.selectedScenario.coachMarks.contains { $0.id == markID }
    }
    private var isDirty: Bool { mark.map { draft.differs(from: $0) } ?? false }
    private var canLeaveEditor: Bool {
        AnnotationTimingEditPolicy.canLeaveEditor(windowIsDirty: isDirty, positionIsDirty: positionDraft.isDirty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            adaptiveRow {
                Label("In / Out", systemImage: "timer").font(.headline).foregroundStyle(color)
                Toggle("To end", isOn: draftBinding.throughEnd).toggleStyle(.button).disabled(!canEdit)
                    .accessibilityHint("Keep the annotation visible through the final replay frame")
                Button("Reset In/Out", action: resetWindow).disabled(!isDirty || !canEdit)
                    .accessibilityLabel("Reset In and Out changes only")
                Button("Apply In/Out", action: applyWindow)
                    .buttonStyle(.borderedProminent).tint(color)
                    .disabled(!canEdit || !isDirty || draft.validationMessage(duration: duration) != nil)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    timeRow("In", text: draftBinding.startText, fallback: mark?.revealTime ?? 0, field: .inTime)
                    if !draft.throughEnd {
                        timeRow("Out", text: draftBinding.endText, fallback: mark?.hideTime ?? duration, field: .outTime)
                    }
                    if let error = draft.validationMessage(duration: duration) {
                        Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                    } else if isDirty {
                        Text("In/Out not applied. Saved position times stay unchanged.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let mark {
                        adaptiveRow {
                            Text("Shift all timing").font(.caption)
                            HStack {
                                Button("−1s") { shift(mark, by: -1) }.disabled(!canShift(mark, by: -1))
                                    .accessibilityLabel("Move annotation window and all position keys one second earlier")
                                Button("+1s") { shift(mark, by: 1) }.disabled(!canShift(mark, by: 1))
                                    .accessibilityLabel("Move annotation window and all position keys one second later")
                            }
                            Label(AnnotationTimingEditPolicy.visibilityLabel(for: mark, at: store.playhead),
                                  systemImage: mark.isVisible(at: store.playhead) ? "eye" : "eye.slash")
                                .font(.caption).foregroundStyle(.secondary)
                        }.buttonStyle(.bordered)
                        if !mark.isVisible(at: store.playhead) {
                            Text(AnnotationTimingEditPolicy.outsideWindowHint)
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if mark.kind != .playerLabel {
                            Divider()
                            keyframeSection(mark)
                        }
                    }
                }
                .padding(.trailing, 8)
                // Measure intrinsic content, not the constrained scroll viewport:
                // changes to the viewport cannot feed back into this height.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    ceil(geometry.size.height)
                } action: { height in
                    if height.isFinite, height > 0 { measuredContentHeight = height }
                }
            }
            .frame(height: AnnotationTimingPanelLayout.height(contentHeight: measuredContentHeight,
                usesAccessibilityText: dynamicTypeSize.isAccessibilitySize))
            .scrollIndicators(.visible)
            .accessibilityHint("Scroll for position keys and key timing controls")
        }
        .onAppear { beginSession(); refreshKeyTimeLabels() }
        .onDisappear {
            if draftSession == nil { localSession.releaseOwnership() }
        }
        .onChange(of: markID) { _, _ in
            focusedField = nil; beginSession(); refreshKeyTimeLabels()
        }
        .onChange(of: draft.throughEnd) { _, throughEnd in
            if throughEnd, focusedField == .outTime { focusedField = nil }
        }
        .onChange(of: mark?.revealTime) { _, _ in refreshCommittedWindow() }
        .onChange(of: mark?.hideTime) { _, _ in refreshCommittedWindow() }
        .onChange(of: mark?.keyframes?.map(\.time)) { _, times in
            if let selectedTime = positionDraft.selectedTime, !(times ?? []).contains(selectedTime) { positionDraft.clear() }
            keyTimeLabels = AnnotationKeyTimeLabels(times: times ?? [])
        }
    }

    private func timeRow(_ title: String, text: Binding<String>, fallback: Double, field: Field) -> some View {
        adaptiveRow {
            Text(title).font(.subheadline.weight(.bold)).frame(minWidth: 36, alignment: .leading)
            TextField("Seconds or m:ss", text: text)
                .textFieldStyle(.roundedBorder).frame(width: fieldWidth).monospacedDigit()
                .accessibilityLabel("Exact annotation \(title) time")
                .accessibilityHint("Enter seconds or a minutes and seconds timestamp")
                .focused($focusedField, equals: field)
                .submitLabel(.done)
                .onSubmit { applyWindow() }
            HStack {
                Button("Now") { text.wrappedValue = AnnotationTimestamp.editable(store.playhead) }
                    .accessibilityLabel("Set \(title) to playhead")
                Button { preview(AnnotationTimestamp.parse(text.wrappedValue)) } label: {
                    Image(systemName: "forward.frame").frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Preview annotation \(title) time")
                    .disabled(!isValidSeek(AnnotationTimestamp.parse(text.wrappedValue)))
            }
            Slider(value: sliderBinding(text, fallback: fallback), in: 0...max(duration, 0.1), step: 0.1)
                .tint(color).frame(minWidth: 140)
                .accessibilityLabel("Annotation \(title) time")
                .accessibilityValue(AnnotationTimestamp.parse(text.wrappedValue).map { AnnotationTimestamp.display($0) } ?? "Invalid time")
        }.disabled(!canEdit)
    }

    private func keyframeSection(_ mark: CoachMark) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            adaptiveRow {
                Label("Saved positions", systemImage: "diamond").font(.headline)
                Button("Adjust shape", action: openShapeEditor).disabled(!canEdit || !canLeaveEditor)
                if mark.hasKeyframes {
                    Button {
                        if store.freezeCoachMarkKeyframes(id: markID) { positionDraft.clear() }
                    } label: { Label("Freeze here", systemImage: "pause.circle") }
                        .accessibilityHint("Keep the current pose and remove its movement keys. Undo can restore them.")
                        .disabled(!canEdit || positionDraft.isDirty)
                }
                Button {
                    if store.captureCoachMarkKeyframe(id: markID) { selectKey(at: store.playhead, seek: false) }
                } label: { Label("Add here", systemImage: "plus.diamond") }
                .disabled(!canEdit || !canCapture(mark))
                .accessibilityLabel("Add position key at \(AnnotationTimestamp.display(store.playhead))")
                Text(AnnotationTimestamp.display(store.playhead)).monospacedDigit()
                    .accessibilityLabel("Playhead \(AnnotationTimestamp.display(store.playhead))")
            }
            Text(keyframeHint(mark)).font(.caption).foregroundStyle(.secondary)
            if mark.hasKeyframes {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(mark.keyframes ?? [], id: \.time) { key in
                            Button { selectKey(at: key.time, seek: true) } label: {
                                Label(keyTimeLabels.label(at: key.time), systemImage: positionDraft.selectedTime == key.time ? "diamond.fill" : "diamond")
                                    .frame(minHeight: 44)
                            }
                            .tint(positionDraft.selectedTime == key.time ? color : Color.secondary)
                            .accessibilityLabel("Select and preview position key at \(keyTimeLabels.label(at: key.time))")
                            .accessibilityAddTraits(positionDraft.selectedTime == key.time ? [.isSelected] : [])
                        }
                    }.buttonStyle(.bordered)
                }.disabled(!store.canChangePlaybackView || positionDraft.isDirty)
            }
            if let selectedTime = positionDraft.selectedTime, mark.keyframes?.contains(where: { $0.time == selectedTime }) == true {
                selectedKeyEditor(mark, time: selectedTime)
            }
        }
    }

    private func selectedKeyEditor(_ mark: CoachMark, time: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            adaptiveRow {
                Text("Position time").font(.caption)
                TextField("Seconds or m:ss", text: positionBinding.text)
                    .textFieldStyle(.roundedBorder).frame(width: fieldWidth).monospacedDigit()
                    .accessibilityLabel("Selected position key time")
                    .focused($focusedField, equals: .positionTime)
                    .submitLabel(.done)
                    .onSubmit { submitPositionTime(mark, from: time) }
                Button("Reset") { resetPositionTime() }
                    .disabled(!positionDraft.isDirty)
                    .accessibilityLabel("Reset selected position time only")
                Button("Move") { moveKey(mark, from: time, to: AnnotationTimestamp.parse(positionDraft.text)) }
                    .disabled(!canMoveKey(mark, from: time, to: AnnotationTimestamp.parse(positionDraft.text)))
                    .accessibilityHint("Change this key's time without changing its position")
                Button("To playhead") { moveKey(mark, from: time, to: store.playhead) }
                    .disabled(positionDraft.isDirty || !canMoveKey(mark, from: time, to: store.playhead))
                Button(role: .destructive) {
                    if store.removeCoachMarkKeyframe(id: markID, at: time) { positionDraft.clear() }
                } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Delete position key at \(keyTimeLabels.label(at: time))")
                    .disabled(positionDraft.isDirty)
            }.disabled(!canEdit)
            if let destination = AnnotationTimestamp.parse(positionDraft.text), abs(destination - time) < CoachMark.keyframeTimeTolerance {
                Text("Move changes the time. Adjust shape edits the current position.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !canMoveKey(mark, from: time, to: AnnotationTimestamp.parse(positionDraft.text)) {
                Text("Choose an unused time inside this replay.").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func adaptiveRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12, content: content)
            VStack(alignment: .leading, spacing: 8, content: content)
        }
    }

    private func sliderBinding(_ text: Binding<String>, fallback: Double) -> Binding<Double> {
        Binding(get: { min(max(AnnotationTimestamp.parse(text.wrappedValue) ?? fallback, 0), max(duration, 0.1)) },
                set: { text.wrappedValue = AnnotationTimestamp.editable($0) })
    }
    private func isValidSeek(_ time: TimeInterval?) -> Bool {
        time.map { $0.isFinite && (0...duration).contains($0) } ?? false
    }
    private func preview(_ time: TimeInterval?) {
        guard let time, isValidSeek(time) else { return }
        store.setPlaying(false); store.seek(to: time)
    }
    private func reload() {
        guard let mark else { return }
        session.resetWindow(mark: mark, duration: duration)
    }
    private func beginSession() {
        guard let mark else { return }
        session.begin(mark: mark, scenarioID: store.selectedScenarioID, duration: duration, store: store)
    }
    private func refreshCommittedWindow() {
        guard let mark else { return }
        session.refreshWindow(mark: mark, duration: duration)
    }
    private func resetWindow() {
        reload()
        if focusedField != .positionTime { focusedField = nil }
    }
    private func refreshKeyTimeLabels() {
        keyTimeLabels = AnnotationKeyTimeLabels(times: mark?.keyframes?.map(\.time) ?? [])
    }
    private func applyWindow() {
        guard canEdit, draft.validationMessage(duration: duration) == nil, let start = draft.start else { return }
        guard isDirty else {
            if focusedField != .positionTime { focusedField = nil }
            return
        }
        if store.setCoachMarkWindow(id: markID, start: start, end: draft.throughEnd ? nil : draft.end) {
            resetWindow()
        }
    }
    private func openShapeEditor() {
        guard canEdit, canLeaveEditor else { return }
        focusedField = nil
        adjustPose()
    }
    private func canShift(_ mark: CoachMark, by delta: Double) -> Bool {
        canEdit && canLeaveEditor && CoachMarkTimingPolicy.windowFits(revealTime: mark.revealTime + delta,
            displayDuration: mark.hideTime.map { $0 - mark.revealTime }, replayDuration: duration)
            && mark.canShiftKeyframes(by: delta, duration: duration)
    }
    private func shift(_ mark: CoachMark, by delta: Double) {
        _ = store.retimeCoachMark(id: markID, to: mark.revealTime + delta)
    }
    private func canCapture(_ mark: CoachMark) -> Bool {
        !positionDraft.isDirty && !mark.followsPlayerTracks && (mark.keyframes?.count ?? 0) < CoachMark.maximumKeyframes
            && !(mark.keyframes ?? []).contains { abs($0.time - store.playhead) < CoachMark.keyframeTimeTolerance }
    }
    private func keyframeHint(_ mark: CoachMark) -> String {
        if positionDraft.isDirty { return "Move or reset this position time before switching." }
        if isDirty { return "Apply or reset In/Out before adjusting shape." }
        if mark.followsPlayerTracks { return "Switch to Fixed before adding position keys." }
        if (mark.keyframes?.count ?? 0) >= CoachMark.maximumKeyframes { return "64 keys saved. Select a key to move or delete it." }
        if !mark.hasKeyframes { return "Add here, seek, then adjust the shape to animate it." }
        return "Tap a timestamp to preview or move it. Seek + Adjust shape saves a new position."
    }
    private func selectKey(at time: TimeInterval, seek: Bool) {
        guard positionDraft.select(time) else { return }
        if focusedField == .positionTime { focusedField = nil }
        if seek { preview(time) }
    }
    private func resetPositionTime() {
        positionDraft.reset()
        if focusedField == .positionTime { focusedField = nil }
    }
    private func submitPositionTime(_ mark: CoachMark, from time: TimeInterval) {
        guard canEdit else { return }
        guard positionDraft.isDirty else { focusedField = nil; return }
        moveKey(mark, from: time, to: AnnotationTimestamp.parse(positionDraft.text))
    }
    private func canMoveKey(_ mark: CoachMark, from time: TimeInterval, to destination: TimeInterval?) -> Bool {
        guard canEdit, let destination else { return false }
        return mark.canRetimeKeyframe(from: time, to: destination, duration: duration)
    }
    private func moveKey(_ mark: CoachMark, from time: TimeInterval, to destination: TimeInterval?) {
        guard let destination, canMoveKey(mark, from: time, to: destination),
              store.retimeCoachMarkKeyframe(id: markID, from: time, to: destination) else { return }
        positionDraft.acceptCommittedTime(destination)
        if focusedField == .positionTime { focusedField = nil }
        preview(destination)
    }
}
