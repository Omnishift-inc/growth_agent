// One campaign per person, at most, in the coming fortnight. The previous seed
// put sends on every weekday, which held back a third of the queue - the rule
// was right, the data was not. Sends stay spread across the week so the grid
// still reads like the Account Engagement one.
delete [SELECT Id FROM Omnishift_Marketing_Send__c];
List<String> NAMES = new List<String>{'Aug 26 Gus Dow Send','Aug 26 Alex Dow Send','Q3 Market Commentary',
  'Business Owner Webinar Invitation','Tax Season Reminder','Quarterly Newsletter','P&G Retirement Package Seminar'};
List<String> TYPES = new List<String>{'Dow drip','Dow drip','Market commentary','Webinar invitation','Tax season','Newsletter','Event follow-up'};
List<String> AUD   = new List<String>{'Prospects - business owners','Prospects - all','Clients and prospects','Prospects - $2m+','Clients - all','Clients and prospects','ABM - Procter & Gamble'};
List<Integer> DAYS = new List<Integer>{1,2,3,4,5,8,9,10,11,12};   // weekdays over two weeks from Sunday
Date wk = Date.today().toStartOfWeek();
List<Omnishift_Marketing_Send__c> out = new List<Omnishift_Marketing_Send__c>();
Integer n = 0;
for (Lead l : [SELECT Id FROM Lead WHERE IsConverted = false ORDER BY CreatedDate]) {
    if (Math.mod(n, 4) != 1) { n++; continue; }           // one in four people
    Integer c = Math.mod(n, NAMES.size()); Integer d = DAYS[Math.mod(n * 3, DAYS.size())]; Integer hr = (Math.mod(d,2)==0) ? 10 : 17;
    out.add(new Omnishift_Marketing_Send__c(Name=NAMES[c], Campaign_Type__c=TYPES[c], Audience__c=AUD[c],
        Source_System__c='Account Engagement', External_Id__c='AE-L'+String.valueOf(800000+n), Omnishift_Lead__c=l.Id,
        Scheduled_For__c=Datetime.newInstance(wk.addDays(d), Time.newInstance(hr,0,0,0))));
    n++;
}
n = 0;
for (Contact ct : [SELECT Id FROM Contact ORDER BY CreatedDate]) {
    if (Math.mod(n, 4) != 2) { n++; continue; }
    Integer c = Math.mod(n + 2, NAMES.size()); Integer d = DAYS[Math.mod(n * 5 + 1, DAYS.size())]; Integer hr = (Math.mod(d,2)==0) ? 10 : 17;
    out.add(new Omnishift_Marketing_Send__c(Name=NAMES[c], Campaign_Type__c=TYPES[c], Audience__c=AUD[c],
        Source_System__c='Account Engagement', External_Id__c='AE-C'+String.valueOf(900000+n), Omnishift_Contact__c=ct.Id,
        Scheduled_For__c=Datetime.newInstance(wk.addDays(d), Time.newInstance(hr,0,0,0))));
    n++;
}
// a few extra recipients on the two Dow sends so the grid shows "N people"
Integer k = 0;
for (Lead l : [SELECT Id FROM Lead WHERE IsConverted = false ORDER BY CreatedDate DESC LIMIT 6]) {
    out.add(new Omnishift_Marketing_Send__c(Name=NAMES[Math.mod(k,2)], Campaign_Type__c='Dow drip', Audience__c=AUD[Math.mod(k,2)],
        Source_System__c='Account Engagement', External_Id__c='AE-X'+String.valueOf(950000+k), Omnishift_Lead__c=l.Id,
        Scheduled_For__c=Datetime.newInstance(wk.addDays(k < 3 ? 8 : 9), Time.newInstance(17,0,0,0))));
    k++;
}
insert out;
System.debug('RESEND-' + out.size());
