# Execute Clicky Chunk 11 — Ghost Cursor overlay (~2 h)

You are the **orchestrator**. Execute Chunk 11 of the Clicky implementation plan (repo: `/Users/pranav1296/clicky`) exactly as written, using **subagent-driven development** per the plan header §1.1. Chunk 10 is complete and tagged `chunk-10-audio-engine` (`f4d58f3`); its review-driven errata (`b103823 docs: record chunk 10 errata`, including the macOS 27 VPIO realities, the measured local-stop values, the manual-check honesty constraints and the user-directed English-first demo note) are part of the plan record — do not modify or re-litigate them, and do not disturb the Chunk 4.5 demo slice (`Sources/ClickyOverlay/GhostCursorController.swift`), the Chunk 6–10 files, or the demo paths.

## 0. Pre-flight (do first, in order)

1. Read `AGENTS.md` (§4.2 claims discipline, §4.3 secrets, §5 workflow, §6 boundaries, §9 ask-before-acting) and the pre-extracted Chunk 11 header `chunk-11-context.md` — **do not read the task texts yourself**; they go to subagents. Re-grep boundaries mechanically — do not trust fixed offsets:
   ```bash
   grep -n '^## Chunk 11\|^### Task 11\|^## Chunk 12' docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md
   ```
   Verified 2026-10-06: `## Chunk 11` 8583 · Task 11.1 8595 · Task 11.2 8822 · Task 11.3 9030 · Task 11.4 9439 · Task 11.5 9548 · `## Chunk 12` 9583.
2. Verify repo state: `git log --oneline -5` must contain `f4d58f3 chunk 10 complete: audio engine` and `b103823 docs: record chunk 10 errata` (any commits on top must be docs-only, e.g. the `docs: add chunk 11 execution prompt` commit); `git tag --list 'chunk-*'` must include `chunk-10-audio-engine` and **no** `chunk-11-*`; `git status --porcelain` clean; `pgrep -fl caffeinate` (start `caffeinate -i` in the background if not running).
3. Baseline (verify with your own runs; do not re-derive — measured 2026-10-06 by the prompt author): `swift build -c release` → `Build complete!`; full suite **152 executed = 144 passed + 8 skipped** (`swift test`; count distinct `Test Case '...' passed` lines — the swift-testing footer is noise; the 8 skipped are the 3 gated `InputIntegrationTests` + the 3 gated `LiveSpikeTests` + the 2 gated `AXLiveCrawlTests`); per-bundle XCTest footers: `ClickyAudioTests` 17 · `ClickyInputTests` 34 (31 passed + 3 gated skipped) · `ClickySafetyTests` 31 · `ClickyGeminiTests` 44 (41 + 3 gated skipped) · `ClickyAccessibilityTests` 19 (17 + 2 gated skipped) · `ClickyCoreTests` 7. `Tests/ClickyOverlayTests/` does not exist and `Package.swift` has no `ClickyOverlayTests` target — Task 11.1 creates both (its insertion line goes directly after the `ClickyAudioTests` line, currently the last test target at `Package.swift:27`). The demos — scripted `--scripted-demo` and the Chunk 5.5 `--live-demo` — are the working paths and stay untouched by this chunk.
4. Pre-checked plan-vs-reality facts (verified 2026-10-06; do not re-litigate):
   - **Existing overlay code:** `Sources/ClickyOverlay/` holds exactly two files: `GhostCursorController.swift` (the Chunk 4.5 demo subset — `public final class GhostCursorController`, `public enum GhostEasing`, and a file-private `private final class GhostCursorView: NSView`) and `OverlayGeometry.swift` (`public enum OverlayGeometry`, reused by Task 11.2 for global-CG → panel-local conversion). Every new type name the chunk introduces was checked against `Sources/`/`Tests/` — all free except the known `GhostCursorView` collision below (`DemoGhostCursorCanvasView` is free).
   - **Demo-path dependency — keep, do not delete (pre-resolved divergence):** `ScriptedDemoRunner.swift` and `LiveConversationRunner.swift` both `import ClickyOverlay` and use `GhostCursorController` extensively (`showOverlay`, `hideOverlay`, `setStatus`, `setIntent`, `moveCursor(to:duration:)`, `showConfirmation`, `dismissConfirmation`, `flashAction`, `showStopped`). `OverlayWindowController` provides none of these (only the four `present*` entry points), so deleting `GhostCursorController.swift` in Chunk 11 would break the build and both working demo paths. The Chunk 11 header's "delete the demo controller / no duplicated overlay code" clause is resolved as: retain the demo file behaviorally untouched, defer its retirement to the integration chunk that rewires the demo paths, and record this divergence in the Chunk 11 errata note. The chunk reviewer must be told this is the accepted resolution.
   - **Name collision + prescribed minimal deviation (scratch-verified 2026-10-06):** Swift rejects a file-private top-level type and an internal top-level type with the same name in one module — a scratch package with `private final class Thing` in A.swift + `struct Thing` in B.swift fails in both default and `.swiftLanguageMode(.v5)` with `error: invalid redeclaration of 'Thing'`. Task 11.3's appended `struct GhostCursorView: View` therefore cannot coexist with the demo file's file-private `GhostCursorView`. In **Task 11.3 only**, rename the old file-private class to `DemoGhostCursorCanvasView` and update its 4 occurrences in `GhostCursorController.swift` (lines 14, 26, 191, 231 as of `b103823` — re-grep first); every other byte of that file stays identical, and the plan's new `struct GhostCursorView: View` plus all Task 11.1–11.3 code stay plan-verbatim. This is an orchestrator-authorized compile-necessary deviation: the implementer reports it; the errata note records it.
   - **Import fix (scratch-verified 2026-10-06):** Task 11.3 Step 1 appends `NSHostingView(rootView:)` to `OverlayWindowController.swift`, whose Task 11.2 imports are AppKit/ClickyCore/Foundation only; `NSHostingView` is not in scope with `import AppKit` alone (`cannot find 'NSHostingView' in scope`) — add `import SwiftUI` to that file in Task 11.3 (one line; report it). `CGWindowID` **is** visible with `import AppKit` alone (no CoreGraphics import needed), and `GhostCursorView.swift` already imports AppKit + Combine + SwiftUI, so the appended views compile as written.
   - **Package.swift:** the one insertion line goes directly after the `.testTarget(name: "ClickyAudioTests", ...)` line (currently `Package.swift:27`), before the closing `]`; deps `["ClickyOverlay", "ClickyCore"]` match the tests' imports. `ClickyApp` already depends on `ClickyOverlay` (`Package.swift:20`) and `ClickyOverlay` on `ClickyCore` (`Package.swift:16`) — no other package changes.
   - **ClickyCore shapes exist as written:** `DisplayGeometry` has a **public** memberwise `init(id:cgFrame:appKitFrame:scaleFactor:)` (`Sources/ClickyCore/CoordinateMath.swift:12`) so Task 11.2's test compiles from the test module; `CoordinateMath.cgFrame(fromAppKit:primaryHeight:)` and `CoordinateMath.display(containing:in:)` exist (lines 21, 24). All Task 11.1/11.2 expected values were hand-verified against these implementations (off-screen `(-2000,500)` → screen 2 → clamped `(0,444)`; `controlPoint` `(0,0)→(100,0)` = `(50,24)`; card centers `214` / `936` / `1738`; banner `(960,44)`; `easedProgress(0.25) = 0.15625`, `(0.75) = 0.84375`).
   - **Expected test-count deltas (verify from actual output — never assert):** Task 11.1 `ClickyOverlayTests` → 9 (`Executed 9 tests, with 0 failures`); Task 11.2 → 16; Task 11.3 → 16; Task 11.4 → 19 with 3 skipped headless (`Executed 19 tests, with 3 tests skipped and 0 failures`); full-suite arithmetic 152 + 19 = **171 executed = 160 passed + 11 skipped** (the 3 `OverlayLiveTests` skip without `CLICKY_OVERLAY_LIVE=1`).
   - **Tag name is `chunk-11-overlay`** — the plan's chunk map (§2, line 153) and Task 11.5 Step 6 both say so; use that exact name (no variant).
   - **Toolchain/SDK shapes compile as written** (`NSPanel(contentRect:styleMask:backing:defer:screen:)`, `animationBehavior = .none`, `sharingType = .none`, `NSDeviceDescriptionKey("NSScreenNumber")`, `NSAccessibility.post(... .announcementRequested ...)`, two-parameter `.onChange(of:)`); Task 11.1 Step 3 and Task 11.2 Step 2 "expect failure" runs are genuine build failures of the new target (the named `cannot find ... in scope` errors).
   - **Manual-check reality:** the live checks need a logged-in desktop session and `CLICKY_OVERLAY_LIVE=1`; the SCK capture check additionally needs Screen Recording TCC for the terminal; the visual, Spaces, multi-display and VoiceOver checks need a human at the machine. Full list: Task 11.4 Steps 3–8 + Task 11.5 Step 3. Multi-display is explicitly non-blocking (record if only one display is available).
5. `[manual OS check]` handling: Task 11.4 Steps 3–8 and Task 11.5 Step 3 define the live state cycle, glass-wall click-through, full-screen/Spaces, multi-display, capture-exclusion and VoiceOver checks. They require **a human at the machine** (clicking/typing/dragging through the overlay, entering native full-screen, running VoiceOver with ⌘F5, judging what is visible) and a logged-in GUI session for `CLICKY_OVERLAY_LIVE=1 swift test` (the live tests are env-gated and never part of the default `swift test`). Coordinate with the user: run the exact commands from the task text, capture the exact outputs (`Executed 1 test, with 0 failures` per live test, the `screencapture` result, what VoiceOver said) and record what was actually observed. **Never fake or simulate a manual check**; if the user cannot perform one (e.g. no second display — the task says do not block on hardware; or no Screen Recording grant — the SCK test self-skips with a grant message), stop and report it as pending rather than claiming it passed. The `screencapture -x /tmp/clicky-overlay-check.png` artifact is temporary — inspect it, then `rm` it; never commit it.
6. Artifacts dir: `/private/var/folders/7m/p85t2ft12ts2spdd0cr1t5mh0000gn/T/opencode/clicky-orchestration/chunk-11/` (never in the repo). The task texts are pre-extracted there (`chunk-11-context.md`, `task-11.1-text.md` … `task-11.5-text.md`); re-verify boundaries with the grep above and re-extract if any range differs (verified extraction: context 8583–8592, 11.1 8595–8818, 11.2 8822–9026, 11.3 9030–9435, 11.4 9439–9544, 11.5 9548–9580; trailing `---` separators excluded).

## 1. Procedure (plan §1.1 — REQUIRED)

- **Per task (11.1 → 11.4):** fresh implementer subagent — `opencode-go/deepseek-v4.1-flash#high` or your harness's equivalent; **no Gemini/agy runs** — given the full task text verbatim (hand it the pre-extracted file path; never conversation history) + the standing instructions: precondition HEAD; exact files; exact commit message; run every command; TDD red states genuine (Task 11.1 Step 3 / Task 11.2 Step 2 must show the named `cannot find ... in scope` build errors); complete bodies — no placeholders/TODOs; minimal compile-necessary deviations only (the two pre-resolved ones below; anything else reported); count tests by distinct `Test Case '...' passed` lines + per-suite `Executed` lines (XCTest uses singular `Executed 1 test`); never push/tag/amend/README; report format (per-step outputs, deviations, counts, `git log --oneline -1`, `git status --porcelain`, `git show --stat HEAD`, status).
  - Task 11.3 dispatch must carry the two pre-resolved deviations explicitly: the `DemoGhostCursorCanvasView` rename in `GhostCursorController.swift` (4 occurrences, no other bytes) and `import SwiftUI` in `OverlayWindowController.swift`.
  - Task 11.4 exception: the implementer executes Steps 1–2 (write the env-gated live tests; headless run → 19 executed / 3 skipped) and commits with the task's exact subject; Steps 3–8 are `[manual OS check]` and are **not attempted by the implementer** — they run in acceptance with the user (the plan's own Task 11.5 Step 3 repeats them).
- **Then the plan's two per-task review gates** (fresh context each, `#max` — e.g. `opencode-go/deepseek-v4.1-flash#max` — over `git show HEAD`); paste-ready, adapted for this chunk:

  **Spec-compliance reviewer (Chunk 11):**
  ```
  You are a spec-compliance reviewer for one task of the Clicky implementation plan.
  - Repo: /Users/pranav1296/clicky. Review ONLY the diff of the latest commit (git show HEAD).
  - Task text (the task the implementer was given): [PASTE FULL TASK TEXT]
  - Check: every step was executed; files match the plan's paths; code matches the plan's
    shapes EXACTLY (only the two pre-authorized deviations are acceptable: the file-private
    demo-class rename in GhostCursorController.swift and `import SwiftUI` in
    OverlayWindowController.swift); verification tags honored ([unit test] / [manual OS check]
    — manual steps deferred to acceptance, not faked); no TODOs/placeholders; commit message
    exact; the pure state → visual mapping matches spec §4.3 (moving blue pointer, review amber
    box, confirm pulsing red + resting pointer, stopped green banner) and the model never
    chooses color or motion.
  - Output: "Approved" or "Issues Found" with a numbered list (file:line, why it matters).
  ```

  **Code-quality reviewer (Chunk 11):**
  ```
  You are a code-quality reviewer for one task of the Clicky implementation plan.
  - Repo: /Users/pranav1296/clicky. Review ONLY the diff of the latest commit (git show HEAD).
  - Check: error handling; @MainActor isolation for panel/UI work; the glass-wall invariant —
    `ignoresMouseEvents = true` is set exactly once, in OverlayPanel.init, and no other line
    touches it; canBecomeKey/canBecomeMain false; the collectionBehavior trio
    [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary] + hidesOnDeactivate = false;
    single-responsibility per file; naming; no dead code; tests assert behavior (not
    implementation); no force-unwraps in OS paths without guards; the confirmation card exposes
    Confirm/Cancel as separate AX elements and the click-through panel never steals focus.
  - Output: "Approved" or "Issues Found" with a numbered list (file:line, why it matters).
  ```

  **Chunk reviewer (Chunk 11)** — plan §1.2 template + Task 11.5 Step 5 must-see list:
  ```
  You are the chunk reviewer for Chunk 11 of the Clicky implementation plan.
  - Repo: /Users/pranav1296/clicky. Review all commits since the previous chunk tag as one unit
    (git log chunk-10-audio-engine..HEAD --oneline; git diff chunk-10-audio-engine..HEAD).
  - Plan: docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md, Chunk 11
    only. Spec: docs/superpowers/specs/2026-10-05-clicky-voice-ai-cursor-design.md §4.3.
  - Check: cross-task interface consistency; every acceptance checklist item actually passes;
    errata B12 recipe exact (.screenSaver, the collection trio, hidesOnDeactivate=false,
    non-key/non-main, ignoresMouseEvents only in init); errata B11 capture exclusion by
    CGWindowID queried at capture time; panels pre-created by an idempotent start() (the
    first-present safety net is the only other creation site, documented as such); the four
    present* entry points matching Chunk 13's OverlayAdapter; OverlayGeometry reused for
    global→local conversion; the pure state→visual mapping unit-tested; the accessible card is
    VoiceOver-readable with keyboard/switch-reachable actions; no unmeasured claims (the ≤16 ms
    first-frame figure stays labeled a target); the pre-authorized deviations (demo controller
    retained + renamed private class; import SwiftUI) are recorded in the errata note.
  - Output: "Approved" or "Issues Found" with a numbered list.
  ```
- Fix loop with the **same implementer** (re-dispatch by sessionID) until both per-task reviewers approve; never proceed with open issues. Commit review fixes as `<type>(scope): address ... review findings` (Chunk 8–10 precedent; record in errata).
- **Orchestrator verifies mechanically after each task:** rerun the relevant filters yourself, count, inspect commit scope, check the exact commit subject; record a dated plan errata note only for genuine plan-vs-reality divergence (the demo-controller retention + rename and the `import SwiftUI` addition are already known and pre-authorized).
- **Claims discipline is a hard gate:** this chunk produces **no performance measurements** — the spec's first-frame ≤16 ms figure and every other overlay timing stay architecture targets, labeled as such in code, README and reports. No number may appear anywhere unless a real run/log produced it.
- **Plan-intended shapes (do not flag as defects):** `OverlayWindowController.shared` singleton with a private `init`; panels pre-created by an idempotent `start()` and rebuilt on `NSApplication.didChangeScreenParametersNotification`; the first `present` calls `start()` as the documented no-start safety net; `announce` posts `NSAccessibility` announcements because the panels never become key; the card is mouse-click-through but reachable through the accessibility tree (VoiceOver / switch control); `BezierTravelEffect` animates via `GeometryEffect`; the live tests are env-gated and self-skipping.

## 2. Task specifics (files, commits, expected checks after)

| Task | Files | Commit subject | Checks after |
|---|---|---|---|
| 11.1 | Modify `Package.swift` (one test-target line after `ClickyAudioTests`) · Create `Sources/ClickyOverlay/GhostCursorView.swift` (pure model) · Create `Tests/ClickyOverlayTests/GhostCursorVisualTests.swift` | `feat(overlay): add unit-tested ghost cursor visual state model` | `swift test --filter ClickyOverlayTests` → 9 |
| 11.2 | Create `Sources/ClickyOverlay/OverlayWindowController.swift` (pure model) · Create `Tests/ClickyOverlayTests/OverlayPlacementResolverTests.swift` | `feat(overlay): add pure placement resolver and overlay command API` | filter → 16 |
| 11.3 | Modify `Sources/ClickyOverlay/OverlayWindowController.swift` (+ `import SwiftUI`) · Modify `Sources/ClickyOverlay/GhostCursorView.swift` (append SwiftUI views) · Modify `Sources/ClickyOverlay/GhostCursorController.swift` (rename only) | `feat(overlay): add per-screen panels, visual states and accessible confirmation card` | `swift build` → `Build complete!`; filter → 16 |
| 11.4 | Create `Tests/ClickyOverlayTests/OverlayLiveTests.swift` (Steps 1–2 only; Steps 3–8 deferred) | `test(overlay): add env-gated live checks for capture exclusion and state cycle` | filter → 19 executed with 3 skipped; manual checks in acceptance |

The task texts carry the exact code and test expectations — the implementer uses them verbatim (with the §0.4 deviations resolved). Key invariants the reviewers must confirm:

- **11.1:** pure value-type model with no window-server dependency; the state → style mapping pinned (moving: blue, no box, no pulse · review: amber, 3 pt box · confirm: red, 4 pt box, pulses, rests on target · stopped: green, banner); `easedProgress` is the clamped smoothstep cubic; quadratic Bézier endpoints/midpoint exact; control point is the midpoint pushed 24 pt perpendicular with a zero-length guard; card below → flip above → clamp; banner top-center.
- **11.2:** `OverlayCommand.visualState` maps 1:1 (`.hidden` → nil); the resolver converts global-CG → panel-local through `OverlayGeometry`, clamps moving/confirm points into the screen, picks the containing screen or the nearest one (moving/review/confirm) and last-active-then-primary for stopped; `PanelPresentation.accessibilityText` carries label/prompt and `"Clicky stopped. <reason>"`.
- **11.3:** glass-wall recipe exact (errata B12); `panelWindowIDs` refreshed on rebuild (errata B11); `DisplayGeometry.from(screen:primaryHeight:)` uses `NSScreenNumber` + `CoordinateMath.cgFrame`; VoiceOver announcement posted on confirm/stopped; card buttons call `onCardAction`; the two pre-resolved deviations applied and reported.
- **11.4:** live tests env-gated via `XCTSkipUnless`; the SCK check compares `panelWindowIDs` against `SCShareableContent` and self-skips with a grant message without Screen Recording; `testLiveStateCycle` holds each state long enough for the manual pass (4 s / 4 s per screen / 12 s / 5 s).

## 3. Acceptance (Task 11.5 — exact order)

1. `swift build -c release 2>&1 | tail -2` → `Build complete!`; `swift test` → all green, 0 failures; the three `OverlayLiveTests` report skipped (env var unset). Expected arithmetic: baseline 152 (144 passed + 8 skipped) + 19 unit/live-gated = **171 executed = 160 passed + 11 skipped**; verify every count from actual output — never assert one you did not read.
2. `./scripts/doctor.sh && ./scripts/make-app.sh` → doctor exit 0 (doctor warns, not fails, on missing `GEMINI_API_KEY`; it probes the Live API host, so a network failure is a real doctor FAIL — report honestly) and `Built and signed: build/Clicky.app`.
3. Manual OS checks (with the user; exact commands/steps in the task text):
   1. Live cycle: `CLICKY_OVERLAY_LIVE=1 swift test --filter OverlayLiveTests/testLiveStateCycle` → blue pointer, amber box per screen, 12 s red pulsing box + card, green banner; ends `Executed 1 test, with 0 failures`.
   2. Glass wall: TextEdit click/type/drag through and under the overlay → every click/keystroke/drag reaches TextEdit; the overlay never takes focus.
   3. Full-screen + Spaces: overlay stays above native full-screen apps, on all Spaces, stationary under Mission Control.
   4. Multi-display: `CLICKY_OVERLAY_LIVE=1 swift test --filter OverlayLiveTests/testOnePanelPerScreenWithLiveWindowIDs` → 1 test, 0 failures; panel count == `NSScreen.screens.count`; if only one display is available, record it and do not block (per the task text).
   5. Capture exclusion: `CLICKY_OVERLAY_LIVE=1 swift test --filter OverlayLiveTests/testPanelsAreExcludedFromShareableContent` → 1 test, 0 failures (or a self-skip without Screen Recording → record pending); `screencapture -x /tmp/clicky-overlay-check.png` during the confirm state shows no overlay artifacts; then `rm /tmp/clicky-overlay-check.png`.
   6. VoiceOver: ⌘F5 → the prompt is announced; VO+→ reaches the card; VO+Space on Cancel shows `Clicky stopped. card cancel`; Accessibility Inspector lists both buttons (`AXPress` works). If VoiceOver cannot reach the click-through panel, record the finding and escalate per plan hard rule 9 — the announcement still satisfies VoiceOver readability; reachability needs a documented follow-up.
4. Acceptance checklist: `swift build` clean · all tests green (`swift test --filter ClickyOverlayTests` → `Executed 19 tests, with 3 tests skipped and 0 failures`) · doctor exit 0 · one panel per screen pre-created by `start()` + rebuilt on display changes (code + live check) · glass wall: `ignoresMouseEvents` exactly once in `OverlayPanel.init`; `canBecomeKey`/`canBecomeMain` false; collection trio + `hidesOnDeactivate = false` (errata B12) · capture exclusion `panelWindowIDs` read at capture time (errata B11) · pure state → visual mapping unit-tested · card announcement + separate Confirm/Cancel AX elements (manual check passes, or a dated errata note records the finding) · `grep -rn "TODO\|FIXME" Sources Tests Package.swift` empty · `git status` clean · no build artifacts staged · the demo paths (`--scripted-demo`, `--live-demo`) still build and are behaviorally untouched.
5. **Chunk reviewer** (`#max`, fresh context, the Chunk 11 block in §1) over `git diff chunk-10-audio-engine..HEAD`. Fix loop until `Approved`.
6. **Completion — only after the chunk reviewer approves:** set Chunk 11's row (`Ghost Cursor overlay`) to `✅ Done` in the README roadmap table (leave other rows unchanged) and refresh the README's status paragraph, module-layout paragraph and measured test-count line to Chunk 11's state (the `f4d58f3` Chunk 10 precedent — claims discipline: only measured counts; the overlay timing figure stays labeled a target), then:
   ```bash
   git add README.md
   git commit -m "chunk 11 complete: ghost cursor overlay"
   git tag chunk-11-overlay
   ```
   `git tag --list 'chunk-*'` must then show `chunk-11-overlay`. **No push** unless the user explicitly says so. **Do not start Chunk 12 before the reviewer approves.** Afterwards, record the dated plan errata note (genuine divergences only — at least: the demo-controller retention resolution, the `DemoGhostCursorCanvasView` rename, the `import SwiftUI` addition, any review-driven fixes, and the manual-check outcomes as actually observed) as a separate `docs: record chunk 11 errata` commit in the Chunk 11 header, per the Chunk 6–10 precedent.

## 4. Safety / key handling / boundaries

- Chunk 11 needs **no API key**: keep the normal test loop and the live overlay checks keyless; never read `~/.clicky-gemini-key`; never print, echo, commit, or log key material — `git grep -I -l -E 'AIza[0-9A-Za-z_-]{35}' 2>/dev/null` must stay empty. Do not run `--live-demo`.
- **No new dependencies:** `Package.swift` changes by exactly the one `ClickyOverlayTests` line; the only framework additions are source-level `import SwiftUI` (Task 11.3) and `import ScreenCaptureKit` (Task 11.4 test) — both system frameworks, no linker settings.
- Do not modify the demo path files (`ScriptedDemoRunner.swift`, `LiveConversationRunner.swift`), the Chunk 5.5 files (`DemoClickGate`, `PCMChunks`, `MicrophoneCapture`, `StreamingAudioPlayer`, the run sheet), `EscapeHotKey.swift`, the Chunk 6–10 files (`Sources/ClickyAccessibility/**`, `Sources/ClickySafety/**`, `Sources/ClickyGemini/**`, `Sources/ClickyInput/**`, `Sources/ClickyAudio/**`), `Sources/ClickyVision/**`, `Resources/**`, `scripts/**`, or the spec/research docs. Task 11.3's only edit outside the two new files is the pre-authorized rename inside `GhostCursorController.swift` (4 occurrences; zero behavior change).
- Overlay panels must stay non-activating and click-through: `ignoresMouseEvents = true` set once in `OverlayPanel.init` and never toggled; `canBecomeKey`/`canBecomeMain` false; `hidesOnDeactivate = false`; `.screenSaver` level; `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`. The accessibility tree — not the pointer — is the card's activation path.
- No TCC/signing changes: never regenerate/replace the `Clicky-Dev` certificate; do not alter TCC behavior beyond running the app/tests as needed. The live SCK test may need Screen Recording for the terminal — grant it with the user or let the test self-skip (pending); never fake it.
- Never run anything with `CLICKY_INPUT_INTEGRATION=1`; run live overlay tests only as `CLICKY_OVERLAY_LIVE=1 swift test --filter OverlayLiveTests/...` on a logged-in desktop session.
- No unmeasured claim anywhere: this chunk adds no performance measurement; the ≤16 ms first-frame figure and every other overlay timing stays an architecture target.

## 5. Final report format

Stop after Chunk 11. Report: per-task status (files, commit hash + subject, both reviewer verdicts and any fix commits); measured counts with exact commands (baseline 152 → final 171 executed / 160 passed / 11 skipped; focused filter 9 → 16 → 19 with 3 skipped); the manual OS check results **as actually observed** (live-cycle output, glass-wall result, Spaces/full-screen, multi-display availability, capture-exclusion result incl. any self-skip reason, VoiceOver outcome) or explicitly pending with the reason; chunk reviewer verdict; errata notes; confirmation that the demos were untouched, no key material was touched or logged, no push happened, and Chunk 12 was not started; anything not run labeled pending. No invented numbers.
