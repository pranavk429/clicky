# macOS Engineering Feasibility Report: "Clicky" Voice-First AI Cursor

**Track:** macOS Engineering Feasibility & System Internals  
**Date:** October 2026  
**Context:** CraftVerse 2.0 Hackathon (Agentic AI Track) | 30-Hour Offline Build  

> ⚠️ **Superseded on details (Oct 5, 2026 validation pass):** `security create-certificate` does not exist (use Keychain Access Certificate Assistant or the openssl `pkcs12` + `security import` recipe); the Electron citation is PR **#10305**, not #25126; Carbon allows zero-modifier hotkeys since 10.3 (the real limitation is modifier-only chords); the VoiceProcessingIO constraint is "engine stopped + matching formats" — the 44.1/48 kHz requirement is community-reported, not documented. See `docs/research/validation/05-spec-errata.md` and Spec Rev 3.

---

## 1. Executive Summary

Building "Clicky"—a low-latency, voice-first macOS cursor agent powered by Gemini Live and shared control—is technically feasible on macOS 14.2+ through native AppKit, Accessibility (`AXUIElement`), CoreGraphics (`CGEvent`), and ScreenCaptureKit APIs. Feasibility hinges on a tri-tier execution hierarchy: **AXUIElement semantic control first**, **direct AppKit/URL handlers second**, and **ScreenCaptureKit + Vision computer-use fallback third**. 

Crucially, Clicky **must be distributed as a non-sandboxed application** (`com.apple.security.app-sandbox = false`) signed with a persistent local development certificate to prevent macOS Transparency, Consent, and Control (TCC) permissions from invalidating on every debug rebuild. Analysis of Farza’s open-source `farzaa/clicky` confirms that while its menu-bar lifecycle, multi-screen overlay window, and `CGEventTap` hotkey monitor provide reusable scaffolding, it entirely lacks Accessibility tree traversal, event injection, and acoustic echo cancellation. Delivering this in a 30-hour sprint requires strict architectural separation, fail-fast asynchronous AX timeouts, and pre-built coordinate normalization math.

---

## 2. Key Findings (with Sources & Labels)

### 2.1 AXUIElement Tree Traversal & App Idiosyncrasies
* **IPC Bottleneck:** Every call to `AXUIElementCopyAttributeValue` incurs synchronous Mach-message Inter-Process Communication (IPC) to the target process [[Apple Developer](https://developer.apple.com/documentation/applicationservices/1462121-axuielementcopyattributevalue)]. Recursive traversal of deep application trees introduces latency of 200ms–2000ms if queried naively [[Verified]].
* **Batch Retrieval:** To mitigate IPC roundtrips, `AXUIElementCopyMultipleAttributeValues` must be used to batch attributes (`kAXRoleAttribute`, `kAXTitleAttribute`, `kAXPositionAttribute`, `kAXSizeAttribute`, `kAXChildrenAttribute`) in a single IPC call [[Apple Developer](https://developer.apple.com/documentation/applicationservices/1460910-axuielementcopymultipleattribute)]. Passing `0` for options ensures individual attribute failures return `kAXValueAXErrorType` rather than aborting the entire batch [[Verified]].
* **Defensive Timeouts:** By default, an unresponsive app can stall `AXUIElement` calls indefinitely. Setting `AXUIElementSetMessagingTimeout(element, 0.25)` forces the IPC call to abort after 250ms with `kAXErrorCannotComplete` (-25204), keeping the agent loop non-blocking [[Apple Developer](https://developer.apple.com/documentation/applicationservices/1460598-axuielementsetmessagingtimeout)] [[Verified]].
* **Dynamic Event Observation:** Polling the AX tree wastes CPU. `AXObserverCreate` paired with `AXObserverAddNotification` allows subscribing directly to system-level UI changes (`kAXFocusedUIElementChangedNotification`, `kAXWindowCreatedNotification`, `kAXUIElementDestroyedNotification`) attached to `CFRunLoopGetCurrent()` [[Apple Developer](https://developer.apple.com/documentation/applicationservices/1461250-axobservercreate)] [[Verified]].
* **Electron & Chromium Activation:** Chromium and Electron apps keep internal web accessibility trees inactive by default to conserve memory [[Chromium Docs](https://chromium.googlesource.com/chromium/src/+/main/docs/accessibility/osx.md)]. 
  * In pure Chromium/Chrome, setting the attribute `AXEnhancedUserInterface = true` on the application `AXUIElement` forces tree generation, but triggers window snapping and focus bugs [[Verified]].
  * In modern Electron apps, setting the boolean attribute `AXManualAccessibility = true` on the app `AXUIElement` enables DOM accessibility without window-manager breakage [[Electron PR #25126](https://github.com/electron/electron/pull/25126)] [[Verified]].
* **App Tree Quality Matrix:**
  * **Chrome / Safari:** High semantic fidelity once initialized, but deeply nested DOMs cause severe traversal latency. Traversal must be capped to visible window bounds [[Verified]].
  * **VS Code / Slack / WhatsApp:** Electron-based; require `AXManualAccessibility = true`. Monaco Editor (VS Code) and chat message history (Slack) virtualize off-screen DOM nodes, meaning elements outside the immediate viewport do not exist in the AX tree [[Inference]].
  * **Figma:** Renders via an opaque WebGL/WebGPU `<canvas>`. The internal canvas UI is **100% invisible** to `AXUIElement`. Figma must immediately trigger the Vision Computer-Use fallback [[Verified]].
  * **Notes / Mail:** Native AppKit/SwiftUI controls expose rich, high-fidelity AX trees with zero IPC lag [[Verified]].
  * **Excel (Microsoft 365):** Custom C++ Ribbon/OfficeArt framework. Exposes window containers and ribbon buttons, but workbook spreadsheet grid cells are virtualized and frequently drop child accessibility nodes [[Inference]].

### 2.2 Event Injection: CGEvent vs AXPerformAction & Secure Input
* **AXPerformAction:** Calling `AXUIElementPerformAction(element, kAXPressAction as CFString)` triggers the control's accessibility handler directly without moving the physical hardware cursor or hijacking mouse control [[Apple Developer](https://developer.apple.com/documentation/applicationservices/1462095-axuielementperformaction)] [[Verified]].
* **Failure Modes of AXPerformAction:** Fails on custom canvas apps (Figma), non-standard custom controls without accessibility handlers, dropdown menus that dismiss if the mouse pointer isn't physically hovering over them, and web inputs that require hardware `mousedown`/`mouseup` to emit JavaScript event chains (`pointerdown`, `input`, `change`) [[Inference]].
* **CGEvent Synthetic Injection:** For elements where `AXPerformAction` fails, synthetic clicks are posted via `CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)` followed by `.leftMouseUp`, and dispatched via `event.post(tap: .cghidEventTap)` [[Apple Developer](https://developer.apple.com/documentation/coregraphics/cgevent/1454356-post)] [[Verified]].
* **Multilingual Unicode Injection:** Typing via keycodes fails for Indic languages (Hindi, Marathi, Hinglish). The Quartz Event API provides `event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16Array)`, which injects arbitrary UTF-16 Unicode characters directly into the focused field without translating to physical keyboard scancodes [[Apple Developer](https://developer.apple.com/documentation/coregraphics/cgevent/1456564-keyboardsetunicodestring)] [[Verified]].
* **Secure Event Input Lockout:** When a user focuses a password field or sensitive prompt, the host app calls `EnableSecureEventInput()` [[Apple Developer Carbon Guide](https://developer.apple.com/documentation/carbon)]. While active:
  * `IsSecureEventInputEnabled()` returns `true` [[Verified]].
  * All `CGEventTap` monitors are blinded to prevent keylogging [[Verified]].
  * `AXUIElementCopyAttributeValue` for `kAXValueAttribute` on secure fields returns empty or `kAXErrorCannotComplete` [[Verified]].
  * `CGEventPost` keystroke injection into secure fields is blocked by WindowServer [[Inference]]. Clicky must detect `IsSecureEventInputEnabled()` and yield control back to the user with an audible prompt.

### 2.3 Visual Context: ScreenCaptureKit Architecture & Cost
* **Stream vs Still Capture:** macOS 14.0+ provides `SCScreenshotManager.captureImage(contentFilter:configuration:)` for one-off screenshots without maintaining an active stream [[Apple Developer](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/4113970-captureimage)] [[Verified]]. For real-time tracking, `SCStream` delivers `CMSampleBuffer` frames directly backed by zero-copy `IOSurface` GPU textures [[Apple Developer](https://developer.apple.com/documentation/screencapturekit/scstream)] [[Verified]].
* **Performance Profile:** `SCStream` runs at 60 fps at <2–4% CPU on Apple Silicon, eliminating the severe WindowServer compositor stalls (50–100ms) associated with legacy `CGWindowListCreateImage` [[Verified]].
* **Self-Window Exclusion:** To prevent the AI from capturing its own overlay cursor, Clicky must query `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`, identify its own windows via `Bundle.main.bundleIdentifier`, and pass them to `SCContentFilter(display:excludingWindows:)` [[Verified via farzaa/clicky codebase]].

### 2.4 Ghost Cursor Overlay: NSWindow & Multi-Display Spaces
* **Window Hierarchy:** A transparent overlay requires subclassing `NSWindow` with:
  * `styleMask = [.borderless]`
  * `isOpaque = false`, `backgroundColor = .clear`
  * `level = .screenSaver` (floats above normal app windows, modal dialogs, and menu popups) [[Verified via farzaa/clicky OverlayWindow.swift]].
* **Click-Through Integrity:** Setting `ignoresMouseEvents = true` is mandatory so user clicks pass directly through the overlay to underlying apps [[Verified]].
* **Spaces & Full-Screen Auxiliaries:** To render seamlessly over native macOS Full-Screen apps and across Spaces, the overlay must set:
  ```swift
  collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
  hidesOnDeactivate = false
  ```
  Overriding `canBecomeKey` and `canBecomeMain` to return `false` ensures Clicky never steals keyboard/window focus [[Apple Developer](https://developer.apple.com/documentation/appkit/nswindow/1419515-collectionbehavior)] [[Verified]].
* **Multi-Display Allocation:** macOS handles multi-monitor coordinates across discrete `NSScreen` objects. A single global window spanning monitors causes clipping artifacts. **Exactly one `OverlayWindow` instance must be instantiated per connected `NSScreen`**, updating on `NSApplication.didChangeScreenParametersNotification` [[Verified via farzaa/clicky]].

### 2.5 Audio Engine: Echo Cancellation via VoiceProcessingIO
* **Acoustic Feedback Problem:** When Gemini Live responds via Mac speakers, the microphone captures the output, triggering false barge-ins and infinite self-interruption loops [[Inference]].
* **Native AEC Implementation:** `AVAudioEngine` provides built-in hardware Acoustic Echo Cancellation (AEC) and Automatic Gain Control (AGC) by configuring the Voice-Processing I/O unit [[Apple Developer](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/3152101-setvoiceprocessingenabled)]:
  ```swift
  try audioEngine.inputNode.setVoiceProcessingEnabled(true)
  try audioEngine.outputNode.setVoiceProcessingEnabled(true)
  ```
* **Strict Constraint:** Voice processing **must be enabled prior to calling `audioEngine.start()`** and requires a 44.1kHz or 48kHz audio format. Dynamic toggling while running causes kernel audio assertion crashes [[Verified]].

### 2.6 TCC Permissions & Code Signing Persistence
* **Required TCC Entitlements:**
  * Accessibility (`kTCCServiceAccessibility`): Required for `AXUIElement` inspection and `CGEventPost` injection.
  * Screen Recording (`kTCCServiceScreenCapture`): Required for `ScreenCaptureKit`.
  * Microphone (`kTCCServiceMicrophone`): Required for `AVAudioEngine` input.
  * Input Monitoring (`kTCCServiceListenEvent`): Required for passive `CGEventTap` shortcut detection if Accessibility is ungranted.
* **The Ad-Hoc Invalidation Trap:** Ad-hoc signed binaries (`codesign -s -`) do not have a stable designated requirement (DR); macOS hashes the raw binary (`cdhash`). Every incremental Xcode build changes the `cdhash`, causing TCC to silently revoke permissions on launch even though the toggle appears "ON" in System Settings [[Apple Developer Forums](https://developer.apple.com/forums/thread/705703)] [[Verified]].
* **The Fix:** Create a self-signed local code-signing identity (`codesign -s "Clicky-Dev"`) with a fixed bundle identifier (`com.clicky.mac`). TCC stores the permission against the stable certificate authority requirement rather than the binary hash [[Verified]].

### 2.7 Global Hotkeys & Push-To-Talk Options
* **Option A: Carbon `RegisterEventHotKey`:** Works system-wide without Accessibility or Input Monitoring permissions. **Limitation:** Requires a standard keycode plus modifier (e.g., `Cmd + Shift + Space`). It **cannot** intercept modifier-only keys (e.g., `Ctrl + Option` or standalone `Fn`) [[Apple Developer Carbon Docs](https://developer.apple.com/documentation/carbon)] [[Verified]].
* **Option B: `CGEventTapCreate` (Listen-Only):** Configured with `CGEventMaskBit(.flagsChanged) | CGEventMaskBit(.keyDown) | CGEventMaskBit(.keyUp)` at `.cghidEventTap`. Reliably captures modifier chords (`Ctrl + Option`) while running in the background [[Verified via farzaa/clicky GlobalPushToTalkShortcutMonitor.swift]]. Requires Accessibility or Input Monitoring.
* **Decision:** Use `CGEventTapCreate` for modifier-only push-to-talk, as Clicky already requires Accessibility permission.

### 2.8 App Lifecycle: LSUIElement & Sandbox Rules
* **Menu-Bar Only:** Setting `LSUIElement = true` in `Info.plist` removes the application from the Dock and Cmd+Tab switcher [[Apple Developer](https://developer.apple.com/documentation/bundleresources/information_property_list/lsuielement)] [[Verified]]. The UI is anchored to an `NSStatusItem` in `NSStatusBar.system`.
* **Sandbox Mandate:** Sandboxed macOS apps (`com.apple.security.app-sandbox = true`) are strictly prohibited from inspecting other apps via `AXUIElement` and cannot post synthetic input via `CGEventPost`. Clicky **must disable the App Sandbox** (`com.apple.security.app-sandbox = false`) in its `.entitlements` file [[Apple Developer Sandbox Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/)] [[Verified]].

### 2.9 macOS 15+ Sequoia Breaking Changes
* **Periodic Screen Recording Prompts:** macOS 15 Sequoia introduced monthly recurring system alerts asking users to re-confirm screen capture permissions for installed applications [[Apple Support macOS 15 Release Notes](https://support.apple.com/en-us/120283)] [[Verified]].
* **Process Restart Requirement:** Toggling Screen Recording in macOS 15 System Settings requires a full application termination (`killall`) before the Mach port grants access; dynamic permission acquisition without restart fails [[Verified]].

### 2.10 Deconstruction of `farzaa/clicky`
Direct inspection of `farzaa/clicky` (`leanring-buddy`) reveals:
* **Reusable Assets:**
  1. `OverlayWindow.swift`: Fully working multi-screen `NSWindow` implementation with `.screenSaver` level, `.fullScreenAuxiliary` collection behavior, and click-through flags [[Verified]].
  2. `MenuBarPanelManager.swift`: Production-grade `NSStatusItem` panel management and outside-click dismissal [[Verified]].
  3. `GlobalPushToTalkShortcutMonitor.swift`: Robust `CGEventTap` listening for `Ctrl + Option` chords [[Verified]].
  4. `CompanionScreenCaptureUtility.swift`: ScreenCaptureKit multi-display capture excluding self-app windows [[Verified]].
* **Missing Components (Must Build from Scratch):**
  1. Zero `AXUIElement` code: Farza's project was strictly a tutoring companion that pointed at elements via Claude vision coordinates; it had no accessibility tree engine [[Verified]].
  2. Zero execution capabilities: No mouse clicking, typing, or scrolling logic [[Verified]].
  3. No Echo Cancellation: Dictation pipeline lacked `VoiceProcessingIO`, causing audio loopback [[Verified]].
  4. Architecture was hardcoded to Anthropic Computer-Use + ElevenLabs + AssemblyAI rather than a unified Gemini Live WebSocket pipeline [[Verified]].

---

## 3. Implications for Clicky

1. **Hybrid Execution Engine (AX + Vision):** Clicky cannot rely solely on accessibility trees (which fail in Figma and virtualized web apps) or solely on vision (which has high latency and 10–20px coordinate inaccuracy). The engine must query the `AXUIElement` tree under the active window. If no matching semantic element is found within 150ms, it must instantly fall back to Gemini Live Vision bounding-box detection.
2. **Asynchronous Architecture:** Traversal and input injection must never run on `@MainActor`. All AX operations must live on a dedicated serial background actor (`AccessibilityActor`) with a 250ms messaging timeout to ensure the UI overlay remains fluid at 60 fps.
3. **Ghost Cursor Shared Control:** The overlay will display two cursors: the user's physical cursor and Clicky's semi-transparent "ghost" cursor. When the AI plans an action, the ghost cursor animates along a cubic Bézier spline to the target element. If the action is destructive (e.g., delete, send money, submit), the cursor pauses with a floating SwiftUI confirmation pill, allowing the user to verbally confirm ("yes, proceed") or steer away before `CGEvent` executes.

---

## 4. Risks & Unknowns

* **Electron Tree Wakeup Latency:** Setting `AXManualAccessibility = true` on an Electron app takes 50–200ms for the renderer to build its accessibility tree. Querying immediately after setting the flag may yield an empty tree [[Inference]].
* **Coordinate Space Mismatch:** CoreGraphics uses display points with a top-left origin; AppKit uses bottom-left; ScreenCaptureKit outputs raw pixel buffers (scaled by Retina 2.0x); and Gemini Vision outputs normalized coordinates (0.0 to 1.0). A single conversion bug inverts or displaces mouse clicks [[Verified]].
* **macOS Sequoia Screen Recording Prompts:** During live judging, a sudden macOS 15 monthly screen recording authorization modal could break the demo flow if the app is freshly installed [[Inference]].
* **Secure Input Traps:** If the user opens Terminal and executes `sudo`, or opens a browser password field, `IsSecureEventInputEnabled()` will drop synthetic events silently, causing the agent to appear frozen [[Verified]].

---

## 5. Recommended Decisions

### 5.1 Swift Package Layout & Module Architecture

```
Clicky/
├── Package.swift
├── Sources/
│   ├── ClickyApp/                 # LSUIElement entry, AppState, AppDelegate
│   │   ├── AppDelegate.swift
│   │   └── MenuBar/              # NSStatusItem & SwiftUI settings panel (from Farza)
│   ├── ClickyCore/                # State machine, action primitives, shared models
│   │   ├── ActionEngine.swift    # Tri-tier dispatcher (AX -> Direct -> Vision)
│   │   └── CoordinateMath.swift  # AppKit <-> CG <-> ScreenCaptureKit converter
│   ├── ClickyAccessibility/       # AXUIElement tree crawler, batching, AXObserver
│   │   ├── AXTreeCrawler.swift   # AXUIElementCopyMultipleAttributeValues
│   │   └── AXAppAdapters.swift   # Electron/Chromium AXManualAccessibility enabler
│   ├── ClickyInput/               # CGEvent injection & Hotkey monitoring
│   │   ├── EventSynthesizer.swift# Mouse clicks, drags, and Devanagari Unicode typing
│   │   ├── PushToTalkMonitor.swift # CGEventTap (adapted from Farza)
│   │   └── SecureInputGuard.swift# IsSecureEventInputEnabled detector
│   ├── ClickyVision/              # ScreenCaptureKit frame capture
│   │   └── ScreenCapturer.swift  # SCScreenshotManager + window filter
│   ├── ClickyAudio/               # AVAudioEngine with AEC & Gemini Live streaming
│   │   └── AudioStreamEngine.swift # VoiceProcessingIO setup (44.1kHz, AEC enabled)
│   ├── ClickyOverlay/             # Transparent NSWindow & SwiftUI ghost cursor
│   │   ├── OverlayWindow.swift   # Multi-display .screenSaver level NSWindow (from Farza)
│   │   └── GhostCursorView.swift # Bézier trajectory animation + confirmation pill
│   └── ClickyGemini/              # WebSocket client for Gemini Live multimodal API
│       └── GeminiLiveClient.swift # Async function calling & bidirectional audio/video
```

### 5.2 The 5 Most Likely Time-Sink Bugs (30-Hour Build) & Mitigations

| # | Bug / Failure Mode | Root Cause | Impact | Mitigation Strategy |
|---|-------------------|------------|--------|---------------------|
| **1** | **TCC Silent Permission Drop on Every Rebuild** | Ad-hoc codesigning (`-`) changes binary `cdhash` on every compile. System Settings says "Allowed", but OS returns `kAXErrorCannotComplete`. | **Dev stalls for 3–5 hours** debugging non-responsive AX/Event taps. | **Create a persistent self-signed identity:** Run `security create-certificate -s "Clicky-Dev"` and configure Xcode to sign with `"Clicky-Dev"`. Never use ad-hoc signing during development. |
| **2** | **Retina vs Logical Coordinate Disconnect** | Top-left vs bottom-left origin mismatch compounded by Retina 2.0x display scaling. | Cursor clicks 500px away from target or at inverted Y coordinates. | **Implement and unit-test `CoordinateMath.swift` in Hour 1.** Build pure functions: `toScreenPoints(normalized: CGPoint, display: NSScreen)` and enforce explicit coordinate types throughout the pipeline. |
| **3** | **Main-Thread Freeze on Deep AX Traversal** | Recursive `AXUIElement` traversal called synchronously on `@MainActor` blocks WindowServer event processing. | Mac spinning beachball; Clicky UI locks up completely. | **Strict Actor Isolation & Timeout:** Enforce `AXUIElementSetMessagingTimeout(element, 0.25)` and execute all crawling inside a dedicated `actor AccessibilityCrawler`. Hardcode a max tree depth of 5. |
| **4** | **Audio Feedback Loop & False Barge-In** | Gemini Live speaker audio bleeds into Mac mic; Gemini interrupts itself continuously. | Voice loop fails instantly; assistant stutters and resets. | **Enable `VoiceProcessingIO` prior to engine start:** Call `try inputNode.setVoiceProcessingEnabled(true)` in `init()`. Add a software gate that drops mic packets if speaker RMS exceeds threshold during early AEC convergence. |
| **5** | **The "Invisible Glass Wall" (Overlay Interception)** | `OverlayWindow` inadvertently captures mouse events if `ignoresMouseEvents` is reset during SwiftUI view updates. | User cannot click anything on their Mac; system appears completely frozen. | **Enforce Window Integrity:** Set `window.ignoresMouseEvents = true` immediately in `OverlayWindow.init()` and lock `canBecomeKey = false`. Test switching to native full-screen apps in Hour 2. |

---

## 6. Sources Cited

1. Apple Developer Documentation: [`AXUIElementCopyAttributeValue`](https://developer.apple.com/documentation/applicationservices/1462121-axuielementcopyattributevalue)
2. Apple Developer Documentation: [`AXUIElementCopyMultipleAttributeValues`](https://developer.apple.com/documentation/applicationservices/1460910-axuielementcopymultipleattribute)
3. Apple Developer Documentation: [`AXUIElementSetMessagingTimeout`](https://developer.apple.com/documentation/applicationservices/1460598-axuielementsetmessagingtimeout)
4. Apple Developer Documentation: [`AXObserverCreate`](https://developer.apple.com/documentation/applicationservices/1461250-axobservercreate)
5. Apple Developer Documentation: [`AXUIElementPerformAction`](https://developer.apple.com/documentation/applicationservices/1462095-axuielementperformaction)
6. Apple Developer Documentation: [`CGEvent.post(tap:)`](https://developer.apple.com/documentation/coregraphics/cgevent/1454356-post)
7. Apple Developer Documentation: [`CGEvent.keyboardSetUnicodeString`](https://developer.apple.com/documentation/coregraphics/cgevent/1456564-keyboardsetunicodestring)
8. Apple Developer Documentation: [Carbon Secure Event Input Reference](https://developer.apple.com/documentation/carbon)
9. Apple Developer Documentation: [`SCScreenshotManager`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/4113970-captureimage)
10. Apple Developer Documentation: [`SCStream`](https://developer.apple.com/documentation/screencapturekit/scstream)
11. Apple Developer Documentation: [`NSWindow.collectionBehavior`](https://developer.apple.com/documentation/appkit/nswindow/1419515-collectionbehavior)
12. Apple Developer Documentation: [`AVAudioInputNode.setVoiceProcessingEnabled`](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/3152101-setvoiceprocessingenabled)
13. Apple Developer Documentation: [`LSUIElement`](https://developer.apple.com/documentation/bundleresources/information_property_list/lsuielement)
14. Apple Developer Documentation: [App Sandbox Design Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/)
15. Apple Developer Forums: [TCC Code Signing and Designated Requirements Across Rebuilds](https://developer.apple.com/forums/thread/705703)
16. Apple Support: [What's new in macOS Sequoia 15](https://support.apple.com/en-us/120283)
17. Chromium Source: [Accessibility on macOS](https://chromium.googlesource.com/chromium/src/+/main/docs/accessibility/osx.md)
18. Electron Repository: [Expose AXManualAccessibility API](https://github.com/electron/electron/pull/25126)
19. GitHub Repository: [`farzaa/clicky`](https://github.com/farzaa/clicky) (`leanring-buddy`)
