import Foundation
@testable import ClickyGemini

/// Waits for a matching element; returns nil on timeout. Continuation-based.
actor Recorder<Element: Sendable> {
    private var elements: [Element] = []
    private var waiters: [(id: UUID, matches: @Sendable (Element) -> Bool, continuation: CheckedContinuation<Element?, Never>)] = []

    func record(_ element: Element) {
        elements.append(element)
        guard let index = waiters.firstIndex(where: { $0.matches(element) }) else { return }
        waiters.remove(at: index).continuation.resume(returning: element)
    }

    func wait(matching predicate: @escaping @Sendable (Element) -> Bool,
              timeout: TimeInterval = 2) async -> Element? {
        if let existing = elements.first(where: predicate) { return existing }
        let id = UUID()
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await self?.timeout(id)
        }
        defer { timeoutTask.cancel() }
        return await withCheckedContinuation { continuation in
            waiters.append((id, predicate, continuation))
        }
    }

    func all() -> [Element] { elements }

    private func timeout(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: nil)
    }
}

/// Configurable tool handler: records invocations, optionally gates specific ids
/// until `release(_:)` (used by the non-blocking and cancellation tests).
actor GatedToolHandler: GeminiToolHandling {
    private let gatedIDs: Set<String>
    private let scheduling: GeminiScheduling
    private var released: Set<String> = []
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]
    private var invoked: [String] = []

    init(gatedIDs: Set<String> = [], scheduling: GeminiScheduling = .whenIdle) {
        self.gatedIDs = gatedIDs
        self.scheduling = scheduling
    }

    func execute(_ call: GeminiToolCall.FunctionCall) async throws -> GeminiToolHandlerResult {
        // Gate first, record after: a call cancelled while it waits is recorded
        // as invoked only if a test explicitly releases it past the gate.
        if gatedIDs.contains(call.id), !released.contains(call.id) {
            await withCheckedContinuation { gates[call.id] = $0 }
        }
        invoked.append(call.id)
        return GeminiToolHandlerResult(payload: .object(["status": .string("ok")]), scheduling: scheduling)
    }

    func release(_ id: String) {
        if let gate = gates.removeValue(forKey: id) { gate.resume() } else { released.insert(id) }
    }

    func invokedIDs() -> [String] { invoked }
}

/// Minimal server-frame builders for scripted scenarios (byte-exact expectations
/// live in `GeminiProtocolTypesTests.Fixtures`).
enum WireFrames {
    static let setupComplete = #"{"setupComplete":{}}"#
    static let interrupted = #"{"serverContent":{"interrupted":true}}"#
    static func turnComplete() -> String { #"{"serverContent":{"turnComplete":true}}"# }
    static func toolCall(id: String, name: String = "execute_action", args: String = "{}") -> String {
        #"{"toolCall":{"functionCalls":[{"id":"\#(id)","name":"\#(name)","args":\#(args)}]}}"#
    }
    static func resumptionUpdate(handle: String, resumable: Bool) -> String {
        #"{"sessionResumptionUpdate":{"newHandle":"\#(handle)","resumable":\#(resumable)}}"#
    }
    static func goAway(_ timeLeft: String) -> String { #"{"goAway":{"timeLeft":"\#(timeLeft)"}}"# }
}
