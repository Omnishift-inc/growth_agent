// Replace fabricated compliance verdicts with earned ones. Every status below is
// produced by running the real checker over text that genuinely contains what the
// reason says it contains, so the record and the verdict agree and a reviewer can
// read the draft and see exactly why it was ruled on.
List<Lead> ls = [SELECT Id, FirstName, Omnishift_Draft_Subject__c FROM Lead
                 WHERE Omnishift_Rank__c != null ORDER BY Omnishift_Rank__c];
List<Contact> cs = [SELECT Id, FirstName, Omnishift_Draft_Subject__c FROM Contact
                    WHERE Omnishift_Rank__c != null ORDER BY Omnishift_Rank__c];

List<Lead> lclear = new List<Lead>();
for (Lead l : ls) lclear.add(new Lead(Id = l.Id, Omnishift_Draft_Edited__c = false));
update lclear;
List<Contact> cclear = new List<Contact>();
for (Contact c : cs) cclear.add(new Contact(Id = c.Id, Omnishift_Draft_Edited__c = false));
update cclear;

// Text an advisor might plausibly type, each tripping a different real rule.
List<String> BLOCKING = new List<String>{
  ' Our approach has delivered guaranteed results for families in your position.',
  ' This is a risk-free way to hold the proceeds while you decide.'
};
List<String> FLAGGING = new List<String>{
  ' Our clients say the difference shows up in the first year.',
  ' The aim is simply to grow your wealth steadily.'
};
List<String> AUTOFIX = new List<String>{
  ' We are the best firm in the city for work of this kind.',
  ' Act now and we can still fit the planning into this tax year.'
};

Integer applied = 0;
for (Integer i = 0; i < ls.size(); i++) {
    String extra;
    if (Math.mod(i, 7) == 0)      extra = BLOCKING[Math.mod(i, BLOCKING.size())];
    else if (Math.mod(i, 7) == 3) extra = FLAGGING[Math.mod(i, FLAGGING.size())];
    else if (Math.mod(i, 7) == 5) extra = AUTOFIX[Math.mod(i, AUTOFIX.size())];
    else continue;
    Lead l = ls[i];
    String body = l.FirstName + ' - a short note before the quarter closes.' + extra;
    OmnishiftAction.saveDraft(l.Id, l.Omnishift_Draft_Subject__c, body);
    applied++;
}
for (Integer i = 0; i < cs.size(); i++) {
    String extra;
    if (Math.mod(i, 9) == 2)      extra = BLOCKING[Math.mod(i, BLOCKING.size())];
    else if (Math.mod(i, 9) == 5) extra = AUTOFIX[Math.mod(i, AUTOFIX.size())];
    else continue;
    Contact c = cs[i];
    String body = c.FirstName + ' - worth a short conversation this quarter.' + extra;
    OmnishiftAction.saveDraft(c.Id, c.Omnishift_Draft_Subject__c, body);
    applied++;
}
System.debug('EARNED-' + applied);
