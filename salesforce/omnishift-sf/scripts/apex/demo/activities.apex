// An activity history that agrees with the record. The client associates work
// a two-week cadence: day 1 call + voicemail + email, day 3 call, day 5 call +
// email, then a 90-day task if nothing lands. A "Meeting booked" outcome means
// a meeting exists and the person has left today's list. An outcome always sits
// on a disposition, because you cannot know what happened without having done
// something first.
delete [SELECT Id FROM Task WHERE Subject LIKE 'CA cadence%' OR Subject LIKE 'Initial meeting%' OR Subject LIKE 'Discovery%'];
delete [SELECT Id FROM Event WHERE Subject LIKE 'Initial meeting%' OR Subject LIKE 'Discovery%'];
Id me = UserInfo.getUserId();
List<Task> tasks = new List<Task>();
List<Event> events = new List<Event>();
List<SObject> fixes = new List<SObject>();

void cadence(Id who, Date d1, Integer depth, String firstName) {
    tasks.add(new Task(WhoId=who, OwnerId=me, Status='Completed', ActivityDate=d1,
        Subject='CA cadence day 1: call, voicemail', Description='No answer. Left a voicemail introducing TMG and mentioned the article on concentrated positions.'));
    tasks.add(new Task(WhoId=who, OwnerId=me, Status='Completed', ActivityDate=d1,
        Subject='CA cadence day 1: follow-up email', Description='Sent the missed-you note with the business-owner piece attached.'));
    if (depth >= 2) tasks.add(new Task(WhoId=who, OwnerId=me, Status='Completed', ActivityDate=d1.addDays(2),
        Subject='CA cadence day 3: call', Description='No answer, no voicemail.'));
    if (depth >= 3) {
        tasks.add(new Task(WhoId=who, OwnerId=me, Status='Completed', ActivityDate=d1.addDays(4),
            Subject='CA cadence day 5: call', Description='Reached ' + firstName + ' briefly. Asked to be called back after the quarter.'));
        tasks.add(new Task(WhoId=who, OwnerId=me, Status='Completed', ActivityDate=d1.addDays(4),
            Subject='CA cadence day 5: email', Description='Sent the fee overview as requested.'));
    }
}

for (Lead l : [SELECT Id, FirstName, Omnishift_Outcome__c, Omnishift_Disposition__c, Omnishift_Dispositioned_On__c,
                      Omnishift_Next_Action_Date__c, CreatedDate FROM Lead WHERE IsConverted = false]) {
    String o = l.Omnishift_Outcome__c;
    Integer hashv = Math.abs(l.Id.hashCode());
    Date d1 = Date.today().addDays(-(6 + Math.mod(hashv, 40)));
    Lead fx = new Lead(Id = l.Id);
    Boolean changed = false;
    if (o == 'Meeting booked') {
        cadence(l.Id, d1, 3, l.FirstName);
        Datetime mtg = Datetime.newInstance(Date.today().addDays(3 + Math.mod(hashv, 9)), Time.newInstance(10 + Math.mod(hashv, 6), 0, 0, 0));
        events.add(new Event(WhoId=l.Id, OwnerId=me, Subject='Initial meeting - prospecting / discovery',
            StartDateTime=mtg, EndDateTime=mtg.addMinutes(45), Description='Booked after the day-5 call. Bring the preliminary framework.'));
        // booked means off today's list, and an outcome needs a disposition
        fx.Omnishift_Next_Action_Date__c = null;
        if (l.Omnishift_Disposition__c == null) { fx.Omnishift_Disposition__c = 'Call logged'; fx.Omnishift_Dispositioned_On__c = Datetime.now().addDays(-2); }
        changed = true;
    } else if (o == 'No response') {
        cadence(l.Id, d1, 3, l.FirstName);
        tasks.add(new Task(WhoId=l.Id, OwnerId=me, Status='Not Started', ActivityDate=d1.addDays(90),
            Subject='CA cadence: resume in 90 days', Description='Two-week cadence completed with no contact. Resume then.'));
        if (l.Omnishift_Disposition__c == null) { fx.Omnishift_Disposition__c = 'Call logged'; fx.Omnishift_Dispositioned_On__c = Datetime.now().addDays(-3); changed = true; }
    } else if (o == 'Replied, no meeting' || o == 'Too early' || o == 'Not interested') {
        cadence(l.Id, d1, 2, l.FirstName);
        if (l.Omnishift_Disposition__c == null) { fx.Omnishift_Disposition__c = 'Approved and sent'; fx.Omnishift_Dispositioned_On__c = Datetime.now().addDays(-4); changed = true; }
    } else if (o == null && l.Omnishift_Disposition__c != null) {
        cadence(l.Id, d1, 1, l.FirstName);
    }
    if (changed) fixes.add(fx);
}
for (Contact c : [SELECT Id, FirstName, Omnishift_Outcome__c, Omnishift_Disposition__c FROM Contact]) {
    Integer hashv = Math.abs(c.Id.hashCode());
    // clients get an annual review on the record, not a prospecting cadence
    Date rev = Date.today().addDays(-(200 + Math.mod(hashv, 160)));
    events.add(new Event(WhoId=c.Id, OwnerId=me, Subject='Discovery / annual review',
        StartDateTime=Datetime.newInstance(rev, Time.newInstance(11,0,0,0)),
        EndDateTime=Datetime.newInstance(rev, Time.newInstance(12,0,0,0)),
        Description='Annual review. Plan on track; revisit the concentrated position at the next one.'));
    if (c.Omnishift_Outcome__c == 'Meeting booked') {
        fixes.add(new Contact(Id=c.Id, Omnishift_Next_Action_Date__c=null,
            Omnishift_Disposition__c = c.Omnishift_Disposition__c == null ? 'Call logged' : c.Omnishift_Disposition__c));
    }
}
insert tasks; insert events;
if (!fixes.isEmpty()) { Database.update(fixes, false); }
System.debug('ACTS-' + tasks.size() + '-' + events.size() + '-' + fixes.size());
