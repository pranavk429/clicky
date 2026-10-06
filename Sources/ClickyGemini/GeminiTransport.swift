import Foundation

/// One bidirectional frame pipe. Implementations: `URLSessionWebSocketTransport`
/// (production/hackathon), `FakeTransport` (Tests/ClickyGeminiTests), `MockSession`
/// (shipped demo fallback).
///
/// Framing is TEXT-first (RFC 6455 opcode 0x1): every Clicky payload is JSON —
/// audio rides base64 inside JSON — and the Live gateway's edge proxies reject
/// BINARY frames.
public protocol GeminiTransport: Sendable {
    func connect() async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

public enum GeminiTransportError: Error, Equatable {
    case closed
    case unsupportedMessage
}

/// Thin `URLSessionWebSocketTask` wrapper — the only production transport (spec §5:
/// no third-party SDK; the legacy Swift SDK is deprecated and has no Live support).
public actor URLSessionWebSocketTransport: GeminiTransport {
    private let task: URLSessionWebSocketTask

    public init(url: URL, session: URLSession = .shared) {
        task = session.webSocketTask(with: url)
    }

    public func connect() async throws { task.resume() }

    /// UTF-8-decodable payloads go out as TEXT frames (the gateway's requirement);
    /// non-UTF-8 bytes fall back to BINARY so the helper stays total.
    public static func message(for data: Data) -> URLSessionWebSocketTask.Message {
        if let text = String(data: data, encoding: .utf8) { return .string(text) }
        return .data(data)
    }

    public func send(_ data: Data) async throws { try await task.send(Self.message(for: data)) }

    public func receive() async throws -> Data {
        let message = try await task.receive()
        switch message {
        case .data(let data): return data
        case .string(let string): return Data(string.utf8)
        @unknown default: throw GeminiTransportError.unsupportedMessage
        }
    }

    public func close() async { task.cancel(with: .normalClosure, reason: nil) }
}
