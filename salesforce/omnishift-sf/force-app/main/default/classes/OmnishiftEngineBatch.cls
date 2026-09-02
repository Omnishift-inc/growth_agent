/**
 * The nightly run. Reads leads and clients, suppresses, scores, ranks, routes,
 * drafts and compliance-checks, then writes the results back to the record.
 *
 * Batched at 200 so each chunk stays well inside governor limits, and the ranking
 * is assigned in a finish() pass so it is global rather than per-chunk.
 */
public with sharing class OmnishiftEngineBatch implements Database.Batchable<sObject>, Database.Stateful {

    private Set<String> ownedEmails = new Set<String>();
    private Set<String> ownedNames  = new Set<String>();
    private List<User>  pool        = new List<User>();
    private Map<Id, Omnishift_Signal__c> signals = new Map<Id, Omnishift_Signal__c>();
    // What outcomes have taught us about each driver, loaded once per run.
    private Map<String, Decimal> learned = OmnishiftLearning.multipliers();
    // Who already has a next step booked. One query, not one per record.
    private Set<Id> withOpenFollowUp = new Set<Id>();
    // The marketing calendar, loaded once. Nearest upcoming send per person.
    private Map<Id, Omnishift_Marketing_Send__c> marketing =
        new Map<Id, Omnishift_Marketing_Send__c>();
    private Map<Id, Integer> load   = new Map<Id, Integer>();
    public  Integer scored = 0;
    public  Integer suppressed = 0;
    private String runId;

    // Both caps are the population this run is willing to look at in one night.
    private static final Integer SCOPE_CAP = 20000;
    private static final Integer RANK_CAP  = 5000;

    public OmnishiftEngineBatch() {
        this.runId = 'run-' + Datetime.now().format('yyyyMMdd-HHmmss');
        // Cross-reference set: who we already own as Contacts.
        for (Contact c : [SELECT Email, FirstName, LastName FROM Contact LIMIT 20000]) {
            if (c.Email != null) ownedEmails.add(c.Email.toLowerCase());
            String nm = ((c.FirstName == null ? '' : c.FirstName) + ' ' + c.LastName).trim().toLowerCase();
            if (nm != '') ownedNames.add(nm);
        }
        // The eligible owners are whoever holds the Growth Agent permission set,
        // not every Standard user. UserType = 'Standard' also matches the
        // platform accounts - Security User, Integration User - and routing a
        // prospect to one of those is worse than not routing it at all.
        Set<Id> eligible = new Set<Id>();
        for (PermissionSetAssignment psa : [
                SELECT AssigneeId FROM PermissionSetAssignment
                WHERE PermissionSet.Name = 'Omnishift_Growth_Agent_User'
                LIMIT 1000]) {
            eligible.add(psa.AssigneeId);
        }
        if (eligible.isEmpty()) eligible.add(UserInfo.getUserId());

        // One query for the whole run. Keep only the strongest signal per person:
        // most recent wins, and confidence breaks a tie on the same day.
        for (Omnishift_Signal__c sig : [
                SELECT Signal_Type__c, Occurred_On__c, Confidence__c, Source__c, Evidence__c, Detail__c,
                       Omnishift_Lead__c, Omnishift_Contact__c
                FROM Omnishift_Signal__c
                WHERE Occurred_On__c != null
                  AND Occurred_On__c >= LAST_N_DAYS:120
                ORDER BY Occurred_On__c DESC, Confidence__c DESC
                LIMIT 20000]) {
            Id key = (sig.Omnishift_Lead__c != null) ? sig.Omnishift_Lead__c : sig.Omnishift_Contact__c;
            if (key != null && !signals.containsKey(key)) signals.put(key, sig);
        }

        for (Omnishift_Marketing_Send__c ms : [
                SELECT Name, Scheduled_For__c, Omnishift_Lead__c, Omnishift_Contact__c
                FROM Omnishift_Marketing_Send__c
                WHERE Scheduled_For__c >= LAST_N_DAYS:7
                ORDER BY Scheduled_For__c ASC LIMIT 20000]) {
            Id key = (ms.Omnishift_Lead__c != null) ? ms.Omnishift_Lead__c : ms.Omnishift_Contact__c;
            if (key != null && !marketing.containsKey(key)) marketing.put(key, ms);
        }

        for (Task t : [SELECT WhoId FROM Task
                       WHERE IsClosed = false AND WhoId != null LIMIT 50000]) {
            withOpenFollowUp.add(t.WhoId);
        }

        pool = [SELECT Id, Name, State FROM User
                WHERE IsActive = true AND Id IN :eligible
                ORDER BY Name LIMIT 200];
    }

    /**
     * A QueryLocator walks one object, and both ways of covering a second one
     * cost something. Chaining a Contact run out of finish() keeps the locator,
     * but it splits the run across two jobs, so the global rank would have to be
     * assigned by whichever finished last - and a batch cannot be started from a
     * batch inside a test, so the cross-object ranking could never be exercised.
     * Handing back both populations as one iterable keeps a single scored set and
     * a single finish(), at the price of the 50,000-row ceiling an iterable
     * carries. SCOPE_CAP keeps the run under it on purpose rather than by luck.
     */
    public Iterable<sObject> start(Database.BatchableContext bc) {
        List<sObject> scope = new List<sObject>();
        scope.addAll((List<sObject>) [
            SELECT Id, FirstName, LastName, Company, Email, State, Status, LeadSource,
                   AnnualRevenue, NumberOfEmployees, Rating, Industry, DoNotCall,
                   HasOptedOutOfEmail, IsConverted, CreatedDate, LastActivityDate,
                   Omnishift_Draft_Edited__c, Omnishift_Escalated__c,
                   Omnishift_Disposition__c, Omnishift_Outcome__c, Omnishift_Next_Action_Date__c
            FROM Lead
            WHERE IsConverted = false
            LIMIT :SCOPE_CAP
        ]);
        scope.addAll((List<sObject>) contactScope());
        return scope;
    }

    /**
     * Dynamic only because of IsPersonAccount, which does not exist as a field
     * until person accounts are enabled and so cannot be named in static SOQL
     * that has to compile in an org where they are off. Person accounts are
     * excluded from scope rather than suppressed: the platform rejects DML
     * against a person account's contact row, so a suppression write would fail
     * just as a scoring write would. Their Omnishift fields would have to live on
     * the Account for that half to work at all.
     */
    private List<Contact> contactScope() {
        String soql =
            'SELECT Id, FirstName, LastName, Email, MailingState, Title, LeadSource, '
          + 'AccountId, Account.AnnualRevenue, DoNotCall, HasOptedOutOfEmail, '
          + 'CreatedDate, LastActivityDate, Omnishift_Draft_Edited__c, Omnishift_Escalated__c, '
          + 'Omnishift_Disposition__c, Omnishift_Outcome__c, Omnishift_Next_Action_Date__c FROM Contact';
        if (OmnishiftEngine.personAccountsEnabled()) soql += ' WHERE IsPersonAccount = false';
        soql += ' LIMIT ' + SCOPE_CAP;
        return (List<Contact>) Database.query(soql);
    }

    public void execute(Database.BatchableContext bc, List<sObject> scope) {
        // Large households the leadership asked to hear about, collected across
        // the chunk and notified once at the end of it.
        List<OmnishiftEscalation.Candidate> escalations = new List<OmnishiftEscalation.Candidate>();
        // Salesforce rejects DML over a list holding more than one object type,
        // so the two go into their own lists all the way to the update.
        List<Lead> leadUpdates = new List<Lead>();
        List<Contact> contactUpdates = new List<Contact>();

        for (sObject rec : scope) {
            Boolean isLead = (rec instanceof Lead);
            OmnishiftEngine.Prospect p = isLead
                ? OmnishiftEngine.fromLead((Lead) rec)
                : OmnishiftEngine.fromContact((Contact) rec);
            OmnishiftEngine.attachSignal(p, signals.get(rec.Id));
            p.hasOpenFollowUp = withOpenFollowUp.contains(rec.Id);
            Omnishift_Marketing_Send__c ms = marketing.get(rec.Id);
            if (ms != null) {
                p.marketingSendOn = ms.Scheduled_For__c.date();
                p.marketingSendName = ms.Name;
            }

            // Every Omnishift field carries the same API name on both objects, so
            // the writes below are identical once the shell is the right type.
            sObject u = isLead ? (sObject) new Lead(Id = rec.Id) : (sObject) new Contact(Id = rec.Id);
            u.put('Omnishift_Run_Id__c', runId);
            u.put('Omnishift_Scored_On__c', Datetime.now());

            OmnishiftEngine.Outcome sup = OmnishiftEngine.suppressionCheck(p, ownedEmails, ownedNames);
            if (sup.suppressed) {
                suppressed++;
                u.put('Omnishift_Score__c', 0);
                u.put('Omnishift_Rank__c', null);
                u.put('Omnishift_Why_Now__c', 'Suppressed: ' + sup.suppressReason);
                // The client raised filtered-out records as a worry of her own.
                // A suppression only she can find by reading prose is
                // indistinguishable from a record the agent never saw.
                u.put('Omnishift_Quarantined__c', true);
                u.put('Omnishift_Quarantine_Reason__c', sup.suppressReason);
                // The driver stays. A prospect held because the meeting is
                // already booked is the loop's best evidence that the reason
                // it was surfaced for converts; clearing it here threw that
                // evidence away the night after it was recorded.
                u.put('Omnishift_Next_Action_Date__c', null);
                u.put('Omnishift_Compliance_Status__c', null);
                u.put('Omnishift_Draft_Subject__c', null);
                u.put('Omnishift_Draft_Body__c', null);
                u.put('Omnishift_Recommended_Owner__c', null);
                if (isLead) leadUpdates.add((Lead) u); else contactUpdates.add((Contact) u);
                continue;
            }

            OmnishiftEngine.Outcome s = OmnishiftEngine.score(p);
            OmnishiftEngine.Outcome d = OmnishiftEngine.draft(p, s.topDriver);
            OmnishiftEngine.Outcome c = OmnishiftEngine.complianceCheck(d.draftSubject, d.draftBody);

            // Evidence adjusts the score; it does not replace the rules. The
            // multiplier is bounded and shrinks toward the firm's prior while
            // the sample is small, so a thin fortnight cannot rewrite the
            // ranking.
            Decimal mult = learned.containsKey(s.topDriver) ? learned.get(s.topDriver) : 1;
            Integer adjusted = Integer.valueOf((s.score * mult).setScale(0, System.RoundingMode.HALF_UP));
            if (adjusted > 100) adjusted = 100;
            if (adjusted < 1) adjusted = 1;
            u.put('Omnishift_Score__c', adjusted);
            // Ranking uses the uncapped figure so records that all display 100
            // still come out in a defensible order.
            u.put('Omnishift_Rank_Score__c', (s.rawScore * mult).setScale(3));
            u.put('Omnishift_Driver__c', s.topDriver);
            u.put('Omnishift_Quarantined__c', false);
            u.put('Omnishift_Quarantine_Reason__c', null);
            u.put('Omnishift_Why_Now__c', s.whyNow);
            // An advisor's edit outranks the template. Regenerating over the top of
            // it every night silently threw away their work, and made any
            // compliance verdict on an edited draft unstable from one run to the
            // next.
            Boolean edited = rec.get('Omnishift_Draft_Edited__c') == true;
            // The status and the reason are one verdict and must move together.
            // Preserving the status while rewriting the reason from the
            // regenerated template produced records reading "Blocked" above
            // "Passed all checks." - a verdict contradicting itself.
            if (!edited) {
                u.put('Omnishift_Draft_Subject__c',
                      c.draftSubject != null ? c.draftSubject : d.draftSubject);
                u.put('Omnishift_Draft_Body__c',
                      c.draftBody != null ? c.draftBody : d.draftBody);
                u.put('Omnishift_Compliance_Status__c', c.complianceStatus);
                u.put('Omnishift_Compliance_Reason__c', c.complianceReason);
            }
            u.put('Omnishift_Recommended_Owner__c', OmnishiftEngine.route(p, pool, load));
            if (OmnishiftEscalation.qualifies(p.fitValue) && rec.get('Omnishift_Escalated__c') != true) {
                escalations.add(new OmnishiftEscalation.Candidate(
                    rec.Id, p.firstName + ' ' + p.lastName, p.fitValue, s.whyNow));
            }
            // Anything scoring 50+ is worth a touch today; the rest get a nurture
            // date. A snooze the advisor set stands: "not now, come back on the
            // 14th" was being undone by the next night's run, which is the
            // fastest way to teach an advisor that the button does nothing.
            // A fresh confirmed event is the one thing that overrides it.
            Boolean snoozed = p.nextActionDate != null && p.nextActionDate > Date.today()
                && p.disposition == 'Snoozed';
            if (snoozed && !sup.surfacedEarly) {
                Boolean freshEvent = p.signalType != null && p.signalOn != null
                    && p.signalOn >= Date.today().addDays(-2) && !OmnishiftEngine.isEngagement(p.signalType);
                if (!freshEvent) u.put('Omnishift_Next_Action_Date__c', p.nextActionDate);
                else u.put('Omnishift_Next_Action_Date__c', Date.today());
            } else {
                u.put('Omnishift_Next_Action_Date__c', (s.score >= 50) ? Date.today() : Date.today().addDays(30));
            }
            scored++;
            if (isLead) leadUpdates.add((Lead) u); else contactUpdates.add((Contact) u);
        }
        if (!leadUpdates.isEmpty()) Database.update(leadUpdates, false);
        if (!contactUpdates.isEmpty()) Database.update(contactUpdates, false);
        // After the scores land, so the notification opens a scored record.
        OmnishiftEscalation.escalate(escalations);
    }

    public void finish(Database.BatchableContext bc) {
        // Global rank, assigned once the whole population is scored. It has to be
        // one merged ordering across both objects: two records sharing rank 1 is
        // the fastest way to make an advisor stop trusting the queue.
        List<Ranked> all = new List<Ranked>();
        for (Lead l : [
                SELECT Id, Omnishift_Score__c, Omnishift_Rank_Score__c, CreatedDate FROM Lead
                WHERE Omnishift_Score__c > 0 AND IsConverted = false
                ORDER BY Omnishift_Score__c DESC, CreatedDate ASC
                LIMIT :RANK_CAP]) {
            all.add(new Ranked(l.Id, l.Omnishift_Rank_Score__c != null ? l.Omnishift_Rank_Score__c : l.Omnishift_Score__c, l.CreatedDate));
        }
        for (Contact c : [
                SELECT Id, Omnishift_Score__c, Omnishift_Rank_Score__c, CreatedDate FROM Contact
                WHERE Omnishift_Score__c > 0
                ORDER BY Omnishift_Score__c DESC, CreatedDate ASC
                LIMIT :RANK_CAP]) {
            all.add(new Ranked(c.Id, c.Omnishift_Rank_Score__c != null ? c.Omnishift_Rank_Score__c : c.Omnishift_Score__c, c.CreatedDate));
        }
        all.sort();

        List<Lead> leadRanks = new List<Lead>();
        List<Contact> contactRanks = new List<Contact>();
        Integer i = 1;
        for (Ranked r : all) {
            if (i > RANK_CAP) break;
            if (r.recordId.getSObjectType() == Lead.SObjectType) {
                leadRanks.add(new Lead(Id = r.recordId, Omnishift_Rank__c = i));
            } else {
                contactRanks.add(new Contact(Id = r.recordId, Omnishift_Rank__c = i));
            }
            i++;
        }
        if (!leadRanks.isEmpty()) Database.update(leadRanks, false);
        if (!contactRanks.isEmpty()) Database.update(contactRanks, false);
    }

    private class Ranked implements Comparable {
        private Id recordId;
        private Decimal score;
        private Datetime created;
        private Ranked(Id recordId, Decimal score, Datetime created) {
            this.recordId = recordId; this.score = score; this.created = created;
        }
        public Integer compareTo(Object other) {
            Ranked r = (Ranked) other;
            if (score != r.score) return (score > r.score) ? -1 : 1;
            if (created != r.created) return (created < r.created) ? -1 : 1;
            // Records loaded in the same second are common in a seeded org. With
            // no final tie-break their order is whatever the two queries happened
            // to return, and the same Lead and Contact would swap rank nightly
            // for no reason an advisor could explain.
            return String.valueOf(recordId).compareTo(String.valueOf(r.recordId));
        }
    }

    /** Kick the run off from a button or the developer console. */
    @AuraEnabled
    public static String runNow() {
        Id jobId = Database.executeBatch(new OmnishiftEngineBatch(), 200);
        return jobId;
    }
}
