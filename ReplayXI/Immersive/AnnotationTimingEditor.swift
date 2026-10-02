import SwiftUI

/// Draft fields do not pollute Undo or autosave on every slider sample.
struct AnnotationTimingEditor: View {
    @Environment(ReplayStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let markID: UUID
    let color: Color
    var draftSession: AnnotationTimingDraftSession? = nil
    var adjustPose: () -> Void = {}
    var close: () -> Void = {}
    @State private var localSession = AnnotationTimingDraftSession()
    @State private var keyTimeLabels = AnnotationKeyTimeLabels()
    @State private var showsExactTimes = false
    @State private var showsPositionTools = false
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
            HStack(alignment: .top, spacing: 12) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .frame(minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                               minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                }
                .buttonStyle(.bordered)
                .disabled(!store.canChangePlaybackView)
                .accessibilityLabel("Close timing controls")
                .accessibilityHint("Returns to this annotation. Unsaved changes need Apply or Discard.")
                VStack(alignment: .leading, spacing: 4) {
                    Label("Annotation timing", systemImage: "timer").font(.headline).foregroundStyle(color)
                    Text(session.hasUnsavedChanges ? "Unsaved changes · Done saves them" : "Choose when this mark appears")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: finishEditing) {
                    Label("Done", systemImage: "checkmark")
                        .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                }
                .buttonStyle(.borderedProminent).tint(color)
                .disabled(!store.canChangePlaybackView || (session.hasUnsavedChanges && !session.canApply(in: store)))
                .accessibilityHint("Saves timing changes and returns to this annotation")
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    adaptiveRow {
                        Text("Scrub the replay, then set Start and End.")
                            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Label("Playhead \(AnnotationTimestamp.display(store.playhead))", systemImage: "clock")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .accessibilityLabel("Playhead \(AnnotationTimestamp.display(store.playhead))")
                    }
                    windowOverview
                    adaptiveRow {
                        boundaryCard(.start)
                        boundaryCard(.end)
                    }
                    Toggle("Keep to replay end", isOn: draftBinding.throughEnd)
                        .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                        .disabled(!canEdit)
                        .accessibilityHint("The annotation stays visible through the final replay frame")
                    if let error = draft.validationMessage(duration: duration) {
                        Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                    }
                    DisclosureGroup(isExpanded: $showsExactTimes) {
                        VStack(alignment: .leading, spacing: 12) {
                            timeRow("Start", text: draftBinding.startText, fallback: mark?.revealTime ?? 0, field: .inTime)
                            if !draft.throughEnd {
                                timeRow("End", text: draftBinding.endText, fallback: mark?.hideTime ?? duration, field: .outTime)
                            }
                            adaptiveRow {
                                Button("Reset times", action: resetWindow).disabled(!isDirty || !canEdit)
                                    .accessibilityLabel("Reset Start and End changes only")
                                Button("Apply times", action: applyWindow)
                                    .disabled(!canEdit || !isDirty || draft.validationMessage(duration: duration) != nil)
                                    .accessibilityHint("Saves Start and End. Position times stay unchanged.")
                            }.buttonStyle(.bordered)
                            if let mark {
                                adaptiveRow {
                                    Text("Shift all timing").font(.caption)
                                    HStack {
                                        Button("−1s") { shift(mark, by: -1) }.disabled(!canShift(mark, by: -1))
                                            .accessibilityLabel("Move annotation window and all position keys one second earlier")
                                        Button("+1s") { shift(mark, by: 1) }.disabled(!canShift(mark, by: 1))
                                            .accessibilityLabel("Move annotation window and all position keys one second later")
                                    }
                                }.buttonStyle(.bordered)
                            }
                        }.padding(.top, 8)
                    } label: {
                        Label("Fine-tune times", systemImage: "slider.horizontal.3")
                            .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                    }
                    if let mark {
                        if mark.kind != .playerLabel {
                            Divider()
                            DisclosureGroup(isExpanded: $showsPositionTools) {
                                keyframeSection(mark).padding(.top, 12)
                            } label: {
                                Label(mark.hasKeyframes ? "Animate position · \(mark.keyframes?.count ?? 0) \((mark.keyframes?.count ?? 0) == 1 ? "key" : "keys")" : "Animate position",
                                      systemImage: "diamond")
                                    .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                            }
                        }
                        Text("Selected marks stay visible while editing. Close the annotation to check playback.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
            .accessibilityHint("Scroll for fine-tune times and optional position animation")
        }
        .onAppear { beginSession(); refreshKeyTimeLabels(); revealPendingEdits() }
        .onDisappear {
            if draftSession == nil { localSession.releaseOwnership() }
        }
        .onChange(of: markID) { _, _ in
            focusedField = nil; showsExactTimes = false; showsPositionTools = false
            beginSession(); refreshKeyTimeLabels(); revealPendingEdits()
        }
        .onChange(of: draft.throughEnd) { _, throughEnd in
            if throughEnd, focusedField == .outTime { focusedField = nil }
        }
        .onChange(of: mark?.revealTime) { _, _ in refreshCommittedWindow() }
        .onChange(of: mark?.hideTime) { _, _ in refreshCommittedWindow() }
        .onChange(of: positionDraft.selectedTime) { _, _ in revealPendingEdits() }
        .onChange(of: positionDraft.isDirty) { _, _ in revealPendingEdits() }
        .onChange(of: mark?.keyframes?.map(\.time)) { _, times in
            if let selectedTime = positionDraft.selectedTime, !(times ?? []).contains(selectedTime) { positionDraft.clear() }
            keyTimeLabels = AnnotationKeyTimeLabels(times: times ?? [])
        }
    }

    private var windowOverview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.visibleRange(duration: duration).map {
                "Visible \(AnnotationTimestamp.display($0.lowerBound)) – \(AnnotationTimestamp.display($0.upperBound))"
            } ?? "Set a valid Start and End")
                .font(.caption.weight(.semibold)).monospacedDigit()
            GeometryReader { geometry in
                let width = max(0, geometry.size.width)
                let timelineDuration = max(duration, 0.1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12)).frame(height: 8)
                    if let range = draft.visibleRange(duration: duration) {
                        let start = width * range.lowerBound / timelineDuration
                        let end = width * range.upperBound / timelineDuration
                        Capsule().fill(color).frame(width: max(4, end - start), height: 8).offset(x: min(start, max(0, width - 4)))
                    }
                    RoundedRectangle(cornerRadius: 2).fill(.white)
                        .frame(width: 3, height: 20)
                        .offset(x: min(max(0, width * store.playhead / timelineDuration), max(0, width - 3)))
                }.frame(height: 20)
            }
            .frame(height: 20)
            .accessibilityHidden(true)
        }
    }

    private func boundaryCard(_ boundary: AnnotationTimingDraft.Boundary) -> some View {
        let isStart = boundary == .start
        let title = isStart ? "Start" : "End"
        let time = isStart ? draft.start : (draft.throughEnd ? duration : draft.end)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text(time.map { AnnotationTimestamp.display($0) } ?? "—").monospacedDigit()
            }
            adaptiveRow {
                Button { setBoundary(boundary) } label: {
                    Label(isStart ? "Start here" : "End here", systemImage: isStart ? "arrow.right.to.line" : "arrow.left.to.line")
                        .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                }
                .buttonStyle(.borderedProminent).tint(color)
                .disabled(!canEdit || !isValidSeek(store.playhead))
                .accessibilityHint("Sets \(title) to the playhead. Choose Done to save.")
                Button { preview(time) } label: {
                    Label(isStart ? "Go to start" : "Go to end", systemImage: "arrow.forward.to.line")
                        .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                }
                .buttonStyle(.bordered)
                .disabled(!store.canChangePlaybackView || !isValidSeek(time))
                .accessibilityHint("Pauses the replay at this boundary without saving changes")
            }
        }
        .padding(12)
        .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.25)))
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
                Button("Adjust shape", action: openShapeEditor)
                    .disabled(!canEdit || !canLeaveEditor || !mark.canRecordPose(at: store.playhead))
                    .accessibilityHint(mark.keyframeCapacityBlockReason(at: store.playhead)
                        ?? "Edit the annotation's position at the playhead")
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
                .accessibilityHint(keyframeHint(mark))
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
                HStack(spacing: 8) {
                    positionTimeNudge(-0.1, symbol: "minus", label: "Move position time draft 0.1 seconds earlier")
                    Text("0.1s").font(.caption).monospacedDigit()
                    positionTimeNudge(0.1, symbol: "plus", label: "Move position time draft 0.1 seconds later")
                }
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
            if let error = positionDraft.validationMessage(for: mark, duration: duration) {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            } else if !positionDraft.isDirty {
                Text("Move changes the time. Adjust shape edits the current position.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Position time not saved. Choose Move or Reset.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func positionTimeNudge(_ delta: TimeInterval, symbol: String, label: String) -> some View {
        Button {
            guard canEdit, positionDraft.nudge(by: delta, duration: duration) else { return }
            if focusedField == .positionTime { focusedField = nil }
        } label: {
            Image(systemName: symbol)
                .frame(minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                       minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
        }
        .buttonStyle(.bordered)
        .disabled(!canEdit || positionDraft.nudgedTime(by: delta, duration: duration) == nil)
        .accessibilityLabel(label)
        .accessibilityHint("Changes only the draft. Choose Move to save, or Reset to discard.")
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
    private func setBoundary(_ boundary: AnnotationTimingDraft.Boundary) {
        guard canEdit, isValidSeek(store.playhead) else { return }
        store.setPlaying(false)
        _ = draft.setBoundary(boundary, at: store.playhead, duration: duration)
        if focusedField != .positionTime { focusedField = nil }
    }
    private func finishEditing() {
        guard store.canChangePlaybackView else { return }
        if session.hasUnsavedChanges, !session.apply(in: store) { return }
        focusedField = nil
        close()
    }
    private func revealPendingEdits() {
        if draft.start == nil || (!draft.throughEnd && draft.end == nil) { showsExactTimes = true }
        if positionDraft.selectedTime != nil || positionDraft.isDirty { showsPositionTools = true }
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
        guard canEdit, canLeaveEditor, let mark, mark.canRecordPose(at: store.playhead) else { return }
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
        canLeaveEditor && !mark.followsPlayerTracks && (mark.keyframes?.count ?? 0) < CoachMark.maximumKeyframes
            && !(mark.keyframes ?? []).contains { abs($0.time - store.playhead) < CoachMark.keyframeTimeTolerance }
    }
    private func keyframeHint(_ mark: CoachMark) -> String {
        Self.keyframeHint(for: mark, at: store.playhead,
            windowIsDirty: isDirty, positionIsDirty: positionDraft.isDirty)
    }

    static func keyframeHint(for mark: CoachMark, at time: TimeInterval,
                             windowIsDirty: Bool, positionIsDirty: Bool) -> String {
        if positionIsDirty { return "Move or reset this position time before switching." }
        if windowIsDirty { return "Apply or reset times before adjusting shape." }
        if mark.followsPlayerTracks { return "Switch to Fixed before adding position keys." }
        if (mark.keyframes?.count ?? 0) >= CoachMark.maximumKeyframes {
            return "64 keys saved. Adjust an existing position, or delete a key."
        }
        if (mark.keyframes ?? []).contains(where: { abs($0.time - time) < CoachMark.keyframeTimeTolerance }) {
            return "A position is already saved at this time. Adjust shape to update it, or seek to add another."
        }
        if let reason = mark.keyframeCapacityBlockReason(at: time) { return reason }
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
