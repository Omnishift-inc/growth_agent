# What still needs doing

## Before it leaves the demo org
- **Compliance rules as records.** A Compliance Rule object (phrase, action, citation, scope, effective dates, field history), the SEC baseline seeded read-only, an import from the firm's lexicon, and a review queue that turns principals' edits into candidate rules. Today the rules are three lists in code.
- **Real feeds.** WealthFeed, VisitIQ, SmartAsset, Account Engagement, LinkedIn, Zoom and GetFeedback are sandboxed. The signal object is the shape they write to; the Universal Integrator proves the path. Each needs a connector, a Named Credential and a schedule.
- **Outcome data from TMG.** The weights are reasoned, not fitted. Last year's conversions and how they arrived are the one input only the firm can give.
- **Advisor routing.** `Omnishift_Recommended_Owner__c` is filled by a simple pool; the demo org has one advisor. Geography, specialism and capacity rules are not built.
- **Time zone.** The demo user is on Los Angeles time; "Act by" reads as yesterday from Yerevan. One user setting.

## Product gaps we know about
- Person Accounts are excluded, not handled.
- No approval process on rule changes or on Flagged drafts; a principal's review is a status, not a workflow.
- The Activity tab's own timeline needs its Refresh link after a panel action (standard component).
- The learning loop keys on the reason only; per-advisor and per-source rates would need more evidence than a demo org has.
- Drafts are templates plus quoted words, not generated text.

## Demo-only
- Dashboard timestamps are per viewer; press Refresh before showing it.
- The integrator runs on 127.0.0.1 and is not wired to Salesforce; the data is kept identical by hand (Diane Okafor).
