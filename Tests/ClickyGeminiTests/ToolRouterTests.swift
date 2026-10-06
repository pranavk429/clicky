import ClickySafety
import CoreGraphics
import XCTest
@testable import ClickyGemini

struct LedgerSpy: IntentLedgerPort {
    let allowed: Bool
    func recordVoiceUtterance(_ text: String, at date: Date) async {}
    func isTraceableToVoiceIntent(_ intent: String, at date: Date) async -> Bool { allowed }
}

struct RiskStub: RiskClassifyingPort {
    let tier: RiskTier
    func classify(kind: ClickyActionKind, targetTitle: String?, targetSubrole: String?,
                  windowTitle: String?, hasAmount: Bool) async -> RiskTier { tier }
}

struct ContextStub: ScreenContextProviding {
    let snapshot: ScreenContext
    func captureContext(reason: String, maxNodes: Int) async -> ScreenContext { snapshot }
}

actor SystemSpy: SystemActionPort {
    private var resolutions: [ResolvedTarget?]
    private(set) var resolves = 0
    private(set) var performs: [ResolvedAction] = []
    init(resolutions: [ResolvedTarget?]) { self.resolutions = resolutions }
    func resolve(title: String?, kind: ClickyActionKind) async -> ResolvedTarget? {
        resolves += 1
        guard !resolutions.isEmpty else { return nil }
        return resolutions.count == 1 ? resolutions[0] : resolutions.removeFirst()
    }
    func perform(_ action: ResolvedAction) async -> ActionOutcome {
        performs.append(action)
        return .performed(detail: "done")
    }
}

actor OverlaySpy: GhostCursorPort {
    private(set) var presentations: [GhostCursorPresentation] = []
    func present(_ presentation: GhostCursorPresentation) async { presentations.append(presentation) }
    func last() -> GhostCursorPresentation? { presentations.last }
}

actor GateScript: ConfirmationGatingPort {
    private let decision: ConfirmationDecision
    private(set) var armed: [PendingConfirmationRequest] = []
    private(set) var modelDecisions: [(Bool, String)] = []
    init(decision: ConfirmationDecision) { self.decision = decision }
    func arm(_ request: PendingConfirmationRequest) async -> ConfirmationDecision { armed.append(request); return decision }
    func submitVoiceTranscript(_ text: String) async {}
    func submitModelDecision(confirmed: Bool, echo: String) async { modelDecisions.append((confirmed, echo)) }
    func markPromptTurnComplete() async {}
}

private func makeTarget(_ title: String = "Project") -> ResolvedTarget {
    ResolvedTarget(applicationName: "Notes", role: "AXButton", subrole: nil, title: title,
                   windowTitle: "Notes", cgFrame: CGRect(x: 20, y: 40, width: 90, height: 24))
}

private func makeCall(_ name: String = ClickyTools.executeAction,
                      _ args: [String: JSONValue] = ["intent": .string("Delete my project notes"),
                                                     "action": .string("click")]) -> GeminiToolCall.FunctionCall {
    GeminiToolCall.FunctionCall(id: "fc-1", name: name, args: args)
}

private struct Fixture {
    let router: ToolRouter
    let system: SystemSpy
    let overlay: OverlaySpy
    let gate: GateScript
}

private func makeFixture(tier: RiskTier = .reversible, allowIntent: Bool = true,
                         resolutions: [ResolvedTarget?] = [makeTarget()],
                         gateDecision: ConfirmationDecision = .confirmed(source: .voiceTranscript)) -> Fixture {
    let context = ScreenContext(applicationName: "Notes", windowTitle: "Notes",
                                elements: [ScreenContextElement(role: "AXButton", subrole: nil, title: "Project",
                                                                elementDescription: "note", enabled: true,
                                                                actions: ["AXPress"])])
    let system = SystemSpy(resolutions: resolutions)
    let overlay = OverlaySpy()
    let gate = GateScript(decision: gateDecision)
    let router = ToolRouter(ledger: LedgerSpy(allowed: allowIntent), risk: RiskStub(tier: tier),
                            screenContext: ContextStub(snapshot: context), system: system,
                            overlay: overlay, gate: gate, sleeper: ImmediateSleeper())
    return Fixture(router: router, system: system, overlay: overlay, gate: gate)
}

private func stringField(_ result: GeminiToolHandlerResult, _ key: String) -> String? {
    guard case .object(let payload) = result.payload, case .string(let value)? = payload[key] else { return nil }
    return value
}

final class ToolRouterTests: XCTestCase {

    func testRefusesCallWithoutVoiceIntent() async throws {
        let fixture = makeFixture(allowIntent: false)
        let result = try await fixture.router.execute(makeCall())
        XCTAssertEqual(stringField(result, "status"), "not_authorized", "T10: screen content can never authorize")
        XCTAssertEqual(result.scheduling, .interrupted)
        let resolves = await fixture.system.resolves
        XCTAssertEqual(resolves, 0, "no OS work before the ledger check")
    }

    func testReadAndReversibleRunWithoutConfirmation() async throws {
        let read = makeFixture(tier: .read)
        let readResult = try await read.router.execute(makeCall(ClickyTools.executeAction,
                                                                ["intent": .string("read the note"), "action": .string("click")]))
        XCTAssertEqual(stringField(readResult, "status"), "executed")
        XCTAssertEqual(readResult.scheduling, .silent, "mechanical actions are SILENT")

        let reversible = makeFixture()
        let reversibleResult = try await reversible.router.execute(makeCall())
        XCTAssertEqual(stringField(reversibleResult, "status"), "executed")
        XCTAssertEqual(reversibleResult.scheduling, .whenIdle, "spoken outcomes wait for idle")
        let armedCount = await reversible.gate.armed.count
        XCTAssertEqual(armedCount, 0)
        guard case .review = await reversible.overlay.last() else { return XCTFail("amber review box expected") }
    }

    func testProhibitedIsBlockedLocally() async throws {
        let fixture = makeFixture(tier: .prohibited)
        let result = try await fixture.router.execute(makeCall())
        XCTAssertEqual(stringField(result, "status"), "refused")
        XCTAssertEqual(result.scheduling, .interrupted)
        let performs = await fixture.system.performs.count
        XCTAssertEqual(performs, 0)
    }

    func testTierThreeCancellationStopsExecution() async throws {
        let fixture = makeFixture(tier: .irreversible, gateDecision: .cancelled(reason: "negation: Ruko"))
        let result = try await fixture.router.execute(makeCall())
        XCTAssertEqual(stringField(result, "status"), "cancelled")
        XCTAssertEqual(result.scheduling, .whenIdle)
        let performs = await fixture.system.performs.count
        XCTAssertEqual(performs, 0, "a cancel must never execute")
        let armedCount = await fixture.gate.armed.count
        XCTAssertEqual(armedCount, 1)
        guard case .stopped = await fixture.overlay.last() else { return XCTFail("stopped banner expected") }
    }

    func testTierThreeConfirmationExecutesAfterRevalidation() async throws {
        let fixture = makeFixture(tier: .irreversible, resolutions: [makeTarget(), makeTarget()])
        let result = try await fixture.router.execute(makeCall())
        XCTAssertEqual(stringField(result, "status"), "executed")
        let tier = await fixture.gate.armed.first?.tier
        XCTAssertEqual(tier, .irreversible)
        let performs = await fixture.system.performs.count
        XCTAssertEqual(performs, 1)
    }

    func testTOCTOUChangeFailsClosed() async throws {
        let fixture = makeFixture(tier: .irreversible, resolutions: [makeTarget(), makeTarget("Project backup")])
        let result = try await fixture.router.execute(makeCall())
        XCTAssertEqual(stringField(result, "status"), "target_changed")
        XCTAssertEqual(result.scheduling, .interrupted)
        let performs = await fixture.system.performs.count
        XCTAssertEqual(performs, 0)
    }

    func testMoneyNeedsTheSpokenAmountAndRejectsModelOnlyConfirmation() async throws {
        let missing = makeFixture(tier: .financial)
        let missingResult = try await missing.router.execute(makeCall())
        XCTAssertEqual(stringField(missingResult, "status"), "amount_required")
        let missingPerforms = await missing.system.performs.count
        XCTAssertEqual(missingPerforms, 0)

        let modelOnly = makeFixture(tier: .financial, resolutions: [makeTarget("Pay ₹500"), makeTarget("Pay ₹500")],
                                    gateDecision: .confirmed(source: .modelTool))
        let modelOnlyResult = try await modelOnly.router.execute(makeCall(ClickyTools.executeAction,
                                                                          ["intent": .string("pay five hundred"),
                                                                           "action": .string("click"),
                                                                           "amount": .string("₹500")]))
        XCTAssertEqual(stringField(modelOnlyResult, "status"), "refused")
        let modelOnlyPerforms = await modelOnly.system.performs.count
        XCTAssertEqual(modelOnlyPerforms, 0)
    }

    func testMoneyConfirmedByVoiceExecutes() async throws {
        let fixture = makeFixture(tier: .financial, resolutions: [makeTarget("Pay ₹500"), makeTarget("Pay ₹500")])
        let result = try await fixture.router.execute(makeCall(ClickyTools.executeAction,
                                                               ["intent": .string("pay five hundred"),
                                                                "action": .string("click"),
                                                                "amount": .string("₹500")]))
        XCTAssertEqual(stringField(result, "status"), "executed")
        let amount = await fixture.gate.armed.first?.amount
        XCTAssertEqual(amount, "₹500")
    }

    func testConfirmActionFeedsTheGateAndStaysSilent() async throws {
        let fixture = makeFixture()
        let result = try await fixture.router.execute(makeCall(ClickyTools.confirmAction,
                                                               ["decision": .string("confirm"), "echo": .string("Haan")]))
        XCTAssertEqual(stringField(result, "status"), "recorded")
        XCTAssertEqual(result.scheduling, .silent)
        let decisions = await fixture.gate.modelDecisions
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions.first?.0, true)
        XCTAssertEqual(decisions.first?.1, "Haan")
        let performs = await fixture.system.performs.count
        XCTAssertEqual(performs, 0)
    }

    func testGetScreenContextReturnsExactTitlesAndNoFrames() async throws {
        let fixture = makeFixture()
        let result = try await fixture.router.execute(makeCall(ClickyTools.getScreenContext,
                                                               ["reason": .string("find the note")]))
        XCTAssertEqual(stringField(result, "status"), "ok")
        XCTAssertEqual(result.scheduling, .silent)
        guard case .object(let payload) = result.payload,
              case .array(let elements)? = payload["elements"],
              case .object(let first)? = elements.first,
              case .string(let title)? = first["title"] else { return XCTFail("elements expected") }
        XCTAssertEqual(title, "Project")
        XCTAssertFalse(String(describing: result.payload).contains("cgFrame"), "frames never reach the model")
        let resolves = await fixture.system.resolves
        XCTAssertEqual(resolves, 0, "context is read-only")
    }
}
