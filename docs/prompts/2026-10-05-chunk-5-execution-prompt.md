# Execute Clicky Chunk 5 — Gemini resilience, mock mode & live spike

You are the **orchestrator**. Execute Chunk 5 of the Clicky implementation plan (repo: `/Users/pranav1296/clicky`) exactly as written, using **subagent-driven development** per the plan header §1.1. Chunk 4 and the Chunk 4.5 demo insertion are complete; evaluation round 2 has been shown. The user has a **`GEMINI_API_KEY` ready** for the live spike (Task 5.3) — coordinate its use without ever exposing it.

## 0. Pre-flight (do first, in order)

1. Read AGENTS.md (§4 commit discipline, §4.2 honesty, §4.3 secrets, §9 ask-before-acting) and the plan's Chunk 5: re-grep boundaries — do not trust fixed offsets —
   `grep -n '^## Chunk 5\|^### Task 5\|^## Chunk 6' docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md`
   and read Chunk 5 in full, including: the **Chunk 4.5 dated note** (Task 5.2 mock-integration), the **count erratum recorded 2026-10-05** ("align chunk 5 expected test counts with chunk 4 erratum"), and the **three known follow-ups at the top of Chunk 4** (re-entrant `start()` — "re-check when `performReconnect` lands"; same-instance restart state reset — "if Chunk 5 makes the client long-lived"; stop-notice wording — "revisit with Chunk 5's retry messaging").
2. Verify repo state: `git log --oneline -1` must show `docs: add chunk 5 execution prompt`; `git status --porcelain` clean; `pgrep -fl caffeinate` running (start `caffeinate -i` if not).
3. Known context carried over (do not re-derive; verify with your own runs):
   - Measured baseline: full **46** (13 foundation + 33 Gemini = 1 pacing + 12 protocol + 4 transport + 10 client + 6 detector), release build clean, 0 warnings. Chunk 4.5's demo slice is built and **user-verified — do not re-verify it**; just don't break it.
   - Count corrections already recorded in the plan (dated note): Task 5.1 Step 5 → Gemini **38** (33 + 5); Task 5.4 Step 1 → full **57** with 3 skipped (no key) or 57 run (keyed). Task 5.2's `Executed 3 tests` filter and Task 5.4 Step 2 are unaffected.
   - Task 5.1's "exact replacement" snippets were authored against plan-era Chunk 4 code. The committed client carries recorded deviations: the `encode(_:)` helper (`.withoutEscapingSlashes`); the setup-timeout generation guard + `do/catch`; `stop()` resolving a pending `readyContinuation` with `.transportUnavailable`; captured `doomed` transport close; fresh-session `cancelledToolCallIDs.removeAll()`; `Task.isCancelled` in `finishToolCall`. Apply the **intent** of the replacements to the current file, keep all existing corrections intact, and report any adaptation precisely.
   - Chunk 4.5 demo files exist: `Sources/ClickyOverlay/GhostCursorController.swift`, `Sources/ClickyApp/ScriptedDemoTransport.swift`, `Sources/ClickyApp/ScriptedDemoRunner.swift`, plus AppDelegate wiring. The demo must keep working (`swift run ClickyApp --scripted-demo` smoke-builds and runs).

## 1. Procedure (same as Chunk 4)

- Artifacts dir: `/private/var/folders/7m/p85t2ft12ts2spdd0cr1t5mh0000gn/T/opencode/clicky-orchestration/chunk-5/` (never in the repo).
- **Extract task texts verbatim FIRST** (before any plan edit): `sed -n` ranges from the grep boundaries; keep `task-5.N-text.md` + `task-5.N-prompt.md` (standing-instructions header + verbatim text).
- Fresh implementer subagent per task, sequential, DeepSeek V4.1 Flash `#high` (or your harness's equivalent; **no Gemini/agy runs**). Standing instructions must include: precondition HEAD; exact files; exact commit message; run every command; TDD red states are genuine; minimal compile-necessary fixes only, each reported; count tests by distinct `Test Case '...' passed` lines + per-suite `Executed` lines (swift-testing footer is noise); no TODOs/placeholders; never push/tag/amend/README; report format (per-step outputs, deviations, `git log --oneline -1`, `git status --porcelain`, `git show --stat HEAD`, status).
- After each task: **spec-compliance review** (`#max`, fresh) → fix → **code-quality review** (`#max`, fresh) → fix. Verify implementer claims mechanically (byte-diff vs plan blocks, rerun suites yourself and count, inspect commit scope). Record dated plan errata only for genuine plan-vs-reality divergence; surface them.
- Commit list expected (subject to fix loops): `feat(gemini): add resumable session cache and goAway reconnect with backoff` → `feat(gemini): add local mock session replaying the demo scenario` → `test(gemini): add day-0 live API spike with pass/fail criteria` → (spike-outcome docs note, see below) → `chunk 5 complete: gemini resilience`.

## 2. Task specifics

### Task 5.1 — Session resumption + `goAway` reconnect with backoff
- Create `Sources/ClickyGemini/GeminiReconnect.swift` (`ReconnectPolicy`, `SleepProviding`, `RealSleeper`, `ImmediateSleeper`); create `Tests/ClickyGeminiTests/GeminiReconnectTests.swift` (5 tests); modify `Sources/ClickyGemini/GeminiLiveClient.swift` (add the `sleeper:` init parameter + `reconnectTask` + reconnect-on-`goAway`/transport-loss with fresh-session fallback).
- Red state: `cannot find 'ReconnectPolicy' in scope`, `cannot find 'SleepProviding' in scope`. Green: `swift test --filter ClickyGeminiTests` → **38 tests, 0 failures** (the plan prints 36 — the dated erratum supersedes).
- While implementing, address the three Chunk 4 follow-ups listed in §0.3 — at minimum: **re-check the re-entrant `start()` hazard now that reconnect lands** (a settling `establish` re-reading `connectGeneration`); decide + document the same-instance restart state reset (reconnect keeps the session — think: resume vs fresh session); check retry-message wording. Record decisions in the task report; add a one-line dated note to the Chunk 5 errata area only if you change behavior beyond the task text.
- Commit exactly: `git add Sources/ClickyGemini/GeminiReconnect.swift Sources/ClickyGemini/GeminiLiveClient.swift Tests/ClickyGeminiTests/GeminiReconnectTests.swift` + the message above.

### Task 5.2 — Local mock mode (the demo fallback)
- Create `Sources/ClickyGemini/MockSession.swift` + `Tests/ClickyGeminiTests/MockSessionTests.swift` (3 tests). Red: `cannot find 'MockSession' in scope`; green: `swift test --filter MockSessionTests` → **3 tests, 0 failures**; Gemini suite → **41**.
- **Chunk 4.5 integration (per the dated note):** if feasible *without changing the demo's beats*, replace the app-side `ScriptedDemoTransport` with `MockSession` + a real-time sleeper (add the real-time sleeper where it belongs; define the demo's scenario JSON in the app), updating `ScriptedDemoRunner` accordingly and deleting the old transport. If not feasible in this task's scope, keep both and record why (one line in the task report + the demo still works). Either way, smoke-check that `swift run ClickyApp --scripted-demo` still builds and runs (you may rely on the user's earlier verification for visual behavior; do not re-verify visually unless something changed).
- Commit exactly: `git add Sources/ClickyGemini/MockSession.swift Tests/ClickyGeminiTests/MockSessionTests.swift` + the message above (plus the app-side files if the replacement shipped — report the exact scope used).

### Task 5.3 — Day-0 live API spike (real key, real network)
- Create `Tests/ClickyGeminiTests/LiveSpikeTests.swift` (3 tests; each `XCTSkip`s without `GEMINI_API_KEY`). Keyless check: `swift test --filter LiveSpikeTests` → `3 tests, 3 skipped, 0 failures`. Keyed run: `swift test --filter LiveSpikeTests` with the key in the environment → `3 tests, 0 failures` within ~60 s.
- **Key handling (non-negotiable):** never print, echo, paste, commit, or screenshot the key; ensure the **normal test-loop shell has `GEMINI_API_KEY` unset** (the plan: do not run the live spike in the normal loop). Agree with the user on one of: (a) they run the keyed command themselves and give you the result lines; (b) they place the key in a file outside the repo (e.g. `~/.clicky-gemini-key`) and you source it per command inside a subshell: `(set -a; source ~/.clicky-gemini-key; set +a; swift test --filter LiveSpikeTests)` — capture counts only.
- Fallbacks per the plan's pass/fail criteria: sensitivity spelling → change the two rawValue constants in `GeminiAutomaticActivityDetection` (single site); `scheduling` placement → move the field into the response payload in `GeminiFunctionResponse` (single site) **and update any protocol fixtures/tests that pin the old shape, consistently** — record a dated errata note with exact counts. Inconclusive third test (model didn't call the tool) → re-run; do not change code.
- After the keyed run, record the outcome as a **dated note in the plan** (Chunk 5 area): date, pass/fallback, exact numbers. Commit: `docs: record chunk 5 live-spike outcome`. If a fallback was applied, the code change goes in the spike commit and the note in this docs commit.
- Commit the test file exactly: `git add Tests/ClickyGeminiTests/LiveSpikeTests.swift` + the message above.

### Task 5.4 — Chunk 5 Acceptance
Run every step for real and capture raw outputs:
1. `swift build -c release` → `Build complete!`, **0 warnings**; `swift test` (keyless shell) → **57 tests, with 3 skipped and 0 failures** (count passed-case lines too).
2. `swift test --filter MockSessionTests` → **3 tests, 0 failures**.
3. Keyed spike (per §2 Task 5.3's coordination) → **3 tests, 0 failures** (~60 s); record date + fallbacks (already noted per 5.3).
4. Protocol audit: `! grep -rq '"mediaChunks"' Sources Tests` → clean; `! grep -rq '"gemini-3.1' Sources Tests` → clean; `! grep -rq '"INTERRUPT"' Sources` → clean; `grep -rn "gemini-3.1" Sources Tests` → exactly **one** hit (the `MockSession.swift` comment documenting the deliberately-unused fallback).
5. Checklist: build clean + tests green + spike skips cleanly without a key; resumable-only caching + `goAway` reconnect ≤2 s margin + fresh-session fallback announced; dropped socket fails in-flight tool calls closed (no response leaks into the new session); mock replay through the real dispatch path; `grep -rn "TODO\|FIXME" Sources Tests Package.swift` empty; `git status` clean, no artifacts/keys staged.
6. **Chunk reviewer** (fresh context, `#max`) over `git diff chunk-4-gemini-client-core..HEAD` as one unit. Must verify: A2 (mock mode, never the 3.1 fallback), A7 (resumable-only caching), A9 (`INTERRUPTED` spelling; spike outcome recorded — errata note if a fallback was applied), A3 (`realtimeInput` shapes untouched), no regressions, claims discipline. Fix-loop until `Approved`.
7. Only on approval: README — Chunk 5 row `⬜ Planned` → `✅ Done`, and refresh the measured line (e.g. "`swift test` of Chunk 5: 57 tests, 0 failures, 3 live-spike tests skipped without a key — measured 2026-10-05; release build clean with 0 warnings from a clean scratch build; keyed live spike passed <date>"). Then:
   ```bash
   git add README.md
   git commit -m "chunk 5 complete: gemini resilience"
   git tag chunk-5-gemini-resilience
   ```
   Push `main` + tag; `gh release create chunk-5-gemini-resilience --title "Chunk 5 — Gemini Resilience, Mock Mode & Spike" --notes-file <notes>` with **measured results only** (trajectory 46 → 51 → 54 → 57; acceptance outputs; spike outcome).

## 3. Finish and report

Stop after Chunk 5. Final report must contain: per-task status; **measured** counts with exact commands (46 → 51 → 54 → 57; note the 56→57 alignment); acceptance outputs (release build, full + filtered counts, protocol audit incl. the single `gemini-3.1` comment hit); spike outcome (date, pass/fallback, key handling — never the key); reviewer verdicts; decisions on the three Chunk 4 follow-ups; commit list; tag `chunk-5-gemini-resilience` + GitHub release URL; all dated notes surfaced; confirmation **Chunk 6 was not started**; anything not run labeled pending. No invented numbers.
