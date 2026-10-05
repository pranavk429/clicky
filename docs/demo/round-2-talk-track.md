# Clicky — CraftVerse 2.0 · Evaluation Round 2 talk track (90 seconds)

> **Label the demo, first sentence:** the demo runs a **scripted server over the real pipeline**.
> The incoming server frames are scripted; the `GeminiLiveClient`, the wire protocol codec,
> the tool-dispatch path, the marker emission, and the ghost-cursor overlay are the real
> implementation. **No network, AX, event-synthesis, or audio calls happen in this slice.**
> No performance number below is measured — the latency meter ships in Chunk 14.

## Run commands (before the conversation starts)

```bash
swift build -c release     # Build complete!, 0 warnings
swift test                 # 46/46 tests, 0 failures
swift run ClickyApp --scripted-demo   # or: menu bar → "Run Scripted Demo"
# Esc at any moment = local stop; menu bar → "Stop Demo (Esc)" is the fallback
```

## The 90-second script

**0:00 — What Clicky is (15 s)**
"Clicky is an accessibility-first, voice-first AI cursor for macOS. You speak naturally —
English, Hindi, or Marathi — and Clicky shows you what it intends to do before it does it:
a ghost cursor glides to the control, an intent label spells out the action in the language
you spoke, and a confirmation gate asks you to approve. Everything can be stopped locally
at any moment: Esc wins immediately, with no network involved."

**0:15 — Run the demo (30 s)**
Start it: `swift run ClickyApp --scripted-demo` (or menu → "Run Scripted Demo").
"Two scripted server frames produce two previews. The ghost cursor glides to the Save
control with the intent label *Save करो* — then a Hindi confirmation gate: *Confirm? बोलो — हाँ*.
Nothing is clicked — the flash reads *preview only — nothing clicked*. A second beat targets
a text field: *Type: नमस्ते*. The status strip shows the real pipeline markers flowing:
T4 · first audio, T8 · tool call → preview, T12 · response sent. Press Esc at any moment:
the banner *STOPPED — local stop (no network)* — the panel then hides itself."

**0:45 — What is real / what is next (25 s)**
"What's real: the scripted frames are processed by the real `GeminiLiveClient` — setupComplete
gating, tool dispatch on the real protocol types, fail-closed cancellation, and byte-exact
wire-protocol encoding, all under test: 46/46 green, including byte-exact encoding tests.
What's next: the Accessibility engine, input synthesis, and the safety gates — after which
this exact interaction runs end-to-end on live voice."

**1:10 — Why this one wins (20 s)**
"Compared with commercial voice commanders, Clicky is not a shortcut launcher: it is a
shared-control cursor. The model proposes; you approve; a hard local stop always wins.
And it treats Indic speech as a first-class interaction language — Hindi intent labels and
confirmation phrases are in the demo itself, not an afterthought."

## If the evaluator asks for evidence

- `swift build -c release` → `Build complete!`, 0 warnings · `swift test` → 46/46, 0 failures.
- "Scripted server, real pipeline": `Sources/ClickyGemini/` is the real client and protocol;
  `ScriptedDemoTransport` is the only scripted component (it never opens a socket).
- The confirm-before-act model: the preview never performs a click, type, AX read, or CGEvent.
- Latency/cost figures: **not measured yet** — latency meter is Chunk 14. Do not quote any.

## Backup recording

- **Status: not yet captured** (the team records it before the round; it is local-only and never committed).
- Planned path: `build/demo-round2/backup-round2.mov` (gitignored; do not commit).
- Capture: one clean run of the command above, ~40 s, screen recording; narrate the script above.
- If the recording is unavailable, the captured stills under `build/demo-round2/stills*/`
  serve as the fallback and must be labeled "captured stills of a scripted demo run".
