// An outcome without outreach is a contradiction: nobody can have "replied"
// to a note that was never sent. Where the outcome seed landed on a record
// with no advisor decision, the outcome goes; the record reads as new and
// unworked, which is what it is.
List<SObject> ups = new List<SObject>();
for (Lead l : [SELECT Id FROM Lead WHERE Omnishift_Outcome__c != null AND Omnishift_Disposition__c = null]) ups.add(new Lead(Id=l.Id, Omnishift_Outcome__c=null, Omnishift_Outcome_On__c=null));
for (Contact c : [SELECT Id FROM Contact WHERE Omnishift_Outcome__c != null AND Omnishift_Disposition__c = null]) ups.add(new Contact(Id=c.Id, Omnishift_Outcome__c=null, Omnishift_Outcome_On__c=null));
update ups;
System.debug('OUTCOMES cleared=' + ups.size());
