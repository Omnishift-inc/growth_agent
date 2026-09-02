// 1. Every phone number in the org is a 555-01xx number. The orgfarm sample
//    data shipped 212 and similar numbers on Other Phone, Fax and Home Phone;
//    fictional in origin, but not obviously so to a reader.
Integer n = 0;
List<SObject> ups = new List<SObject>();
Integer i = 0;
for (Contact c : [SELECT Id, Phone, MobilePhone, HomePhone, OtherPhone, Fax, AssistantPhone FROM Contact]) {
    Boolean ch = false;
    for (String f : new List<String>{'Phone','MobilePhone','HomePhone','OtherPhone','Fax','AssistantPhone'}) {
        String v = (String) c.get(f);
        if (v != null && !v.contains('555')) { c.put(f, '(555) 01' + String.valueOf(Math.mod(i * 7 + f.length(), 100)).leftPad(2, '0') + '-' + String.valueOf(1000 + Math.mod(i * 37 + f.length() * 11, 9000))); ch = true; }
    }
    if (ch) { ups.add(c); n++; } i++;
}
for (Lead l : [SELECT Id, Phone, MobilePhone, Fax FROM Lead]) {
    Boolean ch = false;
    for (String f : new List<String>{'Phone','MobilePhone','Fax'}) {
        String v = (String) l.get(f);
        if (v != null && !v.contains('555')) { l.put(f, '(555) 01' + String.valueOf(Math.mod(i * 7 + f.length(), 100)).leftPad(2, '0') + '-' + String.valueOf(1000 + Math.mod(i * 37 + f.length() * 11, 9000))); ch = true; }
    }
    if (ch) { ups.add(l); n++; } i++;
}
for (Account a : [SELECT Id, Phone, Fax FROM Account]) {
    Boolean ch = false;
    for (String f : new List<String>{'Phone','Fax'}) {
        String v = (String) a.get(f);
        if (v != null && !v.contains('555')) { a.put(f, '(555) 01' + String.valueOf(Math.mod(i * 7 + f.length(), 100)).leftPad(2, '0') + '-' + String.valueOf(1000 + Math.mod(i * 37 + f.length() * 11, 9000))); ch = true; }
    }
    if (ch) { ups.add(a); n++; } i++;
}
update ups;
// 2. An outcome needs the outreach it is an outcome of.
Id me = UserInfo.getUserId();
List<Task> tasks = new List<Task>(); List<SObject> fix = new List<SObject>();
for (String obj : new List<String>{'Lead','Contact'}) {
    for (SObject r : Database.query('SELECT Id, Omnishift_Draft_Subject__c, Omnishift_Draft_Body__c, Omnishift_Outcome_On__c FROM ' + obj + ' WHERE Omnishift_Outcome__c != null AND Omnishift_Disposition__c = null')) {
        Datetime at = ((Datetime) r.get('Omnishift_Outcome_On__c')) == null ? Datetime.now().addDays(-4) : ((Datetime) r.get('Omnishift_Outcome_On__c')).addDays(-3);
        r.put('Omnishift_Disposition__c', 'Approved and sent'); r.put('Omnishift_Disposition_Reason__c', 'Sent as drafted.'); r.put('Omnishift_Dispositioned_On__c', at);
        String subj = (String) r.get('Omnishift_Draft_Subject__c'); String body = (String) r.get('Omnishift_Draft_Body__c');
        if (subj != null) tasks.add(new Task(WhoId = r.Id, OwnerId = me, Status = 'Completed', Priority = 'Normal', ActivityDate = at.date(), Subject = subj, Description = body == null ? '' : body.left(400)));
        fix.add(r);
    }
}
update fix; insert tasks;
System.debug('FINAL phonesScrubbed=' + n + ' outcomesGivenOutreach=' + fix.size());
