// The compliance cases come from the agent's own work, not from a made-up
// advisor edit. Five people said something in their own words - an enquiry
// goal, a survey line - that the firm may not repeat. The draft quotes them,
// the check catches it. The seeded "advisor edits" go; every draft is the
// agent's again. Generated data.
List<SObject> clear = new List<SObject>();
for (Lead l : [SELECT Id FROM Lead WHERE Omnishift_Draft_Edited__c = true]) clear.add(new Lead(Id = l.Id, Omnishift_Draft_Edited__c = false));
for (Contact c : [SELECT Id FROM Contact WHERE Omnishift_Draft_Edited__c = true]) clear.add(new Contact(Id = c.Id, Omnishift_Draft_Edited__c = false));
update clear;

Map<String, String> SAID = new Map<String, String>{
    'Pamela Whitaker' => 'guaranteed income in retirement',           // blocked
    'Theo Nakamura'   => 'a way to beat the market with the proceeds', // blocked
    'Elowen Holloway' => 'the best firm in the city for estate work',  // auto-corrected: "best"
    'Ansel Sandhurst' => 'something to maximise returns before I retire', // flagged
    'Soren Fennimore' => 'a plan that will act now on the sale proceeds' // auto-corrected: "act now"
};
String NOTE = ' [Generated demonstration record - no real person or event.]';
List<Omnishift_Signal__c> sigs = new List<Omnishift_Signal__c>();
Integer i = 0;
for (Lead l : [SELECT Id, Name FROM Lead WHERE Name IN :SAID.keySet() AND IsConverted = false]) {
    String ev = 'Matched enquiry ' + Date.today().addDays(-1 - i).format() + ', self-reported investable assets $5m+, stated goal "' + SAID.get(l.Name) + '", timeframe "within 3 months"; marketplace lead, not exclusive.';
    sigs.add(new Omnishift_Signal__c(Name = 'SmartAsset AMP - Marketplace enquiry', Omnishift_Lead__c = l.Id, Signal_Type__c = 'Marketplace enquiry',
        Source__c = 'SmartAsset AMP', Source_System__c = 'SmartAsset AMP', Occurred_On__c = Date.today().addDays(-1 - i),
        Observed_On__c = Datetime.now().addDays(-1 - i), Confidence__c = 91, External_Id__c = 'SMA-OWN' + i, Evidence__c = ev + NOTE, Detail__c = ev.left(180) + NOTE));
    i++;
}
for (Contact c : [SELECT Id, Name FROM Contact WHERE Name IN :SAID.keySet()]) {
    String ev = 'Survey response ' + Date.today().addDays(-1 - i).format() + ': satisfaction 8/10, "likely" to refer; free text mentions ' + SAID.get(c.Name) + '.';
    sigs.add(new Omnishift_Signal__c(Name = 'GetFeedback - Survey response', Omnishift_Contact__c = c.Id, Signal_Type__c = 'Survey response',
        Source__c = 'GetFeedback', Source_System__c = 'GetFeedback', Occurred_On__c = Date.today().addDays(-1 - i),
        Observed_On__c = Datetime.now().addDays(-1 - i), Confidence__c = 93, External_Id__c = 'GFB-OWN' + i, Evidence__c = ev + NOTE, Detail__c = ev.left(180) + NOTE));
    i++;
}
insert sigs;
System.debug('OWNWORDS cleared=' + clear.size() + ' signals=' + sigs.size());
System.debug(OmnishiftEngineBatch.runNow());
// The person's own words must be the newest thing on the record, or the
// engine reads the older signal and never quotes them.
List<Omnishift_Signal__c> s = [SELECT Id, Occurred_On__c, Evidence__c FROM Omnishift_Signal__c WHERE External_Id__c LIKE 'SMA-OWN%' OR External_Id__c LIKE 'GFB-OWN%'];
for (Omnishift_Signal__c x : s) { x.Occurred_On__c = Date.today(); x.Observed_On__c = Datetime.now().addHours(-2); x.Confidence__c = 99;
    x.Evidence__c = x.Evidence__c.replaceAll('(enquiry|response) \\d+/\\d+/\\d+', '$1 ' + Date.today().format()); x.Detail__c = x.Evidence__c.left(180) + ' [Generated demonstration record - no real person or event.]'; }
update s;
System.debug('OWNWORDS-FIX ' + s.size());
System.debug(OmnishiftEngineBatch.runNow());
