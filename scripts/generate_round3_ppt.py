#!/usr/bin/env python3
"""
Generate CraftVerse 2.0 Evaluation Round 3 PowerPoint Presentation:
Clicky — Startup Go-To-Market, Marketing & Scaling Strategy.

Clones layout, color palette, typography, and visual assets from:
CraftVerse_KARTA_Accessibility.pptx
"""

import os
import shutil
import pptx
from pptx import Presentation
from pptx.util import Pt
from pptx.dml.color import RGBColor

SRC_PPTX = '/Users/pranav1296/clicky/CraftVerse_KARTA_Accessibility.pptx'
OUT_PPTX = '/Users/pranav1296/clicky/CraftVerse_Round3_Marketing_Scaling.pptx'

# Official Design Palette from CraftVerse_KARTA_Accessibility.pptx
NAVY = RGBColor(0x1F, 0x49, 0x7D)       # Primary Title / Lead-in bold
CHARCOAL = RGBColor(0x26, 0x26, 0x26)   # Body text
GRAY = RGBColor(0x59, 0x59, 0x59)       # Secondary / Meta info
AMBER = RGBColor(0x9C, 0x65, 0x00)      # Highlight headers / Accent
CRIMSON = RGBColor(0xC0, 0x50, 0x4D)    # Action / Warning / Q&A
WHITE = RGBColor(0xFF, 0xFF, 0xFF)      # Table headers / White cards

def clear_and_set_para(p, lead_in, body, lead_size=15.5, body_size=14.5, lead_color=NAVY, body_color=CHARCOAL, space_after=Pt(6)):
    p.text = ''
    p.space_after = space_after
    if lead_in:
        r1 = p.add_run()
        r1.text = lead_in + (' ' if lead_in.strip() else '')
        r1.font.name = 'Lucida Sans Unicode'
        r1.font.size = Pt(lead_size)
        r1.font.color.rgb = lead_color
        r1.font.bold = True
    if body:
        r2 = p.add_run()
        r2.text = body
        r2.font.name = 'Lucida Sans Unicode'
        r2.font.size = Pt(body_size)
        r2.font.color.rgb = body_color
        r2.font.bold = False

def clear_text_frame(tf):
    p_elements = tf._txBody.xpath('./a:p')
    for p_elem in p_elements[1:]:
        tf._txBody.remove(p_elem)
    p0 = tf.paragraphs[0]
    p0.text = ''
    return p0

def add_bullet(tf, lead_in, body, lead_size=15.5, body_size=14.5, lead_color=NAVY, body_color=CHARCOAL, space_after=Pt(6)):
    if len(tf.paragraphs) == 1 and tf.paragraphs[0].text == '':
        p = tf.paragraphs[0]
    else:
        p = tf.add_paragraph()
    clear_and_set_para(p, lead_in, body, lead_size, body_size, lead_color, body_color, space_after)
    return p

def get_shape(slide, name):
    matches = [s for s in slide.shapes if s.name == name]
    if not matches:
        raise ValueError(f"Shape '{name}' not found on slide")
    return matches[0]

def build_presentation():
    # Make a clean working copy
    shutil.copyfile(SRC_PPTX, OUT_PPTX)
    prs = Presentation(OUT_PPTX)

    # ==========================================
    # SLIDE 1: TITLE SLIDE
    # ==========================================
    s1 = prs.slides[0]
    tb2 = get_shape(s1, 'TextBox 2')
    tf = tb2.text_frame
    
    # P0: Main title
    p0 = tf.paragraphs[0]
    p0.text = ''
    r0 = p0.add_run()
    r0.text = "CLICKY — Voice-First AI Cursor for macOS"
    r0.font.name = 'Trebuchet MS'
    r0.font.size = Pt(36)
    r0.font.color.rgb = NAVY
    r0.font.bold = True
    
    # P1: Subtitle
    p1 = tf.paragraphs[1]
    p1.text = ''
    r1 = p1.add_run()
    r1.text = "Startup Go-To-Market, Marketing & Scaling Strategy"
    r1.font.name = 'Lucida Sans Unicode'
    r1.font.size = Pt(20)
    r1.font.color.rgb = CHARCOAL
    r1.font.bold = True
    
    # P2: Metadata
    p2 = tf.paragraphs[2]
    p2.text = ''
    r2 = p2.add_run()
    r2.text = "Evaluation Round 3 (Business & Scaling)  ·  Team: Arc Agents  ·  PCCOE&R Pune"
    r2.font.name = 'Lucida Sans Unicode'
    r2.font.size = Pt(15)
    r2.font.color.rgb = GRAY
    r2.font.bold = True

    # P3: Vision tagline
    p3 = tf.paragraphs[3]
    p3.text = ''
    r3 = p3.add_run()
    r3.text = "Wedge: Accessibility Beachhead  →  Platform: Universal Voice Computing Input Layer"
    r3.font.name = 'Lucida Sans Unicode'
    r3.font.size = Pt(14)
    r3.font.color.rgb = NAVY
    r3.font.bold = True

    # ==========================================
    # SLIDE 2: PROBLEM STATEMENT & STRATEGIC POSITIONING
    # ==========================================
    s2 = prs.slides[1]
    
    # Header title
    obj6 = get_shape(s2, 'object 6')
    p = obj6.text_frame.paragraphs[0]
    p.text = ''
    r = p.add_run()
    r.text = "CLICKY — Voice-First AI Cursor for macOS"
    r.font.name = 'Arial'
    r.font.size = Pt(44)
    r.font.color.rgb = NAVY
    r.font.bold = True

    # Meta details
    obj8 = get_shape(s2, 'object 8')
    tf = obj8.text_frame
    details = [
        ("Problem Statement Title :", " Commercializing Voice-First Shared-Control for Personal Computing"),
        ("Domain :", " Artificial Intelligence & Agentic AI (Track)"),
        ("Team Name :", " Arc Agents"),
        ("Team Members & Size :", " 2 members"),
        ("College Name :", " Pimpri Chinchwad College of Engineering & Research (PCCOE&R), Pune")
    ]
    for idx, (lbl, val) in enumerate(details):
        p = tf.paragraphs[idx]
        p.text = ''
        r_lbl = p.add_run()
        r_lbl.text = lbl
        r_lbl.font.name = 'Lucida Sans Unicode'
        r_lbl.font.size = Pt(21)
        r_lbl.font.bold = True
        r_lbl.font.color.rgb = NAVY
        r_val = p.add_run()
        r_val.text = val
        r_val.font.name = 'Lucida Sans Unicode'
        r_val.font.size = Pt(21)
        r_val.font.bold = False
        r_val.font.color.rgb = CHARCOAL

    # Disambiguation & Wedge Card
    rr20 = get_shape(s2, 'Rounded Rectangle 20')
    tf = rr20.text_frame
    # P0: Title
    p0 = tf.paragraphs[0]
    p0.text = ''
    r0 = p0.add_run()
    r0.text = "CATEGORY POSITIONING & COMMERCIAL WEDGE (SPEC §1 & VALIDATION 04)"
    r0.font.name = 'Lucida Sans Unicode'
    r0.font.size = Pt(13.5)
    r0.font.bold = True
    r0.font.color.rgb = NAVY

    # P1: Name Disambiguation
    p1 = tf.paragraphs[1]
    clear_and_set_para(p1, "Name Disambiguation:", 
        "Unlike farzaa/clicky (pointer-only OSS toy) and heyclicky.com (English web-chat only), Clicky is the only voice-first shared-control cursor for macOS with full Indic (Hindi/Marathi) speech actuation and hardware safety.",
        lead_size=12.0, body_size=12.0, lead_color=NAVY, body_color=CHARCOAL, space_after=Pt(3))

    # P2: Commercial Wedge
    p2 = tf.paragraphs[2]
    clear_and_set_para(p2, "The Commercial Wedge:", 
        "India's 700k+ motor-impaired desktop users and 5.8M IT software workforce (34–74% RSI/CTS strain) form an urgent, high-willingness beachhead. We sell to institutions under regulatory compliance mandates, not cash-strapped individuals.",
        lead_size=12.0, body_size=12.0, lead_color=NAVY, body_color=CHARCOAL, space_after=Pt(2))

    # ==========================================
    # SLIDE 3: WHO PAYS: B2B PROCUREMENT & REGULATORY TAILWINDS
    # ==========================================
    s3 = prs.slides[2]
    
    # Title
    get_shape(s3, 'object 2').text_frame.paragraphs[0].text = "WHO PAYS & THE B2B PROCUREMENT WEDGE"
    get_shape(s3, 'object 2').text_frame.paragraphs[0].runs[0].font.name = 'Arial'
    get_shape(s3, 'object 2').text_frame.paragraphs[0].runs[0].font.size = Pt(38)
    get_shape(s3, 'object 2').text_frame.paragraphs[0].runs[0].font.color.rgb = NAVY

    # Section 1 Header & Content
    get_shape(s3, 'object 4').text_frame.paragraphs[0].text = "The Customer Trinity (User vs. Champion vs. Payer)"
    tf1 = get_shape(s3, 'TextBox 17').text_frame
    clear_text_frame(tf1)
    add_bullet(tf1, "The User (Clear Speech, Upper-Limb Limitation):", "Motor-impaired students/workers and RSI sufferers in India's ~5.4M IT workforce. The user experiences the daily pain but is rarely the direct payer in India.")
    add_bullet(tf1, "The Champion (Internal Advocate):", "Corporate DEI Leads, HR Accessibility Officers, and University Equal Opportunity Cell (EOC) Coordinators whose performance is judged on disability inclusion.")
    add_bullet(tf1, "The Payer (Budget Owner):", "Enterprise DEI/HR Accommodation budgets and University Student Welfare/EOC funds. Institutional budget lines exist today and are legally mandated.")

    # Section 2 Header & Content
    get_shape(s3, 'object 6').text_frame.paragraphs[0].text = "The ₹49,999 Pilot Wedge (Bypassing Slow Tender Cycles)"
    tf2 = get_shape(s3, 'TextBox 18').text_frame
    clear_text_frame(tf2)
    add_bullet(tf2, "Discretionary Approval Pricing:", "Priced at ₹49,999 for 10 seats / 6 months. This price point is engineered to sit directly below departmental manager discretionary sign-off thresholds.")
    add_bullet(tf2, "Zero Tender Delays:", "Allows an HR director or Dean/EOC coordinator to sign an LOI immediately without triggering a 9-month corporate procurement committee or government tender.")
    add_bullet(tf2, "Clear Conversion Ladder:", "A 6-month proof-of-value converts into an annual enterprise per-seat license (₹2,499/seat/mo) or campus-wide university site license.")

    # Section 3 Header & Content
    get_shape(s3, 'object 8').text_frame.paragraphs[0].text = "Urgent Regulatory Mandates Driving Institutional Demand"
    tf3 = get_shape(s3, 'TextBox 19').text_frame
    clear_text_frame(tf3)
    add_bullet(tf3, "SEBI Accessibility Mandate (Extended to 31 Oct 2026):", "Regulated financial/corporate entities are legally required to audit & remediate digital accessibility; RFPs require mandatory accessibility accommodation clauses.")
    add_bullet(tf3, "UGC National Directives (Sept 2026):", "All Higher Education Institutes (HEIs) directed to enforce RPwD Act §32, activate Equal Opportunity Cells, and fund assistive technology for enrolled students.")
    add_bullet(tf3, "Supreme Court & RPwD Enforcement:", "Digital access affirmed as a fundamental right (Apr 2025); 155 organizations penalized in Feb 2025 for RPwD non-compliance, creating urgent board-level compliance demand.")

    # ==========================================
    # SLIDE 4: 90-DAY MARKETING & CUSTOMER ACQUISITION PLAYBOOK
    # ==========================================
    s4 = prs.slides[3]
    
    # Title
    get_shape(s4, 'object 2').text_frame.paragraphs[0].text = "90-DAY MARKETING & CUSTOMER ACQUISITION PLAYBOOK"
    get_shape(s4, 'object 2').text_frame.paragraphs[0].runs[0].font.name = 'Arial'
    get_shape(s4, 'object 2').text_frame.paragraphs[0].runs[0].font.size = Pt(38)
    get_shape(s4, 'object 2').text_frame.paragraphs[0].runs[0].font.color.rgb = NAVY

    # Section 1 Header & Content
    get_shape(s4, 'object 4').text_frame.paragraphs[0].text = "Target Audience & Local Beachhead (Pune First)"
    tf1 = get_shape(s4, 'TextBox 17').text_frame
    clear_text_frame(tf1)
    add_bullet(tf1, "Target 90-Day Milestone:", "100 activated users, 60 weekly-active users (WAU), 25 paying seats, and 1 paid institutional pilot (10 seats) in Pune at <₹15,000 total CAC.")
    add_bullet(tf1, "Host Campus Beachhead:", "Immediate pilot deployment via Equal Opportunity Cells at PCCOE & PCCOER (zero-CAC testing and user validation with engineering students).")
    add_bullet(tf1, "Pune IT Hub Outreach:", "Direct engagement with Hinjawadi & Magarpatta tech employers (Persistent Systems, Tech Mahindra Foundation, Zensar) using warm hackathon connections.")

    # Section 2 Header & Content (Process Cards)
    get_shape(s4, 'object 6').text_frame.paragraphs[0].text = "Customer Acquisition Funnel & Distribution Engine"
    
    # 6 Funnel Boxes
    boxes = [
        ('Rounded Rectangle 18', "1. CAMPUS EOCs", "PCCOE, COEP, SPPU", "Zero-CAC student pilot"),
        ('Rounded Rectangle 20', "2. CLINIC REFERRALS", "Ortho & Physio clinics", "IT RSI patients"),
        ('Rounded Rectangle 22', "3. VIRAL DEMOS", "Hindi/Marathi video", "LinkedIn & X reach"),
        ('Rounded Rectangle 24', "4. PILOT LOIs", "₹49,999 / 10 seats", "Employer/HEI sign-off"),
        ('Rounded Rectangle 26', "5. ACTIVE RETENTION", "60 WAU / Telemetry", "AX speed & trust"),
        ('Rounded Rectangle 28', "6. ANNUAL RENEWAL", "Enterprise Contracts", "₹2,499/seat/mo ARR")
    ]
    for b_name, line1, line2, line3 in boxes:
        sh = get_shape(s4, b_name)
        tf = sh.text_frame
        p0 = tf.paragraphs[0]
        p0.text = line1
        p0.runs[0].font.name = 'Lucida Sans Unicode'
        p0.runs[0].font.size = Pt(11.5)
        p0.runs[0].font.bold = True
        p0.runs[0].font.color.rgb = WHITE
        
        p1 = tf.paragraphs[1]
        p1.text = line2
        p1.runs[0].font.name = 'Lucida Sans Unicode'
        p1.runs[0].font.size = Pt(10.0)
        p1.runs[0].font.color.rgb = WHITE
        
        p2 = tf.paragraphs[2]
        p2.text = line3
        p2.runs[0].font.name = 'Lucida Sans Unicode'
        p2.runs[0].font.size = Pt(9.5)
        p2.runs[0].font.color.rgb = WHITE

    # Banner note
    tb30 = get_shape(s4, 'TextBox 30')
    p = tb30.text_frame.paragraphs[0]
    p.text = ''
    r = p.add_run()
    r.text = "Target 90-Day Execution: 100 activated users, 60 WAU, 25 paying seats, and 1 paid institutional pilot in Pune at <₹15k CAC"
    r.font.name = 'Lucida Sans Unicode'
    r.font.size = Pt(12)
    r.font.bold = True
    r.font.color.rgb = AMBER

    # Section 3 Header & Content
    get_shape(s4, 'object 8').text_frame.paragraphs[0].text = "Clinical Referral Engine & Viral Indic Motion"
    tf3 = get_shape(s4, 'TextBox 31').text_frame
    clear_text_frame(tf3)
    add_bullet(tf3, "Offline Clinical Partnerships:", "Referral partnerships with orthopaedic and physiotherapy clinics treating IT repetitive strain injuries in Hinjawadi/Magarpatta; referral cards provide patients 1 month free Pro access.")
    add_bullet(tf3, "High-Contrast Social Motion:", "30-second video clips showing hands-free desktop control in natural Hindi and Marathi ('Clicky, Safari kholo, Notes paste karo'). Demonstrates what Siri and Apple Voice Control cannot do.")
    add_bullet(tf3, "Community Loops & In-Person Clinics:", "Weekly in-person 'Voice Setup Clinics' (microphone placement, noise profiling, personal vocabulary) + distribution across r/pune, LinkedIn, and accessibility developer Discords.")

    # ==========================================
    # SLIDE 5: UNIT ECONOMICS, PRICING & COGS ARCHITECTURE
    # ==========================================
    s5 = prs.slides[4]
    
    # Title
    get_shape(s5, 'object 2').text_frame.paragraphs[0].text = "UNIT ECONOMICS, PRICING & FINANCIAL SUSTAINABILITY"
    get_shape(s5, 'object 2').text_frame.paragraphs[0].runs[0].font.name = 'Arial'
    get_shape(s5, 'object 2').text_frame.paragraphs[0].runs[0].font.size = Pt(38)
    get_shape(s5, 'object 2').text_frame.paragraphs[0].runs[0].font.color.rgb = NAVY

    # Section 1 Header & Content
    get_shape(s5, 'object 4').text_frame.paragraphs[0].text = "Commercial Pricing Structure & Target SKUs"
    tf1 = get_shape(s5, 'TextBox 17').text_frame
    clear_text_frame(tf1)
    add_bullet(tf1, "The Pilot SKU (The First Rupee):", "₹49,999 for 10 seats / 6 months. Low barrier to entry, covers dedicated onboarding and customized application adapter profiling.")
    add_bullet(tf1, "Enterprise License (Margin Engine):", "₹2,499/seat/mo billed annually. Includes centralized admin console, SSO, MDM deployment, 1,200 pooled Live-min/seat/mo, and compliance audit logs.")
    add_bullet(tf1, "University / HEI Site License:", "₹1,800/seat/yr (min 25 seats). Aligned to UGC/EOC budget lines; student self-service tier at ₹249/mo (verified student status via UPI).")
    add_bullet(tf1, "Prosumer Subscriptions:", "India Pro at ₹499/mo (UPI native, 600 min fair-use cap) · Global Mac Pro at $11.99/mo ($99/yr) for US/UK English prosumers.")

    # Section 2 Header & Content
    get_shape(s5, 'object 6').text_frame.paragraphs[0].text = "COGS Architecture & Gross Margin Protection"
    tf2 = get_shape(s5, 'TextBox 18').text_frame
    clear_text_frame(tf2)
    add_bullet(tf2, "AX-First = ₹0 API Tokens:", "Tri-Tier execution engine routes over 90% of desktop actions through the native Accessibility tree (AX) at exactly zero LLM/vision token cost.")
    add_bullet(tf2, "Live Audio Economics:", "Gemini Live costs ~₹1–2/minute today. Blended COGS is aggressively optimized to ≤₹0.4/minute via local fast-path commands and compressed sessions.")
    add_bullet(tf2, "Fair-Use Financial Shield:", "A 600 min/mo fair-use cap guarantees 40–60%+ gross margins on retail tiers; enterprise pooled minutes absorb usage variance safely.")

    # Section 3 Header & Content
    get_shape(s5, 'object 8').text_frame.paragraphs[0].text = "Financial Benchmarks & Cost Advantage vs. Alternatives"
    tf3 = get_shape(s5, 'TextBox 19').text_frame
    clear_text_frame(tf3)
    add_bullet(tf3, "Assistive Hardware Comparison:", "Replaces GlassOuse (₹60,099) and Tobii eye-trackers (₹2,00,000–₹7,00,000+) at 100% native software cost with zero hardware maintenance.")
    add_bullet(tf3, "Legacy Assistive Software:", "Dragon NaturallySpeaking cost ₹17,500–₹50,000 (abandoned Mac in 2018); JAWS Pro costs $1,200 perpetual; Read&Write costs $184/yr.")
    add_bullet(tf3, "Frontier AI Agent Comparison:", "Claude/Codex vision agents burn continuous screenshots at ₹15–₹30 per task. Clicky runs at ~₹1–2 per task, delivering a 10x cost and margin moat.")

    # ==========================================
    # SLIDE 6: DEFENSIVE MOATS & COMPETITIVE ADVANTAGE
    # ==========================================
    s6 = prs.slides[5]
    
    # Title
    get_shape(s6, 'object 2').text_frame.paragraphs[0].text = "DEFENSIVE MOATS: SURVIVING GOOGLE & APPLE"
    get_shape(s6, 'object 2').text_frame.paragraphs[0].runs[0].font.name = 'Arial'
    get_shape(s6, 'object 2').text_frame.paragraphs[0].runs[0].font.size = Pt(38)
    get_shape(s6, 'object 2').text_frame.paragraphs[0].runs[0].font.color.rgb = NAVY

    # Header label
    get_shape(s6, 'object 4').text_frame.paragraphs[0].text = "Market Defensibility & Competitive Positioning Matrix"

    # Card 1
    get_shape(s6, 'TextBox 16').text_frame.paragraphs[0].text = "MOAT 1: THE TRUST STACK"
    tf17 = get_shape(s6, 'TextBox 17').text_frame
    clear_text_frame(tf17)
    add_bullet(tf17, "Client-Side 5-Tier Gate:", "Local risk engine & Intent Ledger prevent untrusted clicks.", lead_size=12.5, body_size=11.5, space_after=Pt(2))
    add_bullet(tf17, "Local <150ms Stop:", "On-device keyword spotting aborts OS queue without cloud lag.", lead_size=12.5, body_size=11.5, space_after=Pt(2))
    add_bullet(tf17, "Enterprise Procured:", "Enterprises buy auditable compliance, not raw model tokens.", lead_size=12.5, body_size=11.5, space_after=Pt(2))

    # Card 2
    get_shape(s6, 'TextBox 21').text_frame.paragraphs[0].text = "MOAT 2: ADAPTER CORPUS"
    tf22 = get_shape(s6, 'TextBox 22').text_frame
    clear_text_frame(tf22)
    add_bullet(tf22, "Proprietary App Recipes:", "Custom AX/canvas automation for Electron, SAP, VS Code.", lead_size=12.5, body_size=11.5, space_after=Pt(2))
    add_bullet(tf22, "Zero Developer APIs:", "Operates complex desktop software without developer buy-in.", lead_size=12.5, body_size=11.5, space_after=Pt(2))
    add_bullet(tf22, "High Switching Costs:", "Telemetry flywheel compounds UI execution reliability.", lead_size=12.5, body_size=11.5, space_after=Pt(2))

    # Card 3
    get_shape(s6, 'TextBox 26').text_frame.paragraphs[0].text = "MOAT 3: INSTITUTIONAL GTM"
    tf27 = get_shape(s6, 'TextBox 27').text_frame
    clear_text_frame(tf27)
    add_bullet(tf27, "Direct Indian Distribution:", "Embedded in University EOCs and Pune IT DEI channels.", lead_size=12.5, body_size=11.5, space_after=Pt(2))
    add_bullet(tf27, "Regulatory Tailwinds:", "Built specifically for RPwD, GIGW 3.0 & Draft AT Rules 2025.", lead_size=12.5, body_size=11.5, space_after=Pt(2))
    add_bullet(tf27, "Invisible to Big Tech:", "Apple & Google will not build local campus/CSR sales networks.", lead_size=12.5, body_size=11.5, space_after=Pt(2))

    # Sub-header above table
    tb29 = get_shape(s6, 'TextBox 29')
    p = tb29.text_frame.paragraphs[0]
    p.text = "COMPETITIVE ADVANTAGE & DEFENSIVE MOAT MATRIX (SPEC §2, §3 & VALIDATION 04)"
    p.runs[0].font.name = 'Lucida Sans Unicode'
    p.runs[0].font.size = Pt(13)
    p.runs[0].font.bold = True
    p.runs[0].font.color.rgb = NAVY

    # Table text
    table_data = [
        ("Rectangle 30", "Dimension", True, WHITE, NAVY),
        ("Rectangle 31", "Frontier Vision Agents (Claude/Codex)", True, WHITE, NAVY),
        ("Rectangle 32", "Clicky (Our Startup Moat)", True, WHITE, NAVY),
        ("Rectangle 33", "Cost & Latency", True, NAVY, WHITE),
        ("Rectangle 34", "₹15–30/task · 3–6s/step (heavy vision loop)", False, CHARCOAL, WHITE),
        ("Rectangle 35", "~₹1–2/task · 25–45ms warm AX (<₹0.4/min COGS)", True, CHARCOAL, WHITE),
        ("Rectangle 36", "Safety & Trust", True, NAVY, WHITE),
        ("Rectangle 37", "Autonomous batch · UI mouse clicks for approvals", False, CHARCOAL, WHITE),
        ("Rectangle 38", "5-Tier local risk gate · Spoken confirm · <150ms kill switch", True, CHARCOAL, WHITE),
        ("Rectangle 39", "Defensibility", True, NAVY, WHITE),
        ("Rectangle 40", "Model is rented supplier · No enterprise trust layer", False, CHARCOAL, WHITE),
        ("Rectangle 41", "Client-side trust stack + proprietary app adapter library", True, CHARCOAL, WHITE),
    ]
    for sh_name, txt, is_bold, text_color, _ in table_data:
        sh = get_shape(s6, sh_name)
        p = sh.text_frame.paragraphs[0]
        p.text = txt
        if p.runs:
            p.runs[0].font.name = 'Lucida Sans Unicode'
            p.runs[0].font.size = Pt(12)
            p.runs[0].font.bold = is_bold
            p.runs[0].font.color.rgb = text_color

    # Amber callout card
    tb43 = get_shape(s6, 'TextBox 43')
    tb43.text_frame.paragraphs[0].text = "WHY GOOGLE AND APPLE CANNOT CRUSH US (MOAT ANALYSIS SPEC §3)"
    tb43.text_frame.paragraphs[0].runs[0].font.name = 'Lucida Sans Unicode'
    tb43.text_frame.paragraphs[0].runs[0].font.size = Pt(13)
    tb43.text_frame.paragraphs[0].runs[0].font.bold = True
    tb43.text_frame.paragraphs[0].runs[0].font.color.rgb = AMBER

    tb44 = get_shape(s6, 'TextBox 44')
    tf = tb44.text_frame
    clear_text_frame(tf)
    add_bullet(tf, "The Model is a Supplier, Not a Product:", "Gemini gets better for everyone; Google cannot sell client-side enterprise trust, local risk gates, or custom desktop actuation.", lead_size=13.0, body_size=12.0, lead_color=NAVY, body_color=CHARCOAL, space_after=Pt(3))
    add_bullet(tf, "Apple Will Not Build Indian Institutional Channels:", "Apple Voice Control lacks Hindi/Marathi navigation and enterprise compliance tools. Clicky owns local distribution.", lead_size=13.0, body_size=12.0, lead_color=NAVY, body_color=CHARCOAL, space_after=Pt(3))
    add_bullet(tf, "Compounding Telemetry Flywheel:", "Opt-in execution data feeds proprietary adapter recipes (Electron, SAP, canvas), creating deep enterprise switching moats.", lead_size=13.0, body_size=12.0, lead_color=NAVY, body_color=CHARCOAL, space_after=Pt(2))

    # ==========================================
    # SLIDE 7: STARTUP SCALING ROADMAP: GATES, NOT DATES
    # ==========================================
    s7 = prs.slides[6]
    
    # Title
    get_shape(s7, 'object 2').text_frame.paragraphs[0].text = "STARTUP SCALING ROADMAP: GATES, NOT DATES"
    get_shape(s7, 'object 2').text_frame.paragraphs[0].runs[0].font.name = 'Arial'
    get_shape(s7, 'object 2').text_frame.paragraphs[0].runs[0].font.size = Pt(38)
    get_shape(s7, 'object 2').text_frame.paragraphs[0].runs[0].font.color.rgb = NAVY

    # Phase 1 Header & Content
    get_shape(s7, 'object 4').text_frame.paragraphs[0].text = "Phase 1 (M0–M3): macOS Validation & Beachhead Revenue"
    tf1 = get_shape(s7, 'TextBox 17').text_frame
    clear_text_frame(tf1)
    add_bullet(tf1, "Production Deliverables:", "Signed .app bundle with 10-app certified adapter matrix (Safari, Mail, Notes, Slack, VS Code, Office); <5-min self-onboarding flow.")
    add_bullet(tf1, "Traction & Revenue Gates:", "2 signed paid pilot LOIs (1 HEI + 1 IT Employer), 25–50 paying seats, and DPDP-2023 compliance pack.")
    add_bullet(tf1, "Non-Dilutive Capital:", "Apply for MeitY TIDE 2.0 grant (₹7 Lakh grant-in-aid, scaling to ₹40 Lakh scale-up funding).")

    # Phase 2 Header & Content
    get_shape(s7, 'object 6').text_frame.paragraphs[0].text = "Phase 2 (M3–M6): Windows UIA Port (The 82% Market Unlock)"
    tf2 = get_shape(s7, 'TextBox 18').text_frame
    clear_text_frame(tf2)
    add_bullet(tf2, "The Strict Trigger Gate:", "Windows development begins only after achieving 100 paid macOS seats + 2 enterprise design partners.")
    add_bullet(tf2, "Decoupled Architecture:", "ClickyCore (intent parser, risk gates, overlay, licensing) is 60% OS-agnostic; porting requires only building the Windows UI Automation (UIA) adapter.")
    add_bullet(tf2, "Massive Market Expansion:", "Instantly unlocks the 82% of Indian desktops running Windows, converting a ₹10–15 Cr SAM into a ₹350–500 Cr TAM. Target: ₹1.5–3L MRR.")

    # Phase 3 Header & Content
    get_shape(s7, 'object 8').text_frame.paragraphs[0].text = "Phase 3 (M6–M18): Enterprise Platform & Scale"
    tf3 = get_shape(s7, 'TextBox 19').text_frame
    clear_text_frame(tf3)
    add_bullet(tf3, "Enterprise IT Hardening:", "Centralized web admin console, MDM fleet deployment, GeM portal vendor registration, and ISO 27001 readiness.")
    add_bullet(tf3, "Revenue & Platform Scale:", "300–500 paid institutional seats; ₹40 Lakh–₹1 Crore ARR; adapter marketplace for third-party enterprise tools.")
    add_bullet(tf3, "Global Prosumer Expansion:", "Scaling English prosumer tier ($99/yr) across US/UK markets as a high-margin cash stabilizer.")

    # ==========================================
    # SLIDE 8: CONCLUSION, THE ASK & THANK YOU
    # ==========================================
    s8 = prs.slides[7]
    
    # Title
    get_shape(s8, 'object 2').text_frame.paragraphs[0].text = "THANK YOU"
    
    # Text Box 6
    tb6 = get_shape(s8, 'TextBox 6')
    tf = tb6.text_frame
    clear_text_frame(tf)
    
    p0 = tf.paragraphs[0]
    r0 = p0.add_run()
    r0.text = "CLICKY — Voice-First AI Cursor for macOS"
    r0.font.name = 'Trebuchet MS'
    r0.font.size = Pt(28)
    r0.font.bold = True
    r0.font.color.rgb = NAVY
    p0.space_after = Pt(8)

    p1 = tf.add_paragraph()
    r1 = p1.add_run()
    r1.text = "From Accessibility Wedge to Universal Computing Input Layer"
    r1.font.name = 'Lucida Sans Unicode'
    r1.font.size = Pt(18)
    r1.font.bold = True
    r1.font.color.rgb = CHARCOAL
    p1.space_after = Pt(8)

    p2 = tf.add_paragraph()
    r2 = p2.add_run()
    r2.text = "Team: Arc Agents  ·  CraftVerse 2.0 Hackathon (Agentic AI Track)  ·  PCCOE&R Pune"
    r2.font.name = 'Lucida Sans Unicode'
    r2.font.size = Pt(16)
    r2.font.bold = True
    r2.font.color.rgb = GRAY
    p2.space_after = Pt(8)

    p3 = tf.add_paragraph()
    r3 = p3.add_run()
    r3.text = "The Ask: 2 Pilot Design Partners (1 HEI EOC + 1 Pune IT Enterprise) & Industry Mentors"
    r3.font.name = 'Lucida Sans Unicode'
    r3.font.size = Pt(16)
    r3.font.bold = True
    r3.font.color.rgb = AMBER
    p3.space_after = Pt(8)

    p4 = tf.add_paragraph()
    r4 = p4.add_run()
    r4.text = "GitHub: github.com/pranav1296/clicky  ·  Open Source MIT License © 2026"
    r4.font.name = 'Lucida Sans Unicode'
    r4.font.size = Pt(15)
    r4.font.bold = True
    r4.font.color.rgb = NAVY
    p4.space_after = Pt(14)

    p5 = tf.add_paragraph()
    r5 = p5.add_run()
    r5.text = "Open for Questions & Startup Evaluation Round 3 Defense"
    r5.font.name = 'Lucida Sans Unicode'
    r5.font.size = Pt(20)
    r5.font.bold = True
    r5.font.color.rgb = CRIMSON

    # Save output
    prs.save(OUT_PPTX)
    print(f"Successfully generated Round 3 presentation at: {OUT_PPTX}")

if __name__ == '__main__':
    build_presentation()
