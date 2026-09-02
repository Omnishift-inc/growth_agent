// The advisor's recorded decision and the engagement history must agree. The
// disposition seed wrote "Approved and sent" without a sent email on file and
// without a date, so the panel said one thing and the history another. Give
// every seeded decision its date and the activity that would exist if an
// advisor had actually clicked the button. Generated values only.
Id me = UserInfo.getUserId();
// Task.Type is not readable from anonymous Apex in this org, so existing
// activity is recognised by subject: the sent draft carries its subject line,
// a logged call is always "Growth Agent call".
Set<String> existing = new Set<String>();
for (Task t : [SELECT WhoId, Subject FROM Task WHERE WhoId != null]) existing.add(t.WhoId + '|' + t.Subject);
List<Task> tasks = new List<Task>();
List<SObject> ups = new List<SObject>();
Integer i = 0;
for (String obj : new List<String>{'Lead', 'Contact'}) {
    String soql = 'SELECT Id, FirstName, Omnishift_Disposition__c, Omnishift_Disposition_Reason__c, Omnishift_Dispositioned_On__c, '
        + 'Omnishift_Compliance_Status__c, Omnishift_Draft_Subject__c, Omnishift_Draft_Body__c FROM ' + obj
        + ' WHERE Omnishift_Disposition__c != null' + (obj == 'Lead' ? ' AND IsConverted = false' : '');
    for (SObject r : Database.query(soql)) {
        String d = (String) r.get('Omnishift_Disposition__c');
        Boolean changed = false;
        // a blocked draft cannot have been sent
        if ((String) r.get('Omnishift_Compliance_Status__c') == 'Blocked' && (d == 'Approved and sent' || d == 'Edited before send')) {
            d = 'Snoozed';
            r.put('Omnishift_Disposition__c', d);
            r.put('Omnishift_Disposition_Reason__c', 'Draft is blocked in compliance; parked until it is rewritten.');
            changed = true;
        }
        Datetime at = (Datetime) r.get('Omnishift_Dispositioned_On__c');
        if (at == null) {
            at = Datetime.newInstance(Date.today().addDays(-(1 + Math.mod(i, 5))), Time.newInstance(9 + Math.mod(i * 3, 8), 10 * Math.mod(i, 6), 0, 0));
            r.put('Omnishift_Dispositioned_On__c', at);
            changed = true;
        }
        String subj = (String) r.get('Omnishift_Draft_Subject__c');
        String body = (String) r.get('Omnishift_Draft_Body__c');
        if ((d == 'Approved and sent' || d == 'Edited before send') && subj != null && !existing.contains(r.Id + '|' + subj)) {
            tasks.add(new Task(WhoId = r.Id, OwnerId = me, Status = 'Completed', Priority = 'Normal',
                ActivityDate = at.date(), Subject = subj,
                Description = (d == 'Edited before send' ? '[Edited before send] ' : '') + (body == null ? '' : body.left(400))));
        } else if (d == 'Call logged' && !existing.contains(r.Id + '|Growth Agent call')) {
            tasks.add(new Task(WhoId = r.Id, OwnerId = me, Status = 'Completed', Priority = 'Normal',
                ActivityDate = at.date(), Subject = 'Growth Agent call',
                Description = (String) r.get('Omnishift_Disposition_Reason__c')));
        }
        if (changed) ups.add(r);
        i++;
    }
}
update ups; insert tasks;
System.debug('CONSISTENT updated=' + ups.size() + ' tasks=' + tasks.size());
