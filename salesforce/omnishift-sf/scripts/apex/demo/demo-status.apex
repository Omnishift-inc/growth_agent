// A prospect who has been emailed or called is not "Open - Not Contacted".
// The standard Lead status must agree with what the agent recorded.
List<Lead> ups = new List<Lead>();
for (Lead l : [SELECT Id, Status, Omnishift_Disposition__c FROM Lead WHERE IsConverted = false AND Status = 'Open - Not Contacted'
               AND Omnishift_Disposition__c IN ('Approved and sent', 'Edited before send', 'Call logged')]) {
    l.Status = 'Working - Contacted'; ups.add(l);
}
update ups;
System.debug('STATUS aligned=' + ups.size());
