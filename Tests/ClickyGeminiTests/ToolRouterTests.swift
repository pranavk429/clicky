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
    func classify(kind: ClickyActionKind, text: String?, targetTitle: String?, targetSubrole: String?,
                  windowTitle: String?, hasAmount: Bool) async -> RiskTier { tier }
}

/// Records what the router handed the risk port so the `text` (URL for
/// `open_url`) wiring is pinned independently of the ClickyApp adapter.
actor RiskSpy: RiskClassifyingPort {
    let tier: RiskTier
    private(set) var calls: [(kind: ClickyActionKind, text: String?)] = []
    init(tier: RiskTier) { self.tier = tier }
    func classify(kind: ClickyActionKind, text: String?, targetTitle: String?, targetSubrole: String?,
                  windowTitle: String?, hasAmount: Bool) async -> RiskTier {
        calls.append((kind, text))
        return tier
    }
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
    /// Deterministic pointer for the `click_cursor` preview/dispatch tests.
    func pointerLocation() async -> CGPoint? { CGPoint(x: 42, y: 24) }
}

/// Screen-vision fake for `click_at` / `click_grid`: `mappedPoint == nil` models
/// "no frame was sent within the 30 s window" for point mapping, and
/// `mappedCell` models the grid-cell mapping outcome. `lookCalls` records the
/// grid request each `look_at_screen` carried.
actor ScreenLookingSpy: ScreenLooking {
    private(set) var mapCalls: [(x: Double, y: Double)] = []
    private(set) var gridMapCalls: [String] = []
    private(set) var lookCalls: [(reason: String, grid: ScreenGrid?)] = []
    private let mappedPoint: CGPoint?
    private let mappedCell: GridCellMapping
    private let lookOutcome: ScreenLookOutcome
    init(mappedPoint: CGPoint?, mappedCell: GridCellMapping = .noFrame,
         lookOutcome: ScreenLookOutcome = .failed(reason: "not used by these tests")) {
        self.mappedPoint = mappedPoint
        self.mappedCell = mappedCell
        self.lookOutcome = lookOutcome
    }
    func lookAtScreen(reason: String, grid: ScreenGrid?) async -> ScreenLookOutcome {
        lookCalls.append((reason, grid))
        return lookOutcome
    }
    func mapFramePoint(x: Double, y: Double, at date: Date) async -> CGPoint? {
        mapCalls.append((x, y))
        return mappedPoint
    }
    func mapGridCell(_ cell: String, at date: Date) async -> GridCellMapping {
        gridMapCalls.append(cell)
        return mappedCell
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
    private(set) var cardDecisions: [Bool] = []
    init(decision: ConfirmationDecision) { self.decision = decision }
    func arm(_ request: PendingConfirmationRequest) async -> ConfirmationDecision { armed.append(request); return decision }
    func submitVoiceTranscript(_ text: String) async {}
    func submitModelDecision(confirmed: Bool, echo: String) async { modelDecisions.append((confirmed, echo)) }
    func submitCardDecision(confirmed: Bool) async { cardDecisions.append(confirmed) }
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

/// Router for the pointer-anchored actions (`click_cursor` / `click_at`).
private func makeRouter(screenLooking: (any ScreenLooking)? = nil,
                        system: SystemSpy = SystemSpy(resolutions: []),
                        overlay: OverlaySpy = OverlaySpy()) -> ToolRouter {
    let context = ScreenContext(applicationName: "Comet", windowTitle: "LinkedIn", elements: [])
    return ToolRouter(ledger: LedgerSpy(allowed: true), risk: RiskStub(tier: .reversible),
                      screenContext: ContextStub(snapshot: context), system: system,
                      overlay: overlay, gate: GateScript(decision: .confirmed(source: .voiceTranscript)),
                      sleeper: ImmediateSleeper(), screenLooking: screenLooking)
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

    func testGetScreenContextClampsOutOfRangeMaxNodesWithoutTrapping() async throws {
        let elements = (0..<500).map { index in
            ScreenContextElement(role: "AXButton", subrole: nil, title: "Item \(index)",
                                 elementDescription: nil, enabled: true, actions: ["AXPress"])
        }
        let context = ScreenContext(applicationName: "Notes", windowTitle: "Notes", elements: elements)
        let router = ToolRouter(ledger: LedgerSpy(allowed: true), risk: RiskStub(tier: .reversible),
                                screenContext: ContextStub(snapshot: context),
                                system: SystemSpy(resolutions: []),
                                overlay: OverlaySpy(), gate: GateScript(decision: .confirmed(source: .voiceTranscript)),
                                sleeper: ImmediateSleeper())
        let result = try await router.execute(GeminiToolCall.FunctionCall(
            id: "ctx-out-of-range", name: ClickyTools.getScreenContext,
            args: ["reason": .string("find the note"), "max_nodes": .number(1e20)]))
        XCTAssertEqual(stringField(result, "status"), "ok")
        XCTAssertEqual(result.scheduling, .silent)
        guard case .object(let payload) = result.payload,
              case .array(let returned)? = payload["elements"] else { return XCTFail("elements expected") }
        XCTAssertLessThanOrEqual(returned.count, ToolRouter.contextMaxNodesCeiling, "ceiling never exceeded")
        XCTAssertEqual(returned.count, ToolRouter.defaultContextMaxNodes,
                       "an out-of-range max_nodes falls back to the default, then clamps")
    }

    // MARK: Pointer-anchored clicks

    func testClickCursorPreviewsAndClicksAtThePointer() async throws {
        let system = SystemSpy(resolutions: [])
        let overlay = OverlaySpy()
        let router = makeRouter(system: system, overlay: overlay)
        let result = try await router.execute(makeCall(ClickyTools.executeAction,
                                                       ["intent": .string("click here"),
                                                        "action": .string("click_cursor")]))
        XCTAssertEqual(stringField(result, "status"), "executed")
        let performs = await system.performs
        XCTAssertEqual(performs.count, 1)
        XCTAssertEqual(performs.first?.kind, .clickCursor)
        XCTAssertEqual(performs.first?.point, CGPoint(x: 42, y: 24),
                       "the previewed pointer point is the clicked point")
        guard case .moving(let point) = await overlay.last() else { return XCTFail("ghost preview expected") }
        XCTAssertEqual(point, CGPoint(x: 42, y: 24))
    }

    func testClickAtFailsClosedWithoutARecentFrame() async throws {
        let screenLooking = ScreenLookingSpy(mappedPoint: nil)
        let system = SystemSpy(resolutions: [])
        let router = makeRouter(screenLooking: screenLooking, system: system)
        let result = try await router.execute(makeCall(ClickyTools.executeAction,
                                                       ["intent": .string("click the blue button"),
                                                        "action": .string("click_at"),
                                                        "x": .number(120), "y": .number(340)]))
        XCTAssertEqual(stringField(result, "status"), "no_frame")
        XCTAssertEqual(result.scheduling, .interrupted)
        let performs = await system.performs.count
        XCTAssertEqual(performs, 0, "no click without a recent look_at_screen frame")
        let mapCalls = await screenLooking.mapCalls
        XCTAssertEqual(mapCalls.count, 1)
        XCTAssertEqual(mapCalls.first?.x, 120)
        XCTAssertEqual(mapCalls.first?.y, 340)
    }

    func testClickAtMapsFrameCoordinatesAndClicksThePoint() async throws {
        let screenLooking = ScreenLookingSpy(mappedPoint: CGPoint(x: 510, y: 384))
        let system = SystemSpy(resolutions: [])
        let overlay = OverlaySpy()
        let router = makeRouter(screenLooking: screenLooking, system: system, overlay: overlay)
        let result = try await router.execute(makeCall(ClickyTools.executeAction,
                                                       ["intent": .string("click the blue button"),
                                                        "action": .string("click_at"),
                                                        "x": .number(120), "y": .number(340)]))
        XCTAssertEqual(stringField(result, "status"), "executed")
        let performs = await system.performs
        XCTAssertEqual(performs.count, 1)
        XCTAssertEqual(performs.first?.kind, .clickAt)
        XCTAssertEqual(performs.first?.point, CGPoint(x: 510, y: 384))
        guard case .moving(let point) = await overlay.last() else { return XCTFail("ghost preview expected") }
        XCTAssertEqual(point, CGPoint(x: 510, y: 384))
    }

    func testClickAtRequiresNumericCoordinates() async throws {
        let system = SystemSpy(resolutions: [])
        let router = makeRouter(system: system)
        let result = try await router.execute(makeCall(ClickyTools.executeAction,
                                                       ["intent": .string("click that"),
                                                        "action": .string("click_at")]))
        XCTAssertEqual(stringField(result, "status"), "invalid_args")
        let performs = await system.performs.count
        XCTAssertEqual(performs, 0)
    }

    // MARK: Grid-anchored clicks

    func testClickGridRequiresACellLabel() async throws {
        let system = SystemSpy(resolutions: [])
        let router = makeRouter(system: system)
        let result = try await router.execute(makeCall(ClickyTools.executeAction,
                                                       ["intent": .string("click the video"),
                                                        "action": .string("click_grid")]))
        XCTAssertEqual(stringField(result, "status"), "invalid_args")
        XCTAssertEqual(result.scheduling, .interrupted)
        let performs = await system.performs.count
        XCTAssertEqual(performs, 0)
    }

    func testClickGridRejectsAMalformedCellLabel() async throws {
        let screenLooking = ScreenLookingSpy(mappedPoint: nil,
                                             mappedCell: .mapped(rect: CGRect(x: 0, y: 0, width: 10, height: 10)))
        let system = SystemSpy(resolutions: [])
        let router = makeRouter(screenLooking: screenLooking, system: system)
        let result = try await router.execute(makeCall(ClickyTools.executeAction,
                                                       ["intent": .string("click the video"),
                                                        "action": .string("click_grid"),
                                                        "cell": .string("banana")]))
        XCTAssertEqual(stringField(result, "status"), "invalid_args")
        let gridMapCalls = await screenLooking.gridMapCalls
        XCTAssertEqual(gridMapCalls.count, 0, "a malformed cell never reaches the vision port")
        let performs = await system.performs.count
        XCTAssertEqual(performs, 0, "a malformed click_grid never reaches the OS")
    }

    func testClickGridFailsClosedWithoutARecentGriddedFrame() async throws {
        let screenLooking = ScreenLookingSpy(mappedPoint: nil) // mappedCell defaults to .noFrame
        let system = SystemSpy(resolutions: [])
        let router = makeRouter(screenLooking: screenLooking, system: system)
        let result = try await router.execute(makeCall(ClickyTools.executeAction,
                                                       ["intent": .string("click the video"),
                                                        "action": .string("click_grid"),
                                                        "cell": .string("C5")]))
        XCTAssertEqual(stringField(result, "status"), "no_frame")
        XCTAssertEqual(result.scheduling, .interrupted)
        let performs = await system.performs.count
        XCTAssertEqual(performs, 0, "no click without a recent gridded look_at_screen frame")
        let gridMapCalls = await screenLooking.gridMapCalls
        XCTAssertEqual(gridMapCalls, ["C5"])
    }

    func testClickGridOutOfRangeCellIsInvalidArgs() async throws {
        let screenLooking = ScreenLookingSpy(mappedPoint: nil, mappedCell: .invalidCell)
        let system = SystemSpy(resolutions: [])
        let router = makeRouter(screenLooking: screenLooking, system: system)
        let result = try await router.execute(makeCall(ClickyTools.executeAction,
                                                       ["intent": .string("click the video"),
                                                        "action": .string("click_grid"),
                                                        "cell": .string("Z9")]))
        XCTAssertEqual(stringField(result, "status"), "invalid_args")
        XCTAssertEqual(result.scheduling, .interrupted)
        let performs = await system.performs.count
        XCTAssertEqual(performs, 0)
    }

    func testClickGridMapsTheCellAndClicksItsCenter() async throws {
        let rect = CGRect(x: 400, y: 300, width: 80, height: 60)
        let screenLooking = ScreenLookingSpy(mappedPoint: nil, mappedCell: .mapped(rect: rect))
        let system = SystemSpy(resolutions: [])
        let overlay = OverlaySpy()
        let router = makeRouter(screenLooking: screenLooking, system: system, overlay: overlay)
        let result = try await router.execute(makeCall(ClickyTools.executeAction,
                                                       ["intent": .string("click the video"),
                                                        "action": .string("click_grid"),
                                                        "cell": .string("c5")]))
        XCTAssertEqual(stringField(result, "status"), "executed")
        let gridMapCalls = await screenLooking.gridMapCalls
        XCTAssertEqual(gridMapCalls, ["C5"], "cell labels are normalized before mapping")
        let performs = await system.performs
        XCTAssertEqual(performs.count, 1)
        XCTAssertEqual(performs.first?.kind, .clickGrid)
        XCTAssertEqual(performs.first?.point, CGPoint(x: 440, y: 330), "the cell center is the click point")
        XCTAssertEqual(performs.first?.gridCell, "C5", "the adapter can name what it clicked")
        XCTAssertEqual(performs.first?.gridRect, rect, "the adapter probes AX inside the cell rect")
        guard case .moving(let point) = await overlay.last() else { return XCTFail("ghost preview expected") }
        XCTAssertEqual(point, CGPoint(x: 440, y: 330))
    }

    // MARK: look_at_screen grid requests

    func testLookAtScreenGridRequestReachesTheVisionPortAndPayload() async throws {
        let cursor = ScreenCursorContext(applicationName: "Comet", point: CGPoint(x: 10, y: 20))
        let screenLooking = ScreenLookingSpy(mappedPoint: nil,
                                             lookOutcome: .frameSent(cursor: cursor,
                                                                     pixelSize: CGSize(width: 1280, height: 800)))
        let router = makeRouter(screenLooking: screenLooking)
        let result = try await router.execute(makeCall(ClickyTools.lookAtScreen,
                                                       ["reason": .string("find the video"),
                                                        "grid": .string("12x8")]))
        XCTAssertEqual(stringField(result, "status"), "frame_sent")
        XCTAssertEqual(result.scheduling, .whenIdle)
        let lookCalls = await screenLooking.lookCalls
        XCTAssertEqual(lookCalls.count, 1)
        XCTAssertEqual(lookCalls.first?.grid, ScreenGrid(cols: 12, rows: 8),
                       "the explicit grid travels to the vision port")
        guard case .object(let payload) = result.payload,
              case .object(let grid)? = payload["grid"],
              case .number(let cols)? = grid["cols"],
              case .number(let rows)? = grid["rows"] else { return XCTFail("grid payload expected") }
        XCTAssertEqual(cols, 12)
        XCTAssertEqual(rows, 8)
        guard case .object(let frameSize)? = payload["frame_size"],
              case .number(let width)? = frameSize["width"],
              case .number(let height)? = frameSize["height"] else { return XCTFail("frame_size payload expected") }
        XCTAssertEqual(width, 1280, "the model must know the exact frame width for click_at")
        XCTAssertEqual(height, 800)
        let note = stringField(result, "note") ?? ""
        XCTAssertTrue(note.contains("1280×800"), "the note declares the frame's pixel size")
        XCTAssertTrue(note.contains("0..<1280") && note.contains("0..<800"),
                      "the note declares the accepted click_at conventions")
    }

    func testLookAtScreenBooleanGridUsesTheDefault12x8() async throws {
        let screenLooking = ScreenLookingSpy(mappedPoint: nil,
                                             lookOutcome: .frameSent(cursor: ScreenCursorContext(),
                                                                     pixelSize: CGSize(width: 1024, height: 768)))
        let router = makeRouter(screenLooking: screenLooking)
        let result = try await router.execute(makeCall(ClickyTools.lookAtScreen,
                                                       ["reason": .string("find the video"),
                                                        "grid": .bool(true)]))
        XCTAssertEqual(stringField(result, "status"), "frame_sent")
        let lookCalls = await screenLooking.lookCalls
        XCTAssertEqual(lookCalls.first?.grid, ScreenGrid.defaultGrid)
    }

    func testLookAtScreenRejectsAMalformedGridBeforeTheVisionPort() async throws {
        let screenLooking = ScreenLookingSpy(mappedPoint: nil,
                                             lookOutcome: .frameSent(cursor: ScreenCursorContext(),
                                                                     pixelSize: CGSize(width: 1024, height: 768)))
        let router = makeRouter(screenLooking: screenLooking)
        let result = try await router.execute(makeCall(ClickyTools.lookAtScreen,
                                                       ["reason": .string("find the video"),
                                                        "grid": .string("huge")]))
        XCTAssertEqual(stringField(result, "status"), "invalid_args")
        XCTAssertEqual(result.scheduling, .interrupted)
        let lookCalls = await screenLooking.lookCalls
        XCTAssertEqual(lookCalls.count, 0, "a malformed grid never reaches the vision port")
    }

    func testLookAtScreenWithoutGridReportsFrameSizeAndNoGridPayload() async throws {
        let screenLooking = ScreenLookingSpy(mappedPoint: nil,
                                             lookOutcome: .frameSent(cursor: ScreenCursorContext(),
                                                                     pixelSize: CGSize(width: 1024, height: 768)))
        let router = makeRouter(screenLooking: screenLooking)
        let result = try await router.execute(makeCall(ClickyTools.lookAtScreen,
                                                       ["reason": .string("what is on screen")]))
        XCTAssertEqual(stringField(result, "status"), "frame_sent")
        let lookCalls = await screenLooking.lookCalls
        XCTAssertEqual(lookCalls.first?.grid, nil)
        guard case .object(let payload) = result.payload else { return XCTFail("payload expected") }
        XCTAssertNil(payload["grid"], "no grid payload unless the overlay was requested")
        guard case .object(let frameSize)? = payload["frame_size"],
              case .number(let width)? = frameSize["width"],
              case .number(let height)? = frameSize["height"] else { return XCTFail("frame_size payload expected") }
        XCTAssertEqual(width, 1024)
        XCTAssertEqual(height, 768)
        let note = stringField(result, "note") ?? ""
        XCTAssertTrue(note.contains("1024×768"))
    }
}

actor KillSwitchSpy: KillSwitchPort {
    private(set) var triggers: [String] = []
    func triggerKillSwitch(source: String) async { triggers.append(source) }
}
actor FailingSystemSpy: SystemActionPort {
    private(set) var performCount = 0
    func resolve(title: String?, kind: ClickyActionKind) async -> ResolvedTarget? { makeTarget() }
    func perform(_ action: ResolvedAction) async -> ActionOutcome {
        performCount += 1
        return .failed(reason: "hardware unavailable")
    }
}
final class TimeBox: @unchecked Sendable {
    var now: Date; init(_ now: Date = Date()) { self.now = now }
}
extension ToolRouterTests {
    func testPerTurnActionBudgetEnforced() async throws {
        let system = SystemSpy(resolutions: [makeTarget(), makeTarget(), makeTarget()])
        let router = ToolRouter(ledger: LedgerSpy(allowed: true), risk: RiskStub(tier: .reversible),
                                screenContext: ContextStub(snapshot: ScreenContext(applicationName: "A", windowTitle: "W", elements: [])),
                                system: system,
                                overlay: OverlaySpy(), gate: GateScript(decision: .confirmed(source: .voiceTranscript)),
                                sleeper: ImmediateSleeper(), actionBudget: 2)
        let first = try await router.execute(GeminiToolCall.FunctionCall(id: "b1", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")]))
        XCTAssertEqual(stringField(first, "status"), "executed")
        let second = try await router.execute(GeminiToolCall.FunctionCall(id: "b2", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")]))
        XCTAssertEqual(stringField(second, "status"), "executed")
        let third = try await router.execute(GeminiToolCall.FunctionCall(id: "b3", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")]))
        XCTAssertEqual(stringField(third, "status"), "budget_exceeded")
        XCTAssertEqual(third.scheduling, .interrupted)
        let performs = await system.performs.count
        XCTAssertEqual(performs, 2)
    }
    func testBeginTurnReplenishesBudgetAndClearsCallIDs() async throws {
        let system = SystemSpy(resolutions: [makeTarget(), makeTarget()])
        let router = ToolRouter(ledger: LedgerSpy(allowed: true), risk: RiskStub(tier: .reversible),
                                screenContext: ContextStub(snapshot: ScreenContext(applicationName: "A", windowTitle: "W", elements: [])),
                                system: system,
                                overlay: OverlaySpy(), gate: GateScript(decision: .confirmed(source: .voiceTranscript)),
                                sleeper: ImmediateSleeper(), actionBudget: 1)
        let call = GeminiToolCall.FunctionCall(id: "turn-1", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")])
        let first = try await router.execute(call)
        XCTAssertEqual(stringField(first, "status"), "executed")
        let overBudget = try await router.execute(GeminiToolCall.FunctionCall(id: "turn-2", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")]))
        XCTAssertEqual(stringField(overBudget, "status"), "budget_exceeded")
        await router.beginTurn()
        let replayed = try await router.execute(call)
        XCTAssertEqual(stringField(replayed, "status"), "executed", "a new turn replenishes budget and forgets prior call ids")
    }
    func testDuplicateToolCallIDIsDeduplicated() async throws {
        let fixture = makeFixture()
        let call = GeminiToolCall.FunctionCall(id: "call-dup", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")])
        let first = try await fixture.router.execute(call)
        XCTAssertEqual(stringField(first, "status"), "executed")
        let dup = try await fixture.router.execute(call)
        XCTAssertEqual(stringField(dup, "status"), "duplicate")
        XCTAssertEqual(dup.scheduling, .interrupted)
        let performs = await fixture.system.performs.count
        XCTAssertEqual(performs, 1)
    }
    func testActionRateLimitingThrottlesRapidDispatches() async throws {
        let box = TimeBox(Date(timeIntervalSince1970: 1000))
        let router = ToolRouter(ledger: LedgerSpy(allowed: true), risk: RiskStub(tier: .reversible),
                                screenContext: ContextStub(snapshot: ScreenContext(applicationName: "A", windowTitle: "W", elements: [])),
                                system: SystemSpy(resolutions: [makeTarget(), makeTarget()]),
                                overlay: OverlaySpy(), gate: GateScript(decision: .confirmed(source: .voiceTranscript)),
                                sleeper: ImmediateSleeper(), minActionInterval: 0.2, now: { box.now })
        let first = try await router.execute(GeminiToolCall.FunctionCall(id: "r1", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")]))
        XCTAssertEqual(stringField(first, "status"), "executed")
        let rapid = try await router.execute(GeminiToolCall.FunctionCall(id: "r2", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")]))
        XCTAssertEqual(stringField(rapid, "status"), "rate_limited")
        box.now = box.now.addingTimeInterval(0.25)
        let ok = try await router.execute(GeminiToolCall.FunctionCall(id: "r3", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")]))
        XCTAssertEqual(stringField(ok, "status"), "executed")
    }
    func testCircuitBreakerTripsAndEscalatesToKillSwitch() async throws {
        let killSpy = KillSwitchSpy()
        let failingSystem = FailingSystemSpy()
        let router = ToolRouter(ledger: LedgerSpy(allowed: true), risk: RiskStub(tier: .reversible),
                                screenContext: ContextStub(snapshot: ScreenContext(applicationName: "A", windowTitle: "W", elements: [])),
                                system: failingSystem, overlay: OverlaySpy(),
                                gate: GateScript(decision: .confirmed(source: .voiceTranscript)),
                                sleeper: ImmediateSleeper(), failureThreshold: 2, killSwitch: killSpy)
        _ = try await router.execute(GeminiToolCall.FunctionCall(id: "f1", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")]))
        _ = try await router.execute(GeminiToolCall.FunctionCall(id: "f2", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")]))
        let triggers = await killSpy.triggers
        XCTAssertEqual(triggers, ["circuit_breaker"])
        let postTrip = try await router.execute(GeminiToolCall.FunctionCall(id: "f3", name: ClickyTools.executeAction, args: ["intent": .string("t"), "action": .string("click")]))
        XCTAssertEqual(stringField(postTrip, "status"), "circuit_breaker_tripped")
        XCTAssertEqual(postTrip.scheduling, .interrupted)
        let performCount = await failingSystem.performCount
        XCTAssertEqual(performCount, 2)
        // The one-shot escalation guard in `recordFailure` (`!isCircuitBreakerTripped`)
        // is reachable only when concurrent in-flight dispatches both pass the breaker
        // pre-check; that reentrancy path is verified by inspection, not pinned here
        // (coverage gap recorded in the chunk errata).
    }
    func testBeginTurnResetsFailureStreakButNotTheBreakerLatch() async throws {
        let killSpy = KillSwitchSpy()
        let failingSystem = FailingSystemSpy()
        let router = ToolRouter(ledger: LedgerSpy(allowed: true), risk: RiskStub(tier: .reversible),
                                screenContext: ContextStub(snapshot: ScreenContext(applicationName: "A", windowTitle: "W", elements: [])),
                                system: failingSystem, overlay: OverlaySpy(),
                                gate: GateScript(decision: .confirmed(source: .voiceTranscript)),
                                sleeper: ImmediateSleeper(), failureThreshold: 3, killSwitch: killSpy)
        func failingCall(_ id: String) -> GeminiToolCall.FunctionCall {
            GeminiToolCall.FunctionCall(id: id, name: ClickyTools.executeAction,
                                        args: ["intent": .string("t"), "action": .string("click")])
        }
        // Two failures, a turn boundary, then two more: the streak is per-turn,
        // so the breaker must not latch (live testing: three minor errors spread
        // across a 20-minute session must not kill the session).
        _ = try await router.execute(failingCall("turn1-f1"))
        _ = try await router.execute(failingCall("turn1-f2"))
        await router.beginTurn()
        let secondTurnFirst = try await router.execute(failingCall("turn2-f1"))
        let secondTurnSecond = try await router.execute(failingCall("turn2-f2"))
        XCTAssertEqual(stringField(secondTurnFirst, "status"), "failed")
        XCTAssertEqual(stringField(secondTurnSecond, "status"), "failed")
        var triggers = await killSpy.triggers
        XCTAssertTrue(triggers.isEmpty, "2 failures + beginTurn + 2 failures must not trip the breaker")
        // A third failure inside one turn does trip and escalates exactly once.
        let tripping = try await router.execute(failingCall("turn2-f3"))
        XCTAssertEqual(stringField(tripping, "status"), "failed")
        triggers = await killSpy.triggers
        XCTAssertEqual(triggers, ["circuit_breaker"], "3 failures within one turn escalate exactly once")
        let latched = try await router.execute(failingCall("turn2-f4"))
        XCTAssertEqual(stringField(latched, "status"), "circuit_breaker_tripped")
        XCTAssertEqual(latched.scheduling, .interrupted)
        // The latch is session-scoped: beginTurn resets the streak, never the latch.
        await router.beginTurn()
        let stillLatched = try await router.execute(failingCall("turn3-f1"))
        XCTAssertEqual(stringField(stillLatched, "status"), "circuit_breaker_tripped",
                       "beginTurn must not clear the session-scoped breaker latch")
        triggers = await killSpy.triggers
        XCTAssertEqual(triggers, ["circuit_breaker"], "the kill switch never re-triggers")
    }
    func testOpenURLTextReachesTheRiskClassifier() async throws {
        let risk = RiskSpy(tier: .reversible)
        let router = ToolRouter(ledger: LedgerSpy(allowed: true), risk: risk,
                                screenContext: ContextStub(snapshot: ScreenContext(applicationName: "Safari",
                                                                                   windowTitle: "Start", elements: [])),
                                system: SystemSpy(resolutions: [nil]),
                                overlay: OverlaySpy(), gate: GateScript(decision: .confirmed(source: .voiceTranscript)),
                                sleeper: ImmediateSleeper())
        let result = try await router.execute(GeminiToolCall.FunctionCall(
            id: "open-url-1", name: ClickyTools.executeAction,
            args: ["intent": .string("open youtube"), "action": .string("open_url"),
                   "text": .string("https://www.youtube.com")]))
        XCTAssertEqual(stringField(result, "status"), "executed")
        let calls = await risk.calls
        XCTAssertEqual(calls.count, 1)
        guard let call = calls.first else { return XCTFail("the risk port must see the action") }
        XCTAssertEqual(call.kind, .openURL)
        XCTAssertEqual(call.text, "https://www.youtube.com",
                       "the URL must reach the classifier so the allowlist check can see the host")
    }

    // MARK: navigate

    func testNavigateDispatchesURLAndBrowserToTheSystemPort() async throws {
        let system = SystemSpy(resolutions: [nil])
        let router = ToolRouter(ledger: LedgerSpy(allowed: true), risk: RiskStub(tier: .reversible),
                                screenContext: ContextStub(snapshot: ScreenContext(applicationName: "Comet",
                                                                                   windowTitle: "Start", elements: [])),
                                system: system,
                                overlay: OverlaySpy(), gate: GateScript(decision: .confirmed(source: .voiceTranscript)),
                                sleeper: ImmediateSleeper())
        let result = try await router.execute(GeminiToolCall.FunctionCall(
            id: "navigate-1", name: ClickyTools.executeAction,
            args: ["intent": .string("open linkedin in chrome"), "action": .string("navigate"),
                   "text": .string("https://www.linkedin.com"), "browser": .string("Chrome")]))
        XCTAssertEqual(stringField(result, "status"), "executed")
        let performs = await system.performs
        XCTAssertEqual(performs.count, 1)
        XCTAssertEqual(performs.first?.kind, .navigate)
        XCTAssertEqual(performs.first?.text, "https://www.linkedin.com")
        XCTAssertEqual(performs.first?.browser, "Chrome", "the named browser travels with the action")
    }

    func testNavigateURLReachesTheRiskClassifier() async throws {
        let risk = RiskSpy(tier: .reversible)
        let router = ToolRouter(ledger: LedgerSpy(allowed: true), risk: risk,
                                screenContext: ContextStub(snapshot: ScreenContext(applicationName: "Chrome",
                                                                                   windowTitle: "Start", elements: [])),
                                system: SystemSpy(resolutions: [nil]),
                                overlay: OverlaySpy(), gate: GateScript(decision: .confirmed(source: .voiceTranscript)),
                                sleeper: ImmediateSleeper())
        let result = try await router.execute(GeminiToolCall.FunctionCall(
            id: "navigate-2", name: ClickyTools.executeAction,
            args: ["intent": .string("go to youtube"), "action": .string("navigate"),
                   "text": .string("https://www.youtube.com/watch?v=abc123")]))
        XCTAssertEqual(stringField(result, "status"), "executed")
        let calls = await risk.calls
        XCTAssertEqual(calls.count, 1)
        guard let call = calls.first else { return XCTFail("the risk port must see the action") }
        XCTAssertEqual(call.kind, .navigate)
        XCTAssertEqual(call.text, "https://www.youtube.com/watch?v=abc123",
                       "the URL must reach the classifier so the allowlist and query-string tiering apply")
    }

    func testNavigateWithoutURLIsInvalidArgs() async throws {
        let system = SystemSpy(resolutions: [nil])
        let router = makeRouter(system: system)
        let result = try await router.execute(makeCall(ClickyTools.executeAction,
                                                       ["intent": .string("go to youtube"),
                                                        "action": .string("navigate")]))
        XCTAssertEqual(stringField(result, "status"), "invalid_args")
        XCTAssertEqual(result.scheduling, .interrupted)
        let performs = await system.performs.count
        XCTAssertEqual(performs, 0, "a malformed navigate never reaches the OS")
    }
}
