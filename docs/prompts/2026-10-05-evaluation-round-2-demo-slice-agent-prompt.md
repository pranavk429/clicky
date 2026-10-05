# Execute Clicky "Chunk 4.5" — evaluation-round-2 scripted ghost-cursor slice (time-critical)

You are the **orchestrator** for the user-approved one-off insertion **Chunk 4.5** of the Clicky implementation plan (repo: `/Users/pranav1296/clicky`). Evaluation round 2 for the CraftVerse 2.0 hackathon is **imminent (~2 hours)**; the user needs a live, visual demonstration of the signature interaction, honestly labeled. This insertion is recorded in the plan with a dated, user-approved note. Read the plan section first.

## 0. Pre-flight (do first)

1. Read: `docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md` **Chunk 4.5** (find via `grep -n '^## Chunk 4.5'`), plus its dated notes at Chunk 5, Chunk 11, and the chunk map. Also skim Chunk 11's header (window recipe: `.screenSaver` level, `ignoresMouseEvents` set once in `init`) and Task 5.2's header (`MockSession`) so nothing conflicts.
2. Verify repo state: `git log --oneline -1` must show `docs: add chunk 4.5 evaluation-round-2 demo slice and execution prompt`; `git status --porcelain` clean. Ensure `caffeinate -i` is running (`pgrep -fl caffeinate`; start it in the background if not).
3. Read `AGENTS.md` §4.2 (claims discipline) and §4.3 (secrets) — this slice must stay honest: **"scripted server, real pipeline"** wherever it is described.

## 1. What exists (do not rebuild)

- Real and tested: `GeminiLiveClient` actor (`setupComplete` gating, single-reader receive loop, tool dispatch via `GeminiToolHandling`, fail-closed `toolCallCancellation`, `GeminiMarker` T3/T4/T6/T8/T12, `GeminiConnectionState`, `StopReason`), the `GeminiTransport` protocol, `GeminiSetupBuilder`, `CoordinateMath` (normalized → CG → AppKit), `OverlayGeometry`, the menu-bar shell (`Sources/ClickyApp/AppDelegate.swift`), `AppState`, and 46/46 tests green. HEAD is tagged `chunk-4-gemini-client-core`.
- Not built (do not build): AX engine, input synthesis, safety gates, audio, vision, real reconnect (Chunks 6–14).

## 2. Frozen scope (these files only)

- Create `Sources/ClickyOverlay/GhostCursorController.swift`
- Create `Sources/ClickyApp/ScriptedDemoTransport.swift`
- Create `Sources/ClickyApp/ScriptedDemoRunner.swift`
- Modify `Sources/ClickyApp/AppDelegate.swift` (menu items + `--scripted-demo` flag; ~30 lines)
- Create `docs/demo/round-2-talk-track.md`
- `Package.swift` must NOT change (ClickyApp already depends on all modules; there is no new test target). Do not touch `README.md`, `scripts/`, `Resources/`, tests, or any other module.

## 3. Frozen interface (implement exactly; latitude only where stated)

### 3.1 `GhostCursorController` (in `ClickyOverlay`)

```swift
import AppKit

@MainActor
public final class GhostCursorController {
    public init()                                                        // main screen, one panel
    public func showOverlay()
    public func hideOverlay()
    public func setStatus(_ text: String)                                // top pill
    public func setIntent(_ text: String?)                               // label under cursor
    public func moveCursor(to screenPoint: CGPoint, duration: TimeInterval) async
    public func showConfirmation(_ text: String)                         // red pulsing gate
    public func dismissConfirmation()
    public func flashAction(_ text: String)                              // amber, brief
    public func showStopped(_ reason: String)                            // green banner
}
```

- One borderless `NSPanel`, `level = .screenSaver`, `isFloatingPanel = true`, `becomesKeyOnlyIfNeeded = true`, `styleMask = [.borderless, .nonactivatingPanel]`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `ignoresMouseEvents = true` **set once in `init` and never touched** (the spec/errata B12 recipe, demo subset).
- Points are **AppKit screen coordinates** (bottom-left origin of the primary screen). Map to panel-local with `point - NSScreen.screens[0].frame.origin`; main screen only.
- Drawn shapes only (no image assets): blue pointer for moving (`NSColor.systemBlue`), amber label chip, red pulsing ring for the gate (repeating alpha pulse via `Timer`), green banner for stopped. Keep everything click-through and non-activating.
- `moveCursor` animates with an ease-out cubic over `duration` and returns when done. Keep the easing as a pure `static func` (e.g. `GhostEasing.easeOutCubic(_:)`). It cannot be CI-tested without a new test target (which is out of scope) — leave it untested and note that.

### 3.2 `ScriptedDemoTransport` (in `ClickyApp`)

- `actor ScriptedDemoTransport: GeminiTransport` — mirrors `Tests/ClickyGeminiTests/FakeTransport.swift`'s shape (AsyncStream + continuation, `sentStrings()`, `deliver(_:)`, `finish()`), but lives in the app target. No timing inside it: the runner drives the timeline.

### 3.3 `ScriptedDemoRunner` (in `ClickyApp`)

- `@MainActor final class ScriptedDemoRunner` with `func start()` and `func stop(reason: StopReason)`; owns `GhostCursorController`, the `ScriptedDemoTransport`, and the real `GeminiLiveClient`:

```swift
client = GeminiLiveClient(
    transportFactory: { transport },                 // same instance
    setupFactory: { _ in GeminiSetupBuilder.make(systemInstruction: "Demo.") },
    toolHandler: DemoToolHandler(overlay: overlay),
    onServerContent: { /* update HUD on audio / interruption */ },
    onNotice: { /* setStatus */ },
    onMarker: { marker in Task { @MainActor in runner.showMarker(marker) } })
```

- `DemoToolHandler: GeminiToolHandling` (a `Sendable` struct holding the `@MainActor` controller — `GhostCursorController` is implicitly `Sendable` as a global-actor class): decodes `args` `target` (`{x,y}` normalized, top-left origin) and `label`; converts **through `CoordinateMath`**: build `DisplayGeometry` from `NSScreen.main` (`cgFrame` = top-left rect, `appKitFrame` = `NSScreen.frame`, scale = `backingScaleFactor`), `cg = CoordinateMath.cgPoint(fromNormalized:on:)`, `appKit = CoordinateMath.appKitPoint(fromCG: cg, primaryHeight: NSScreen.screens[0].frame.height)`; then `await overlay.setIntent(label)`, `await overlay.moveCursor(to: appKit, duration: 0.8)`, `await overlay.showConfirmation("Confirm? बोलो — हाँ")`, sleep 1.2 s, `await overlay.dismissConfirmation()`, `await overlay.flashAction("preview only — nothing clicked")`; return `GeminiToolHandlerResult(payload: .object(["status": .string("previewed")]), scheduling: .whenIdle)`.
- Timeline (the runner drives `Task { for (delay, json) in timeline { try await Task.sleep(...); await transport.deliver(json) } }`; start the driver **before** `try await client.start()`):

```swift
private static let timeline: [(TimeInterval, String)] = [
    (0.5, #"{"setupComplete":{}}"#),
    (1.2, #"{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"data":"AA==","mimeType":"audio/pcm;rate=24000"}}]}}}"#),
    (2.6, #"{"toolCall":{"functionCalls":[{"id":"demo-fc-1","name":"preview_action","args":{"target":{"x":0.5,"y":0.42},"label":"Save करो"}}]}}"#),
    (7.0, #"{"toolCall":{"functionCalls":[{"id":"demo-fc-2","name":"preview_action","args":{"target":{"x":0.3,"y":0.62},"label":"Type: नमस्ते"}}]}}"#),
]
```

(Spacing keeps the two previews sequential; tune slightly if needed but keep ≥3 s of handler time between calls.)

- HUD text (`setStatus`): "Clicky demo — scripted server, real client" → "Ready (scripted)" → on T4 "T4 · first audio" → on T8 "T8 · tool call → preview" → on T12 "T12 · response sent". One status string; do not over-build.
- **Esc (local stop):** register a Carbon hotkey while the demo runs — `RegisterEventHotKey(UInt32(kVK_Escape), 0, ...)` + `InstallEventHandler` for `kEventHotKeyPressed` (`import Carbon`); on fire → `Task { await runner.stop(reason: .killSwitch) }`. Unregister on stop. If Carbon cannot be made reliable within ~15 minutes, fall back to the "Stop Demo" menu item + a local `NSEvent` monitor, and **report which mechanism shipped**.
- `stop(reason:)`: cancel the driver task; `await client.stop(reason:)`; `overlay.showStopped("STOPPED — local stop (no network)")`; keep the banner ~4 s, then `hideOverlay()`.
- End of timeline: after the last beat + ~3 s, `stop(reason: .userToggle)` with banner "Demo complete".
- Menu wiring in `AppDelegate`: "Run Scripted Demo" / "Stop Demo (Esc)" items (call the runner); `--scripted-demo` in `CommandLine.arguments` auto-starts the demo ~2 s after `applicationDidFinishLaunching`. Hold one `ScriptedDemoRunner` instance in the delegate. Leave `AppState`/session machine untouched.

## 4. Subagent-driven execution (time-boxed)

Use your harness's subagents (DeepSeek V4.1 Flash `#high` for implementers; no Gemini/agy runs). Given the deadline, run **two implementers in parallel** over disjoint files:

- Agent A: `Sources/ClickyOverlay/GhostCursorController.swift` only.
- Agent B: `Sources/ClickyApp/ScriptedDemoTransport.swift`, `ScriptedDemoRunner.swift`, and the `AppDelegate.swift` modification (code against the frozen §3.1 API — do not modify the overlay file).

Then integrate yourself: `swift build`, fix compile errors (minimal), run `swift run ClickyApp --scripted-demo`, observe. Schedule: build ≤40 min · integration ≤65 min · combined review ≤90 min · recording + talk track ≤110 min · 10 min buffer. If not green by 75 min, take the next fallback from the plan's Chunk 4.5 fallback ladder **and say so**.

## 5. Verification (run all; capture raw outputs)

1. `swift build -c release` → `Build complete!`, 0 warnings.
2. `swift test` → **46/46, 0 failures** (count distinct `Test Case '...' passed` lines; the swift-testing footer is noise).
3. Launch verification: run `swift run ClickyApp --scripted-demo` in the background; take timestamped stills with `screencapture -x <out>/demo-N.png` every ~1.5 s for ~12 s. If Screen Recording permission blocks `screencapture`, say so and ask the user to watch. Read the stills back (they are images — inspect them) to confirm: overlay visible, cursor moved, label text, gate, banner. Test Esc via `osascript -e 'tell application "System Events" to key code 53'` if permissions allow; otherwise mark "Esc stop: user-verified visually" and ask the user to confirm.
4. Click-through check: user moves the mouse and clicks over the overlay area — input must pass through.
5. `grep -rn "TODO\|FIXME" Sources` empty; `git status` clean apart from the intended files; no secrets (this slice must not need any API key).
6. Optional (only if time permits; recommended for stage credibility): `./scripts/make-app.sh` and `open build/Clicky.app --args --scripted-demo` — verify the signed bundle runs the demo. **Never regenerate the signing certificate; if signing behaves unexpectedly, stop and use `swift run`.**

## 6. Review + commits

- One time-boxed combined spec+quality review subagent (`#max`, fresh context) over the diff: checks the frozen scope, honesty constraints (no network/AX/`CGEvent`/audio calls anywhere; labels say scripted), the click-through panel recipe, and that `Package.swift`/tests/README are untouched.
- Fix only build/behavior defects; do not gold-plate.
- Commits (main stays green):
  1. `feat(app): add scripted ghost-cursor demo slice through the real Live client` — the four code files only.
  2. `docs: add round 2 demo talk track` — `docs/demo/round-2-talk-track.md`.
- Do not tag, do not create a GitHub release, do not update the README.

## 7. Round-2 deliverables (beyond code)

1. **Backup recording** — ask the user to QuickTime-record one clean run (~40 s) of `--scripted-demo` with the talk track; note the local file path in `docs/demo/round-2-talk-track.md` (do not commit the video). If the user cannot, assemble an annotated screenshot sequence and label it as such.
2. **Talk track** — write `docs/demo/round-2-talk-track.md`: a 90-second script for the evaluator, e.g. (0:00) what Clicky is — an accessibility-first, voice-first AI cursor for macOS in English/Hindi/Marathi; (0:15) run the demo — ghost cursor glides, intent label, confirmation gate, Esc = local stop; (0:45) "what is real": scripted server, real `GeminiLiveClient` pipeline, real markers, 46/46 tests, byte-exact wire protocol; "what is next": AX engine + input + safety gates for live end-to-end; (1:10) differentiation, stated factually: a shared-control cursor with a preview-before-action model and a hard local stop; commercial commanders optimize shortcuts, and Indic voice is where this one wins. **No measured-performance claims anywhere** (the meter has not run yet); label the demo explicitly as scripted.
3. Print the talk track in your final report.

## 8. Final report format

- Status per deliverable (overlay / runner / wiring / verification / review / recording / talk track).
- Exact commands and raw outputs for §5; test counts with the counting method.
- Which Esc mechanism shipped; any fallback taken.
- Commit hashes + `git log --oneline -5`; `git status --porcelain`.
- Talk track (full text).
- Anything not run, labeled pending. No invented numbers.
