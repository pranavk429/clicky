# Execution Handoff — Clicky Implementation Plan

**Plan:** `docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md` (committed `f8a7258`; 15 review-sized chunks, each ≤1000 lines, every chunk ends with an Acceptance task + chunk-reviewer gate).

**Status of the plan:** complete and reviewed. All 15 chunks written; each chunk passed a plan-document review with findings fixed (protocol correctness, compile-level code fixes, test counts, cross-chunk APIs reconciled).

## Pre-flight before starting Chunk 1
1. **Xcode / XCTest:** ✅ RESOLVED (2026-10-05). Xcode 27.0 installed at `/Applications/Xcode.app`, selected via `xcode-select`, license accepted, first-launch complete. Verified: `swift --version` → Apple Swift 6.4; XCTest smoke test passes (`swift test` → `Executed 1 test, with 0 failures`). Tests can run.
2. **Git state:** untracked `CraftVerse_KARTA_Accessibility.pptx` at repo root — commit it or add it to `.gitignore` by user choice (plan Task 1.1 pre-flight).
3. `caffeinate -i` is running to keep the Mac awake during long agent runs (`killall caffeinate` to stop).

## How to start (fresh chat)
Use `superpowers:subagent-driven-development` (fallback: `superpowers:executing-plans`): per task → fresh implementer subagent gets the full task text → implement + tests + commit → spec-compliance review → fix → code-quality review → fix → next task. Per chunk → Acceptance task → chunk reviewer over the whole chunk diff → fix → `chunk N complete` commit + tag.

Start with **Chunk 1, Task 1.1** (repo baseline + pre-flight), then Task 1.2, etc. Chunk 1's row: tag `chunk-1-foundation-a`.

## Notes
- Scope-cut ladder (plan §1.6): vision fallback → Marathi tuning → Tier-2 handlers; never cut Ghost Cursor, voice-triggered AX click, confirmation gate, local stop.
- Open items deliberately left for execution-time measurement: `scheduling` enum placement (Spike 5.3), VAD sensitivity spellings (Spike 5.3), Electron wake latency, frame token counts — each has a measurement step + fallback in the plan.
