// Evidence that matches the signal it sits under, in the words the source
// tool would use, varying per household. The previous seed handed out
// evidence by position, so a retirement carried a Form 4 sale and three
// people shared one $18.4m Form D. One sentence each, dates from the signal
// itself, amounts and counts derived from the record. Generated data.
String NOTE = ' [Generated demonstration record - no real person or event.]';
Map<Id, String> company = new Map<Id, String>();
for (Lead l : [SELECT Id, Company FROM Lead]) company.put(l.Id, l.Company);
for (Contact c : [SELECT Id, Account.Name FROM Contact]) company.put(c.Id, c.Account == null ? 'the household company' : c.Account.Name);
List<String> OLDT = new List<String>{'Chief Operating Officer','Managing Director','General Counsel','Head of Trading','Chief Financial Officer'};
List<String> NEWT = new List<String>{'Board Director','Senior Adviser','Executive Chair','Non-Executive Director','Partner'};
List<String> GOAL = new List<String>{'retirement planning','business sale proceeds','concentrated stock','estate planning','college funding'};
List<String> PIECE = new List<String>{'succession-planning','estate-planning','concentrated-positions','business-owner','fee-schedule'};
List<String> TOPIC = new List<String>{'a pending relocation','an inheritance expected this year','selling a minority stake','a second home purchase','retiring in eighteen months'};
List<Omnishift_Signal__c> sigs = [SELECT Id, Signal_Type__c, Source__c, Occurred_On__c, Confidence__c, Omnishift_Lead__c, Omnishift_Contact__c FROM Omnishift_Signal__c ORDER BY Occurred_On__c DESC];
Integer i = 0;
for (Omnishift_Signal__c s : sigs) {
    Id who = s.Omnishift_Lead__c != null ? s.Omnishift_Lead__c : s.Omnishift_Contact__c;
    String co = company.containsKey(who) && company.get(who) != null ? company.get(who) : 'the operating company';
    Integer h = Math.abs(String.valueOf(who).hashCode()) + i * 31;
    String d = s.Occurred_On__c == null ? 'this month' : s.Occurred_On__c.format();
    Decimal m1 = (Decimal) (2 + Math.mod(h, 27)) + (Decimal) Math.mod(h, 10) / 10;   // 2.0 .. 28.9
    Integer n1 = 3 + Math.mod(h, 5);
    String t = s.Signal_Type__c;
    String ev;
    if (t == 'Business sale') {
        ev = Math.mod(h, 2) == 0
            ? 'Form D filed ' + d + ', Rule 506(b), total offering $' + m1 + 'm; filer address matches the household record'
            : 'UCC-3 termination filed ' + d + ' against ' + co + ', which usually follows a sale closing; Secretary of State record matched on officer name';
    } else if (t == 'Liquidity event') {
        ev = Math.mod(h, 2) == 0
            ? 'Form 4 insider sale filed ' + d + ', ' + (20 + Math.mod(h, 60)) + ',000 shares disposed following lock-up expiry; SEC EDGAR, matched on reporting person'
            : 'Lock-up on a post-IPO holding expires ' + d.left(6) + '; position worth roughly $' + m1 + 'm at the current price';
    } else if (t == 'Property transaction') {
        ev = 'Deed transfer recorded ' + d + ', commercial parcel, consideration $' + m1 + 'm above assessed value; county recorder feed, matched on grantor name and mailing address';
    } else if (t == 'Inheritance filing') {
        ev = 'Probate filing ' + d + ' names the household as beneficiary of an estate of roughly $' + m1 + 'm; court record, matched on surname, county and decedent address';
    } else if (t == 'Retirement') {
        ev = 'Retirement effective end of quarter announced by ' + co + ' on ' + d + '; plan rollover decision pending on roughly $' + m1 + 'm';
    } else if (t == 'Website research') {
        ev = n1 + ' sessions in ' + (n1 * 2 + 1) + ' days from one de-anonymised visitor: /' + PIECE[Math.mod(h, PIECE.size())] + ', /team, /fees, longest ' + (4 + Math.mod(h, 8)) + 'm ' + (10 + Math.mod(h, 50)) + 's; matched by IP-to-company plus a prior form fill';
    } else if (t == 'Marketplace enquiry') {
        ev = 'Matched enquiry ' + d + ', self-reported investable assets $' + (Math.mod(h, 2) == 0 ? '2.5m-$5m' : '5m+') + ', stated goal "' + GOAL[Math.mod(h, GOAL.size())] + '", timeframe "within ' + n1 + ' months"; marketplace lead, not exclusive';
    } else if (t == 'Email engagement') {
        ev = 'Opened the ' + (s.Omnishift_Contact__c != null ? 'quarterly client letter' : 'Aug 26 Dow drip') + ' ' + n1 + ' times and clicked through to the ' + PIECE[Math.mod(h, PIECE.size())].replace('-', ' ') + ' piece twice; prospect score ' + (60 + Math.mod(h, 35)) + ', grade ' + (Math.mod(h, 3) == 0 ? 'A-' : 'B+') + '; no form submitted';
    } else if (t == 'Survey response') {
        ev = 'Survey response ' + d + ': satisfaction ' + (7 + Math.mod(h, 3)) + '/10, "' + (Math.mod(h, 2) == 0 ? 'very likely' : 'likely') + '" to refer; free text mentions ' + TOPIC[Math.mod(h, TOPIC.size())];
    } else if (t == 'Role change') {
        ev = Math.mod(h, 2) == 0
            ? 'Title changed from ' + OLDT[Math.mod(h, OLDT.size())] + ' to ' + NEWT[Math.mod(h, NEWT.size())] + ' at ' + co + ' on ' + d + '; compensation mix typically shifts from salary to equity at this transition'
            : 'Announced a move from ' + co + ' to a new firm after ' + (6 + Math.mod(h, 12)) + ' years on ' + d + ', which puts a legacy retirement plan in play';
    } else if (t == 'Webinar attendance') {
        ev = 'Attended the ' + (Math.mod(h, 2) == 0 ? 'Q3 business-owner' : 'tax-season') + ' webinar on ' + d + ', stayed ' + (38 + Math.mod(h, 12)) + ' of 50 minutes, asked one question in chat about ' + GOAL[Math.mod(h, GOAL.size())];
    } else {
        ev = t + ' reported by ' + s.Source__c + ' on ' + d;
    }
    s.Evidence__c = ev + '.' + NOTE;
    s.Detail__c   = (ev + '.').left(180) + NOTE;
    i++;
}
update sigs;
System.debug('EVIDENCE ' + sigs.size());
System.debug(OmnishiftEngineBatch.runNow());
