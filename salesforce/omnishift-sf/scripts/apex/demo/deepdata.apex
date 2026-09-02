// Rebuilds the signal history so every scored person carries a plausible trail
// across the tools the firm actually runs, each writing in its own voice: a
// filing reads nothing like a page view, which reads nothing like a survey
// answer. Every record says it is generated.
delete [SELECT Id FROM Omnishift_Signal__c];
delete [SELECT Id FROM Omnishift_Marketing_Send__c];

String NOTE = ' [Generated demonstration record - no real person or event.]';

// ---- what each source can see, and how it says it -------------------------
Map<String, List<String>> TYPES = new Map<String, List<String>>{
  'WealthFeed'         => new List<String>{'Business sale','Liquidity event','Property transaction','Inheritance filing','Retirement'},
  'VisitIQ'            => new List<String>{'Website research'},
  'SmartAsset AMP'     => new List<String>{'Marketplace enquiry'},
  'Account Engagement' => new List<String>{'Email engagement'},
  'GetFeedback'        => new List<String>{'Survey response'},
  'LinkedIn'           => new List<String>{'Role change'},
  'Zoom'               => new List<String>{'Webinar attendance'}
};

Map<String, List<String>> EVIDENCE = new Map<String, List<String>>{
  'WealthFeed' => new List<String>{
    'Form D filed 14 Aug 2026, Rule 506(b), total offering $18.4m. Filer address matches the household record. Confidence high on name + state + entity officer match.',
    'UCC-3 termination filed against the operating company, which usually follows a sale closing. Secretary of State record, matched on officer name and DBA.',
    'Deed transfer recorded, commercial parcel, consideration $4.1m above assessed. County recorder feed, matched on grantor name and mailing address.',
    'Probate filing lists the household as beneficiary. Court record, matched on surname, county and decedent address.',
    'Form 4 insider sale, 42,000 shares disposed following lock-up expiry. SEC EDGAR, matched on reporting person CIK.'
  },
  'VisitIQ' => new List<String>{
    'Four sessions in nine days from one de-anonymised visitor. Path: /succession-planning, /team, /team/gus-dow, then /succession-planning again for 6m 12s. Matched to household by IP-to-company plus form fill on a prior visit.',
    'Return visit after 11 months dormant. Landed on /fees, then /our-process, then the fee schedule PDF. Session 8m 40s, no form submitted.',
    'Three visits to /business-owners in a fortnight, each arriving from a different device on the same household IP.'
  },
  'SmartAsset AMP' => new List<String>{
    'Matched enquiry, self-reported investable assets $2.5m-$5m, stated goal "retirement planning", timeframe "within 3 months". Marketplace lead, not exclusive - assume competing advisers received it.',
    'Second enquiry from the same household in six weeks, this time self-reporting $5m+ and "business sale proceeds".'
  },
  'Account Engagement' => new List<String>{
    'Opened the Aug 26 Dow drip four times, clicked through to the succession piece twice, forwarded once. Prospect score 78, grade B+. No form submission yet.',
    'Score moved 34 to 71 in eleven days on email engagement alone. Grade unchanged at C+, which is profile fit, not behaviour.',
    'Unsubscribed from Market Commentary but stayed opted in to everything else - a preference, not a rejection.'
  },
  'GetFeedback' => new List<String>{
    'Annual survey response: satisfaction 9/10, "very likely" to refer, free text names two people they had already mentioned to their adviser.',
    'Survey response flags an upcoming liquidity event in the free text field that appears nowhere else in the record.'
  },
  'LinkedIn' => new List<String>{
    'Title changed from Chief Operating Officer to Board Director. Company unchanged. Compensation mix typically shifts from salary to equity at this transition.',
    'Announced a move to a new firm after nine years, which usually puts a legacy retirement plan in play.'
  },
  'Zoom' => new List<String>{
    'Attended the Q3 business-owner webinar, stayed 46 of 50 minutes, asked one question in chat about concentrated stock.',
    'Registered for the tax-season webinar and did not attend, then watched the recording twice.'
  }
};

List<Lead> leads = [SELECT Id FROM Lead WHERE IsConverted = false ORDER BY CreatedDate];
List<Contact> cons = [SELECT Id FROM Contact ORDER BY CreatedDate];
List<String> SRC = new List<String>(EVIDENCE.keySet());

List<Omnishift_Signal__c> out = new List<Omnishift_Signal__c>();
Integer n = 0;

// Give most people two or three signals from different tools, because that is
// what a real record looks like: one strong event and a trail of engagement.
for (Lead l : leads) {
    Integer howMany = Math.mod(n, 5) == 0 ? 3 : (Math.mod(n, 3) == 0 ? 2 : 1);
    for (Integer k = 0; k < howMany; k++) {
        String src = SRC[Math.mod(n * 3 + k * 2, SRC.size())];
        List<String> ev = EVIDENCE.get(src);
        List<String> ty = TYPES.get(src);
        Integer daysAgo = Math.mod(n * 7 + k * 13, 95);
        Datetime occurred = Datetime.now().addDays(-daysAgo);
        out.add(new Omnishift_Signal__c(
            Name = src + ' - ' + ty[Math.mod(n + k, ty.size())],
            Omnishift_Lead__c = l.Id,
            Signal_Type__c    = ty[Math.mod(n + k, ty.size())],
            Source__c         = src,
            Source_System__c  = src,
            Occurred_On__c    = occurred.date(),
            // Feeds lag. The gap between the event and our seeing it is the
            // number that decides whether we are early or late.
            Observed_On__c    = occurred.addHours(Math.mod(n * 5 + k, 72) + 2),
            Confidence__c     = 58 + Math.mod(n * 11 + k * 7, 42),
            External_Id__c    = src.left(3).toUpperCase() + '-' + String.valueOf(100000 + n * 7 + k),
            Evidence__c       = ev[Math.mod(n + k, ev.size())] + NOTE,
            Detail__c         = ev[Math.mod(n + k, ev.size())].left(180) + NOTE
        ));
    }
    n++;
}
n = 0;
for (Contact c : cons) {
    Integer howMany = Math.mod(n, 4) == 0 ? 3 : 2;
    for (Integer k = 0; k < howMany; k++) {
        String src = SRC[Math.mod(n * 5 + k * 3, SRC.size())];
        List<String> ev = EVIDENCE.get(src);
        List<String> ty = TYPES.get(src);
        Integer daysAgo = Math.mod(n * 9 + k * 17, 110);
        Datetime occurred = Datetime.now().addDays(-daysAgo);
        out.add(new Omnishift_Signal__c(
            Name = src + ' - ' + ty[Math.mod(n + k, ty.size())],
            Omnishift_Contact__c = c.Id,
            Signal_Type__c    = ty[Math.mod(n + k, ty.size())],
            Source__c         = src,
            Source_System__c  = src,
            Occurred_On__c    = occurred.date(),
            Observed_On__c    = occurred.addHours(Math.mod(n * 3 + k, 60) + 2),
            Confidence__c     = 62 + Math.mod(n * 13 + k * 5, 38),
            External_Id__c    = src.left(3).toUpperCase() + '-C' + String.valueOf(200000 + n * 5 + k),
            Evidence__c       = ev[Math.mod(n + k, ev.size())] + NOTE,
            Detail__c         = ev[Math.mod(n + k, ev.size())].left(180) + NOTE
        ));
    }
    n++;
}
insert out;
System.debug('SIGNALS-' + out.size());

// ---- the marketing calendar, as Account Engagement holds it ---------------
List<String> SENDS = new List<String>{
  'Aug 26 Gus Dow Send','Aug 26 Alex Dow Send','Q3 Market Commentary',
  'Business Owner Webinar Invitation','Tax Season Reminder','Quarterly Newsletter'
};
List<String> CTYPE = new List<String>{
  'Dow drip','Dow drip','Market commentary','Webinar invitation','Tax season','Newsletter'
};
List<String> AUD = new List<String>{
  'Prospects - business owners','Prospects - all','Clients and prospects',
  'Prospects - $2m+','Clients - all','Clients and prospects'
};
List<Omnishift_Marketing_Send__c> calendarRows = new List<Omnishift_Marketing_Send__c>();
n = 0;
for (Lead l : leads) {
    // Only some people are in a campaign at any time.
    if (Math.mod(n, 4) != 1) { n++; continue; }
    Integer i = Math.mod(n, SENDS.size());
    calendarRows.add(new Omnishift_Marketing_Send__c(
        Name = SENDS[i],
        Omnishift_Lead__c = l.Id,
        Scheduled_For__c = Datetime.now().addDays(Math.mod(n * 3, 12) - 2).addHours(17),
        Campaign_Type__c = CTYPE[i],
        Audience__c      = AUD[i],
        Source_System__c = 'Account Engagement',
        External_Id__c   = 'AE-' + String.valueOf(500000 + n)
    ));
    n++;
}
n = 0;
for (Contact c : cons) {
    if (Math.mod(n, 5) != 2) { n++; continue; }
    Integer i = Math.mod(n + 2, SENDS.size());
    calendarRows.add(new Omnishift_Marketing_Send__c(
        Name = SENDS[i],
        Omnishift_Contact__c = c.Id,
        Scheduled_For__c = Datetime.now().addDays(Math.mod(n * 4, 14) - 1).addHours(17),
        Campaign_Type__c = CTYPE[i],
        Audience__c      = AUD[i],
        Source_System__c = 'Account Engagement',
        External_Id__c   = 'AE-C' + String.valueOf(600000 + n)
    ));
    n++;
}
insert calendarRows;
System.debug('SENDS-' + calendarRows.size());
