# Execution Handoff — Clicky Implementation Plan

**Plan:** `docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md` (committed `f8a7258`; 15 review-sized chunks, each ≤1000 lines, every chunk ends with an Acceptance task + chunk-reviewer gate).

**Status of the plan:** complete and reviewed. All 15 chunks written; each chunk passed a plan-document review with findings fixed (protocol correctness, compile-level code fixes, test counts, cross-chunk APIs reconciled).

## Pre-flight before starting Chunk 1 (known blockers)
1. **Xcode / XCTest:** this machine is CommandLineTools-only (`xcode-select -p` → `/Library/Developer/CommandLineTools`); `swift test` cannot resolve XCTest. Install full Xcode (or select a toolchain with XCTest) before any `[unit test]` step. Build-only steps are fine either way.
2. **Git state:** untracked `CraftVerse_KARTA_Accessibility.pptx` at repo root — commit it or add it to `.gitignore` by user choice (plan Task 1.1 pre-flight).
3. `caffeinate -i` is running to keep the Mac awake during long agent runs (`killall caffeinate` to stop).

## How to start (fresh chat)
Use `superpowers:subagent-driven-development` (fallback: `superpowers:executing-plans`): per task → fresh implementer subagent gets the full task text → implement + tests + commit → spec-compliance review → fix → code-quality review → fix → next task. Per chunk → Acceptance task → chunk reviewer over the whole chunk diff → fix → `chunk N complete` commit + tag.

Start with **Chunk 1, Task 1.1** (repo baseline + pre-flight), then Task 1.2, etc. Chunk 1's row: tag `chunk-1-foundation-a`.

## Notes
- Scope-cut ladder (plan §1.6): vision fallback → Marathi tuning → Tier-2 handlers; never cut Ghost Cursor, voice-triggered AX click, confirmation gate, local stop.
- Open items deliberately left for execution-time measurement: `scheduling` enum placement (Spike 5.3), VAD sensitivity spellings (Spike 5.3), Electron wake latency, frame token counts — each has a measurement step + fallback in the plan.
