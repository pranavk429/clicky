# Execute Clicky Chunk 9 — LocalVAD + local kill switch (~2 h)

You are the **orchestrator**. Execute Chunk 9 of the Clicky implementation plan (repo: `/Users/pranav1296/clicky`) exactly as written, using **subagent-driven development** per the plan header §1.1. Chunk 8 is complete and tagged `chunk-8-safety` (`e6d2f80`); its review-driven errata (`32588fb docs: record chunk 8 errata`) are part of the plan record — do not modify or re-litigate them, and do not disturb the Chunk 5.5 files, the Chunk 6–8 files, or the demo paths.

## 0. Pre-flight (do first, in order)

1. Read `AGENTS.md` (§4.2 claims discipline, §4.3 secrets, §5 workflow, §6 boundaries, §9 ask-before-acting) and the plan's **Chunk 9** in full; re-grep boundaries — do not trust fixed offsets:
   ```bash
   grep -n '^## Chunk 9\|^### Task 9\|^## Chunk 10' docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md
   ```
   Verified 2026-10-06: `## Chunk 9` 7288 · Task 9.1 7298 · Task 9.2 7442 · Task 9.3 7792 · `## Chunk 10` 7844.
2. Verify repo state: `git log --oneline -6` must contain `e6d2f80 chunk 8 complete: safety gates` and `32588fb docs: record chunk 8 errata` (any commits on top must be docs-only, e.g. the `docs: add chunk 9 execution prompt` commit); `git tag --list 'chunk-*'` must include `chunk-8-safety` and **no** `chunk-9-*`; `git status --porcelain` clean; `pgrep -fl caffeinate` (start `caffeinate -i` in the background if not running).
3. Baseline (verify with your own runs; do not re-derive — measured 2026-10-06): release build clean; full suite **136 = 128 passed + 8 skipped** (`swift test`; count distinct `Test Case '...' passed` lines — the swift-testing footer is noise; the 8 skipped are the 5 pre-existing gated tests + the 3 gated `InputIntegrationTests`); `swift test --filter ClickyAudioTests` = **7 passed**; `swift test --filter ClickyInputTests` = **28 executed = 25 passed + 3 gated skipped**; `swift test --filter ClickySafetyTests` = **31**. The demos — scripted `--scripted-demo` and the Chunk 5.5 `--live-demo` — are the working paths and stay untouched by this chunk.
4. Pre-checked plan-vs-reality facts (verified 2026-10-06; do not re-litigate):
   - `AudioLevel.rms(_ samples: [Int16]) -> Float` already exists in `Sources/ClickyAudio/AudioLevel.swift` and is exactly the API Task 9.1 calls (RMS of 320×12 000 samples ≈ 0.366, above the 0.03 onset threshold).
   - No `LocalVAD` / `GlobalHotKey` / `KillSwitchManager` / `SyntheticInputPanic` symbol exists anywhere yet — no collisions.
   - `Carbon` already imports and links in `ClickyInput` (`Sources/ClickyInput/SecureInputGuard.swift`) and in app targets (`Carbon.HIToolbox`), so `Package.swift` must **not** change and no linker settings are needed.
   - `ContinuousClock.now` (static) and `Duration.components` usage compile on this toolchain — verified with a scratch script: `ContinuousClock.now - .milliseconds(120)` measured 120.0 ms; Carbon constants are `kVK_ANSI_X` 7, `kVK_Space` 49, `cmdKey` 256, `shiftKey` 512.
   - `swift test --filter "A|B"` is a regex alternation — verified (`RiskGatekeeperTests|IntentLedgerTests` → 14 executed).
   - Logger subsystem convention is `com.clicky.mac` (`Sources/ClickyInput/EventSynthesizer.swift`), matching the plan's `KillSwitchManager` logger.
   - Only `Sources/ClickyAudio/**` + `Tests/ClickyAudioTests/**` (Task 9.1) and `Sources/ClickyInput/**` + `Tests/ClickyInputTests/**` (Task 9.2) may change until the completion commit. Task 9.2 is **add-only** in `ClickyInput`: existing `EventSynthesizer.swift` / `SecureInputGuard.swift` / `UnicodeChunker.swift` (Chunk 7 record) stay untouched; `EventSynthesizer.releaseHeldInput()` already exists and is *not* a duplicate of the new `SyntheticInputPanic` (the app wires both in Chunk 10). All chunk-9 code is pure logic plus main-thread Carbon registration — **no API key, no microphone needed by the unit tests**.
5. `[manual OS check]` handling: Task 9.3 Step 3 defines the ⌘⇧X kill procedure, but the app registers the chords in Task 10.2 — per plan, that procedure is **executed on the first wired build (Chunk 10)** and its log attached to the Chunk 10 acceptance. Do **not** run the signed app or the audio self-test in this chunk, and do **not** fake the check; the contract is pinned by unit tests (Task 9.3 Step 1). State it as `defined, deferred to Chunk 10 per plan` in the final report.
6. Artifacts dir: `/private/var/folders/7m/p85t2ft12ts2spdd0cr1t5mh0000gn/T/opencode/clicky-orchestration/chunk-9/` (never in the repo). The task texts are pre-extracted there (`chunk-9-context.md`, `task-9.1-text.md` … `task-9.3-text.md`, `standing-instructions.md`); re-verify boundaries with the grep above and re-extract if any range differs.

## 1. Procedure (plan §1.1 — REQUIRED)

- **Per task (9.1 → 9.2):** fresh implementer subagent — `opencode-go/deepseek-v4.1-flash#high` or your harness's equivalent; **no Gemini/agy runs** — given the full task text verbatim (never conversation history) + the standing instructions: precondition HEAD; exact files; exact commit message; run every command; TDD red states genuine; complete bodies — no placeholders/TODOs; minimal compile-necessary deviations only, each reported; count tests by distinct `Test Case '...' passed` lines + per-suite `Executed` lines (XCTest uses singular `Executed 1 test`); never push/tag/amend/README; report format (per-step outputs, deviations, counts, `git log --oneline -1`, `git status --porcelain`, `git show --stat HEAD`, status).
- **Then the plan's two per-task review gates** (fresh context each, `#max` — e.g. `opencode-go/deepseek-v4.1-flash#max` — over `git show HEAD`):
  1. **Spec-compliance reviewer** (plan §1.2 template): every step executed; files match the plan's paths; code matches the plan's shapes exactly; verification tags honored (`[unit test]` here except the deferred manual procedure); no TODOs/placeholders; commit message exact.
  2. **Code-quality reviewer** (plan §1.2 template): error handling, thread-safety/Sendable (`GlobalHotKey`/`KillSwitchManager` are `@unchecked Sendable`, `LocalVAD` is a value struct), single-responsibility per file, naming, no dead code, tests assert behavior, no force-unwraps without prior guards.
  - Fix loop with the **same implementer** (re-dispatch by sessionID) until both approve; never proceed with open issues.
- **Orchestrator verifies mechanically after each task:** rerun the relevant filters yourself, count, inspect commit scope, check the exact commit subject; record a dated plan errata note only for genuine plan-vs-reality divergence.
- **Claims discipline is a hard gate:** the ~30–80 ms onset and the <150 ms local stop are spec/architecture targets (Validation 01 §2.3), never measurements; the `T7−T1` barge-in anchor is instrumentation whose test only bounds a synthetic 110–<500 ms window — no performance number may appear in code, comments, messages, or reports unless actually measured. This chunk introduces no measured latency claim.
- **Plan-intended shapes (do not flag as defects):** `LocalVAD` is a `struct` with `mutating` process methods (value semantics for the audio callback — not an actor); `GlobalHotKey.register()` is documented main-thread-only and `KillSwitchManager`'s hooks are app-supplied (UI hooks hop to the main queue themselves); `SyntheticInputPanic.releaseAll()` posts modifier key-ups and mouse-ups even for inputs that are not held (documented safe direction — errata C4); the hotkey path records **no** latency anchor (`nil`) by design (T7−T1 exists only for the voice-onset path).
- **If the chunk reviewer requires fixes:** commit them as `<type>(scope): address chunk 9 review findings`.

## 2. Task specifics (files, commits, expected checks after)

| Task | Files | Commit subject | Checks after |
|---|---|---|---|
| 9.1 | `Sources/ClickyAudio/LocalVAD.swift` + `Tests/ClickyAudioTests/LocalVADTests.swift` | `feat(audio): add LocalVAD energy-onset barge-in state machine` | `--filter LocalVADTests` → 5; `ClickyAudioTests` → 12 (7 + 5) |
| 9.2 | `Sources/ClickyInput/GlobalHotKey.swift` + `KillSwitchManager.swift` + `Tests/ClickyInputTests/GlobalHotKeyTests.swift` + `KillSwitchManagerTests.swift` | `feat(input): add Carbon global hotkeys and local kill-switch manager` | filter `KillSwitchManagerTests` + `GlobalHotKeyTests` (regex alternation) → 6; `ClickyInputTests` → 34 executed = 31 passed + 3 gated skipped |

The task texts carry the exact code and test expectations — the implementer uses them verbatim. Key invariants the reviewers must confirm:

- **9.1:** onset fires only after `onsetFrames` consecutive frames ≥ `onsetThreshold` and fires once per burst; a burst ends only after `releaseFrames` consecutive frames < `releaseThreshold` (hysteresis); `reset()` clears active speech; `process(samples:)` delegates to `AudioLevel.rms`; single spikes and quiet input never fire.
- **9.2:** the interruption latch flips **before any hook runs** (readers of `isInterrupted` fail closed) and is idempotent until `reset()`; kill hook order is stopPlayback → releaseSyntheticInput → banner → stopSession, barge-in is stopPlayback only; `clickyKillSwitchFired` posts after **every** trigger; ⌘⇧Space and ⌘⇧X chords carry ⌘⇧ modifiers, never bare keys (errata B13); kill posts modifier key-ups + mouse-ups (panic release, errata C4); the latency anchor records only when an onset instant is supplied.

## 3. Acceptance (Task 9.3 — exact order)

1. `swift test --filter "LocalVADTests|KillSwitchManagerTests|GlobalHotKeyTests" 2>&1 | tail -3` → **`Executed 11 tests, with 0 failures`**.
2. `swift build -c release 2>&1 | tail -2` → `Build complete!` (0 warnings) and the full suite → 0 failures. Expected arithmetic: baseline 136 (128 passed + 8 skipped) + 11 unit = **147 executed = 139 passed + 8 skipped**; verify every count from actual output — never assert one you did not read.
3. Manual OS check (⌘⇧X): **defined, deferred to Chunk 10** per the plan (chords register in Task 10.2) — do not run, do not fake; record as deferred in the final report.
4. Acceptance checklist: `swift build` clean · all tests green · VAD onset/hysteresis pinned by tests · kill latch-before-hooks pinned · panic release present (C4) · chords carry modifiers (B13) · `grep -rn "TODO\|FIXME" Sources Tests Package.swift` empty · `git status` clean · no build artifacts staged.
5. **Chunk reviewer** (`#max`, fresh context, plan §1.2 template) over `git diff chunk-8-safety..HEAD`. The reviewer must see: onset is the primary stop (server `interrupted` is confirmation only); latch-before-hooks (fail-closed readers keep working); synthetic-modifier + mouse-up panic release on kill (errata C4); Carbon chords carry modifiers, never bare keys (errata B13); `clickyKillSwitchFired` posts after every trigger; no TODOs; no force-unwraps without prior guards; nothing claimed as measured that was not. Fix loop until `Approved`.
6. **Completion — only after the chunk reviewer approves:** set Chunk 9's status to `✅ Done` in the README roadmap table (leave other rows unchanged), then:
   ```bash
   git add README.md
   git commit -m "chunk 9 complete: audio and local stop"
   git tag chunk-9-audio-stop
   ```
   `git tag --list 'chunk-*'` must then show `chunk-9-audio-stop`. **No push** unless the user explicitly says so. **Do not start Chunk 10 before the reviewer approves.** Afterwards, record the dated plan errata note (genuine divergences only) as a separate `docs: record chunk 9 errata` commit in the Chunk 9 header, per the Chunk 6/7/8 precedent.

## 4. Safety / key handling / boundaries

- Chunk 9 needs **no API key** and no microphone: keep the normal test loop keyless; never read `~/.clicky-gemini-key`; never print, echo, commit, or log key material — `git grep -I -l -E 'AIza[0-9A-Za-z_-]{35}' 2>/dev/null` must stay empty.
- Do not modify the Chunk 5.5 files (`LiveConversationRunner`, `DemoClickGate`, `PCMChunks`, `MicrophoneCapture`, `StreamingAudioPlayer`, the run sheet), `Sources/ClickyApp/**`, the demo paths, `Sources/ClickyAccessibility/**` (Chunk 6 record), `Sources/ClickySafety/**` (Chunk 8 record), or the existing Chunk 7 `ClickyInput` files (`EventSynthesizer.swift`, `SecureInputGuard.swift`, `UnicodeChunker.swift`) — Task 9.2 adds new files only.
- `Package.swift` must **not** change (system frameworks only).
- Never run anything with `CLICKY_INPUT_INTEGRATION=1`; the only `[manual OS check]` is the ⌘⇧X procedure, deferred to Chunk 10 per plan.
- No unmeasured claim anywhere: no timing number is written unless a real measurement produced it.

## 5. Final report format

Stop after Chunk 9. Report: per-task status (files, commit hash + subject, both reviewer verdicts and any fix commits); measured counts with exact commands (baseline 136 → final 147 executed / 139 passed / 8 skipped; focused filter 11); chunk reviewer verdict; errata notes (only genuine divergences); confirmation that the demos were untouched, no key material was touched or logged, no push happened, and Chunk 10 was not started; the ⌘⇧X manual OS check stated as defined-but-deferred to Chunk 10; anything not run labeled pending. No invented numbers.
