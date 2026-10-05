import Foundation

// MARK: - Endpoint (spec §4.1; errata A1 model, A4 constrained endpoint is v1beta)

public enum GeminiEndpoint {
    public static let modelName = "models/gemini-3.8-live"
    public static let defaultVoiceName = "Aoede"

    /// Hackathon build: API key from the environment (never embedded). Production
    /// path (not built here): backend-minted ephemeral tokens against the `v1beta`
    /// `BidiGenerateContentConstrained` endpoint (errata A4).
    public static func webSocketURL(apiKey: String) -> URL? {
        guard var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        return components.url
    }
}

// MARK: - JSON value (tool args / tool responses; chunk 11's tool payloads)

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Blobs (A3: `realtimeInput.audio` / `.video`; never `mediaChunks`)

public struct GeminiBlob: Codable, Equatable, Sendable {
    public var data: String        // base64, no data: prefix
    public var mimeType: String
    public init(data: String, mimeType: String) { self.data = data; self.mimeType = mimeType }
    public init(bytes: Data, mimeType: String) { self.data = bytes.base64EncodedString(); self.mimeType = mimeType }
}

// MARK: - Content

public struct GeminiPart: Codable, Equatable, Sendable {
    public var text: String?
    public var inlineData: GeminiBlob?
    public init(text: String? = nil, inlineData: GeminiBlob? = nil) { self.text = text; self.inlineData = inlineData }
}

public struct GeminiContent: Codable, Equatable, Sendable {
    public var role: String?
    public var parts: [GeminiPart]
    public init(role: String? = nil, parts: [GeminiPart]) { self.role = role; self.parts = parts }
    public init(role: String? = nil, text: String) { self.role = role; self.parts = [GeminiPart(text: text)] }
}

// MARK: - Setup message

public struct GeminiPrebuiltVoiceConfig: Codable, Equatable, Sendable {
    public var voiceName: String
    public init(voiceName: String) { self.voiceName = voiceName }
}

public struct GeminiSpeechConfig: Codable, Equatable, Sendable {
    public struct VoiceConfig: Codable, Equatable, Sendable {
        public var prebuiltVoiceConfig: GeminiPrebuiltVoiceConfig
        public init(prebuiltVoiceConfig: GeminiPrebuiltVoiceConfig) { self.prebuiltVoiceConfig = prebuiltVoiceConfig }
    }
    public var voiceConfig: VoiceConfig
    public init(voiceName: String) { self.voiceConfig = VoiceConfig(prebuiltVoiceConfig: GeminiPrebuiltVoiceConfig(voiceName: voiceName)) }
}

public struct GeminiGenerationConfig: Codable, Equatable, Sendable {
    public var responseModalities: [String]
    public var speechConfig: GeminiSpeechConfig?
    public init(responseModalities: [String], speechConfig: GeminiSpeechConfig? = nil) {
        self.responseModalities = responseModalities
        self.speechConfig = speechConfig
    }
}

public struct GeminiFunctionDeclaration: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONValue?
    /// `behavior: "NON_BLOCKING"` keeps speech flowing while a tool executes (errata A2).
    public var behavior: String?
    public init(name: String, description: String, parameters: JSONValue? = nil, behavior: String? = "NON_BLOCKING") {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.behavior = behavior
    }
}

public struct GeminiTool: Codable, Equatable, Sendable {
    public var functionDeclarations: [GeminiFunctionDeclaration]
    public init(functionDeclarations: [GeminiFunctionDeclaration]) { self.functionDeclarations = functionDeclarations }
}

/// Server VAD stays on; these are the tuned half of the hybrid VAD (spec §4.1):
/// silenceDurationMs 350–500, prefixPaddingMs 20–40, sensitivity HIGH.
public struct GeminiAutomaticActivityDetection: Codable, Equatable, Sendable {
    /// Doc-derived enum spellings — verified in Spike 5.3 (Task 5.3). If the server
    /// rejects them, replace these two rawValue constants (the single definition
    /// site), re-run the spike, and record a dated errata note in the plan.
    public static let startOfSpeechHigh = "START_OF_SPEECH_SENSITIVITY_HIGH"
    public static let endOfSpeechHigh = "END_OF_SPEECH_SENSITIVITY_HIGH"
    public static let defaultSilenceDurationMs = 400
    public static let defaultPrefixPaddingMs = 30

    public var silenceDurationMs: Int?
    public var prefixPaddingMs: Int?
    public var startOfSpeechSensitivity: String?
    public var endOfSpeechSensitivity: String?

    public init(silenceDurationMs: Int? = nil, prefixPaddingMs: Int? = nil,
                startOfSpeechSensitivity: String? = nil, endOfSpeechSensitivity: String? = nil) {
        self.silenceDurationMs = silenceDurationMs
        self.prefixPaddingMs = prefixPaddingMs
        self.startOfSpeechSensitivity = startOfSpeechSensitivity
        self.endOfSpeechSensitivity = endOfSpeechSensitivity
    }

    public static let clickyDefault = GeminiAutomaticActivityDetection(
        silenceDurationMs: defaultSilenceDurationMs, prefixPaddingMs: defaultPrefixPaddingMs,
        startOfSpeechSensitivity: startOfSpeechHigh, endOfSpeechSensitivity: endOfSpeechHigh)
}

public struct GeminiRealtimeInputConfig: Codable, Equatable, Sendable {
    public var automaticActivityDetection: GeminiAutomaticActivityDetection?
    public init(automaticActivityDetection: GeminiAutomaticActivityDetection? = nil) {
        self.automaticActivityDetection = automaticActivityDetection
    }
}

/// Encodes to `{}` — the sliding window has no required fields here.
public struct GeminiSlidingWindow: Codable, Equatable, Sendable {
    public init() {}
}

public struct GeminiContextWindowCompression: Codable, Equatable, Sendable {
    public var slidingWindow: GeminiSlidingWindow
    public init() { self.slidingWindow = GeminiSlidingWindow() }
}

public struct GeminiSessionResumption: Codable, Equatable, Sendable {
    public var handle: String?
    public init(handle: String? = nil) { self.handle = handle }
}

/// Encodes to `{}` — enables input transcriptions (chunk 8's confirmation gate consumes them).
public struct GeminiAudioTranscriptionConfig: Codable, Equatable, Sendable {
    public init() {}
}

public struct GeminiSetup: Codable, Equatable, Sendable {
    public var model: String
    public var generationConfig: GeminiGenerationConfig
    public var systemInstruction: GeminiContent?
    public var tools: [GeminiTool]?
    public var realtimeInputConfig: GeminiRealtimeInputConfig?
    public var contextWindowCompression: GeminiContextWindowCompression?
    public var sessionResumption: GeminiSessionResumption?
    public var inputAudioTranscription: GeminiAudioTranscriptionConfig?
}

/// The one place the setup frame is assembled. Chunk 11 injects the real system
/// instruction and tool declarations; Tasks 4.1–5.3 inject test doubles.
public enum GeminiSetupBuilder {
    public static func make(systemInstruction: String,
                            tools: [GeminiTool]? = nil,
                            voiceName: String = GeminiEndpoint.defaultVoiceName,
                            resumptionHandle: String? = nil,
                            vad: GeminiAutomaticActivityDetection = .clickyDefault) -> GeminiSetup {
        GeminiSetup(model: GeminiEndpoint.modelName,
                    generationConfig: GeminiGenerationConfig(responseModalities: ["AUDIO"],
                                                             speechConfig: GeminiSpeechConfig(voiceName: voiceName)),
                    systemInstruction: GeminiContent(text: systemInstruction),
                    tools: tools,
                    realtimeInputConfig: GeminiRealtimeInputConfig(automaticActivityDetection: vad),
                    contextWindowCompression: GeminiContextWindowCompression(),
                    sessionResumption: GeminiSessionResumption(handle: resumptionHandle),
                    inputAudioTranscription: GeminiAudioTranscriptionConfig())
    }
}

// MARK: - Client → server messages

public enum GeminiClientMessage: Equatable, Sendable {
    case setup(GeminiSetup)
    case realtimeAudio(GeminiBlob)
    case realtimeVideo(GeminiBlob)
    case audioStreamEnd
    case clientContent(turns: [GeminiContent], turnComplete: Bool)
    case toolResponse(GeminiToolResponse)

    private enum RootKey: String, CodingKey { case setup, realtimeInput, clientContent, toolResponse }
    private struct RealtimeInput: Encodable { var audio: GeminiBlob?; var video: GeminiBlob?; var audioStreamEnd: Bool? }
    private struct ClientContent: Encodable { var turns: [GeminiContent]; var turnComplete: Bool }
}

extension GeminiClientMessage: Encodable {
    public func encode(to encoder: Encoder) throws {
        var root = encoder.container(keyedBy: RootKey.self)
        switch self {
        case .setup(let setup):
            try root.encode(setup, forKey: .setup)
        case .realtimeAudio(let blob):
            try root.encode(RealtimeInput(audio: blob), forKey: .realtimeInput)
        case .realtimeVideo(let blob):
            try root.encode(RealtimeInput(video: blob), forKey: .realtimeInput)
        case .audioStreamEnd:
            try root.encode(RealtimeInput(audioStreamEnd: true), forKey: .realtimeInput)
        case .clientContent(let turns, let turnComplete):
            try root.encode(ClientContent(turns: turns, turnComplete: turnComplete), forKey: .clientContent)
        case .toolResponse(let response):
            try root.encode(response, forKey: .toolResponse)
        }
    }
}

public enum GeminiScheduling: String, Codable, Equatable, Sendable {
    case silent = "SILENT"
    case whenIdle = "WHEN_IDLE"
    case interrupted = "INTERRUPTED"   // errata A9: spelling is INTERRUPTED, never INTERRUPT
}

public struct GeminiFunctionResponse: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var response: JSONValue
    /// Top-level `FunctionResponse.scheduling` per the API reference (errata A9). The
    /// Python/JS examples nest it inside `response`; Spike 5.3 decides. If placement
    /// is wrong, move this field into the `response` dictionary — one site to change.
    public var scheduling: GeminiScheduling?
    public init(id: String, name: String, response: JSONValue, scheduling: GeminiScheduling? = nil) {
        self.id = id
        self.name = name
        self.response = response
        self.scheduling = scheduling
    }
}

public struct GeminiToolResponse: Codable, Equatable, Sendable {
    public var functionResponses: [GeminiFunctionResponse]
    public init(functionResponses: [GeminiFunctionResponse]) { self.functionResponses = functionResponses }
}

// MARK: - Server → client messages

public struct GeminiTranscription: Codable, Equatable, Sendable {
    public var text: String?
}

public struct GeminiServerContent: Codable, Equatable, Sendable {
    public var modelTurn: GeminiContent?
    public var turnComplete: Bool?
    public var interrupted: Bool?
    public var inputTranscription: GeminiTranscription?
    public var outputTranscription: GeminiTranscription?

    /// Base64 24 kHz PCM payloads of this content message (spec §4.1 output format).
    public var audioBase64Chunks: [String] {
        (modelTurn?.parts ?? []).compactMap { part in
            guard let inlineData = part.inlineData, inlineData.mimeType.hasPrefix("audio/pcm") else { return nil }
            return inlineData.data
        }
    }
}

public struct GeminiToolCall: Codable, Equatable, Sendable {
    public struct FunctionCall: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var args: [String: JSONValue]?
    }
    public var functionCalls: [FunctionCall]
}

public struct GeminiToolCallCancellation: Codable, Equatable, Sendable {
    public var ids: [String]
}

public struct GeminiGoAway: Codable, Equatable, Sendable {
    /// Protobuf duration string, e.g. `"12.5s"`.
    public var timeLeft: String?
    public var timeLeftSeconds: Double? { Self.parseDurationSeconds(timeLeft) }

    public static func parseDurationSeconds(_ value: String?) -> Double? {
        guard let value, value.hasSuffix("s") else { return nil }
        return Double(value.dropLast())
    }
}

public struct GeminiSessionResumptionUpdate: Codable, Equatable, Sendable {
    public var resumable: Bool?
    public var newHandle: String?
}

public enum GeminiServerMessage: Equatable, Sendable {
    case setupComplete
    case serverContent(GeminiServerContent)
    case toolCall(GeminiToolCall)
    case toolCallCancellation(ids: [String])
    case goAway(timeLeftSeconds: Double?)
    case sessionResumptionUpdate(resumable: Bool, newHandle: String?)

    private struct EmptyMessage: Decodable {}
    private struct Envelope: Decodable {
        var setupComplete: EmptyMessage?
        var serverContent: GeminiServerContent?
        var toolCall: GeminiToolCall?
        var toolCallCancellation: GeminiToolCallCancellation?
        var goAway: GeminiGoAway?
        var sessionResumptionUpdate: GeminiSessionResumptionUpdate?
    }

    /// Returns nil for unknown frames — the receive loop logs and ignores them
    /// instead of crashing (forward compatibility with server-side changes).
    public static func decode(from data: Data) -> GeminiServerMessage? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        if envelope.setupComplete != nil { return .setupComplete }
        if let value = envelope.serverContent { return .serverContent(value) }
        if let value = envelope.toolCall { return .toolCall(value) }
        if let value = envelope.toolCallCancellation { return .toolCallCancellation(ids: value.ids) }
        if let value = envelope.goAway { return .goAway(timeLeftSeconds: value.timeLeftSeconds) }
        if let value = envelope.sessionResumptionUpdate {
            return .sessionResumptionUpdate(resumable: value.resumable ?? false, newHandle: value.newHandle)
        }
        return nil
    }
}
