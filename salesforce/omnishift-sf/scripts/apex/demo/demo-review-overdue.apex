// One client whose reason is the annual review itself: nothing recorded for
// over a year and no fresh signal, so the relationship rule - not an event -
// puts him on the list. Dashiell Ainsleigh: last review moved to Aug 2025,
// his signals aged out of their windows.
Contact c = [SELECT Id FROM Contact WHERE Name = 'Dashiell Ainsleigh' LIMIT 1];
List<Event> ev = [SELECT Id, StartDateTime, EndDateTime FROM Event WHERE WhoId = :c.Id];
for (Event e : ev) { e.StartDateTime = Datetime.newInstance(2025, 8, 12, 11, 0, 0); e.EndDateTime = Datetime.newInstance(2025, 8, 12, 12, 0, 0); }
update ev;
List<Task> ts = [SELECT Id, ActivityDate FROM Task WHERE WhoId = :c.Id AND ActivityDate > 2025-08-12];
for (Task t : ts) t.ActivityDate = Date.newInstance(2025, 8, 12);
update ts;
List<Omnishift_Signal__c> sigs = [SELECT Id, Occurred_On__c FROM Omnishift_Signal__c WHERE Omnishift_Contact__c = :c.Id];
for (Omnishift_Signal__c s : sigs) { s.Occurred_On__c = Date.today().addDays(-150); s.Observed_On__c = Datetime.now().addDays(-150); }
update sigs;
System.debug('REVIEW-OVERDUE set'); System.debug(OmnishiftEngineBatch.runNow());
