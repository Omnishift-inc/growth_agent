# Vendor questions — ready to forward
Deana routes these to the CEOs: Sam Kendry (WealthFeed) and Vern (VisitIQ).
TMG got in early with both and is helping shape the platforms — ask for what we need, not only what exists.

Covering line: "Answers to the API and identity-key questions are what let us design the integration properly — if we get those back before the next session, we can bring an architecture rather than a set of options."

---

## WealthFeed — for Sam Kendry

### Access and integration
1. Do you expose a REST API for programmatic access to prospect records and wealth events? If so, what authentication, and is there developer documentation?
2. What are the rate limits and volume ceilings per account?
3. Can we receive events by webhook or push when a catalyst fires, rather than polling?
4. How does the existing Salesforce integration work — native managed package, middleware, or export? Which objects and fields does it write?
5. Is there a bulk or batch endpoint for enriching a list of existing records, as opposed to one lookup at a time?

### The suppression gap — lead with this
6. TMG's largest operational bottleneck is that WealthFeed does not suppress records that already exist in their Salesforce. Client associates cross-reference by hand on every prospect. Is bidirectional suppression on your roadmap, and on what timeline?
7. If not, can we push a suppression list to you via API and have it respected in search results and exports?
8. What identity resolution key do you match on — email, name plus address, a proprietary person ID? Is that ID stable and can it be stored in Salesforce for future matching?

### Data, provenance and licensing
9. For each field — net worth, investable assets, income, age — is the value observed or modelled, and do you expose a confidence score?
10. What are the 16 catalyst types, what is the detection latency for each, and how is recency stamped?
11. What does the licence permit regarding derived works — may we compute and store scores derived from your data inside TMG's environment?
12. Any restriction on passing your data to a third-party processor such as ourselves, and do you need to approve us as a sub-processor?
13. What is the source and refresh cadence of the underlying data, and how are opt-outs and do-not-contact requests handled?

---

## VisitIQ — for Vern

### Access and integration
1. Is there a REST API for identified visitor records and their journeys? Authentication, rate limits, documentation?
2. Can identifications be delivered by webhook in near real time, so an alert can reach a client associate the same day?
3. How does the Salesforce push work today — which objects, which fields, and is it configurable?
4. Is the journey data (page sequence, UTM source, timestamps) available through the API, or only in the interface? Deana noted it does not appear on every record — why?

### Match quality — ask directly
5. What is your measured accuracy for person-level identification, and how was it measured? Would you support a known-visitor test where TMG sends five known people to the site and we check what comes back?
6. Do you return a confidence score per identification, and can it be filtered on?
7. TMG's uploaded list produced records with implausible net worth values. What causes that, and is there a way to flag low-confidence enrichments rather than returning them silently?
8. Can we push a client and do-not-contact suppression list so existing clients never surface? Deana is still working around this manually.

### Consent, provenance and compliance
9. What exactly is the consent basis for identification, and what does the pixel capture before consent is given?
10. Do you provide an auditable record of consent per identified visitor — timestamp, banner version, choice made? TMG is an SEC-registered adviser and needs to evidence this.
11. How do you handle state privacy law opt-outs and deletion requests, and what is the turnaround?
12. Which fields are observed versus modelled, and what are the licence terms on derived works and third-party processing?
