import ClickyCore
import Foundation

/// Connection lifecycle reported upward. Chunk 11 maps this onto
/// ClickyCore.SessionStateMachine (ready → .listening, reconnecting → .reconnecting,
/// stopped(reason) → .stopRequested(reason)).
public enum GeminiConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case ready
    case reconnecting(attempt: Int)
    case stopped(reason: StopReason)
}

public enum GeminiClientError: Error, Equatable {
    case notReady
    case alreadyStarted
    case transportUnavailable
    case setupTimeout
}

/// Latency-meter hooks owned by this chunk (T3/T4/T6/T8/T12; Validation 01 §4.1).
/// The observer (chunk 12) timestamps each marker on receipt.
public enum GeminiMarker: Equatable, Sendable {
    case audioStreamEndSent                                  // T3
    case firstAudioFrameReceived                             // T4 — once per turn
    case interruptedReceived                                 // T6
    case toolCallReceived(id: String)                        // T8
    case toolResponseSent(id: String)                        // T12
    case toolCallDropped(id: String, reason: String)         // local fail-closed
}

public struct GeminiToolHandlerResult: Sendable, Equatable {
    public let payload: JSONValue
    public let scheduling: GeminiScheduling
    public init(payload: JSONValue, scheduling: GeminiScheduling) {
        self.payload = payload
        self.scheduling = scheduling
    }
}

/// Executes one tool call. The receive loop dispatches this in a child task and
/// never waits inside the frame loop (spec §4.5: toolCall → dispatch < 5 ms).
public protocol GeminiToolHandling: Sendable {
    func execute(_ call: GeminiToolCall.FunctionCall) async throws -> GeminiToolHandlerResult
}

/// The Live session state machine. Exactly one reader: the receive loop is the
/// only caller of `transport.receive()`. Nothing but `setup` is sent before
/// `setupComplete` (errata A20).
public actor GeminiLiveClient {
    public typealias TransportFactory = @Sendable () async throws -> any GeminiTransport
    public typealias SetupFactory = @Sendable (String?) -> GeminiSetup

    private let transportFactory: TransportFactory
    private let setupFactory: SetupFactory
    private let toolHandler: (any GeminiToolHandling)?
    private let setupTimeout: TimeInterval
    private let onServerContent: (@Sendable (GeminiServerContent) -> Void)?
    private let onNotice: (@Sendable (String) -> Void)?
    private let onMarker: (@Sendable (GeminiMarker) -> Void)?

    private var state: GeminiConnectionState = .idle
    private var transport: (any GeminiTransport)?
    private var receiveTask: Task<Void, Never>?
    private var connectGeneration = 0
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var setupTimeoutTask: Task<Void, Never>?
    private var inFlightToolTasks: [String: Task<Void, Never>] = [:]
    private var cancelledToolCallIDs: Set<String> = []
    private var resumptionHandle: String?
    private var sawAudioThisTurn = false

    public init(transportFactory: @escaping TransportFactory,
                setupFactory: @escaping SetupFactory,
                toolHandler: (any GeminiToolHandling)? = nil,
                setupTimeout: TimeInterval = 10,
                onServerContent: (@Sendable (GeminiServerContent) -> Void)? = nil,
                onNotice: (@Sendable (String) -> Void)? = nil,
                onMarker: (@Sendable (GeminiMarker) -> Void)? = nil) {
        self.transportFactory = transportFactory
        self.setupFactory = setupFactory
        self.toolHandler = toolHandler
        self.setupTimeout = setupTimeout
        self.onServerContent = onServerContent
        self.onNotice = onNotice
        self.onMarker = onMarker
    }

    public var connectionState: GeminiConnectionState { state }
    public var cachedResumptionHandle: String? { resumptionHandle }

    // MARK: Lifecycle

    public func start() async throws {
        switch state {
        case .idle, .stopped: break
        case .connecting, .ready, .reconnecting: throw GeminiClientError.alreadyStarted
        }
        state = .connecting
        do {
            try await establish(handle: nil)
        } catch {
            // A stop during `.connecting` already recorded the user's reason —
            // never overwrite it with `.networkFailure`.
            switch state {
            case .stopped: break
            default: state = .stopped(reason: .networkFailure)
            }
            throw error
        }
    }

    public func stop(reason: StopReason) async {
        // Mark stopped FIRST: the receive-loop failure handler must see `.stopped`
        // and return — no spurious "Connection lost." and no reconnect for a stop.
        state = .stopped(reason: reason)
        receiveTask?.cancel()
        receiveTask = nil
        dropInFlightToolCalls(reason: "session stopped")
        await transport?.close()
        transport = nil
    }

    // MARK: Sending

    /// Raw 16-bit LE PCM from ClickyAudio. The audio engine feeds 20 ms chunks
    /// (320 samples @ 16 kHz); 20–40 ms pacing, 100 ms is the tolerated ceiling
    /// (spec §4.1; constants in AudioChunkPacing).
    public func sendAudio(_ pcm: Data) async throws {
        try await transmit(.realtimeAudio(GeminiBlob(bytes: pcm, mimeType: AudioChunkPacing.audioMimeType)))
    }

    public func sendVideoFrame(jpeg: Data) async throws {
        try await transmit(.realtimeVideo(GeminiBlob(bytes: jpeg, mimeType: AudioChunkPacing.videoMimeType)))
    }

    public func sendAudioStreamEnd() async throws {
        try await transmit(.audioStreamEnd)
    }

    /// Text turns — used by the live spike; chunk 11's text-command fallback reuses it.
    public func sendTextTurn(_ text: String) async throws {
        try await transmit(.clientContent(turns: [GeminiContent(role: "user", text: text)], turnComplete: true))
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func transmit(_ message: GeminiClientMessage) async throws {
        guard state == .ready else { throw GeminiClientError.notReady }
        guard let transport else { throw GeminiClientError.transportUnavailable }
        try await transport.send(try encode(message))
        switch message {
        case .audioStreamEnd:
            onMarker?(.audioStreamEndSent)
        case .toolResponse(let response):
            for functionResponse in response.functionResponses {
                onMarker?(.toolResponseSent(id: functionResponse.id))
            }
        default:
            break
        }
    }

    // MARK: Connection

    private func establish(handle: String?) async throws {
        connectGeneration += 1
        let generation = connectGeneration
        await transport?.close()
        do {
            let newTransport = try await transportFactory()
            transport = newTransport
            try await newTransport.connect()
            let setup = setupFactory(handle)
            try await newTransport.send(try encode(GeminiClientMessage.setup(setup)))
            // A stop may have landed between the send and this point (actor
            // interleaving) — fail the handshake promptly instead of waiting
            // for the setup timeout.
            if case .stopped = state { throw GeminiClientError.transportUnavailable }
            receiveTask?.cancel()
            receiveTask = Task { await self.receiveLoop(generation: generation) }
            try await awaitSetupComplete()
        } catch {
            receiveTask?.cancel()
            receiveTask = nil
            await transport?.close()
            transport = nil
            throw error
        }
    }

    private func awaitSetupComplete() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
            let timeout = setupTimeout
            setupTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.setupTimedOut()
            }
        }
    }

    private func setupTimedOut() {
        guard let continuation = readyContinuation else { return }
        readyContinuation = nil
        continuation.resume(throwing: GeminiClientError.setupTimeout)
    }

    private func signalReady() {
        setupTimeoutTask?.cancel()
        setupTimeoutTask = nil
        guard let continuation = readyContinuation else { return }
        readyContinuation = nil
        continuation.resume()
    }

    private func receiveLoop(generation: Int) async {
        while generation == connectGeneration, let transport {
            do {
                let data = try await transport.receive()
                handleFrame(data)
            } catch {
                if generation == connectGeneration { handleTransportFailure() }
                return
            }
        }
    }

    private func handleFrame(_ data: Data) {
        guard let message = GeminiServerMessage.decode(from: data) else {
            onNotice?("Ignored an unrecognized server frame.")
            return
        }
        switch message {
        case .setupComplete:
            state = .ready
            signalReady()
        case .serverContent(let content):
            if content.interrupted == true {
                sawAudioThisTurn = false            // the next turn starts fresh after an interruption
                onMarker?(.interruptedReceived)
            }
            if !sawAudioThisTurn, !content.audioBase64Chunks.isEmpty {
                sawAudioThisTurn = true
                onMarker?(.firstAudioFrameReceived)
            }
            if content.turnComplete == true { sawAudioThisTurn = false }
            onServerContent?(content)
        case .toolCall(let call):
            for functionCall in call.functionCalls {
                onMarker?(.toolCallReceived(id: functionCall.id))
                guard inFlightToolTasks[functionCall.id] == nil,
                      !cancelledToolCallIDs.contains(functionCall.id) else { continue }
                inFlightToolTasks[functionCall.id] = Task { await self.runToolCall(functionCall) }
            }
        case .toolCallCancellation(let ids):
            for id in ids {
                // Record every cancelled id, even with no in-flight task: a
                // cancellation can precede its toolCall frame (fail closed).
                inFlightToolTasks.removeValue(forKey: id)?.cancel()
                cancelledToolCallIDs.insert(id)
                onMarker?(.toolCallDropped(id: id, reason: "cancelled by server"))
            }
        case .goAway(let timeLeftSeconds):
            handleGoAway(timeLeftSeconds: timeLeftSeconds)
        case .sessionResumptionUpdate(let resumable, let newHandle):
            // Cache ONLY `resumable == true` with a non-empty handle (errata A7):
            // resumption is impossible mid-generation / mid-function-call.
            if resumable, let newHandle, !newHandle.isEmpty { resumptionHandle = newHandle }
        }
    }

    private func handleGoAway(timeLeftSeconds: Double?) {
        onNotice?("The server will close this connection soon.")
    }

    private func handleTransportFailure() {
        if let continuation = readyContinuation {
            readyContinuation = nil
            continuation.resume(throwing: GeminiClientError.transportUnavailable)
        }
        switch state {
        case .idle, .stopped: return
        case .connecting, .ready, .reconnecting: break
        }
        state = .stopped(reason: .networkFailure)
        onNotice?("Connection lost.")
        dropInFlightToolCalls(reason: "connection lost")
        Task { await self.transport?.close() }
    }

    // MARK: Tool calls (dispatch never blocks the receive loop)

    private func runToolCall(_ call: GeminiToolCall.FunctionCall) async {
        // Fail closed before the handler runs: the task may have been cancelled
        // while queued, or the id may have been cancelled before dispatch. The
        // cancelling party already emitted `toolCallDropped`.
        guard !Task.isCancelled, !cancelledToolCallIDs.contains(call.id) else { return }
        let result: GeminiToolHandlerResult
        if let toolHandler {
            do {
                result = try await toolHandler.execute(call)
            } catch {
                result = GeminiToolHandlerResult(payload: .object(["status": .string("error")]),
                                                 scheduling: .interrupted)
            }
        } else {
            result = GeminiToolHandlerResult(
                payload: .object(["status": .string("error"), "detail": .string("no tool handler installed")]),
                scheduling: .interrupted)
        }
        await finishToolCall(id: call.id, name: call.name, result: result)
    }

    private func finishToolCall(id: String, name: String, result: GeminiToolHandlerResult) async {
        inFlightToolTasks.removeValue(forKey: id)
        guard !cancelledToolCallIDs.contains(id) else { return }
        let response = GeminiFunctionResponse(id: id, name: name, response: result.payload, scheduling: result.scheduling)
        do {
            try await transmit(.toolResponse(GeminiToolResponse(functionResponses: [response])))
        } catch {
            cancelledToolCallIDs.insert(id)
            onNotice?("A tool result could not be delivered — the connection was busy.")
        }
    }

    private func dropInFlightToolCalls(reason: String) {
        for id in inFlightToolTasks.keys {
            inFlightToolTasks[id]?.cancel()
            cancelledToolCallIDs.insert(id)
            onMarker?(.toolCallDropped(id: id, reason: reason))
        }
        inFlightToolTasks.removeAll()
    }
}
