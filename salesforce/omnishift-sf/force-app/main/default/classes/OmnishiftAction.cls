/**
 * Closes the loop on a recommendation.
 *
 * The panel used to write the disposition and stop there, which meant an
 * approved draft left no trace on the record and a snoozed lead came back the
 * next morning. Everything a disposition implies now happens in one
 * transaction: the audit activity, the next action date, and the queue exit.
 */
public with sharing class OmnishiftAction {

    public class ActionException extends Exception {}

        private static String recordDispositionImpl(Id recordId, String disposition, String reason,
                                           String subject, String body, Date snoozeUntil) {
        if (recordId == null || String.isBlank(disposition)) {
            throw new ActionException('A record and a disposition are both required.');
        }

        String sObj = recordId.getSObjectType().getDescribe().getName();
        if (sObj != 'Lead' && sObj != 'Contact') {
            throw new ActionException('The Growth Agent only dispositions Leads and Contacts.');
        }

        SObject rec = Schema.getGlobalDescribe().get(sObj).newSObject(recordId);
        rec.put('Omnishift_Disposition__c', disposition);
        // Nothing else records when the advisor acted. LastModifiedDate cannot
        // stand in for it, because the nightly run rewrites that on every record.
        rec.put('Omnishift_Dispositioned_On__c', Datetime.now());
        if (String.isNotBlank(reason)) rec.put('Omnishift_Disposition_Reason__c', reason);

        // The next action date is what the Today queue filters on, so it is the
        // field that decides whether this record comes back tomorrow.
        if (disposition == 'Snoozed') {
            // The advisor knows when to come back better than a constant does. A
            // week is only the fallback when they express no preference.
            Date returnOn = (snoozeUntil != null && snoozeUntil > Date.today())
                ? snoozeUntil
                : Date.today().addDays(7);
            rec.put('Omnishift_Next_Action_Date__c', returnOn);
        } else if (disposition == 'Wrong person') {
            rec.put('Omnishift_Next_Action_Date__c', null);
        } else {
            rec.put('Omnishift_Next_Action_Date__c', null);
        }

        List<Task> log = new List<Task>();
        if (disposition == 'Approved and sent' || disposition == 'Edited before send') {
            log.add(buildTask(recordId, sObj, 'Email',
                String.isBlank(subject) ? 'Growth Agent outreach' : subject,
                buildBody(disposition, body)));
        } else if (disposition == 'Call logged') {
            log.add(buildTask(recordId, sObj, 'Call', 'Growth Agent call',
                String.isBlank(reason) ? 'Call logged from the Growth Agent panel.' : reason));
        }

        if (!log.isEmpty()) {
            if (!Schema.sObjectType.Task.isCreateable()) {
                throw new ActionException('You do not have permission to log activities.');
            }
            insert log;
        }

        if (!canUpdate(sObj)) {
            throw new ActionException('You do not have permission to update this record.');
        }
        // The standard record moves with the agent's record. A prospect who has
        // just been emailed or called is no longer "Open - Not Contacted", and
        // the Path at the top of the page should say so without a second click.
        if (sObj == 'Lead' && (disposition == 'Approved and sent' || disposition == 'Edited before send'
                || disposition == 'Call logged')) {
            Lead cur = [SELECT Status FROM Lead WHERE Id = :recordId LIMIT 1];
            if (cur.Status == 'Open - Not Contacted') rec.put('Status', 'Working - Contacted');
        }
        update rec;

        if (disposition != 'Snoozed') return 'Logged as ' + disposition.toLowerCase();
        Date shown = (snoozeUntil != null && snoozeUntil > Date.today())
            ? snoozeUntil : Date.today().addDays(7);
        return 'Snoozed until ' + shown.format();
    }

    private static Task buildTask(Id recordId, String sObj, String type, String subject, String body) {
        Task t = new Task(
            Subject      = subject,
            Description  = body,
            Type         = type,
            Status       = 'Completed',
            Priority     = 'Normal',
            ActivityDate = Date.today(),
            OwnerId      = UserInfo.getUserId()
        );
        // WhoId takes both Lead and Contact ids. WhatId does not accept a Lead,
        // which is the same constraint that rules EmailMessage out here.
        t.WhoId = recordId;
        return t;
    }

    private static String buildBody(String disposition, String body) {
        String prefix = disposition == 'Edited before send'
            ? 'Sent from the Growth Agent panel, edited by the advisor before sending.\n\n'
            : 'Sent from the Growth Agent panel, approved as drafted.\n\n';
        return prefix + (String.isBlank(body) ? '' : body);
    }

    private static Boolean canUpdate(String sObj) {
        Map<String, Schema.SObjectField> f = Schema.getGlobalDescribe().get(sObj)
            .getDescribe().fields.getMap();
        return f.get('Omnishift_Disposition__c').getDescribe().isUpdateable()
            && f.get('Omnishift_Next_Action_Date__c').getDescribe().isUpdateable();
    }

    /**
     * Persists an advisor's edit to the draft.
     *
     * Compliance re-runs here rather than only on the nightly text: the whole
     * point of an editable draft is that a human can put something in it that
     * the generated template never would.
     */
        private static Map<String, Object> saveDraftImpl(Id recordId, String subject, String body) {
        assertSupported(recordId);
        if (String.isBlank(subject) || String.isBlank(body)) {
            throw new ActionException('A draft needs both a subject and a body.');
        }

        OmnishiftEngine.Outcome c = OmnishiftEngine.complianceCheck(subject, body);
        // Auto-correct hands back cleaned text; take it so what is stored is what
        // was checked.
        String finalSubject = (c.draftSubject != null) ? c.draftSubject : subject;
        String finalBody    = (c.draftBody    != null) ? c.draftBody    : body;

        String sObj = recordId.getSObjectType().getDescribe().getName();
        SObject rec = Schema.getGlobalDescribe().get(sObj).newSObject(recordId);
        rec.put('Omnishift_Draft_Subject__c', finalSubject);
        rec.put('Omnishift_Draft_Body__c', finalBody);
        rec.put('Omnishift_Compliance_Status__c', c.complianceStatus);
        rec.put('Omnishift_Compliance_Reason__c', c.complianceReason);
        // Tells the nightly run to leave this draft alone.
        rec.put('Omnishift_Draft_Edited__c', true);
        update rec;

        return new Map<String, Object>{
            'subject'    => finalSubject,
            'body'       => finalBody,
            'status'     => c.complianceStatus,
            'reason'     => c.complianceReason,
            'blocked'    => c.complianceStatus == 'Blocked'
        };
    }

    /**
     * Sends the draft, or records it without sending when live email is off.
     *
     * Omnishift_Config__mdt.Send_Live_Email__c is false everywhere until the firm
     * has settled archiving and deliverability, so the default behaviour is to
     * produce the audit trail without putting anything in a prospect's inbox.
     */
        private static String sendDraftImpl(Id recordId, String subject, String body, Boolean wasEdited) {
        assertSupported(recordId);

        // Never send text that has not just been checked. An advisor can edit in a
        // violation between the nightly run and the click.
        OmnishiftEngine.Outcome c = OmnishiftEngine.complianceCheck(subject, body);
        if (c.complianceStatus == 'Blocked') {
            throw new ActionException('Cannot send. ' + c.complianceReason);
        }
        String outSubject = (c.draftSubject != null) ? c.draftSubject : subject;
        String outBody    = (c.draftBody    != null) ? c.draftBody    : body;

        Boolean live = liveEmailEnabled();
        String disposition = (wasEdited == true) ? 'Edited before send' : 'Approved and sent';

        if (live) {
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setTargetObjectId(recordId);     // accepts Lead and Contact
            m.setSaveAsActivity(true);         // Salesforce writes the activity itself
            m.setSubject(outSubject);
            m.setPlainTextBody(outBody);
            m.setTreatTargetObjectAsRecipient(true);
            List<Messaging.SendEmailResult> res =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m }, false);
            if (!res.isEmpty() && !res[0].isSuccess()) {
                String why = res[0].getErrors().isEmpty()
                    ? 'unknown error' : res[0].getErrors()[0].getMessage();
                throw new ActionException('Salesforce refused the send: ' + why);
            }
            recordDispositionImpl(recordId, disposition, null, null, null, null);
            return 'Sent to the prospect and logged.';
        }

        // Not live: recordDisposition writes the Task that is the audit trail.
        recordDispositionImpl(recordId, disposition, null, outSubject, outBody, null);
        return 'Recorded as ' + disposition.toLowerCase()
             + '. Live email is off in this org, so nothing left Salesforce.';
    }

    @AuraEnabled(cacheable=true)
    public static Boolean liveEmailEnabled() {
        Omnishift_Config__mdt cfg = Omnishift_Config__mdt.getInstance('Default');
        return cfg != null && cfg.Send_Live_Email__c == true;
    }

    private static void assertSupported(Id recordId) {
        if (recordId == null) throw new ActionException('A record is required.');
        String sObj = recordId.getSObjectType().getDescribe().getName();
        if (sObj != 'Lead' && sObj != 'Contact') {
            throw new ActionException('The Growth Agent only works Leads and Contacts.');
        }
    }

    // ---- entry points ------------------------------------------------------
    // AuraHandledException can only be thrown from an Aura or Visualforce
    // context, which made the rules above impossible to exercise from a test or
    // from anonymous Apex. The logic raises ActionException; only these three
    // wrappers translate it into something the UI can display.

    @AuraEnabled
    public static String recordDisposition(Id recordId, String disposition, String reason,
                                           String subject, String body, Date snoozeUntil) {
        try {
            return recordDispositionImpl(recordId, disposition, reason, subject, body, snoozeUntil);
        } catch (ActionException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> saveDraft(Id recordId, String subject, String body) {
        try {
            return saveDraftImpl(recordId, subject, body);
        } catch (ActionException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String sendDraft(Id recordId, String subject, String body, Boolean wasEdited) {
        try {
            return sendDraftImpl(recordId, subject, body, wasEdited);
        } catch (ActionException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @TestVisible
    private static String sendDraftForTest(Id recordId, String subject, String body, Boolean edited) {
        return sendDraftImpl(recordId, subject, body, edited);
    }
    @TestVisible
    private static Map<String, Object> saveDraftForTest(Id recordId, String subject, String body) {
        return saveDraftImpl(recordId, subject, body);
    }
    @TestVisible
    private static String dispositionForTest(Id recordId, String d, String r, String s2, String b) {
        return recordDispositionImpl(recordId, d, r, s2, b, null);
    }
    @TestVisible
    private static String snoozeForTest(Id recordId, Date until) {
        return recordDispositionImpl(recordId, 'Snoozed', null, null, null, until);
    }

    /**
     * Whether this org has Person Accounts turned on.
     *
     * Contact.IsPersonAccount only exists when it does. The panel was asking for
     * it on every Contact, so getRecord failed on all of them and reported a
     * field-level-security problem that was not the cause.
     */
    /**
     * The signal trail behind a recommendation.
     *
     * The panel shows where each piece of evidence came from, because an advisor
     * about to call someone deserves to know whether the reason is a public
     * filing or a pattern of visits to the website - and how sure the provider is.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getSignals(Id recordId) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (recordId == null) return out;
        String sObj = recordId.getSObjectType().getDescribe().getName();
        List<Omnishift_Signal__c> sigs = (sObj == 'Contact')
            ? [SELECT Signal_Type__c, Occurred_On__c, Observed_On__c, Confidence__c,
                      Source__c, Source_System__c, Detail__c, Evidence__c, External_Id__c
               FROM Omnishift_Signal__c WHERE Omnishift_Contact__c = :recordId
               ORDER BY Occurred_On__c DESC LIMIT 10]
            : [SELECT Signal_Type__c, Occurred_On__c, Observed_On__c, Confidence__c,
                      Source__c, Source_System__c, Detail__c, Evidence__c, External_Id__c
               FROM Omnishift_Signal__c WHERE Omnishift_Lead__c = :recordId
               ORDER BY Occurred_On__c DESC LIMIT 10];
        for (Omnishift_Signal__c g : sigs) {
            Integer ageDays = (g.Occurred_On__c == null)
                ? null : g.Occurred_On__c.daysBetween(Date.today());
            // How long the feed took to tell us. Being early is the whole
            // proposition, so the lag is worth showing rather than hiding.
            String lag = '';
            if (g.Observed_On__c != null && g.Occurred_On__c != null) {
                // Occurred_On__c is a Date, so it has to be lifted to a Datetime
                // before the two can be subtracted.
                Datetime occurredAt =
                    Datetime.newInstance(g.Occurred_On__c, Time.newInstance(0, 0, 0, 0));
                Integer h = Integer.valueOf(
                    (g.Observed_On__c.getTime() - occurredAt.getTime()) / 3600000);
                lag = (h < 24) ? h + 'h after the event'
                    : (h / 24) + 'd after the event';
            }
            out.add(new Map<String, Object>{
                'type'       => g.Signal_Type__c,
                'source'     => String.isBlank(g.Source_System__c) ? g.Source__c : g.Source_System__c,
                'evidence'   => g.Evidence__c,
                'externalId' => g.External_Id__c,
                'lag'        => lag,
                'detail'     => g.Detail__c,
                'confidence' => g.Confidence__c == null ? null : g.Confidence__c.setScale(0),
                'occurredOn' => g.Occurred_On__c,
                'age'        => ageDays == null ? '' :
                                ageDays == 0 ? 'today' :
                                ageDays == 1 ? 'yesterday' : ageDays + ' days ago'
            });
        }
        return out;
    }

    /**
     * The morning briefing: what the last run produced, across both objects.
     *
     * Every number is counted from the records themselves rather than stored, so
     * it cannot drift from what the queue and the panels show.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getBriefing() {
        Integer dueLeads = [SELECT COUNT() FROM Lead
                            WHERE Omnishift_Next_Action_Date__c <= TODAY AND IsConverted = false];
        Integer dueCons  = [SELECT COUNT() FROM Contact WHERE Omnishift_Next_Action_Date__c <= TODAY];
        Integer blocked  = [SELECT COUNT() FROM Lead WHERE Omnishift_Compliance_Status__c = 'Blocked']
                         + [SELECT COUNT() FROM Contact WHERE Omnishift_Compliance_Status__c = 'Blocked'];
        Integer worked   = [SELECT COUNT() FROM Lead WHERE Omnishift_Dispositioned_On__c = TODAY]
                         + [SELECT COUNT() FROM Contact WHERE Omnishift_Dispositioned_On__c = TODAY];
        Integer suppressed = [SELECT COUNT() FROM Lead
                              WHERE Omnishift_Score__c = 0 AND IsConverted = false];

        // Signal provenance, which is the part a prospective client asks about.
        Map<String, Integer> bySource = new Map<String, Integer>();
        for (AggregateResult ar : [SELECT Source__c src, COUNT(Id) n FROM Omnishift_Signal__c
                                   WHERE Occurred_On__c >= LAST_N_DAYS:120 GROUP BY Source__c]) {
            bySource.put((String) ar.get('src'), (Integer) ar.get('n'));
        }
        List<Map<String, Object>> sources = new List<Map<String, Object>>();
        for (String k : bySource.keySet()) {
            sources.add(new Map<String, Object>{ 'name' => k, 'count' => bySource.get(k) });
        }

        String runId;
        Datetime scoredOn;
        for (Lead l : [SELECT Omnishift_Run_Id__c, Omnishift_Scored_On__c FROM Lead
                       WHERE Omnishift_Scored_On__c != null
                       ORDER BY Omnishift_Scored_On__c DESC LIMIT 1]) {
            runId = l.Omnishift_Run_Id__c;
            scoredOn = l.Omnishift_Scored_On__c;
        }

        return new Map<String, Object>{
            'due'        => dueLeads + dueCons,
            'dueLeads'   => dueLeads,
            'dueContacts'=> dueCons,
            'blocked'    => blocked,
            'worked'     => worked,
            'suppressed' => suppressed,
            'sources'    => sources,
            'runId'      => runId,
            'scoredOn'   => scoredOn
        };
    }

    /**
     * Records what happened with the prospect, which is the label the ranking
     * learns from. Kept separate from the disposition on purpose: "edited before
     * send" says what the advisor did with the draft, and says nothing at all
     * about whether surfacing the person was right.
     */
    @AuraEnabled
    public static String recordOutcome(Id recordId, String outcome) {
        try {
            if (recordId == null || String.isBlank(outcome)) {
                throw new ActionException('A record and an outcome are both required.');
            }
            String sObj = recordId.getSObjectType().getDescribe().getName();
            if (sObj != 'Lead' && sObj != 'Contact') {
                throw new ActionException('The Growth Agent only works Leads and Contacts.');
            }
            SObject rec = Schema.getGlobalDescribe().get(sObj).newSObject(recordId);
            rec.put('Omnishift_Outcome__c', outcome);
            rec.put('Omnishift_Outcome_On__c', Datetime.now());
            if (outcome == 'Meeting booked' || outcome == 'Not interested'
                || outcome == 'Should not have been surfaced') {
                rec.put('Omnishift_Next_Action_Date__c', null);
            }
            update rec;
            return outcome == 'Meeting booked'
                ? 'Meeting booked. That is the outcome the ranking learns from.'
                : 'Recorded as ' + outcome.toLowerCase() + '.';
        } catch (ActionException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @TestVisible
    private static String outcomeForTest(Id recordId, String outcome) {
        SObject rec = Schema.getGlobalDescribe()
            .get(recordId.getSObjectType().getDescribe().getName()).newSObject(recordId);
        rec.put('Omnishift_Outcome__c', outcome);
        rec.put('Omnishift_Outcome_On__c', Datetime.now());
        update rec;
        return outcome;
    }

    /**
     * Engagement history: every touch the firm knows about, in one order.
     *
     * Deana pointed at the Pardot tab - "so we can see their engagement history"
     * - and said the Omnishift tab should be that "with more information". The
     * signals showed the external feeds; this merges them with what Salesforce
     * itself holds (activities, dispositions, outcomes) and with what marketing
     * has scheduled, so the advisor sees one timeline rather than four tabs.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getTimeline(Id recordId) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (recordId == null) return out;
        String sObj = recordId.getSObjectType().getDescribe().getName();
        Boolean isLead = (sObj == 'Lead');

        // 1. external signals, via the same query the panel already trusts
        for (Map<String, Object> g : getSignals(recordId)) {
            // 'on' is reserved in Apex - it is the trigger keyword.
            Date occurred = (Date) g.get('occurredOn');
            out.add(row(occurred == null ? null : Datetime.newInstance(occurred, Time.newInstance(9,0,0,0)),
                        'signal', (String) g.get('source'), (String) g.get('type'),
                        (String) g.get('detail'), g.get('confidence') == null ? '' :
                        g.get('confidence') + '% confidence', false));
        }
        // 2. marketing calendar - past sends as history, future ones as a warning
        List<Omnishift_Marketing_Send__c> ms = isLead
            ? [SELECT Name, Scheduled_For__c, Campaign_Type__c, Audience__c, Source_System__c
               FROM Omnishift_Marketing_Send__c WHERE Omnishift_Lead__c = :recordId
               ORDER BY Scheduled_For__c DESC LIMIT 20]
            : [SELECT Name, Scheduled_For__c, Campaign_Type__c, Audience__c, Source_System__c
               FROM Omnishift_Marketing_Send__c WHERE Omnishift_Contact__c = :recordId
               ORDER BY Scheduled_For__c DESC LIMIT 20];
        for (Omnishift_Marketing_Send__c m : ms) {
            Boolean future = m.Scheduled_For__c > Datetime.now();
            out.add(row(m.Scheduled_For__c, 'marketing', m.Source_System__c, m.Name,
                        (future ? 'Scheduled. ' : 'Sent. ') + m.Campaign_Type__c
                        + ' to ' + m.Audience__c + '.', future ? 'upcoming' : '', future));
        }
        // 3. what the firm itself did
        for (Task t : [SELECT Subject, Type, Status, ActivityDate, Description, CreatedDate,
                              Owner.Name
                       FROM Task WHERE WhoId = :recordId ORDER BY CreatedDate DESC LIMIT 30]) {
            Datetime at = t.ActivityDate != null
                ? Datetime.newInstance(t.ActivityDate, Time.newInstance(12,0,0,0)) : t.CreatedDate;
            // Seeded activity does not always carry a Type; the subject says
            // what it was, and "Activity:" says nothing.
            String kind = t.Type;
            if (String.isBlank(kind)) {
                String s = t.Subject == null ? '' : t.Subject.toLowerCase();
                kind = s.contains('call') ? 'Call' : (s.contains('email') || s.contains('note') || s.contains('question') || s.contains('conversation') || s.contains('timing')) ? 'Email' : 'Activity';
            }
            out.add(row(at, 'activity', 'Salesforce',
                        kind + ': ' + t.Subject,
                        String.isBlank(t.Description) ? t.Status : t.Description.left(220),
                        t.Owner.Name, false));
        }
        // 4. the agent's own trail
        SObject rec = Database.query('SELECT Omnishift_Scored_On__c, Omnishift_Run_Id__c, '
            + 'Omnishift_Driver__c, Omnishift_Disposition__c, Omnishift_Dispositioned_On__c, '
            + 'Omnishift_Outcome__c, Omnishift_Outcome_On__c, Omnishift_Escalated__c, '
            + 'Omnishift_Escalated_On__c FROM ' + sObj + ' WHERE Id = :recordId LIMIT 1');
        if (rec.get('Omnishift_Scored_On__c') != null) {
            out.add(row((Datetime) rec.get('Omnishift_Scored_On__c'), 'agent', 'Omnishift',
                        'Surfaced by the agent', 'Driver: ' + rec.get('Omnishift_Driver__c') + '.',
                        'run ' + rec.get('Omnishift_Run_Id__c'), false));
        }
        if (rec.get('Omnishift_Dispositioned_On__c') != null) {
            out.add(row((Datetime) rec.get('Omnishift_Dispositioned_On__c'), 'agent', 'Omnishift',
                        'Advisor: ' + rec.get('Omnishift_Disposition__c'), '', '', false));
        }
        if (rec.get('Omnishift_Outcome_On__c') != null) {
            out.add(row((Datetime) rec.get('Omnishift_Outcome_On__c'), 'outcome', 'Omnishift',
                        'Outcome: ' + rec.get('Omnishift_Outcome__c'), '', '', false));
        }
        if (rec.get('Omnishift_Escalated_On__c') != null) {
            out.add(row((Datetime) rec.get('Omnishift_Escalated_On__c'), 'agent', 'Omnishift',
                        'Escalated to leadership', 'High-value household surfaced.', '', false));
        }
        // newest first, undated last
        List<TimelineRow> sortable = new List<TimelineRow>();
        for (Map<String, Object> r : out) sortable.add(new TimelineRow(r));
        sortable.sort();
        List<Map<String, Object>> sorted = new List<Map<String, Object>>();
        for (TimelineRow r : sortable) sorted.add(r.data);
        return sorted;
    }

    private static Map<String, Object> row(Datetime at, String kind, String source, String title,
                                           String detail, String meta, Boolean upcoming) {
        return new Map<String, Object>{
            'at' => at, 'kind' => kind, 'source' => source, 'title' => title,
            'detail' => detail, 'meta' => meta, 'upcoming' => upcoming,
            'when' => at == null ? '' : at.format('d MMM yyyy')
        };
    }
    private class TimelineRow implements Comparable {
        public Map<String, Object> data;
        TimelineRow(Map<String, Object> d) { data = d; }
        public Integer compareTo(Object o) {
            Datetime a = (Datetime) data.get('at'), b = (Datetime) ((TimelineRow) o).data.get('at');
            if (a == null && b == null) return 0;
            if (a == null) return 1;
            if (b == null) return -1;
            return a > b ? -1 : (a < b ? 1 : 0);
        }
    }

    /**
     * The marketing calendar, as Account Engagement shows it and as Deana had it
     * on screen: a week grid of scheduled sends. Here it also carries what the
     * agent did about each send - how many people it held back so the firm does
     * not arrive twice in one inbox.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getCalendar(Date weekStart) {
        Date start = (weekStart == null) ? Date.today().toStartOfWeek() : weekStart;
        Date stop = start.addDays(7);
        // from, to and like are SOQL keywords and cannot name variables.
        Datetime windowStart = Datetime.newInstance(start, Time.newInstance(0,0,0,0));
        Datetime windowEnd = Datetime.newInstance(stop, Time.newInstance(0,0,0,0));

        // group by send name + day: one calendar entry per campaign per day
        Map<String, Map<String, Object>> entries = new Map<String, Map<String, Object>>();
        for (Omnishift_Marketing_Send__c m : [
                SELECT Name, Scheduled_For__c, Campaign_Type__c, Audience__c, Source_System__c,
                       Omnishift_Lead__c, Omnishift_Lead__r.Name, Omnishift_Lead__r.Omnishift_Quarantine_Reason__c,
                       Omnishift_Contact__c, Omnishift_Contact__r.Name, Omnishift_Contact__r.Omnishift_Quarantine_Reason__c
                FROM Omnishift_Marketing_Send__c
                WHERE Scheduled_For__c >= :windowStart AND Scheduled_For__c < :windowEnd
                ORDER BY Scheduled_For__c LIMIT 2000]) {
            Date d = m.Scheduled_For__c.date();
            String key = d.format() + '|' + m.Name;
            Map<String, Object> e = entries.get(key);
            if (e == null) {
                e = new Map<String, Object>{
                    'key' => key, 'name' => m.Name, 'day' => d,
                    'dayIndex' => start.daysBetween(d),
                    'time' => m.Scheduled_For__c.format('h:mma').toLowerCase(),
                    'type' => m.Campaign_Type__c, 'audience' => m.Audience__c,
                    'source' => m.Source_System__c, 'people' => 0, 'deferred' => 0,
                    'recipients' => new List<Map<String, Object>>()
                };
                entries.put(key, e);
            }
            e.put('people', (Integer) e.get('people') + 1);
            // Who is on the send, so the calendar entry can open to the people
            // behind the count and each one to the record.
            Boolean isLead = m.Omnishift_Lead__c != null;
            String heldReason = isLead ? m.Omnishift_Lead__r.Omnishift_Quarantine_Reason__c
                                       : m.Omnishift_Contact__r.Omnishift_Quarantine_Reason__c;
            if (isLead || m.Omnishift_Contact__c != null) {
                ((List<Map<String, Object>>) e.get('recipients')).add(new Map<String, Object>{
                    'id' => isLead ? m.Omnishift_Lead__c : m.Omnishift_Contact__c,
                    'name' => isLead ? m.Omnishift_Lead__r.Name : m.Omnishift_Contact__r.Name,
                    'objectApiName' => isLead ? 'Lead' : 'Contact',
                    'held' => heldReason != null && heldReason.contains('"' + m.Name + '"')
                });
            }
        }
        // How many the agent held back for each send. One query per object,
        // counted in memory - the previous version ran two COUNT queries per
        // calendar entry, which is what made the Home page slow to open.
        Map<String, Integer> heldByName = new Map<String, Integer>();
        for (String obj : new List<String>{ 'Lead', 'Contact' }) {
            for (sObject r : Database.query('SELECT Omnishift_Quarantine_Reason__c FROM ' + obj
                    + ' WHERE Omnishift_Quarantined__c = true LIMIT 5000')) {
                String reason = (String) r.get('Omnishift_Quarantine_Reason__c');
                if (reason == null) continue;
                for (String key : entries.keySet()) {
                    String nm = (String) entries.get(key).get('name');
                    if (reason.contains('"' + nm + '"')) {
                        heldByName.put(nm, (heldByName.containsKey(nm) ? heldByName.get(nm) : 0) + 1);
                    }
                }
            }
        }
        for (String key : entries.keySet()) {
            String nm = (String) entries.get(key).get('name');
            entries.get(key).put('deferred', heldByName.containsKey(nm) ? heldByName.get(nm) : 0);
        }
        return entries.values();
    }

    /**
     * Everything the panel needs that is not on the record itself, in one round
     * trip. It was four: person-account support, the live-email switch, the
     * signals, the timeline - each a separate server call before the panel
     * could settle. The timeline already contains the signals.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPanelContext(Id recordId) {
        return new Map<String, Object>{
            'personAccounts' => personAccountsEnabled(),
            'liveEmail'      => liveEmailEnabled(),
            'timeline'       => getTimeline(recordId)
        };
    }

    @AuraEnabled(cacheable=true)
    public static Boolean personAccountsEnabled() {
        return OmnishiftEngine.personAccountsEnabled();
    }
}
