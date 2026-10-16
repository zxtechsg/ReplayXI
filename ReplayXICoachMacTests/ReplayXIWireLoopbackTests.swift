import XCTest
import Network
import SwiftUI
import AppKit
import CryptoKit
@testable import ReplayXICoachMac

@MainActor
final class ReplayXIWireLoopbackTests: XCTestCase {
    func testPairAcknowledgementStillNeedsReplayState() async throws {
        try await withPairFixture(timeout: .milliseconds(250), response: { peer, message in
            peer.send(.init(type: "result", id: message.id, ok: true))
        }) { link in
            for _ in 0..<100 {
                if !link.isConnecting { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(link.connected)
            XCTAssertFalse(link.isConnecting)
            XCTAssertNil(link.state)
            XCTAssertTrue(link.status.contains("no replay arrived"))
        }
    }

    func testUnpairedReplayStateCannotOpenWorkspace() async throws {
        var sentState = false
        try await withPairFixture(timeout: .seconds(2), response: { peer, _ in
            peer.send(.init(type: "state", state: Self.previewState))
            sentState = true
        }) { link in
            for _ in 0..<100 {
                if sentState { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertTrue(sentState)
            XCTAssertNil(link.state)
            XCTAssertFalse(link.connected)
            XCTAssertTrue(link.isConnecting)
            link.disconnect()
            XCTAssertFalse(link.isConnecting)
        }
    }

    func testPairingUsesPINAtClickAndIgnoresRepeatedPairClicks() async throws {
        var requestedPIN: String?
        var requests = 0
        try await withPairFixture(response: { peer, message in
            requestedPIN = message.pin
            requests += 1
            peer.send(.init(type: "result", id: message.id, ok: true))
            peer.send(.init(type: "state", state: Self.previewState))
        }) { link in
            link.pin = "654321"
            link.connectToSimulator() // Must not replace the in-flight fixture connection.
            for _ in 0..<100 {
                if link.connected { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(link.connected)
            XCTAssertFalse(link.isConnecting)
            XCTAssertEqual(requestedPIN, "123456")
            XCTAssertEqual(requests, 1)
        }
    }

    private func withPairFixture(timeout: Duration = .seconds(2),
        response: @escaping (ReplayXIWireConnection, ReplayXIWireMessage) -> Void,
        exercise: (ReplayXIMacLink) async throws -> Void) async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "pairing fixture ready")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        var serverPeer: ReplayXIWireConnection?
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let peer = ReplayXIWireConnection(connection)
                serverPeer = peer
                peer.onMessage = { response(peer, $0) }
                peer.start()
            }
        }
        listener.start(queue: .main)
        defer { listener.cancel(); serverPeer?.close() }
        await fulfillment(of: [ready], timeout: 5)
        let link = ReplayXIMacLink(pairingTimeout: timeout)
        link.pin = "123456"
        link.connectToSimulator(port: try XCTUnwrap(listener.port).rawValue)
        defer { link.disconnect() }
        try await exercise(link)
    }

    func testExplicitSimulatorTargetPairsAndExchangesPlaybackAndAnnotationCommands() async throws {
        // An ephemeral loopback fixture never touches a running demo's port.
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "simulator fixture ready")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        var serverPeer: ReplayXIWireConnection?
        var serverState = Self.previewState
        var commands: [ReplayXIWireCommand] = []
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let peer = ReplayXIWireConnection(connection)
                serverPeer = peer
                peer.onMessage = { message in
                    if message.type == "pair" {
                        guard message.pin == "123456" else {
                            peer.send(.init(type: "result", id: message.id, ok: false, detail: "Pairing failed"))
                            peer.closeAfterFlush()
                            return
                        }
                        peer.send(.init(type: "result", id: message.id, ok: true))
                        peer.send(.init(type: "state", state: serverState))
                    } else if let command = message.command {
                        commands.append(command)
                        XCTAssertEqual(command.expectedScenarioID, serverState.scenarioID)
                        XCTAssertEqual(command.expectedRevision, serverState.revision)
                        switch command.name {
                        case "seek": serverState.playhead = command.time ?? -1
                        case "window":
                            XCTAssertEqual(command.time, serverState.playhead)
                            XCTAssertEqual(command.markID, serverState.marks[0].id)
                            serverState.marks[0].showAt = command.showAt ?? -1
                            serverState.marks[0].hideAt = command.hideAt
                        case "pov": serverState.perspectiveID = command.playerID ?? ""
                        case "play": serverState.playing = command.value ?? false
                        default: XCTFail("Unexpected command")
                        }
                        serverState.revision += 1
                        peer.send(.init(type: "result", id: message.id, ok: true, detail: "Applied"))
                        peer.send(.init(type: "state", state: serverState))
                    }
                }
                peer.start()
            }
        }
        listener.start(queue: .main)
        defer { listener.cancel(); serverPeer?.close() }
        await fulfillment(of: [ready], timeout: 5)
        let link = ReplayXIMacLink()
        link.pin = "123456"
        link.connectToSimulator(port: try XCTUnwrap(listener.port).rawValue)
        defer { link.disconnect() }

        func awaitRevision(_ revision: UInt64) async {
            for _ in 0..<150 {
                if link.state?.revision == revision { return }
                try? await Task.sleep(for: .milliseconds(20))
            }
            XCTFail("Missing Simulator state revision \(revision)")
        }

        await awaitRevision(1)
        XCTAssertTrue(link.connected)
        XCTAssertTrue(link.devices.isEmpty, "Direct Simulator pairing must not depend on Bonjour")
        link.send(.init(name: "seek", time: 15))
        await awaitRevision(2)
        XCTAssertEqual(link.state?.playhead, 15)
        link.send(.init(name: "window", markID: serverState.marks[0].id, showAt: 15, hideAt: 22))
        await awaitRevision(3)
        XCTAssertEqual(link.state?.marks.first?.showAt, 15)
        XCTAssertEqual(link.state?.marks.first?.hideAt, 22)
        link.send(.init(name: "pov", playerID: "p9"))
        await awaitRevision(4)
        XCTAssertEqual(link.state?.perspectiveID, "p9")
        link.send(.init(name: "play", value: true))
        await awaitRevision(5)
        XCTAssertEqual(link.state?.playing, true)
        XCTAssertEqual(commands.map(\.name), ["seek", "window", "pov", "play"])
    }

    func testSimulatorStillRequiresSixDigitPIN() {
        let link = ReplayXIMacLink()
        for pin in ["", "12345", "abc123", "1234567"] {
            link.pin = pin
            link.connectToSimulator()
            XCTAssertFalse(link.connected)
            XCTAssertEqual(link.status, "Enter the six digit PIN shown in Replay XI")
        }
    }

    func testPairCommandStateAndDisconnectOverTCP() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "listener ready")
        let paired = expectation(description: "paired")
        let commanded = expectation(description: "commanded")
        let receivedState = expectation(description: "state received")
        let disconnected = expectation(description: "disconnected")
        var serverPeer: ReplayXIWireConnection?
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let peer = ReplayXIWireConnection(connection)
                serverPeer = peer
                peer.onMessage = { message in
                    if message.type == "pair", message.pin == "123456" {
                        paired.fulfill()
                        peer.send(.init(type: "result", id: message.id, ok: true))
                    } else if message.type == "command", message.command?.name == "seek",
                              message.command?.time == 12 {
                        commanded.fulfill()
                        peer.send(.init(type: "state", state: Self.sampleState))
                    }
                }
                peer.start()
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let client = ReplayXIWireConnection(NWConnection(host: "127.0.0.1", port: port, using: .tcp))
        client.onReady = { client.send(.init(type: "pair", id: UUID(), pin: "123456")) }
        client.onMessage = { message in
            if message.type == "result", message.ok == true {
                client.send(.init(type: "command", id: UUID(),
                    command: .init(name: "seek", time: 12)))
            } else if message.type == "state", message.state?.playhead == 12 {
                receivedState.fulfill()
                client.close()
            }
        }
        client.onClose = { disconnected.fulfill() }
        client.start()
        await fulfillment(of: [paired, commanded, receivedState, disconnected], timeout: 5)
        serverPeer?.close()
        listener.cancel()
    }

    func testFullMarkPayloadIsLossless() throws {
        let original = Data("{\"curve\":{\"controlOffset\":[1,2,3]},\"anchors\":[\"A\"]}".utf8)
        let mark = ReplayXIWireMark(id: UUID(), kind: "arc", start: .init(x: -2, z: 3),
            end: .init(x: 5, z: 7), startHeight: 0.5, endHeight: 1.2,
            label: "Curved run", showAt: 2, hideAt: 8, keyframes: [2, 5], authored: false,
            controlPoint: .init(x: 1, y: 2, z: 4), encodedMark: original)
        let decoded = try ReplayXIWire.decoder.decode(ReplayXIWireMark.self,
            from: ReplayXIWire.encoder.encode(mark))
        XCTAssertEqual(decoded.encodedMark, original)
        XCTAssertEqual(decoded.controlPoint, mark.controlPoint)
    }

    func testStateValueEqualityTracksEveryChangingWireComponent() throws {
        var baseline = Self.previewState
        baseline.revision = 0 // Same basis as the service's change detection.
        let canonical = try ReplayXIWire.encoder.encode(baseline)
        let decoded = try ReplayXIWire.decoder.decode(ReplayXIWireState.self, from: canonical)
        XCTAssertEqual(decoded, baseline)
        XCTAssertEqual(try ReplayXIWire.encoder.encode(decoded), canonical)

        func changed(_ field: String, _ mutate: (inout ReplayXIWireState) -> Void) throws {
            var next = baseline
            mutate(&next)
            XCTAssertNotEqual(next, baseline, field)
            XCTAssertNotEqual(try ReplayXIWire.encoder.encode(next), canonical, field)
            let line = try ReplayXIWire.encodeLine(.init(type: "state", state: next))
            var parser = ReplayXIWireParser()
            XCTAssertEqual(try parser.append(line).first?.state, next, field)
        }

        try changed("playhead") { $0.playhead += 0.25 }
        try changed("mark bytes") { $0.marks[0].encodedMark.append(0x5A) }
        try changed("key times") { $0.marks[0].keyframes[0] += 0.5 }
        try changed("arc control") { $0.marks[0].controlPoint!.y += 0.25 }
        try changed("edit gate") { $0.canEdit.toggle() }
        try changed("status") { $0.status = "Changed" }
        try changed("players") { $0.players[0].position.x += 1 }
        try changed("scenario") { $0.scenarioID = "different" }
        try changed("scenario list") { $0.scenarios[0].title = "Updated" }
        try changed("ball") { $0.ball.y += 0.25 }
    }

    func testCanonicalEncodingAndBoundedParser() throws {
        let encoded = try ReplayXIWire.encoder.encode(["z": 1, "a": 2])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "{\"a\":2,\"z\":1}")
        var parser = ReplayXIWireParser()
        let valid = try ReplayXIWire.encoder.encode(ReplayXIWireMessage(type: "pair", pin: "123456"))
        XCTAssertTrue(try parser.append(valid.prefix(4)).isEmpty)
        XCTAssertEqual(try parser.append(valid.dropFirst(4) + Data([0x0A])).first?.pin, "123456")
        var wrong = ReplayXIWireMessage(type: "pair")
        wrong.version = 99
        var versionParser = ReplayXIWireParser()
        XCTAssertThrowsError(try versionParser.append(ReplayXIWire.encoder.encode(wrong) + Data([0x0A]))) {
            XCTAssertEqual($0 as? ReplayXIWireError, .version)
        }
        var oversizedParser = ReplayXIWireParser()
        XCTAssertThrowsError(try oversizedParser.append(Data(repeating: 65,
            count: ReplayXIWire.maximumMessageBytes + 2))) {
            XCTAssertEqual($0 as? ReplayXIWireError, .oversized)
        }
        let pair = try ReplayXIWire.encodeLine(.init(type: "pair", pin: "123456",
            detail: String(repeating: "x", count: 5_000)))
        var serverParser = ReplayXIWireParser(receivesStates: false)
        XCTAssertEqual(try serverParser.append(pair + pair).count, 2)
        var commandParser = ReplayXIWireParser(receivesStates: false)
        XCTAssertThrowsError(try commandParser.append(Data(repeating: 65,
            count: ReplayXIWire.maximumCommandBytes + 1))) {
            XCTAssertEqual($0 as? ReplayXIWireError, .oversized)
        }
    }

    func testMaximumMarkAndKeyframeCorpusRoundTripsInBoundedState() throws {
        let keyframes = (0..<64).map { index in
            "{\"time\":\(index),\"start\":{\"x\":12.345,\"z\":-32.125}," +
            "\"end\":{\"x\":13.75,\"z\":-29.5},\"startElevation\":0.5," +
            "\"endElevation\":1.25,\"curve\":{\"bend\":0.3,\"lift\":2.1}}"
        }.joined(separator: ",")
        let marks = (0..<128).map { index in
            ReplayXIWireMark(id: UUID(), kind: "arc", start: .init(x: 1, z: 2),
                end: .init(x: 3, z: 4), startHeight: 0.5, endHeight: 1.25,
                label: "Mark \(index)", showAt: 0, hideAt: 64,
                keyframes: (0..<64).map(Double.init), authored: false,
                controlPoint: .init(x: 2, y: 2, z: 3),
                encodedMark: Data("{\"keyframes\":[\(keyframes)]}".utf8))
        }
        var state = Self.sampleState
        state.marks = marks
        let raw = try ReplayXIWire.encoder.encode(ReplayXIWireMessage(type: "state", state: state))
        XCTAssertGreaterThan(raw.count, ReplayXIWire.compressionThreshold)
        let line = try ReplayXIWire.encodeLine(.init(type: "state", state: state))
        XCTAssertLessThan(line.count, ReplayXIWire.maximumMessageBytes)
        var parser = ReplayXIWireParser()
        let restored = try XCTUnwrap(parser.append(line).first?.state)
        XCTAssertEqual(restored.marks.count, 128)
        XCTAssertEqual(restored.marks[127].keyframes.count, 64)
        XCTAssertEqual(restored.marks[127].encodedMark, marks[127].encodedMark)
        var serverParser = ReplayXIWireParser(receivesStates: false)
        XCTAssertThrowsError(try serverParser.append(line)) {
            XCTAssertEqual($0 as? ReplayXIWireError, .oversized)
        }
        var smallServerParser = ReplayXIWireParser(receivesStates: false)
        let smallState = try ReplayXIWire.encodeLine(.init(type: "state", state: Self.sampleState))
        XCTAssertThrowsError(try smallServerParser.append(smallState)) {
            XCTAssertEqual($0 as? ReplayXIWireError, .invalid)
        }
    }

    func testStateAboveWireLimitCompressesWithoutDroppingMarkBytes() throws {
        var state = Self.sampleState
        let original = Data(repeating: 0x41, count: ReplayXIWire.maximumMessageBytes)
        state.marks = [ReplayXIWireMark(id: UUID(), kind: "run",
            start: .init(x: 0, z: 0), end: .init(x: 1, z: 1),
            startHeight: 0, endHeight: 0, label: "Large review", showAt: 0,
            hideAt: nil, keyframes: [], authored: false, controlPoint: nil,
            encodedMark: original)]
        XCTAssertGreaterThan(try ReplayXIWire.encoder.encode(
            ReplayXIWireMessage(type: "state", state: state)).count,
            ReplayXIWire.maximumMessageBytes)
        let line = try ReplayXIWire.encodeLine(.init(type: "state", state: state))
        var parser = ReplayXIWireParser()
        XCTAssertEqual(try parser.append(line).first?.state?.marks.first?.encodedMark, original)
    }

    func testCompressedStateRejectsMalformedAndOversizedOutput() throws {
        var parser = ReplayXIWireParser()
        let bogus = ReplayXIWireMessage(type: "state", packedState: Data([1, 2, 3]),
            unpackedStateBytes: 1024)
        XCTAssertThrowsError(try parser.append(ReplayXIWire.encoder.encode(bogus) + Data([0x0A]))) {
            XCTAssertEqual($0 as? ReplayXIWireError, .invalid)
        }
        var sizeParser = ReplayXIWireParser()
        let oversized = ReplayXIWireMessage(type: "state", packedState: Data([1]),
            unpackedStateBytes: ReplayXIWire.maximumStateBytes + 1)
        XCTAssertThrowsError(try sizeParser.append(ReplayXIWire.encoder.encode(oversized) + Data([0x0A]))) {
            XCTAssertEqual($0 as? ReplayXIWireError, .invalid)
        }
        var state = Self.sampleState
        state.status = String(repeating: "A", count: ReplayXIWire.compressionThreshold)
        let compressedLine = try ReplayXIWire.encodeLine(.init(type: "state", state: state))
        let original = try ReplayXIWire.decoder.decode(ReplayXIWireMessage.self,
            from: compressedLine.dropLast())
        XCTAssertNotNil(original.packedState)
        var tooSmall = original
        tooSmall.unpackedStateBytes! -= 1
        var tooSmallParser = ReplayXIWireParser()
        XCTAssertThrowsError(try tooSmallParser.append(ReplayXIWire.encoder.encode(tooSmall) + Data([0x0A]))) {
            XCTAssertEqual($0 as? ReplayXIWireError, .invalid)
        }
        var truncated = original
        truncated.packedState!.removeLast()
        truncated.packedStateDigest = Data(SHA256.hash(data: truncated.packedState!))
        var truncatedParser = ReplayXIWireParser()
        XCTAssertThrowsError(try truncatedParser.append(ReplayXIWire.encoder.encode(truncated) + Data([0x0A]))) {
            XCTAssertEqual($0 as? ReplayXIWireError, .invalid)
        }
        var trailing = original
        trailing.packedState!.append(0x00)
        trailing.packedStateDigest = Data(SHA256.hash(data: trailing.packedState!))
        var trailingParser = ReplayXIWireParser()
        XCTAssertThrowsError(try trailingParser.append(ReplayXIWire.encoder.encode(trailing) + Data([0x0A]))) {
            XCTAssertEqual($0 as? ReplayXIWireError, .invalid)
        }
    }

    func testRejectedPairingKeepsFailureVisibleAfterClose() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "listener ready")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        var serverPeer: ReplayXIWireConnection?
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let peer = ReplayXIWireConnection(connection)
                serverPeer = peer
                peer.onMessage = { message in
                    guard message.type == "pair" else { return }
                    peer.send(.init(type: "result", id: message.id, ok: false, detail: "Pairing failed"))
                    peer.closeAfterFlush()
                }
                peer.start()
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)
        let link = ReplayXIMacLink()
        link.pin = "123456"
        link.connect(to: .init(id: "fixture", name: "Fixture",
            endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(listener.port))))
        let rejected = expectation(description: "rejection visible")
        Task { @MainActor in
            for _ in 0..<150 {
                if link.status == "Pairing failed", !link.connected { rejected.fulfill(); return }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        await fulfillment(of: [rejected], timeout: 5)
        link.disconnect()
        serverPeer?.close()
        listener.cancel()
    }

    func testPairedCoachWindowRendersAtDesktopAndMinimumSizes() async throws {
        print("Mac window QA: starting fixture")
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "fixture listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        var serverPeer: ReplayXIWireConnection?
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let peer = ReplayXIWireConnection(connection)
                serverPeer = peer
                peer.onMessage = { message in
                    if message.type == "pair", message.pin == "123456" {
                        peer.send(.init(type: "result", id: message.id, ok: true))
                        peer.send(.init(type: "state", state: Self.previewState))
                    }
                }
                peer.start()
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)

        let link = ReplayXIMacLink()
        link.pin = "123456"
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: try XCTUnwrap(listener.port))
        link.connect(to: .init(id: "loopback", name: "UI fixture", endpoint: endpoint))
        let paired = expectation(description: "paired view state")
        Task { @MainActor in
            for _ in 0..<150 {
                if link.state != nil { paired.fulfill(); return }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        await fulfillment(of: [paired], timeout: 5)
        print("Mac window QA: paired fixture")
        XCTAssertEqual(link.state?.marks.count, 2)
        XCTAssertEqual(link.state?.players.count, 3)

        let output = URL(fileURLWithPath: "/private/tmp/replayxi-mac-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (width, height) in [(1360, 840), (1060, 700)] {
            print("Mac window QA: rendering \(width)")
            let view = CoachWindow(selectedMarkID: Self.previewState.marks.first?.id).environment(link)
                .frame(width: CGFloat(width), height: CGFloat(height))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
            let image = try XCTUnwrap(renderer.nsImage)
            print("Mac window QA: image renderer done")
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            XCTAssertEqual(bitmap.pixelsWide, width)
            XCTAssertEqual(bitmap.pixelsHigh, height)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 10_000)
            try png.write(to: output.appendingPathComponent("replayxi-coach-\(width)x\(height).png"))

            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let hosted = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: hosted)
            print("Mac window QA: host cache done")
            let hostedPNG = try XCTUnwrap(hosted.representation(using: .png, properties: [:]))
            try hostedPNG.write(to: output.appendingPathComponent("replayxi-coach-host-\(width)x\(height).png"))

            // Bitmap snapshots verify layout, but system glass/inspector layers
            // require a compositor screenshot for visual QA.
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: height),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Replay XI Coach · QA sample data"
            window.contentView = host
            // Do not activate another copy of the app while a demo is open.
            // A window-backed view can draw without taking keyboard focus.
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            print("Mac window QA: native window ready")
            if let seconds = Double(ProcessInfo.processInfo.environment["REPLAYXI_QA_HOLD_SECONDS"] ?? ""), seconds > 0 {
                // Opt-in only: leave the sample window visible for a CUA capture.
                try? await Task.sleep(for: .seconds(min(seconds, 30)))
            }
            host.displayIfNeeded()
            let windowBitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: windowBitmap)
            try XCTUnwrap(windowBitmap.representation(using: .png, properties: [:])).write(to:
                output.appendingPathComponent("replayxi-coach-window-host-\(width)x\(height).png"))
            window.orderOut(nil)
            print("Mac window QA: native window done")
        }
        link.disconnect()
        serverPeer?.close()
        listener.cancel()
    }

    func testDisconnectedHeaderRendersAtTop() throws {
        let link = ReplayXIMacLink()
        let view = CoachWindow().environment(link).frame(width: 1360, height: 840)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1360, height: 840)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        let output = URL(fileURLWithPath: "/private/tmp/replayxi-mac-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try png.write(to: output.appendingPathComponent("replayxi-coach-disconnected-1360x840.png"))
    }

    private static var sampleState: ReplayXIWireState {
        .init(revision: 1, scenarioID: "test", playhead: 12, playing: false,
            rate: 1, viewMode: "tacticalTable", perspectiveID: "player", duration: 60,
            scenarios: [.init(id: "test", title: "Test", duration: 60)], players: [],
            ball: .init(x: 0, y: 0.11, z: 0), marks: [],
            canUndo: false, canRedo: false, canSave: true, canEdit: true, status: "Ready")
    }

    private static var previewState: ReplayXIWireState {
        let arc = ReplayXIWireMark(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: "arc", start: .init(x: -20, z: -28), end: .init(x: 8, z: 18),
            startHeight: 0.5, endHeight: 1.2, label: "Curved overlap", showAt: 7,
            hideAt: 20, keyframes: [7, 12, 18], authored: false,
            controlPoint: .init(x: -23, y: 3.2, z: 4), encodedMark: Data("{}".utf8))
        let pass = ReplayXIWireMark(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            kind: "pass", start: .init(x: 10, z: -3), end: .init(x: 22, z: 14),
            startHeight: 0, endHeight: 0, label: "Release the lane", showAt: 11,
            hideAt: 17, keyframes: [], authored: true,
            controlPoint: nil, encodedMark: Data("{}".utf8))
        return ReplayXIWireState(revision: 1, scenarioID: "preview", playhead: 12,
            playing: false, rate: 1, viewMode: "tacticalTable", perspectiveID: "p7",
            duration: 36, scenarios: [.init(id: "preview", title: "Counterattack", duration: 36)],
            players: [
                .init(id: "p7", name: "Left winger", number: 7, team: "home", position: .init(x: -18, z: -20)),
                .init(id: "p9", name: "Striker", number: 9, team: "home", position: .init(x: 4, z: 5)),
                .init(id: "p4", name: "Defender", number: 4, team: "away", position: .init(x: 16, z: 12))
            ], ball: .init(x: 2, y: 0.11, z: 1), marks: [arc, pass],
            canUndo: true, canRedo: false, canSave: true, canEdit: true,
            status: "Sample UI state")
    }
}
