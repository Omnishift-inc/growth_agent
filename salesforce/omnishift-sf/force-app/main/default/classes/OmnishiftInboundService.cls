/**
 * Scores a newly arrived record immediately.
 *
 * The firm runs a stated SLA: "the client associate team should get to this
 * lead within under five minutes." A job at 02:00 cannot serve that - it was
 * writing "the stated SLA is a response inside five minutes" onto records it
 * would not surface for another seventeen hours.
 *
 * The nightly run still does the full re-rank across everything, because a
 * global rank needs the whole population. This only puts a new arrival on the
 * board straight away, with the reason and the draft already there.
 */
public with sharing class OmnishiftInboundService {

    // Only intake channels the firm actually holds an SLA on. Scoring every
    // insert would put the batch's work in the path of every data load.
    private static final Set<String> URGENT_SOURCES = new Set<String>{
        'Web', 'Referral', 'Partner Referral', 'Employee Referral'
    };

    public static void scoreNew(List<Lead> newLeads) {
        List<Id> urgent = new List<Id>();
        for (Lead l : newLeads) {
            if (l.IsConverted) continue;
            if (l.LeadSource != null && URGENT_SOURCES.contains(l.LeadSource)) urgent.add(l.Id);
        }
        if (urgent.isEmpty()) return;
        // Asynchronous: the form submission should not wait on our scoring, and
        // a trigger that throws must never be the reason a lead is lost.
        scoreAsync(urgent);
    }

    @future
    public static void scoreAsync(List<Id> leadIds) {
        try {
            List<Lead> ls = [
                SELECT Id, FirstName, LastName, Company, Email, State, Status, LeadSource,
                       AnnualRevenue, NumberOfEmployees, Rating, Industry, DoNotCall,
                       HasOptedOutOfEmail, IsConverted, CreatedDate, LastActivityDate,
                       Omnishift_Draft_Edited__c, Omnishift_Escalated__c
                FROM Lead WHERE Id IN :leadIds AND IsConverted = false];
            if (ls.isEmpty()) return;

            List<User> pool = [SELECT Id, Name, State FROM User
                               WHERE IsActive = true AND Id IN (
                                   SELECT AssigneeId FROM PermissionSetAssignment
                                   WHERE PermissionSet.Name = 'Omnishift_Growth_Agent_User')
                               ORDER BY Name LIMIT 200];
            Map<Id, Integer> load = new Map<Id, Integer>();
            Map<String, Decimal> learned = OmnishiftLearning.multipliers();
            String runId = 'inbound-' + Datetime.now().format('yyyyMMdd-HHmmss');

            List<Lead> updates = new List<Lead>();
            List<OmnishiftEscalation.Candidate> escalations = new List<OmnishiftEscalation.Candidate>();
            for (Lead l : ls) {
                OmnishiftEngine.Prospect p = OmnishiftEngine.fromLead(l);
                OmnishiftEngine.Outcome sup =
                    OmnishiftEngine.suppressionCheck(p, new Set<String>(), new Set<String>());
                Lead u = new Lead(Id = l.Id);
                u.Omnishift_Run_Id__c = runId;
                u.Omnishift_Scored_On__c = Datetime.now();
                if (sup.suppressed) {
                    u.Omnishift_Quarantined__c = true;
                    u.Omnishift_Quarantine_Reason__c = sup.suppressReason;
                    u.Omnishift_Why_Now__c = 'Suppressed: ' + sup.suppressReason;
                    updates.add(u);
                    continue;
                }
                OmnishiftEngine.Outcome s = OmnishiftEngine.score(p);
                OmnishiftEngine.Outcome d = OmnishiftEngine.draft(p, s.topDriver);
                OmnishiftEngine.Outcome c = OmnishiftEngine.complianceCheck(d.draftSubject, d.draftBody);

                Decimal mult = learned.containsKey(s.topDriver) ? learned.get(s.topDriver) : 1;
                Integer adjusted = Integer.valueOf((s.score * mult).setScale(0, System.RoundingMode.HALF_UP));
                if (adjusted > 100) adjusted = 100;
                if (adjusted < 1) adjusted = 1;

                u.Omnishift_Score__c = adjusted;
                u.Omnishift_Driver__c = s.topDriver;
                u.Omnishift_Why_Now__c = s.whyNow;
                // Same rule as the nightly run: an advisor's edit outranks the
                // template. Without this the immediate scoring would regenerate
                // over an edit made seconds earlier and reset its verdict.
                if (l.Omnishift_Draft_Edited__c != true) {
                    u.Omnishift_Draft_Subject__c = (c.draftSubject != null) ? c.draftSubject : d.draftSubject;
                    u.Omnishift_Draft_Body__c = (c.draftBody != null) ? c.draftBody : d.draftBody;
                    u.Omnishift_Compliance_Status__c = c.complianceStatus;
                    u.Omnishift_Compliance_Reason__c = c.complianceReason;
                }
                u.Omnishift_Recommended_Owner__c = OmnishiftEngine.route(p, pool, load);
                if (OmnishiftEscalation.qualifies(p.fitValue) && l.Omnishift_Escalated__c != true) {
                    escalations.add(new OmnishiftEscalation.Candidate(
                        l.Id, p.firstName + ' ' + p.lastName, p.fitValue, s.whyNow));
                }
                u.Omnishift_Quarantined__c = false;
                // On the board today. The nightly run assigns the global rank;
                // until then it sits unranked at the top of the queue rather
                // than waiting seventeen hours for a number.
                u.Omnishift_Next_Action_Date__c = Date.today();
                updates.add(u);
            }
            if (!updates.isEmpty()) Database.update(updates, false);
            OmnishiftEscalation.escalate(escalations);
        } catch (Exception e) {
            // A scoring failure must never be why a lead is lost. Record it and
            // let the nightly run pick the record up.
            System.debug(LoggingLevel.ERROR, 'Omnishift inbound scoring failed: ' + e.getMessage());
        }
    }
}
