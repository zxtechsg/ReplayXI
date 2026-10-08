import SwiftUI

struct CoachWindow: View {
    @Environment(ReplayXIMacLink.self) private var link
    @State private var deviceID = ""
    @State private var selectedMarkID: UUID?
    @State private var drawKind = "run"
    @State private var drawStart: ReplayXIWirePoint?
    @State private var dragStart: ReplayXIWirePoint?
    @State private var dragEnd: ReplayXIWirePoint?
    @State private var draftTime = 0.0
    @State private var scrubbing = false
    @State private var startHeight = 0.0
    @State private var endHeight = 0.0
    @State private var label = ""
    @State private var showAt = 0.0
    @State private var hideAt = 0.0
    @State private var hasHide = true
    @State private var controlHeight = 0.0
    @State private var saveName = "Coach review"
    @State private var selectedKey = 0.0
    @State private var retimeKey = 0.0
    @State private var labelPlayerID = ""
    @State private var showClearConfirmation = false
    @State private var loadedMarkFingerprint: Data?
    @State private var loadedDraft: InspectorDraft?
    @State private var inspectorConflict = false

    private struct InspectorDraft: Equatable {
        var label: String
        var startHeight: Double
        var endHeight: Double
        var showAt: Double
        var hideAt: Double
        var hasHide: Bool
        var controlHeight: Double
    }

    private var currentDraft: InspectorDraft {
        .init(label: label, startHeight: startHeight, endHeight: endHeight,
            showAt: showAt, hideAt: hideAt, hasHide: hasHide,
            controlHeight: controlHeight)
    }

    private var state: ReplayXIWireState? { link.state }
    private var selectedMark: ReplayXIWireMark? { state?.marks.first { $0.id == selectedMarkID } }
    private var currentDevice: ReplayXIMacLink.Device? { link.devices.first { $0.id == deviceID } }

    var body: some View {
        VStack(spacing: 0) {
            connectionBar
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            if let state {
                HStack(spacing: 0) {
                    VStack(spacing: 10) {
                        playbackBar(state)
                        PitchMap(state: state, selectedMarkID: $selectedMarkID,
                            drawKind: drawKind, drawStart: $drawStart,
                            dragStart: $dragStart, dragEnd: $dragEnd,
                            onPitchClick: pitchClicked, onMove: moveEndpoint,
                            onArcControl: { mark, point in
                                guard state.canEdit, !inspectorConflict else { return }
                                link.send(.init(name: "arcControl", markID: mark.id,
                                    controlPoint: .init(x: point.x, y: Float(controlHeight), z: point.z)))
                            })
                        timeline(state)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    Divider()
                    inspector(state)
                        .frame(width: 330)
                }
            } else {
                ContentUnavailableView("Connect to Replay XI", systemImage: "visionpro",
                    description: Text("Open Replay XI on Vision Pro, then enter its Mac link PIN."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: state?.playhead, initial: true) { _, value in
            if !scrubbing, let value { draftTime = value }
        }
        .onChange(of: selectedMarkID) { _, _ in loadInspector() }
        .onChange(of: state?.scenarioID) { _, _ in
            labelPlayerID = state?.players.first?.id ?? ""
        }
        .onChange(of: state?.revision) { _, _ in
            if let id = selectedMarkID, state?.marks.contains(where: { $0.id == id }) != true {
                selectedMarkID = nil
            } else if let mark = selectedMark,
                      let fingerprint = try? ReplayXIWire.encoder.encode(mark),
                      fingerprint != loadedMarkFingerprint {
                if currentDraft == loadedDraft { loadInspector() }
                else { inspectorConflict = true }
            }
        }
    }

    private var connectionBar: some View {
        HStack(spacing: 12) {
            Text("REPLAY XI / MAC COACH").font(.headline)
            Spacer()
            Text(link.status).font(.caption).foregroundStyle(link.connected ? .green : .secondary)
            if link.connected {
                Button("Disconnect") { link.disconnect() }
            } else {
                Picker("Headset", selection: $deviceID) {
                    Text("Select headset").tag("")
                    ForEach(link.devices) { device in Text(device.name).tag(device.id) }
                }
                .frame(width: 195)
                SecureField("Six digit PIN", text: Bindable(link).pin)
                    .frame(width: 110)
                Button("Pair") {
                    if let currentDevice { link.connect(to: currentDevice) }
                }
                .disabled(currentDevice == nil || link.pin.count != 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func playbackBar(_ state: ReplayXIWireState) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                scenarioPicker(state)
                transportControls(state)
                viewPicker(state)
                povPicker(state)
                speedPicker(state)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    scenarioPicker(state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    transportControls(state)
                    speedPicker(state)
                }
                HStack(spacing: 8) {
                    viewPicker(state)
                    povPicker(state)
                    Spacer(minLength: 0)
                }
            }
        }
        .controlSize(.small)
    }

    private func scenarioPicker(_ state: ReplayXIWireState) -> some View {
        Picker("Scenario", selection: Binding(
                get: { state.scenarioID },
                set: { link.send(.init(name: "scenario", scenarioID: $0)) }
            )) {
                ForEach(state.scenarios) { scenario in Text(scenario.title).tag(scenario.id) }
            }
            .frame(maxWidth: 320)
    }

    private func transportControls(_ state: ReplayXIWireState) -> some View {
        HStack(spacing: 8) {
            Button(state.playing ? "Pause" : "Play") {
                link.send(.init(name: "play", value: !state.playing))
            }
            .keyboardShortcut(.space, modifiers: [])
            Button("−5s") { link.send(.init(name: "seek", time: max(0, state.playhead - 5))) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("+5s") { link.send(.init(name: "seek", time: min(state.duration, state.playhead + 5))) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    private func viewPicker(_ state: ReplayXIWireState) -> some View {
        Picker("View", selection: Binding(
                get: { state.viewMode },
                set: { link.send(.init(name: "view", viewMode: $0)) }
            )) {
                Text("Tactical").tag("tacticalTable")
                Text("Touchline").tag("touchline")
                Text("Positioning").tag("positional")
                Text("Player POV").tag("firstPerson")
            }
            .frame(width: 180)
    }

    private func povPicker(_ state: ReplayXIWireState) -> some View {
        Picker("POV", selection: Binding(
                get: { state.perspectiveID },
                set: { link.send(.init(name: "pov", playerID: $0)) }
            )) {
                ForEach(state.players) { player in
                    Text("#\(player.number) \(player.name)").tag(player.id)
                }
            }
            .frame(width: 165)
    }

    private func speedPicker(_ state: ReplayXIWireState) -> some View {
        Picker("Speed", selection: Binding(
                get: { state.rate },
                set: { link.send(.init(name: "rate", rate: $0)) }
            )) {
                ForEach([0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 4.0], id: \.self) { rate in
                    Text("\(rate.formatted())×").tag(rate)
                }
            }
            .frame(width: 105)
    }

    private func timeline(_ state: ReplayXIWireState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TIMELINE").font(.caption).bold()
                Spacer()
                Text("\(draftTime.formatted(.number.precision(.fractionLength(1)))) / \(state.duration.formatted(.number.precision(.fractionLength(1)))) s")
                    .monospacedDigit().font(.caption)
            }
            Slider(value: $draftTime, in: 0...max(state.duration, 0.01)) { editing in
                scrubbing = editing
                if !editing { link.send(.init(name: "seek", time: draftTime)) }
            }
            GeometryReader { size in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.secondary.opacity(0.25)).frame(height: 2)
                    ForEach(state.marks) { mark in
                        let x = CGFloat(mark.showAt / max(state.duration, 0.01)) * size.size.width
                        Circle().fill(mark.authored ? .gray : .orange)
                            .frame(width: selectedMarkID == mark.id ? 10 : 7, height: 10)
                            .position(x: x, y: 7)
                            .help("\(mark.label) · show \(mark.showAt.formatted()) s")
                            .onTapGesture { selectedMarkID = mark.id }
                    }
                }
            }
            .frame(height: 16)
        }
    }

    private func inspector(_ state: ReplayXIWireState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ANNOTATIONS").font(.headline)
                HStack {
                    Picker("Draw", selection: $drawKind) {
                        ForEach(["run", "pass", "arc", "danger", "space"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Button(drawStart == nil ? "New: click start" : "Click end") { drawStart = nil }
                }
                Text("Click two pitch points to add a mark. Drag its handles to edit.")
                    .font(.caption).foregroundStyle(.secondary)
                if !state.canEdit {
                    Text("Pause playback and finish headset edits to edit annotations here.")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Picker("Player label", selection: $labelPlayerID) {
                        Text("Select player").tag("")
                        ForEach(state.players) { player in
                            Text("#\(player.number) \(player.name)").tag(player.id)
                        }
                    }
                    Button("Add label") {
                        link.send(.init(name: "labelPlayer", playerID: labelPlayerID))
                    }
                    .disabled(!state.canEdit || labelPlayerID.isEmpty)
                }
                ForEach(state.marks) { mark in
                    Button {
                        selectedMarkID = mark.id
                    } label: {
                        HStack {
                            Circle().fill(mark.authored ? .gray : .orange).frame(width: 7, height: 7)
                            Text(mark.label).lineLimit(1)
                            Spacer()
                            Text(mark.kind).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(selectedMarkID == mark.id ? Color.accentColor.opacity(0.2) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Divider()
                if let mark = selectedMark {
                    Text(mark.authored ? "Authored overlay · view only" : "SELECTED / \(mark.kind.uppercased())")
                        .font(.caption).bold()
                    if inspectorConflict {
                        HStack {
                            Text("Headset state changed. Reload this mark before editing.")
                                .font(.caption).foregroundStyle(.orange)
                            Button("Reload") { loadInspector() }
                        }
                    }
                    TextField("Label", text: $label)
                    Button("Apply label") {
                        commitInspectorDraft()
                        link.send(.init(name: "label", markID: mark.id, label: label))
                    }
                        .disabled(mark.authored || !state.canEdit || inspectorConflict)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Start height · m")
                            Slider(value: $startHeight, in: 0...4)
                        }
                        Text(startHeight.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
                    }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("End height · m")
                            Slider(value: $endHeight, in: 0...4)
                        }
                        Text(endHeight.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
                    }
                    Button("Apply 3D pose") { sendPose(mark, start: mark.start, end: mark.end) }
                        .disabled(mark.authored || !state.canEdit || inspectorConflict)
                    if mark.kind == "arc", let control = mark.controlPoint {
                        HStack {
                            Text("Arc control height")
                            Slider(value: $controlHeight, in: 0...12)
                            Text(controlHeight.formatted(.number.precision(.fractionLength(2))))
                        }
                        Button("Apply arc control") {
                            commitInspectorDraft()
                            link.send(.init(name: "arcControl", markID: mark.id,
                                controlPoint: .init(x: control.x, y: Float(controlHeight), z: control.z)))
                        }
                        .disabled(mark.authored || !state.canEdit || inspectorConflict)
                    }
                    Divider()
                    Text("VISIBLE WINDOW").font(.caption).bold()
                    HStack { Text("Show at"); TextField("s", value: $showAt, format: .number).frame(width: 80) }
                    Toggle("Hide at", isOn: $hasHide)
                    if hasHide { TextField("Hide time · s", value: $hideAt, format: .number) }
                    Button("Apply show / hide") {
                        commitInspectorDraft()
                        link.send(.init(name: "window", markID: mark.id,
                            showAt: showAt, hideAt: hasHide ? hideAt : nil))
                    }
                    .disabled(mark.authored || !state.canEdit || inspectorConflict)
                    Divider()
                    Text("KEYFRAMES").font(.caption).bold()
                    HStack {
                        Button("Capture at playhead") { link.send(.init(name: "captureKey", markID: mark.id)) }
                        .disabled(mark.authored || !state.canEdit)
                    }
                    ForEach(mark.keyframes, id: \.self) { time in
                        Button("\(time.formatted(.number.precision(.fractionLength(2)))) s") {
                            selectedKey = time; retimeKey = time
                            link.send(.init(name: "seek", time: time))
                        }
                    }
                    if !mark.keyframes.isEmpty {
                        HStack {
                            Text("Selected \(selectedKey.formatted(.number.precision(.fractionLength(2)))) s")
                            Button("Delete key") { link.send(.init(name: "deleteKey", markID: mark.id, keyframeAt: selectedKey)) }
                        }
                        HStack {
                            TextField("Move to · s", value: $retimeKey, format: .number)
                            Button("Move key") { link.send(.init(name: "retimeKey", markID: mark.id, keyframeAt: selectedKey, keyframeTo: retimeKey)) }
                        }
                        .disabled(mark.authored || !state.canEdit)
                    }
                    Button("Delete mark", role: .destructive) { link.send(.init(name: "delete", markID: mark.id)) }
                        .disabled(mark.authored || !state.canEdit)
                        .keyboardShortcut(.delete, modifiers: [])
                }
                Divider()
                HStack {
                    Button("Undo") { link.send(.init(name: "undo")) }
                        .disabled(!state.canUndo)
                        .keyboardShortcut("z", modifiers: .command)
                    Button("Redo") { link.send(.init(name: "redo")) }
                        .disabled(!state.canRedo)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                }
                Button("Clear coach marks", role: .destructive) {
                    showClearConfirmation = true
                }
                .disabled(!state.canEdit || !state.marks.contains(where: { !$0.authored }))
                .confirmationDialog("Clear all coach marks?", isPresented: $showClearConfirmation) {
                    Button("Clear coach marks", role: .destructive) {
                        link.send(.init(name: "clear"))
                    }
                } message: {
                    Text("This removes coach-added marks in this scenario. Authored overlays remain.")
                }
                HStack {
                    TextField("Save name", text: $saveName)
                    Button("Save") { link.send(.init(name: "save", saveName: saveName)) }
                        .disabled(!state.canSave)
                        .keyboardShortcut("s", modifiers: .command)
                }
                Text(state.status).font(.caption).foregroundStyle(.secondary)
                if !link.lastAction.isEmpty {
                    Text(link.lastAction).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(16)
        }
    }

    private func loadInspector() {
        guard let mark = selectedMark else { return }
        label = mark.label
        startHeight = Double(mark.startHeight)
        endHeight = Double(mark.endHeight)
        showAt = mark.showAt
        hideAt = mark.hideAt ?? min((state?.duration ?? mark.showAt), mark.showAt + 5)
        hasHide = mark.hideAt != nil
        controlHeight = Double(mark.controlPoint?.y ?? 0)
        selectedKey = mark.keyframes.first ?? 0
        retimeKey = selectedKey
        loadedMarkFingerprint = try? ReplayXIWire.encoder.encode(mark)
        loadedDraft = currentDraft
        inspectorConflict = false
    }

    private func commitInspectorDraft() { loadedDraft = currentDraft }

    private func pitchClicked(_ point: ReplayXIWirePoint) {
        guard state?.canEdit == true else { return }
        guard let start = drawStart else { drawStart = point; return }
        let label: String = switch drawKind {
        case "pass": "Pass"
        case "arc": "Curved run"
        case "danger": "Pressure"
        case "space": "Useful space"
        default: "Run"
        }
        link.send(.init(name: "create", kind: drawKind, start: start, end: point,
            startHeight: 0, endHeight: 0, label: label))
        drawStart = nil
    }

    private func moveEndpoint(_ mark: ReplayXIWireMark, _ endpoint: String, _ point: ReplayXIWirePoint) {
        guard state?.canEdit == true, !inspectorConflict else { return }
        let start = endpoint == "start" ? point : mark.start
        let end = endpoint == "end" ? point : mark.end
        sendPose(mark, start: start, end: end)
        dragStart = nil; dragEnd = nil
    }

    private func sendPose(_ mark: ReplayXIWireMark, start: ReplayXIWirePoint, end: ReplayXIWirePoint) {
        guard !inspectorConflict else { return }
        commitInspectorDraft()
        link.send(.init(name: "geometry", markID: mark.id, start: start, end: end,
            startHeight: Float(startHeight), endHeight: Float(endHeight)))
    }
}

private struct PitchMap: View {
    let state: ReplayXIWireState
    @Binding var selectedMarkID: UUID?
    let drawKind: String
    @Binding var drawStart: ReplayXIWirePoint?
    @Binding var dragStart: ReplayXIWirePoint?
    @Binding var dragEnd: ReplayXIWirePoint?
    let onPitchClick: (ReplayXIWirePoint) -> Void
    let onMove: (ReplayXIWireMark, String, ReplayXIWirePoint) -> Void
    let onArcControl: (ReplayXIWireMark, ReplayXIWirePoint) -> Void

    var body: some View {
        GeometryReader { geo in
            let rect = pitchRect(in: geo.size)
            ZStack {
                Color.black.opacity(0.86)
                Path { path in
                    path.addRect(rect)
                    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                    path.addEllipse(in: CGRect(x: rect.midX - 34, y: rect.midY - 34, width: 68, height: 68))
                }
                .stroke(.white.opacity(0.55), lineWidth: 1.5)
                ForEach(state.marks) { mark in
                    let a = screen(dragStart != nil && selectedMarkID == mark.id ? dragStart! : mark.start, rect)
                    let b = screen(dragEnd != nil && selectedMarkID == mark.id ? dragEnd! : mark.end, rect)
                    Path { path in
                        path.move(to: a)
                        if let control = mark.controlPoint {
                            path.addQuadCurve(to: b,
                                control: screen(.init(x: control.x, z: control.z), rect))
                        } else { path.addLine(to: b) }
                    }
                    .stroke(mark.authored ? .gray : .orange,
                            style: StrokeStyle(lineWidth: selectedMarkID == mark.id ? 3 : 2, dash: mark.authored ? [5, 4] : []))
                    Circle().fill(mark.authored ? .gray : .orange)
                        .frame(width: 11, height: 11)
                        .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                        .help("Select \(mark.label)")
                        .onTapGesture { selectedMarkID = mark.id }
                    if selectedMarkID == mark.id, !mark.authored {
                        handle(mark, "start", at: a, rect: rect)
                        handle(mark, "end", at: b, rect: rect)
                        if let control = mark.controlPoint {
                            Circle().fill(.cyan).frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.black, lineWidth: 2))
                                .position(screen(.init(x: control.x, z: control.z), rect))
                                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("pitch"))
                                    .onEnded { value in onArcControl(mark, pitch(value.location, rect)) })
                                .help("Drag arc control point. Height is set in the inspector.")
                        }
                    }
                }
                ForEach(state.players) { player in
                    Text("\(player.number)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 23, height: 23)
                        .background(player.team == "home" ? Color.blue : Color.red, in: Circle())
                        .position(screen(player.position, rect))
                        .help(player.name)
                }
                Circle().fill(.white).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.black, lineWidth: 2))
                    .position(screen(.init(x: state.ball.x, z: state.ball.z), rect))
                    .help("Ball · \(state.ball.y.formatted(.number.precision(.fractionLength(2)))) m high")
                if let drawStart {
                    Circle().fill(.orange).frame(width: 13, height: 13)
                        .position(screen(drawStart, rect))
                }
                Text("68 × 105 m · \(drawKind.capitalized)")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(12)
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: "pitch")
            .gesture(SpatialTapGesture(coordinateSpace: .named("pitch")).onEnded { tap in
                if rect.contains(tap.location) { onPitchClick(pitch(tap.location, rect)) }
            })
        }
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func handle(_ mark: ReplayXIWireMark, _ endpoint: String,
                        at point: CGPoint, rect: CGRect) -> some View {
        Circle().fill(.yellow).frame(width: 18, height: 18)
            .overlay(Circle().stroke(.black, lineWidth: 2))
            .position(point)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("pitch"))
                .onChanged { value in
                    let next = pitch(value.location, rect)
                    if endpoint == "start" { dragStart = next } else { dragEnd = next }
                }
                .onEnded { value in onMove(mark, endpoint, pitch(value.location, rect)) })
    }

    private func pitchRect(in size: CGSize) -> CGRect {
        let h = max(1, size.height - 26)
        let w = min(size.width - 26, h * 68 / 105)
        let actualH = w * 105 / 68
        return CGRect(x: (size.width - w) / 2, y: (size.height - actualH) / 2,
                      width: w, height: actualH)
    }
    private func screen(_ p: ReplayXIWirePoint, _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX + CGFloat(p.x / 68) * rect.width,
                y: rect.midY + CGFloat(p.z / 105) * rect.height)
    }
    private func pitch(_ p: CGPoint, _ rect: CGRect) -> ReplayXIWirePoint {
        .init(x: Float(min(max((p.x - rect.midX) / rect.width * 68, -34), 34)),
              z: Float(min(max((p.y - rect.midY) / rect.height * 105, -52.5), 52.5)))
    }
}
