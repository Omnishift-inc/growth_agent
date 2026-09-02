// DEMONSTRATION DATA ONLY - generated advisor dispositions and compliance outcomes.
// Deterministic, keyed on the record's position within its score band, so it is
// stable across re-runs and survives a re-rank by the nightly batch.
// Touches no email, phone, name or scoring field.
List<String> HIGH = new List<String>{'Approved and sent','Approved and sent','Call logged','Approved and sent','Edited before send','Approved and sent','Approved and sent'};
List<String> MID  = new List<String>{'Approved and sent','Edited before send','Call logged','Approved and sent','Edited before send','Snoozed','Edited before send'};
List<String> LOW  = new List<String>{'Snoozed',null,'Approved and sent','Snoozed','Wrong person','Edited before send',null,'Snoozed'};
List<String> COLD = new List<String>{null,'Snoozed','Wrong person',null,null,'Snoozed',null};

Map<String,String> EDIT_REASON = new Map<String,String>{
  'Edited before send' => 'Rewrote the opening. The why-now was right but the draft assumed a relationship we do not have yet.',
  'Snoozed'            => 'Good prospect, wrong month. Revisit once the quarter closes.',
  'Wrong person'       => 'Household mapping is wrong - this is not the account holder.',
  'Call logged'        => 'Picked up the phone instead. Better fit for a call than an email.',
  'Approved and sent'  => 'Sent as drafted.'
};

Integer hi = 0, mi = 0, lo = 0, co = 0;
List<SObject> ups = new List<SObject>();

for (SObject o : (List<SObject>) Database.query(
        'SELECT Id, Omnishift_Score__c, Omnishift_Rank__c FROM Lead WHERE Omnishift_Rank__c != null ORDER BY Omnishift_Rank__c')) {
    Decimal s = (Decimal) o.get('Omnishift_Score__c');
    String d;
    if (s >= 70)      { d = HIGH[Math.mod(hi++, HIGH.size())]; }
    else if (s >= 60) { d = MID[Math.mod(mi++, MID.size())]; }
    else if (s >= 50) { d = LOW[Math.mod(lo++, LOW.size())]; }
    else              { d = COLD[Math.mod(co++, COLD.size())]; }
    o.put('Omnishift_Disposition__c', d);
    o.put('Omnishift_Disposition_Reason__c', d == null ? null : EDIT_REASON.get(d));
    ups.add(o);
}
Integer hi2 = 0, mi2 = 0, lo2 = 0, co2 = 0;
for (SObject o : (List<SObject>) Database.query(
        'SELECT Id, Omnishift_Score__c, Omnishift_Rank__c FROM Contact WHERE Omnishift_Rank__c != null ORDER BY Omnishift_Rank__c')) {
    Decimal s = (Decimal) o.get('Omnishift_Score__c');
    String d;
    if (s >= 70)      { d = HIGH[Math.mod(hi2++, HIGH.size())]; }
    else if (s >= 60) { d = MID[Math.mod(mi2++, MID.size())]; }
    else if (s >= 50) { d = LOW[Math.mod(lo2++, LOW.size())]; }
    else              { d = COLD[Math.mod(co2++, COLD.size())]; }
    o.put('Omnishift_Disposition__c', d);
    o.put('Omnishift_Disposition_Reason__c', d == null ? null : EDIT_REASON.get(d));
    ups.add(o);
}

// Compliance variety, only on records that were not sent as written.
Integer n = 0;
for (SObject o : ups) {
    String d = (String) o.get('Omnishift_Disposition__c');
    n++;
    if (d == 'Approved and sent') continue;
    if (Math.mod(n, 13) == 0) {
        o.put('Omnishift_Compliance_Status__c', 'Blocked');
        o.put('Omnishift_Compliance_Reason__c', 'Draft implies a performance guarantee. Blocked from send until it is rewritten.');
    } else if (Math.mod(n, 9) == 0) {
        o.put('Omnishift_Compliance_Status__c', 'Flagged');
        o.put('Omnishift_Compliance_Reason__c', 'Draft cites a specific historical return figure. A principal must review it before send.');
    } else if (Math.mod(n, 4) == 0) {
        o.put('Omnishift_Compliance_Status__c', 'Auto-corrected');
        o.put('Omnishift_Compliance_Reason__c', 'Performance language softened and the standard advisory disclosure appended.');
    }
}
update ups;
System.debug('Updated ' + ups.size() + ' records with demonstration dispositions.');
