// The top of the list is the agent at its best: every draft there is clean
// and can go as written. The compliance cases belong further down, where a
// prospect's own awkward phrase is a realistic thing to run into. Move the
// three that had landed in the top ten onto lower-ranked, weaker-profile
// records, older and less certain, so the boost does not carry them up.
delete [SELECT Id FROM Omnishift_Signal__c WHERE External_Id__c LIKE 'SMA-OWN%' OR External_Id__c LIKE 'GFB-OWN%'];
String NOTE = ' [Generated demonstration record - no real person or event.]';
Map<String, String> LEAD_SAID = new Map<String, String>{
    'Pamela Whitaker'   => 'guaranteed income in retirement',              // blocked
    'Delphine Yatesbury'=> 'a way to beat the market with the proceeds',    // blocked
    'Juno Hartrigg'     => 'the best firm in the city for estate work',     // auto-corrected
    'Ansel Sandhurst'   => 'something to maximise returns before I retire'  // flagged
};
Map<String, String> CONTACT_SAID = new Map<String, String>{
    'Jarek Quarrymore'  => 'a plan that will act now on the sale proceeds'  // auto-corrected
};
List<Omnishift_Signal__c> sigs = new List<Omnishift_Signal__c>();
Integer i = 0;
for (Lead l : [SELECT Id, Name FROM Lead WHERE Name IN :LEAD_SAID.keySet() AND IsConverted = false AND Status != 'Closed - Not Converted']) {
    Integer daysAgo = l.Name == 'Pamela Whitaker' ? 0 : 9 + i;               // Pamela stays the fresh example at #12
    Date d = Date.today().addDays(-daysAgo);
    String ev = 'Matched enquiry ' + d.format() + ', self-reported investable assets $2.5m-$5m, stated goal "' + LEAD_SAID.get(l.Name) + '", timeframe "within 6 months"; marketplace lead, not exclusive.';
    sigs.add(new Omnishift_Signal__c(Name = 'SmartAsset AMP - Marketplace enquiry', Omnishift_Lead__c = l.Id, Signal_Type__c = 'Marketplace enquiry',
        Source__c = 'SmartAsset AMP', Source_System__c = 'SmartAsset AMP', Occurred_On__c = d, Observed_On__c = Datetime.newInstance(d, Time.newInstance(11,0,0,0)),
        Confidence__c = l.Name == 'Pamela Whitaker' ? 99 : 70, External_Id__c = 'SMA-OWN' + i, Evidence__c = ev + NOTE, Detail__c = ev.left(180) + NOTE));
    i++;
}
for (Contact c : [SELECT Id, Name FROM Contact WHERE Name IN :CONTACT_SAID.keySet()]) {
    Date d = Date.today().addDays(-11);
    String ev = 'Survey response ' + d.format() + ': satisfaction 7/10, "likely" to refer; free text mentions ' + CONTACT_SAID.get(c.Name) + '.';
    sigs.add(new Omnishift_Signal__c(Name = 'GetFeedback - Survey response', Omnishift_Contact__c = c.Id, Signal_Type__c = 'Survey response',
        Source__c = 'GetFeedback', Source_System__c = 'GetFeedback', Occurred_On__c = d, Observed_On__c = Datetime.newInstance(d, Time.newInstance(11,0,0,0)),
        Confidence__c = 70, External_Id__c = 'GFB-OWN' + i, Evidence__c = ev + NOTE, Detail__c = ev.left(180) + NOTE));
    i++;
}
insert sigs;
System.debug('OWNWORDS-LOWER ' + sigs.size());
System.debug(OmnishiftEngineBatch.runNow());
// The quieter cases must still be the newest thing on their record or the
// engine never quotes them; fresh but low-confidence keeps them out of the
// top ten. Hartrigg is parked behind a cadence, so the auto-correct example
// moves to Emrys Inchcape. Pamela is un-parked so the block is visible.
String NOTE = ' [Generated demonstration record - no real person or event.]';
delete [SELECT Id FROM Omnishift_Signal__c WHERE External_Id__c LIKE 'SMA-OWN%' AND Omnishift_Lead__r.Name = 'Juno Hartrigg'];
Lead em = [SELECT Id FROM Lead WHERE Name = 'Emrys Inchcape' AND IsConverted = false LIMIT 1];
String ev = 'Matched enquiry ' + Date.today().format() + ', self-reported investable assets $2.5m-$5m, stated goal "the best firm in the city for estate work", timeframe "within 6 months"; marketplace lead, not exclusive.';
insert new Omnishift_Signal__c(Name = 'SmartAsset AMP - Marketplace enquiry', Omnishift_Lead__c = em.Id, Signal_Type__c = 'Marketplace enquiry',
    Source__c = 'SmartAsset AMP', Source_System__c = 'SmartAsset AMP', Occurred_On__c = Date.today(), Observed_On__c = Datetime.now().addHours(-3),
    Confidence__c = 60, External_Id__c = 'SMA-OWN9', Evidence__c = ev + NOTE, Detail__c = ev.left(180) + NOTE);
List<Omnishift_Signal__c> tune = [SELECT Id, Evidence__c FROM Omnishift_Signal__c WHERE (External_Id__c LIKE 'SMA-OWN%' OR External_Id__c LIKE 'GFB-OWN%')
                                  AND (Omnishift_Lead__r.Name = 'Ansel Sandhurst' OR Omnishift_Contact__r.Name = 'Jarek Quarrymore')];
for (Omnishift_Signal__c s : tune) { s.Occurred_On__c = Date.today(); s.Observed_On__c = Datetime.now().addHours(-4); s.Confidence__c = 60;
    s.Evidence__c = s.Evidence__c.replaceAll('(enquiry|response) \\d+/\\d+/\\d+', '$1 ' + Date.today().format()); s.Detail__c = s.Evidence__c.left(180) + NOTE; }
update tune;
update new Lead(Id = [SELECT Id FROM Lead WHERE Name = 'Pamela Whitaker' AND IsConverted = false LIMIT 1].Id,
    Omnishift_Disposition__c = null, Omnishift_Disposition_Reason__c = null, Omnishift_Dispositioned_On__c = null, Omnishift_Next_Action_Date__c = Date.today());
System.debug('TUNE ' + tune.size());
System.debug(OmnishiftEngineBatch.runNow());
