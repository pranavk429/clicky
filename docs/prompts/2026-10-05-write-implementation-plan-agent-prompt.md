# Prompt for the Next Agent: Write the Clicky Implementation Plan

Copy everything between the rules below into your next agent session.

---

**Role:** You are a senior macOS/Swift engineering planner. You write plans that OTHER AGENTS execute without you — so every task must be completely self-contained.

**Mission:** Produce the complete, in-depth implementation plan for the Clicky macOS prototype, optimized for subagent-driven execution, from the approved Revision 3 spec.

**Workspace:** `/Users/pranav1296/clicky` (not a git repo yet — your Chunk 1 covers `git init`).

## Read before writing anything (in this order)
1. `docs/superpowers/specs/2026-10-05-clicky-voice-ai-cursor-design.md` — **Revision 3**. Single architectural authority. §4.1–§4.6 contain the corrected protocol shapes, VAD/latency budgets, safety gates, signing/setup flow.
2. `docs/research/validation/05-spec-errata.md` — the 7 build-blockers and 16 corrections you must encode.
3. `docs/research/validation/01-latency-and-live-feel.md` — T0–T12 instrumentation anchors, hybrid VAD tuning, masking techniques.
4. Skim `docs/research/validation/02-competitive-killshots.md`, `03-accessibility-wedge.md`, `04-product-positioning.md`, and the six `docs/research/reports/` files (they carry correction banners — where they conflict with the spec, the spec wins).

## Method (required)
- Invoke and follow the `writing-plans` skill exactly: plan header, bite-sized TDD steps with `- [ ]` checkboxes, exact file paths, complete code, exact commands with expected output, commit per task, and its plan-document-review loop. Announce at the start that you are using that skill.
- Save the plan to: `docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md`
- The plan header MUST include the REQUIRED line directing executors to `superpowers:subagent-driven-development` (fresh subagent per task + two-stage review), with `superpowers:executing-plans` as the no-subagent fallback.
- Structure as exactly these 5 chunks. Each chunk ≤1000 lines and ends with a review checkpoint:

**Chunk 1 — Foundation (~3 h):** repo init + `.gitignore` (`.build/`, `*.app`, secrets) + initial commit; `Package.swift` with module targets (`ClickyCore`, `ClickyGemini`, `ClickyAccessibility`, `ClickyInput`, `ClickySafety`, `ClickyAudio`, `ClickyVision`, `ClickyOverlay`, `ClickyApp`) + test targets, all with `swiftLanguageMode(.v5)`; unit-tested `CoordinateMath` (AppKit ↔ CG ↔ normalized-vision, retina, multi-display); menu-bar skeleton (`NSStatusItem`, session start/stop toggle, listening indicator, quit); permission center + first-run wizard (Accessibility / Screen Recording / Microphone deep links, restart note, per-app Automation pre-trigger, runtime permission watchdog); `Resources/Info.plist` (`LSUIElement`, usage descriptions); corrected signing/bundle scripts (`scripts/sign-dev.sh` — Keychain Certificate Assistant or openssl `pkcs12` + `security import`, NEVER `security create-certificate`; never regenerate the cert; `scripts/make-app.sh` builds and signs `Clicky.app`; `scripts/doctor.sh` pre-flight; `scripts/run.sh`). The demo path is the signed `.app`; `swift run` is dev-only for unit work.

**Chunk 2 — Gemini Live client (~5 h):** `GeminiProtocolTypes` (Codable) + fixture tests using the CORRECT wire format — `realtimeInput.audio` / `.video` blobs (`{"data": "<base64>", "mimeType": "audio/pcm;rate=16000"}`), `realtimeInput.audioStreamEnd`, `toolResponse.functionResponses[].scheduling` ∈ `SILENT | WHEN_IDLE | INTERRUPTED`, `setupComplete` gating, `goAway`, `sessionResumptionUpdate`; transport protocol + fake transport for tests; `GeminiLiveClient` actor (state machine, receive loop that never blocks, tool-call dispatch, cancellation handling); hybrid VAD (client end-of-speech → `audioStreamEnd`, `silenceDurationMs` 350–500, sensitivity HIGH, prefix padding, 20–40 ms chunk pacing); session resumption (cache ONLY `resumable == true` handles) + `goAway` reconnect state machine with backoff and a fresh-session fallback; **local mock mode** (scripted session replayed through the real router/AX path — the demo fallback, NOT the 3.1 model); day-0 real-API spike procedure with pass/fail criteria.

**Chunk 3 — Accessibility engine + input (~7 h):** snapshot normalizer + `CacheKey` (role + **subrole** + title + description), with `kAXSubroleAttribute` `AXSecureTextField` detection; `ElementMatcher` scoring (exact → fuzzy, role-aware, unit-tested); `AXTreeCrawler` (global timeout via `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)`, depth ≤ 5 / 2000 nodes, batched attribute fetch); `AXHotCache` (per-app AXObserver, 100 ms debounce, speculative crawl on VAD onset/app activation, revalidation seam for TOCTOU); `AXAppAdapters` (Electron `AXManualAccessibility` — cite PR #10305 — and Chromium `AXEnhancedUserInterface`, 150 ms retry, restore attribute if set); `EventSynthesizer` (≤20 UTF-16 units per `keyboardSetUnicodeString` call, grapheme-safe chunking tested, verify-then-pasteboard fallback, `AXPressAction` → `CGEvent` click fallback, mouse move/drag); `SecureInputGuard`.

**Chunk 4 — Safety, audio, overlay (~7 h):** `RiskGatekeeper` (5 tiers, TDD with English/Hindi/Marathi keyword cases; egress actions → Tier 3+; LLM can never downgrade; financial → Tier 4; terminal/sudo/keychain/credential → Tier 5); `IntentLedger` (tool calls must bind to a recorded user intent); `PendingActionGate` (echo gate, `AmountNormalizer` for ₹/digits/Devanagari numerals, adjustable 8–10 s timer starting after prompt `turnComplete`, ≥500 ms arm window, TOCTOU revalidation, fail-closed); `LocalVAD` + `KillSwitchManager` (on-device energy-onset stop path as primary; `Cmd+Shift+X` Carbon hotkey; release held synthetic modifiers + mouse-up on kill; banner); `AudioStreamEngine` (VoiceProcessingIO enabled before `start()`, 1024-frame tap @ 48 kHz, single `AVAudioConverter` → 16 kHz, 20 ms chunks, adaptive 2-chunk jitter buffer, RMS mute gate during AEC convergence, `AVAudioEngineConfigurationChange` handling); `OverlayWindowController` + `GhostCursorView` (one pre-created `.screenSaver`-level `NSPanel` per screen, `ignoresMouseEvents` locked in `init`, capture-excluded by `CGWindowID`, states: moving / review / confirm / stopped, accessible confirmation card).

**Chunk 5 — Integration, telemetry, demo (~6 h):** `ToolRouter` + tool declarations (`execute_action`, `confirm_action`, `get_screen_context`) with full JSON schemas in the plan + the complete system instruction text (trilingual persona, exact-AX-title grounding rule, always-respond + filler rule, confirmation scripts); `AppState` end-to-end wiring; `LatencyMeter` (T0–T12 anchors from Validation 01, p50/p95, on-screen demo meter) + `CostModel` (official Gemini rates, ₹85/USD configurable) with unit tests; demo hardening (mock-mode fallback wiring, hot-spot failover, uncut backup video, rehearsal checklist, `doctor.sh`); stretch task (clearly cuttable): benchmark harness for T01–T10 with OS-state assertions.

## Granularity + subagent-execution requirements
- Every task: **Files** (exact create/modify/test paths), then steps of 2–5 minutes: write the failing test → run it and show the expected failure → implement (complete code in the plan) → run and show expected pass → manual OS verification where unavoidable (exact clicks/commands/expected result) → commit with an exact message.
- Tag every verification step as `[unit test]`, `[integration]`, or `[manual OS check]` so the orchestrator knows when a human is required.
- Self-containment: a fresh subagent sees only the plan chunk + the repo. No "as discussed", no "similar to Task X" — include the actual content every time.
- Where something is unverified (AX rebuild time, Electron wake-up, frame token counts), do NOT assert a number — add a measurement step and a documented fallback.
- Include verbatim in the plan: `Package.swift` target graph, all four scripts, `Info.plist`, protocol fixture JSONs, tool declaration schemas, system instruction text, and full test-file bodies for pure logic.
- Add per-chunk time estimates (30-hour hackathon budget) and the scope-cut ladder: vision fallback first, then Marathi tuning, then Tier-2 handlers. Never cut: ghost cursor, voice-triggered AX click, confirmation gate, local stop path.

## Chunk gates (required — encode these in the plan itself)
The plan must make each chunk independently verifiable and committable before the next chunk starts. For every chunk:
- End the chunk with an explicit **"Chunk N Acceptance" task** whose steps are exact commands (build, full test run, the chunk's `[integration]` and `[manual OS check]` procedures) with expected outputs, ending in a chunk-completion commit.
- Define a **Chunk Acceptance Checklist** (definition of done) in the plan: `swift build` clean, all tests green, the chunk's runnable capability demonstrated (state exactly what a human should see/do), no TODOs introduced, repo left in a buildable state.
- Include the orchestration instruction: after the checklist passes, dispatch a **chunk reviewer subagent** (use the `requesting-code-review` / code-quality-reviewer templates) to review the ENTIRE chunk — all task diffs as one unit: spec/plan compliance across tasks, interface consistency, error handling, no regressions. The implementing agent fixes issues and the chunk reviewer re-reviews until approved.
- Only after the chunk reviewer approves: commit/tag the chunk (`chunk N complete: <name>`) and hand off to the next chunk (fresh subagents for its tasks). Never start chunk N+1 with failing chunk N checks or open review issues.

## Execution loop the plan must prescribe (subagent-driven-development)
- Per task: fresh implementer subagent (full task text, never session history) → implement + tests + commit → **spec-compliance reviewer** → fix loop → **code-quality reviewer** → fix loop → mark task complete. Order is fixed: spec review before quality review; never proceed with open issues.
- Per chunk: Acceptance task → chunk reviewer → fix loop → chunk commit → next chunk.
- After the final chunk: whole-implementation review + `finishing-a-development-branch`.
- Include model-selection guidance in the plan: cheap/fast models for mechanical tasks, standard models for integration tasks, most capable models for reviews.

## Plan review loop (writing phase — required)
After each chunk of the plan is written, dispatch a plan-document-reviewer subagent using the `writing-plans` skill's reviewer template (chunk + spec path). Checks: completeness (no TODOs/placeholders), spec alignment, atomic tasks, single-responsibility files, checkbox syntax, chunk ≤1000 lines. Fix issues with the same writer and re-review until approved. Keep reviewer context limited to the chunk + spec — never your session history.

## Hard rules
- Do NOT modify the spec, validation reports, or research reports.
- No placeholders, no TODOs, no "add validation here" — complete code or exact API-level instructions.
- Correct protocol everywhere: `realtimeInput.audio`/`.video` (never `mediaChunks`), `audioStreamEnd`, `scheduling` enum spelling `INTERRUPTED`, resumption only on `resumable == true`, ephemeral-token endpoint `v1beta`, mock mode instead of the 3.1 fallback.
- Never commit secrets; `GEMINI_API_KEY` via environment. Commit after each task.
- The plan must produce honest, measured demo numbers — instrumentation before claims.

## Done means
- Single plan file at the path above, 5 chunks; each plan chunk reviewer-approved; every chunk ends with an explicit Acceptance task and chunk-reviewer gate; task-level two-stage review instructions encoded in the plan header.
- Final report to me: chunk list with line counts, reviewer verdict per chunk, any open questions, and the exact handoff sentence: "Plan complete and saved to `docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md`. Ready to execute with subagent-driven-development?"

---
