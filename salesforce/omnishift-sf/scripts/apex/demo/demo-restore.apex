// Bring the demo back to a full list with a real spread of scores.
// Three seed artefacts had emptied it: the outcome seed booked meetings for the
// best prospects (which rightly takes them off the list), the cadence seed parked
// a third of the rest behind 90-day tasks, and the calendar seed put yesterday's
// send on most clients. Signals had also aged out of their windows. Every value
// below is generated; no email, phone or name is touched.
Id me = UserInfo.getUserId();
Set<String> KEEP_BOOKED = new Set<String>{'Marlowe','Draycott'};     // one meeting each stays on record
Set<String> KEEP_PARKED = new Set<String>{'Hartrigg'};              // one parked cadence stays

List<Lead> leads = [SELECT Id, LastName, FirstName, Omnishift_Outcome__c, Omnishift_Disposition__c, Omnishift_Next_Action_Date__c
                    FROM Lead WHERE IsConverted = false AND Status NOT IN ('Closed - Not Converted') ORDER BY CreatedDate, LastName];
Set<Id> bookedKeep = new Set<Id>(), parkedKeep = new Set<Id>(), freed = new Set<Id>();
Integer bk = 0, pk = 0, altIx = 0;
List<String> ALT = new List<String>{'Replied, no meeting', 'Too early', null, 'Not interested', null};
List<Lead> lu = new List<Lead>();
for (Lead l : leads) {
    Boolean changed = false;
    if (l.Omnishift_Outcome__c == 'Meeting booked') {
        if (KEEP_BOOKED.contains(l.LastName) && bk < 2) { bookedKeep.add(l.Id); bk++; }
        else { l.Omnishift_Outcome__c = ALT[Math.mod(altIx++, ALT.size())]; freed.add(l.Id); changed = true; }
    } else if (l.Omnishift_Outcome__c == 'No response') {
        if (KEEP_PARKED.contains(l.LastName) && pk < 1) { parkedKeep.add(l.Id); pk++; }
        else { l.Omnishift_Outcome__c = ALT[Math.mod(altIx++, ALT.size())]; freed.add(l.Id); changed = true; }
    }
    if (freed.contains(l.Id)) {
        l.Omnishift_Outcome_On__c = l.Omnishift_Outcome__c == null ? null : Datetime.now().addDays(-3);
        if (l.Omnishift_Next_Action_Date__c == null) l.Omnishift_Next_Action_Date__c = Date.today();
        changed = true;
    }
    if (changed) lu.add(l);
}
update lu;
// the meeting and the parked task go with the outcome they belonged to
delete [SELECT Id FROM Event WHERE WhoId IN :freed AND Subject LIKE 'Initial meeting%'];
delete [SELECT Id FROM Task WHERE WhoId IN :freed AND Subject = 'CA cadence: resume in 90 days'];
// a cadence that ended weeks ago should not read as "contacted in the last two days"
List<Task> recent = [SELECT Id, ActivityDate FROM Task WHERE WhoId IN :freed AND ActivityDate >= :Date.today().addDays(-2)];
for (Task t : recent) t.ActivityDate = Date.today().addDays(-5);
update recent;

// ---- marketing calendar: one collision to demonstrate, the rest next week ----
Set<String> COLLIDE = new Set<String>{'Wexford', 'Blackwood'};
List<Omnishift_Marketing_Send__c> ms = [SELECT Id, Scheduled_For__c, Omnishift_Lead__r.LastName, Omnishift_Contact__r.LastName FROM Omnishift_Marketing_Send__c
                                        WHERE Scheduled_For__c >= :Datetime.now().addDays(-2) AND Scheduled_For__c <= :Datetime.now().addDays(4)];
Integer k = 0;
List<Omnishift_Marketing_Send__c> mu = new List<Omnishift_Marketing_Send__c>();
for (Omnishift_Marketing_Send__c m : ms) {
    String ln = m.Omnishift_Lead__c != null ? m.Omnishift_Lead__r.LastName : m.Omnishift_Contact__r.LastName;
    if (COLLIDE.contains(ln)) continue;
    Date d = Date.today().toStartOfWeek().addDays(8 + Math.mod(k, 4));   // Mon..Thu next week
    m.Scheduled_For__c = Datetime.newInstance(d, Time.newInstance(Math.mod(k, 2) == 0 ? 10 : 17, 0, 0, 0));
    mu.add(m); k++;
}
update mu;

// ---- signals: the feeds saw something recently for most of the list ----------
// Two in three prospects and one in two clients get their strongest signal moved
// into the last fortnight at a confidence a real feed would report. The rest keep
// older signals so ICP-fit and referral narratives still appear.
Set<String> ENGAGEMENT = new Set<String>{'Website research','Marketplace enquiry','Email engagement','Survey response','Webinar attendance'};
Map<Id, List<Omnishift_Signal__c>> byWho = new Map<Id, List<Omnishift_Signal__c>>();
for (Omnishift_Signal__c s : [SELECT Id, Omnishift_Lead__c, Omnishift_Contact__c, Signal_Type__c, Occurred_On__c, Observed_On__c, Confidence__c FROM Omnishift_Signal__c ORDER BY Confidence__c DESC]) {
    Id who = s.Omnishift_Lead__c != null ? s.Omnishift_Lead__c : s.Omnishift_Contact__c;
    if (!byWho.containsKey(who)) byWho.put(who, new List<Omnishift_Signal__c>());
    byWho.get(who).add(s);
}
List<Omnishift_Signal__c> su = new List<Omnishift_Signal__c>();
Integer i = 0;
for (Lead l : leads) {
    i++;
    if (bookedKeep.contains(l.Id) || parkedKeep.contains(l.Id)) continue;
    if (Math.mod(i, 3) == 0) continue;
    List<Omnishift_Signal__c> sigs = byWho.get(l.Id);
    if (sigs == null || sigs.isEmpty()) continue;
    Omnishift_Signal__c pick = sigs[0];
    for (Omnishift_Signal__c s : sigs) if (!ENGAGEMENT.contains(s.Signal_Type__c)) { pick = s; break; }
    Integer daysAgo = Math.mod(i * 5, 13);                 // 0..12 days
    pick.Occurred_On__c = Date.today().addDays(-daysAgo);
    pick.Observed_On__c = Datetime.newInstance(pick.Occurred_On__c, Time.newInstance(9, 0, 0, 0)).addHours(Math.mod(i * 7, 40) + 2);
    pick.Confidence__c  = 78 + Math.mod(i * 7, 20);        // 78..97
    su.add(pick);
}
i = 0;
for (Contact c : [SELECT Id FROM Contact ORDER BY CreatedDate, LastName]) {
    i++;
    if (Math.mod(i, 2) == 0) continue;
    List<Omnishift_Signal__c> sigs = byWho.get(c.Id);
    if (sigs == null || sigs.isEmpty()) continue;
    Omnishift_Signal__c pick = sigs[0];
    for (Omnishift_Signal__c s : sigs) if (!ENGAGEMENT.contains(s.Signal_Type__c)) { pick = s; break; }
    Integer daysAgo = Math.mod(i * 4, 12);
    pick.Occurred_On__c = Date.today().addDays(-daysAgo);
    pick.Observed_On__c = Datetime.newInstance(pick.Occurred_On__c, Time.newInstance(9, 0, 0, 0)).addHours(Math.mod(i * 5, 30) + 2);
    pick.Confidence__c  = 80 + Math.mod(i * 9, 18);
    su.add(pick);
}
update su;
System.debug('RESTORE leads=' + lu.size() + ' freed=' + freed.size() + ' sends moved=' + mu.size() + ' signals refreshed=' + su.size());
System.debug(OmnishiftEngineBatch.runNow());
