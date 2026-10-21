import SwiftUI

struct CoachWindow: View {
    @Environment(ReplayXIMacLink.self) private var link
    @AppStorage("ReplayXI.coachConnectionTarget") private var connectionTarget = "simulator"
    @State private var deviceID = ""
    @State private var selectedMarkID: UUID?
    @State private var drawKind = "run"
    @State private var drawingEnabled = false
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
    @State private var showClearConfirmation = false
    @State private var pendingFreezeID: UUID?
    @State private var loadedMark: ReplayXIWireMark?
    @State private var loadedDraft: CoachInspectorDraft?
    @State private var inspectorConflict = false
    @State private var library = "marks"
    @State private var search = ""
    @State private var activeOnly = false
    @State private var showSave = false
    @State private var showShortcuts = false
    @State private var showShape = false
    @State private var showKeys = false
    @State private var showInspector = true
    @AppStorage("ReplayXI.coach3DPreview") private var shows3D = true
    @AppStorage("ReplayXI.coachRecordMotion") private var recordMotion = true
    @State private var previewReset = 0
    @State private var pendingDrawKind: String?
    @State private var marksBeforeCreate: Set<UUID>?
    @FocusState private var timeFieldFocused: Bool

    init(selectedMarkID: UUID? = nil) {
        _selectedMarkID = State(initialValue: selectedMarkID)
    }

    private var currentDraft: CoachInspectorDraft {
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
                    VStack(spacing: 8) {
                        playbackBar(state)
                        toolBar(state).disabled(link.playbackContextPending)
                        if shows3D {
                            CoachScenePreview(state: state, selectedMarkID: selectedMarkID,
                                drawingEnabled: drawingEnabled, drawStart: drawStart,
                                resetRevision: previewReset,
                                select: { selectedMarkID = $0 }, onPlayer: { link.send(.init(name: "pov", playerID: $0)) },
                                onPitchClick: pitchClicked,
                                onPose: { mark, start, end, control in
                                    guard state.canEdit, !inspectorConflict else { return }
                                    link.send(.init(name: "geometry", markID: mark.id,
                                        start: .init(x: start.x, z: start.z), end: .init(x: end.x, z: end.z),
                                        startHeight: start.y, endHeight: end.y, controlPoint: control,
                                        recordMotion: recordMotion))
                                })
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .allowsHitTesting(!link.playbackContextPending)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                        PitchMap(state: state, selectedMarkID: $selectedMarkID,
                            drawKind: drawKind, drawingEnabled: drawingEnabled, drawStart: $drawStart,
                            dragStart: $dragStart, dragEnd: $dragEnd,
                            onPitchClick: pitchClicked, onMove: moveEndpoint,
                            onPlayer: { link.send(.init(name: "pov", playerID: $0)) },
                            onArcControl: { mark, point in
                                guard state.canEdit, !inspectorConflict else { return }
                                link.send(.init(name: "geometry", markID: mark.id, start: mark.start, end: mark.end,
                                    startHeight: mark.startHeight, endHeight: mark.endHeight,
                                    controlPoint: .init(x: point.x, y: Float(controlHeight), z: point.z),
                                    recordMotion: recordMotion))
                            })
                            .allowsHitTesting(!link.playbackContextPending)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        timeline(state)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                workspaceFooter(state).disabled(link.playbackContextPending)
            } else {
                ContentUnavailableView(connectionTarget == "simulator" ? "Connect to Vision Pro Simulator" : "Connect to Replay XI",
                    systemImage: connectionTarget == "simulator" ? "desktopcomputer" : "visionpro",
                    description: Text(connectionTarget == "simulator"
                        ? "On this Mac, open Replay XI in Vision Pro Simulator. Choose Start Mac link, then enter its PIN above."
                        : "Open Replay XI on Vision Pro and choose Start Mac link. Use the same local network and enter its PIN above."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .inspector(isPresented: Binding(get: { state != nil && showInspector }, set: { showInspector = $0 })) {
            if let state {
                inspector(state).disabled(link.playbackContextPending)
                    .inspectorColumnWidth(min: 340, ideal: 390, max: 480)
            }
        }
        .toolbar {
            if state != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showInspector.toggle() } label: { Image(systemName: "sidebar.trailing") }
                        .help("Show or hide Review · ⌥⌘I")
                        .accessibilityLabel("Show or hide Review")
                        .keyboardShortcut("i", modifiers: [.option, .command])
                }
            }
        }
        .toolbarRole(.editor)
        .confirmationDialog("Freeze motion here?", isPresented: Binding(
            get: { pendingFreezeID != nil }, set: { if !$0 { pendingFreezeID = nil } })) {
            Button("Freeze at playhead") {
                if let id = pendingFreezeID { link.send(.init(name: "freezeKeys", markID: id)) }
                pendingFreezeID = nil; recordMotion = false
            }
        } message: { Text("Keeps the current shape and removes its saved poses. You can undo this.") }
        .onChange(of: state?.playhead, initial: true) { _, value in
            if !scrubbing, !timeFieldFocused, let value { draftTime = value }
        }
        .onChange(of: draftTime) { _, time in
            if scrubbing { link.seek(to: time, final: false) }
        }
        .onChange(of: selectedMarkID, initial: true) { _, _ in loadInspector() }
        .onChange(of: timeFieldFocused) { _, focused in
            if !focused { draftTime = state?.playhead ?? 0 }
        }
        .onChange(of: state?.scenarioID) { _, _ in
            if state != nil { showInspector = true }
            drawingEnabled = false
            drawStart = nil
            selectedMarkID = nil
            pendingDrawKind = nil
            marksBeforeCreate = nil
            search = ""
        }
        .onExitCommand {
            drawingEnabled = false
            drawStart = nil
            dragStart = nil
            dragEnd = nil
            pendingDrawKind = nil
        }
        .onChange(of: state?.canEdit) { _, canEdit in
            if canEdit == true, let kind = pendingDrawKind {
                pendingDrawKind = nil
                beginDrawing(kind)
            } else if canEdit != true {
                drawingEnabled = false; drawStart = nil; dragStart = nil; dragEnd = nil
            }
        }
        .onChange(of: library) { _, _ in search = "" }
        .onChange(of: state?.revision) { _, _ in
            if state?.playing == false, let kind = pendingDrawKind {
                pendingDrawKind = nil
                if state?.canEdit == true { beginDrawing(kind) }
            }
            if let previous = marksBeforeCreate,
               let created = state?.marks.first(where: { !$0.authored && !previous.contains($0.id) }) {
                selectedMarkID = created.id
                marksBeforeCreate = nil
                showInspector = true
                showShape = created.kind == "arc"
            }
            if let id = selectedMarkID, state?.marks.contains(where: { $0.id == id }) != true {
                selectedMarkID = nil
            } else if let mark = selectedMark, mark != loadedMark, let base = loadedDraft {
                let remote = CoachInspectorDraft(mark, duration: state?.duration ?? mark.showAt)
                let merged = CoachInspectorDraft.merge(base: base, local: currentDraft, remote: remote)
                applyDraft(merged.draft)
                inspectorConflict = inspectorConflict || merged.conflict
                loadedDraft = remote
                loadedMark = mark
                if !mark.keyframes.contains(selectedKey) {
                    selectedKey = mark.keyframes.first ?? 0; retimeKey = selectedKey
                }
            }
        }
        .onChange(of: link.lastAction) { _, action in
            if action.hasPrefix("Rejected:") { pendingDrawKind = nil; marksBeforeCreate = nil }
        }
    }

    private var connectionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sportscourt")
                .help("Replay XI Coach connection")
                .accessibilityLabel("Replay XI Coach connection")
            Spacer()
            Label(link.status, systemImage: link.connected ? "checkmark.circle.fill" : "wifi")
                .font(.caption)
                .foregroundStyle(link.connected ? .green : .secondary)
                .lineLimit(1).help(link.status)
            if link.connected {
                Button("Disconnect") { link.disconnect() }
            } else {
                Picker("Connect", selection: $connectionTarget) {
                    Text("Simulator on this Mac").tag("simulator")
                    Text("Vision Pro headset").tag("headset")
                }.labelsHidden().frame(width: 190).disabled(link.isConnecting)
                if connectionTarget == "headset" {
                Picker("Headset", selection: $deviceID) {
                    Text("Select headset").tag("")
                    ForEach(link.devices) { device in Text(device.name).tag(device.id) }
                }
                .frame(width: 195).disabled(link.isConnecting)
                Button("Rescan") { link.retryDiscovery() }.disabled(link.isConnecting)
                }
                SecureField("Six digit PIN", text: Bindable(link).pin)
                    .frame(width: 110).disabled(link.isConnecting)
                    .onSubmit { pair() }
                if link.isConnecting {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { link.disconnect() }
                } else {
                Button("Pair") { pair() }
                .buttonStyle(.borderedProminent)
                .disabled((connectionTarget == "headset" && currentDevice == nil) ||
                    link.pin.count != 6 || !link.pin.allSatisfy(\.isNumber))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .modifier(CoachGlassSurface())
    }

    private func scenarioPicker(_ state: ReplayXIWireState) -> some View {
        Picker("Scenario", selection: Binding(
                get: { state.scenarioID },
                set: { link.send(.init(name: "scenario", scenarioID: $0)) }
            )) {
                ForEach(state.scenarios) { scenario in Text(scenario.title).tag(scenario.id) }
            }
            .labelsHidden()
            .frame(maxWidth: 320)
            .help("Choose scenario")
    }

    private func transportControls(_ state: ReplayXIWireState) -> some View {
        HStack(spacing: 8) {
            Button { link.send(.init(name: "seek", time: max(0, state.playhead - 5))) } label: {
                Image(systemName: "gobackward.5")
            }
            .help("Back 5 seconds · ←").accessibilityLabel("Back 5 seconds")
            .keyboardShortcut(.leftArrow, modifiers: [])
            Button {
                link.send(.init(name: "play", value: !state.playing))
            } label: {
                Image(systemName: state.playing ? "pause.fill" : "play.fill").frame(width: 20)
            }
            .help(state.playing ? "Pause · Space" : "Play · Space")
            .accessibilityLabel(state.playing ? "Pause" : "Play")
            .keyboardShortcut(.space, modifiers: [])
            Button { link.send(.init(name: "seek", time: min(state.duration, state.playhead + 5))) } label: {
                Image(systemName: "goforward.5")
            }
            .help("Forward 5 seconds · →").accessibilityLabel("Forward 5 seconds")
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
            .labelsHidden()
            .frame(width: 180)
            .help("Headset view")
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
            .labelsHidden()
            .frame(width: 165)
            .help("Headset player POV")
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
            .labelsHidden()
            .frame(width: 105)
            .help("Playback speed")
    }

    private func timeline(_ state: ReplayXIWireState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { link.send(.init(name: "seek", time: max(0, state.playhead - 1.0 / 30))) } label: {
                    Image(systemName: "backward.frame")
                }
                .help("Back 1/30 second · ⌥←").accessibilityLabel("Back 1/30 second")
                .keyboardShortcut(.leftArrow, modifiers: .option)
                Button { link.send(.init(name: "seek", time: min(state.duration, state.playhead + 1.0 / 30))) } label: {
                    Image(systemName: "forward.frame")
                }
                .help("Forward 1/30 second · ⌥→").accessibilityLabel("Forward 1/30 second")
                .keyboardShortcut(.rightArrow, modifiers: .option)
                TextField("Seconds", value: $draftTime, format: .number.precision(.fractionLength(2)))
                    .frame(width: 70).monospacedDigit()
                    .focused($timeFieldFocused)
                    .onSubmit {
                        guard draftTime.isFinite else { draftTime = state.playhead; return }
                        draftTime = min(max(0, draftTime), state.duration)
                        link.send(.init(name: "seek", time: draftTime))
                    }
                    .help("Enter an exact time in seconds, then press Return.")
                Spacer()
                if let mark = selectedMark {
                    Button { jumpKey(mark, forward: false) } label: { Image(systemName: "backward.end") }
                        .help("Previous saved pose").accessibilityLabel("Previous saved pose")
                        .disabled(CoachWorkspace.adjacentKey(in: mark.keyframes, at: state.playhead, forward: false) == nil)
                    Text("\(mark.keyframes.count) poses").font(.caption).foregroundStyle(.secondary)
                    Button { jumpKey(mark, forward: true) } label: { Image(systemName: "forward.end") }
                        .help("Next saved pose").accessibilityLabel("Next saved pose")
                        .disabled(CoachWorkspace.adjacentKey(in: mark.keyframes, at: state.playhead, forward: true) == nil)
                }
                Text("\(CoachWorkspace.clock(draftTime)) / \(CoachWorkspace.clock(state.duration))")
                    .monospacedDigit().font(.callout)
            }
            .controlSize(.small)
            Slider(value: $draftTime, in: 0...max(state.duration, 0.01)) { editing in
                if editing { timeFieldFocused = false }
                scrubbing = editing
                if !editing { link.seek(to: draftTime, final: true) }
            }
            CoachMarkTimeline(state: state, selectedMarkID: selectedMarkID, playhead: draftTime,
                select: { selectedMarkID = $0.id }, seek: { time, final in
                    timeFieldFocused = false; scrubbing = !final; draftTime = time
                    if selectedMark?.keyframes.contains(where: { abs($0 - time) <= CoachWorkspace.keyTimeTolerance }) == true {
                        selectedKey = time; retimeKey = time
                    }
                    // Preview is coalesced by onChange(draftTime). Release
                    // flushes here even if the last pointer sample was equal.
                    if final { link.seek(to: time, final: true) }
                }, trim: { mark, start, end in
                    guard !link.playbackContextPending, !inspectorConflict,
                          CoachWorkspace.validWindow(show: start, hide: end, duration: state.duration) else { return }
                    link.send(.init(name: "window", markID: mark.id, showAt: start, hideAt: end))
                }, retime: { mark, old, new in
                    guard !link.playbackContextPending, !inspectorConflict, state.canEdit, !mark.authored,
                        CoachWorkspace.validKeyMove(from: old, to: new,
                            keys: mark.keyframes, duration: state.duration) else { return }
                    selectedMarkID = mark.id; selectedKey = new; retimeKey = new
                    link.send(.init(name: "retimeKey", markID: mark.id,
                        keyframeAt: old, keyframeTo: new))
                })
        }
    }

    private func toolBar(_ state: ReplayXIWireState) -> some View {
        HStack(spacing: 7) {
            Picker("Preview", selection: $shows3D) {
                Text("3D").tag(true)
                Text("2D").tag(false)
            }.pickerStyle(.segmented).frame(width: 85)
            if shows3D {
                Button { previewReset += 1 } label: { Image(systemName: "viewfinder") }
                    .help("Reset 3D camera").accessibilityLabel("Reset 3D camera")
            }
            Menu {
                Button("Look at ball", systemImage: "soccerball") {
                    link.send(.init(name: "lookAt", lookTarget: "ball"))
                }
                if !state.perspectiveID.isEmpty {
                    Button("Look at POV player", systemImage: "person.crop.circle") {
                        link.send(.init(name: "lookAt", playerID: state.perspectiveID,
                            lookTarget: "player"))
                    }
                }
                if let mark = selectedMark {
                    Divider()
                    Button("Look at mark origin", systemImage: "scope") {
                        link.send(.init(name: "lookAt", markID: mark.id,
                            lookTarget: "markStart"))
                    }
                    Button("Look at mark end", systemImage: "scope") {
                        link.send(.init(name: "lookAt", markID: mark.id,
                            lookTarget: "markEnd"))
                    }
                }
            } label: { Image(systemName: "eye") }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("Aim headset view once at ball, player or mark")
            .accessibilityLabel("Aim headset view")
            if let mark = selectedMark, !mark.authored, mark.kind != "playerLabel" {
                Toggle(isOn: $recordMotion) { Image(systemName: "diamond.fill") }
                    .toggleStyle(.button)
                    .help(mark.keyframes.isEmpty ? "Record moves: seek, then drag a point to save its pose" : "Motion active. Freeze here in Motion poses to return to static editing.")
                    .accessibilityLabel("Record moves at playhead")
                    .disabled(!mark.keyframes.isEmpty || mark.startPlayerID != nil || mark.endPlayerID != nil)
            }
            Button {
                drawingEnabled = false; drawStart = nil; pendingDrawKind = nil
            } label: { Image(systemName: "cursorarrow").frame(width: 22, height: 20) }
            .tint(!drawingEnabled ? .accentColor : .secondary)
            .help("Select / move · Esc").accessibilityLabel("Select or move")
            ForEach(["run", "pass", "arc", "space", "danger"], id: \.self) { kind in
                Button {
                    beginDrawing(kind)
                } label: { Image(systemName: CoachWorkspace.symbol(for: kind)).frame(width: 22, height: 20) }
                .tint(drawingEnabled && drawKind == kind ? .orange : .secondary)
                .help("Draw \(CoachWorkspace.title(for: kind).lowercased()) · click two pitch points")
                .accessibilityLabel("Draw \(CoachWorkspace.title(for: kind))")
                .disabled(!state.canEdit && !state.playing)
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(drawingEnabled && drawKind == kind ? Color.orange : .clear, lineWidth: 2))
            }
            Spacer(minLength: 4)
            if pendingDrawKind != nil || drawingEnabled {
                Image(systemName: pendingDrawKind != nil ? "pause.circle" : "pencil.tip.crop.circle")
                    .foregroundStyle(.orange)
                    .help(pendingDrawKind != nil ? "Pausing playback" :
                        "Draw \(CoachWorkspace.title(for: drawKind)): \(drawStart == nil ? "click origin" : "click end")")
                    .accessibilityLabel(pendingDrawKind != nil ? "Pausing playback" : "Drawing annotation")
            }
            Button { link.send(.init(name: "undo")) } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!state.canUndo || !state.canEdit)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo · ⌘Z").accessibilityLabel("Undo")
            Button { link.send(.init(name: "redo")) } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!state.canRedo || !state.canEdit)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo · ⇧⌘Z").accessibilityLabel("Redo")
        }
        .controlSize(.regular)
        .frame(height: 42)
        .padding(.horizontal, 10)
        .modifier(CoachGlassSurface())
    }

    private func workspaceFooter(_ state: ReplayXIWireState) -> some View {
        HStack {
            Image(systemName: state.canEdit ? "pencil.circle" : "lock.circle")
                .foregroundStyle(state.canEdit ? Color.secondary : .orange)
            Text(link.lastAction.isEmpty ? state.status : link.lastAction)
                .font(.caption).lineLimit(1)
                .help(link.lastAction.isEmpty ? state.status : link.lastAction)
            Spacer()
            Button { showShortcuts.toggle() } label: { Image(systemName: "keyboard") }
                .help("Keyboard shortcuts").accessibilityLabel("Keyboard shortcuts")
                .popover(isPresented: $showShortcuts) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Keyboard shortcuts").font(.headline)
                        Text("Space    Play / pause\n← →    Seek 5 seconds\n⌥← ⌥→    Step 1/30 second\n⌘N    Draw selected tool\nEsc    Cancel drawing\n⌘Z / ⇧⌘Z    Undo / redo\n⌘S    Save review\n⌘⌫    Delete selected mark")
                            .font(.callout).lineSpacing(5)
                    }.padding(20)
                }
            Menu {
                Button("Clear coach marks…", role: .destructive) { showClearConfirmation = true }
                    .disabled(!state.canEdit || !state.marks.contains(where: { !$0.authored }))
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).frame(width: 25).help("Review actions")
            Button("Save review…", systemImage: "square.and.arrow.down") { showSave = true }
                .disabled(!state.canSave || !state.canEdit)
                .keyboardShortcut("s", modifiers: .command)
                .popover(isPresented: $showSave) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Save on Vision Pro").font(.headline)
                        TextField("Review name", text: $saveName).frame(width: 240).onSubmit { saveReview() }
                        Button("Save review") { saveReview() }
                        .disabled(saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.canEdit || !state.canSave)
                    }.padding(18)
                }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .confirmationDialog("Clear all coach marks?", isPresented: $showClearConfirmation) {
            Button("Clear coach marks", role: .destructive) { link.send(.init(name: "clear")) }
        } message: { Text("Authored overlays remain. You can undo this change.") }
    }

    private func inspector(_ state: ReplayXIWireState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                libraryPanel(state)
                if !state.canEdit {
                    Text(state.playing ? "Pause to edit annotations." : "Finish the current headset edit to continue here.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Divider()
                if let mark = selectedMark {
                    HStack {
                        Label(CoachWorkspace.title(for: mark.kind), systemImage: CoachWorkspace.symbol(for: mark.kind))
                            .font(.headline)
                        Spacer()
                        Text(mark.authored ? "Read only" : "Coach mark")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !CoachWorkspace.isVisible(mark, at: state.playhead) {
                        Label("Hidden at this time · dashed preview only", systemImage: "eye.slash")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if inspectorConflict {
                        HStack {
                            Text("Headset state changed. Reload this mark before editing.")
                                .font(.caption).foregroundStyle(.orange)
                            Button("Reload") { loadInspector() }
                        }
                    }
                    HStack {
                        TextField("Label", text: $label).disabled(mark.authored || !state.canEdit || inspectorConflict)
                        Button("Rename") {
                        link.send(.init(name: "label", markID: mark.id, label: label))
                        }
                        .disabled(mark.authored || !state.canEdit || inspectorConflict || label == mark.label)
                    }
                    if mark.kind != "playerLabel" {
                        endpointLink(mark, endpoint: "start", title: "Origin", state: state)
                        endpointLink(mark, endpoint: "end", title: "End", state: state)
                        if mark.startPlayerID != nil || mark.endPlayerID != nil {
                            Text("Linked points follow the player. Unlink both for saved-pose motion.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup("3D shape", isExpanded: $showShape) {
                    VStack(alignment: .leading, spacing: 10) {
                    Text("Drag yellow ends on the pitch. Height is in metres.")
                        .font(.caption).foregroundStyle(.secondary)
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
                        Text("Drag the cyan point to bend the arc. Raise it for an overhead curve.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Arc control height")
                            Slider(value: $controlHeight, in: 0...12)
                            Text(controlHeight.formatted(.number.precision(.fractionLength(2))))
                        }
                        Button("Apply arc control") {
                                link.send(.init(name: "geometry", markID: mark.id, start: mark.start, end: mark.end,
                                    startHeight: mark.startHeight, endHeight: mark.endHeight,
                                    controlPoint: .init(x: control.x, y: Float(controlHeight), z: control.z),
                                    recordMotion: recordMotion))
                        }
                        .disabled(mark.authored || !state.canEdit || inspectorConflict)
                    }
                    }
                    .disabled(mark.authored || !state.canEdit || inspectorConflict)
                    .padding(.top, 8)
                    }
                    Divider()
                    Text("Visibility").font(.headline)
                    HStack {
                        Text("Show").frame(width: 40, alignment: .leading)
                        TextField("Seconds", value: $showAt, format: .number.precision(.fractionLength(2)))
                        Button("Now") { showAt = state.playhead }
                            .help("Use the current playhead time")
                    }
                    Toggle("Hide at a time", isOn: $hasHide)
                    if hasHide {
                        HStack {
                            Text("Hide").frame(width: 40, alignment: .leading)
                            TextField("Seconds", value: $hideAt, format: .number.precision(.fractionLength(2)))
                            Button("Now") { hideAt = state.playhead }
                                .help("Use the current playhead time")
                        }
                    }
                    if !CoachWorkspace.validWindow(show: showAt, hide: hasHide ? hideAt : nil, duration: state.duration) {
                        Text("Choose 0.5–30 seconds inside this clip, or leave Out unset.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                    Button("Apply timing") {
                        link.send(.init(name: "window", markID: mark.id,
                            showAt: showAt, hideAt: hasHide ? hideAt : nil))
                    }
                    .disabled(mark.authored || !state.canEdit || inspectorConflict ||
                        !CoachWorkspace.validWindow(show: showAt, hide: hasHide ? hideAt : nil, duration: state.duration))
                    Button("Go to start") { link.send(.init(name: "seek", time: mark.showAt)) }
                    }
                    Divider()
                    DisclosureGroup("Motion poses · \(mark.keyframes.count)", isExpanded: $showKeys) {
                    VStack(alignment: .leading, spacing: 8) {
                    Toggle("Record moves at playhead", isOn: $recordMotion)
                        .disabled(!mark.keyframes.isEmpty || mark.startPlayerID != nil || mark.endPlayerID != nil || mark.authored)
                    Text("Seek, then drag a point. Its pose is saved at that time. Click a diamond to return.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Capture at playhead") { link.send(.init(name: "captureKey", markID: mark.id)) }
                        .disabled(mark.authored || !state.canEdit || inspectorConflict || mark.startPlayerID != nil || mark.endPlayerID != nil)
                    }
                    ForEach(mark.keyframes, id: \.self) { time in
                        Button {
                            selectedKey = time; retimeKey = time
                            link.send(.init(name: "seek", time: time))
                        } label: {
                            Label(CoachWorkspace.clock(time), systemImage: selectedKey == time ? "diamond.fill" : "diamond")
                        }
                    }
                    if !mark.keyframes.isEmpty {
                        Button("Freeze here…") { pendingFreezeID = mark.id }
                            .disabled(mark.authored || !state.canEdit || inspectorConflict)
                        HStack {
                            Text("Selected \(selectedKey.formatted(.number.precision(.fractionLength(2)))) s")
                            Button("Delete key") { link.send(.init(name: "deleteKey", markID: mark.id, keyframeAt: selectedKey)) }
                                .disabled(mark.authored || !state.canEdit || inspectorConflict)
                        }
                        HStack {
                            TextField("Move to · s", value: $retimeKey, format: .number)
                            Button("Move key") { link.send(.init(name: "retimeKey", markID: mark.id, keyframeAt: selectedKey, keyframeTo: retimeKey)) }
                                .disabled(!CoachWorkspace.validKeyMove(from: selectedKey,
                                    to: retimeKey, keys: mark.keyframes, duration: state.duration))
                        }
                        .disabled(mark.authored || !state.canEdit || inspectorConflict)
                    }
                    }.padding(.top, 8)
                    }
                    Button("Delete mark", role: .destructive) { link.send(.init(name: "delete", markID: mark.id)) }
                        .disabled(mark.authored || !state.canEdit || inspectorConflict)
                        .keyboardShortcut(.delete, modifiers: .command)
                } else {
                    Label("Select a mark to adjust its shape and timing.", systemImage: "cursorarrow.click")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func libraryPanel(_ state: ReplayXIWireState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Review").font(.title3).bold()
                Spacer()
                Button {
                    beginDrawing(drawKind)
                } label: { Image(systemName: "plus") }
                .help("Draw \(CoachWorkspace.title(for: drawKind).lowercased()) · ⌘N")
                .accessibilityLabel("Draw selected annotation tool")
                .disabled(!state.canEdit && !state.playing).keyboardShortcut("n", modifiers: .command)
            }
            Picker("Browse", selection: $library) {
                Text("Marks · \(state.marks.count)").tag("marks")
                Text("Players · \(state.players.count)").tag("players")
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(library == "marks" ? "Find a mark or tool…" : "Name, number or team…", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            if library == "marks" {
                Toggle("Visible now", isOn: $activeOnly).toggleStyle(.checkbox).font(.caption)
                let marks = state.marks.filter {
                    (!activeOnly || CoachWorkspace.isVisible($0, at: state.playhead)) &&
                        CoachWorkspace.matches(search, values: [$0.label, CoachWorkspace.title(for: $0.kind)])
                }
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(marks) { mark in
                            Button { selectedMarkID = mark.id } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: CoachWorkspace.symbol(for: mark.kind))
                                        .foregroundStyle(mark.authored ? Color.secondary : .orange).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mark.label.isEmpty ? CoachWorkspace.title(for: mark.kind) : mark.label)
                                            .lineLimit(1)
                                        Text("\(CoachWorkspace.clock(mark.showAt)) – \(mark.hideAt.map(CoachWorkspace.clock) ?? "end")")
                                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 2)
                                    Image(systemName: mark.authored ? "lock" :
                                        (CoachWorkspace.isVisible(mark, at: state.playhead) ? "eye" : "eye.slash"))
                                        .foregroundStyle(.secondary).font(.caption)
                                }
                                .padding(7).contentShape(Rectangle())
                                .background(selectedMarkID == mark.id ? Color.accentColor.opacity(0.15) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                        if marks.isEmpty {
                            Text(state.marks.isEmpty ? "Choose a tool above the pitch to add a mark." : "No matching marks.")
                                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 14)
                        }
                    }
                }.frame(maxHeight: 170)
            } else {
                let players = state.players.filter {
                    CoachWorkspace.matches(search, values: [$0.name, "#\($0.number)", $0.team])
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(players) { player in
                            HStack(spacing: 8) {
                                Button { link.send(.init(name: "pov", playerID: player.id)) } label: {
                                    HStack {
                                        Text("\(player.number)").font(.system(size: 12, weight: .bold, design: .rounded))
                                            .frame(width: 26, height: 26).foregroundStyle(.white)
                                            .background(player.team == "home" ? Color.blue : .red, in: Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(player.name).lineLimit(1)
                                            Text(player.team.capitalized).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        if state.perspectiveID == player.id { Image(systemName: "eye.fill").font(.caption) }
                                    }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).help("Switch to #\(player.number) \(player.name)'s POV")
                                Button { link.send(.init(name: "labelPlayer", playerID: player.id)) } label: {
                                    Image(systemName: "tag.badge.plus")
                                }
                                .disabled(!state.canEdit).help("Add a 3D player label")
                                .accessibilityLabel("Label \(player.name)")
                            }.padding(5)
                        }
                        if players.isEmpty { Text("No matching players.").font(.caption).foregroundStyle(.secondary).padding() }
                    }
                }.frame(maxHeight: 170)
            }
        }
    }

    private func loadInspector() {
        guard let mark = selectedMark else {
            loadedMark = nil; loadedDraft = nil; inspectorConflict = false
            return
        }
        let draft = CoachInspectorDraft(mark, duration: state?.duration ?? mark.showAt)
        applyDraft(draft)
        selectedKey = mark.keyframes.first ?? 0
        retimeKey = selectedKey
        loadedMark = mark
        loadedDraft = draft
        inspectorConflict = false
    }

    private func applyDraft(_ draft: CoachInspectorDraft) {
        label = draft.label; startHeight = draft.startHeight; endHeight = draft.endHeight
        showAt = draft.showAt; hideAt = draft.hideAt; hasHide = draft.hasHide
        controlHeight = draft.controlHeight
    }

    private func pair() {
        guard !link.isConnecting, link.pin.count == 6, link.pin.allSatisfy(\.isNumber) else { return }
        if connectionTarget == "simulator" { link.connectToSimulator() }
        else if let currentDevice { link.connect(to: currentDevice) }
    }

    private func beginDrawing(_ kind: String) {
        guard let state else { return }
        drawingEnabled = false; drawStart = nil
        if state.playing {
            pendingDrawKind = kind
            link.send(.init(name: "play", value: false))
        } else if state.canEdit {
            drawKind = kind; drawingEnabled = true; drawStart = nil
        }
    }

    private func saveReview() {
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state?.canSave == true, state?.canEdit == true, !name.isEmpty else { return }
        link.send(.init(name: "save", saveName: name))
        showSave = false
    }

    private func pitchClicked(_ point: ReplayXIWirePoint) {
        guard state?.canEdit == true, drawingEnabled else { return }
        guard let start = drawStart else { drawStart = point; return }
        let label: String = switch drawKind {
        case "pass": "Pass"
        case "arc": "Curved run"
        case "danger": "Pressure"
        case "space": "Useful space"
        default: "Run"
        }
        marksBeforeCreate = Set(state?.marks.map(\.id) ?? [])
        link.send(.init(name: "create", kind: drawKind, start: start, end: point,
            startHeight: 0, endHeight: 0, label: label))
        drawStart = nil
        drawingEnabled = false
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
        link.send(.init(name: "geometry", markID: mark.id, start: start, end: end,
            startHeight: Float(startHeight), endHeight: Float(endHeight), recordMotion: recordMotion))
    }

    private func jumpKey(_ mark: ReplayXIWireMark, forward: Bool) {
        guard let time = CoachWorkspace.adjacentKey(in: mark.keyframes, at: state?.playhead ?? 0, forward: forward) else { return }
        selectedKey = time; retimeKey = time
        link.seek(to: time, final: true)
    }

    private func endpointLink(_ mark: ReplayXIWireMark, endpoint: String, title: String,
                              state: ReplayXIWireState) -> some View {
        let point = endpoint == "start" ? mark.start : mark.end
        let linkedID = endpoint == "start" ? mark.startPlayerID : mark.endPlayerID
        let closest = state.players.min { a, b in
            let ax = a.position.x - point.x, az = a.position.z - point.z
            let bx = b.position.x - point.x, bz = b.position.z - point.z
            return ax * ax + az * az < bx * bx + bz * bz
        }
        return VStack(alignment: .leading, spacing: 3) {
            Picker(title, selection: Binding(get: { linkedID ?? "" }, set: { id in
                link.send(.init(name: "trackEndpoint", playerID: id.isEmpty ? nil : id,
                                markID: mark.id, endpoint: endpoint))
            })) {
                Text("Pitch fixed").tag("")
                ForEach(state.players) { player in
                    Text("\(player.team.capitalized) · #\(player.number) \(player.name)").tag(player.id)
                }
            }
            if let closest, closest.id != linkedID {
                Button("Link to nearest · #\(closest.number) \(closest.name)") {
                    link.send(.init(name: "trackEndpoint", playerID: closest.id,
                        markID: mark.id, endpoint: endpoint))
                }
                .buttonStyle(.link)
                .font(.caption)
                .help("Keep the point's current offset from #\(closest.number) \(closest.name)")
                .accessibilityLabel("Link \(title.lowercased()) to #\(closest.number) \(closest.name)")
            }
        }
        .disabled(mark.authored || !state.canEdit || inspectorConflict || !mark.keyframes.isEmpty)
        .help(mark.keyframes.isEmpty ? "Keep this point's current offset from a player" : "Saved poses are kept. Freeze motion before linking a player.")
    }
}

private struct PitchMap: View {
    let state: ReplayXIWireState
    @Binding var selectedMarkID: UUID?
    let drawKind: String
    let drawingEnabled: Bool
    @Binding var drawStart: ReplayXIWirePoint?
    @Binding var dragStart: ReplayXIWirePoint?
    @Binding var dragEnd: ReplayXIWirePoint?
    let onPitchClick: (ReplayXIWirePoint) -> Void
    let onMove: (ReplayXIWireMark, String, ReplayXIWirePoint) -> Void
    let onPlayer: (String) -> Void
    let onArcControl: (ReplayXIWireMark, ReplayXIWirePoint) -> Void
    @GestureState private var arcDrag: ReplayXIWirePoint?

    var body: some View {
        GeometryReader { geo in
            let rect = pitchRect(in: geo.size)
            ZStack {
                Color(red: 0.035, green: 0.10, blue: 0.075)
                Rectangle().fill(Color.green.opacity(0.08)).frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                Path { path in
                    path.addRect(rect)
                    path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                    let metre = rect.width / 68
                    path.addEllipse(in: CGRect(x: rect.midX - 9.15 * metre, y: rect.midY - 9.15 * metre,
                        width: 18.3 * metre, height: 18.3 * metre))
                    for top in [true, false] {
                        path.addRect(CGRect(x: rect.midX - 20.16 * metre,
                            y: top ? rect.minY : rect.maxY - 16.5 * metre,
                            width: 40.32 * metre, height: 16.5 * metre))
                        path.addRect(CGRect(x: rect.midX - 9.16 * metre,
                            y: top ? rect.minY : rect.maxY - 5.5 * metre,
                            width: 18.32 * metre, height: 5.5 * metre))
                    }
                }
                .stroke(.white.opacity(0.55), lineWidth: 1.5)
                ForEach(state.marks.filter { CoachWorkspace.isVisible($0, at: state.playhead) || $0.id == selectedMarkID }) { mark in
                    let a = screen(dragStart != nil && selectedMarkID == mark.id ? dragStart! : mark.start, rect)
                    let b = screen(dragEnd != nil && selectedMarkID == mark.id ? dragEnd! : mark.end, rect)
                    let control = selectedMarkID == mark.id ? arcDrag ?? mark.controlPoint.map { ReplayXIWirePoint(x: $0.x, z: $0.z) }
                        : mark.controlPoint.map { ReplayXIWirePoint(x: $0.x, z: $0.z) }
                    let visible = CoachWorkspace.isVisible(mark, at: state.playhead)
                    Path { path in
                        if mark.kind == "space" {
                            path.addEllipse(in: CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                width: abs(b.x - a.x), height: abs(b.y - a.y)))
                        } else if let control {
                            path.move(to: a)
                            path.addQuadCurve(to: b, control: screen(control, rect))
                        } else {
                            path.move(to: a); path.addLine(to: b)
                        }
                        if ["run", "pass", "arc", "danger"].contains(mark.kind) {
                            let origin = control.map { screen($0, rect) } ?? a
                            let angle = atan2(b.y - origin.y, b.x - origin.x)
                            for turn in [-0.5, 0.5] {
                                path.move(to: b)
                                path.addLine(to: CGPoint(x: b.x - 9 * cos(angle + turn), y: b.y - 9 * sin(angle + turn)))
                            }
                        }
                    }
                    .stroke(mark.authored ? .gray : .orange,
                            style: StrokeStyle(lineWidth: selectedMarkID == mark.id ? 3 : 2,
                                dash: mark.authored || !visible ? [5, 4] : []))
                    .opacity(visible ? 1 : 0.45)
                    .allowsHitTesting(false)
                    Circle().fill(mark.authored ? .gray : .orange)
                        .frame(width: 11, height: 11)
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                        .position(control.map { control in
                            let c = screen(control, rect)
                            return CGPoint(x: (a.x + 2 * c.x + b.x) / 4, y: (a.y + 2 * c.y + b.y) / 4)
                        } ?? CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
                        .help("Select \(mark.label)")
                        .onTapGesture { selectedMarkID = mark.id }
                        .allowsHitTesting(!drawingEnabled)
                    if selectedMarkID == mark.id, !mark.authored, state.canEdit, !drawingEnabled {
                        handle(mark, "start", at: a, rect: rect)
                        handle(mark, "end", at: b, rect: rect)
                        if let control {
                            Circle().fill(.cyan).frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.black, lineWidth: 2))
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                                .position(screen(control, rect))
                                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("pitch"))
                                    .updating($arcDrag) { value, draft, _ in draft = pitch(value.location, rect) }
                                    .onEnded { value in onArcControl(mark, pitch(value.location, rect)) })
                                .help("Drag arc control point. Height is set in the inspector.")
                                .zIndex(3)
                        }
                    }
                }
                ForEach(state.players) { player in
                    Button { onPlayer(player.id) } label: {
                    Text("\(player.number)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 23, height: 23)
                        .background(player.team == "home" ? Color.blue : Color.red, in: Circle())
                        .overlay(Circle().stroke(state.perspectiveID == player.id ? Color.white : .clear, lineWidth: 2))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(screen(player.position, rect))
                    .help("#\(player.number) \(player.name) · click for POV")
                    .accessibilityLabel("View #\(player.number) \(player.name)'s POV")
                    .allowsHitTesting(!drawingEnabled)
                }
                Circle().fill(.orange.opacity(0.3)).frame(width: 34, height: 34)
                    .overlay(Circle().stroke(.orange.opacity(0.85), lineWidth: 2))
                    .overlay(Circle().fill(.white).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.black, lineWidth: 2)))
                    .position(screen(.init(x: state.ball.x, z: state.ball.z), rect))
                    .help("Ball · \(state.ball.y.formatted(.number.precision(.fractionLength(2)))) m high")
                    .accessibilityLabel("Ball")
                    .allowsHitTesting(false)
                    .zIndex(4)
                if let drawStart {
                    Circle().fill(.orange).frame(width: 13, height: 13)
                        .position(screen(drawStart, rect))
                }
                Text("Top-down · \(drawingEnabled ? "Drawing \(CoachWorkspace.title(for: drawKind))" : "Click player → POV")")
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
            .frame(width: 28, height: 28)
            .contentShape(Circle())
            .position(point)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("pitch"))
                .onChanged { value in
                    let next = pitch(value.location, rect)
                    if endpoint == "start" { dragStart = next } else { dragEnd = next }
                }
                .onEnded { value in onMove(mark, endpoint, pitch(value.location, rect)) })
            .zIndex(3)
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
