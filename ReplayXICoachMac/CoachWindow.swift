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
    @State private var loadedMarkFingerprint: Data?
    @State private var loadedDraft: InspectorDraft?
    @State private var inspectorConflict = false
    @State private var library = "marks"
    @State private var search = ""
    @State private var activeOnly = false
    @State private var showSave = false
    @State private var showShortcuts = false
    @State private var showShape = false
    @State private var showKeys = false
    @FocusState private var timeFieldFocused: Bool

    init(selectedMarkID: UUID? = nil) {
        _selectedMarkID = State(initialValue: selectedMarkID)
    }

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
                        toolBar(state)
                        PitchMap(state: state, selectedMarkID: $selectedMarkID,
                            drawKind: drawKind, drawingEnabled: drawingEnabled, drawStart: $drawStart,
                            dragStart: $dragStart, dragEnd: $dragEnd,
                            onPitchClick: pitchClicked, onMove: moveEndpoint,
                            onPlayer: { link.send(.init(name: "pov", playerID: $0)) },
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
                        .frame(width: 340)
                }
                Divider()
                workspaceFooter(state)
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
        .onChange(of: state?.playhead, initial: true) { _, value in
            if !scrubbing, !timeFieldFocused, let value { draftTime = value }
        }
        .onChange(of: selectedMarkID, initial: true) { _, _ in loadInspector() }
        .onChange(of: timeFieldFocused) { _, focused in
            if !focused { draftTime = state?.playhead ?? 0 }
        }
        .onChange(of: state?.scenarioID) { _, _ in
            drawingEnabled = false
            drawStart = nil
            selectedMarkID = nil
            search = ""
        }
        .onExitCommand {
            drawingEnabled = false
            drawStart = nil
            dragStart = nil
            dragEnd = nil
        }
        .onChange(of: state?.canEdit) { _, canEdit in
            if canEdit != true {
                drawingEnabled = false; drawStart = nil; dragStart = nil; dragEnd = nil
            }
        }
        .onChange(of: library) { _, _ in search = "" }
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
            Label("Replay XI Coach", systemImage: "sportscourt").font(.headline)
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
                }.labelsHidden().frame(width: 190)
                if connectionTarget == "headset" {
                Picker("Headset", selection: $deviceID) {
                    Text("Select headset").tag("")
                    ForEach(link.devices) { device in Text(device.name).tag(device.id) }
                }
                .frame(width: 195)
                Button("Rescan") { link.retryDiscovery() }
                }
                SecureField("Six digit PIN", text: Bindable(link).pin)
                    .frame(width: 110)
                Button("Pair") {
                    if connectionTarget == "simulator" { link.connectToSimulator() }
                    else if let currentDevice { link.connect(to: currentDevice) }
                }
                .disabled((connectionTarget == "headset" && currentDevice == nil) ||
                    link.pin.count != 6 || !link.pin.allSatisfy(\.isNumber))
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
                Text("\(CoachWorkspace.clock(draftTime)) / \(CoachWorkspace.clock(state.duration))")
                    .monospacedDigit().font(.callout)
            }
            .controlSize(.small)
            Slider(value: $draftTime, in: 0...max(state.duration, 0.01)) { editing in
                if editing { timeFieldFocused = false }
                scrubbing = editing
                if !editing { link.send(.init(name: "seek", time: draftTime)) }
            }
            CoachMarkTimeline(state: state, selectedMarkID: selectedMarkID) { mark in
                selectedMarkID = mark.id
                link.send(.init(name: "seek", time: mark.showAt))
            }
        }
    }

    private func toolBar(_ state: ReplayXIWireState) -> some View {
        HStack(spacing: 7) {
            Button {
                drawingEnabled = false; drawStart = nil
            } label: { Image(systemName: "cursorarrow").frame(width: 22, height: 20) }
            .tint(!drawingEnabled ? .accentColor : .secondary)
            .help("Select / move · Esc").accessibilityLabel("Select or move")
            ForEach(["run", "pass", "arc", "space", "danger"], id: \.self) { kind in
                Button {
                    drawKind = kind; drawingEnabled = true; drawStart = nil
                } label: { Image(systemName: CoachWorkspace.symbol(for: kind)).frame(width: 22, height: 20) }
                .tint(drawingEnabled && drawKind == kind ? .orange : .secondary)
                .help("Draw \(CoachWorkspace.title(for: kind).lowercased()) · click two pitch points")
                .accessibilityLabel("Draw \(CoachWorkspace.title(for: kind))")
                .disabled(!state.canEdit)
            }
            Spacer(minLength: 4)
            if drawingEnabled {
                Text(drawStart == nil ? "1 · Click start" : "2 · Click end")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text(state.canEdit ? "Click a player for POV" : "Pause to annotate")
                    .font(.caption).foregroundStyle(.secondary)
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
                        TextField("Review name", text: $saveName).frame(width: 240)
                        Button("Save review") {
                            link.send(.init(name: "save", saveName: saveName.trimmingCharacters(in: .whitespacesAndNewlines)))
                            showSave = false
                        }
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
                        commitInspectorDraft()
                        link.send(.init(name: "label", markID: mark.id, label: label))
                        }
                        .disabled(mark.authored || !state.canEdit || inspectorConflict || label == mark.label)
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
                            commitInspectorDraft()
                            link.send(.init(name: "arcControl", markID: mark.id,
                                controlPoint: .init(x: control.x, y: Float(controlHeight), z: control.z)))
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
                        Text("Hide must be after Show. Both must be inside this clip.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                    Button("Apply timing") {
                        commitInspectorDraft()
                        link.send(.init(name: "window", markID: mark.id,
                            showAt: showAt, hideAt: hasHide ? hideAt : nil))
                    }
                    .disabled(mark.authored || !state.canEdit || inspectorConflict ||
                        !CoachWorkspace.validWindow(show: showAt, hide: hasHide ? hideAt : nil, duration: state.duration))
                    Button("Go to start") { link.send(.init(name: "seek", time: mark.showAt)) }
                    }
                    Divider()
                    DisclosureGroup("Motion keys · \(mark.keyframes.count)", isExpanded: $showKeys) {
                    VStack(alignment: .leading, spacing: 8) {
                    Text("Set a position, capture it, then repeat at another time.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Capture at playhead") { link.send(.init(name: "captureKey", markID: mark.id)) }
                        .disabled(mark.authored || !state.canEdit || inspectorConflict)
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
                        HStack {
                            Text("Selected \(selectedKey.formatted(.number.precision(.fractionLength(2)))) s")
                            Button("Delete key") { link.send(.init(name: "deleteKey", markID: mark.id, keyframeAt: selectedKey)) }
                                .disabled(mark.authored || !state.canEdit || inspectorConflict)
                        }
                        HStack {
                            TextField("Move to · s", value: $retimeKey, format: .number)
                            Button("Move key") { link.send(.init(name: "retimeKey", markID: mark.id, keyframeAt: selectedKey, keyframeTo: retimeKey)) }
                                .disabled(!retimeKey.isFinite || !(0...state.duration).contains(retimeKey) ||
                                    mark.keyframes.contains(where: { $0 != selectedKey && abs($0 - retimeKey) < 0.001 }))
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
                    drawingEnabled = true; drawStart = nil
                } label: { Image(systemName: "plus") }
                .help("Draw \(CoachWorkspace.title(for: drawKind).lowercased()) · ⌘N")
                .accessibilityLabel("Draw selected annotation tool")
                .disabled(!state.canEdit).keyboardShortcut("n", modifiers: .command)
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
            loadedMarkFingerprint = nil; loadedDraft = nil; inspectorConflict = false
            return
        }
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
        guard state?.canEdit == true, drawingEnabled else { return }
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
        commitInspectorDraft()
        link.send(.init(name: "geometry", markID: mark.id, start: start, end: end,
            startHeight: Float(startHeight), endHeight: Float(endHeight)))
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
                    let visible = CoachWorkspace.isVisible(mark, at: state.playhead)
                    Path { path in
                        if mark.kind == "space" {
                            path.addEllipse(in: CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                width: abs(b.x - a.x), height: abs(b.y - a.y)))
                        } else if let control = mark.controlPoint {
                            path.move(to: a)
                            path.addQuadCurve(to: b,
                                control: screen(.init(x: control.x, z: control.z), rect))
                        } else {
                            path.move(to: a); path.addLine(to: b)
                        }
                        if ["run", "pass", "arc", "danger"].contains(mark.kind) {
                            let origin = mark.controlPoint.map { screen(.init(x: $0.x, z: $0.z), rect) } ?? a
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
                        .position(mark.controlPoint.map { control in
                            let c = screen(.init(x: control.x, z: control.z), rect)
                            return CGPoint(x: (a.x + 2 * c.x + b.x) / 4, y: (a.y + 2 * c.y + b.y) / 4)
                        } ?? CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
                        .help("Select \(mark.label)")
                        .onTapGesture { selectedMarkID = mark.id }
                        .allowsHitTesting(!drawingEnabled)
                    if selectedMarkID == mark.id, !mark.authored, state.canEdit, !drawingEnabled {
                        handle(mark, "start", at: a, rect: rect)
                        handle(mark, "end", at: b, rect: rect)
                        if let control = mark.controlPoint {
                            Circle().fill(.cyan).frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.black, lineWidth: 2))
                                .position(screen(.init(x: control.x, z: control.z), rect))
                                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("pitch"))
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
                    }
                    .buttonStyle(.plain)
                    .position(screen(player.position, rect))
                    .help("#\(player.number) \(player.name) · click for POV")
                    .accessibilityLabel("View #\(player.number) \(player.name)'s POV")
                    .allowsHitTesting(!drawingEnabled)
                }
                Circle().fill(.white).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.black, lineWidth: 2))
                    .position(screen(.init(x: state.ball.x, z: state.ball.z), rect))
                    .help("Ball · \(state.ball.y.formatted(.number.precision(.fractionLength(2)))) m high")
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
