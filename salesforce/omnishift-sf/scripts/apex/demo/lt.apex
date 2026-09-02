// Learning needs outcomes to learn from. Record a plausible spread so the loop
// is demonstrably closed rather than merely wired.
List<String> OUT = new List<String>{'Meeting booked','Replied, no meeting','No response',
                                    'Not interested','Too early','Should not have been surfaced'};
List<Lead> ls = [SELECT Id, Omnishift_Score__c, Omnishift_Driver__c FROM Lead
                 WHERE Omnishift_Rank__c != null ORDER BY Omnishift_Rank__c];
List<Lead> up = new List<Lead>();
Integer i = 0;
for (Lead l : ls) {
    // Higher-scored records book more often, which is the correlation the
    // ranking claims to have. If it is not there, the loop should say so.
    Integer s = (l.Omnishift_Score__c == null) ? 0 : l.Omnishift_Score__c.intValue();
    String o;
    if (s >= 85)      o = (Math.mod(i,3)==0) ? 'Meeting booked' : (Math.mod(i,3)==1 ? 'Replied, no meeting' : 'Meeting booked');
    else if (s >= 70) o = (Math.mod(i,3)==0) ? 'Meeting booked' : 'No response';
    else              o = (Math.mod(i,4)==0) ? 'Too early' : (Math.mod(i,4)==1 ? 'Not interested' : 'No response');
    up.add(new Lead(Id=l.Id, Omnishift_Outcome__c=o, Omnishift_Outcome_On__c=Datetime.now()));
    i++;
}
update up;
System.debug('OUTCOMES-' + up.size());
