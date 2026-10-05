# Validation Report 01 — Latency & the "Live Conversation" Claim

**Project:** Clicky — Voice-First AI Cursor for macOS · **Date:** 2026-10-05 · **Status:** Adversarial validation of Spec Rev 2 §4.1/§4.5
**Scope:** Verify end-to-end Gemini Live voice-to-voice latency, audit every contributor in Clicky's pipeline, correct unsupportable numbers, define engineering levers, instrumentation, and tests. This report does not modify the spec; §6 lists exact redlines for the spec owner.
**Labels:** `[VERIFIED]` official/primary source · `[MEASURED]` third-party measurement · `[INFERENCE]` arithmetic/engineering judgment · `[CORRECTION]` contradicts spec or Reports 02/03 · `[RISK]` failure mode.

---

## Executive Summary

Clicky's "live conversation" feel is buildable, but **two of the three headline latency claims are stated too confidently and one is measured against the wrong anchor**. The implementation plan must define anchors and budgets the way this report does, or the first judge who asks "how do you measure that?" wins.

| Claim (Spec §4.5 / §4.4) | Verdict | Corrected statement |
| :--- | :--- | :--- |
| Voice turn **450–750 ms** (last speech sample → first audio) | **Optimistic / under-specified** | On a good network with tuned hybrid VAD: **~600–1000 ms typical**; 450–550 ms is a best-case floor; first turn +200–500 ms; conference Wi-Fi **1.5–2.5 s**. Absolute floor at default settings is ~1.0 s because server VAD default silence is ≈800 ms. |
| Execution leg **<300 ms p95** (`toolCall` → action + overlay) | **Achievable only with conditions** | Warm AX cache + native app: p50 **25–45 ms**, p95 **60–120 ms**. Cache miss in Chromium/Electron: **150–450 ms**, can exceed p95. Add a cold-cache fallback budget (<500 ms) and speculative crawl. |
| Barge-in stop **<150 ms** | **Achievable only locally** | Local VAD → playback ducked & queue cleared: **<150 ms** (design target). Server `interrupted` + generation cancel: **150–400 ms typical** — RTT-bound, not controllable. Never claim the server-cancel number as <150 ms. |

Biggest findings, in priority order:

1. **The 450–750 ms claim has no published source.** Google says only "low-latency"/"ultra-low latency" [VERIFIED]; Report 02 labels its range `[INFERENCE]`. The only independent measurement of the exact model, Artificial Analysis, clocks Gemini 3.8 Live at **1.18 s time-to-first-audio** (Big Bench Audio) `[MEASURED]` — consistent with ~800 ms default server-side silence-end detection plus inference.
2. **Default VAD silently adds ~800 ms per turn** and the spec never configures it. Google documents `silenceDurationMs` default ≈800 ms and recommends 500–800 ms for quality; 100–200 ms fragments speech `[VERIFIED]`. Clicky must use **hybrid VAD** (server auto-VAD + client-side end-of-speech → `audioStreamEnd`) plus a tuned `silenceDurationMs` (~350–500 ms) to reach the claim. `[CORRECTION]`
3. **Barge-in must be a local-first path.** The server's `interrupted` frame is a network round-trip away. Local VAD onset → stop `AVAudioPlayerNode` → clear pending queue is the only way to hit <150 ms; the server frame arrives later and only confirms cancellation upstream. `[CORRECTION]`
4. **Fallback model risk:** `gemini-3.1-flash-live-preview` does **not** support async function calling — if the fallback is used, tool calls block speech until `toolResponse`, destroying the "keep talking while acting" premise. `[CORRECTION]` `[RISK]`
5. **Three schema drift items** that will cost a hackathon hour each: `realtimeInput.mediaChunks` is deprecated (use `audio`/`video`/`text` fields); scheduling enum is `INTERRUPTED` (not `INTERRUPT`); Live API now supports **99** languages, not 70. `[CORRECTION]`
6. **Perception science says <400 ms one-way is "natural", >600–700 ms feels robotic** (ITU-T G.114 band, human turn-gap median ≈200 ms) `[MEASURED]`. Clicky cannot beat physics on inference; it must **mask** the 600–1000 ms with instant visual acknowledgement (<100 ms), speculative ghost-cursor motion on `toolCall` arrival, and spoken fillers. That masking — not raw API latency — is what makes the demo feel instantaneous.

---

## 1. What Gemini Live Actually Delivers

### 1.1 Documented mechanics (primary sources)

- **Audio formats:** input raw 16-bit PCM, natively 16 kHz; output 24 kHz. The server resamples input if needed, "so any sample rate can be sent" — but Google's own best practice is to resample client-side to 16 kHz before transmission `[VERIFIED]` (ai.google.dev/gemini-api/docs/live-api/capabilities; .../best-practices).
- **Chunk pacing:** "Send audio in chunks of **20 ms to 40 ms**"; "don't buffer input audio significantly (such as 1 second)… send small chunks (20 ms–100 ms)" `[VERIFIED]`. This directly answers the "~100 ms chunks?" question: 100 ms is the tolerated ceiling, not the target. 20 ms is the latency-optimal point before per-message overhead dominates.
- **Server VAD:** on by default. `silenceDurationMs` — "required duration of detected non-speech before end-of-speech is committed… larger value increases the model's latency"; internal server default ≈800 ms; recommended 500–800 ms; 100–200 ms fragments utterances and degrades transcription/response quality `[VERIFIED]` (capabilities guide).
- **Hybrid VAD (official pattern):** automatic VAD stays on; the client runs its own end-of-speech detector and sends `audioStreamEnd`, which "bypasses the default server-side silence detection delay" `[VERIFIED]`. This is the single highest-leverage latency setting in the stack.
- **Barge-in:** `serverContent.interrupted: true` tells the client to "stop and empty the current playback queue". `toolCallCancellation` cancels server-side tool calls, but "occurs only in cases where the clients interrupt server turns" — no other proactive cancellation `[VERIFIED]` (api/live).
- **Async tools:** Gemini 3.8 Live defaults to `behavior: NON_BLOCKING`; response `scheduling` ∈ `SILENT | WHEN_IDLE | INTERRUPTED` `[VERIFIED]` (model page + tools guide).
- **Session lifecycle:** audio-only 15 min, audio+video 2 min without compression; resumption handles valid ~2 h; resumption mid-generation/function-call "will result in some data loss"; server may reset the socket periodically and sends `goAway { timeLeft }` `[VERIFIED]`.
- **Proactive audio is permanently ON** in `gemini-3.8-live` (`proactive_audio:false` errors) — the model may choose not to respond, and billing accrues on listening input `[VERIFIED]`. Add a system-instruction rule: always respond to direct commands, even tersely. `[RISK]`
- **No published latency SLA.** Google's pages and the Sept 15, 2026 launch blog say "near real-time"/"ultra-low latency" with no milliseconds `[VERIFIED]`.

### 1.2 Independent measurements

| Model (as measured by Artificial Analysis, accessed 2026-10-05) | Time-to-first-audio (Big Bench Audio) |
| :--- | :--- |
| Gemini 2.5 Flash Native Audio Dialog | **0.63 s** |
| Gemini 3.1 Flash Live (Minimal) | 0.96 s |
| Gemini 3.8 Live | **1.18 s** |
| OpenAI GPT-Realtime-2 (High) | 1.14 s |
| OpenAI GPT-Live-1 (Sol, low) | 1.24 s |
| Gemini 3.8 Live Extended Thinking (High) | 1.35 s |
| Gemini 3.1 Flash Live (High) | 2.99 s |

Source: artificialanalysis.ai/speech-to-speech + methodology page (TTFA = "average seconds to generate the first token of audio output"). `[MEASURED]` Caveat: their harness anchors may differ from ours (they measure a fixed-dataset turn, and may not use the same VAD config), so treat these as **comparative, not absolute**; the 3.8 Live number likely includes default server-side end-of-turn handling. Even so, no independent source shows native-audio S2S **median** first-audio under ~600 ms from end-of-utterance on a general API, and none shows 450 ms for 3.8 Live.

Human perception anchors: median inter-turn gap ≈200 ms (arXiv:2404.16053 via CloudX); <400 ms reads as natural, >400 ms is flagged as degraded conversational quality (ITU-T G.114), >600–700 ms reads as "robotic/satellite" `[MEASURED]` (dev.to/cloudx 30-stack benchmark).

### 1.3 Reality check on 450–750 ms `[CORRECTION]`

Arithmetic with tuned settings (good network, RTT 30–60 ms):

| Segment (from last speech sample) | Tuned | Default |
| :--- | :--- | :--- |
| Mic capture + tap buffer (1024 @48k) | 5–21 ms | 5–21 ms |
| Resample to 16k + 20 ms chunking | 5–15 ms | 5–15 ms |
| Uplink network (½ RTT) | 15–40 ms | 15–40 ms |
| **Server VAD end-of-turn wait** | **~200–350 ms (client EOS)** | **~800 ms (default)** |
| Model inference → first audio chunk | 300–550 ms | 300–600 ms |
| Downlink + playout buffer | 30–80 ms | 30–80 ms |
| **Total** | **~550–1050 ms** | **~1150–1550 ms** |

Conclusion: use **"~0.6–1.0 s typical, sub-second on a good network, 450 ms best case under ideal jitter"**. Keep 450–750 ms only if the demo script footnote says "with hybrid VAD on a wired/5G link"; otherwise judges who have used AI Studio will sense the gap. `[CORRECTION]`

---

## 2. End-to-End Budget Audit (every contributor)

### 2.1 Voice turn (speech-end → first audio out)

| Contributor | Realistic value | Evidence | Blockers / notes |
| :--- | :--- | :--- | :--- |
| Microphone + HAL + tap (`installTap`, 1024 fr @48k) | 5–21 ms | CoreAudio default ~512-frame HAL buffer (~10.7 ms); tap adds up to one buffer | 4096-frame taps = ~85 ms alone. Use 1024 and convert immediately. `[INFERENCE]` |
| AUVoiceIO / AEC | ~0 ms added latency; **convergence 100–500 ms after playback starts** | Apple WWDC19/23 voice-processing sessions; Report 03 §2.5 | Misconfiguration (enable after `start()`, or output bypassing the engine) = no AEC → false barge-in loop. `[RISK]` |
| Resample 48k→16k | <2 ms + one buffer | Google best practices; AVAudioConverter | Must be 16k natively; server would resample otherwise (same result, 3× uplink bytes). `[VERIFIED]` |
| PCM chunk pacing | 0–20 ms | Google: 20–40 ms recommended, ≤100 ms tolerated | Sending on a 1 s timer is the classic self-inflicted +500 ms. `[RISK]` |
| Uplink network | 15–40 ms each way typical; 50–500 ms conference Wi-Fi | RTT to Google edge; TCP, not UDP (no FEC; retransmit stalls ≤ RTO) | IPv6 partial support on venue Wi-Fi can add setup delay/asymmetric path; log `URLSessionTaskMetrics.networkProtocolName` + `roundTripTime`. `[RISK]` |
| Server VAD end-of-turn | **200–350 ms tuned; ~800 ms default** | `silenceDurationMs` docs | #1 budget killer. Hybrid VAD + `audioStreamEnd`. `[VERIFIED]` |
| Inference to first audio | 300–550 ms (3.8 Live class) | Derived from AA 1.18 s TTFA minus turn-handling; Extended Thinking 1.35 s | First turn higher (+200–500 ms prompt tax); context compression adds a transient spike. `[MEASURED]`/`[INFERENCE]` |
| Downlink + jitter buffer + output | 30–80 ms | 1–3 × 20 ms chunks + 10–20 ms device buffer | Buffer <1 chunk = underruns; >4 chunks = audible lag. Adaptive 20→60 ms. `[INFERENCE]` |

**Verdict:** claim "450–750 ms" is **only supportable as an ideal-case band with a footnote**; budget **600–1000 ms p50 / ≤2.0 s p95 venue**, and say "sub-second" in the pitch. Also define the metric anchor on screen: "from your last speech sample."

### 2.2 Execution leg (`toolCall` frame → action posted + overlay moving)

| Segment | Spec budget | Audited value | Verdict |
| :--- | :--- | :--- | :--- |
| Frame parse → router dispatch | <5 ms | 1–3 ms if the WS receive loop never blocks | OK — but `toolResponse` must not be awaited synchronously. `[RISK]` |
| Element resolution | <20 ms (cache hit) | <1 ms warm hit; native miss 10–40 ms; Chromium miss 50–250 ms; **cold Electron 250–450 ms** (incl. optional 150 ms retry) | Claim holds **only for warm cache**. Needs speculative crawl on voice onset. `[CORRECTION]` |
| Risk classification | <1 ms | <0.5 ms local rules | OK |
| Action execution | <10 ms | AXPerformAction native 1–10 ms; Chromium 10–80 ms; CGEvent post 1–5 ms + ≤1 frame render (16.7 ms) | OK for native; p95 exceeds budget on Chromium. |
| Overlay kickoff | ≤16 ms (60 FPS) | 8–17 ms warm (pre-created NSPanel); 50–200 ms if window is created lazily | Spec pre-creates overlay per screen — keep it; cold-create is a common hackathon regression. `[RISK]` |
| **Total** | **p50 ~100 ms / p95 <300 ms** | **warm native: p50 25–45 ms, p95 60–120 ms; cold Chromium/Electron: p95 150–450 ms** | p50 target trivially met; p95 target conditional. Add a stated exclusion + fallback path. `[CORRECTION]` |

Note the clock starts at `toolCall` receipt — **the model's decision time is not in this leg**, which is legitimate but must be disclosed. Speculative ghost motion starts at that same instant and can visually lead the hardware action by design (Tier 1–2 only).

### 2.3 Barge-in (`"Ruko"`/`"Stop"` → execution queue cleared / playback stops)

| Path | Latency | Verdict |
| :--- | :--- | :--- |
| Local VAD onset detection (energy/on-device VAD) | 30–60 ms (tap ≤21 ms + VAD frame ~20 ms + decision) | required for the claim |
| Stop `AVAudioPlayerNode` / duck output | ≤1 output buffer, 10–21 ms | gives audible stop ≤~80 ms total |
| Clear pending queue + set interruption flag | <1 ms | <150 ms **achievable locally** `[INFERENCE]` |
| Server `interrupted` frame (generation halt upstream) | 150–400 ms typical (RTT + server VAD), worse on lossy Wi-Fi | cannot be <150 ms; never report as such `[CORRECTION]` |
| `toolCallCancellation` | after server interruption; races already-posted local actions | keep 300–400 ms arm window for Tier 3–4; Tier 2 actions already applied are **not undoable** `[RISK]` |

Recommended metric split for judges: **"local stop <150 ms"** (playback + queue) and **"server generation cancelled 150–400 ms"** (secondary). Report 05's `<120 ms` claim should be relabeled "local stop path."

### 2.4 What breaks these budgets (explicit adversary list)

1. **Conference Wi-Fi / bufferbloat:** TCP retransmit RTO ≥200 ms means a single lost audio packet can add 200 ms–2 s to both audio and `toolCall` delivery (head-of-line blocking). Mitigation: hotspot failover (already planned), hydrate a local mock mode, and test scenario S2.
2. **IPv6 routing:** Google edges prefer IPv6; venues with broken/partial IPv6 raise connect time and path asymmetry. Pre-warm at launch; if not connected within ~3 s, force the hotspot before the demo starts. `[RISK]`
3. **Audio buffers:** tap 4096 frames (~85 ms), HAL 1024 frames, or a 200 ms playout queue each silently add latency. Pin tap=1024 @48k, output schedule 20–60 ms.
4. **PCM pacing:** swapping the deprecated `mediaChunks` array with multiple entries sends only the first ("all but the first will be ignored") — audio gaps that look like latency `[VERIFIED]`. Use one `realtimeInput.audio` Blob per 20 ms.
5. **AEC convergence:** false barge-in loop (model interrupts itself) destroys conversation feel; software RMS gate during the first ~300 ms of playback is the documented fallback.
6. **Tool blocking:** a synchronous handler that waits for AX before returning starves the receive loop; on the 3.1 fallback, blocking is unavoidable per protocol.
7. **Context compression spikes:** compression "causes a temporary latency increase"; keep `triggerTokens` high enough to avoid mid-demo compression (or force one compression in pre-flight). `[VERIFIED]`
8. **First-turn tax:** system prompt + tool declarations are ingested on turn 1 only; warm the session before the audience arrives. `[INFERENCE]`
9. **Offline/fallback:** `gemini-3.1-flash-live-preview` disables the entire async-tool latency story; if the 3.8 preview key fails, the demo must switch to local mock mode rather than the 3.1 "quick fix." `[CORRECTION]`

---

## 3. Engineering Levers (make it feel instantaneous)

### 3.1 Audio path (client, Swift/AVAudioEngine)

1. **Enable voice processing before `start()`** on both input and output (`setVoiceProcessingEnabled(true)`), hardware format 48 kHz. Treat this as immutable init order. `[VERIFIED]`
2. **Tap: `installTap(bufferSize: 1024)` at 48 kHz** (~21 ms). Convert with **one long-lived `AVAudioConverter`** to 16k mono Int16; send every 320 frames (20 ms), zero extra buffering. Keep off `@MainActor`.
3. **Do not resample twice:** 48→16 on input, 24→48 on output; the only "avoid resampling" wins are (a) reuse converters, (b) preallocate buffers, (c) no per-chunk JSON thrash. Construct `Data` once per chunk; base64 once.
4. **Output jitter buffer:** start at 2 chunks (~40 ms); adaptive to 20 ms on clean links, 60–100 ms under loss; underrun counter to the latency meter. Playback via `AVAudioPlayerNode` scheduling; on `interrupted` (or local VAD onset) call `stop()` + `reset()` immediately, not just stop scheduling.
5. **AEC hygiene:** during AEC convergence, drop mic packets while speaker RMS > threshold; never route model audio outside the engine (bypassing VPIO re-introduces echo).

### 3.2 Protocol & session

1. **Hybrid VAD:** keep server auto-VAD, run lightweight local end-of-speech (energy/RMS with 250–350 ms silence), send `audioStreamEnd`. Set `silenceDurationMs` ≈350–500, `startOfSpeechSensitivity` HIGH, `prefixPaddingMs` 20–40. Validate against multi-clause Hinglish commands; if quality degrades, raise to 500 ms and accept the latency.
2. **Pre-warm:** open the WebSocket and complete `setup` at app launch/lid-open; never connect on first utterance. Cache every `sessionResumptionUpdate.newHandle`; on `goAway`, reconnect immediately with the handle (≤2 s target). Accept docs caveat: resumption during generation can lose the in-flight turn. `[VERIFIED]`
3. **Tools:** declarations `behavior: NON_BLOCKING`; respond `scheduling: SILENT` for mechanical actions (click/scroll), `WHEN_IDLE` for spoken outcome narration, reserve `INTERRUPTED` for failures. Never block the WS receive queue; `toolResponse` send happens from a task.
4. **`toolCallCancellation`:** on receipt (and on local VAD onset) clear the queue and drop IDs; belt is the 300–400 ms arm window for Tier 3–4.
5. **No continuous video:** default turn coverage includes all video; only send on-demand frames for Tier 3 to avoid context compression and bandwidth.
6. **Reconnect UX:** expose connection state as a visual dot; on drop, Ghost Cursor pauses rather than freezing the cursor.

### 3.3 Perceptual masking (the actual "live feel" engine)

| Technique | Trigger | Effect |
| :--- | :--- | :--- |
| Instant visual ack (pulse ring / "listening" state) | local VAD onset (<50 ms) | user sees acknowledgement immediately; conversation feels half-duplex-instant |
| Speculative ghost-cursor motion | `toolCall` frame (often before/with audio) | action appears while Gemini is still speaking; masks the execution leg entirely |
| Speculative AX crawl | VAD onset / app activation | warm cache when `toolCall` lands; keeps execution leg <50 ms |
| Spoken filler (model-side) | system instruction: "open with a 2–4 word acknowledgement in the user's language before tool calls" | e.g., "Haan, dekhta hoon" arrives as first audio; Google's own Extended Thinking uses "Let me check that…" `[VERIFIED]` |
| Cached local earcon/word | voice-turn expected >600 ms | instant "Haan?" tick at ~100 ms; swap in real audio when it arrives — use sparingly and only for confirmed commands |
| Sub-turn tool calls | model calls `preview_action` while speaking | visual progress without extra round trip |
| Never overlap filler with action feedback | tool starts when call arrives | "acting" state (cursor motion) and "speaking" state are independent |

Rule of thumb from the measurements: users forgive **hearing** a 700–900 ms reply if they **see** acknowledgment in <150 ms and **see** the cursor act in <300 ms. Latency budget should be spent protecting the two visual legs.

---

## 4. Instrumentation Plan

### 4.1 Timestamp map (Swift, monotonic `ContinuousClock` or `mach_continuous_time`)

Log every event into a ring buffer (OSSignposter for Instruments + in-app meter). Anchors the demo must report:

| ID | Event | Where |
| :--- | :--- | :--- |
| T0 | last non-silent mic sample of the user turn | audio tap (track peak continuously) |
| T1 | local VAD speech onset (for barge-in) | VAD module |
| T2 | local end-of-speech detected (tuned silence) | VAD module |
| T3 | `audioStreamEnd` sent / last PCM chunk sent | WS send queue |
| T4 | first server audio frame received | WS receive loop |
| T5 | first audio frame rendered to output | `AVAudioPlayerNode` completion handler / playerTime |
| T6 | `interrupted` frame received (barge-in, server path) | WS receive loop |
| T7 | playback stopped / queue cleared after barge-in | barge-in controller |
| T8 | `toolCall` frame received | WS receive loop |
| T9 | element resolved (with hit/miss + crawl ms) | AXHotCache actor |
| T10 | action posted (`AXUIElementPerformAction` / `CGEvent.post` return) | EventSynth |
| T11 | overlay first changed frame (proxy: animation tick ≤1 frame) | GhostCursorView |
| T12 | `toolResponse` sent | WS send queue |

Derived (what actually gets judged):

- **Voice turn (strict):** T5 − T0
- **Voice turn (turn-committed):** T5 − T2 (report both; the difference exposes VAD tuning)
- **Execution leg:** min(T10, T11) − T8, split by AX hit/miss
- **Barge-in local:** T7 − T1 · **Barge-in server:** T6 − T1
- **Network:** `URLSessionTaskMetrics.roundTripTime` + `networkProtocolName` sampled every 5 s; log WS send-queue depth as a backpressure alarm.

Implementation notes: use one `LatencyEvent` struct; never format strings on the audio thread; batch meter updates at 10 Hz. Put the anchor definitions in the UI (footnote), not just the docs.

### 4.2 On-screen latency meter (demo)

Show three big numbers + samples + network dot:

1. **"Voice → speech (from end of your speech): XXX ms"** — rolling p50, colored ≤900 green / ≤1500 amber / >1500 red.
2. **"Call → action: XX ms"** — rolling p95 beside p50, with a tiny "cache hit/miss" flag.
3. **"Ruko → stop: XX ms"** — local stop (T1→T7); show "(server cancelled: XXX ms)" smaller, so the demo claim self-documents.
4. Sparkline of last 20 turns + green/amber connectivity dot (RTT bucket). Wrong anchors or rounded-to-integer fake values are worse than no meter; judges read source.

### 4.3 Five test scenarios (run before demo day)

| # | Scenario | Setup | Pass/Fail (p50/p95) |
| :--- | :--- | :--- | :--- |
| **S1** | Clean baseline | Wired/5G, RTT <60 ms, loss <0.5%; 20 turns across Notes/Safari/Calculator | Voice turn p50 ≤900 ms, p95 ≤1300 ms; exec leg p95 ≤250 ms warm; barge-in local ≤150 ms; 0 false barge-ins |
| **S2** | Adversarial network | macOS Network Link Conditioner: 100 ms delay, 5% loss, 2 Mbps down; 10 turns | Session survives; voice p95 ≤2200 ms; local stop ≤250 ms; hotspot failover completes ≤15 s if 2 consecutive turns >2500 ms |
| **S3** | Barge-in torture | 10 mid-sentence "ruko/stop/thamba" interrupts incl. while `when_idle` speech is queued | ≥9/10 pending queues cleared; 0 gated actions executed post-cancel; playback silent ≤200 ms p95; no self-interruption in 60 s playback |
| **S4** | AX chaos | 10 commands in cold Electron (VS Code/Slack) and 10 in Safari DOM; force cache miss | Exec leg p95 ≤450 ms cold, ≤250 ms warm; no MainActor stall >50 ms; fallback ghost motion visible every time |
| **S5** | Endurance + resumption | 12-minute session; force socket close after a cached handle; trigger one context compression | Reconnect ≤2 s; 0 lost turns post-resume; p95 voice-turn degradation ≤20%; no compression latency spike >500 ms within 60 s |

---

## 5. Top 7 Latency Bugs That Will Actually Happen (and fixes)

| # | Bug (symptom) | Root cause | Fix | Proof |
| :--- | :--- | :--- | :--- | :--- |
| 1 | **Every turn feels 1.5–2 s late** | default `silenceDurationMs` ≈800 ms + no client EOS | hybrid VAD; client EOS → `audioStreamEnd`; silence 350–500 ms; log T5−T2 | S1 voice p50 improves ≥300 ms |
| 2 | **Uplink adds 300–1000 ms** | 4096-frame tap, 500 ms accumulation before send, or sending 100 ms bundles | tap 1024 @48k; convert once; send 20 ms chunks immediately; sender on its own serial queue | T3−T0 ≤50 ms in logs |
| 3 | **Model interrupts itself / endless self-barge-in** | AEC enabled after `start()`, or playback bypasses VPIO; or `interrupted` handled but buffer not cleared | enable VPIO pre-start (48 kHz); play through engine; RMS gate during convergence; on interrupt `stop()+reset()` | S3 no false interrupts in 60 s |
| 4 | **Speech freezes whenever a tool runs** | handler awaits AX work before replying; or blocking tool declaration on fallback model | reply only after scheduling; `NON_BLOCKING` + `SILENT/WHEN_IDLE`; never await in WS receive loop; keep 3.1 fallback out of tool paths | T12 sent ≤30 ms after T8; no receive-loop gap >100 ms |
| 5 | **Click lands 300–500 ms late in Chrome/VS Code** | AX cache miss; live crawl of Chromium tree on hot path | speculative crawl on VAD onset/app switch; depth ≤5; batch attributes; fallback: start ghost motion from predicted target at T8 | S4 exec p95 ≤450 ms cold, ≤250 ms warm |
| 6 | **Ghost cursor appears after speech ends** | overlay panel created lazily; animation scheduled on MainActor while AX work blocks it | pre-create per-screen panels at launch; AX work on dedicated actor; start motion at T8 with a spring, never a delayed task | T11−T8 ≤1 frame warm; S4 no stall |
| 7 | **Mid-demo freeze: reconnect loses a turn** | handle not cached / reconnect only after close; resumption mid-generation loses state; `goAway` ignored | cache every `newHandle`; reconnect on `goAway` immediately; pre-warm second socket; local mock mode as the emergency tape path | S5 reconnect ≤2 s, 0 lost turns |

Honorable mention: base64/JSON per 20 ms chunk on the main thread (CPU spikes → jitter); preallocate and encode off-main, or you will debug it as "network latency."

---

## 6. Claim Corrections (redlines for spec owner — not applied)

1. §1.1/§4.5 "450–750 ms" → **"~0.6–1.0 s typical; 450–550 ms best case with hybrid VAD; ≤2.0 s p95 on venue Wi-Fi; first turn +200–500 ms."**
2. §4.5 execution leg **"<300 ms p95"** → keep for **warm, native-app AX cache hits**; add "cold Chromium/Electron ≤500 ms" and speculative-crawl requirement.
3. §4.4/§7 barge-in **"<150 ms"** → define as **local playback stop + queue clear**; add server-cancel **150–400 ms** secondary metric; note already-posted actions cannot be undone.
4. §4.2 "sub-50ms AX control" → "median warm-cache native AX; 50–300 ms cold/virtualized trees."
5. Report 02: `mediaChunks` deprecated → use `realtimeInput.audio/video/text`; `mediaChunks` multi-entry sends only the first.
6. Report 02: `scheduling: "INTERRUPT"` → **`INTERRUPTED`**; async is **default** on 3.8 Live.
7. Report 02: "70 languages" → **99** (Hindi/Marathi confirmed).
8. Fallback `gemini-3.1-flash-live-preview` **cannot** do async tool calls; correct fallback strategy is local mock mode, not 3.1.
9. Add to §4.1: VAD config (silence 350–500 ms, sensitivity HIGH, hybrid `audioStreamEnd`), pre-warmed socket, handle caching, compression spike caution, proactive-audio "always answer commands" instruction.

---

## Recommendations

1. **Adopt the corrected numbers in §6 today**; they are defensible under judge cross-examination and still strong ("sub-second voice, sub-300 ms warm execution, sub-150 ms local stop").
2. **Build the hybrid VAD + pre-warmed socket first** (Spike 1–2). It is 300–500 ms of free perceived latency before any UI work.
3. **Make local-first barge-in non-negotiable:** local VAD onset stops playback and freezes execution; treat the server `interrupted`/`toolCallCancellation` as confirmation, not the trigger.
4. **Instrument T0–T12 in hour 1**; no demo number without a timestamp. Publish the anchors in the UI.
5. **Protect the two visual legs:** instant ack <150 ms, speculative ghost motion at `toolCall` arrival <300 ms; mask the voice turn with model-side fillers.
6. **Pre-flight S1–S5** (30 minutes) and record an uncut backup video showing the same meter; run S2 over the hotspot path so the failover is rehearsed.
7. **Keep local mock mode wired to real AX execution** — it is the only fallback that preserves the latency story if the preview key or the venue network fails.

## Sources

1. Live API WebSockets reference — https://ai.google.dev/api/live (VAD fields, interruption, cancellation, resumption; updated 2026-09-04)
2. Live API best practices — https://ai.google.dev/gemini-api/docs/live-api/best-practices (20–40 ms chunks, no large buffering, resampling, interrupted buffer discard; updated 2026-09-15)
3. Live API capabilities — https://ai.google.dev/gemini-api/docs/live-api/capabilities (audio rates, VAD defaults/quality guidance, hybrid VAD, 99 languages, 15/2-min limits; updated 2026-09-18)
4. Live API tool use — https://ai.google.dev/gemini-api/docs/live-api/tools (NON_BLOCKING, scheduling semantics, 3.1 limitation)
5. Gemini 3.8 Live model page — https://ai.google.dev/gemini-api/docs/models/gemini-3.8-live (async default, proactive audio, limits)
6. Live API session management — https://ai.google.dev/gemini-api/docs/live-api/session-management (compression, goAway, resume)
7. Google launch blog, Sept 15 2026 — https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-8-live-gemini-3-8-live-extended-thinking/ (fillers, capabilities; no latency ms)
8. Artificial Analysis Speech-to-Speech leaderboard — https://artificialanalysis.ai/speech-to-speech (TTFA 1.18 s for 3.8 Live) + methodology https://artificialanalysis.ai/methodology/speech-to-speech-benchmarking
9. CloudX 30-stack voice latency benchmark — https://dev.to/cloudx/cracking-the-1-second-voice-loop-what-we-learned-after-30-stack-benchmarks-427 (perception thresholds, prompt tax, TTFT/TTFB)
10. Apple WWDC19 "What's New in AVAudioEngine" (voice-processing init order) — https://developer.apple.com/videos/play/wwdc2019/510/ · WWDC23 "What's new in voice processing" — https://developer.apple.com/videos/play/wwdc2023/10235/
11. Local sources: Spec Rev 2 §4.1/§4.4/§4.5; docs/research/reports/02-gemini-live.md; docs/research/reports/03-macos-engineering.md; docs/research/reports/05-safety-trust.md
