# Growth Agent - demo script

**Org:** https://orgfarm-7c54862b2e-dev-ed.develop.lightning.force.com (log in as the demo user first; the links below bounce to the login page otherwise)
**Universal Integrator:** http://127.0.0.1:8788 (runs separately; the person it researches, Diane Okafor, is the same person in Salesforce)
**Before you start:** open the dashboard once and press *Refresh*; hard-reload the Home page (Cmd-Shift-R) so nothing is cached from an earlier build.

Every name, email (`@example.com`), phone (`555-01xx`) and event in the org is generated. Nothing can reach a real person. Live sending is off.

---

## 0. The one-sentence frame (30s)

"You asked for an agent that tells your associates who to call today and why, learns from what happens, and never sends something compliance would not sign. It lives inside the Salesforce you already have. Nothing here is a new tool to learn."

## 1. Home: today's list (2 min)

https://orgfarm-7c54862b2e-dev-ed.develop.lightning.force.com/lightning/page/home

- "Today you should work 25 people." Deana's phrase from the call, made literal. One merged, ranked list across Leads (prospects) and Contacts (existing clients), because both live in your Salesforce and both have reasons to be called.
- Read row 1 aloud, Wren Ashcombe: the **why-now** is a specific event with the evidence behind it, in WealthFeed's words - the probate filing, the amount, how it was matched. Not "high intent". Something an associate can open the call with.
- Every row ends in **Cleared to send**: the draft is already written and has already passed the compliance check. The top of the list is sendable as it stands.
- **Existing clients are on the same list.** Press the **Contacts** pill. The point: the agent does not only find new money, it tells advisors which of the households they already look after need a call this week, and why. Thea Mossgrove at #2: WealthFeed saw her company file a Form D - a client with new proceeds and a plan that no longer fits. Rosalind Wexford: answered the survey four days ago and named two people she would refer. Dashiell Ainsleigh at #23: no event at all, on the list because his annual review is a year overdue - the relationship rule, not a feed. Clients get a fortnight's cooling period instead of two days, and client drafts read as a relationship, not a pitch.

  *Say:* "Half the value is in the book you already have. Nobody is looking for the client whose company just sold; the agent is."
- Briefing card on the right: 25 to work, how many handled today, how many drafts held by compliance, how many records **suppressed** - and the eight feeds the signals came from in the last 120 days (VisitIQ, WealthFeed, SmartAsset, Account Engagement, LinkedIn, Zoom, GetFeedback, public web). That last list is the point of the integrator: any source that can be read becomes a signal here.

## 2. A prospect record: the reasoning, then the action (3 min)

Wren Ashcombe, #1: https://orgfarm-7c54862b2e-dev-ed.develop.lightning.force.com/lightning/r/Lead/00Qg800000CPTmHEAX/view -> **Omnishift** tab

- Score 100, the why-now, then the facts strip: **#1 of 25 today · Surfaced for Event · WealthFeed · Draft cleared to send · Escalation: Leadership notified**.
- Escalation: Tom's rule from the call - above the $10M threshold John and Deana get a notification. It fired once, the first night she surfaced, to whoever holds the Manager permission set. The firm decides who "John and Deana" are without a code change.
- The orange line: **marketing is emailing this person on 7 Sep**, from the Account Engagement calendar Deana showed. Far enough out that today is fine; inside three days the agent would have held her back so the firm does not arrive twice. That is the "calendar" you asked about, read, not just displayed.
- **Engagement history**: everything the firm knows about her in one timeline - the WealthFeed filing with its evidence, the scheduled send, the agent's own trail. Sources labelled.
- **Draft**: open it. Written by the agent, addressed to her, no event named (a feed's confidence is not certainty - you never open with "congratulations on the sale" to someone who did not sell). Press **Approve**: the compliance check runs again on the exact text, a completed Email task lands on the record, the Lead moves to *Working - Contacted* on the Path, and she leaves tomorrow's list. Nothing was delivered: live sending is a switch that stays off until archiving is settled.
- Show **Not now** -> choose a date. The panel changes state: "Not now, comes back 10 Sep" with *Bring back today* and *Change date*. The nightly run honours it. Then bring her back.

## 3. Compliance: the check catching the agent's own draft (2 min)

Pamela Whitaker: https://orgfarm-7c54862b2e-dev-ed.develop.lightning.force.com/lightning/r/Lead/00Qg800000CN71TEAT/view -> **Omnishift** tab

- She wrote "guaranteed income in retirement" in her SmartAsset enquiry. The agent did the natural thing and quoted her words back to her. The check stopped it: **Blocked: this draft cannot be sent as written**, with the sentence explaining whose words they are and why the firm may not repeat them (SEC marketing rule 206(4)-1), and a **Rewrite the draft** button.
- Press it, delete the phrase, Save: the check runs on the edited text and the block lifts. The same check runs at the moment of sending, so an associate's last-minute edit is caught too.
- Where the rules live today: in code, shipped as the SEC baseline. Where they will live: a Compliance Rule object your CCO owns, with your own lexicon imported in the first week and every change audited. (Describe; not built.)

## 4. The agent learns, and the advisor's decision wins (1 min)

Any record footer -> **What happened after the email?** with the outcomes as pills.

- An outcome is the label the ranking learns from: booking rate per reason, blended with the firm's prior until there is enough evidence, bounded so one good fortnight tilts the ranking and never rebuilds it. Briefing shows it in the multipliers.
- **Wrong person** holds the record off the list until you undo it. **Meeting booked** takes it off the list. **Not now** stands until the date, unless a fresh confirmed event arrives. The nightly run does not undo an advisor.

## 5. Suppression and quarantine: what was removed overnight and why (1 min)

Briefing -> "15 suppressed". Any held record's Omnishift tab shows the reason in words: *Duplicate of an owned Contact - cross-reference* (Tom's team does this by hand today), *Closed*, *Contacted within 14 days - cooling period*, *Already being worked - an open follow-up is scheduled*, *Marketing has a send scheduled*, *Marked as the wrong person by the advisor*. Held, not deleted; a human can release it.

## 6. Universal Integrator: any source becomes a signal (2 min)

http://127.0.0.1:8788 (separate window)

- Run the research job on **Diane Okafor**. Watch it read WealthFeed (sudden-wealth event, est. $5.2M inheritance, 29 Aug), VisitIQ (one organic visit on 30 Aug, "/" then "/our-team", three minutes) and the public directory (Senior Counsel at Truist, Charlotte NC).
- Switch to her Salesforce record: https://orgfarm-7c54862b2e-dev-ed.develop.lightning.force.com/lightning/r/Lead/00Qg800000CQanJEAT/view -> Omnishift tab. Same three signals, same wording, same dates, scored and drafted. "This is what the integration writes. It does not matter what the source is; if it can be read, it becomes a reason on the list."

## 7. Is it working? (1 min)

Dashboard: https://orgfarm-7c54862b2e-dev-ed.develop.lightning.force.com/lightning/r/Dashboard/01Zg8000002ppNVEAY/view

- Four numbers and one chart: surfaced, worked, top-of-list untouched, compliance holds; and whether advisors act on the top of the list more than the bottom - the only in-org evidence the ranking is real. Sixteen reports behind it. Be straight: the dispositions and outcomes in this org are generated so the instrument is readable; the reading comes from their data.

## Close (30s)

"Meetings booked and hours not spent hunting. The 34% close rate is after a BD is in the room; we protect it, we do not promise to raise it. Next step is the one thing only you can give us: which leads converted last year, and how they arrived. That turns these weights from reasoned into fitted."

---

## If asked

- **Is any of this real data?** No. Every person, event, email and phone number is generated and says so on the record. Live email is off by default and is a Setup switch.
- **What does the score mean?** Five weighted features - how they arrived, timing, fit, dormancy, and a confirmed event - adjusted by what outcomes have taught the loop, capped at 100.
- **Why is someone not on the list?** Open the record; the Omnishift tab says the hold reason in words.
- **Who wrote the draft?** The agent. Every draft is a template written to pass the check; personal lines come only from what the person themselves wrote, and those are checked too.
- **Where do the compliance rules come from?** The SEC Marketing Rule baseline today; your CCO's lexicon and reviews tomorrow (see section 3).
