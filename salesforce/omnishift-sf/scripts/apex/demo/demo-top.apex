// The head of the list should look like the households the firm actually
// chases: a confirmed event this week and a balance worth the call. Generated
// values only; no email, phone or name is touched.
Set<String> ENGAGEMENT = new Set<String>{'Website research','Marketplace enquiry','Email engagement','Survey response','Webinar attendance'};
Map<Id, List<Omnishift_Signal__c>> byWho = new Map<Id, List<Omnishift_Signal__c>>();
for (Omnishift_Signal__c s : [SELECT Id, Omnishift_Lead__c, Omnishift_Contact__c, Signal_Type__c, Occurred_On__c, Observed_On__c, Confidence__c FROM Omnishift_Signal__c ORDER BY Confidence__c DESC]) {
    Id who = s.Omnishift_Lead__c != null ? s.Omnishift_Lead__c : s.Omnishift_Contact__c;
    if (!byWho.containsKey(who)) byWho.put(who, new List<Omnishift_Signal__c>());
    byWho.get(who).add(s);
}
List<Omnishift_Signal__c> su = new List<Omnishift_Signal__c>();
List<Lead> lu = new List<Lead>();
List<Decimal> REV = new List<Decimal>{24000000, 12500000, 18000000, 10400000, 31000000, 14000000, 11200000, 16500000};
Integer i = 0;
for (Lead l : [SELECT Id, AnnualRevenue FROM Lead WHERE Omnishift_Rank__c != null ORDER BY Omnishift_Rank__c LIMIT 8]) {
    if (l.AnnualRevenue == null || l.AnnualRevenue < 10000000) { l.AnnualRevenue = REV[i]; lu.add(l); }
    List<Omnishift_Signal__c> sigs = byWho.get(l.Id);
    if (sigs != null && !sigs.isEmpty()) {
        Omnishift_Signal__c pick = sigs[0];
        for (Omnishift_Signal__c s : sigs) if (!ENGAGEMENT.contains(s.Signal_Type__c)) { pick = s; break; }
        pick.Occurred_On__c = Date.today().addDays(-Math.mod(i * 3, 5));       // 0..4 days ago
        pick.Observed_On__c = Datetime.newInstance(pick.Occurred_On__c, Time.newInstance(8, 0, 0, 0)).addHours(Math.mod(i * 5, 20) + 3);
        pick.Confidence__c  = 88 + Math.mod(i * 3, 10);                       // 88..97
        su.add(pick);
    }
    i++;
}
i = 0;
for (Contact c : [SELECT Id FROM Contact WHERE Omnishift_Rank__c != null ORDER BY Omnishift_Rank__c LIMIT 4]) {
    List<Omnishift_Signal__c> sigs = byWho.get(c.Id);
    if (sigs != null && !sigs.isEmpty()) {
        Omnishift_Signal__c pick = sigs[0];
        for (Omnishift_Signal__c s : sigs) if (!ENGAGEMENT.contains(s.Signal_Type__c)) { pick = s; break; }
        pick.Occurred_On__c = Date.today().addDays(-Math.mod(i * 2, 4));
        pick.Observed_On__c = Datetime.newInstance(pick.Occurred_On__c, Time.newInstance(8, 0, 0, 0)).addHours(Math.mod(i * 7, 20) + 3);
        pick.Confidence__c  = 92 + Math.mod(i * 2, 6);
        su.add(pick);
    }
    i++;
}
update lu; update su;
System.debug('TOP leads revenue=' + lu.size() + ' signals=' + su.size());
System.debug(OmnishiftEngineBatch.runNow());
