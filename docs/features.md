# Growth Agent - what is built

Everything runs inside Salesforce (Apex, Lightning Web Components, standard objects plus custom fields). No external service is called. Every number on screen traces to a rule in `OmnishiftEngine.cls`.

| Area | What it does | Where |
|---|---|---|
| Nightly engine | Reads every Lead and Contact, suppresses, scores five weighted features (intake, timing, fit, dormancy, confirmed event), applies what outcomes have taught it, ranks both objects in one order, routes to an advisor, drafts, checks compliance, escalates | `OmnishiftEngineBatch`, `OmnishiftEngine`, scheduled 02:00 |
| Immediate scoring | A new web or referral Lead is scored on insert, for the five-minute SLA | `OmnishiftInboundService`, `OmnishiftLeadTrigger` |
| Signals | `Omnishift_Signal__c`: type, source, date, confidence, evidence. Eight sources seeded. A recent confirmed event outranks a merely newer engagement signal | object + `pickSignal` |
| Why-now | One paragraph per record: the event, its evidence in the source's words, the consequence, plus intake context | engine |
| Drafts | Templates per reason, addressed to the person; quote the person's own words when a feed carries them | engine |
| Compliance | SEC 206(4)-1 checks on every draft, every save and every send: block, flag for a principal, or auto-correct with a re-read prompt | `complianceCheck` |
| Suppression / quarantine | Closed, opt-out, duplicate of an owned Contact, marketing send inside the window, open follow-up, cooling period (2 days prospects, 14 clients), wrong person, meeting booked. Held with the reason on the record | engine + batch |
| Marketing calendar | `Omnishift_Marketing_Send__c` read for collisions; week grid on Home and Today's list; entries open to the people on them | `omnishiftMarketingCalendar` |
| Escalation | Households at or above $10M notify holders of the Manager permission set once | `OmnishiftEscalation` |
| Learning loop | Booking rate per reason, blended with the prior, bounded 0.85-1.15, applied nightly | `OmnishiftLearning` |
| Home page | Merged ranked queue (Leads / Contacts), briefing (counts, feeds, list-view links), calendar | `omnishiftTodayQueue`, `omnishiftBriefing` |
| Today's list tab | The same queue full-page | app page `Omnishift_Today` |
| Record page | Omnishift tab: score, why-now, facts strip, marketing note, compliance note, engagement history, next step, draft; footer that shows the record's state and only the actions left | `omnishiftPanel` on Lead and Contact pages |
| Actions | Approve (send + task + status), Edit first, Log a call, Not now (date), Wrong person, outcomes, Undo / Bring back today. Every action writes the record, logs activity and moves the standard Lead status | `OmnishiftAction` |
| Details tab | Growth Agent section on both layouts, read-only | layouts |
| Measurement | 16 reports, dashboard "Growth Agent: Is It Working?" | folder `Growth_Agent_Performance` |
| Safety | All emails `@example.com`, phones 555-01xx, generated names and events; live email behind `Omnishift_Config__mdt.Send_Live_Email__c` (off) | |
| Tests | 73 Apex tests, every class above 75% coverage | `OmnishiftEngineTest`, `OmnishiftActionTest` |
| Demo data | 21 scripts under `salesforce/omnishift-sf/scripts/apex/demo` rebuild the demo state | |
