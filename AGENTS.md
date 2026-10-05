# AGENTS.md — Working in the Clicky repository

> **Audience:** every AI coding agent (and human) who touches this repository.  
> **Goal:** keep the repository **professional, honest, and buildable at every commit** while the project is built for the CraftVerse 2.0 Hackathon (Agentic AI track).
>
> Read this file completely before writing anything. It is intentionally opinionated; when in doubt, favor the spec over your own judgment and ask the user.

---

## 1. What this repository is

**Clicky** is a voice-first, accessibility-first, shared-control AI cursor for macOS: natural speech in English / Hindi / Marathi → direct OS actions, with a Ghost Cursor preview, spoken confirmation gates, and a local <150 ms stop.

| Fact | Value |
| :--- | :--- |
| Event | CraftVerse 2.0 Hackathon (PCCOE&R Pune), Agentic AI track |
| Visibility | **Public** — assume everything you commit is world-readable forever |
| License | MIT © 2026 Clicky contributors |
| Language / runtime | Swift 6 (v5 language mode), AppKit + SwiftUI, macOS 14.2+ |
| Cloud dependency | Google Gemini 3.8 Live (voice) + 3.8 Flash (vision fallback only) |
| Current stage | **Pre-alpha: spec complete, implementation starting** |

## 2. Sources of truth (read in this order)

1. **`docs/superpowers/specs/2026-10-05-clicky-voice-ai-cursor-design.md`** — *Revision 3*. The single architectural authority. Contains the corrected wire protocol, tri-tier execution, 5-tier safety model, latency budgets, signing/bundle recipe, and the 3-minute demo script. **Any conflict with any other document is resolved in favor of the spec.**
2. **`docs/research/validation/05-spec-errata.md`** — the adversarial review that produced Revision 3. Read it before implementing anything protocol- or safety-related; it explains *why* the spec says what it says.
3. **The implementation plan** — to be written at `docs/superpowers/plans/2026-10-05-clicky-voice-ai-cursor-implementation.md` using the prompt in `docs/prompts/2026-10-05-write-implementation-plan-agent-prompt.md`. Once it exists, **the plan is the task-level authority**; this file remains the repo-process authority.
4. **`docs/research/reports/` and `docs/research/validation/`** — supporting evidence. Reports carry correction banners; where they disagree with the spec, the spec wins.

### Immutable documents — never modify
- `docs/superpowers/specs/**` (the spec)
- `docs/research/**` (reports, validation, errata, prompts, logs)

If you find an error in an immutable document, **do not edit it**. Record the discrepancy in the appropriate place (plan errata, a new dated validation note) and surface it to the user.

## 3. Current status and next action

- ✅ Spec Revision 3 — signed off.
- ✅ Research + 5 validation passes — complete.
- ⬜ Implementation plan — **next action**. A fresh agent session must be handed `docs/prompts/2026-10-05-write-implementation-plan-agent-prompt.md` verbatim.
- ⬜ Chunks 1–5 build (see §5).

**Do not start coding until the implementation plan exists** and the user has signed off on it. The plan defines exact file paths, task order, and per-task verification.

## 4. Repository professionalism contract

These rules exist so the public repo reads as a serious engineering project to judges, users, and future contributors. Treat them as CI-level requirements.

### 4.1 Commit discipline
- **`main` is always buildable and green.** Never leave a broken build or failing tests on `main`.
- **One logical change per commit.** During plan execution: one task = one commit (the plan encodes exact commit messages).
- **Conventional Commits** format, imperative mood, lowercase scope:

  | Type | Use for | Example |
  | :--- | :--- | :--- |
  | `feat` | new capability | `feat(core): add unit-tested coordinate conversions` |
  | `fix` | bug fix | `fix(input): chunk unicode keystrokes at 20 UTF-16 units` |
  | `test` | tests only | `test(safety): cover Hindi/Marathi confirmation phrases` |
  | `docs` | documentation | `docs: add chunk 2 completion notes to README` |
  | `chore` | tooling, deps, housekeeping | `chore: pin swift-tools-version in Package.swift` |
  | `refactor` | no behavior change | `refactor(ax): extract CacheKey normalization` |

- Scopes follow module names: `core`, `gemini`, `ax`, `input`, `safety`, `audio`, `vision`, `overlay`, `app`, `scripts`, `docs`.
- **Never** commit generated artifacts (`.build/`, `build/`, `*.app`), secrets, or anything matched by `.gitignore`.
- After each accepted chunk: tag it (`git tag chunk-1-foundation`) and write a GitHub Release with a short, honest summary.
- Update the README roadmap table (`⬜ Planned → 🟨 In progress → ✅ Done`) in the same commit that completes a chunk.

### 4.2 Honesty rules (non-negotiable)
- **No unmeasured claims.** Every performance number is either **measured** (with the meter/benchmark that produced it) or explicitly labeled a **target**. The spec's claims discipline applies to README, slides, commit messages, and PR descriptions alike.
- Unverified platform behavior (AX rebuild times, Electron tree wake-up, frame token counts) must ship with a *measurement step + documented fallback* — never an asserted number.
- Known open verification items (flag, verify, then update the plan — do not guess):
  - `scheduling` enum spelling/placement (`INTERRUPT` vs `INTERRUPTED`; on `FunctionResponse` vs nested in the response payload) — verify in the day-0 Live API spike.
  - Computer Use frame token counts — read from `usageMetadata`.
  - Electron `AXManualAccessibility` wake-up latency — measure per app.

### 4.3 Secret hygiene
- **Never commit** `GEMINI_API_KEY` or any credential, token, certificate, or `.p12`. The key is read from the environment (dev) / Keychain (app).
- No API keys in logs, test fixtures, screenshots, or commit messages.
- If the signing certificate is ever regenerated, **all TCC grants are destroyed** — the plan's recipe exists precisely to avoid this. Do not "fix" signing by recreating the cert.

### 4.4 Public-repo hygiene
- No personal data: remove/redact names, emails, phone numbers, machine-specific paths, and tokens from logs and fixtures before committing.
- Keep `README.md` current: status, roadmap, and screenshots whenever a user-visible milestone lands.
- Maintain the GitHub repo metadata (description + topics) as the project evolves.
- File an issue before starting large, unplanned work; link the relevant spec section.

## 5. Execution workflow (once the plan exists)

The plan prescribes **subagent-driven development** with review gates. Summary:

1. **Per task:** fresh implementer subagent (give it the full task text — never conversation history) → implement + tests + commit → **spec-compliance review** → fix → **code-quality review** → fix → task complete.
2. **Per chunk:** run the chunk's Acceptance task (exact commands + manual OS checks) → dispatch a **chunk reviewer** over all task diffs as one unit → fix → tag + commit `chunk N complete: <name>`.
3. **Never start chunk N+1** with failing checks or open review issues from chunk N.
4. **TDD always** for pure logic: failing test → show failure → implement → show pass. OS integrations get explicit `[manual OS check]` procedures instead.
5. Tag every verification step `[unit test]`, `[integration]`, or `[manual OS check]`.
6. Model selection: cheap/fast models for mechanical tasks, standard models for integration, most capable models for reviews.
7. After the final chunk: whole-implementation review + `finishing-a-development-branch`.

**Scope-cut ladder if behind (spec §8):** vision fallback first → Marathi tuning → Tier-2 AppleScript handlers.  
**Never cut:** Ghost Cursor overlay, voice-triggered AX click, spoken confirmation gate, local stop path.

## 6. Repository layout and boundaries

```text
clicky/
├── README.md                  # public front door — keep current
├── AGENTS.md                  # this file
├── LICENSE                    # MIT
├── docs/                      # spec, research, plans — immutable except plans/
├── Package.swift              # (Chunk 1) SwiftPM graph: 9 library targets + test targets
├── Resources/Info.plist       # (Chunk 1) LSUIElement + usage descriptions
├── scripts/                   # (Chunk 1) sign-dev.sh · make-app.sh · doctor.sh · run.sh
├── Sources/
│   ├── ClickyApp/             # LSUIElement entry, menu bar, onboarding
│   ├── ClickyCore/            # CoordinateMath, Permissions, LatencyMeter
│   ├── ClickyGemini/          # protocol types, Live client, tool router
│   ├── ClickyAccessibility/   # crawler, hot cache, app adapters
│   ├── ClickyInput/           # event synthesis, kill switch, secure input
│   ├── ClickySafety/          # risk gate, pending-action gate, intent ledger
│   ├── ClickyAudio/           # AVAudioEngine + AEC + local VAD
│   ├── ClickyVision/          # on-demand frame capture
│   └── ClickyOverlay/         # per-screen panels + Ghost Cursor
└── Tests/                     # one target per logic module
```

Rules:
- All targets use `swiftLanguageMode(.v5)`.
- New files go inside the module that owns the concern — no dumping grounds.
- Pure logic (coordinate math, risk classification, protocol models, normalization) must be unit-testable and tested; OS touchpoints are isolated behind protocols for faking.
- The **demo path is the signed `.app`** (`scripts/make-app.sh` → `build/Clicky.app`). `swift run` is developer-only for unit work — macOS will not grant microphone access to a bare executable.

## 7. Demo and evidence rules (judge-proofing)

- The 3-minute demo arc (spec §6) is the contract: hook → Indic voice speed → shared control / Ghost Cursor stop → telemetry closer.
- The on-screen **latency meter** shows the three measured legs; the **cost meter** uses official rates (₹85/USD configurable).
- Adversarial task T10 passes only when **no tool call executes for instructions originating in screen content** — "the model refused" is not a pass.
- Destructive-action rule: **0 unconfirmed Tier 3–5 actions across 20 trials** — demo must show the gate, not bypass it.
- Demo insurance: local mock mode (scripted session through the real AX/CGEvent path — *not* the 3.1 fallback model), hotspot failover, uncut backup video, `doctor.sh` before every run.
- When presenting: disambiguate the "Clicky" name in the first 10 seconds (vs. `farzaa/clicky` and `heyclicky.com` — neither controls the computer or supports Indic voice).

## 8. Checklists

**Before every commit**
- [ ] Build + tests pass (or the commit is docs-only)
- [ ] No secrets, tokens, personal data, or build artifacts staged (`git status` + `git diff --cached --stat`)
- [ ] Conventional commit message; one logical change
- [ ] Docs touched by the change (README roadmap if a chunk landed)

**Before every push to `main`**
- [ ] `main` builds from clean checkout
- [ ] README still accurate (status, roadmap, links resolve)
- [ ] No WIP/TODO comments introduced (plan rule: no placeholders, ever)

**Before the demo**
- [ ] `./scripts/doctor.sh` green; signed `.app` runs on the demo machine
- [ ] Permissions pre-granted; mock mode wired; hotspot failover tested
- [ ] Meter reading real values; claims in slides match meter or are labeled targets
- [ ] Backup video ready

## 9. Ask-before-acting

Escalate to the user (do not decide autonomously):
- Any change to the spec's architecture, safety model, or scope-cut ordering.
- Rebranding, licensing, or repo-visibility changes.
- Adding new cloud services, dependencies, or telemetry beyond the spec.
- Anything that would alter TCC/signing behavior on the user's machine.
- Publishing anything to the README that claims a measured number.
