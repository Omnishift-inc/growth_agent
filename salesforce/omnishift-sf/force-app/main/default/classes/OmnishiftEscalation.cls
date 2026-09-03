/**
 * Tells the people who take a second look when a large household surfaces.
 *
 * Tom, on the call: "In the event that there is higher levels of assets
 * included, that's usually when we would loop in John and Deana." Gevorg
 * confirmed the shape - above a threshold, they get a notification. Until now
 * the threshold only raised the score, which tells the advisor and nobody else.
 *
 * Recipients are whoever holds the Manager permission set, so the firm decides
 * who "John and Deana" are without a code change. Fires once per record.
 */
public with sharing class OmnishiftEscalation {

    // The number Gevorg used on the call and nobody corrected.
    public static final Decimal THRESHOLD = 10000000;

    private static final String NOTIF_TYPE = 'Omnishift_High_Value_Prospect';
    private static final String MANAGER_SET = 'Omnishift_Growth_Agent_Manager';

    public class Candidate {
        public Id recordId;
        public String name;
        public Decimal fitValue;
        public String whyNow;
        public Candidate(Id recordId, String name, Decimal fitValue, String whyNow) {
            this.recordId = recordId; this.name = name; this.fitValue = fitValue; this.whyNow = whyNow;
        }
    }

    public static Boolean qualifies(Decimal fitValue) {
        return fitValue != null && fitValue >= THRESHOLD;
    }

    /**
     * Notifies managers about every candidate and marks each record so the same
     * household does not ring the bell every night. Bulk-safe: one notification
     * call per record, one DML for the flags, no per-record queries.
     */
    public static Integer escalate(List<Candidate> candidates) {
        if (candidates == null || candidates.isEmpty()) return 0;

        Set<String> recipients = new Set<String>();
        for (PermissionSetAssignment psa : [
                SELECT AssigneeId FROM PermissionSetAssignment
                WHERE PermissionSet.Name = :MANAGER_SET
                  AND Assignee.IsActive = true LIMIT 200]) {
            recipients.add(psa.AssigneeId);
        }
        // Nobody holds the set yet: still mark the record so the queue can show
        // it, and say plainly in the log that the bell rang in an empty room.
        CustomNotificationType nt;
        for (CustomNotificationType t : [SELECT Id FROM CustomNotificationType
                                          WHERE DeveloperName = :NOTIF_TYPE LIMIT 1]) nt = t;

        List<SObject> flags = new List<SObject>();
        Integer sent = 0;
        for (Candidate c : candidates) {
            if (nt != null && !recipients.isEmpty() && !Test.isRunningTest()) {
                Messaging.CustomNotification n = new Messaging.CustomNotification();
                n.setNotificationTypeId(nt.Id);
                n.setTargetId(c.recordId);
                n.setTitle('High-value prospect surfaced: ' + c.name);
                n.setBody(formatMoney(c.fitValue) + ' - ' + shorten(c.whyNow, 160));
                try {
                    n.send(recipients);
                    sent++;
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Escalation notification failed for '
                        + c.recordId + ': ' + e.getMessage());
                }
            } else if (recipients.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'High-value prospect ' + c.name
                    + ' surfaced but nobody holds ' + MANAGER_SET + '.');
            }
            String sObj = c.recordId.getSObjectType().getDescribe().getName();
            SObject f = Schema.getGlobalDescribe().get(sObj).newSObject(c.recordId);
            f.put('Omnishift_Escalated__c', true);
            f.put('Omnishift_Escalated_On__c', Datetime.now());
            flags.add(f);
        }
        // Mixed sObject lists are rejected by DML; split by type.
        List<Lead> ls = new List<Lead>(); List<Contact> cs = new List<Contact>();
        for (SObject f : flags) {
            if (f instanceof Lead) ls.add((Lead) f); else cs.add((Contact) f);
        }
        if (!ls.isEmpty()) Database.update(ls, false);
        if (!cs.isEmpty()) Database.update(cs, false);
        return sent;
    }

    @TestVisible
    private static String formatMoney(Decimal d) {
        if (d == null) return '';
        if (d >= 1000000) return '$' + (d / 1000000).setScale(1) + 'm';
        return '$' + d.setScale(0);
    }
    @TestVisible
    private static String shorten(String s, Integer n) {
        if (s == null) return '';
        return s.length() <= n ? s : s.left(n - 1) + '…';
    }
}
