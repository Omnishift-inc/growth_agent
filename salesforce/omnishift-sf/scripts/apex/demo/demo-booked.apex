// Two more event-driven prospects booked a meeting after the outreach, with the
// meeting on the calendar so the record agrees with the outcome. Booked people
// leave today's list; their outcome is what teaches the loop that confirmed
// events convert. Generated values only.
Id me = UserInfo.getUserId();
List<Lead> picks = [SELECT Id, FirstName, LastName, Omnishift_Disposition__c FROM Lead
                    WHERE IsConverted = false AND Omnishift_Rank__c != null AND Omnishift_Driver__c = 'Event'
                      AND LastName IN ('Carrowmore', 'Yatesbury') AND Omnishift_Outcome__c != 'Meeting booked'];
List<Event> ev = new List<Event>();
Integer i = 0;
for (Lead l : picks) {
    l.Omnishift_Outcome__c = 'Meeting booked';
    l.Omnishift_Outcome_On__c = Datetime.now().addDays(-1 - i);
    if (l.Omnishift_Disposition__c == null) l.Omnishift_Disposition__c = 'Approved and sent';
    l.Omnishift_Next_Action_Date__c = null;
    Datetime mtg = Datetime.newInstance(Date.today().addDays(4 + i * 3), Time.newInstance(10 + i, 0, 0, 0));
    ev.add(new Event(WhoId = l.Id, OwnerId = me, Subject = 'Initial meeting - prospecting / discovery',
        StartDateTime = mtg, EndDateTime = mtg.addMinutes(45),
        Description = 'Booked after the reply to the event-driven note. Bring the preliminary framework.'));
    i++;
}
update picks; insert ev;
System.debug('BOOKED ' + picks.size());
