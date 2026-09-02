// Final placement. The top ten are clean drafts; the blocked example sits
// just below them. The needs-review example keeps its quote by making the
// enquiry the event the engine reads. Diane's evidence reads as one sentence.
String NOTE = ' [Generated demonstration record - no real person or event.]';
for (Omnishift_Signal__c s : [SELECT Id FROM Omnishift_Signal__c WHERE External_Id__c LIKE 'SMA-OWN%' AND Omnishift_Lead__r.Name = 'Pamela Whitaker']) {
    s.Occurred_On__c = Date.today().addDays(-1); s.Confidence__c = 86; update s;
}
for (Omnishift_Signal__c s : [SELECT Id FROM Omnishift_Signal__c WHERE Omnishift_Lead__r.Name = 'Ansel Sandhurst' AND Signal_Type__c != 'Marketplace enquiry' AND Occurred_On__c >= :Date.today().addDays(-30)]) {
    s.Occurred_On__c = Date.today().addDays(-41); update s;
}
Omnishift_Signal__c d = [SELECT Id FROM Omnishift_Signal__c WHERE External_Id__c = 'WEA-DIANE'];
d.Evidence__c = 'Sudden-wealth event: estimated $5.2M inheritance; probate filing 8/29/2026 links the household to the Okafor family trust; court record, matched on surname, county and decedent address.' + NOTE;
d.Detail__c = 'Sudden-wealth event: estimated $5.2M inheritance; probate filing 8/29/2026 links the household to the Okafor family trust.' + NOTE;
update d;
System.debug('TUNED'); System.debug(OmnishiftEngineBatch.runNow());
