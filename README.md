<div align="center">

# Clicky

**A voice-first AI cursor for macOS.**  
Speak naturally in English, Hindi, or Marathi — Clicky shows you what it will do before it does it, and asks before it acts.

![status](https://img.shields.io/badge/status-pre--alpha-orange)
![platform](https://img.shields.io/badge/platform-macOS%2014.2%2B-blue)
![swift](https://img.shields.io/badge/Swift%206.0-orange)
![license](https://img.shields.io/badge/license-MIT-green)
![hackathon](https://img.shields.io/badge/hackathon-CraftVerse%202.0%20%C2%B7%20Agentic%20AI-purple)

*Built for the [CraftVerse 2.0 Hackathon](https://github.com/pranavk429/clicky) (PCCOE&R Pune) — Agentic AI track.*

**📐 [System design specification](docs/superpowers/specs/2026-10-05-clicky-voice-ai-cursor-design.md) · 📋 [Research & validation](docs/research) · 🗺️ [Roadmap](#roadmap)**

</div>

---

> **Project status (2026-10-05): pre-alpha.** The system design is complete and has survived five independent research/validation passes. Implementation is starting now, in reviewed chunks. Nothing has been measured on-device yet — every performance number in this README is an **architecture target** and will be replaced with on-screen meter readings as the build lands.

## The problem

Traditional ways to control a Mac without a mouse are broken for the people who need them most:

- **Assistive hardware is priced out of reach.** Eye-trackers and switch systems run from ₹60,000 to ₹7,00,000+.
- **Apple's Voice Control offers no Hindi or Marathi control**, and demands rigid syntax.
- **Today's computer-use agents are autonomous by design.** They run in the background, their approvals are on-screen clicks ("spoken approval is not supported"), and interrupting them does not cancel the work already dispatched.

Meanwhile, in India alone, millions work through upper-limb strain every day: up to **34–74% of the ~5.4M IT workforce** reports work-related musculoskeletal strain.

## What is Clicky?

Clicky is a **shared-control** AI cursor: a co-pilot, not an autopilot. Voice steering is full-duplex, every consequential action is previewed, and the safety gates are enforced locally in Swift — the cloud produces *intent*, but only local code can post a hardware event.

|  | What it means |
| :--- | :--- |
| 👻 **Ghost Cursor** | The intended target is previewed before actuation — amber bounding box for reversible review, pulsing red for confirmation-required actions. |
| 🗣️ **Spoken confirmation** | Irreversible actions are read back and require an explicit spoken confirmation (English / Hindi / Marathi). Financial actions additionally require exact amount read-back against a local normalizer. |
| ⚡ **Local-first barge-in** | On-device keyword spotting ("Stop" / "Ruko" / "Thamba") halts playback and clears the execution queue in **<150 ms (target)** — no server round-trip. |
| 🇮🇳 **Indic-first** | Hindi, Marathi, and Hinglish speech map straight to desktop actions, with English parity. |
| 🪜 **Tri-tier execution** | Native Accessibility API first (fast, cheap), direct app handlers second, vision + computer-use as a last resort — frames are fallback-only, on demand, and never stored. |
| ♿ **Accessibility at the core** | Designed with and for people with upper-limb limitation and clear speech. Voice-first, not voice-only: text-command and keyboard/switch confirmations are first-class fallbacks. |

**In scope:** adults with clear speech and upper-limb limitation — RSI/CTS, one-handed use, spinal-cord injury, post-stroke — who work on macOS.  
**Honest non-goals:** severe dysarthria, anarthria, and aphasia (a voice-only channel would exclude them). Clicky is a companion to, not a replacement for, dedicated AAC hardware.

## How it works

```mermaid
flowchart TB
    subgraph UI["Audio & Visual Layer"]
        Mic["🎙 Microphone<br/>16 kHz PCM"]
        Speaker["🔊 Speaker<br/>24 kHz PCM"]
        Overlay["👻 Ghost Cursor Overlay<br/>NSPanel · per screen"]
        Screen["🖥 ScreenCaptureKit<br/>on-demand frames, ≤1 FPS"]
    end

    subgraph Cloud["Gemini Intelligence Hub"]
        Live["Gemini 3.8 Live<br/>Bidi WebSocket · full-duplex"]
        CU["Gemini 3.8 Flash<br/>Computer Use · separate REST call"]
    end

    subgraph Local["Local Orchestrator (Swift)"]
        Router["Tool Router<br/>+ Intent Ledger"]
        Gate["5-Tier Risk Gate<br/>+ Confirmation Gate"]
        AX["AX Engine<br/>crawler · hot cache · adapters"]
        Synth["Event Synthesizer<br/>CGEvent — the only path to the OS"]
    end

    Mic --> Live
    Live --> Speaker
    Screen -.-> CU
    Live -- "toolCall (NON_BLOCKING)" --> Router
    Router --> Gate
    Gate -- "safe / reversible" --> AX
    Gate -- "irreversible+" --> Overlay
    Overlay -- "spoken confirmation" --> Gate
    AX -- "opaque canvas only" --> CU
    AX --> Synth
    CU --> Synth
    Synth --> Overlay
```

The cloud can suggest, never execute. Every tool call must bind to a user-issued intent, pass the local 5-tier risk gate, and — for irreversible actions — survive a spoken confirmation with a re-resolution check that the target has not changed (fail-closed).

## Latency: three measured legs (targets for now)

Clicky does not quote one fuzzy "latency" number. It reports three legs separately, and the on-screen demo meter displays exactly these anchors:

| Leg | Architecture target | Mechanism |
| :--- | :--- | :--- |
| **Voice turn** — last speech sample → first audio out | **~0.6–1.0 s typical** (450–550 ms best case with hybrid VAD); ≤2.0 s p95 on venue Wi-Fi | Client-side end-of-speech detection + `audioStreamEnd`; perceptual masking (instant visual ack, fillers, speculative cursor motion) |
| **Execution leg** — `toolCall` frame → action executed | **p50 25–45 ms / p95 <300 ms warm AX**; ≤500 ms cold | AXHotCache + speculative crawl on voice onset; non-blocking dispatch loop |
| **Barge-in** — user starts "Ruko" → everything stopped | **<150 ms local** (server cancel 150–400 ms, disclosed separately) | On-device VAD + player stop + queue clear, no network dependency |

> These are **targets**, not measured results. The build exit criteria require them to be demonstrated live: execution leg p50 ≤150 ms / p95 <300 ms over ≥50 tool calls, local stop <150 ms, and **0 unconfirmed Tier 3–5 actions across 20 trials**.

## Safety model in one glance

Actions are classified **locally** into five tiers. The language model can request an action, but it can never lower a tier or bypass the gate:

1. **Read / inspection** — autonomous.
2. **Reversible navigation** — autonomous, narrated live. (Actions that can move data off-device are reclassified Tier 3+.)
3. **Irreversible** — Ghost Cursor + spoken confirmation that names action and target; deletions go to Trash (recoverable).
4. **Financial / critical** — hard stop, amount read-back verified locally (₹500 ≡ "paanch sau" ≡ "५००"), 3-second lock, echo gate.
5. **Prohibited** — kernel-level reject: security settings, Terminal/sudo, Keychain, credential fields.

Plus: intent ledger for prompt-injection containment, URL allowlist, per-turn action budgets, and a dual kill switch (voice + `Cmd+Shift+X`).

## Repository layout

```text
clicky/
├── docs/
│   ├── superpowers/specs/    # System design specification (Revision 3 — architectural authority)
│   ├── research/             # Competitive, latency, macOS, user, safety & strategy research
│   │   ├── reports/          #   six research reports
│   │   ├── validation/       #   independent adversarial validation passes + spec errata
│   │   └── logs/, prompts/   #   how the research was run (reproducibility)
│   └── prompts/              # Prompts that drive the next planning/implementation agents
├── Package.swift             # SwiftPM package (planned — Chunk 1)
├── Resources/Info.plist      # LSUIElement bundle config (planned — Chunk 1)
├── scripts/                  # sign-dev / make-app / doctor / run (planned — Chunk 1)
├── Sources/                  # ClickyCore · ClickyGemini · ClickyAccessibility · ClickyInput
│                             # ClickySafety · ClickyAudio · ClickyVision · ClickyOverlay · ClickyApp
└── Tests/                    # one test target per logic module
```

The full module graph and file-level layout are specified in [spec §5](docs/superpowers/specs/2026-10-05-clicky-voice-ai-cursor-design.md). Today, only `docs/` exists — the rest lands chunk by chunk.

## Roadmap

Implementation runs in five reviewed chunks (each ends with an acceptance task, a full-chunk review, and a tagged commit):

| # | Chunk | Contents | Status |
| :-: | :--- | :--- | :--- |
| 1 | **Foundation** | SwiftPM graph, unit-tested coordinate math, menu-bar app, permission wizard, signing + bundle scripts | ⬜ Planned |
| 2 | **Gemini Live client** | Correct wire protocol, hybrid VAD, session resumption & reconnect, local mock mode | ⬜ Planned |
| 3 | **Accessibility engine + input** | AX crawler & hot cache, app adapters (Electron/Chromium), element matcher, CGEvent synthesis | ⬜ Planned |
| 4 | **Safety, audio, overlay** | 5-tier risk gate, confirmation gate, kill switch, audio pipeline with AEC, Ghost Cursor | ⬜ Planned |
| 5 | **Integration & demo** | Tool router + system instruction, latency meter, cost model, demo hardening | ⬜ Planned |

**Never cut** (per spec §8): Ghost Cursor overlay, voice-triggered AX click, spoken confirmation gate, local stop path.

## Documentation

| Document | What it covers |
| :--- | :--- |
| [System design spec (Rev 3)](docs/superpowers/specs/2026-10-05-clicky-voice-ai-cursor-design.md) | The architectural authority: protocol shapes, tri-tier execution, safety gates, latency budget, demo script |
| [Spec errata](docs/research/validation/05-spec-errata.md) | Adversarial review that hardened Revision 3 — 7 blockers fixed in spec |
| [Validation passes](docs/research/validation) | Independent checks: latency, competitive killshots, accessibility wedge, positioning |
| [Research reports](docs/research/reports) | Six deep dives: competitors, Gemini Live, macOS engineering, users, safety, hackathon strategy |

### Building

Not yet runnable. When Chunk 1 lands, the path will be:

```bash
swift build -c release          # developer loop
./scripts/make-app.sh           # assemble + sign Clicky.app (the demo path)
open build/Clicky.app
```

The demo runs as a signed `.app` bundle (macOS kills microphone access for bare `swift run` executables without usage descriptions). `GEMINI_API_KEY` is read from the environment — never committed.

## Name disclaimer

"Clicky" is the hackathon working name. It collides with an [open-source pointer project](https://github.com/farzaa/clicky) and a commercial product (`heyclicky.com`); neither controls the computer or provides Indic voice control. This project is an independent, accessibility-first system and will be rebranded before any paid pilot.

## License

[MIT](LICENSE) © 2026 Clicky contributors.
