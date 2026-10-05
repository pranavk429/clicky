# Execute Clicky Chunk 7 — input synthesis (~3 h)

You are the **orchestrator**. Execute Chunk 7 of the Clicky implementation plan (repo: `/Users/pranav1296/clicky`) exactly as written, using **subagent-driven development** per the plan header §1.1. Chunk 6 is complete and tagged `chunk-6-accessibility-engine` (`613cbd1`); its errata notes (`59276ae`, `ef2cc8f`) are part of the plan record — do not modify or re-litigate them, and do not disturb the Chunk 5.5 files or the demo paths.

## 0. Pre-flight (do first, in order)

1. Read `AGENTS.md` (§4.2 claims discipline, §4.3 secrets, §5 workflow, §6 boundaries, §9 ask-before-acting) and the plan's **Chunk 7** in full; re-grep boundaries — do not trust fixed offsets:
   ```bash
   grep -n '^## Chunk 7\|^### Task 7\|^## Chunk 8' docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md
   ```
2. Verify repo state: `git log --oneline -6` must contain `613cbd1 chunk 6 complete: accessibility engine` (any commits on top must be docs-only, e.g. the `docs: add chunk 7 execution prompt` commit); `git tag --list 'chunk-*'` must include `chunk-6-accessibility-engine` and **no** `chunk-7-*`; `git status --porcelain` clean; `pgrep -fl caffeinate` (start `caffeinate -i` in the background if not running).
3. Baseline (verify with your own runs; do not re-derive): release build clean; full suite **81 = 76 passed + 5 skipped** (`swift test`; count distinct `Test Case '...' passed` lines — the swift-testing footer is noise; the 5 skipped are the 3 pre-existing `LiveSpikeTests` + the 2 gated `AXLiveCrawlTests`); `swift test --filter ClickyInputTests` = **3** (`UnicodeChunkerTests`) — note filtered runs print trailing `Executed 0 tests` empty-suite lines *after* the real counts, so count distinct `Test Case` lines, not the last `tail` line. The demos — scripted `--scripted-demo` and the Chunk 5.5 `--live-demo` — are the working paths and stay untouched by this chunk.
4. Pre-checked plan-vs-reality facts (verified in advance; do not re-litigate): `Sources/ClickyInput/UnicodeChunker.swift` already provides `chunk(_:)` and `maxUTF16UnitsPerEvent` (20) — every task that references them compiles against this; `Tests/ClickyInputTests/UnicodeChunkerTests.swift` has exactly 3 tests; only `Sources/ClickyInput/**` and `Tests/ClickyInputTests/**` may change until the completion commit; `Package.swift` must **not** change (the target exists; system frameworks only).
5. Artifacts dir: `/private/var/folders/7m/p85t2ft12ts2spdd0cr1t5mh0000gn/T/opencode/clicky-orchestration/chunk-7/` (never in the repo). The task texts are pre-extracted there (`chunk-7-context.md`, `task-7.1-text.md` … `task-7.5-text.md`, `standing-instructions.md`); re-verify boundaries with the grep above and re-extract if any range differs.

## 1. Procedure (plan §1.1 — REQUIRED)

- **Per task (7.1 → 7.4):** fresh implementer subagent — `opencode-go/deepseek-v4.1-flash#high` or your harness's equivalent; **no Gemini/agy runs** — given the full task text verbatim (never conversation history) + the standing instructions: precondition HEAD; exact files; exact commit message; run every command; TDD red states genuine; complete bodies — no placeholders/TODOs; minimal compile-necessary deviations only, each reported; count tests by distinct `Test Case '...' passed` lines + per-suite `Executed` lines; never push/tag/amend/README; report format (per-step outputs, deviations, counts, `git log --oneline -1`, `git status --porcelain`, `git show --stat HEAD`, status).
- **Then the plan's two per-task review gates** (fresh context each, `#max` — e.g. `opencode-go/deepseek-v4.1-flash#max` — over `git show HEAD`):
  1. **Spec-compliance reviewer** (plan §1.2 template): every step executed; files match the plan's paths; code matches the plan's shapes exactly; verification tags honored; no TODOs/placeholders; commit message exact.
  2. **Code-quality reviewer** (plan §1.2 template): error handling, actor isolation (AX/event work off `@MainActor`, seams intact), single-responsibility per file, naming, no dead code, tests assert behavior, no force-unwraps in OS paths without prior guards.
  - Fix loop with the **same implementer** (re-dispatch by sessionID) until both approve; never proceed with open issues.
- **Orchestrator verifies mechanically after each task:** rerun the relevant filter yourself, count, inspect commit scope, check the exact commit subject; record a dated plan errata note only for genuine plan-vs-reality divergence.
- **Claims discipline is a hard gate:** the spec's "<10 ms local `CGEvent.post`" (spec §4.5) is an **architecture target, never asserted or measured in this chunk**; no performance number may appear in code, comments, messages, or reports unless actually measured. The `AXSecureTextField`-as-subrole rule (errata B1) and the ≤20-UTF-16-unit rule (errata B7) are non-negotiable.
- **Expected quality-gate watch item:** Task 7.3's `pressKey` discards its guard decision and posts the chord regardless of a blocked keystroke decision — per errata B8 keystrokes must be refused while the guard blocks. Let the quality reviewer evaluate it; if it fixes, the fix must be minimal (skip posting / return false when blocked) and must keep the plan's tests passing (they run with secure input off), and the deviation is recorded.

## 2. Task specifics (files, commits, expected filter counts)

| Task | Files (all under `Sources/ClickyInput/` and `Tests/ClickyInputTests/`) | Commit subject | `ClickyInputTests` after |
|---|---|---|---|
| 7.1 | `EventSynthesizer.swift` (seams) + `SecureInputGuard.swift` + `InputTestDoubles.swift` + `SecureInputGuardTests.swift` | `feat(input): add input seams and secure-input guard` | 7 |
| 7.2 | `EventSynthesizer.swift` (append) + `InputTestDoubles.swift` (append) + `EventSynthesizerTests.swift` | `feat(input): add unicode typing with verify-then-pasteboard fallback` | 14 |
| 7.3 | `EventSynthesizer.swift` (append) + `PointerSynthesisTests.swift` | `feat(input): add AX press fallback, click, move and drag synthesis` | 21 |
| 7.4 | `InputIntegrationTests.swift` | `test(input): add env-gated live checks for typing, pointer and secure input` | 24 (3 skipped) |

The task texts carry the exact code and test expectations — the implementer uses them verbatim. Key invariants the reviewers must confirm:

- **7.1:** OS touchpoints behind `EventPosting`/`ElementServices`/`PasteboardWriting` seams (only `System*` types touch hardware); guard is typed per operation — keystrokes blocked on global `IsSecureEventInputEnabled()`, `AXSecureTextField` **subrole** (errata B1), `AXProtectedContent` role, or credential keywords; **pointer operations are never blocked, only logged** (errata B8); `CredentialHeuristic` is word-bounded, case-insensitive, includes Devanagari (`पासवर्ड`, `पिन`, `ओटीपी`), and **fails closed** if the regex cannot be built; the fired rule is logged with the `input.secure` category and private target description.
- **7.2:** entry via `keyboardSetUnicodeString` events of ≤20 UTF-16 units using `UnicodeChunker.chunk` (never splits grapheme clusters — errata B7); verify → pasteboard + ⌘V (keyCode 9, `.maskCommand`) → refuse; the guard is re-checked **before every chunk** and before the paste fallback; clipboard restored after the fallback; empty text and missing focus refuse before any event; `TextEntryOutcome`/`SynthesisPacing` shapes exactly as the plan states; all work on the `EventSynthesizer` actor.
- **7.3:** `AXPressAction` first, hover + click fallback at the given point (or the element's resolved center) on any AX error, reporting the triggering `AXError`; `click(at:)` returns the logged decision and posts `mouseMoved` + `leftMouseDown` + `leftMouseUp`; drag interpolates `.leftMouseDragged` steps and posts `leftMouseUp` at the end; `releaseHeldInput()` completes an interrupted drag with a mouse-up at the **live cursor** and cancels remaining steps (kill-switch hook for Chunk 9); chords post down+up atomically so no modifier is ever held.
- **7.4:** the three live checks skip unless `CLICKY_INPUT_INTEGRATION=1` (the terminal that runs them needs Accessibility permission); no real events post in the normal test loop.

## 3. Acceptance (Task 7.5 — exact order)

1. `swift build -c release 2>&1 | tail -2` → `Build complete!` (0 warnings) and the full suite → 0 failures. Expected arithmetic: baseline 81 (76 passed + 5 skipped) + 18 unit = 99 (94 + 5) + 3 gated integration skipped = **102 executed = 94 passed + 8 skipped**; `swift test --filter ClickyInputTests` → **`Executed 24 tests, with 3 tests skipped and 0 failures`**. Verify every count from actual output — never assert one you did not read.
2. **Manual OS checks — the user performs** (the terminal needs Accessibility; wait for the user's confirmation before proceeding):
   1. **Devanagari typing:** `open -a TextEdit`, File → New, click into the document body, keep it focused, then `CLICKY_INPUT_INTEGRATION=1 swift test --filter InputIntegrationTests/testTypeDevanagariIntoFocusedField` → `Executed 1 test, with 0 failures` and the sentence `नमस्ते, सफारी उघड आणि पुण्याचे हवामान शोध.` appears in the document via direct `keyboardSetUnicodeString` entry (the test asserts `.directVerified`, not the pasteboard path). If focus moved back to the terminal, click into the TextEdit document during the 20-second wait.
   2. **Secure input blocks keystrokes but not clicks:** in Terminal enable Secure Keyboard Entry (menu bar; if your terminal lacks the feature, use Apple Terminal.app); in a second window start `log stream --predicate 'subsystem == "com.clicky.mac" AND category == "input.secure"' --style compact`; run `CLICKY_INPUT_INTEGRATION=1 swift test --filter InputIntegrationTests/testSecureInputBlocksKeystrokesButNotClicks` → `Executed 1 test, with 0 failures`; the log shows `blocked op=keystrokes rule=globalSecureEventInput` and `allowed op=pointerClick rule=globalSecureEventInput` (errata B8 — clicks tracked, never blocked). Turn Secure Keyboard Entry off afterwards. A skip means Secure Keyboard Entry was not actually enabled.
   3. **Pointer move reaches WindowServer:** `CLICKY_INPUT_INTEGRATION=1 swift test --filter InputIntegrationTests/testPointerMoveReachesWindowServer` → `Executed 1 test, with 0 failures`; the pointer visibly jumps to (240, 240).
   If a manual check fails, fix immediately — do not proceed.
3. Acceptance checklist: `swift build` clean · all tests green (24 filter = 21 unit + 3 gated integration skipped by default) · ≤20 UTF-16 units and no grapheme splits · entry chain direct → verify → pasteboard → refuse with clipboard restore · secure input typed decisions + logged rule (B8) · `releaseHeldInput()` completes an interrupted drag · `grep -rn "TODO\|FIXME" Sources/ClickyInput Tests/ClickyInputTests` empty · `git status` clean.
4. **Chunk reviewer** (`#max`, fresh context, plan §1.2 template) over `git diff chunk-6-accessibility-engine..HEAD`. The reviewer must see: **B7** (≤20 UTF-16 units, grapheme-safe, verify → pasteboard → refuse, clipboard restore), **B8** (pointer events never blocked; fired rule logged; typed per-operation decision), all AX/event work off `@MainActor` (actor isolation), no TODOs, no force-unwraps in OS paths without a prior guard; cross-task interface consistency (`TextEntryOutcome`/`PressOutcome`/`SecureInputDecision` shapes as consumed by Chunks 12–13 and Chunk 9's `releaseHeldInput()`); nothing claimed as measured that was not. Fix loop until `Approved` (fixes commit as `<type>(scope): address chunk 7 review findings`).
5. **Completion — only after the chunk reviewer approves:** set Chunk 7's status to `✅ Done` in the README roadmap table (leave other rows unchanged), then:
   ```bash
   git add README.md
   git commit -m "chunk 7 complete: input synthesis"
   git tag chunk-7-input-synthesis
   ```
   `git tag --list 'chunk-*'` must then show `chunk-7-input-synthesis`. **No push** unless the user explicitly says so. **Do not start Chunk 8 before the reviewer approves.**

## 4. Safety / key handling / boundaries

- Chunk 7 needs **no API key**: keep the normal test loop keyless; never read `~/.clicky-gemini-key`; never print, echo, commit, or log key material — `git grep -I -l -E 'AIza[0-9A-Za-z_-]{35}' 2>/dev/null` must stay empty.
- Do not modify the Chunk 5.5 files (`LiveConversationRunner`, `DemoClickGate`, `PCMChunks`, `MicrophoneCapture`, `StreamingAudioPlayer`, the run sheet), `Sources/ClickyApp/**`, or the demo paths.
- The user performs every `[manual OS check]`; wait for their confirmation before proceeding. If a manual check fails, fix immediately — do not proceed.
- Never run `CLICKY_INPUT_INTEGRATION=1` in the normal test loop; the three live checks must report as skipped by default.
- No unmeasured claim anywhere: the `<10 ms` post target stays a target; no timing number is written unless a real measurement produced it.

## 5. Final report format

Stop after Chunk 7. Report: per-task status (files, commit hash + subject, both reviewer verdicts and any fix commits); measured counts with exact commands (baseline 81 → final 102 executed / 94 passed / 8 skipped; filter 24 with 3 skipped); the user's three manual-check outcomes (Devanagari direct-verified, secure-input block/allowed log lines, pointer at (240, 240)); chunk reviewer verdict; errata notes (only genuine divergences); confirmation that the demos were untouched, no key material was touched or logged, no push happened, and Chunk 8 was not started; anything not run labeled pending. No invented numbers.
