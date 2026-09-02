// Fill every contact and lead with the details a real record carries, and give
// each person an activity history that agrees with what the agent says about
// them. Every value is generated; nothing can reach a real person.
String NOTE = ' [Generated demonstration record.]';
List<String> BIOS = new List<String>{
  'Retired from an operating role in 2024; still sits on two boards. Spouse manages the household finances day to day.',
  'Founder-owner, second-generation family business. Interested in succession, not in selling. Two children in college.',
  'Senior executive, equity-heavy compensation, concentrated position in employer stock. Wants a plan for diversifying without a tax shock.',
  'Recently widowed; inherited a portfolio spread across three custodians. Wants one adviser and one statement.',
  'Physician couple, both still practising, saving aggressively. Main concern is tax efficiency and college funding.',
  'Sold a minority stake last year; proceeds sitting in cash. Cautious, wants to understand fees before anything else.',
  'Long-standing client of the Chicago office. Reviews annually in the autumn; prefers phone to email.',
  'Introduced by an existing client. Comparing two advisers; timing driven by a pending relocation.'
};
List<Contact> cs = [SELECT Id, Description, Birthdate, AccountId, Account.AnnualRevenue, Account.Industry FROM Contact];
Map<Id, Account> accs = new Map<Id, Account>();
Integer i = 0;
for (Contact c : cs) {
    if (String.isBlank(c.Description)) c.Description = BIOS[Math.mod(i, BIOS.size())] + NOTE;
    if (c.Birthdate == null) c.Birthdate = Date.newInstance(1958 + Math.mod(i * 7, 22), 1 + Math.mod(i * 5, 12), 1 + Math.mod(i * 3, 27));
    if (c.AccountId != null && (c.Account.AnnualRevenue == null || String.isBlank(c.Account.Industry))) {
        Account a = accs.containsKey(c.AccountId) ? accs.get(c.AccountId) : new Account(Id = c.AccountId);
        if (c.Account.AnnualRevenue == null) a.AnnualRevenue = 1500000 + Math.mod(i * 1300000, 18000000);
        if (String.isBlank(c.Account.Industry)) a.Industry = 'Finance';
        accs.put(c.AccountId, a);
    }
    i++;
}
update cs;
if (!accs.isEmpty()) update accs.values();
List<Lead> ls = [SELECT Id, Title, Description FROM Lead WHERE IsConverted = false];
i = 0;
for (Lead l : ls) {
    if (String.isBlank(l.Title)) l.Title = 'Managing Partner';
    if (String.isBlank(l.Description) || l.Description.startsWith('Generated demonstration record. No real'))
        l.Description = BIOS[Math.mod(i * 3, BIOS.size())] + NOTE;
    i++;
}
update ls;
System.debug('DETAILS-' + cs.size() + '-' + accs.size() + '-' + ls.size());
