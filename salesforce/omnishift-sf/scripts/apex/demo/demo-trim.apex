// The seed handed out "Snoozed" and "Wrong person" generously; now that the
// engine honours both, a third of the list was parked or held. A real desk
// has a couple of each. Keep three snoozes and two wrong-person marks; the
// rest go back to unworked. Generated data.
Integer keptSnooze = 0, keptWrong = 0;
List<SObject> ups = new List<SObject>();
for (String obj : new List<String>{'Lead', 'Contact'}) {
    for (SObject r : Database.query('SELECT Id, Omnishift_Disposition__c, Omnishift_Quarantined__c FROM ' + obj + ' WHERE Omnishift_Disposition__c IN (\'Snoozed\', \'Wrong person\')' + (obj == 'Lead' ? ' AND IsConverted = false' : '') + ' ORDER BY Omnishift_Score__c DESC')) {
        String d = (String) r.get('Omnishift_Disposition__c');
        if (d == 'Snoozed' && keptSnooze < 3) { keptSnooze++; continue; }
        if (d == 'Wrong person' && keptWrong < 2) { keptWrong++; continue; }
        r.put('Omnishift_Disposition__c', null);
        r.put('Omnishift_Disposition_Reason__c', null);
        r.put('Omnishift_Dispositioned_On__c', null);
        r.put('Omnishift_Next_Action_Date__c', Date.today());
        ups.add(r);
    }
}
update ups;
System.debug('TRIM cleared=' + ups.size() + ' keptSnooze=' + keptSnooze + ' keptWrong=' + keptWrong);
System.debug(OmnishiftEngineBatch.runNow());
