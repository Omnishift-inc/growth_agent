// A parked record needs a date to come back on; "snoozed" with today's date is a contradiction.
List<SObject> ups = new List<SObject>();
for (Lead l : [SELECT Id FROM Lead WHERE Omnishift_Disposition__c = 'Snoozed' AND (Omnishift_Next_Action_Date__c = null OR Omnishift_Next_Action_Date__c <= TODAY)]) ups.add(new Lead(Id=l.Id, Omnishift_Next_Action_Date__c=Date.today().addDays(6)));
for (Contact c : [SELECT Id FROM Contact WHERE Omnishift_Disposition__c = 'Snoozed' AND (Omnishift_Next_Action_Date__c = null OR Omnishift_Next_Action_Date__c <= TODAY)]) ups.add(new Contact(Id=c.Id, Omnishift_Next_Action_Date__c=Date.today().addDays(6)));
update ups; System.debug('PARKED ' + ups.size());
