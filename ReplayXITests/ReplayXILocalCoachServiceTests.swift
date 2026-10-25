import XCTest
import Network
@testable import ReplayXI

@MainActor
final class ReplayXILocalCoachServiceTests: XCTestCase {
    func testReleasingServiceStopsPublisherWithoutExplicitStop() async throws {
        #if targetEnvironment(simulator)
        var service: ReplayXILocalCoachService? = ReplayXILocalCoachService(store: ReplayStore())
        service?.simulatorPortOverrideForTesting = 0
        service?.start()
        _ = try await readyPort(try XCTUnwrap(service))
        let publisher = try XCTUnwrap(service?.publisherForTesting)
        defer { publisher.cancel(); service?.stop() }
        let stopped = expectation(description: "Released service stops its publisher")
        Task { await publisher.value; stopped.fulfill() }
        weak var releasedService = service
        service = nil
        XCTAssertNil(releasedService)
        await fulfillment(of: [stopped], timeout: 2)
        #endif
    }

    func testStoppingPairedServiceReleasesItsPeer() async throws {
        #if targetEnvironment(simulator)
        let service = ReplayXILocalCoachService(store: ReplayStore())
        service.simulatorPortOverrideForTesting = 0
        service.start()
        defer { service.stop() }
        let port = try await readyPort(service)
        let pin = service.pin
        let paired = expectation(description: "PIN accepted")
        let client = ReplayXIWireConnection(NWConnection(host: .ipv4(.loopback), port: port, using: .tcp))
        defer { client.close() }
        client.onReady = { [weak client] in client?.send(.init(type: "pair", pin: pin)) }
        client.onMessage = { message in
            if message.type == "result", message.ok == true { paired.fulfill() }
        }
        client.start()
        await fulfillment(of: [paired], timeout: 5)
        weak var releasedPeer = service.peerForTesting
        XCTAssertNotNil(releasedPeer)
        // Also break the old self-cycle on a failed regression run.
        defer { releasedPeer?.onMessage = nil }
        service.stop()
        for _ in 0..<50 where releasedPeer != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(releasedPeer, "A closed peer must not retain its own message callback")
        #endif
    }

    func testStoppingLinkRotatesPairingPINAndIgnoresQueuedListenerStatus() async {
        let service = ReplayXILocalCoachService(store: ReplayStore())
        service.simulatorPortOverrideForTesting = 0
        let first = service.pin
        service.start()
        service.stop()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNotEqual(service.pin, first)
        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(service.status, "Mac link off")
    }

    func testWirePlayersAndLinkedXYZArcMatchPresentedImpactAndIdealHistory() async throws {
        #if targetEnvironment(simulator)
        for ideal in [false, true] {
            let store = ReplayStore()
            store.prepareForLocalExperience()
            store.selectScenario(id: ideal ? "triangle-lock" : "everyone-with-seven", broadcast: false)
            if ideal {
                store.setShapeFocusStage(.ideal, broadcast: false)
            } else {
                store.setViewMode(.tacticalTable, broadcast: false)
                store.seek(to: 15, broadcast: false)
            }
            let player = try XCTUnwrap(store.selectedScenario.player(id: ideal ? "navy-rb" : "red-lb"))
            let time = store.playhead
            let origin = store.presentedPlayerPose(for: player, at: time).position
            let mark = try XCTUnwrap(store.addMacCoachMark(kind: .arc,
                start: origin, end: .init(x: origin.x - 3, z: origin.z - 4),
                startElevation: 1, endElevation: 2, label: "Linked XYZ"))
            XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: player.id))
            XCTAssertTrue(store.updateCoachMarkArcControlPoint(id: mark.id,
                point: [origin.x - 2, 5, origin.z - 1]))

            let service = ReplayXILocalCoachService(store: store)
            service.simulatorPortOverrideForTesting = 0
            service.start()
            defer { service.stop() }
            let port = try await readyPort(service)
            let pin = service.pin
            let client = ReplayXIWireConnection(NWConnection(host: .ipv4(.loopback), port: port, using: .tcp))
            defer { client.close() }
            var received: ReplayXIWireState?
            client.onReady = { [weak client] in client?.send(.init(type: "pair", pin: pin)) }
            client.onMessage = { message in
                if let state = message.state { received = state }
            }
            client.start()

            for offset in [0.0, 0.5, 0.0] {
                store.seek(to: time + offset, broadcast: false)
                if offset > 0 { XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: nil)) }
                let current = try XCTUnwrap(store.marks.first { $0.id == mark.id })
                let encoded = try ReplayXIWire.encoder.encode(current)
                for _ in 0..<100 {
                    if received?.playhead == store.playhead,
                       received?.marks.first(where: { $0.id == mark.id })?.encodedMark == encoded { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                let state = try XCTUnwrap(received)
                XCTAssertEqual(state.playhead, store.playhead)
                XCTAssertEqual(state.players.count, store.selectedScenario.players.count)
                for wirePlayer in state.players {
                    let track = try XCTUnwrap(store.selectedScenario.player(id: wirePlayer.id))
                    let expected = store.presentedPlayerPose(for: track, at: state.playhead)
                    XCTAssertEqual(wirePlayer.position.x, expected.position.x)
                    XCTAssertEqual(wirePlayer.position.z, expected.position.z)
                    XCTAssertEqual(wirePlayer.facingDegrees, expected.facingDegrees)
                }
                let wireMark = try XCTUnwrap(state.marks.first { $0.id == mark.id })
                XCTAssertEqual(wireMark.encodedMark, encoded)
                let pose = current.resolvingTrackGeometry(in: store.selectedScenario, at: state.playhead,
                    presentedPlayerPoses: store.playerPresentation.poses(in: store.selectedScenario, at: state.playhead))
                XCTAssertEqual(wireMark.start.x, pose.start.x)
                XCTAssertEqual(wireMark.start.z, pose.start.z)
                XCTAssertEqual(wireMark.end.x, pose.end.x)
                XCTAssertEqual(wireMark.end.z, pose.end.z)
                XCTAssertEqual(wireMark.startHeight, pose.resolvedStartElevation)
                XCTAssertEqual(wireMark.endHeight, pose.resolvedEndElevation)
                let control = pose.resolvedCurve.controlPoint(for: pose)
                let wireControl = try XCTUnwrap(wireMark.controlPoint)
                XCTAssertEqual(wireControl.x, control.x, accuracy: 0.0001)
                XCTAssertEqual(wireControl.y, control.y, accuracy: 0.0001)
                XCTAssertEqual(wireControl.z, control.z, accuracy: 0.0001)
                let sampled = current.sampled(at: state.playhead)
                XCTAssertEqual(wireMark.startPlayerID, sampled.startTrackAnchor?.playerID)
                XCTAssertEqual(wireMark.endPlayerID, sampled.endTrackAnchor?.playerID)
            }
        }
        #endif
    }

    func testSimulatorListenerBindsOnlyLoopbackWithoutBonjour() throws {
        let parameters = ReplayXILocalCoachService.listenerParameters(simulatorOnly: true)
        XCTAssertEqual(parameters.requiredInterfaceType, .loopback)
        XCTAssertFalse(parameters.includePeerToPeer)
        XCTAssertEqual(parameters.requiredLocalEndpoint,
            .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: ReplayXIWire.simulatorPort)!))
        XCTAssertNil(ReplayXILocalCoachService.advertisedService(simulatorOnly: true))
        XCTAssertTrue((49_152...65_535).contains(Int(ReplayXIWire.simulatorPort)))
        let device = ReplayXILocalCoachService.listenerParameters(simulatorOnly: false)
        XCTAssertNil(device.requiredLocalEndpoint)
        XCTAssertNotEqual(device.requiredInterfaceType, .loopback)
        XCTAssertFalse(device.includePeerToPeer)
        XCTAssertEqual(ReplayXILocalCoachService.advertisedService(simulatorOnly: false)?.type,
                       ReplayXIWire.serviceType)
    }

    func testSimulatorPortConflictExplainsHowToRecover() {
        let message = ReplayXILocalCoachService.failureMessage(.posix(.EADDRINUSE), simulatorOnly: true)
        XCTAssertTrue(message.contains("Stop Mac link in the other Replay XI Simulator"))
        XCTAssertTrue(message.contains("retry"))
    }

    func testOccupiedSimulatorPortStopsCleanlyAndCanBeRetried() async throws {
        #if targetEnvironment(simulator)
        let first = ReplayXILocalCoachService(store: ReplayStore())
        first.simulatorPortOverrideForTesting = 0
        first.start()
        defer { first.stop() }
        let occupied = try await readyPort(first)
        let second = ReplayXILocalCoachService(store: ReplayStore())
        second.simulatorPortOverrideForTesting = occupied.rawValue
        second.start()
        defer { second.stop() }
        for _ in 0..<100 {
            if !second.isRunning { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertFalse(second.isRunning, "A busy port must expose Start/Retry, not a stuck running link")
        XCTAssertNil(second.listeningPort)
        XCTAssertTrue(second.status.contains("Stop Mac link in the other Replay XI Simulator"), second.status)
        first.stop()
        try await Task.sleep(for: .milliseconds(100))
        second.start()
        let retried = try await readyPort(second)
        XCTAssertEqual(retried, occupied)
        XCTAssertTrue(second.isRunning)
        #endif
    }

    func testSimulatorPairsAndSeeksOverPINProtectedLoopback() async throws {
        #if targetEnvironment(simulator)
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.setPlaying(false)
        let service = ReplayXILocalCoachService(store: store)
        service.simulatorPortOverrideForTesting = 0
        XCTAssertNil(service.listeningPort)
        XCTAssertFalse(service.isRunning)
        let pin = service.pin
        service.start()
        defer { service.stop() }
        let port = try await readyPort(service)
        let paired = expectation(description: "PIN accepted")
        let sought = expectation(description: "Exact replay state returned after seek")
        let pairID = UUID(), seekID = UUID()
        let client = ReplayXIWireConnection(NWConnection(host: .ipv4(.loopback), port: port, using: .tcp))
        defer { client.close() }
        client.onReady = { [weak client] in client?.send(.init(type: "pair", id: pairID, pin: pin)) }
        var receivedSeekState = false
        client.onMessage = { [weak client] message in
            if message.type == "result", message.id == pairID {
                XCTAssertEqual(message.ok, true)
                paired.fulfill()
                client?.send(.init(type: "command", id: seekID, command: .init(name: "seek", time: 2)))
            } else if message.type == "state", message.state?.playhead == 2, !receivedSeekState {
                receivedSeekState = true
                sought.fulfill()
            }
        }
        client.start()
        await fulfillment(of: [paired, sought], timeout: 5)
        XCTAssertTrue(service.isPaired)
        XCTAssertNotEqual(service.pin, pin, "The visible pairing PIN remains single-use on loopback")
        XCTAssertEqual(store.playhead, 2)
        service.stop()
        XCTAssertNil(service.listeningPort)
        XCTAssertFalse(service.isRunning)
        #endif
    }

    func testSimulatorRejectsCommandsWithoutThePIN() async throws {
        #if targetEnvironment(simulator)
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.setPlaying(false)
        let service = ReplayXILocalCoachService(store: store)
        service.simulatorPortOverrideForTesting = 0
        service.start()
        defer { service.stop() }
        let port = try await readyPort(service)
        let rejected = expectation(description: "Unauthenticated command rejected")
        let closed = expectation(description: "Unauthenticated connection closed")
        let client = ReplayXIWireConnection(NWConnection(host: .ipv4(.loopback), port: port, using: .tcp))
        defer { client.close() }
        client.onReady = { [weak client] in
            client?.send(.init(type: "command", id: UUID(), command: .init(name: "seek", time: 2)))
        }
        client.onMessage = { message in
            if message.type == "result" {
                XCTAssertEqual(message.ok, false)
                rejected.fulfill()
            }
        }
        client.onClose = { closed.fulfill() }
        client.start()
        await fulfillment(of: [rejected, closed], timeout: 5)
        XCTAssertFalse(service.isPaired)
        XCTAssertEqual(store.playhead, 0)
        #endif
    }

    private func readyPort(_ service: ReplayXILocalCoachService) async throws -> NWEndpoint.Port {
        for _ in 0..<100 {
            if let raw = service.listeningPort, let port = NWEndpoint.Port(rawValue: raw) { return port }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Listener did not become ready: \(service.status)")
        return try XCTUnwrap(service.listeningPort.flatMap(NWEndpoint.Port.init(rawValue:)))
    }

    func testServiceStaysOffUntilStartedAndRejectsStaleOrPlayingEdits() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let service = ReplayXILocalCoachService(store: store)
        XCTAssertFalse(service.isRunning)
        var create = edit("create", store: store)
        create.kind = "run"
        create.start = .init(x: 0, z: 0)
        create.end = .init(x: 5, z: 5)
        create.startHeight = 0
        create.endHeight = 0
        create.label = "Mac run"

        store.setPlaying(true)
        XCTAssertFalse(service.apply(create))
        store.setPlaying(false)
        store.seek(to: 3)
        XCTAssertFalse(service.apply(create)) // wrong time
        create.time = store.playhead
        create.expectedRevision = 1
        XCTAssertFalse(service.apply(create)) // wrong revision
        create.expectedRevision = 0
        XCTAssertTrue(service.apply(create))
        let mark = try XCTUnwrap(store.marks.first { $0.label == "Mac run" })

        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        XCTAssertFalse(service.apply(.init(name: "play", value: true)))
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))

        let clear = edit("clear", store: store)
        XCTAssertTrue(service.apply(clear))
        XCTAssertFalse(store.marks.contains { $0.id == mark.id })
        XCTAssertEqual(store.marks.map(\.id), store.selectedScenario.coachMarks.map(\.id))
    }

    func testPlayerLabelUsesStoreAndKeepsAuthoredOverlays() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let service = ReplayXILocalCoachService(store: store)
        let player = try XCTUnwrap(store.selectedScenario.players.first)
        var command = edit("labelPlayer", store: store)
        command.playerID = player.id
        XCTAssertTrue(service.apply(command))
        XCTAssertTrue(store.marks.contains { $0.kind == .playerLabel && $0.playerID == player.id })
        XCTAssertTrue(service.apply(edit("clear", store: store)))
        XCTAssertEqual(store.marks.map(\.id), store.selectedScenario.coachMarks.map(\.id))
    }

    private func edit(_ name: String, store: ReplayStore) -> ReplayXIWireCommand {
        var command = ReplayXIWireCommand(name: name)
        command.expectedRevision = 0
        command.expectedScenarioID = store.selectedScenarioID
        command.time = store.playhead
        return command
    }
}
