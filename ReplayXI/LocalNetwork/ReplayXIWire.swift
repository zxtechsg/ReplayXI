import Foundation
import Network
import Compression
import CryptoKit

// Shared by the visionOS service and the separate macOS app. A line is one
// bounded JSON message; the full encoded CoachMark is carried without loss.
enum ReplayXIWire {
    static let serviceType = "_replayxi-coach._tcp"
    /// Explicit same-Mac Simulator route. The Simulator server binds loopback
    /// only; the physical headset continues to use Bonjour on its local LAN.
    nonisolated static let simulatorPort: UInt16 = 49_311
    static let maximumMessageBytes = 4 * 1024 * 1024
    static let maximumCommandBytes = 8 * 1024
    static let maximumStateBytes = 16 * 1024 * 1024
    static let compressionThreshold = 128 * 1024
    static let protocolVersion = 2
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    static let decoder = JSONDecoder()

    /// State compression is transport-only. The decoded DTO still contains
    /// every full CoachMark byte and keyframe.
    static func encodeLine(_ source: ReplayXIWireMessage) throws -> Data {
        var message = source
        if message.type == "state", let state = message.state {
            let raw = try encoder.encode(state)
            guard raw.count <= maximumStateBytes else { throw ReplayXIWireError.oversized }
            if raw.count >= compressionThreshold, let packed = try? compress(raw) {
                var candidate = message
                candidate.packedState = packed
                candidate.packedStateLength = packed.count
                candidate.unpackedStateBytes = raw.count
                candidate.packedStateDigest = Data(SHA256.hash(data: packed))
                candidate.state = nil
                if try encoder.encode(candidate).count < raw.count { message = candidate }
            }
        }
        var line = try encoder.encode(message)
        guard line.count <= maximumMessageBytes else { throw ReplayXIWireError.oversized }
        line.append(0x0A)
        return line
    }

    private static func compress(_ source: Data) throws -> Data {
        var destination = Data(count: source.count + 1024)
        let written = source.withUnsafeBytes { input in
            destination.withUnsafeMutableBytes { output in
                compression_encode_buffer(output.bindMemory(to: UInt8.self).baseAddress!,
                    output.count, input.bindMemory(to: UInt8.self).baseAddress!,
                    input.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard written > 0 else { throw ReplayXIWireError.oversized }
        destination.removeSubrange(written..<destination.count)
        return destination
    }

    static func unpack(_ message: inout ReplayXIWireMessage) throws {
        guard let packed = message.packedState else {
            guard message.unpackedStateBytes == nil, message.packedStateLength == nil,
                  message.packedStateDigest == nil,
                  message.type != "state" || message.state != nil else {
                throw ReplayXIWireError.invalid
            }
            return
        }
        guard message.type == "state", message.state == nil,
              let size = message.unpackedStateBytes,
              (1...maximumStateBytes).contains(size), !packed.isEmpty,
              message.packedStateLength == packed.count,
              let digest = message.packedStateDigest, digest.count == 32,
              Data(SHA256.hash(data: packed)) == digest else {
            throw ReplayXIWireError.invalid
        }
        // One extra output byte distinguishes an honest exact size from a
        // compressed stream that only filled the caller's declared buffer.
        var output = Data(count: size + 1)
        var sentinel: UInt8 = 0
        let complete = withUnsafeMutablePointer(to: &sentinel) { pointer in
            var stream = compression_stream(dst_ptr: pointer, dst_size: 0,
                src_ptr: UnsafePointer(pointer), src_size: 0, state: nil)
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE,
                COMPRESSION_LZFSE) == COMPRESSION_STATUS_OK else { return false }
            defer { compression_stream_destroy(&stream) }
            return packed.withUnsafeBytes { input in
                output.withUnsafeMutableBytes { destination in
                    stream.src_ptr = input.bindMemory(to: UInt8.self).baseAddress!
                    stream.src_size = input.count
                    stream.dst_ptr = destination.bindMemory(to: UInt8.self).baseAddress!
                    stream.dst_size = destination.count
                    while true {
                        let previousInput = stream.src_size
                        let previousOutput = stream.dst_size
                        let status = compression_stream_process(&stream,
                            Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                        if status == COMPRESSION_STATUS_END {
                            return stream.src_size == 0 &&
                                destination.count - stream.dst_size == size
                        }
                        guard status == COMPRESSION_STATUS_OK, stream.dst_size > 0,
                              stream.src_size != previousInput || stream.dst_size != previousOutput else {
                            return false
                        }
                    }
                }
            }
        }
        guard complete else { throw ReplayXIWireError.invalid }
        output.removeLast()
        guard let state = try? decoder.decode(ReplayXIWireState.self, from: output) else {
            throw ReplayXIWireError.invalid
        }
        message.state = state
        message.packedState = nil
        message.packedStateLength = nil
        message.unpackedStateBytes = nil
        message.packedStateDigest = nil
    }
}

struct ReplayXIWirePoint: Codable, Equatable {
    var x: Float
    var z: Float
}

struct ReplayXIWirePoint3: Codable, Equatable {
    var x: Float
    var y: Float
    var z: Float
}

struct ReplayXIWirePlayer: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var number: Int
    var team: String
    var position: ReplayXIWirePoint
    var facingDegrees: Float? = nil
}

struct ReplayXIWireScenario: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var duration: Double
}

struct ReplayXIWireMark: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: String
    var start: ReplayXIWirePoint
    var end: ReplayXIWirePoint
    var startHeight: Float
    var endHeight: Float
    var label: String
    var showAt: Double
    var hideAt: Double?
    var keyframes: [Double]
    var authored: Bool
    var controlPoint: ReplayXIWirePoint3?
    /// Exact CoachMark Codable bytes, including anchors, curves and keyframes.
    var encodedMark: Data
    var startPlayerID: String? = nil
    var endPlayerID: String? = nil
}

struct ReplayXIWireState: Codable, Equatable {
    var revision: UInt64
    var scenarioID: String
    var playhead: Double
    var playing: Bool
    var rate: Double
    var viewMode: String
    var perspectiveID: String
    var duration: Double
    var scenarios: [ReplayXIWireScenario]
    var players: [ReplayXIWirePlayer]
    var ball: ReplayXIWirePoint3
    var marks: [ReplayXIWireMark]
    var canUndo: Bool
    var canRedo: Bool
    var canSave: Bool
    var canEdit: Bool
    var status: String
}

struct ReplayXIWireCommand: Codable {
    var name: String
    var expectedRevision: UInt64? = nil
    var expectedScenarioID: String? = nil
    var scenarioID: String? = nil
    var time: Double? = nil
    var rate: Double? = nil
    var value: Bool? = nil
    var viewMode: String? = nil
    var playerID: String? = nil
    var markID: UUID? = nil
    var kind: String? = nil
    var start: ReplayXIWirePoint? = nil
    var end: ReplayXIWirePoint? = nil
    var startHeight: Float? = nil
    var endHeight: Float? = nil
    var controlPoint: ReplayXIWirePoint3? = nil
    var label: String? = nil
    var showAt: Double? = nil
    var hideAt: Double? = nil
    var keyframeAt: Double? = nil
    var keyframeTo: Double? = nil
    var saveName: String? = nil
    var endpoint: String? = nil
    var recordMotion: Bool? = nil
    /// One-shot virtual view direction. Never reads or locks physical eye gaze.
    var lookTarget: String? = nil
}

struct ReplayXIWireMessage: Codable {
    var version: Int = ReplayXIWire.protocolVersion
    var type: String
    var id: UUID? = nil
    var pin: String? = nil
    var command: ReplayXIWireCommand? = nil
    var state: ReplayXIWireState? = nil
    var packedState: Data? = nil
    var packedStateLength: Int? = nil
    var unpackedStateBytes: Int? = nil
    /// Unkeyed integrity check for truncated/extra bytes, not authentication.
    var packedStateDigest: Data? = nil
    var ok: Bool? = nil
    var detail: String? = nil
    /// The authoritative state produced by this command. Results can overtake
    /// coalesced state packets; clients wait for this revision before editing.
    var stateRevision: UInt64? = nil
}

enum ReplayXIWireError: Error, Equatable {
    case oversized
    case invalid
    case version

    var detail: String {
        switch self {
        case .oversized: "Replay XI message exceeds 4 MB limit"
        case .invalid: "Invalid Replay XI message"
        case .version: "Replay XI versions differ"
        }
    }
}

struct ReplayXIWireParser {
    private var input = Data()
    private let receivesStates: Bool
    private let maximumBytes: Int

    init(receivesStates: Bool = true) {
        self.receivesStates = receivesStates
        maximumBytes = receivesStates ? ReplayXIWire.maximumMessageBytes : ReplayXIWire.maximumCommandBytes
    }

    mutating func append(_ bytes: Data) throws -> [ReplayXIWireMessage] {
        var messages: [ReplayXIWireMessage] = []
        var start = bytes.startIndex
        while let newline = bytes[start...].firstIndex(of: 0x0A) {
            let fragment = bytes[start..<newline]
            guard input.count + fragment.count <= maximumBytes else { throw ReplayXIWireError.oversized }
            input.append(contentsOf: fragment)
            guard var message = try? ReplayXIWire.decoder.decode(ReplayXIWireMessage.self, from: input) else {
                throw ReplayXIWireError.invalid
            }
            input.removeAll(keepingCapacity: true)
            guard message.version == ReplayXIWire.protocolVersion else {
                throw ReplayXIWireError.version
            }
            guard receivesStates || message.type != "state" else {
                throw ReplayXIWireError.invalid
            }
            try ReplayXIWire.unpack(&message)
            messages.append(message)
            start = bytes.index(after: newline)
        }
        let tail = bytes[start...]
        guard input.count + tail.count <= maximumBytes else { throw ReplayXIWireError.oversized }
        input.append(contentsOf: tail)
        return messages
    }
}

@MainActor
final class ReplayXIWireConnection {
    let connection: NWConnection
    var onMessage: ((ReplayXIWireMessage) -> Void)?
    var onClose: (() -> Void)?
    var onReady: (() -> Void)?
    var onProtocolError: ((String) -> Void)?
    var onTransportError: ((String) -> Void)?
    private var parser: ReplayXIWireParser
    private var closed = false
    private var closingAfterFlush = false
    private var sending = false
    private var pendingCritical: [Data] = []
    private var pendingState: Data?

    init(_ connection: NWConnection, receivesStates: Bool = true) {
        self.connection = connection
        parser = ReplayXIWireParser(receivesStates: receivesStates)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .ready = state { self.onReady?() }
                if case let .failed(error) = state {
                    self.onTransportError?(error.localizedDescription)
                    self.close()
                }
                if case .cancelled = state { self.close() }
            }
        }
        connection.start(queue: .main)
        receive()
    }

    @discardableResult
    func send(_ message: ReplayXIWireMessage) -> Bool {
        guard !closed, let line = try? ReplayXIWire.encodeLine(message) else { return false }
        if message.type == "state" {
            pendingState = line
        } else {
            guard pendingCritical.count < 16 else { close(); return false }
            pendingCritical.append(line)
        }
        drain()
        return true
    }

    func closeAfterFlush() {
        closingAfterFlush = true
        drain()
    }

    private func drain() {
        guard !sending, !closed else { return }
        let line: Data
        if !pendingCritical.isEmpty { line = pendingCritical.removeFirst() }
        else if let state = pendingState { line = state; pendingState = nil }
        else {
            if closingAfterFlush { close() }
            return
        }
        sending = true
        connection.send(content: line, completion: .contentProcessed { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sending = false
                if error != nil { self.close() } else { self.drain() }
            }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] bytes, _, done, error in
            Task { @MainActor [weak self] in
                guard let self, !self.closed, !self.closingAfterFlush else { return }
                do {
                    let messages = try self.parser.append(bytes ?? Data())
                    for message in messages {
                        self.onMessage?(message)
                        if self.closed { return }
                    }
                } catch let wireError as ReplayXIWireError {
                    self.onProtocolError?(wireError.detail)
                    self.close()
                    return
                } catch {
                    self.onProtocolError?("Invalid Replay XI message")
                    self.close()
                    return
                }
                if error != nil || done { self.close() } else { self.receive() }
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?()
    }
}
