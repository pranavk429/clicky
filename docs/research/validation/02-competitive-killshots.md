# Competitive Kill-Shot Battlecard — "Why not Claude / Codex / Apple?"

**Project:** Clicky — voice-first shared-control AI cursor for macOS (Gemini Live, AX-first, Ghost Cursor, Hindi/Marathi/Hinglish)
**Audience:** Hackathon judges, skeptical technical evaluators, future investors
**Owner:** Competitive Intelligence
**Date:** October 5, 2026 · **Status:** Final v1 — built on fresh web verification (Sept–Oct 2026 sources)
**Inputs:** Spec Rev 2 (`docs/superpowers/specs/2026-10-05-clicky-voice-ai-cursor-design.md`), Reports 01/06
**Rules of engagement:** every fact is tagged `[VERIFIED + link]`, `[INFERENCE]`, `[UNKNOWN]` or `[SPEC/TARGET]`. No claim is rated stronger than its evidence. Where we lose an axis, this document says so.

---

## 1. Executive Summary (read this first)

1. **The 2025 pitch is dead.** "Claude/OpenAI freeze your screen for 40 seconds" is no longer defensible. Claude background computer use (Sept 2–3, 2026) and Codex computer use (April 16, 2026) both run **in background windows on macOS without taking your pointer** `[VERIFIED: support.claude.com/en/articles/14128542]` `[VERIFIED: developers.openai.com/codex/app/computer-use]`. Claude is also moving new Cowork tasks to the cloud on **Oct 6, 2026** — if the event is after that date, expect a judge to raise it `[VERIFIED: support.claude.com/en/articles/13345190]`. Our pitch must be about *where control lives*, not about the screen being "locked".
2. **OpenAI now has full-duplex voice that steers agents.** ChatGPT Voice (GPT-Live-1, July 2026) can "start tasks, check progress… or steer the task" and is interruptible `[VERIFIED: learn.chatgpt.com/docs/features/voice]`. Our "you can't talk to them" line is falsified on stage. But the approved modality is still clicks: in ChatGPT Voice, connected-app approvals require **on-screen controls; "spoken approval is not supported"** `[VERIFIED: help.openai.com/en/articles/8400625]` — this is now our sharpest accessibility kill-shot.
3. **Barge-in ≠ cancellation.** OpenAI's own GPT-Live API notes: "interrupting speech does not automatically cancel backend work" `[VERIFIED: community.openai.com/t/introducing-gpt-live-1-in-the-api/1396471]`. Claude publishes no sub-second cancellation path to an in-flight OS event `[UNKNOWN — no public doc found]`. Clicky's differentiator is that the cancel is local and attached to the event queue (`<150ms` `[SPEC/TARGET]`), not to a cloud task.
4. **Indic is still ours, but narrow the claim.** Apple Voice Control still lists **no Hindi/Marathi** even in macOS 27 Golden Gate `[VERIFIED: apple.com/macos/feature-availability]`; Windows Voice Access has no Indic *control* languages either `[VERIFIED: Microsoft Support]`. But Claude voice mode added **Hindi** (no Marathi) in July 2026 `[VERIFIED: CNET 2026-07-23]`, and ChatGPT Live demos Hindi translation `[VERIFIED: TechCrunch 2026-07-08]`. The honest moat is: **Hindi/Marathi/Hinglish speech → desktop actions with an action-level voice gate** — nobody ships that.
5. **heyclicky is now a real competitor, not a pointer toy.** The commercial app (25,000+ users, $20–$100/mo) has voice, agents, routines, connectors and guarded computer use with **voice approvals** — but it **removed its on-screen floating cursor on Sept 24, 2026** and remains macOS-only, English-first `[VERIFIED: heyclicky.com/changelog]`. The OSS repo (`farzaa/clicky`) is still pointer-only `[VERIFIED: github.com/farzaa/clicky]`.
6. **Benchmark honesty:** short computer-use tasks are nearly solved (~85–86% on OSWorld-Verified `[VERIFIED: leaderboard.steel.dev]`); long-horizon workflows are not (best tracked **binary completion ~32%**, official harness **20.6%**; partial scores up to ~78% under modified settings `[VERIFIED: leaderboard.steel.dev/leaderboards/osworld-2]`). We must not claim to beat frontier agents at general task success. We claim to beat them at *accessible, interruptible, low-cost control*.
7. **Strongest card:** nobody else combines (a) spoken per-action confirmation, (b) ghost-cursor preview of the pending action, (c) measured local barge-in, and (d) Indic-first desktop action mapping. **Weakest card:** our speed/cost/safety numbers are `[SPEC/TARGET]` until the benchmark suite and live meter produce real data — judges can ask to see the meter, and they will.

---

## 2. Verified Competitor State (as of Oct 5, 2026)

### 2.1 Claude Desktop — Cowork / Code / Computer Use

| Dimension | State | Label |
| :--- | :--- | :--- |
| Interaction model | Cowork chat/agent tasks; computer use toggle in Cowork & Claude Code; voice mode can use connected tools (Gmail/Calendar/Slack) but is **turn-based**, not OS control, and "built to work best from your phone" | `[VERIFIED: support.claude.com 11101966]` `[VERIFIED: Engadget 2026-08-09]` |
| Takeover behavior | Sept 3, 2026: background computer use in **hidden background windows on macOS 15+**; "doesn't take over your pointer or keyboard… waits if you're in the middle of typing"; full-screen tasks ask permission first, per session | `[VERIFIED: support.claude.com/en/articles/14128542]` |
| Latency | No published per-step figure. Docs: "Screen interaction is slower than connectors"; "complex tasks sometimes need a second try" | `[VERIFIED: same article]`; per-step 3–5s is `[INFERENCE, pre-background]` |
| Cost | Pro/Max incl.; no per-task price published. Comparable long-horizon runs cost **$8+/task** and author benchmark runs **~$2,750–$3,870 per 108 tasks** | `[VERIFIED: leaderboard.steel.dev/osworld-2]` |
| Interruptibility | Voice mode is turn-based; no published cancellation of an in-flight desktop action; in Cowork/Code, dictation exists but the help center says "voice mode isn't" available (while also saying voice works in "any conversation") | `[VERIFIED: support 11101966 — contradictory doc, quote both]` |
| Languages | Voice mode: 11 languages incl. **Hindi** (no Marathi); text interface multiple | `[VERIFIED: CNET 2026-07-23]` |
| Accessibility | None specific; no hands-free per-action confirm; approval/consent flows are UI-driven | `[INFERENCE from docs]` |
| Safety | Permission gate first full-screen use per session; **no sandbox between Claude and your apps**; classifiers for prompt injection | `[VERIFIED: support 14128542]` |
| Platform | macOS + Windows; web/mobile for Cowork; new tasks cloud-run from Oct 6, 2026 | `[VERIFIED: support 13345190]` |

**Judge-facing takeaway:** Claude is the strongest "delegate and walk away" product. It is not a shared-control accessibility tool. Do not call it slow; call it *autonomous by design*.

### 2.2 OpenAI — Codex App / ChatGPT Voice / Agent Mode

| Dimension | State | Label |
| :--- | :--- | :--- |
| Interaction model | Codex app (Feb 2, 2026) + ChatGPT desktop (Chat/Work/Codex). Computer use = "seeing, clicking, and typing with its own cursor"; multiple agents in parallel | `[VERIFIED: openai.com/index/codex-for-almost-everything]` |
| Takeover behavior | macOS: scoped **background** task while you keep working. Windows: "runs on the active desktop… expect Codex to move the pointer, type, and take over the foreground" | `[VERIFIED: developers.openai.com/codex/app/computer-use]` |
| Latency | No published per-step number; vision+CUA loop | `[UNKNOWN]` |
| Cost | Included in ChatGPT plans (Plus $20; Pro tiers); voice API $0.05/min; long-horizon runs ~$2,750–$3,870/run in benchmarks | `[VERIFIED: community.openai.com GPT-Live-1 API; leaderboard.steel.dev]` |
| Interruptibility | **Full-duplex** voice (GPT-Live-1); can interrupt/steer tasks by voice. But: "interrupting speech does not automatically cancel backend work" (API docs); approvals for connected apps require on-screen controls — spoken approval unsupported | `[VERIFIED: community.openai.com 1396471; help.openai.com 8400625]` |
| Languages | "Optimized for most spoken languages", specifics unlisted; Hindi live translation demoed with heavy accent per TechCrunch | `[VERIFIED: TechCrunch 2026-07-08]` |
| Accessibility | None specific. Computer-use safety page: user approval per app; cannot automate terminal/approve security prompts | `[VERIFIED: codex computer-use docs]` |
| Platform | Codex app macOS + Windows (computer use excluded in EEA/UK/CH at launch); ChatGPT desktop macOS + Windows; voice remote via iOS | `[VERIFIED: codex docs; TechCrunch 2026-07-24]` |

**Judge-facing takeaway:** OpenAI has the best voice model and is closest on barge-in at the *conversation* layer — but the safety/approval layer is still click-first, and cancellation of in-flight work is explicitly not guaranteed. That is exactly the gap Clicky's local gate closes.

### 2.3 heyclicky (commercial) + farzaa/clicky (OSS)

| Dimension | State | Label |
| :--- | :--- | :--- |
| What it is | AI buddy at the cursor: voice Q&A, dictation, "Clickys" agents, routines, connectors; **computer use with per-conversation approval (voice or UI: Allow once / Always allow / Not now)** | `[VERIFIED: heyclicky.com/changelog v1.0.49–53]` |
| Takeover | Aug 25, 2026: native computer-use driver, background clicks "scoped to the target window and never move your real cursor"; **floating on-screen cursor removed Sept 24, 2026** (drew over apps, broke window screenshots) | `[VERIFIED: changelog v1.0.48, v1.0.52]` |
| Latency | Not published; cloud voice+model path; earlier OSS stack (AssemblyAI+Claude+ElevenLabs) was >2.5s PTT | `[INFERENCE from OSS AGENTS.md]` |
| Cost | Free 25 agent msgs; **Pro $20/mo = 150 agent msgs; Max $100/mo = 1,000**; student/maker discounts; 25,000+ users | `[VERIFIED: heyclicky.com]` |
| Interruptibility | Follow-ups by holding voice key; "stop a task"; no published cancellation latency for in-flight clicks | `[VERIFIED/UNKNOWN: changelog]` |
| Languages | English-first; no Indic claims found | `[VERIFIED: site review]` |
| Safety | Approval cards before clicks; per-conversation yes; passwords not typed | `[VERIFIED: changelog]` |
| Platform | macOS (Sonoma 14.2+); Windows waitlist | `[VERIFIED: heyclicky.com]` |
| OSS repo | Pointer-only (tutor); zero clicks; MIT; README says new work is private | `[VERIFIED: github.com/farzaa/clicky]` |

**Judge-facing takeaway:** heyclicky is the closest commercial cousin and the name collision is real — handle it in the first 10 seconds with a disambiguation slide. Our edges: Indic-first, ghost-cursor preview + spoken per-action gate (they removed their cursor), measured barge-in, AX-first cost story. Their edge: 25k users, weekly shipping, connectors.

### 2.4 Apple — Voice Control + Siri AI (macOS 27 Golden Gate)

| Dimension | State | Label |
| :--- | :--- | :--- |
| Interaction model | Deterministic command parser + numbered badges (`Show numbers` → `Click 14`) / grid for unlabeled UI; no multi-step intent reasoning | `[VERIFIED: apple.com/macos/feature-availability; Report 01]` |
| Latency | Local, ~0.1–0.3s per command | `[REPORT 01 / INFERENCE]` |
| Cost | Free, on-device | `[VERIFIED]` |
| Takeover | None — command-only | `[VERIFIED]` |
| Interruptibility | N/A (single commands) | `[VERIFIED]` |
| Languages | macOS 27 Voice Control: Arabic (SA), Cantonese, English (AU/CA/IN/UK/US), French, German, Italian, Japanese, Korean, Mandarin, Russian, Spanish, Turkish — **no Hindi, no Marathi** | `[VERIFIED: apple.com/macos/feature-availability]` |
| Accessibility | The benchmark for OS-native motor access; free; trusted | `[VERIFIED]` |
| Safety | Immediate undo; system-scoped | `[VERIFIED]` |
| New in 2026 | Siri AI (macOS 27): on-screen awareness + app actions — **English only at launch**; full app actions require developers to adopt App Intents/view annotations | `[VERIFIED: MacRumors 2026-06-08; Apple support "Whats new in macOS 27"; WWDC26 session 343]` |
| Platform | All Apple platforms | `[VERIFIED]` |

**Judge-facing takeaway:** Apple owns trust and price, not intent or Indic. Siri AI is a future threat we should mention honestly; its app-action coverage depends on developer adoption and is English-first.

### 2.5 Talon Voice

| Dimension | State | Label |
| :--- | :--- | :--- |
| Interaction model | Programmable voice/eye/noise input system; user scripts define every command; community sets (knausj) required | `[VERIFIED: talonvoice.com/docs; talon.wiki]` |
| Latency | On-device, <100ms command execution claim | `[REPORT 01 / INFERENCE (community consensus)]` |
| Cost | Free engine; beta builds via Patreon | `[VERIFIED: talonvoice.com]` |
| Takeover | None (input layer only) | `[VERIFIED]` |
| Interruptibility | Deterministic sleep/wake commands | `[VERIFIED: docs]` |
| Languages | English command phonetics; Vosk/WebSpeech for multilingual **dictation**, not command grammars | `[VERIFIED: talon.wiki speech engines]` |
| Accessibility | Very high for trained power users (coders, gamers); eye tracking (Tobii) supported | `[VERIFIED: talonvoice.com]` |
| Safety | Deterministic scripts; no semantic risk gate | `[INFERENCE]` |
| Platform | macOS, Windows, Linux (X11) | `[VERIFIED]` |
| 2026 state | v0.4.0 (Dec 2025 beta line): Conformer D2 + Whisper engine, mixed mode, faster recognition; no NLP intent engine | `[VERIFIED: talonvoice.com/update 2025-12-16]` |

**Judge-facing takeaway:** Talon is the expert's tool and we respect it. Our user is the person who will never learn "air bat cap drum". Do not claim Talon is bad; claim it targets a different user.

---

## 3. Honest Axis-by-Axis Scorecard

Axes that matter to a motor-impaired / hands-free user. **W** = we genuinely win · **L** = we genuinely lose · **T** = tie / contested.

| Axis | Clicky | Claude | OpenAI | Apple | heyclicky | Talon | Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Real-time conversational steering | Full-duplex + local cancel | Turn-based voice; autonomous tasks | Full-duplex voice → task steering | N/A | Voice follow-ups | Command-level only | **T vs OpenAI** (they talk, we cancel) |
| Barge-in that cancels the in-flight OS event | Local queue cancel `<150ms` `[TARGET]` | Not published | Explicitly not automatic | N/A | Not published | Deterministic stop | **W (if measured)** |
| Spoken per-action confirmation | Required for Tier 3–5 | UI session permission | On-screen approval required; no spoken approval | N/A | Voice approvals exist | N/A | **W/T vs heyclicky** |
| Ghost-cursor preview before irreversible action | Yes | No | No | Numbers overlay only | Removed its cursor | N/A | **W** |
| Indic speech → desktop actions | Hindi/Marathi/Hinglish `[TARGET]` | Hindi voice, no Marathi; no desktop-action voice | Unspecified; no Marathi claim | None for control | None | None for commands | **W (narrowed)** |
| AX-first speed & zero-vision cost | Tier 1 local AX `[TARGET <300ms leg]` | Vision loop by default | Vision CUA loop | Local commands | Native driver, cloud model | Local keystrokes | **W on cost path (if measured)** |
| General task success / model reasoning | Gemini-powered; no OSWorld score | Frontier (≈85% OSWorld-Verified) | Frontier | N/A | GPT-6 family | N/A | **L** |
| Long-horizon autonomy (unattended) | Human-in-the-loop by design | Strong (background, cloud tasks) | Strong | No | Agents/routines | No | **L (intentionally)** |
| Enterprise integrations / connectors | None (hackathon) | MCP, Chrome, plugins, Salesforce | 90+ plugins, connectors, workspace agents | Ecosystem-native | Gmail/Stripe/Cal/MCP | User scripts | **L** |
| Platform reach | macOS only | macOS + Windows + web/mobile | macOS + Windows | All Apple | macOS (+Windows waitlist) | 3 OS | **L** |
| Price transparency | ₹2–3.5/task `[TARGET]`, no subscription decided | ₹1,999/mo Pro (Report 01) + limits | $20–$200/mo + limits | Free | $20–$100/mo + msg caps | Freeish | **T (ours unproven)** |
| Privacy posture | 0 pixels in Tier 1; no sandbox vs full agent | No sandbox; screen interaction | Screenshots, computer history opt-in | On-device | Screenshot-on-hotkey; cloud models | On-device | **W (Tier 1) — prove it** |
| Zero hardware / no screen takeover | Overlay never steals pointer | No takeover (macOS 15+) | Background on macOS; foreground on Windows | Never | Background; cursor removed | Never | **T on macOS** |
| Accessibility-first design & trust | Core audience, spoken-only flow | None | None | Native A11y both | Generalist | Expert disability tool | **W (design), L (no disabled-user evidence yet)** |

**What this means:** we win the *control and trust* axes and lose the *generalization, ecosystem, and reach* axes. Never present it any other way.

---

## 4. Kill-Shot Demo Moments (<30 s each, demoable with what we have)

> Each kill-shot is scripted for live judging: state the claim in one sentence, show the beat, show the receipt.

### K1 — vs Claude Cowork / Codex: "The Interruption" (25 s)
- **Setup:** Clicky is armed on a destructive action (red ghost box on Delete).
- **Beat:** Judge/friend shouts "Ruko!" → on-screen latency meter freezes the action, cursor retreats, banner "Clicky stopped".
- **Receipt on screen:** meter reads `<150ms`; next to it, two citations: OpenAI's GPT-Live-1 API note ("interrupting speech does not automatically cancel backend work") and Claude's docs (background task continues; no published per-action cancel).
- **Line:** "Both giants can *talk* while working. Neither promises your next word reaches the click before it lands. Ours is local."
- **Risk:** if the meter reads high on the day, show the p95 and say so; never hide it.

### K2 — vs ChatGPT Voice approvals: "The Hands-Free Approval" (20 s)
- **Setup:** Show (slide/screenshot, not live) that ChatGPT Voice connected-app approvals say: "Use the on-screen controls to approve or decline; spoken approval is not supported."
- **Beat:** Same action in Clicky: action freezes → Gemini asks in Hindi → user says "Haan" → action executes; hands never move (presenter keeps hands behind back the entire demo).
- **Line:** "Their safety gate is a click. Our safety gate is a sentence. For a user with no usable hands, that's the difference between safety and a locked door."
- **Risk:** they could add spoken approvals; cite the date. Also note heyclicky *does* accept voice approvals — keep this beat vs Claude/OpenAI only.

### K3 — vs Apple Voice Control: "The Language Test + Grid Tax" (30 s)
- **Setup:** Both apps running on the same Mac; Voice Control enabled.
- **Beat A:** Presenter says, in Marathi: *"Clicky, हे bill फोल्डर उघड आणि पहिला PDF Notes मध्ये paste कर"* → Clicky executes. Then ask Voice Control the same thing → no reaction (Hindi/Marathi not in its language list even on macOS 27).
- **Beat B:** Find a button with no accessibility label under Voice Control → "Show numbers" → wait → "Click 14" (3 spoken commands, one click). In Clicky, one sentence performs the whole task.
- **Receipt:** Apple's own macOS 27 feature-availability page open on screen (no Hindi/Marathi in the Voice Control list).
- **Line:** "Voice Control is excellent — if you speak six non-Indic languages and think in numbered grids."
- **Risk:** Apple may add Indic; cite "verified Oct 5, 2026". Don't claim Voice Control is bad — claim it's narrow.

### K4 — vs heyclicky: "The Preview + The Hindi Gate" (25 s)
- **Setup:** Disambiguation slide first (3 s): "heyclicky = the buddy; Clicky = the accessible control cursor. Different products, same unfortunate name."
- **Beat:** Delete action → amber/red ghost box appears on the exact target while Clicky speaks Hindi confirmation. Receipt: heyclicky's own Sept 24, 2026 changelog — it removed its floating cursor layer. Their approvals are chat cards; ours is a preview of the literal pixel about to be pressed.
- **Line:** "They removed the on-screen cursor because it interfered with the desktop. We built ours to never touch the desktop — `ignoresMouseEvents`, capture-excluded — so it can *show* you the action before it happens."
- **Risk:** heyclicky ships weekly; re-check the changelog the morning of the demo.

### K5 — vs Talon Voice: "The Cold Start" (20 s)
- **Setup:** Show Talon's wiki requirement ("Talon won't recognize any commands until you add scripts… Conformer install from the menu").
- **Beat:** Hand a judge the mic: they speak one natural Marathi/Hinglish task; Clicky does it. No scripts, no alphabet, no training.
- **Line:** "Talon is a superpower after three weeks. Our user may have one usable hand, three spoons of energy, and no three weeks."
- **Risk:** don't attempt to run Talon live without a pre-built setup; use the docs as the receipt.

---

## 5. The 15 Hardest Judge Questions (ordered by likelihood)

**Q1. "Claude and Codex already do computer use. Why does Clicky exist?"**
They are autonomous agents for general work; Clicky is an accessibility control layer. Three structural differences: (a) per-action spoken confirmation — ChatGPT Live requires **on-screen** approval and OpenAI's own API says interrupting speech does not cancel backend work; (b) AX-first execution means a click is a local 10–100ms action, not a vision round-trip; (c) Hindi/Marathi action mapping. **Proof:** live interruption beat (meter), the OpenAI help-page quote on screen, and our latency meter. Caveat we volunteer: frontier agents reach ~85% on short OSWorld tasks; we don't claim to out-generalize them — we claim to out-control them for users who cannot use a mouse.

**Q2. "Apple Voice Control is already free and built in."**
True, and we keep it as the fallback if our network dies. But it is a command parser: no Hindi/Marathi in its language list even in macOS 27, no multi-step intent, and unlabeled controls force "Show numbers → Click 14" drills. Siri AI's new on-screen awareness is English-only at launch and depends on developers adopting App Intents. **Proof:** Apple's own feature-availability page live; side-by-side language test; one-sentence-vs-three-commands grid tax. The product is additive: Voice Control stays installed, Clicky adds intent + safety.

**Q3. "Why build for macOS when India is 82% Windows?"**
Honest answer: macOS is ~2.6–3.5% of Indian desktops (Statcounter); we chose it because `AXUIElement` + `ScreenCaptureKit` let us prove the architecture in 30 hours on the judges' hardware. The intent engine is decoupled from the OS adapter — Windows UI Automation is a port, not a rewrite, and Windows Voice Access has no Indic control languages either, so the gap is real there too. **Proof:** the adapter boundary in our architecture diagram; stat cited from Report 01; and the fact that the same demo runs natively on the judges' MacBooks today.

**Q4. "How do you prove usability superiority?"**
We don't claim global superiority; we claim a measurable protocol with published failures. A 3-arm benchmark on 10 OS-state-verified tasks (one-handed manual vs vision-only baseline vs Clicky) measuring success, wall-clock, interruption latency and ₹/task. **Proof:** the raw run chart + failure log. If we only get n=3 including ourselves, we say exactly that on the slide — "pilot, n=3, no motor-impaired tester yet" — and put the protocol up so anyone can re-run it. Judges reward the protocol and the honesty more than a puffed percentage.

**Q5. "Can it really work hands-free?"**
For the demo scope, yes by construction: the whole 3-minute arc runs with hands behind the back — voice confirmation ("Haan"), voice barge-in, voice kill switch; the keyboard path is optional. Tier 4 (payments) requires a spoken read-back with no hardware input at all. **Proof:** our build exit criterion is "hands-free end-to-end 5/5 runs on Notes/Safari/Calculator"; the live demo is that run. Boundaries we admit: password/Secure Input fields hand back to the user by design; unlabeled canvases need the vision fallback.

**Q6. "What if it clicks the wrong thing?"**
Defense in depth, enforced locally where the model can't reach: (1) 5-tier risk gate classifies by AX role/title — the LLM can request, never downgrade; (2) Tier 3–4 actions need a ghost-cursor preview and spoken confirmation; (3) a 300–400ms arm window re-checks the interrupt flag before any hardware event; (4) kill switch clears the queue in <20ms; deletes go to Trash; text rolls back via Cmd-Z. **Proof:** run the cancel live; our exit criterion is "0 unconfirmed Tier 3–5 actions across 20 trials" — show the log. Also demo T10: poisoned document refusing injected instructions.

**Q7. "What does it cost at scale?"**
AX-first is the economic story: Tier 1 sends zero pixels and costs zero vision tokens; the bill is Live audio tokens plus rare frames. We target <₹2–3.5 per 3-minute task and print the measured number from the in-app meter, next to the alternative: frontier long-horizon runs cost $8+ per task (author benchmark runs ~$2,750–$3,870 per 108 tasks). Caveats we state ourselves: Gemini Live bills cumulative context per turn (we run compression), audio dominates, and Google's promo token rates roughly double on Jan 1, 2027. **Proof:** live cost meter + the billing doc; no projection without a receipt.

**Q8. "What's your moat when Gemini/Claude/GPT get better?"**
The moat is not the model — it's the control plane: local risk gate, AX hot cache, ghost-cursor consent UX, Indic→English AX label mapping, and the accessibility procurement niche. Better models improve our intent layer (we swap models behind a client interface) while competitors still lack action-level spoken consent and Indic action mapping. **Proof:** architecture slide showing the model as a replaceable component; the OpenAI quote showing approvals still require clicks. Distribution (grants, DEI procurement, accessibility certifications) is a moat models don't erase.

**Q9. "Isn't this just a Gemini API wrapper?"**
We'd deserve that if we piped audio and printed text. What we built locally: AX crawler + hot cache with timeouts, 5-tier risk gate, CGEvent synthesizer, NSPanel ghost overlay that never intercepts clicks, AEC audio stack, kill switch, coordinate math (unit-tested). The model proposes intent; it cannot post hardware events. **Proof:** repo file map + tests, and the offline mock mode replaying cached tool calls through the same local execution path — if it were a wrapper, mock mode would do nothing.

**Q10. "Prompt injection — a malicious page tells it to delete files."**
Screen text is data, never instructions; the only command channel is the authenticated human voice, and the enforcement is structural in the local gate, not in a prompt. Tier 5 refuses security settings, terminal and keychain actions; vision frames are disabled by default on bank/payment/password windows; secure text fields are excluded entirely. **Proof:** T10 poisoned-document test recorded (15-second refusal clip); risk-gate unit tests; the architecture rule that the model can request but never execute.

**Q11. "That's heyclicky's name — 25k users already; why not them?"**
Different product, and we'll say it first. heyclicky is a general AI buddy with agents and approvals — and as of Sept 24, 2026 it removed its on-screen cursor; it's English-first and $20–$100/mo with message caps. Clicky is accessibility-first: ghost-cursor preview + spoken per-action gate, Hindi/Marathi/Hinglish actions, AX-first cost, measured barge-in. We may ship a qualifier name ("Clicky Live") to kill the confusion. **Proof:** their changelog and pricing page on one slide next to our demo; disambiguation on the first slide of the pitch.

**Q12. "Talon already enables disabled power users — why would they switch?"**
Usually they won't switch — and that's fine. Talon is a programmable tool: scripts required before any command works, English phonetics, weeks of training, eye-tracking optional. Our user is the person who can't invest those weeks: stroke recovery, RSI, one-handed professionals, and Marathi/Hindi speakers. Clicky is natural language, zero-training, and doesn't require abandoning Talon for power workflows. **Proof:** Talon's own docs ("Talon won't recognize any commands until you add some scripts"); our <60s zero-config setup requirement; the demo judge speaking a Marathi task cold.

**Q13. "Privacy — you send screen and voice to Google. What about DPDP?"**
Tier 1 tasks send zero pixels — only AX element text; vision frames are on-demand, redacted (password/PII bounds black-boxed), processed ephemerally with storage off, and disabled by default on banking/payment windows; secure input fields are excluded; consent is trilingual on first run. The demo build uses an env key; shipping switches to backend-minted ephemeral tokens pinned to the model and system prompt. **Proof:** network panel showing zero image calls during a Tier-1 task; the redaction module in the vision path; the consent screen. Honest limit: audio always leaves the device during a live session — that's the deal with cloud speech, and we say it.

**Q14. "Business model — who actually pays for this in India?"**
Not app-store consumers. Assistive tech is procurement-driven: government schemes (Accessible India-style programs, ADIP), CSR disability budgets, university accessibility offices, and enterprise DEI accommodation budgets — plus hospital/clinic rehab channels for stroke recovery. Hardware alternatives cost ₹60,000–₹7,00,000; a subscription that is a fraction of that is the pitch, priced per seat via institutions. **Proof:** we cannot prove revenue today, and we won't pretend to. What we show is the pricing anchor vs hardware, and the pilot pipeline plan (one disability NGO / college accessibility office letter-of-intent as the goal).

**Q15. "What if the Wi-Fi dies during your demo?"**
Rehearsed degradation, not prayers: dedicated 5G hotspot with auto-switch; local mock mode replaying cached tool calls through the real AX/CGEvent path; an uncut emergency video; `doctor.sh` pre-flight. In production terms: queued actions either complete or cancel cleanly, and Clicky speaks a "connection lost, handing back" notice instead of freezing mid-action. **Proof:** turn Wi-Fi off live and show mock mode executing a real AX click — it's the same execution path, so it's a feature demo, not a trick.

---

## 6. Five Falsifiable Claims in Our Current Spec/Pitch — and Safer Wordings

| # | Risky claim (spec/pitch) | Why a judge can falsify it on stage | Safer wording |
| :-- | :--- | :--- | :--- |
| 1 | "Claude Desktop / OpenAI Operator runs a slow screenshot loop… locks the display" (spec §1.2, §6) and "Claude and OpenAI freeze your screen for 40 seconds" | Claude background computer use (Sept 2026) and Codex mac computer use (Apr 2026) run in background windows without moving your pointer; Operator branding is gone (ChatGPT agent). A judge can demo this in one sentence | "Competitor agents are optimized for autonomous batch work. On macOS they run in background windows — but steering, confirmation and cancellation happen at the task/UI layer, not at the hardware event. Clicky's control loop is local, per-action and spoken." |
| 2 | "Lacks real-time conversational interruption" / "You cannot talk to it while it executes" (spec §2, §6; Report 01) | ChatGPT Voice (GPT-Live-1) is full-duplex and steers agents; Claude has voice mode (turn-based). Judge: "OpenAI literally demos interrupting while it works." | "No competitor ties spoken interruption to the in-flight OS event: OpenAI's GPT-Live-1 API notes interrupting speech does not cancel backend work; Claude publishes no per-action cancellation. Clicky cancels at the local queue — target <150ms, shown on the meter." |
| 3 | "farzaa/clicky: Zero actions (points only), read-only" (spec §2 matrix; Report 01) | True for the OSS repo — but **heyclicky commercial now has agents + computer use with approvals and 25k users**. Judge: "You audited the old open-source repo and ignored the product." | Split the row: "farzaa/clicky (OSS): pointer-only tutor. heyclicky (commercial): agents + guarded computer use — no on-screen preview cursor (removed 2026-09-24), English-first, macOS-only. Clicky: accessibility-first shared control." Add disambiguation slide (first 10 seconds). |
| 4 | "Native Hindi, Marathi & Hinglish" implied as uncontested (spec §2 matrix, §6) | Claude voice mode supports Hindi (July 2026); ChatGPT Live demos Hindi translation. Judge: "Claude speaks Hindi — see CNET." | "The only system we found that maps **Hindi/Marathi/Hinglish speech to desktop actions** with an action-level spoken confirmation gate. Competitors support Indic *conversation* at best (Claude: 11 languages incl. Hindi, no Marathi; ChatGPT: unspecified; Apple/Windows voice control: none for control)." |
| 5 | "₹2–₹3.50 per 3-min task; 450–750ms voice turn; sub-50ms AX" presented as facts (spec §1.2, §4.5, §7) | Live meter can contradict any of them; Gemini Live bills cumulative context per turn; promo pricing doubles Jan 1, 2027; sub-50ms is an AX call, not the execution leg | "Measured live by the in-app meter in this session" for every number; label unmeasured ones "architecture target". Say the two-leg breakdown (voice turn vs execution leg) and disclose the Jan 2027 Gemini repricing. Drop "sub-50ms" as a headline; use "execution leg p50 <100ms, p95 <300ms — measured". |

**Also avoid entirely:** "the first real-time shared-control AI cursor" (unprovable — heyclicky shipped a cursor first) and any claim like "zero latency" or "100% safe". Say "the first accessibility- and Indic-first shared-control cursor we know of", and "0 unconfirmed destructive actions in N trials".

---

## 7. Source Ledger (verified during this review, Sept–Oct 2026)

1. Anthropic — "Let Claude use your computer in Cowork": https://support.claude.com/en/articles/14128542 (background windows, no pointer takeover, no sandbox, permission gate)
2. Anthropic — "Get started with Claude Cowork": https://support.claude.com/en/articles/13345190 (Oct 6, 2026 cloud shift)
3. Anthropic — "Use voice mode": https://support.claude.com/en/articles/11101966 (turn-based caveat; Cowork/Code voice gap)
4. Anthropic — Dispatch & computer use launch: https://claude.com/blog/dispatch-and-computer-use
5. CNET (2026-07-23) — Claude voice mode languages incl. Hindi: https://www.cnet.com/tech/services-and-software/claude-voice-mode-gets-an-upgrade-now-powered-by-new-models
6. Engadget (2026-08-09) — Claude voice "turn-based": https://www.engadget.com/2231293/how-to-use-claude-voice-mode
7. OpenAI — "Codex for (almost) everything": https://openai.com/index/codex-for-almost-everything
8. OpenAI — Codex computer use docs: https://developers.openai.com/codex/app/computer-use (macOS background / Windows foreground; permissions; EEA/UK/CH exclusion)
9. The Verge (2026-04-16) — Codex computer use: https://www.theverge.com/ai-artificial-intelligence/913034/openai-codex-updates-use-macos
10. OpenAI — ChatGPT Voice docs: https://learn.chatgpt.com/docs/features/voice
11. OpenAI — ChatGPT Voice FAQ (spoken approval unsupported): https://help.openai.com/en/articles/8400625
12. OpenAI — GPT-Live-1 API (interrupt ≠ cancel): https://community.openai.com/t/introducing-gpt-live-1-in-the-api/1396471
13. OpenAI — GPT-Live launch: https://openai.com/index/introducing-gpt-live; TechCrunch (2026-07-08, 2026-07-24)
14. heyclicky — site + pricing: https://www.heyclicky.com; changelog v1.0.48–53: https://www.heyclicky.com/changelog
15. farzaa/clicky OSS: https://github.com/farzaa/clicky
16. Apple — macOS 27 feature availability (Voice Control languages): https://www.apple.com/macos/feature-availability
17. Apple — "What's new in macOS 27" / Siri AI: https://support.apple.com/guide/mac-help/whats-new-in-macos-27-apd07d671600/mac; MacRumors (2026-06-08); WWDC26 session 343 (onscreen awareness requires App Intents)
18. Talon — https://talonvoice.com, /docs, /update (0.4.0 beta, 2025-12-16); talon.wiki
19. OSWorld 2.0 leaderboard (Steel.dev, updated 2026-09-30): https://leaderboard.steel.dev/leaderboards/osworld-2 (binary best 32.0%; official-harness 20.6%; partial up to 77.9%; run costs)
20. OSWorld 2.0 paper: https://arxiv.org/abs/2606.29537 (20.6% binary best config; 137–163 min bins <10%)
21. OSWorld 1.0 leaderboard (Steel.dev): https://leaderboard.steel.dev/leaderboards/osworld (short tasks ~85–86%)
22. Gemini API pricing (Sept 2026 read): https://benchlm.ai/google/api-pricing; Gemini Live billing Q&A: https://discuss.ai.google.dev/t/pricing-of-speech-to-speech-live-model/140340 (cumulative context re-billing; Jan 2027 repricing per Krater/BenchLM)
23. Microsoft — Voice Access languages: https://support.microsoft.com/en-us/accessibility/windows/voice-access/voice-access-command-list; July 2026 update KB5101684 (Korean added; still no Indic control)
24. Statcounter India desktop OS share (macOS ~2.64%): https://gs.statcounter.com/os-market-share/desktop/india (carried from Report 01)

**Maintenance:** re-verify items 1, 2, 4 (Anthropic ships weekly) and 14 (heyclicky ships weekly) the morning of the demo. If Claude/OpenAI add spoken approvals or guaranteed in-flight cancellation, Q1/K2/Q6 answers must be rewritten before judges see them.
