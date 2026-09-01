# TMG × Omnishift — Prototype Structure (v2)
Revised against the TMG Discovery Debrief. Engine spec, not a standalone product.

Two things from the call move the plan: **what we ship** (Salesforce overlay, not a new app) and **what we are measured on** (CA meetings booked, not 34% close).

---

## 0. What this prototype is

Omnishift is the **engine**. CAs never log into it.

What they see, inside Salesforce they already live in:

1. An **Omnishift tab** on the Lead / Contact record (Super Profile, Why Now, draft, checks)
2. An **alert** (“call now” / “Pam was on the site yesterday”)
3. A **Today Queue dashboard** (“work these 17”)

John: *“This is like the engine behind that they don't even necessarily need to see.”*

If a CA has to leave Salesforce, the design failed.

**Hard part is not display. It is feedback capture.** In a standalone app that is a button. Inside Salesforce it is custom fields, page-layout changes, and adoption. Design those fields now. Do not promise a tab, a custom object, or a dashboard component until Stu Maggs says what they cost in this org.

---

## 1. Two products. Do not bundle them.

| | Product A — Phase 0 / 1 | Product B — Phase 2 |
|---|---|---|
| Job | Who to reach today, why now, what to say | Which CA / BD should say it |
| Model | Prospect ranking + identity | Person-to-person matching |
| Input TMG already has | Salesforce activity, WealthFeed catalysts, VisitIQ journeys | Geo + lead-owner field only |
| Input TMG does **not** have | — | Per-person conversion by segment, certs, strengths |
| First visible feature | Suppression + post-call compliant email | Skill graph + high-AUM HITL |
| Risk if bundled | Phase 1 stalls waiting on a roster TMG has not assembled | — |

John led with matching (*“Gus is really good with this type of person… Claire is the best at closing this type of executive”*). Deana offered to build the roster. That is a **different product**. Tom’s current routing is geography + lead owner. Keep that in Phase 1. Say this out loud next call.

High-AUM (e.g. $10M+) → John / Deana review is a **rule**, not matching. It can ship in Phase 1 as an exception, not a model.

---

## 2. Scoreboard (have this conversation next call)

John gave 34% — initial held → agreement signed. That happens **after** a BD is already in a four-meeting process. The agent sits **upstream**. If 34% becomes the success metric we will be judged on something we barely touch.

**Say this:** *“John, you gave us 34% and that is a great number to know — but it happens after a BD advisor is already in the room. What we affect is upstream: how many initial meetings your CAs book, and how much of their week goes to research instead of dialling. Can we agree those as the scoreboard, and treat 34% as the thing we protect rather than the thing we promise to raise?”*

| Metric | Who owns it | Does the agent move it? |
|---|---|---|
| Lead → initial meeting conversion | CA team | **Yes. Headline metric.** |
| Initial meetings booked per CA per week | Tom’s team | **Yes. Shows up first.** |
| Contact rate per cadence | Tom’s team | **Yes.** Right person, time, channel. |
| CA hours lost to cross-reference and copy-paste | Tom’s team | **Yes, week one** (suppression + post-call email). |
| 34% initial → signed | BD advisors, 4 meetings | Barely. **Protect, do not promise.** |
| Average client size at signing | Shared | Partly. Tom already credits WealthFeed — attribution will be contested. |

Deck SLAs we still honor as constraints, not as our scoreboard: website CA contact **< 5 min**, referral **immediate**.

---

## 3. What WealthFeed is (and is not)

Identification only. Search by ICP, wealth data, catalysts (inheritance, job change, relocation). Firm-wide since early July after an 8-week pilot. Immediate impact on client size and pipeline.

**No outreach automation. No sequencer. No Proofpoint compliance flow in use.** CAs call and email by hand.

Stop treating WealthFeed as a competitor. It is an **upstream data source**. The decision layer, messaging layer, and supervision layer are open. Say that plainly next time.

VisitIQ is the same kind of source: pixel, journey, UTM, identified people. Client suppression there is still leaky.

---

## 4. Engine (the prototype structure)

```
SALESFORCE  (only daily surface)
  Omnishift tab on Lead/Contact     Super Profile, Why Now, draft, checks, feedback fields
  Alert                             website form, referral, hot VisitIQ, high-AUM
  Today Queue dashboard             ranked work for this CA
  Writes                            tasks, activity, sent email
        ▲
        │  LWC + REST / Platform Events — cost confirmed with Stu Maggs before we promise
        ▼
OMNISHIFT ENGINE
  [P0] Identity resolution + suppression + quarantine
  [P1] Super Profile → Scoring / Why Now → Cadence / timing
  [P1] Compliant message agent (visible: post-call follow-up email)
  [P1] Feedback capture (approve / edit / wrong person / done) → learning loop
  [P2] Router: CA/BD match by conversion-by-segment   ← SEPARATE PRODUCT
  [P3] Zoom Revenue Accelerator → conversion reasons

SOURCES: Salesforce · WealthFeed (ID only) · VisitIQ · Pardot/ABM · Zoom RA
         CA/BD roster (P2 only)
```

### Super Profile
One person, resolved across systems. Pam is the acceptance test: VisitIQ journey + 2018 SF note (“didn’t know when she can retire”) + Atlanta geo → Atlanta CA’s queue that morning, retirement-framed opener.

Groups: identity, ICP fit, why now (catalyst, journey, campaign, last activity, old notes), intent pages/UTM, history, fit flags (below ICP / already client / incomplete), recommended action (not recommended owner until P2), draft, score + explanation.

### Today Queue
Ranked list. Each row answers: who, why now, what to say, channel, window. One click: call, send approved email, snooze, wrong person. Target line: “work these 17 today.”

### Cadence (Tom, until first contact)
Day 1: call + VM + email. Day 3: call, no VM. Day 5: call + email. Two weeks (extend high AUM). No connect → inactive `unresponsive` + 90-day task. After connect: prospect-driven.

**Visible P1 feature Tom asked for:** after a live call, a compliance-approved follow-up email is drafted (and, once trusted, sent). That is the first send automation. Not cold mass mail.

### Quarantine (nothing silent)
Identity collision, client in a prospect list, below ICP, incomplete cookie, ambiguous why-now. Reason code required. CA can push back in.

### Feedback fields (design now, Salesforce-native)
On the recommendation / activity: `acted` / `snoozed` / `wrong_person` + why / `edited_then_sent` / `rejected` + why. This is the learning loop. If Stu cannot give us fields, we do not have a product, we have a display.

### Lead-to-advisor matching (P2 only)
Needs: roster (certs, geo, strengths — Deana offered), plus historical conversion by segment (almost certainly not assembled). Until then, keep SF owner + geo, plus the $10M John/Deana rule.

---

## 5. Four intakes (shared profile, different SLA)

Do not collapse these into one generic lead. Engine scores on one Super Profile; first action differs.

| Channel | First action | SLA | P1? |
|---|---|---|---|
| Website form | CA contact, VisitIQ journey on the opener | < 5 min | **Yes — recommended hot path** |
| Referral | Named advisor if given, skip the ranker | Immediate | Yes, as a rule |
| WealthFeed catalyst | Enrich → call + email | Same day if ICP | After suppression exists |
| ABM | CA copy in campaign language (surround-sound) | Campaign-aligned | P1.5, once marketing list + suppression work |

All four terminate at Opportunity. The 5-meeting BD conversion path is **observed, not automated**. We do not skip meetings. We do not take credit for 34%.

---

## 6. Phased build

### Phase 0 — Identity (this is the bottleneck Tom named twice)
Suppression between WealthFeed and Salesforce. Same problem in VisitIQ (clients still leak) and ABM.

**Ask WealthFeed first.** Suppression is arguably their job; Deana has Sam Kendry’s mobile. If they will not ship it, we build it and it is a fast, measurable win (CA hours). Identity key stored on the Salesforce record.

### Phase 1 — Visible engine, one hot path
Recommended path: **Website + VisitIQ intent** (SLA already exists, journey is the why-now).

Ship:
- Super Profile + Why Now + Today Queue (overlay)
- **Post-call compliance-approved email** (Tom specified this; adoption is guaranteed)
- Quarantine + feedback fields
- High-AUM exception rule
- Referral skip-the-ranker rule

Measure: meetings booked / CA / week, contact rate, hours saved vs cross-reference and copy-paste, lead → initial conversion.

### Phase 2 — Lead-to-advisor matching (separate product)
Roster + conversion-by-segment. Do not start until Deana’s database exists and we have said out loud this is a second engagement slice.

### Phase 3 — Conversion intelligence
Zoom Revenue Accelerator in. Meeting briefs, stall detection on M1–M5. **Request the data now** even though this ships last. Longest lead time.

---

## 7. Next-call prototype (what to put on screen)

Not the logic slides we already have. Three Salesforce-shaped surfaces:

1. **Record tab** — Pam. Identity strip, Why Now (VisitIQ pages + 2018 note + wealth band), recommended action, compliant draft with checks passed, three feedback buttons.
2. **Alert** — “Pam returned to the site yesterday. Call today.” Click opens the tab.
3. **Dashboard** — Today Queue for one CA. 17 rows. Why Now on each. Hours-saved ticker is optional and honest (suppression).

Label it *engine preview inside Salesforce chrome*. Do not fake a new app.

Before promising any of it is installable: Stu Maggs answers cost of tab / custom object / dashboard component in this org.

---

## 8. Explicitly out of scope for Phase 1

- A standalone CA daily app
- Lead-to-advisor matching as a model (P2)
- Fully virtual close
- Replacing WealthFeed search
- Silent drops
- Unapproved mass email
- Deep Salesforce data-model rewrite
- Promising to raise 34%
- Generating more top-of-funnel leads

---

## 9. Acceptance tests

1. **Pam test.** VisitIQ + old SF note + Atlanta geo → Atlanta CA’s queue same morning, retirement-framed draft.
2. **Five-minute test.** Website form → alert + profile + opener inside five minutes.
3. **Referral test.** Named-advisor referral skips the ranker.
4. **Suppression test.** Existing SF contact in a WealthFeed export never duplicates; collision goes to quarantine with a reason.
5. **Wrong-person test.** CA marks it, says why, similar records drop, reason is visible on the record.
6. **High-AUM test.** $10M+ does not auto-assign; John/Deana see it first. (Rule, not matching.)
7. **Tom’s email test.** After a logged call, a disclosure-complete follow-up is ready to approve.
8. **Feedback test.** The disposition the CA chose is written to a Salesforce field, not only shown in our UI.

---

## 10. What to send today (from the debrief)

1. Vendor questions for Deana → Sam Kendry (WealthFeed) and Vern (VisitIQ). Suppression is question 1 for WealthFeed. Full lists in `/workspace/tmg-vendor-questions.md`.
2. Retrospective **data request** (nobody asked on the call; longest lead time). Include Zoom Revenue Accelerator: API and transcript export.
3. Ask for **Stu Maggs** (what a tab / custom object / dashboard costs) and **Adam** (compliance is load-bearing for Tom’s auto-email) on the next session.
4. Ask again, in writing, to **watch Tom or a CA work for 20 minutes**. Gevorg asked, Deana moved to VisitIQ, it slipped.
5. Short recap that **names the metrics** so 34% does not harden by default.

Covering line for the vendor email: *“Answers to the API and identity-key questions are what let us design the integration properly — if we get those back before the next session, we can bring an architecture rather than a set of options.”*
