# Demo data scripts

Anonymous Apex that builds and repairs the demonstration data in the dev org.
Every value is generated: emails are `@example.com`, phones `555-01xx`, names
invented. Nothing here can reach a real person.

Run with `sf apex run -o <org> -f scripts/apex/demo/<file>.apex`.

| Order | Script | What it does |
|---|---|---|
| 1 | `realdata.apex` | Bios, birthdates, account revenue, titles on every record |
| 2 | `deepdata.apex` | Signals from WealthFeed, VisitIQ, SmartAsset, Account Engagement, GetFeedback, LinkedIn, Zoom; first marketing calendar |
| 3 | `resendcal.apex` | Marketing calendar: one campaign per person over two weeks |
| 4 | `gen2.apex` | Advisor dispositions and compliance outcomes by score band |
| 5 | `earned.apex` | Compliance verdicts produced by the real checker over drafts that genuinely trip a rule |
| 6 | `lt.apex` | Outcomes on prospects so the learning loop has evidence |
| 7 | `activities.apex` | Cadence tasks and meetings that agree with the outcomes |
| 8 | `demo-restore.apex` | Frees prospects the seeds had parked or booked, moves colliding sends, refreshes signals; runs the engine |
| 9 | `demo-top.apex` | Head of the list: fresh confirmed event and a $10m+ balance; runs the engine |
| 10 | `demo-booked.apex` | Two event-driven prospects with a meeting on the calendar (teaches the loop) |
| 11 | `demo-clients.apex` | Spreads client signal ages and confidences so clients do not bunch at 100; runs the engine |

After any of these, run the engine (`System.debug(OmnishiftEngineBatch.runNow());`)
twice if outcomes changed: the first pass records drivers, the second learns from them.
| 12 | `demo-consistent.apex` | Every seeded advisor decision gets its date and the email or call it implies; a blocked draft cannot have been sent |
| 13 | `demo-outcomes.apex` | Removes outcomes from records that were never worked |
| 14 | `demo-status.apex` | Lead status agrees with the recorded outreach |
| 15 | `demo-evidence.apex` | Evidence that matches each signal's type, in the source tool's words, varying per household; runs the engine |
| 16 | `demo-park.apex` | Snoozed records carry the date they come back on |
| 17 | `demo-trim.apex` | A realistic few snoozes and wrong-person marks instead of a third of the list; runs the engine |
| 18 | `demo-ownwords.apex` | Compliance cases from the agent's own drafts quoting what the prospect wrote; drops the seeded advisor edits; runs the engine |
