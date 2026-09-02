// Clients were bunching at the ceiling: every one of them carried a days-old,
// high-confidence event on top of a large account. Spread the signal ages and
// confidences the way a feed actually reports them, keep one household hot.
Set<String> ENGAGEMENT = new Set<String>{'Website research','Marketplace enquiry','Email engagement','Survey response','Webinar attendance'};
Map<Id, List<Omnishift_Signal__c>> byWho = new Map<Id, List<Omnishift_Signal__c>>();
for (Omnishift_Signal__c s : [SELECT Id, Omnishift_Contact__c, Signal_Type__c, Occurred_On__c, Observed_On__c, Confidence__c FROM Omnishift_Signal__c WHERE Omnishift_Contact__c != null ORDER BY Occurred_On__c DESC]) {
    if (!byWho.containsKey(s.Omnishift_Contact__c)) byWho.put(s.Omnishift_Contact__c, new List<Omnishift_Signal__c>());
    byWho.get(s.Omnishift_Contact__c).add(s);
}
List<Omnishift_Signal__c> su = new List<Omnishift_Signal__c>();
Integer i = 0;
for (Contact c : [SELECT Id FROM Contact WHERE Omnishift_Rank__c != null ORDER BY Omnishift_Rank__c]) {
    List<Omnishift_Signal__c> sigs = byWho.get(c.Id);
    if (sigs == null || sigs.isEmpty()) { i++; continue; }
    Omnishift_Signal__c latest = sigs[0];                         // the one the engine reads
    Integer daysAgo = (i == 0) ? 1 : 2 + Math.mod(i * 3, 16);     // 2..17 days
    Integer conf    = (i == 0) ? 96 : 68 + Math.mod(i * 7, 26);   // 68..93
    latest.Occurred_On__c = Date.today().addDays(-daysAgo);
    latest.Observed_On__c = Datetime.newInstance(latest.Occurred_On__c, Time.newInstance(8, 0, 0, 0)).addHours(Math.mod(i * 5, 30) + 3);
    latest.Confidence__c  = conf;
    su.add(latest);
    i++;
}
update su;
System.debug('CLIENTS ' + su.size());
System.debug(OmnishiftEngineBatch.runNow());
