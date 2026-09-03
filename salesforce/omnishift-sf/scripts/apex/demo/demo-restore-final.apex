// Puts back the final demo state after test activity from another session.
// Idempotent: safe to run again before the demo.
// 1. No advisor-edited drafts in the demo: every draft is the agent's.
List<SObject> ups = new List<SObject>();
for (Lead l : [SELECT Id FROM Lead WHERE Omnishift_Draft_Edited__c = true]) ups.add(new Lead(Id = l.Id, Omnishift_Draft_Edited__c = false));
for (Contact c : [SELECT Id FROM Contact WHERE Omnishift_Draft_Edited__c = true]) ups.add(new Contact(Id = c.Id, Omnishift_Draft_Edited__c = false));
update ups;
// 2. The named demo people back to their scripted state.
Lead pam = [SELECT Id FROM Lead WHERE Name = 'Pamela Whitaker' AND IsConverted = false LIMIT 1];
pam.Omnishift_Disposition__c = null; pam.Omnishift_Disposition_Reason__c = null; pam.Omnishift_Dispositioned_On__c = null;
pam.Omnishift_Outcome__c = null; pam.Omnishift_Outcome_On__c = null; pam.Omnishift_Next_Action_Date__c = Date.today(); pam.Status = 'Open - Not Contacted';
update pam;
delete [SELECT Id FROM Task WHERE WhoId = :pam.Id AND CreatedDate = LAST_N_DAYS:2];
Contact dash = [SELECT Id FROM Contact WHERE Name = 'Dashiell Ainsleigh' LIMIT 1];
dash.Omnishift_Disposition__c = null; dash.Omnishift_Disposition_Reason__c = null; dash.Omnishift_Dispositioned_On__c = null;
dash.Omnishift_Outcome__c = null; dash.Omnishift_Outcome_On__c = null; dash.Omnishift_Next_Action_Date__c = Date.today();
update dash;
// 3. Test sends undone: a closed lead cannot have been emailed; Yarrowby stays unworked.
for (Lead m : [SELECT Id FROM Lead WHERE Name = 'Maeve Carrowmore' AND Status = 'Closed - Not Converted']) {
    delete [SELECT Id FROM Task WHERE WhoId = :m.Id AND Subject = 'Growth Agent outreach'];
    update new Lead(Id = m.Id, Omnishift_Disposition__c = null, Omnishift_Disposition_Reason__c = null, Omnishift_Dispositioned_On__c = null);
}
Contact kes = [SELECT Id FROM Contact WHERE Name = 'Kestrel Yarrowby' LIMIT 1];
delete [SELECT Id FROM Task WHERE WhoId = :kes.Id AND CreatedDate = LAST_N_DAYS:2 AND Subject = 'A thank you, and a thought'];
update new Contact(Id = kes.Id, Omnishift_Disposition__c = null, Omnishift_Disposition_Reason__c = null, Omnishift_Dispositioned_On__c = null, Omnishift_Next_Action_Date__c = Date.today());
// 3b. A snooze always carries the date it comes back on.
List<SObject> parked = new List<SObject>();
for (Lead l : [SELECT Id FROM Lead WHERE Omnishift_Disposition__c = 'Snoozed' AND (Omnishift_Next_Action_Date__c = null OR Omnishift_Next_Action_Date__c <= TODAY)]) parked.add(new Lead(Id = l.Id, Omnishift_Next_Action_Date__c = Date.today().addDays(6)));
for (Contact c : [SELECT Id FROM Contact WHERE Omnishift_Disposition__c = 'Snoozed' AND (Omnishift_Next_Action_Date__c = null OR Omnishift_Next_Action_Date__c <= TODAY)]) parked.add(new Contact(Id = c.Id, Omnishift_Next_Action_Date__c = Date.today().addDays(6)));
update parked;
// 4. Diane's why-now is the engine's; the integrator's words live in her signals. The run below rewrites it.
System.debug('RESTORED edited=' + ups.size());
System.debug(OmnishiftEngineBatch.runNow());

// 5. Pamela Whitaker is the blocked example just below the top ten: a $3.2m
//    household that has been worked once, not a $11m household nobody has
//    touched. Delphine Yatesbury's blocked draft cannot have been sent.
Lead pw = [SELECT Id FROM Lead WHERE Name = 'Pamela Whitaker' AND IsConverted = false LIMIT 1];
pw.AnnualRevenue = 3200000; pw.Omnishift_Escalated__c = false; pw.Omnishift_Escalated_On__c = null; update pw;
if ([SELECT count() FROM Task WHERE WhoId = :pw.Id AND Subject LIKE 'CA cadence day 1%'] == 0) {
    insert new Task(WhoId = pw.Id, OwnerId = UserInfo.getUserId(), Status = 'Completed', Priority = 'Normal', ActivityDate = Date.today().addDays(-21),
        Subject = 'CA cadence day 1: call, voicemail', Description = 'No answer. Left a voicemail introducing TMG.');
}
for (Lead dy : [SELECT Id FROM Lead WHERE Name = 'Delphine Yatesbury' AND Omnishift_Compliance_Status__c = 'Blocked' AND Omnishift_Disposition__c IN ('Approved and sent','Edited before send')]) {
    update new Lead(Id = dy.Id, Omnishift_Disposition__c = 'Snoozed', Omnishift_Disposition_Reason__c = 'Draft is blocked in compliance; parked until it is rewritten.', Omnishift_Next_Action_Date__c = Date.today().addDays(6));
}
System.debug(OmnishiftEngineBatch.runNow());
