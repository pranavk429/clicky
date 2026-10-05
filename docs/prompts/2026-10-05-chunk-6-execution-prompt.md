# Execute Clicky Chunk 6 — accessibility engine (~3.5 h)

You are the **orchestrator**. Execute Chunk 6 of the Clicky implementation plan (repo: `/Users/pranav1296/clicky`) exactly as written, using **subagent-driven development** per the plan header §1.1. Chunk 5 is complete and tagged `chunk-5-gemini-resilience`. The user-approved Chunk 5.5 live-conversation slice is complete, reviewed and fixed (`155c9e2`, **no tag by design**) — it must not be disturbed by this chunk.

## 0. Pre-flight (do first, in order)

1. Read `AGENTS.md` (§4.2 claims discipline, §4.3 secrets, §5 workflow, §6 boundaries, §9 ask-before-acting) and the plan's **Chunk 6** in full; re-grep boundaries — do not trust fixed offsets:
   ```bash
   grep -n '^## Chunk 6\|^### Task 6\|^## Chunk 7' docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md
   ```
2. Verify repo state: `git log --oneline -6` must contain `155c9e2 fix(app): address chunk 5.5 review findings` (any commits on top must be docs-only, e.g. the `docs: add chunk 6 execution prompt` commit); `git tag --list 'chunk-*'` must include `chunk-5-gemini-resilience` and **no** `chunk-6-*`; `git status --porcelain` clean; `pgrep -fl caffeinate` (start `caffeinate -i` in the background if not running).
3. Baseline (verify with your own runs; do not re-derive): release build clean; full suite **63 = 60 passed + 3 skipped** (`swift test`; count distinct `Test Case '...' passed` lines — the swift-testing footer is noise; the 3 skipped are the pre-existing `LiveSpikeTests`); `swift test --filter ClickyAccessibilityTests` = **1** (`CrawlerBudgetTests`). The demos — scripted `--scripted-demo` and the Chunk 5.5 `--live-demo` — are the working paths and stay untouched by this chunk.
4. Pre-checked plan-vs-reality facts (verified in advance; do not re-litigate): `Sources/ClickyAccessibility/CrawlerBudget.swift` already provides `interfaceTimeoutSeconds` (0.25), `maxDepth` (5), `maxNodes` (2000), `debounceMilliseconds` (100), `allows(depth:visitedNodes:)` — every task that references them compiles against this. Only `Sources/ClickyAccessibility/**` and `Tests/ClickyAccessibilityTests/**` may change until the completion commit; `Package.swift` must **not** change (the test target exists).
5. Artifacts dir: `/private/var/folders/7m/p85t2ft12ts2spdd0cr1t5mh0000gn/T/opencode/clicky-orchestration/chunk-6/` (never in the repo). On 2026-10-05 the task texts were already extracted there (`chunk-6-context.md`, `task-6.1-text.md` … `task-6.6-text.md`, `standing-instructions.md`); re-verify boundaries with the grep above and re-extract if any range differs.

## 1. Procedure (plan §1.1 — REQUIRED)

- **Per task (6.1 → 6.5):** fresh implementer subagent — `opencode-go/deepseek-v4.1-flash#high` or your harness's equivalent; **no Gemini/agy runs** — given the full task text verbatim (never conversation history) + standing instructions: precondition HEAD; exact files; exact commit message; run every command; TDD red states genuine; complete bodies — no placeholders/TODOs; minimal compile-necessary deviations only, each reported; count tests by distinct `Test Case '...' passed` lines + per-suite `Executed` lines; never push/tag/amend/README; report format (per-step outputs, deviations, counts, `git log --oneline -1`, `git status --porcelain`, `git show --stat HEAD`, status).
- **Then the plan's two per-task review gates** (fresh context each, `#max` — e.g. `opencode-go/deepseek-v4.1-flash#max` — over `git show HEAD`):
  1. **Spec-compliance reviewer** (plan §1.2 template): every step executed; files match the plan's paths; code matches the plan's shapes exactly; verification tags honored; no TODOs/placeholders; commit message exact. Output `Approved` or `Issues Found` with a numbered list (file:line, why it matters).
  2. **Code-quality reviewer** (plan §1.2 template): error handling, actor isolation (AX work off `@MainActor`), single-responsibility per file, naming, no dead code, tests assert behavior, no force-unwraps in OS paths without guards.
  - Fix loop with the **same implementer** (re-dispatch by sessionID) until both approve; never proceed with open issues.
  - Chunk 5.5 used a single combined review by explicit user approval — do **not** assume that here. Chunk 6 follows §1.1's two gates unless the user explicitly approves a lighter model.
- **Orchestrator verifies mechanically after each task:** rerun the relevant filter yourself, count, inspect commit scope, check the exact commit subject; record a dated plan errata note only for genuine plan-vs-reality divergence.
- **Claims discipline is a hard gate:** the live crawl's printed **milliseconds are a measured datum** — record the value verbatim; the Electron/Chromium ~50–200 ms tree-wake band stays labeled **unverified** (errata B6) and the 150 ms retry is a configurable default, never a measured claim.

## 2. Task specifics (files, commits, expected filter counts)

| Task | Files (all under `Sources/ClickyAccessibility/` and `Tests/ClickyAccessibilityTests/`) | Commit subject | `ClickyAccessibilityTests` after |
|---|---|---|---|
| 6.1 | `ElementSnapshot.swift` + `ElementSnapshotTests.swift` | `feat(ax): add normalized element snapshots and cache keys with secure-field detection` | 3 |
| 6.2 | `ElementMatcher.swift` + `ElementMatcherTests.swift` | `feat(ax): add role-aware element matcher scoring` | 7 |
| 6.3 | `AXTreeCrawler.swift` + `AXTreeCrawlerTests.swift` (defines the shared `FakeAXNode`/`FakeAXNodeFactory` that 6.4 reuses) | `feat(ax): add budgeted AX tree crawler with global messaging timeout` | 10 |
| 6.4 | `AXHotCache.swift` + `AXHotCacheTests.swift` | `feat(ax): add AX hot cache with observer debounce and TOCTOU revalidation` | 13 |
| 6.5 | `AXAppAdapters.swift` + `AXAppAdaptersTests.swift` | `feat(ax): add Electron and Chromium AX tree adapters` | 15 |
| 6.6 | `AXLiveCrawlTests.swift` | `test(ax): add permission-gated live crawl and adapter checks` | 17 (2 skipped) |

The task texts carry the exact code and test expectations — the implementer uses them verbatim. Key invariants the reviewers must confirm:

- **6.1:** secure detection is **subrole-first** (errata B1 — `AXSecureTextField` is never treated as a role), then `AXProtectedContent` + whole-word title/placeholder keywords including Devanagari; `normalizedPoint` is the frame midpoint.
- **6.2:** scoring exact 1.0 / contains 0.6 / token-Jaccard ×0.4 (threshold 0.5); role hint ×1.2 on match, ×0.5 on mismatch; disabled ×0.5; **secure fields always 0** (never targets).
- **6.3:** BFS with depth ≤ 5 / ≤ 2000 nodes via `CrawlerBudget`; **one batched fetch per node** (errata B3); global 0.25 s timeout installed once on the system-wide element (errata B2); role-less nodes dropped; AX frames stay in global top-left coordinates (no conversion in this module).
- **6.4:** one per-app `AXObserver` (errata B4; main run loop source but the callback only enqueues — no AX IPC on main); 100 ms debounce; speculative crawl; **TOCTOU `revalidate` fails closed** (mismatch drops the entry); secure fields excluded from lookups.
- **6.5:** file-system family detection; `AXManualAccessibility` (**Electron PR #10305** citation, errata B5) / `AXEnhancedUserInterface`; restore-or-no-op closure; one 150 ms retry labeled unverified (errata B6).
- **Known mechanical gap to allow and report:** 6.5's test text imports only `XCTest` but uses `NSTemporaryDirectory()` — if the compiler requires it, adding `import Foundation` is the minimal allowed deviation; report it.

## 3. Acceptance (Task 6.6 — exact order)

1. Commit the live tests; `swift test --filter ClickyAccessibilityTests` → `Executed 17 tests, with 2 tests skipped and 0 failures`.
2. `swift build -c release 2>&1 | tail -2` → `Build complete!` (0 warnings) and the full suite → 0 failures. Expected arithmetic: baseline 63 executed (60 passed + 3 skipped) + 15 unit = 78 (75 passed + 3 skipped) + 2 gated live skipped = **80 executed = 75 passed + 5 skipped**; verify every count from actual output — never assert one you did not read.
3. **Live-crawl `[manual OS check]` — the user performs:** grant the terminal Accessibility (System Settings → Privacy & Security → Accessibility), open TextEdit with a document window frontmost, then `CLICKY_AX_LIVE=1 swift test --filter AXLiveCrawlTests 2>&1 | tail -6`; expect the test to pass and print `AX live crawl: N elements in X ms` with N > 0. Record the printed ms as the first real crawl datum. **Wait for the user's confirmation.**
4. **Electron/Chromium `[manual OS check]` — the user performs:** VS Code focused, `CLICKY_AX_LIVE=1 CLICKY_AX_PID=$(pgrep -x Code | head -1) swift test --filter testLiveWebTreeAdapter 2>&1 | tail -6`; expect `family=electron treeWake=true` and pass. If the first probe already finds `AXWebArea`, record that the tree was already warm; the 50–200 ms band remains unverified. Optional Chrome repeat (`pgrep -f "Google Chrome"` → `family=chromium`).
5. Acceptance checklist: `swift build` clean · all tests green (15 unit + 2 gated live skipped by default) · live crawl passed · matcher tests cover exact/contains/fuzzy/role/secure/disabled · `grep -rn "TODO\|FIXME" Sources/ClickyAccessibility Tests/ClickyAccessibilityTests` empty · `git status` clean.
6. **Chunk reviewer** (`#max`, fresh context, plan §1.2 template) over `git diff chunk-5-gemini-resilience..HEAD` — this includes Chunk 5.5, which was separately reviewed and fixed in `155c9e2`; focus on Chunk 6. The reviewer must see: errata **B1** (subrole check + heuristics — `AXSecureTextField` never a role), **B2** (system-wide 0.25 s timeout set once), **B3** (one batched fetch per node), **B4** (per-app observer; structure-only notifications; speculative crawls compensate), **B5** (PR #10305 citation; restore/no-op etiquette for `AXEnhancedUserInterface`), **B6** (150 ms retry configurable and labeled unverified); TOCTOU revalidation is fail-closed; secure fields are never match targets; all AX work on the crawler/cache actors, not `@MainActor`. Fix loop until `Approved` (fixes commit as `<type>(scope): address chunk 6 review findings`).
7. **Completion — only after the chunk reviewer approves:** set Chunk 6's status to `✅ Done` in the README roadmap table, then:
   ```bash
   git add README.md
   git commit -m "chunk 6 complete: accessibility engine"
   git tag chunk-6-accessibility-engine
   ```
   `git tag --list 'chunk-*'` must then show `chunk-6-accessibility-engine`. **No push** unless the user explicitly says so. **Do not start Chunk 7 before the reviewer approves.**

## 4. Safety / key handling / boundaries

- Chunk 6 needs **no API key**: keep the normal test loop keyless; never read `~/.clicky-gemini-key`; never print, echo, commit, or log key material — `git grep -I -l -E 'AIza[0-9A-Za-z_-]{35}' 2>/dev/null` must stay empty.
- Do not modify Chunk 5.5 files (`LiveConversationRunner`, `DemoClickGate`, `PCMChunks`, `MicrophoneCapture`, `StreamingAudioPlayer`, the run sheet) or the demo paths.
- The user performs every `[manual OS check]`; wait for their confirmation before proceeding. If a manual check fails, fix immediately — do not proceed.
- No unmeasured claim anywhere: crawl milliseconds are measured data; the wake band stays unverified; the 0.25 s timeout is an implementation constant, not a performance claim.

## 5. Final report format

Stop after Chunk 6. Report: per-task status (files, commit hash + subject, both reviewer verdicts and any fix commits); measured counts with exact commands (baseline 63 → final 80 executed / 75 passed / 5 skipped; filter 17 with 2 skipped); the user's live-crawl and adapter outcomes including the recorded crawl ms; chunk reviewer verdict; errata notes (only genuine divergences); confirmation that the demos were untouched, no key material was touched or logged, no push happened, and Chunk 7 was not started; anything not run labeled pending. No invented numbers.
