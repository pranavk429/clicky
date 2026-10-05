# Clicky — Product & Business Positioning (Validation Report)

**Document:** Round-1 positioning pressure-test and sharpened story
**Project:** Clicky — voice-first shared-control AI cursor (macOS → Windows → Linux)
**Date:** 5 October 2026 · **Status:** Decision support for CraftVerse 2.0 Round 1
**Method:** bottom-up market sizing, budget-line verification from public sources ([VERIFIED]/[INFERENCE] labels inline), moat stress-tests against Gemini/Apple scenarios, pricing benchmarks. No changes made to the spec or previous reports.

---

## 0. Verdict (read this first)

| Gate (pattern-breaker, business mode) | Score | Mechanism |
| :--- | :---: | :--- |
| Pain intensity | 9/10 | A user who cannot operate a pointer is locked out of education/employment. RSI cohort is large and already on Macs. Pain is not the risk. |
| Willingness to pay — direct | 4/10 | The sufferer is often not the payer; Indian individuals anchor on free (Voice Control) and cheap (₹399/mo ChatGPT Go). |
| Willingness to pay — institutional | 7/10 | HEIs, regulated enterprises and CSR programs already hold budgets and deadlines (SEBI, UGC, RPwD). |
| Distribution | 4/10 | No channel exists yet. Must be built campus-by-campus and company-by-company in Pune first. |

**Verdict:** the *product* story is credible; the *business* story is not yet evidenced. One concrete fix flips the verdict: **sign two paid pilot LOIs (one HEI, one employer/NGO) before Round 2 at a published price — ₹49,999 / 10 seats / 6 months.** The team does not need to have collected the money; it needs to have a signature that says the budget line exists.

**Positioning in one line:** *Clicky is the voice-first control layer for the personal computer — you speak in English, Hindi, or Marathi; it executes through the OS itself; and nothing irreversible happens without your confirmation.*

**The single weakest part of the business story:** **no evidenced payer.** Every claim about "institutions will pay" is currently inference. Fix in §8.

---

## 1. Who pays, and with what budget

Three different people must be named, always: the **user** (motor-impaired student/worker, RSI sufferer), the **champion** (EOC coordinator, DEI/accessibility lead, NGO program manager, physiotherapist), and the **payer** (institute purchase committee, CSR committee, employer DEI/HR budget, family). The sale is to the champion, the money is the payer's, and today Clicky has tested neither.

### 1.1 Payer ranking (India first, global second)

| # | Payer | Budget line that actually exists | Evidence | Procurement path | Sales cycle | Year-1 verdict |
| :-: | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | **Pune IT employer — DEI / HR accommodation** | DEI & reasonable-accommodation spend; accessibility now a board-visible compliance item driven by SEBI's 2025–26 mandates | SEBI circular 31 Jul 2025 + extension to 31 Oct 2026; Feb 2025: 155 orgs penalized for RPwD digital-accessibility non-compliance; Persistent won CII Award for Excellence in Disability Inclusion with Pune as benchmark site [VERIFIED] | DEI/accessibility lead → procurement/legal → security review. Sell a 10-seat paid pilot; annual per-seat license thereafter | 1–2 quarters | **First rupee. Primary.** |
| 2 | **University / HEI — EOC + student welfare** | Institute funds, UGC/RUSA grants, state SIPDA grants; NAAC counts "assistive technology… screen-reading software" | UGC Accessibility Guidelines mandate Equal Opportunity Cells/Enabling Units; UGC directed all HEIs (Sept 2026) to implement RPwD Act §32 and activate EOCs; PCCOE and PCCOER both have EOCs [VERIFIED] | EOC coordinator → Dean/Registrar → purchase committee. Start with a free 10-seat semester pilot, convert to paid site license | 1–2 semesters | **Second. Strategic credibility.** |
| 3 | **NGO / CSR program** | Disability-tagged CSR: total CSR ≈ ₹17,967 cr; disability gets <1% (≈₹100–250 cr nationally); Samarthanam alone crossed ₹100 cr/yr; Tech Mahindra Foundation runs SMART+/ARISE+ for PwD; Persistent Foundation funds Pune causes | CSR portal data via Bluesky CSR / Giving Compass / Dasra; Tech Mahindra Foundation and Persistent Foundation sites [VERIFIED pool, INFERENCE fit] | Program manager → CSR committee (annual budget calendar). Sponsored seats: NGO buys 100–500 seats at ₹1,500/seat/yr; Clicky supplies outcome dashboard for CSR reporting | 1–3 quarters | **Volume + mission evidence.** |
| 4 | **Government schemes (ADIP / SIPDA / Sugamya Bharat)** | ADIP: 100% subsidy ≤₹22,500/mo income, 50% ≤₹30,000; category ceilings (up to ₹50,000 on approved expensive items; device list notified 9 Jul 2024). SIPDA: grant-in-aid to states/UTs, autonomous bodies and universities for accessibility, inclusion and skill projects | DEPwD ADIP page (revised w.e.f. 26 Sep 2024; **continuation approved only up to 31 Mar 2026 — renewal must be verified**); DEPwD SIPDA page; PIB [VERIFIED scheme, **UNKNOWN whether desktop software is on the ADIP list** — treat as a gap] | ADIP money flows through implementing agencies (ALIMCO, DDRCs, SHDCs, NGOs), not to software vendors directly. SIPDA flows through state departments/universities | 12–24 months | **Do not count in year 1.** Build the relationship now. |
| 5 | **Direct consumers (India)** | Personal/family spend; UPI-friendly | ChatGPT Go ₹399/mo (India-first tier) is the psychological anchor; Claude Pro ₹1,999/mo [VERIFIED] | App download + UPI. Student price needed | instant | **Evidence and retention, not the engine.** |
| 6 | **Global prosumer (English-speaking Mac)** | Personal spend, USD; AT software norms already exist | Read&Write individual $184/yr; JAWS Home $90–100/yr; Speechify ~$139/yr [VERIFIED] | Website, App Store, SEO, disability communities | instant | **Margin stabiliser.** |

**Honest read:** the first cheque comes from an **institution**, not a disabled individual. Clicky's pitch to judges must say this out loud — it reads as commercial realism, not lack of mission.

### 1.2 Procurement paths, concretely

- **Enterprise:** security review is the real gate — a non-sandboxed app requesting Accessibility + Screen Recording permissions will alarm IT. Requirements to pass: SSO (Azure AD/Okta), MDM deployment, local-only mode by default, audit log, DPDP-2023 privacy note, and a written "safety never travels to the cloud" architecture statement. Target M6 readiness.
- **University:** purchase-committee + GST vendor registration; government institutions eventually want a GeM listing. A semester pilot paid from EOC/discretionary funds (₹25k–50k) avoids the annual tender cycle.
- **NGO/CSR:** align to CSR committee calendars (annual budget approval, Q4/Q1 concentration). Offer a sponsorship SKU — "₹7.5 lakh funds 500 student seats for a year" — with a reportable impact dashboard.
- **Dealers (RehaKart et al.):** useful for hardware bundling and credibility, poor for software volume; assume 20–30% channel margin [INFERENCE]. Treat as a catalog placement, not a growth channel.
- **Sugamya Bharat / GIGW / IS 17802:** these are *compliance mandates*, not purchase orders. They create demand for accessible products, and SEBI's July 2025 circular explicitly requires accessibility clauses in **RFPs and vendor contracts** — Clicky should be listed in those RFPs as a workplace accommodation, and Clicky itself should publish an accessibility conformance statement [VERIFIED mandates; INFERENCE fit].

### 1.3 Regulatory window (why now)

- **SEBI:** regulated entities must complete digital-accessibility audits and remediation by **31 October 2026** (extended from earlier deadlines). They must also embed accessibility requirements into all procurement/RFP processes [VERIFIED].
- **UGC (Sept 2026):** HEIs directed to implement RPwD §32, activate EOCs, and track disability support data [VERIFIED].
- **Supreme Court (Apr 2025):** digital access affirmed as a fundamental right [VERIFIED, via Deque summary].
- **Draft Assistive Technology (Standards and Accessibility) Rules, 2025:** published for consultation (30 Sep 2025) — standards, distribution framework, BIS-recognised conformity, and a national safety-incident database for AT. Getting Clicky designed to these draft rules now is a defensible enterprise/procurement asset [VERIFIED draft; final notification status to monitor].

---

## 2. Market sizing sanity check (bottom-up, no hockey sticks)

### 2.1 India

| Layer | Calculation | Value |
| :--- | :--- | :--- |
| Motor-impaired active computer users | 5.43M locomotor-disabled (Census 2011) / 18.9M (NSS 76th) → ~250k–450k active desktop users [Report 04 inference] | ~350k (mid) |
| RSI/upper-limb knowledge workers | 5.8M IT workforce + ~2M adjacent desk roles; 5–8% with clinically significant limitation (from 34–74% reporting MSK symptoms — take the conservative tail) | ~350k–465k |
| **India TAM (24–36 mo, all OS)** | ~700k–900k people × blended ₹5,000/yr | **≈₹350–500 cr/yr ($40–55M)** |
| **India SAM (now: macOS + institutions)** | ~60–90k Mac individuals (≲ ₹4.5 cr) + serviceable institutional seats (top 200 HEIs, top 1,000 employers) | **≈₹10–15 cr/yr** |
| **India SOM (36 mo)** | 300–500 paid seats, blended mix of consumer/HEI/enterprise | **≈₹15–40 L ARR** |

The Windows port is what converts a ₹10-crore niche into a ₹350-crore market — that is the actual strategic argument for the roadmap, not platform vanity.

### 2.2 Global English-speaking Mac

- Mac installed base ≈ **100M users** globally (2024 estimate); US Mac share ≈ 14.8% of PCs [VERIFIED estimates, order-of-magnitude only].
- English-majority markets ≈ 40–45M Mac users. Significant upper-limb/motor or RSI need: conservative 1.5–3% → **0.6–1.3M people**.
- TAM at $99–144/yr: **$60–190M/yr**. Near-term SAM (willing to pay within 24 mo): ~60–130k people → **$6–13M/yr**. SOM: 1–3k subscribers by year 3 → **$100–400k ARR**.
- Global AT market context: $30.4B (2025) growing ~9%/yr, but mostly hearing/mobility hardware — do not cite it as Clicky's TAM.

**Combined realistic 36-month case: ₹2–5.5 cr ARR** (India institutional + global prosumer). That is an honest, investable niche-business number. The venture-scale upside is the platform thesis (voice as a general input layer) — present it as optionality, never as the base case.

### 2.3 First 100 users in Pune (90-day motion)

Definition of success: **100 activated users, 60 weekly-active by day 90, 20 paying consumers + 1 paid institutional pilot (10 seats) = 30 paying seats.** Activation = ≥3 successful sessions in first 10 days; D30 retention target 50%.

| Channel | Named targets | Reached | Installs | Active | Cost |
| :--- | :--- | :-: | :-: | :-: | :-: |
| Host-college EOC | PCCOE + PCCOER Equal Opportunity Cells (both exist [VERIFIED]) | 60 | 20 | 10 | ₹0 |
| Pune campuses | SPPU EOC, COEP, MIT-WPU, VIT; disability/welfare cells | 150 | 35 | 15 | ₹3k |
| NGO/rehab | Handicap Center Pune [VERIFIED]; Sarthak/Youth4Jobs (reach TBC) | 30 | 15 | 8 | ₹2k |
| RSI/physio clinics | Ortho/physio departments (e.g., Sancheti-type channels); referral cards + 1 free month | 40 | 12 | 6 | ₹5k |
| Pune IT DEI | Persistent, Tech Mahindra Foundation, Zensar, KPIT — warm intro via hackathon judges | 15 | 15 | 8 | ₹0 |
| Online (Marathi/Hinglish) | r/Pune, LinkedIn, accessibility Discords, physio creators | 50 | 20 | 8 | ₹0 |
| **Total** | | **~345** | **~117** | **~55–60** | **~₹10–15k** |

Cadence: 2 demos/week + 1 in-person "voice setup clinic"/week (mic placement, noise, personal vocabulary — this is the real retention lever for ASR quality). One demo-to-install conversation per weekday via WhatsApp follow-up.

---

## 3. Moat analysis — what survives Gemini and Apple

Premise: **the model is a supplier, not a product.** Gemini gets better for everyone. Apple owns the OS. Therefore the moat must live in execution, trust, distribution and evidence — never in acoustics or raw intelligence.

| Rank | Moat | What it actually is | If Gemini improves… | If Apple ships a voice-Siri for Mac… | What kills it | Verdict |
| :-: | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | **Trust / safety stack** | 5-tier local risk gate, Ghost Cursor, spoken confirmation, barge-in, injection isolation, audit log, DPDP posture | Unaffected — safety is client-side, not model-side | Apple can copy UX but does not sell an auditable enterprise compliance product with admin console | If Apple makes "confirm every destructive action" free and consumer-grade *and* enterprises accept it | **Primary.** Survives both scenarios. |
| 2 | **Engine + adapter library + compatibility corpus** | Per-app recipes (AX paths, Electron/Chromium enablement, canvas fallbacks, Indic unicode keystroke dispatch), failure telemetry (opt-in) | Adapters stay necessary; models don't execute UI actions deterministically | Apple could expose a desktop automation intents API; even so, per-app enterprise coverage takes years | If OS vendors ship a universal, reliable desktop intents API | **Primary, compounding.** 12–24 mo to replicate. |
| 3 | **India institutional distribution + compliance evidence** | EOC/NGO/CSR/dealer relationships; product built for RPwD/GIGW/IS 17802 and draft AT Rules; CSR reporting dashboards | Unaffected | Apple will not build Pune EOC relationships or CSR dashboards | Slow sales; tiny served market until Windows ships | **Strong in India, invisible to Apple.** |
| 4 | Integrations (SSO, MDM, VDI, enterprise app packs) | Enterprise deployment surface | Unaffected | Apple/frontier labs do not do customer-specific enterprise integrations | Commoditised only if the category matures | **Sticky in deals, not standalone.** |
| 5 | Latency engineering | AXHotCache, speculative ghost-cursor motion, <300ms execution leg, local execution | Model-leg latency advantage evaporates for everyone; execution leg stays local | Apple already has OS-level locality | Replicable by any strong client team | **Quality bar, not a moat.** 12–18 mo advantage. |
| 6 | Indic intent→OS grounding | Code-mixed command corpora, Marathi/Hindi UI-label mapping, accent-robust slot filling | Erodes — models will speak Marathi natively; everyone gets better | Apple adds Hindi/Marathi Voice Control (likely eventually) | Model improvement itself | **Wedge, not moat.** Own the *intent grammar*, not the acoustics. |
| 7 | Data flywheel | Unique execution-outcome data (which recipe worked, where it failed) feeds adapter quality | Amplifies adapters only if collection is instrumented from day 1 | N/A | Privacy constraints (DPDP) + low volume | **Amplifier for #2**, not a standalone moat. |

**Moat stack statement:** adapters improve with telemetry → benchmarked safety wins institutional deals → institutions fund adapter breadth and the Windows port → cross-platform coverage makes Clicky the default accommodation layer. Apple cannot serve the Indian institutional channel; Google cannot sell trust. **Nothing in the model layer is defensible; everything in the execution/trust/institutional layer is — if built deliberately.**

---

## 4. Business model and pricing

### 4.1 Options considered

| Option | Verdict | Reason |
| :--- | :--- | :--- |
| Consumer subscription (India) | Keep as a tier | ₹399 ChatGPT Go sets the ceiling; low ability to pay; but UPI makes it frictionless |
| Consumer subscription (global Mac) | **Recommended** | $99–144/yr is normal AT software pricing (Read&Write $184, JAWS Home $90–100) |
| Enterprise per-seat | **Recommended — margin engine** | ₹2,499/seat/mo is below JAWS Professional ($1,200 perpetual) amortised, and compliance budgets exist now |
| University site license | **Recommended — activation engine** | Aligns with UGC mandates; benchmark Read&Write $18.30/seat/yr at 150+ scale |
| NGO/CSR sponsored seats | **Recommended — volume + evidence** | Taps a real ₹100–250 cr disability CSR pool; provides reportable impact |
| Government (ADIP/SIPDA) | Watch, 12–24 mo | Scheme covers devices; desktop software coverage unproven; continuation beyond 31 Mar 2026 unverified |
| Hardware bundle | **No manufacturing.** Bundle a certified USB/BT mic via dealers at cost | Mic quality is the biggest WER lever; hardware margins and support are not |
| Per-task pricing | Reject | Meter anxiety is hostile to a user who depends on the tool; and it makes institutional budgeting impossible |
| Perpetual license | Reject until year 2 | API COGS is recurring; perpetual creates negative-margin legacy users |

### 4.2 Recommended price sheet

| SKU | Price | Notes |
| :--- | :--- | :--- |
| Free | ₹0 | 30 Live minutes/mo + unlimited local "fast-path" commands (English), 5 apps. Mission + funnel; hard-capped because every Live minute costs money |
| Student Pro | ₹249/mo | Verified student status; UPI |
| India Pro | ₹499/mo or ₹4,499/yr | 600 Live-min fair use/mo; overage packs ₹99/100 min |
| Global Pro | $11.99/mo or $99/yr | English markets; card/App Store |
| University/HEI | ₹1,800/seat/yr (min 25 seats) | Pooled 2,000 min/seat/yr; campus quotes above 1,000 seats |
| Enterprise | ₹2,499/seat/mo billed annually (₹29,988/yr) | Min 10 seats; pooled 1,200 min/user/mo; admin console, SSO, audit log, SLA, onboarding; ₹1,999 at 100+ seats |
| NGO/CSR sponsored | ₹1,500/seat/yr | Sponsor dashboard for CSR reporting; 100+ seat blocks |
| **Pilot (the first rupee)** | **₹49,999 / 10 seats / 6 months** | Under a manager's discretionary-approval threshold; converts to enterprise/university SKU |

Benchmarks used: GlassOuse V1.4 ₹60,099; Tobii setups ₹2–7L; Dragon ₹17,500–50,000 (Windows-only since macOS retirement); JAWS Professional $1,200 / Home $90–100/yr; Read&Write $18.30/seat/yr (150+) and $184 individual; Claude Pro ₹1,999/mo; ChatGPT Go ₹399/mo [all VERIFIED in reports 04/01 or this session].

### 4.3 Unit economics (the number that must be managed)

Verified Live rates: audio input $3/1M tokens ≈ $0.005/min; audio output $12/1M ≈ $0.018/min (25–32 tokens/sec) [VERIFIED]. In rupees, a mixed conversation costs roughly **₹1–2 per active minute** with the current model and no optimisation [INFERENCE].

| Daily active use | Monthly Live minutes | Monthly COGS @ ₹1/min | Viable at ₹499? |
| :--- | :-: | :-: | :--- |
| 10 min/day | 300 | ~₹300 | Yes (40%+ margin) |
| 20 min/day | 600 | ~₹600 | No — needs caps |
| 40 min/day | 1,200 | ~₹1,200 | No — enterprise tier |

**Conclusions and required actions:**
1. **Unlimited consumer plans are not fundable.** Fair-use caps are a financial control, not a customer-hostile limit — message them as such.
2. **COGS optimisation is a business requirement, not an optimisation:** route deterministic commands through a local/cheap fast-path (₹0), use cheaper Live flash tiers where available, prefer TTS output ($6/1M ≈ $0.009/min) over Live audio output ($12–21/1M) for confirmations, close idle sessions, and keep context compression on. Target ≤₹0.4/min blended by M6.
3. **Enterprise pools absorb variance**; price per seat, meter pooled minutes, and never sell unlimited site licenses without a pooled cap.
4. Institutional prepayment (annual, in advance) funds the API bill — retail monthly consumers should not drive cash flow.

---

## 5. Roadmap to platform — engine + adapters

**Architecture story (say it exactly like this):** one OS-agnostic engine (intent routing, risk gate, session lifecycle, overlay, licensing) + per-OS adapters (macOS AXUIElement → Windows UIA → Linux AT-SPI) + per-app recipes (adapters that encode how Salesforce, SAP, VS Code, or an intranet app behaves). macOS is not the market — it is the **proving ground** where AX gives the cleanest execution layer.

| Phase | Timeline | Build | Exit milestone (gate) |
| :--- | :--- | :--- | :--- |
| **P0 — Evidence** | Now (hackathon) | Working macOS demo; 10-task benchmark; latency/cost telemetry; Ghost Cursor safety proof | Benchmark deck + 0 unconfirmed destructive actions; disambiguation slide |
| **P1 — Pilot revenue** | M0–M3 (Oct–Dec 2026) | 10-app certification matrix; <5-min onboarding; licensing/billing; privacy + DPDP note; security questionnaire pack | **2 paid pilot LOIs (HEI + enterprise/NGO); 25 paying seats**; TIDE 2.0 application; rebrand decision |
| **P2 — Enterprise-ready + Windows spike** | M3–M6 (Jan–Mar 2027) | Adapter SDK v0; admin console + license server; Windows UIA feasibility spike (5 apps: Chrome/Edge, Word, Outlook, Teams, Explorer) | **100 paid seats; first university site license; ₹1.5–3L MRR**; Windows spike demo on the same tool schema |
| **P3 — Second platform** | M6–M12 (Apr–Oct 2027) | Windows private beta with 2 paid design partners; adapter breadth; GeM registration; ISO 27001 readiness | **300–500 paid seats; ₹40L–1 cr ARR**; Windows gate = 100 paid macOS seats + 2 enterprise design partners |
| **P4 — Platform** | M12–M24 | Adapter marketplace/SDK licensing to other AT vendors and employers; Linux AT-SPI only if an anchor deployment funds it | 3+ enterprise logos; platform API users; Linux gate = anchor customer funding |

Port cost estimate [INFERENCE]: core engine is 55–65% reusable; Windows UIA parity on ~20 apps ≈ 2 engineers × 10–12 weeks; Linux AT-SPI alpha ≈ 1 engineer × 8–10 weeks. The existing file layout (`ClickyCore` vs `ClickyAccessibility`) is already the proof of decoupling to show judges.

**Hackathon slide framing:** show three phases with **gates, not dates** — "Windows pilot starts when we have 100 paid macOS seats and two design partners." That is the opposite of hand-waving: it is a commitment device. One line to neutralise the 2.64% macOS market-share objection: *"macOS is the proving ground, not the market — Windows is where 82% of India's desktops are, and the engine is already split from the OS adapter."*

---

## 6. Positioning and naming

### 6.1 Positioning statement (one sentence)

**"Clicky is the voice-first control layer for the personal computer: you speak naturally in English, Hindi, or Marathi, and it operates the machine through the OS's own accessibility APIs — visibly, reversibly, and only on your confirmation — turning voice into a first-class input for the people the mouse was never designed for."**

Shorter cut for slides: *"Clicky turns voice into a first-class computer input — natural speech in, safe OS actions out, under your control."*

Category language rule: in India, lead with **accessibility** (mission + buyers). In investor/global contexts, lead with **input layer** (category expansion). Never call it "an AI cursor" — that's the farzaa/clicky box, and it makes the product sound like a toy.

### 6.2 Taglines (3 options)

1. **"Voice is the new cursor."** — category-defining; best for slides, HN/Product Hunt, investors. (Recommended master tagline.)
2. **"Control your computer in the language you think in."** — India wedge; mirror in Devanagari for Marathi/Hindi campaigns.
3. **"It doesn't just talk. It does — with your permission."** — shared-control/trust line; best for enterprise and safety-conscious buyers.

### 6.3 Naming decision

**Recommendation: keep "Clicky" only as the hackathon working name; rebrand before the first paid pilot.**

Reasons: (a) three live collisions — Roxr Software's Clicky Web Analytics on clicky.com since 2006, used by 1M+ websites [VERIFIED this session], `farzaa/clicky` (MIT, viral) [Report 01], and commercial `heyclicky.com` [Report 01]; (b) "Clicky" is a generic, toy-sounding English word, which contradicts the platform positioning and weakens trademark/SEO (the `.com` is occupied by an established brand); (c) rebranding costs nothing today and everything after contracts and app-store listings exist.

At Round 1: include a one-line disambiguation note ("working name; ships as [X] before pilot") rather than a defensive slide. Screen candidates against: 2 syllables, class 9/42 trademark clear, .com/.ai available, not a common English word, optional Devanagari form. Shortlist to screen (not recommendations yet): **Vaani (वाणी), Shabda, Saarthi, Awaaz** — each requires a trademark + domain check before use.

---

## 7. Updated Round-1 PPT skeleton (7 slides)

**Slide 1 — Title & Hook.**
**Headline:** "Voice is the new cursor."
- Working macOS prototype — not slideware: end-to-end spoken command → real OS action (Safari, Notes, Mail, Calculator).
- Execution leg <300ms (p50 ≈ 100ms), measured live by the in-app latency meter; voice turn 450–750ms.
- Natural Hindi / Marathi / English — what macOS Voice Control cannot do (no Hindi/Marathi navigation support).

**Slide 2 — The Problem.**
**Headline:** "The last interface that still requires working hands."
- 18.9M Indians live with locomotor disability (NSS 76th); 34–74% of Indian software workers report work-related musculoskeletal strain.
- Today's options: GlassOuse ₹60,099, Tobii ₹2–7L, Dragon ₹17.5k–50k (macOS abandoned 2018) — or free but rigid, English-only Voice Control.
- AI agents are the wrong shape for this user: 3–6 s per step, autonomous, no real-time stop, ₹13–30/task.

**Slide 3 — The Solution: Shared Control.**
**Headline:** "You speak. Clicky shows. You confirm."
- Tri-tier execution: Accessibility tree (<50ms, zero tokens) → direct APIs → vision only when blind.
- Ghost Cursor + spoken confirmation ("Haan"/"Go") on irreversible actions; barge-in cancellation <150ms.
- 5-tier local risk gate + prompt-injection isolation: the cloud never gets authority to click.

**Slide 4 — Market & Who Pays (sharpened).**
**Headline:** "A beachhead we can own, and the institutions that already hold the budget."
- Bottom-up: ~350k motor-impaired + ~350k RSI desktop users in India; ₹350–500 cr TAM, ₹10–15 cr serviceable today (Mac + institutions) — honest, expands with the Windows port.
- Payers, in order: enterprise DEI/accommodation → HEI Equal Opportunity Cells (UGC mandate, Sept 2026) → CSR programs (₹100–250 cr disability pool).
- Why now: SEBI accessibility audit/remediation deadline 31 Oct 2026; Feb 2025 saw 155 orgs penalised under RPwD.

**Slide 5 — Moat & Technical Edge.**
**Headline:** "The model is rented. The control layer is ours."
- Trust stack: local 5-tier gate, audit trail, injection defense — the thing enterprises can procure and verify.
- Adapter library + compatibility corpus (Electron, canvas, Indic unicode dispatch) — Gemini-independent, compounds with opt-in telemetry.
- Cost/latency: 90% of actions via AX at ~₹0; ~₹2/task all-in vs ₹13–30 for vision agents.

**Slide 6 — Business Model & Traction Plan.**
**Headline:** "Institutions pay first; subscriptions scale later."
- Price sheet: pilot ₹49,999/10 seats/6 months; HEI ₹1,800/seat/yr; enterprise ₹2,499/seat/mo; India Pro ₹499/mo; global $11.99/mo (benchmarks: GlassOuse ₹60,099; JAWS $90–1,200; Read&Write $18–184; Claude Pro ₹1,999).
- Unit economics: ~₹1–2/min Live COGS today, target ≤₹0.4/min via fast-path routing and cheaper output; fair-use caps; enterprise pools.
- 90-day traction: 100 activated users in Pune (PCCOE/PCCOER EOCs, SPPU, Handicap Center Pune, RSI clinics, IT DEI teams) → 25 paying seats + 1 pilot.

**Slide 7 — Roadmap, Team & Ask.**
**Headline:** "macOS is the proving ground; Windows is the market."
- Engine + adapters: Phase 1 macOS proof → Phase 2 Windows UIA with 2 paid design partners (gated on 100 paid seats + 2 LOIs) → Phase 3 adapter SDK/platform; Linux only if anchor-funded.
- Team of 4 with owned subsystems: AX/input, Gemini Live streaming, overlay/UX, benchmarks/pitch — 30-hour burndown tracker on the slide.
- The ask: 2 pilot partners (one HEI, one Pune employer/NGO) and mentors; first LOIs targeted within 30 days of the event.

*(Changes vs Report 06 skeleton: replaced the generic "Impact" slide with "Market & Who Pays"; added pricing and payer proof to the business slide; reframed the roadmap as gates-not-dates; added the rebrand/working-name note.)*

---

## 8. Risks, the weakest link, and the 2-week fix

| Risk | Severity | Mitigation |
| :--- | :---: | :--- |
| No evidenced payer (weakest) | Critical | 10 outreach calls now; 2 LOIs before Round 2; publish the ₹49,999 pilot price |
| Live COGS vs ₹499 pricing | High | Caps + fast-path + TTS optimisation; target ≤₹0.4/min by M6 |
| ADIP covers devices, not software; continuation beyond 31 Mar 2026 unverified | Medium | Don't build year-1 revenue on ADIP; verify renewal; pursue SIPDA/CSR first |
| macOS ~2.6% India share | Medium | Global Mac revenue + Windows roadmap; macOS framed as proving ground |
| Enterprise IT security review blocks non-sandboxed app | Medium | SSO/MDM/audit/logging by M6; local-first data posture; DPDP note |
| Google dependency (model rented) | Medium | Model-agnostic router behind the tool schema; test a second Live provider each quarter |
| Name collision confusion | Low now, high later | Rebrand before first paid pilot; working-name note at hackathon |
| Prompt-injection trust failure in the wild | High | Keep T10 adversarial benchmark in every release; publish refusal evidence |

**The fix that matters (2 weeks):**
1. Put the ₹49,999 / 10-seat / 6-month pilot offer on one page (with the HEI and enterprise SKUs behind it).
2. Ten structured conversations — 3 HEIs (start with PCCOE/PCCOER EOC), 3 Pune employers (Persistent, Tech Mahindra Foundation, Zensar/KPIT), 2 NGOs, 2 clinicians.
3. Ask one closing question in each: *"If this worked as demoed, could you sign a 10-seat pilot this quarter, and from which budget line?"*
4. Instrument usage from day 1 (minutes/seat, sessions/week) — retention data is the asset that makes the next pricing decision evidence-based.
5. Target: **2 signed LOIs + 1 written budget-line confirmation** before Round 2 judging.

**What would change our mind on the verdict:** two signed paid pilots → the business story becomes evidenced; zero signatures despite ten honest attempts → the wedge must shift toward global prosumer B2C first (subscription in USD) with India as a mission/marketing dimension, not the revenue engine.

---

## Sources (spot-verified this session unless carried from Reports 01/04/06)

- DEPwD — ADIP scheme page (revised 26.09.2024; continuation to 31.3.2026; device list 09.07.2024): https://depwd.gov.in/en/adip
- UMANG — ADIP subsidy/income details (₹22,500 for 100%; up to ₹50,000 for expensive items): https://web.umang.gov.in/landing/scheme/detail/scheme-of-assistance-to-disabled-persons-for-purchasefitting-of-aidsappliances_sadppfaa.html
- Vikaspedia — ADIP (dependent income ceiling ₹30,000): https://en.vikaspedia.in/viewcontent/social-welfare/differently-abled-welfare/schemes-programmes/adip-scheme
- DEPwD — SIPDA: https://depwd.gov.in/en/sipda
- PIB — DEPwD schemes overview (SIPDA description): https://www.pib.gov.in/PressReleasePage.aspx?PRID=2197426
- UGC — Accessibility Guidelines PDF: https://www.ugc.gov.in/pdfnews/8572354_Final-Accessibility-Guidelines.pdf
- University World News — UGC directs HEIs on RPwD implementation (Sept 2026): https://www.universityworldnews.com/post.php?story=2026092516320482
- DEPwD — public consultation on draft AT standards (Sept 30, 2025): https://depwd.gov.in/en/public-consultation-on-draft-accessibility-standards-for-the-assistive-technologies-sector
- Assistive Technology (Standards and Accessibility) Rules, 2025 (draft text): https://cdnbbsr.s3waas.gov.in/s3e58aea67b01fa747687f038dfde066f6/uploads/2025/09/20250930960097846.pdf
- SEBI circular coverage (July 31, 2025; audits/remediation extended to Oct 31, 2026; RFP clauses): https://leglobal.law/2025/09/19/india-sebi-mandates-digital-accessibility-for-all-regulated-entities · https://www.digitala11y.com/indias-digital-accessibility-laws-and-overview/
- GIGW 3.0 mandatory, 88 checkpoints, STQC certification: https://blog.certcube.com/gigw-compliance-audit · https://halfaccessible.com/india-digital-accessibility-compliance
- Feb 2025 enforcement — 155 organisations penalised: https://www.pivotalaccessibility.com/2025/06/rpwd-act-and-is-17802-indias-digital-accessibility-standards-2025-guide
- Supreme Court Apr 2025 digital-access ruling (summary): https://www.deque.com/blog/indias-proposed-new-accessibility-standards-what-businesses-can-do-today
- CSR: disability <1% of ~₹17,967 cr spend: https://blueskycsr.com/2026/03/06/csr-spending-in-the-disability-area-an-underutilized-opportunity · 0.9% ≈ ₹234 cr: https://givingcompass.org/article/why-disability-is-overlooked-in-corporate-social-responsibility-funding · Dasra landscape: https://dasra.org/individual-resources/from-promise-to-practice-a-landscape-report-on-disability-inclusion-and-civil-society-action-in-india
- Samarthanam ₹100 cr CSR milestone: https://samarthanam.org/samarthanam-trust-crosses-100-crore-csr-funding
- Tech Mahindra Foundation disability programs (SMART+/ARISE+): https://www.techmahindra.com/about-us/corporate-citizenship/tech-mahindra-foundation/disability
- Persistent — CII award for disability inclusion (Pune benchmark): https://www.persistent.com/media/press-releases/persistent-wins-cii-award-for-excellence-in-disability-inclusion
- PCCOE/PCCOER Equal Opportunity Cells: http://www.pccoepune.com/equal-opportunity-cell.php · https://www.pccoer.com/equal-opportunity-cell.php
- Handicap Center Pune: https://handicapcenterpune.org
- MeitY TIDE 2.0 (up to ₹7L grant, ₹40L scale-up): https://msh.meity.gov.in/schemes/tide · https://www.sandipincubator.org/tide2.0.php
- ChatGPT Go India ₹399/mo (UPI): https://www.ndtv.com/india-news/openai-launches-new-chatgpt-go-plan-in-india-check-prices-features-9112949 · https://indianexpress.com/article/technology/openai-introduces-chatgpt-go-in-india-at-rs-399-upi-10197639
- Gemini Live token rates ($3 audio in / $12 audio out per 1M; 25–32 tokens/sec): https://ai.google.dev/gemini-api/docs/pricing · https://www.linkedin.com/posts/dynamicwebpaige_its-still-wild-to-compare-the-cost-of-google-activity-7404970713645785088-VgKt
- JAWS pricing ($1,200 Pro perpetual; $90–100/yr Home): https://vispero.com/news/freedom-scientific-announces-changes-to-us-pricing-and-software-delivery-options · https://afb.org/aw/19/12/15137
- Texthelp Read&Write pricing ($18.30/seat/yr at 150+; $184 individual; district $2.75 at 25k): https://www.everway.com/products/read-and-write-education/pricing
- Mac installed base ~100M (2024); US share 14.8%: https://www.spyhunter.com/shm/macos-stats · https://www.reddit.com/r/mac/comments/1jej8a5/
- Global AT market size ($30.4B 2025, ~8.9% CAGR): https://www.custommarketinsights.com/report/assistive-technology-market

*End of Report.*
