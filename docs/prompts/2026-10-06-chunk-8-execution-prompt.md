# Execute Clicky Chunk 8 — safety gates (~3.5 h)

You are the **orchestrator**. Execute Chunk 8 of the Clicky implementation plan (repo: `/Users/pranav1296/clicky`) exactly as written, using **subagent-driven development** per the plan header §1.1. Chunk 7 is complete and tagged `chunk-7-input-synthesis` (`8191877`); its review-driven errata (`acad184`, including the D7.2 test-data fix and the `PressOutcome.noTargetPoint` case) are part of the plan record — do not modify or re-litigate them, and do not disturb the Chunk 5.5 files or the demo paths.

## 0. Pre-flight (do first, in order)

1. Read `AGENTS.md` (§4.2 claims discipline, §4.3 secrets, §5 workflow, §6 boundaries, §9 ask-before-acting) and the plan's **Chunk 8** in full; re-grep boundaries — do not trust fixed offsets:
   ```bash
   grep -n '^## Chunk 8\|^### Task 8\|^## Chunk 9' docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md
   ```
2. Verify repo state: `git log --oneline -6` must contain `8191877 chunk 7 complete: input synthesis` (any commits on top must be docs-only, e.g. `acad184 docs: record chunk 7 errata` and the `docs: add chunk 8 execution prompt` commit); `git tag --list 'chunk-*'` must include `chunk-7-input-synthesis` and **no** `chunk-8-*`; `git status --porcelain` clean; `pgrep -fl caffeinate` (start `caffeinate -i` in the background if not running).
3. Baseline (verify with your own runs; do not re-derive): release build clean; full suite **106 = 98 passed + 8 skipped** (`swift test`; count distinct `Test Case '...' passed` lines — the swift-testing footer is noise; the 8 skipped are the 5 pre-existing gated tests + the 3 gated `InputIntegrationTests`); `swift test --filter ClickySafetyTests` = **1** (`RiskTierTests.testOrderingAndGateProperties` — XCTest prints the singular `Executed 1 test, with 0 failures`). The demos — scripted `--scripted-demo` and the Chunk 5.5 `--live-demo` — are the working paths and stay untouched by this chunk.
4. Pre-checked plan-vs-reality facts (verified in advance; do not re-litigate): `Sources/ClickySafety/RiskTier.swift` already provides the ordered 5-tier `RiskTier` (read 1 < reversible 2 < irreversible 3 < financial 4 < prohibited 5, with `requiresGhostCursor` / `requiresSpokenConfirmation` / `requiresAmountReadBack` / `isBlocked`) and is **reused unchanged** — read it before Task 8.1; only `Sources/ClickySafety/**` and `Tests/ClickySafetyTests/**` may change until the completion commit; `Package.swift` must **not** change (`ClickySafety` already depends on `ClickyCore`; system frameworks only); all chunk-8 code is pure logic with injected clocks — **no `[manual OS check]` steps and no API key**; every task's code block compiles against the existing module (the only import is Foundation).
5. Artifacts dir: `/private/var/folders/7m/p85t2ft12ts2spdd0cr1t5mh0000gn/T/opencode/clicky-orchestration/chunk-8/` (never in the repo). The task texts are pre-extracted there (`chunk-8-context.md`, `task-8.1-text.md` … `task-8.5-text.md`, `standing-instructions.md`); re-verify boundaries with the grep above and re-extract if any range differs.

## 1. Procedure (plan §1.1 — REQUIRED)

- **Per task (8.1 → 8.4):** fresh implementer subagent — `opencode-go/deepseek-v4.1-flash#high` or your harness's equivalent; **no Gemini/agy runs** — given the full task text verbatim (never conversation history) + the standing instructions: precondition HEAD; exact files; exact commit message; run every command; TDD red states genuine; complete bodies — no placeholders/TODOs; minimal compile-necessary deviations only, each reported; count tests by distinct `Test Case '...' passed` lines + per-suite `Executed` lines (XCTest uses singular `Executed 1 test`); never push/tag/amend/README; report format (per-step outputs, deviations, counts, `git log --oneline -1`, `git status --porcelain`, `git show --stat HEAD`, status).
- **Then the plan's two per-task review gates** (fresh context each, `#max` — e.g. `opencode-go/deepseek-v4.1-flash#max` — over `git show HEAD`):
  1. **Spec-compliance reviewer** (plan §1.2 template): every step executed; files match the plan's paths; code matches the plan's shapes exactly; verification tags honored; no TODOs/placeholders; commit message exact.
  2. **Code-quality reviewer** (plan §1.2 template): error handling, actor isolation (the gate/ledger are actors; no `@MainActor` on their work), single-responsibility per file, naming, no dead code, tests assert behavior, no force-unwraps without prior guards.
  - Fix loop with the **same implementer** (re-dispatch by sessionID) until both approve; never proceed with open issues.
- **Orchestrator verifies mechanically after each task:** rerun the relevant filter yourself, count, inspect commit scope, check the exact commit subject; record a dated plan errata note only for genuine plan-vs-reality divergence.
- **Claims discipline is a hard gate:** the 8 s / 10 s / 60 s / 500 ms / 3 s constants are spec/errata-defined product behavior, never measurements; no performance number may appear in code, comments, messages, or reports unless actually measured. This chunk introduces no timing claims.
- **Expected quality-gate watch item:** Task 8.1's title-based financial rule assigns `tier = .financial` (not `tier = max(tier, .financial)`), so an element that already fired a prohibited rule (secure subrole / `AXProtectedContent` role / prohibited bundle) and then matches a financial title would have `.prohibited` downgraded to `.financial` — a local monotonicity violation ("the gate can never lower a tier"; `RiskTier` order above). The plan's tests do not combine those cases. Let the quality reviewer evaluate it; if it fixes, the fix must be minimal (`tier = max(tier, .financial)`) and must keep the plan's tests passing (they run unchanged), and the deviation is recorded. Do **not** pre-fix it in the implementer dispatch.
- **Do not flag as defects (plan-intended):** `.read` deliberately returns Tier 1 even for secure fields (inspection posts no events and macOS suppresses secure values to external clients — `testReadsAreTierOne` asserts this); the `AXSecureTextField` check is subrole-first (errata B1); `RiskTier.swift` is not touched.

## 2. Task specifics (files, commits, expected filter counts)

| Task | Files (all under `Sources/ClickySafety/` and `Tests/ClickySafetyTests/`) | Commit subject | `ClickySafetyTests` after |
|---|---|---|---|
| 8.1 | `RiskGatekeeper.swift` + `RiskGatekeeperTests.swift` | `feat(safety): add local 5-tier risk gatekeeper with trilingual rules` | 9 |
| 8.2 | `IntentLedger.swift` + `IntentLedgerTests.swift` + `TestClock.swift` (shared test clock, reused by 8.4) | `feat(safety): add intent ledger binding tool calls to user utterances` | 15 |
| 8.3 | `AmountNormalizer.swift` + `AmountNormalizerTests.swift` | `feat(safety): add local amount normalizer for financial confirmations` | 20 |
| 8.4 | `PendingActionGate.swift` + `PendingActionGateTests.swift` | `feat(safety): add pending action gate with echo gate and TOCTOU revalidation` | 31 |

The task texts carry the exact code and test expectations — the implementer uses them verbatim. Key invariants the reviewers must confirm:

- **8.1:** classification is local and deterministic; egress (URL with parameters, non-allowlisted domain, missing URL, web-field typing, clipboard write, form submit, outbound message) → Tier 3+ with `isEgress == true`; financial titles → Tier 4; terminal/sudo/keychain/credential targets → Tier 5 (English/Hindi/Marathi keywords); `AXSecureTextField` checked as **subrole** (errata B1); the model can raise a tier but never lower it; `NavigationPolicy` matches exact hosts/suffixes only (no `evilwikipedia.org` or `wikipedia.org.evil.com` bypass); `SafetyText` whole-token matching, no diacritic folding (Devanagari matras must survive).
- **8.2:** only voice/text-command utterances create intents; a call is authorized only when every token of one anchor appears in a recorded intent inside the 120 s window; capacity pruning keeps the newest intents; blank text/anchors refuse (`.noAnchors`); the T10 property — screen-originated anchors are refused before reaching the risk gate.
- **8.3:** `₹500` / `paanch sau` / `५००` / `पाँच सौ` normalize equal on-device; digit formats (`Rs.1,250`, `1,50,000`, Devanagari digits, decimals); compound numbers (`दो हजार पाँच सौ`, `do hazaar paanch sau`, `पाचशे`, `sau`, `five hundred`); matches inside transcripts; non-amount phrases return nil.
- **8.4:** the timer starts only at prompt `turnComplete`; adjustable 8–60 s with an 8 s floor (errata C2); pause-on-speech freezes the countdown and speech end extends the deadline; echo gate blocks while TTS is audible; financial lock 3 s + local amount normalization (errata C3 — the model never judges money); ≥500 ms arm window is a hard floor with TOCTOU revalidation at the end (errata C1); negation cancels in every state; kill/negation inside the arm window abort before execute; no `.execute` without revalidation; every failure mode fails closed.

## 3. Acceptance (Task 8.5 — exact order)

1. `swift build -c release 2>&1 | tail -2` → `Build complete!` (0 warnings) and the full suite → 0 failures. Expected arithmetic: baseline 106 (98 passed + 8 skipped) + 30 unit = **136 executed = 128 passed + 8 skipped**; `swift test --filter ClickySafetyTests` → **`Executed 31 tests, with 0 failures`** (1 Chunk-1 `RiskTierTests` method + 30 new: 8 + 6 + 5 + 11). Verify every count from actual output — never assert one you did not read.
2. No `[manual OS check]` steps in this chunk — all pure logic with injected clocks; do not invent any.
3. Acceptance checklist: `swift build` clean · all tests green · risk gate coverage (egress / financial / prohibited / model-raise) · T10 intent-ledger property · amount triad equal · gate timer + 8 s floor + pause-on-speech + ≥500 ms arm window + TOCTOU + negation-in-every-state · `grep -rn "TODO\|FIXME" Sources/ClickySafety Tests/ClickySafetyTests` empty · `git status` clean.
4. **Chunk reviewer** (`#max`, fresh context, plan §1.2 template) over `git diff chunk-7-input-synthesis..HEAD`. The reviewer must see: **C1** (≥500 ms arm window is a hard floor; TOCTOU revalidation at the end of the window), **C2** (timer starts after prompt `turnComplete`; adjustable with an 8 s floor; pauses while user speech is detected), **C3** (echo gate + local amount normalization — the model never judges money), **C5** (intent ledger + egress tiering + URL allowlist), **B1** (`AXSecureTextField` as subrole); no TODOs; no force-unwraps without prior guards; nothing claimed as measured that was not. Fix loop until `Approved` (fixes commit as `<type>(scope): address chunk 8 review findings`).
5. **Completion — only after the chunk reviewer approves:** set Chunk 8's status to `✅ Done` in the README roadmap table (leave other rows unchanged), then:
   ```bash
   git add README.md
   git commit -m "chunk 8 complete: safety gates"
   git tag chunk-8-safety
   ```
   `git tag --list 'chunk-*'` must then show `chunk-8-safety`. **No push** unless the user explicitly says so. **Do not start Chunk 9 before the reviewer approves.** Afterwards, record the dated plan errata note (genuine divergences only, e.g. the watch-item outcome and any count delta) as a separate `docs: record chunk 8 errata` commit in the Chunk 8 header, per the Chunk 6/7 precedent.

## 4. Safety / key handling / boundaries

- Chunk 8 needs **no API key**: keep the normal test loop keyless; never read `~/.clicky-gemini-key`; never print, echo, commit, or log key material — `git grep -I -l -E 'AIza[0-9A-Za-z_-]{35}' 2>/dev/null` must stay empty.
- Do not modify the Chunk 5.5 files (`LiveConversationRunner`, `DemoClickGate`, `PCMChunks`, `MicrophoneCapture`, `StreamingAudioPlayer`, the run sheet), `Sources/ClickyApp/**`, the demo paths, `Sources/ClickyAccessibility/**` (Chunk 6 record), or `Sources/ClickyInput/**` (Chunk 7 record).
- `Sources/ClickySafety/RiskTier.swift` (Chunk 1) is reused unchanged — no edits.
- Never run anything with `CLICKY_INPUT_INTEGRATION=1`; there are no manual OS checks in this chunk.
- No unmeasured claim anywhere: no timing number is written unless a real measurement produced it.

## 5. Final report format

Stop after Chunk 8. Report: per-task status (files, commit hash + subject, both reviewer verdicts and any fix commits); measured counts with exact commands (baseline 106 → final 136 executed / 128 passed / 8 skipped; filter 31); chunk reviewer verdict; errata notes (only genuine divergences); confirmation that the demos were untouched, no key material was touched or logged, no push happened, and Chunk 9 was not started; anything not run labeled pending. No invented numbers.
