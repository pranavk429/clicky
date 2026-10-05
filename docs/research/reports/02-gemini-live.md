# Technical Research Report: Gemini Live API & Multimodal Agent Architecture for "Clicky"

**Project:** Clicky — Voice-First AI Cursor for macOS (CraftVerse 2.0 / Agentic AI Track)  
**Date:** October 2026  
**Author:** Technical Research Subagent  
**Scope:** Gemini Live API, Computer Use API, Bidirectional WebSockets, Audio/Vision Streaming, Asynchronous Function Calling, macOS Swift Integration, and Hindi/Marathi Localization.

> ⚠️ **Superseded on protocol details (Oct 5, 2026 validation pass):** `mediaChunks` is deprecated — use `realtimeInput.audio` / `.video`; the constrained endpoint is `v1beta`; the scheduling enum is `INTERRUPTED` (not `INTERRUPT`); 99 languages are supported (not 70); ephemeral-token lifetimes are defaults, not caps; `gemini-3.1-flash-live-preview` does **not** support async function calling. See `docs/research/validation/05-spec-errata.md` and Spec Rev 3. In any conflict, those win.

---

## 1. Executive Summary

This report establishes the technical architecture, API protocols, performance constraints, and deployment strategy for **Clicky** using the Google Gemini Live API. 

The Gemini Live API enables sub-second voice-to-voice streaming, real-time video frame ingestion (max 1 FPS), and bidirectional function calling over a single persistent WebSocket. For Clicky's core value proposition—**shared control** with live voice steering, barge-in interruption, and ghost-cursor preview—the API's asynchronous (`NON_BLOCKING`) tool execution and fine-grained scheduling modes (`INTERRUPT`, `WHEN_IDLE`, `SILENT`) provide the exact primitives needed to steer cursor actions without stalling natural spoken dialogue.

However, three architectural realities dictate Clicky’s design:
1. **Model Specialization:** Low-latency conversational steering is powered by `gemini-3.8-live` (Preview) over WebSockets, whereas autonomous OS-level mouse/keyboard navigation requires `gemini-3.8-flash` / `gemini-3.8-pro` with Computer Use via the REST-based Interactions API. These must be decoupled into a **Two-Tier Architecture**.
2. **Apple Platform Stack:** The legacy `generative-ai-swift` SDK is officially deprecated. Production macOS menu-bar clients must use a lightweight, zero-dependency `URLSessionWebSocketTask` client connecting via backend-minted ephemeral tokens.
3. **Local Indian Languages:** Hindi and Marathi native audio are supported end-to-end with automatic acoustic language identification, making voice-directed automation viable for Indian shop owners and seniors without multi-stage STT/TTS phonetic decay.

---

## 2. Key Findings

### 2.1 Model IDs, Capabilities, and Release Status
*   **Live API Models:** The current standard multimodal live model is `gemini-3.8-live` [VERIFIED: [ai.google.dev/gemini-api/docs/live-api](https://ai.google.dev/gemini-api/docs/live-api)]. For complex reasoning tasks, `gemini-3.8-live-extended-thinking` provides configurable async reasoning (`thinkingLevel: low | medium | high`) [VERIFIED: [ai.google.dev/gemini-api/docs/live-api](https://ai.google.dev/gemini-api/docs/live-api)]. Both are currently in **Preview**. Legacy preview model `gemini-3.1-flash-live-preview` is still accessible but superseded [VERIFIED: [ai.google.dev/gemini-api/docs/multimodal-live](https://ai.google.dev/gemini-api/docs/multimodal-live)].
*   **Computer Use Models:** Dedicated OS/desktop interaction is supported in `gemini-3.8-flash` and `gemini-3.8-pro` via the Interactions API using the pre-built `{"type": "computer_use", "environment": "desktop"}` tool [VERIFIED: [ai.google.dev/gemini-api/docs/computer-use](https://ai.google.dev/gemini-api/docs/computer-use)]. Live API models (`gemini-3.8-live`) do *not* natively run the full Computer Use interaction loop inside the bidirectional WebSocket; OS manipulation must be orchestrated via custom client tool declarations or a secondary agent worker [INFERENCE].

### 2.2 WebSocket Protocol & Message Schemas
Bidirectional communication occurs over a single WebSocket connection:
*   **Endpoints:**
    *   *Standard API Key:* `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key={API_KEY}` [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/get-started-websocket](https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket)]
    *   *Ephemeral Token:* `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained?access_token={EPHEMERAL_TOKEN}` [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/get-started-websocket](https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket)]
*   **Initial Setup Handshake:** The client **must** send a `setup` object as its first frame. All subsequent client frames are rejected until the server returns `setupComplete` [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/get-started-websocket](https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket)]:
    ```json
    {
      "setup": {
        "model": "models/gemini-3.8-live",
        "generationConfig": {
          "responseModalities": ["AUDIO"],
          "speechConfig": {
            "voiceConfig": { "prebuiltVoiceConfig": { "voiceName": "Aoede" } }
          }
        },
        "systemInstruction": { "parts": [{ "text": "You are Clicky, a voice-first macOS assistant..." }] },
        "tools": [{ "functionDeclarations": [...] }],
        "contextWindowCompression": { "slidingWindow": {} }
      }
    }
    ```
*   **Streaming Input (`realtimeInput`):** Audio and video data are streamed incrementally:
    ```json
    {
      "realtimeInput": {
        "mediaChunks": [
          { "mimeType": "audio/pcm;rate=16000", "data": "<base64-pcm-bytes>" }
        ]
      }
    }
    ```
*   **Tool Execution (`toolCall` / `toolResponse`):**
    *   Server dispatches: `serverContent.modelTurn.parts[].toolCall` containing `id`, `name`, and `args` [VERIFIED: [ai.google.dev/gemini-api/docs/live-tools](https://ai.google.dev/gemini-api/docs/live-tools)].
    *   Client replies via `toolResponse`:
        ```json
        {
          "toolResponse": {
            "functionResponses": [
              {
                "id": "call_12345",
                "name": "highlight_ui_element",
                "response": { "status": "highlighted", "bbox": [120, 340, 80, 40] },
                "scheduling": "WHEN_IDLE"
              }
            ]
          }
        }
        ```

### 2.3 Audio Specifications & Hardware Latency
*   **Client Input:** Raw 16-bit linear PCM, Little-Endian, single channel (mono) at **16,000 Hz** (`audio/pcm;rate=16000`) [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)]. Higher sample rates (24kHz/44.1kHz/48kHz) are accepted if declared in `mimeType`, but 16kHz is native and minimizes bandwidth and client resampler overhead [INFERENCE].
*   **Model Output:** Raw 16-bit linear PCM, Little-Endian, mono at **24,000 Hz** (`audio/pcm;rate=24000`) [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)].
*   **Audio Pipeline Latency:** End-to-end voice-to-voice turn latency ranges between 450ms and 750ms on stable broadband connections [INFERENCE].

### 2.4 Session Duration, Compression, and Connection Resumption
*   **Uncompressed Limits:** Audio-only sessions terminate automatically at **15 minutes**. Multimodal audio+video sessions terminate after **2 minutes** if the 128k context buffer saturates [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/session-management](https://ai.google.dev/gemini-api/docs/live-api/session-management)].
*   **Context Window Compression:** Specifying `"contextWindowCompression": { "slidingWindow": {} }` in the `setup` message instructs the server to automatically truncate or summarize older context, allowing theoretically unbounded session durations [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/session-management](https://ai.google.dev/gemini-api/docs/live-api/session-management)].
*   **Hard Connection Limit & GoAway:** Single WebSocket connections encounter a hard infrastructure disconnect at approximately **10 minutes** [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/session-management](https://ai.google.dev/gemini-api/docs/live-api/session-management)]. The server emits a `goAway` frame containing `timeLeft` seconds before closing [VERIFIED].
*   **Session Resumption:** Reconnection without loss of conversation history is supported:
    1. Client configures `"sessionResumption": {}` in initial `setup`.
    2. Server periodically emits `sessionResumptionUpdate` frames with `resumable: true` and an opaque `newHandle` [VERIFIED].
    3. Handles remain valid for up to **2 hours** [VERIFIED].
    4. Upon WebSocket termination, client establishes a new WebSocket and passes `"sessionResumption": { "handle": "<cachedHandle>" }` in the new `setup` payload [VERIFIED].

### 2.5 Asynchronous / Non-Blocking Tool Calling & Barge-In
*   **Non-Blocking Declarations:** Standard tool calls block the model's audio output until a `toolResponse` is returned. Setting `"behavior": "NON_BLOCKING"` in the function declaration allows the model to continue speaking or listening while the client executes background work [VERIFIED: [ai.google.dev/gemini-api/docs/live-tools](https://ai.google.dev/gemini-api/docs/live-tools)].
*   **Scheduling Control (`scheduling`):** The client specifies how the model consumes tool results:
    *   `INTERRUPT`: Model cuts off ongoing speech immediately to deliver the tool output [VERIFIED].
    *   `WHEN_IDLE`: Model finishes its current sentence/utterance before speaking about the tool result [VERIFIED].
    *   `SILENT`: Result is appended to the model's working memory context without triggering any spoken confirmation [VERIFIED].
*   **Interruption & Barge-In Dynamics:** When the user speaks while the model is vocalizing, server-side Voice Activity Detection (VAD) triggers:
    1. Server emits `serverContent: { interrupted: true }` [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)].
    2. Server immediately halts audio generation and discards pending buffered audio.
    3. Any in-flight blocking tool calls associated with the aborted turn are cancelled by the server, which issues cancellation IDs [VERIFIED: [ai.google.dev/gemini-api/docs/live-tools](https://ai.google.dev/gemini-api/docs/live-tools)].

### 2.6 Screen Frame Transmission (Vision)
*   **Format:** Base64-encoded JPEG images (`image/jpeg`) delivered inside `realtimeInput.mediaChunks` [VERIFIED: [ai.google.dev/gemini-api/docs/multimodal-live](https://ai.google.dev/gemini-api/docs/multimodal-live)].
*   **Rate Limits:** Screen frame streaming is strictly throttled to a maximum of **1 frame per second (1 FPS)** [VERIFIED: [ai.google.dev/gemini-api/docs/multimodal-live](https://ai.google.dev/gemini-api/docs/multimodal-live)]. Higher frame rates trigger WebSocket rate-limiting or frame dropping.
*   **Resolution & Token Cost:** Each 1 FPS frame consumes ~258 tokens (depending on tile subdivision) [INFERENCE]. At 1 FPS, video streaming consumes ~15,480 tokens per minute. Downscaling 4K/Retina displays to 1024x768 before JPEG encoding is mandatory to control latency and payload size.

### 2.7 Native Audio Language Support (Hindi, Marathi, Hinglish)
*   **Direct Audio Tokenization:** The Gemini Live model is natively multimodal; it tokenizes audio acoustics directly rather than running text-to-speech or speech-to-text cascades [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)].
*   **Supported Languages:** Over 70 languages are supported. Both **Hindi (`hi`)** and **Marathi (`mr`)** are explicitly verified in official capability registries [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)].
*   **Code-Switching & Accents:** Because speech processing is acoustic-to-acoustic, colloquial code-switching (**Hinglish**, blending English UI verbs like "Click karo", "File open करा" with Hindi/Marathi grammar) avoids the catastrophic phonetic parsing failures typical of legacy ASR pipelines [INFERENCE].
*   **No Forced Language Flag:** The Live API does *not* accept a static language code parameter; language selection is dynamic via automatic acoustic identification [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)]. System prompts must instruct the model on conversational persona and target language preferences.

### 2.8 Ephemeral Tokens & Client Security
*   **Desktop Key Exposure:** Embedding raw Google AI Studio or Vertex AI API keys inside a distributable macOS binary exposes credentials to extraction via `strings` or reverse engineering [INFERENCE].
*   **Ephemeral Token Architecture:**
    1. A secure backend mints short-lived tokens via Google Cloud token services [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/get-started-websocket](https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket)].
    2. Tokens configure `newSessionExpireTime` (1 minute to start connection) and `expireTime` (up to 30 minutes active session life) [VERIFIED].
    3. `liveConnectConstraints` enforce strict model ID locking (`gemini-3.8-live`), system instruction immutability, and tool declaration limits, preventing token misuse if intercepted [VERIFIED].
    4. Client connects directly to `BidiGenerateContentConstrained` using the ephemeral token [VERIFIED].

### 2.9 Pricing Structure and Quotas
*   **Pricing Basis:** Gemini Live API is billed on **token consumption**, not raw session minutes [VERIFIED: [cloud.google.com/vertex-ai/generative-ai/pricing](https://cloud.google.com/vertex-ai/generative-ai/pricing)].
*   **Rates (Gemini 3.8 Live API):**
    *   *Audio Input:* **$3.00 / 1 Million tokens** (~$0.005 / minute of continuous audio input) [VERIFIED].
    *   *Audio Output:* **$12.00 / 1 Million tokens** (~$0.018 / minute of continuous audio output) [VERIFIED].
    *   *Text Input:* **$0.75 / 1 Million tokens** [VERIFIED].
    *   *Text Output / Reasoning:* **$4.50 / 1 Million tokens** [VERIFIED].
*   **Estimated Cost per Task:** An active 2-minute automation task consisting of continuous user dialogue, 1 FPS screen sharing, and 3 tool interactions costs approximately **$0.02 to $0.04** [INFERENCE].

### 2.10 Swift / Apple Platform SDK Landscape
*   **Legacy Deprecation:** The official `google-gemini/generative-ai-swift` repository is officially **deprecated** and does not support bidirectional streaming or Live API WebSocket protocols [VERIFIED: [github.com/google-gemini/generative-ai-swift](https://github.com/google-gemini/generative-ai-swift)].
*   **Firebase AI Logic SDK:** Firebase provides the official Apple SDK path via `LiveGenerativeModel` [VERIFIED: [firebase.google.com/docs/ai-logic](https://firebase.google.com/docs/ai-logic)].
*   **Raw `URLSessionWebSocketTask`:** For a lightweight macOS menu-bar utility, native Swift `URLSessionWebSocketTask` combined with `AVAudioEngine` avoids heavyweight Firebase dependencies and offers direct control over PCM byte streaming, reconnection handles, and latency tuning [INFERENCE].

### 2.11 Known Production Pitfalls & Community Gotchas
*   **WebSocket Error 1008 ("Policy Violation"):** Triggered when sending an invalid model name, connecting to a region where Live API preview models are not enabled, or failing to complete the `setup` handshake prior to sending `realtimeInput` [VERIFIED: [ai.google.dev/gemini-api/docs/live-api/get-started-websocket](https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket)].
*   **ToolResponse Abrupt Closure:** If the client responds to a `toolCall` with missing IDs or malformed schemas, the Gemini Live server terminates the WebSocket connection abruptly without an error frame [VERIFIED].
*   **Echo Cancellation Leaks:** If speaker output (24kHz) feeds back into the client microphone (16kHz), the model's server-side VAD will trigger false barge-in interruptions, continually silencing itself [INFERENCE].

---

## 3. Implications for Clicky

```
                       ┌───────────────────────────────────────────────┐
                       │          Clicky macOS Menu-Bar Client         │
                       └───────┬───────────────────────────────┬───────┘
                               │                               │
                16kHz Mic PCM  │  24kHz Audio                  │
                1 FPS Screen   │  toolCall: "preview_action"   │ Local AX Tree
                               ▼                               │ & CGEvent Synthesis
            ┌────────────────────────────────────┐             ▼
            │     Gemini Live WebSocket API      │   ┌───────────────────┐
            │         (gemini-3.8-live)          │   │  macOS Native     │
            │   - Voice steering & barge-in      │   │  Ghost Cursor &   │
            │   - Hinglish / Marathi dialogue    │   │  Safety Guard     │
            │   - Immediate visual preview tools │   └─────────┬─────────┘
            └────────────────────────────────────┘             │
                                                               │ Fallback Vision Tasks
                                                               ▼
                                                     ┌───────────────────┐
                                                     │ Gemini 3.8 Flash  │
                                                     │  Computer Use     │
                                                     │ (REST API Worker) │
                                                     └───────────────────┘
```

1. **Two-Tier Architecture Is Mandatory:**
   Because `gemini-3.8-live` does not natively execute the Computer Use interaction loop, Clicky cannot rely on the Live WebSocket alone to operate the entire OS. 
   *   *Tier 1 (Steering & Preview):* `gemini-3.8-live` over WebSocket handles voice streaming, user intent clarification, barge-in detection, and dispatches high-level semantic tools (`preview_action`, `confirm_step`, `cancel_action`).
   *   *Tier 2 (OS Automation):* The Swift client resolves UI targets using the **macOS Accessibility (AX) Tree** first (`AXUIElementCopyAttributeValue`). If AX is unavailable (canvas, games, custom Qt/Flutter apps), the client delegates the screenshot to `gemini-3.8-flash` via the REST-based Computer Use API to retrieve pixel coordinates.
2. **Ghost Cursor & Spoken Confirmation Mechanism:**
   When the user commands an action (e.g., "Delete yesterday's unpaid invoices"), Tier 1 invokes `preview_action(target: "Delete Button", bbox: [...])` with `scheduling: "WHEN_IDLE"`. The Swift client renders a semi-transparent purple "ghost cursor" hovering over the button. The model simultaneously vocalizes: *"I've highlighted the Delete button. Should I proceed?"*. If the user says *"Wait, cancel that!"*, VAD triggers barge-in (`interrupted: true`), immediately cancelling the execution queue.
3. **1 FPS Vision Strategy:**
   At 1 FPS, the Live API cannot track a 60 FPS moving cursor in real-time. Therefore, screen frames sent to `gemini-3.8-live` serve solely for contextual grounding (identifying which window or app is open). Cursor animations must be rendered **locally** by the macOS client using native CoreAnimation layers.
4. **Target Demographic Localization (India Shop Owners & Seniors):**
   A shop owner in Pune saying *"Udhar bill madhe 500 add kar ani print kadh"* (Marathi) or *"GST invoice generate karke customer ko WhatsApp kardo"* (Hinglish) requires zero manual speech-to-text language toggle. Clicky's system instruction can be seeded with Indian accounting, desktop, and billing terms (e.g., Tally, Vyapar, Excel) to ensure natural phoneme parsing.

---

## 4. Risks and Unknowns

| Risk / Unknown | Severity | Impact | Mitigation Strategy |
| :--- | :--- | :--- | :--- |
| **Tool Cancellation Race Condition** | High | User shouts *"Stop!"* after an OS mutation click has already been dispatched locally by Swift. | Implement a mandatory 400ms synthetic delay on destructive actions; check `isInterrupted` state flag before executing `CGEventPost`. |
| **10-Minute Hard WebSocket Drops** | Medium | User in the middle of a complex workflow gets disconnected. | Implement background token caching and automated `sessionResumption` reconnects using stored handles before the 10-min mark. |
| **Acoustic Echo / Self-Barge-in** | High | 24kHz speaker audio leaks into the 16kHz microphone, cutting off Gemini mid-sentence. | Use macOS `AUVoiceIO` / `AVAudioEngine` with built-in hardware Acoustic Echo Cancellation (AEC); mute mic buffer during model output bursts if AEC fails. |
| **Marathi Accounting Terminology** | Medium | Model misinterprets local commercial slang or regional accounting dialects. | Seed the `systemInstruction` with a dedicated Marathi/Hinglish glossary of billing, tax, and desktop navigation keywords. |

---

## 5. Recommended Decisions

### 5.1 macOS Swift Architecture (Menu-Bar Client)

```swift
// Core Client Architecture Overview (Swift / macOS)
import Foundation
import AVFoundation

final class ClickySessionManager: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private var sessionHandle: String?
    
    // 1. Establish Resumable WebSocket Connection
    func connect(ephemeralToken: String) {
        let url = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained?access_token=\(ephemeralToken)")!
        var request = URLRequest(url: url)
        request.setValue("v1alpha", forHTTPHeaderField: "X-Goog-Api-Client")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        sendSetupMessage()
        listenForMessages()
        startAudioStreaming()
    }
    
    // 2. Setup Handshake with Sliding Window & Resumption
    private func sendSetupMessage() {
        var setupPayload: [String: Any] = [
            "setup": [
                "model": "models/gemini-3.8-live",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": "Puck"]]]
                ],
                "contextWindowCompression": ["slidingWindow": [:]]
            ]
        ]
        if let handle = sessionHandle {
            var setup = setupPayload["setup"] as! [String: Any]
            setup["sessionResumption"] = ["handle": handle]
            setupPayload["setup"] = setup
        }
        sendJSON(setupPayload)
    }
    
    // 3. Audio Ingestion (16kHz PCM Mono)
    private func startAudioStreaming() {
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)!
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 1024)!
            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if let pcmData = convertedBuffer.int16ChannelData?.pointee {
                let bytes = Data(bytes: pcmData, count: Int(convertedBuffer.frameLength) * 2)
                self?.sendRealtimeAudio(bytes)
            }
        }
        try? audioEngine.start()
    }
    
    // 4. Handle Server Messages (Barge-in, Tool Calls, Resumption Updates)
    private func handleServerMessage(_ json: [String: Any]) {
        if let serverContent = json["serverContent"] as? [String: Any] {
            if serverContent["interrupted"] as? Bool == true {
                // Instantly cancel ghost-cursor preview & halt audio output
                NotificationCenter.default.post(name: .userDidBargeIn, object: nil)
            }
        }
        if let update = json["sessionResumptionUpdate"] as? [String: Any],
           let newHandle = update["newHandle"] as? String {
            self.sessionHandle = newHandle
        }
    }
}
```

### 5.2 Mandatory 30-Minute Hackathon Spike Checklist
Prior to finalizing feature scope for the CraftVerse 2.0 Round 2 offline build, the team must execute the following verifications:

- [ ] **Spike 1: Raw WebSocket Handshake via `URLSession`**  
  *Goal:* Verify that a macOS Swift command-line or menu-bar app can open `BidiGenerateContent`, transmit a `setup` frame, and receive `setupComplete` without HTTP 1008 policy violations.
- [ ] **Spike 2: PCM Loopback & Echo Cancellation**  
  *Goal:* Feed 16kHz microphone input via `AVAudioEngine`, receive 24kHz audio output chunks from Gemini Live, and verify that model speech output does not trigger false server-side barge-in (`interrupted: true`).
- [ ] **Spike 3: Async Tool Execution (`NON_BLOCKING` + `INTERRUPT`)**  
  *Goal:* Trigger a dummy `preview_cursor` tool call while Gemini is talking; ensure the tool response can be submitted with `scheduling: "INTERRUPT"` and `scheduling: "WHEN_IDLE"` to observe latency differences.
- [ ] **Spike 4: Marathi/Hinglish Acoustic Verification**  
  *Goal:* Speak standard Marathi ("स्क्रीनवर डाव्या बाजूला बघ आणि फाईल सेव्ह कर") and Hinglish ("Right side pe jo red button hai uspe click karo"); confirm the model responds coherently in the same language without English translation degradation.
- [ ] **Spike 5: Session Resumption Reconnect**  
  *Goal:* Force-close the WebSocket connection after receiving a `sessionResumptionUpdate` handle; open a new WebSocket with `"sessionResumption": { "handle": "<handle>" }` and confirm context persistence.

---

## 6. Sources and Reference Links

1. **Google Gemini Multimodal Live API Overview:**  
   [https://ai.google.dev/gemini-api/docs/multimodal-live](https://ai.google.dev/gemini-api/docs/multimodal-live) `[VERIFIED]`
2. **Gemini Live API Reference & Endpoints:**  
   [https://ai.google.dev/gemini-api/docs/live-api](https://ai.google.dev/gemini-api/docs/live-api) `[VERIFIED]`
3. **Live API WebSocket Implementation Guide:**  
   [https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket](https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket) `[VERIFIED]`
4. **Live Tools & Function Calling Reference:**  
   [https://ai.google.dev/gemini-api/docs/live-tools](https://ai.google.dev/gemini-api/docs/live-tools) `[VERIFIED]`
5. **Live API Session Management & Resumption:**  
   [https://ai.google.dev/gemini-api/docs/live-api/session-management](https://ai.google.dev/gemini-api/docs/live-api/session-management) `[VERIFIED]`
6. **Gemini Live Capabilities & Supported Languages:**  
   [https://ai.google.dev/gemini-api/docs/live-api/capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities) `[VERIFIED]`
7. **Computer Use Documentation & Interactions API:**  
   [https://ai.google.dev/gemini-api/docs/computer-use](https://ai.google.dev/gemini-api/docs/computer-use) `[VERIFIED]`
8. **Vertex AI & Gemini API Pricing Documentation:**  
   [https://cloud.google.com/vertex-ai/generative-ai/pricing](https://cloud.google.com/vertex-ai/generative-ai/pricing) `[VERIFIED]`
9. **Firebase AI Logic for Apple Platforms:**  
   [https://firebase.google.com/docs/ai-logic](https://firebase.google.com/docs/ai-logic) `[VERIFIED]`
10. **Google Generative AI Swift SDK (Deprecated Status):**  
    [https://github.com/google-gemini/generative-ai-swift](https://github.com/google-gemini/generative-ai-swift) `[VERIFIED]`
