# Clicky — Accessibility Wedge Validation: Motor Impairment, RSI, and the Speech Caveat

**Document:** Validation Report 03 — Accessibility Wedge  
**Project:** Clicky — Voice-First Shared-Control AI Cursor for macOS (CraftVerse 2.0, Pune)  
**Date:** 5 October 2026  
**Status:** Research/validation — does not modify the spec. Feeds Revision 3 and the Round-1 PPT.  
**Method:** Primary-source web verification (Oct 2026) of every disability/RSI/AT claim in the spec and Reports 01/04/05/06; clinical-literature check on dysarthria and ASR; ethics review of the demo and pitch.

---

## Executive Summary

The accessibility wedge is real but narrower, and differently shaped, than the current documents claim. Three headline findings:

1. **The strongest provable wedge is not "all motor disabilities" — it is *upper-limb limitation with clear speech*.** Roughly half or more of people with cerebral palsy have dysarthria (50–90%); 52% of stroke survivors have dysarthria; ~90% of people with Parkinson's experience speech changes; and severe dysarthria still causes >51% word-error rates even in the best 2025 commercial ASR systems. A speech-only product that claims to serve "motor disability" as a whole will exclude many of the users it claims to serve. This must become an explicit, honest scope boundary ("voice-first, not voice-only"), with fallback channels.
2. **Two integrity problems must be fixed before any judge sees the deck.** (a) Report 04 attributes a specific quote to a named real person (Pranav Nair) via an Indian Express URL that 404s; the quote does not appear in the real interview article. (b) Report 06's demo says "Meet Rahul. He has cerebral palsy" — a fabricated persona presented as fact. Both are exactly the kind of thing an accessibility-literate judge (or a disabled audience member) will catch, and both contradict "nothing about us without us."
3. **Most of the hard data survives verification, with caveats.** Census 2011 (5.44M movement disability), NSS 76th (2.2% prevalence), GlassOuse ₹60,099, 52.2% PwD literacy (NSS 76th), 4.4%/23.4% computer ownership (NSS 75th) all check out. But the "31.1% CTS in software professionals" line misattributes a Kolhapur *bank computer-user* study; the Census and NSS numbers measure different things and are 7–15 years old; and India's national prevalence (2.2%) is far below WHO's global estimate (16%) because of narrow definitions — so the 5.43M figure is a floor, not "the market."

**Bottom line:** keep the accessibility mission, drop the universal claim, name the capability class precisely, relabel simulations honestly, add fallback interaction, and fix two integrity defects. The result is a stronger, judge-proof story: *independence and user control for people who can speak clearly and cannot comfortably use their hands* — with a stated roadmap for the rest.

---

## 1. Data Verification Ledger

| # | Claim (as used in spec/reports) | Verdict | Evidence / correction |
|---|---|---|---|
| 1 | Census 2011: 26.8M disabled; 5.44M "movement" disability; 20.3% of disabled population | **[VERIFIED]** | Census Table C-20: 54,36,604 movement disability; 20.3% share; 2.21% of population. [enabled.in](https://a11y.enabled.in/census-of-india-2011-disabled-population/), [PLOS One analysis](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0159809) |
| 2 | NSS 76th Round (2018): overall disability prevalence 2.2%; locomotor most prevalent at 1.4% | **[VERIFIED — overall 2.2%]**; **[PARTIAL — 1.4% locomotor]** | MoSPI Press Note / Report 583 confirms 2.2% (2.3% rural, 2.0% urban). The 1.4% locomotor figure is consistently reported by secondary sources but should be re-extracted from Report 583 Statement 3 before it goes on a slide. [MoSPI](https://www.mospi.gov.in/sites/default/files/press_release/Press%2BNote_Report%20No%20583%20DISABILITTY_76%20_Final.pdf) |
| 3 | "5.43M locomotor-disabled citizens per Census 2011 / NSS 76th Round" (spec §1.2) | **[CONFLATED — fix]** | Census *counts* 5.44M people; NSS *extrapolates* 1.4% of a larger 2018 population (~18–19M). Different instruments, definitions, years. Do not write one figure "per" both sources. Also: locomotor disability includes lower-limb/mobility impairments that do not impede desktop use — it is context, not the addressable base. |
| 4 | Addressable base of desktop-using motor-impaired Indians ≈ 250k–450k | **[INFERENCE — method not shown]** | Keep, but label as an estimate and show the arithmetic (urban computer ownership × locomotor prevalence × desktop share × etc.), or drop the number. NSS 75th: only 4.4% of rural and 23.4% of urban households had a computer; PwD literacy 52.2% (NSS 76th) vs ~80% national. [PIB NSS 75th](https://www.pib.gov.in/Pressreleaseshare.aspx?PRID=1593251), [PIB NSS 76th](https://www.pib.gov.in/PressReleasePage.aspx?PRID=1593253) |
| 5 | India national disability prevalence vs global | **[VERIFIED — and a caveat]** | WHO (2023): ~1.3B people (16%) globally; India's own instruments say 2.2%. The gap reflects India's narrow medical-model questions and self-report stigma, not a lower rate. [WHO](https://www.who.int/news-room/fact-sheets/detail/disability-and-health). Census 2027 will include disability (Q13), but rights groups already flag gaps; data remains contested until then. [The Hindu](https://www.thehindu.com/news/national/disability-rights-groups-flag-gaps-in-proposed-census-2027-categories/article71364696.ece) |
| 6 | "34–74% of Indian software workers report work-related musculoskeletal strain" | **[VERIFIED — as symptom range]** | Mani 2022 (Chennai, n=152): 74.3% musculoskeletal *symptoms*; Panchal 2020 (Ahmedabad IT): 66.8% MSD; a literature review reports ~74% overall, with 34% in at least one cited study. Phrase as "report symptoms," never "have RSI." [J. Comprehensive Health — Mani](https://journalofcomprehensivehealth.co.in/work-related-morbidity-profile-among-software-professionals-in-chennai-tamil-nadu-a-pre-pandemic-cross-sectional-study/), [Panchal](https://journalofcomprehensivehealth.co.in/prevalence-and-determinants-of-musculoskeletal-disorders-among-information-technology-sector-employees-of-ahmedabad-gujarat/) |
| 7 | "31.1% testing positive for clinical signs of CTS" among Indian software professionals | **[MISATTRIBUTED — fix]** | The 31.10% figure is from a study of computer users **in banks of Kolhapur city** (2022), not software professionals; the classic Chennai software-professional study (Ali & Sathiyasekaran, 2006) found **13.1%** CTS. [JEOH Kolhapur study](https://www.informaticsjournals.co.in/index.php/JEOH/article/download/45596/32159/103507), [PubMed Ali 2006](https://pubmed.ncbi.nlm.nih.gov/16984790/) |
| 8 | GlassOuse V1.4 ≈ ₹60,099; switches extra | **[VERIFIED]** | RehaKart India: V1.4 ₹60,099; PRO ₹79,399; bite switch ₹7,375; puff ₹14,799; cheek ₹9,999. [RehaKart](https://rehakart.in/products/glassouse-v1-4) |
| 9 | Tobii consumer ₹39,499–58,000; clinical Dynavox ₹2–7L+ | **[PARTIAL]** | Consumer Eye Tracker 5 listed ~₹45,999 (IndiaMART). PCEye 5 UK £1,995–2,440 (~₹2.1–2.6L); India AAC bundles require dealer quotes, so ₹2–7L is plausible but should be "dealer-quoted." [IndiaMART](https://www.indiamart.com/proddetail/tobii-eye-tracker-5-2855387501473.html) |
| 10 | Apple Voice Control has no Hindi/Marathi | **[VERIFIED — narrowly]** | Apple's own list (Dec 2025): Arabic (SA), Cantonese, English (AU/CA/**India**/SG/UK/US), French, German, Italian, Japanese, Korean, Mandarin, Russian, Spanish, Turkish — no Hindi, no Marathi *for navigation commands*. Notably, Apple **Dictation/Speak** supports Hindi and Marathi for text, and "Listen for atypical speech" exists but is **U.S. English only**. Claims must say "command navigation," not "all voice." [Apple accessibility features footnote 18](https://support.apple.com/en-sa/121825), [Apple speech features](https://support.apple.com/en-in/guide/mac-help/mchl6972f04a/mac) |
| 11 | "Dragon discontinued on macOS since 2018" | **[VERIFIED — as reported]** | Consistent with Nuance's macOS retirement; keep as-is, cite Nuance. |
| 12 | PwD literacy 52.2% | **[VERIFIED]** | NSS 76th (age 7+). Do not mix with Census 2011's 54.5% literacy figure; they are different instruments. |
| 13 | Report 04 quote attributed to Pranav Nair | **[REMOVE — unverifiable/fabricated]** | Cited URL `...8037302/` returns **404**; the real PTI/Indian Express article (ID 9167890) does not contain the quote or its "scribes/interfaces" sentiment. Never quote a real person without a live source and, ideally, consent. [Real article](https://indianexpress.com/article/education/cerebral-palsy-affected-iit-guwahati-students-dream-placement-in-google-9167890/) |
| 14 | Report 04's "IT professional with severe RSI" quote | **[REMOVE]** | A synthesized quote in quotation marks is not a quote. Label illustrative composites as composites, outside quote marks. |

**Data-deck rule:** every number on a slide carries one of `[Census 2011]`, `[NSS 76th, 2018]`, `[peer-reviewed study, n]`, or `[our estimate, method]`. Mixed provenance is how hackathon claims die in Q&A.

---

## 2. Persona Analysis — Who Can Actually Use Clicky

### 2.1 The speech caveat (the finding that changes the wedge)

Voice-first interaction presumes *intelligible speech*. Motor impairment and speech impairment co-occur far more than the current documents acknowledge:

- **Cerebral palsy:** 50–90% have dysarthria (mild to severe). [CP Resource](https://cpresource.org/topic/communication/dysarthria-and-cerebral-palsy-fact-sheet); Mei et al. 2020 estimate 33–63% have speech difficulty; ASHA-cited work reports up to 78%. [Mei 2020](https://www.ovid.com/journals/dmcn/fulltext/10.1111/dmcn.14592~speech-in-children-with-cerebral-palsy)
- **Stroke:** 52% of survivors have dysarthria (28% together with aphasia, 24% dysarthria only); 12% more have aphasia only — i.e., ~64% have a communication impairment. Both dysarthria and aphasia break naive voice-first design. [Mitchell et al. 2021](https://www.tandfonline.com/doi/full/10.1080/02687038.2020.1759772)
- **Parkinson's disease:** ~90% develop hypokinetic dysarthria (reduced loudness, monotone, accelerating rate). [Atalar & Oguz 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC10600629/)
- **ASR reality (2025 benchmark):** mild dysarthria now reaches 1–2% WER in leading commercial systems, but **severe dysarthria exceeds 51% WER in every system tested**; Gemini Live has not been validated on dysarthric Hindi/Marathi. [Alsayegh et al. 2025](https://arxiv.org/abs/2512.17474)
- **Counter-trend:** the cross-industry Speech Accessibility Project (Amazon, Apple, Google, Meta, Microsoft; 500+ speakers, 400+ hours) is actively improving dysarthric ASR — so "not yet" is the honest word, not "never." [SAP](https://speechaccessibilityproject.beckman.illinois.edu/)

**Implication:** Clicky's claim must be capability-based, not label-based. You are not building "for all motor disabilities"; you are building for people who **can speak and cannot comfortably use their hands** — and you will design and state what happens for everyone else.

### 2.2 Sub-segment suitability (honest)

| Sub-segment | Speech | Voice-first fit | Notes for the pitch |
|---|---|---|---|
| RSI/CTS (moderate–severe) | Unaffected | **High** | Largest recruit-able cohort; Pune IT corridor; not a disability under RPwD Act — frame as occupational-injury/productivity, never as the face of disability |
| One-handed / upper-limb reduction (amputation, brachial plexus injury, hemiparesis) | Unaffected | **High** | Strong accessibility story; often underdocumented needs |
| Spinal cord injury (paraplegia; tetraplegia with preserved bulbar speech) | Usually preserved | **High** | macOS Dragon gap since 2018 is a real, specific pain; some already use head/eye switches — position Clicky as a complement |
| Post-stroke, **clear speech** (no aphasia/dysarthria) | Preserved in ~36% | **Medium–High** | Vet for fatigue, attention, timeouts; do not recruit from the 64% with communication impairment for a voice demo |
| Cerebral palsy with intelligible speech | Variable | **Medium** | Heterogeneous; always test per person; never present CP as uniformly voice-served |
| Mild dysarthria | Reduced intelligibility | **Medium — research target** | Test explicitly; report per-speaker WER; do not claim reliability until measured |
| Moderate dysarthria | Reduced | **Low–Medium** | Personalization/ASR work needed; likely needs the fallback channel as primary |
| **Severe dysarthria** | Severely reduced | **Excluded today** | >51% WER; state openly |
| **Anarthria / non-speaking** (locked-in, late ALS, some CP) | Absent | **Excluded today** | Needs eye-gaze/switch/AAC; Clicky has no path yet |
| **Aphasia** (with/without dysarthria) | Language formulation/comprehension impaired | **Excluded today** | Natural-language command model itself fails |
| Deaf/hard-of-hearing + motor impairment | — | **Excluded today** | Audio-first responses and spoken confirmations must become text/visual first |
| Cognitive disability + motor | — | **Unexplored** | Timeout/confirm burden untested |

### 2.3 Recommended personas

**PRIMARY PERSONA — "The clear-speech, upper-limb-limited Mac user."**  
Inclusion criteria (all three): (1) substantial pain/difficulty using a mouse/trackpad for sustained work, or cannot use hands; (2) speech intelligible to unfamiliar listeners for command-length utterances (quick self-report + a 2-minute live probe at first run); (3) uses macOS for work or study. Priority sub-cohorts for validation: **RSI/CTS in Pune IT**, then one-handed users, SCI, CP with clear speech, post-stroke with clear speech. This is provable in Pune, matches macOS share reality, and every capability claim can be tested with the people present.

**SECONDARY PERSONA — "Mild-to-moderate dysarthria, testing only."** Recruit 1–2 participants explicitly to *measure failure*, with informed consent that reliability is unproven. Report WER, task success, and fallback usage honestly. This becomes the roadmap's evidence base, not the demo's hero.

**SECONDARY PERSONA — "Assisted setup / shared household."** Many users will have a family member or assistant install software and grant permissions. Support an explicit, privacy-scoped "helper mode" (permissions page, headphone check, first run) rather than pretending setup is hands-free.

**EXPLICIT NON-GOALS (state on the slide):** severe dysarthria; anarthria; aphasia; deaf + motor impairment (until visual/confirmation-text mode ships); users without a Mac, reliable power, or connectivity. "Voice-first, not voice-only" goes in §1 of the spec.

### 2.4 Fallback interaction for unclear speech (recommended, cheap)

1. **Text command box** in the menu bar (Full Keyboard Access + VoiceOver-labelled): type the command, same executor, same risk gate. This is the single highest-value addition to the product.
2. **On-screen confirmation controls** as first-class AX elements (pressable by macOS Switch Control, keyboard, or a pointer), not just "say the phrase."
3. **Adaptive-switch start/stop:** expose Start/Stop and Push-to-Talk as focusable controls so a USB/Bluetooth switch (e.g., GlassOuse G-Switch, foot pedal) can drive the session — a real hands-free path that doesn't require the cloud to be listening.
4. **Caretaker/assistant mode** for setup and emergencies, with explicit scope and an audit record; never silent access.
5. **Auto-repeat / rephrase loop:** if ASR confidence is low twice, drop to the text box and say so. Do not guess.

---

## 3. Interaction Design — What "True Hands-Free" Requires

### 3.1 Wake activation (pick honestly, expose all options)

| Option | Hands-free? | Privacy/cost | Recommendation |
|---|---|---|---|
| Always-listening cloud stream | Yes | Poor: continuous audio to Google; DPDP/consent exposure; false triggers | **No as default.** Opt-in only, with visible mic state and zero retention. |
| Push-to-talk hotkey (Cmd+Shift+Space, etc.) | No (needs a keypress) | Best: mic on only while held | **Default**, but remappable to a switch/foot pedal; must not be the *only* path. |
| On-device wake word ("Clicky") | Yes | Good: audio never leaves the Mac when idle | **Recommended stretch**; needs enrollment for atypical/Indic accents; ship a fallback. |
| System activation: "Hey Siri" + Shortcuts/App Intents ("start Clicky") | Yes | Uses Siri's existing wake path; no new always-on pipeline | **Recommended quick win**; document latency (~1–2 s). |
| Switch / dwell activation through our own UI | Yes | Local | **Required for parity** (see §2.4). |

**Design rule:** the microphone is idle unless (a) the user activated a session by voice/switch/hotkey, or (b) the user explicitly enabled always-listening. Show a persistent mic indicator and a one-utterance "listening" state. Sessions auto-sleep after 30–60 s of silence; speaking resumes them without a new wake phrase.

### 3.2 Confirmation misrecognition — short affirmatives are the weakest link

"Haan", "Ho", "Go", and "Yes" are short, phonetically confusable with their negatives ("nahi/nako/no"), extremely common as filler in Hinglish/Marathi conversation, and likely to appear in TV/background speech. Risk is asymmetric: a false accept on Tier 3–4 is catastrophic; a false reject is an annoyance. The current spec's bare "Say Go / Haan" default should change.

**Fix set (all cheap, all local):**
1. **Action-specific confirmation phrases.** The user must echo the action + object: *"Haan, Trash karo"* / *"होय, ट्रॅश करा"* / *"Yes, Trash it"*. For money: read back payee + amount; require the amount echoed back, ideally digit-by-digit (*"Confirm five-zero-zero"*). Dynamic echo beats static "Go" because background audio will not coincidentally say the target's name.
2. **Negation-first policy.** Any negation token within the window ("nahi", "nako", "no", "ruko", "thamba", "cancel", "stop") cancels immediately and outranks any affirmative; on ambiguity, cancel. Never fuzzy-match a positive when a negative was detected anywhere in the utterance.
3. **Single-shot, bounded window.** Open the confirmation window only *after* the read-back; accept one utterance; then close. Speech onset extends the window.
4. **Timeout adjustable, not 5 s fixed.** Default 10–15 s, configurable 5–60 s, with a visible countdown and a "wait" phrase that extends it. The fixed 5 s gate also violates the WCAG 2.2.1 "Timing Adjustable" principle for users who need more time. [WCAG 2.2.1](https://www.w3.org/WAI/WCAG22/Understanding/timing-adjustable.html)
5. **Local kill phrase, always armed.** "Ruko" / "थांब" / "Stop" is detected on-device (VAD + keyword) even if the network is down, and even while Clicky is speaking; it cancels the queue and shows the green "Stopped" banner. The hardware hotkey remains as an optional secondary channel — not the primary one, because the target user may not be able to press it.
6. **Background-speech handling.** Gate commands to the active session; if two speaker voices are detected or system audio is loud, suspect the environment, cancel the pending action, and ask the user to repeat. Recommend headphones during vision/audio sessions; verify the AEC leak path in Spike 2. Optional voice-profile enrollment (roadmap) for shared rooms.
7. **Replay/spoof awareness.** A video or phone call saying *"Haan, confirm"* must not send money. Dynamic challenge phrases + freshness + rate limits raise the bar; do not claim security-grade authentication. Log every confirmation attempt.
8. **Say what will actually happen.** If deletions route to Trash, the read-back says *"Trash mein bhej doon? Baad mein wapas la sakte hain"* — never "hamesha ke liye delete" (the current demo script contradicts the architecture's own reversible-delete design).

### 3.3 Other hands-free realities to document

- **First run is not hands-free.** macOS TCC dialogs (Accessibility, Screen Recording, Microphone) need a human. Ship an explicit "assisted setup" flow; say so in the deck.
- **Secure Input fallback already yields control back** (spec §4.2.6) — keep; localize the spoken notice.
- **Capability parity for our own UI:** the overlay and any confirmation UI must be keyboard/switch/VoiceOver reachable with AX labels, and must not rely on color alone (amber/red need icons/labels), per WCAG and RPwD-aligned design.
- **Captions/text echo of all spoken prompts** for deaf/hard-of-hearing users and noisy rooms — a small addition that widens the audience and passes "universal design" questions.
- **Pause semantics:** "stop listening" must be a visible, persistent state, with a one-action resume.

---

## 4. Validation Plan — Pune, 5–7 Questions, Artifacts, Consent

### 4.1 Where to find real users (recruit through organizations, not cold DMs)

- **University cells:** SPPU's new PwD cell / Equal Opportunity Cell (SPPU announced dedicated PwD assistance cells) [TOI](https://timesofindia.indiatimes.com/city/pune/sppu-to-start-two-new-assistance-cells-for-students/articleshow/107979548.cms); host campus **PCCOE&R** EOC; COEP, Fergusson, MIT-WPU EOCs.
- **Rehab/clinical partners (Pune):** **Muktangan Rehabilitation Center**, Yerawada (CP/motor, adults and children) [muktangan.org](https://www.muktangan.org/contact-us/); **Sancheti Institute** (CP/neuro rehab) [sanchetihospital.org](https://sanchetihospital.org/specialities/neurology-department/cerebral-palsy/); **KEM Hospital Pune** — TDH Rehabilitation & Morris Child Development Centre [KEM](https://www.facebook.com/kempune/posts/1325437786277225/).
- **National DPOs/employment orgs:** **EnAble India** (works across the 21 RPwD disabilities; employment@enableindia.org) [EnAble India](https://www.enableindia.org/livelihood/wage-employment/); **NCPEDP** for advocacy-network referrals; **Atypical Advantage / v-shesh / Youth4Jobs** for employed PwD talent networks.
- **Expert reviewers:** Assistech Lab (IIT Delhi), TISS Mumbai Centre for Disability Studies and Action, occupational therapists at the rehab partners.
- **RSI cohort:** IT employers' DEI/ERG and occupational-health programs in Pune's tech corridor (Persistent, Infosys, TCS, Wipro, etc.) — the fastest route to the largest sub-cohort.
- **Realism check:** with 30 hours, expect 3–5 interviews; prioritize 2 primary-persona users, 1 mild-dysarthria tester, and 1 expert (OT/accessibility trainer). If a Mac-owning motor-impaired user is unavailable, say so in the deck and use the expert + RSI users honestly — never fake a participant.

### 4.2 Seven interview questions (open-ended, non-leading; ask for stories, not opinions)

1. "Walk me through a recent work/school day on your Mac — which moments demanded the most hand or arm effort, and what did you do instead?"
2. "What have you tried for those moments (Voice Control, dictation, Talon, Dwell, switches, help from a person)? What worked, what did you abandon, and why?"
3. "When you talk to a computer, how do you actually phrase things — English, Hindi, Marathi, mixed? Give me an example from last week." (Ask for their real phrasing; record it.)
4. "Who sets up software and permissions on this Mac — you, or someone else?" (setup reality)
5. "If a cursor previewed where it would click and asked you to confirm first, what would make you trust it? What would make you close the app for good?" (trust, not reassurance-seeking)
6. "What should happen when it mishears you, or when a TV or another person in the room is talking?" (background speech; ambiguity behavior)
7. "What would make this worth using every week — and what would make you stop using it after a week?" (adoption and failure modes)

*Avoid the current report's "would that give you confidence?" question — it invites a polite yes. Ask what would break trust instead.*

### 4.3 Artifacts to collect for the PPT

- **Consent + release form** (per participant; English/Hindi/Marathi; separate checkboxes for face, voice, screen, quote attribution).
- **3–5 quote cards** — first name (or anonymous), role, capability (not diagnosis), their own words, verified against the recording.
- **2 × 45–90 s video clips**: (a) user completes a real task; (b) the **false-accept test** — TV/phone audio saying "haan/go" while Clicky refuses to act.
- **Task-timing sheet**: task, tool (Voice Control vs Clicky), time, errors, pain/effort rating (simple 1–5), hands-free path used.
- **"What failed" notes** — one honesty slide builds more trust than four polished ones, and preempts the hard judge question.
- **Credits/acknowledgements** slide: organizations and participants (with permission).

### 4.4 Consent, privacy, and dignity (DPDP-aligned, and then some)

- Written informed consent in plain language; explain what is recorded, where it lives, who sees it, when it is deleted, and how to withdraw (must be as easy as opting in).
- Separate opt-ins for face, voice, screen contents; offer anonymization (voice pitch scrub, blurred face, hands-only framing). Never film medical equipment, therapy rooms, or private spaces.
- Use demo accounts and synthetic files on screen — no real email, financial, or medical content.
- Fair compensation for time/consulting expertise (reimburse travel + honorarium), plus a copy/credit of the output if they want it.
- Give participants **review rights** over their clip before submission; no surprise cuts. Do not call anyone "inspiring" or "suffering."
- Do not disclose diagnoses in captions unless the participant explicitly asks; lead with capability and goals.
- Delete raw recordings after the event unless renewal is agreed; keep consent forms securely; no training on their data.
- Consultation basis: UN CRPD Art. 4.3 ("nothing about us without us") and RPwD Act 2016 principles — involve users in design, not only in the demo.

---

## 5. Two-Minute Demo Storyline (respectful, specific, low-latency)

**Casting rule:** a real consenting user delivers the demo; if impossible, the teammate must open with a plainly labeled simulation: *"This is a teammate simulating restricted hand use. It is not a simulation of disability, and we say that plainly."* Never invent a persona ("Meet Rahul…"). Never film frustration for drama.

| Time | Beat | Action / exact commands (EN · HI · MR) |
|---|---|---|
| 0:00–0:15 | **Who, not what** | User (or labeled narrator): "I use a Mac for work. Holding a mouse hurts after a few minutes. Clicky lets me keep my hands for what matters and use my voice for the rest." No pity framing; no "overcoming." |
| 0:15–0:45 | **Everyday flow** | *EN:* "Clicky, open Safari and search Pune weather." · *HI:* "क्लिकी, सफ़ारी खोलो और पुणे का मौसम खोजो।" · *MR:* "क्लिकी, सफारी उघड आणि पुण्याचे हवामान शोध." Cursor glides; spoken read-back; latency meter <1 s. |
| 0:45–1:15 | **Multi-step, language mix** | *HI:* "इस पेज का पहला लिंक खोलो और मेरे नोट्स में सेव कर दो।" · *MR:* "या पानावरील पहिली लिंक उघड आणि माझ्या नोट्समध्ये सेव्ह कर." Shows chaining + AX-first: "0 screen images sent." |
| 1:15–1:45 | **Control & safety (the real wow)** | *EN:* "Clicky, move this duplicate to Trash." · Clicky: "Duplicate-Report.pdf — Trash?" *(correct reversible wording)* · *HI:* "हाँ, ट्रैश करो।" · *MR:* "होय, ट्रॅश करा." Then the veto: *"नहीं, रुको!"* / "नको, थांब!" / "No, stop." → cursor freezes, green **Stopped** banner. Then the pivot: "इसका नाम 'Report-final' कर दो." |
| 1:45–2:00 | **Closer** | One sentence of architecture honesty ("AX-first, so most actions cost nothing and send no pixels; vision only when it must"), one user sentence, and the scope line: "Voice-first — and building the fallbacks for people who can't speak clearly, with the Speech Accessibility Project generation of models." |

**Production rules:** subtitles for Hindi/Marathi; sanitized screen; headphones; one dry run *with the actual user* before the event; stop on fatigue; a consented recording as backup (never play a fake "live" clip).

---

## 6. Ethics and Integrity Risks in the Current Spec/Reports — with Fixes

| # | Risk (where) | Why it matters | Fix |
|---|---|---|---|
| 1 | **Fabricated quote/citation** (Report 04 §2.3, Pranav Nair; 404 link) | Dishonesty caught by any fact-check; uses a real person without consent | Delete; replace with consented quotes; audit all report citations (404s/derived claims) before any slide |
| 2 | **Fake persona "Rahul has cerebral palsy"** (Report 06 §7A) | Presenting fiction as biography is "inspiration porn" and false | Use a real user or a clearly labeled simulation of *constraint only* |
| 3 | **"For all motor disabilities" overclaim** (spec §1, Report 06 Slide 1: "for 5.4M motor-impaired Indians") | Excludes dysarthria/anarthria/aphasia users by design; judges may ask | Capability-based scope statement + non-goals + fallback roadmap |
| 4 | **Speech-difference silence** (throughout) | The most ethically exposed gap: claiming accessibility while excluding the most speech-affected | Add "voice-first, not voice-only"; text box + switch/on-screen confirm; mild-dysarthria test cohort |
| 5 | **Mixed data provenance** (5.43M "per" two sources; 31.1% misattribution) | Overstated evidence undermines the whole deck | Use §1 corrections; one provenance label per number |
| 6 | **Our own UI accessibility** (5 s fixed timeout; color-coded states; no captions) | A disability product must pass basic accessibility itself | Timing adjustable; icons + labels; text echo of speech; keyboard/Switch Control/VoiceOver-operable confirmation and overlay |
| 7 | **Deletion narration contradicts reversible design** (spec §6 vs T09/Trash) | Scare copy erodes trust when users learn files are recoverable | Say "Trash — recoverable later" |
| 8 | **Bare "Go/Haan/Ho" confirmations + bystander/replay** (spec §4.4) | False accepts on irreversible actions; TV/phone can trigger | Dynamic action-specific echo; negation-first; bounded window; local kill; background-speech test; document limits |
| 9 | **Kill switch defaults to a hardware hotkey** (spec §4.4) | Target users may be unable to press it | Voice kill (local) primary; switch input; hotkey optional |
| 10 | **Privacy of always-on/cloud audio** | DPDP consent, purpose limitation, bystanders' voices | Local wake word option, mic-state indicator, zero retention, trilingual notice, deletion path, opt-in only |
| 11 | **Financial-tier demo** | Real money + vulnerable users = unacceptable | Sandbox only (already in spec §8.5 — keep); explicit "SIMULATION" label; never real accounts |
| 12 | **Inconsistent cost claims** (₹0.52 vs ₹2–3.50 vs $0.002 per task) | Judges cross-check; gets read as unscientific | One cost model, one units table, measured live |
| 13 | **"Simulated one-handed" benchmark** (§7) | Restraining a hand is a constraint proxy, not disability | Label as proxy; state the limits; add real-user data or mark provisional |
| 14 | **Savior/pity language** ("suffering from", "giving hands-free computing to", "wheelchair-bound") | Alienates disabled judges/users; violates respectful framing | Person-first, neutral, agency-based language; user controls the machine — Clicky never "gives" anything |
| 15 | **Benefit overclaim** ("reduces RSI") | Not a medical device; no evidence | Say "reduces reliance on mouse/trackpad"; never therapeutic claims |
| 16 | **No co-design involvement** | Consultation is a rights principle, not a courtesy | At least one participant reviews the demo script/product before judging; credit them |

---

## 7. Recommendations (Priority-Ordered)

**P0 — before Round 1 PPT (hours, not days):**
1. Remove the Nair quote and the fabricated RSI quote; replace Report 06's "Rahul" with an honest simulation label.
2. Rewrite the user scope: *"For people with limited or painful hand/arm use and clear speech — built voice-first, adding text/switch fallbacks; not yet for severe dysarthria, anarthria, or aphasia."*
3. Apply the §1 corrections (31.1% attribution; Census/NSS separation; "symptoms, not RSI").
4. Change the confirmation design: action-specific echo phrases, negation-first, adjustable timeout; update the demo line from "permanently deleted" to Trash.
5. Unify the three conflicting per-task cost figures into one measured model.

**P1 — before Round 2 demo (build + validation):**
6. Ship the text-command fallback and keyboard/switch-accessible confirmation UI; make timeouts configurable.
7. Implement the local voice kill phrase; keep the hotkey optional.
8. Run the background-speech false-accept test: loop Hindi TV audio with "haan/go" for 10 minutes; zero confirms required.
9. Recruit via SPPU/PCCOE EOC, Muktangan, Sancheti, EnAble India; 2 primary-persona users + 1 mild-dysarthria tester + 1 OT/expert; consent kit + honorarium ready.
10. Collect the artifacts in §4.3, including a "what failed" slide.

**P2 — post-hackathon roadmap (say it on the slide):**
11. Dysarthria personalization (voice profile; on-device ASR options; SAP-informed models) with published per-speaker WER.
12. Speaker verification and visual-first mode for deaf/HoH + motor users; AAC/switch interoperability.
13. Windows (UIA) port — the majority-platform ethical requirement, not a nice-to-have.

**New accessibility exit criteria:** 0 unconfirmed destructive actions across 20 trials including 10 adversarial background-speech attempts; ≥1 real primary-persona user completes a 3-task session unaided after setup; timeout configurable and exercised; a switch/PTT-only path can start/stop a session; spoken prompts echoed in text.

---

### Source index (verification, October 2026)

Census 2011 disability tables — enabled.in / PLOS One; NSS 76th Round (MoSPI Report 583, PIB); NSS 75th Round (PIB); WHO disability fact sheet; Mani 2022 & Panchal 2020 (J. Comprehensive Health); Ali & Sathiyasekaran 2006 (PubMed); JEOH Kolhapur CTS study; RehaKart (GlassOuse India pricing); IndiaMART (Tobii Eye Tracker 5); Apple accessibility footnotes (Voice Control languages; speech features; atypical speech US-English only); Mitchell 2021 (stroke dysarthria); Atalar 2023 (Parkinson's); CP Resource / Mei 2020 (CP dysarthria); Alsayegh 2025 (dysarthria WER); Speech Accessibility Project; WCAG 2.2.1; UN CRPD Art. 4.3; DPDP Act 2023; The Hindu (Census 2027 disability gaps); TOI (SPPU PwD cell); Muktangan, Sancheti, KEM (Pune); EnAble India.
