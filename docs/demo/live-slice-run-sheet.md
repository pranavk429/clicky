# Clicky — live English conversation slice run sheet

> **Status (2026-10-06): the Chunk 5.5 "live English slice" prototype is retired.** `--live-demo`
> no longer launches it — the flag now starts the full `SessionCoordinator` session 2 seconds
> after launch, the same path as the menu-bar **Start Listening** toggle, through the real
> `GeminiLiveClient`, overlay, Chunks 7–8 safety gates, and Esc hard local stop. Mock mode
> remains `CLICKY_MOCK=1` (transport swap only: every scripted tool call still flows through
> the real AX/CGEvent path). The scripted Chunk 4.5 demo (`--scripted-demo`) keeps working as
> the emergency backup.
>
> **Prototype-specific details below are historical:** the English-only label described the
> prototype's tuning (the full session mirrors English, Hindi, or Marathi), the click beat's
> demo panel (`DemoClickGate`) is gone, and the typing/click labels predate the Chunks 7–8
> gates that now precede execution. The conversation, Safari, typing, and Esc beats still run
> against the real session; the honesty rules still apply — **no performance number below is
> measured**, and "stops in the same second" for barge-in is a **manual observation**, never a
> metered number.

---

## 1. Launch recipe (built app) + key hygiene

Build the signed app once, then launch it through the sourced recipe:

```bash
./scripts/make-app.sh                          # → "Built and signed: build/Clicky.app"

# Key is sourced ONLY inside the subshell — never echoed, never logged, never committed,
# never screenshotted. The app reads GEMINI_API_KEY from its environment.
# `--live-demo` now starts the full SessionCoordinator session 2 s after launch (the same
# path as the menu-bar "Start Listening" toggle); the Chunk 5.5 prototype is retired.
(set -a; source ~/.clicky-gemini-key; set +a; build/Clicky.app/Contents/MacOS/Clicky --live-demo)

# Mock mode (offline / key failure): swaps ONLY the transport — every scripted tool call
# still flows through the real AX/CGEvent path.
CLICKY_MOCK=1 build/Clicky.app/Contents/MacOS/Clicky
```

**Key hygiene (non-negotiable):**
- The key lives only in `~/.clicky-gemini-key` and is read only via the subshell above
  (`set -a; source …; set +a; …`). Do not `cat`, `echo`, `printenv`, or in any way display it.
- Never commit, paste, or screenshot the key — not in terminals, slides, recordings, or issues.
- Never place the key inside the app bundle. `open build/Clicky.app` cannot carry it
  (LaunchServices starts a fresh environment) — use the sourced recipe for live runs.

**Permissions required:**
- **Microphone** — first run shows the TCC prompt (from `NSMicrophoneUsageDescription` in
  `Resources/Info.plist`). Grant it.
- **Accessibility** — required for typed text and the real demo click (synthetic `CGEvent`
  keystrokes and clicks). Grant it under System Settings › Privacy & Security › Accessibility.

**If the microphone is killed when exec'd via the sourced recipe:** run `open build/Clicky.app`
once, grant **Microphone**, quit the app, then re-run the sourced recipe above. (`open` cannot
carry the key — so the `open` step is only to seed the TCC grant, not to run the live slice.)

**Stop at any time:** press **Esc**. The green banner reads `STOPPED — local stop (no network)`.
Esc is a hard, local stop — it is never repurposed for anything else.

---

## 2. The ~90-second beat sheet

Say the honest label first, then run these beats **in order**. Speak naturally; Clicky is a
conversation partner, not a shortcut launcher.

**0:00 — What this is (15 s)**
"live conversation slice — English; Tier 1–2 real actions; Tier 3+ previews/gates only. You
talk, it talks back, you can interrupt it mid-reply, and actions happen inside the conversation
— not as a one-shot trigger. Esc stops everything locally at any moment."

**0:15 — Hello / conversation (15 s)**
Say "Hello, who are you?" and chat for a turn or two. It answers briefly. Confirm it feels like
a conversation, not a single command.

**0:30 — Interrupt mid-reply (10 s)**
While it is still speaking, talk over it. **Manual observation:** playback stops in the same
second and it answers the new words. (This is observed, not metered.)

**0:40 — "Open Safari" (15 s)**
Say **"Open Safari."** Clicky calls `switch_app` and Safari comes forward, narrated with the
real outcome returned by the local computer. (Tier-2 real action.)

**0:55 — "Type: …" into Notes (15 s)**
With a **scratch note** focused in Notes (never a secure field), say **"Type: hello Clicky, १२३
123"**. The text appears grapheme-intact. If a secure field (login/password prompt) is focused
instead, the ask is refused and **nothing** is typed.

**1:10 — "Click the demo button" + Return (10 s)**
Say **"Click the demo button."** Clicky's own on-screen test panel appears, the ghost cursor
glides to the button, and the red confirmation gate shows: *Press ⏎ to confirm — Esc stops the
session*. Press **Return** → the flash confirms the real click landed on Clicky's own panel.
Press **Esc** during the gate instead → *Click cancelled — nothing was clicked* **and** the hard
stop fires. (The click target is only Clicky's own panel.)

**1:20 — Esc stop (10 s)**
Press **Esc** → the green banner `STOPPED — local stop (no network)`; no further audio, mic
released.

---

## 3. Honest labels (state these, do not soften them)

- **English only in this slice.** No Hindi/Marathi tuning is claimed or demonstrated here.
- **Tier 1–2 real actions; Tier 3+ previews/gates only.** Switching apps (`switch_app`) is real.
  Higher-tier actions are shown as previews/gates, not as executed destructive actions.
- **Typing and the click ship before the Chunks 7–8 safety gates.** The click targets **only
  Clicky's own demo panel**; typing **refuses secure input** and is demoed into a **scratch note
  only**. Neither is a general-purpose capability yet.
- **The T3→T4 chip is one leg, not the meter (Chunk 14).** It reports only the last voice turn's
  time from end-of-speech to first reply audio, and it carries its own qualifier
  (…*voice-turn leg only; full meter ships in Chunk 14 (not an end-to-end claim)*). Present it as
  a single leg of the pipeline, never as the product's end-to-end latency.

---

## 4. Fallback ladder (in order)

If anything in the live loop misbehaves, fall to the next rung — do not present a broken rung as
working:

1. **AEC (default).** `AVAudioEngine` voice processing is on by default. If it does not hear
   itself, stay here.
2. **Half-duplex.** If it hears itself (loops or self-interrupts), use the menu item
   **"Half-duplex (mute mic while speaking)"** → the loop stops. Barge-in is disabled by design
   in this mode; Esc still stops, always.
3. **Headphones.** If half-duplex is not enough, run the demo on headphones to break the acoustic
   loop.
4. **Scripted `--scripted-demo`.** The round-2 scripted demo (`swift run ClickyApp --scripted-demo`
   or menu bar → "Run Scripted Demo") runs the same beats over the real pipeline with scripted
   server frames. It is the emergency backup and must be labeled as the scripted demo — not as
   live conversation.
5. **Backup recording (last resort).** Play the pre-recorded clean run (see §5) and walk the
   audience through it. Label it as a recording of the live slice — never claim it is happening
   live.

---

## 5. Backup recording + hotspot note

**Backup recording procedure:**
- Capture **one clean run** of the sourced launch recipe on this machine with QuickTime screen
  recording (with system audio if available).
- Save it to a **local path only**, e.g. `~/Desktop/clicky-live-slice-backup.mov`.
- **Never commit the video** (it is large and local-only) and never commit any stills that could
  carry a key or personal data.
- Before the round: verify the file plays, is the intended clean run, and is labeled on screen as
  a recording of the **live English conversation slice — Tier 1–2 real actions; Tier 3+
  previews/gates only**.
- Status: **not yet captured** — record it before the round. Nothing is recorded by this document.

**Hotspot / network note:**
- The live slice needs the network. **A network drop fails closed to the scripted demo** — the
  live loop ends and the emergency backup (`--scripted-demo`) takes over.
- There is **no offline live claim**: do not present the scripted demo as a live conversation,
  and do not claim live behavior while offline.
- If the hotspot is the only link, prefer the scripted demo for the live-backed beats and label
  it accordingly, rather than risking a mid-sentence drop on the live path.
