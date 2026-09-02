@isTest
private class OmnishiftEngineTest {

    @isTest static void referralScoresHigherThanColdList() {
        Lead ref  = new Lead(LastName='A', Company='A Co', LeadSource='Referral', AnnualRevenue=5000000);
        Lead cold = new Lead(LastName='B', Company='B Co', LeadSource='Purchased List', AnnualRevenue=5000000);
        insert new List<Lead>{ ref, cold };
        ref  = [SELECT Id, FirstName, LastName, LeadSource, AnnualRevenue, CreatedDate, LastActivityDate, State FROM Lead WHERE Id=:ref.Id];
        cold = [SELECT Id, FirstName, LastName, LeadSource, AnnualRevenue, CreatedDate, LastActivityDate, State FROM Lead WHERE Id=:cold.Id];
        System.assert(OmnishiftEngine.score(ref).score > OmnishiftEngine.score(cold).score,
            'A referral must outrank a purchased-list lead');
    }

    @isTest static void suppressesRecordWeAlreadyOwn() {
        Lead l = new Lead(LastName='Dupe', Company='X', Email='dupe@example.com');
        OmnishiftEngine.Outcome o = OmnishiftEngine.suppressionCheck(
            l, new Set<String>{'dupe@example.com'}, new Set<String>());
        System.assert(o.suppressed, 'A lead matching an owned contact email must be suppressed');
        System.assert(o.suppressReason.contains('cross-reference'));
    }

    @isTest static void complianceBlocksGuaranteeAndPerformance() {
        System.assertEquals('Blocked',
            OmnishiftEngine.complianceCheck('x', 'we guarantee results').complianceStatus);
        System.assertEquals('Blocked',
            OmnishiftEngine.complianceCheck('x', 'we returned 12% annually').complianceStatus);
        System.assertEquals('Flagged',
            OmnishiftEngine.complianceCheck('x', 'our clients say we are great').complianceStatus);
        System.assertEquals('Auto-corrected',
            OmnishiftEngine.complianceCheck('x', 'the best firm around').complianceStatus);
        System.assertEquals('Passed',
            OmnishiftEngine.complianceCheck('A short introduction', 'Happy to make time.').complianceStatus);
    }

    @isTest static void draftsAreCleanByDefault() {
        Lead l = new Lead(FirstName='Ann', LastName='Lee', Company='Lee Co');
        for (String d : new List<String>{'Referral','Inbound web','New and unworked','ICP fit'}) {
            OmnishiftEngine.Outcome o = OmnishiftEngine.draft(l, d);
            System.assertEquals('Passed',
                OmnishiftEngine.complianceCheck(o.draftSubject, o.draftBody).complianceStatus,
                'Our own templates must pass compliance: ' + d);
        }
    }

    @isTest static void batchScoresAndRanks() {
        List<Lead> ls = new List<Lead>();
        for (Integer i = 0; i < 20; i++) {
            ls.add(new Lead(LastName='L'+i, Company='C'+i,
                LeadSource = (Math.mod(i,2)==0 ? 'Referral' : 'Purchased List'),
                AnnualRevenue = 1000000 * i));
        }
        insert ls;
        Test.startTest();
        Database.executeBatch(new OmnishiftEngineBatch(), 200);
        Test.stopTest();
        Integer scored = [SELECT COUNT() FROM Lead WHERE Omnishift_Score__c > 0];
        System.assert(scored > 0, 'The batch must score leads');
        Integer ranked = [SELECT COUNT() FROM Lead WHERE Omnishift_Rank__c = 1];
        System.assertEquals(1, ranked, 'Exactly one lead holds rank 1');
    }

    @isTest static void runNowReturnsAJobId() {
        Test.startTest();
        String jobId = OmnishiftEngineBatch.runNow();
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }

    @isTest static void schedulerRuns() {
        Test.startTest();
        System.schedule('OmnishiftTest', '0 0 2 * * ?', new OmnishiftEngineSchedule());
        Test.stopTest();
    }

    @isTest static void autoCorrectActuallyRemovesTheTerm() {
        OmnishiftEngine.Outcome c = OmnishiftEngine.complianceCheck(
            'Worth a conversation?', 'Margaret - we are the best firm in Chicago. No pitch.');
        System.assertEquals('Auto-corrected', c.complianceStatus);
        System.assert(c.complianceReason.contains('Re-read'),
            'Stripping a phrase can leave a limping sentence; the advisor must be told: '
            + c.complianceReason);
        System.assertNotEquals(null, c.draftBody,
            'An auto-corrected result must return the corrected text, not null.');
        System.assert(!c.draftBody.toLowerCase().contains('best'),
            'The term the label claims was removed must actually be gone: ' + c.draftBody);
        System.assert(c.draftBody.contains('firm in Chicago'), 'The rest of the sentence must survive.');
        System.assert(!c.draftBody.contains('  '), 'No double spaces left behind: ' + c.draftBody);
    }

    @isTest static void aPassingDraftIsLeftAlone() {
        OmnishiftEngine.Outcome c = OmnishiftEngine.complianceCheck('Hello', 'A plain and honest note.');
        System.assertEquals('Passed', c.complianceStatus);
        System.assertEquals(null, c.draftBody, 'Nothing to correct means nothing returned.');
    }

    @isTest static void complianceReasonDoesNotTouchTheAdvisorsReason() {
        Lead l = new Lead(FirstName='Ada', LastName='Byron', Company='Engines',
                          LeadSource='Referral', Status='Open - Not Contacted',
                          Omnishift_Disposition_Reason__c='Advisor said the timing was wrong');
        insert l;
        Test.startTest();
        OmnishiftEngineBatch.runNow();
        Test.stopTest();
        Lead after = [SELECT Omnishift_Disposition_Reason__c, Omnishift_Compliance_Reason__c
                      FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Advisor said the timing was wrong', after.Omnishift_Disposition_Reason__c,
            'A scoring run must not overwrite what the advisor recorded.');
        System.assertNotEquals(null, after.Omnishift_Compliance_Reason__c,
            'The compliance reason belongs in its own field.');
    }

    @isTest static void aFreshWebEnquirySaysSoEvenWhenTimingWins() {
        Lead l = new Lead(FirstName='Wren', LastName='Ashcombe', Company='Ashcombe Partners',
                          LeadSource='Web', Status='Open - Not Contacted');
        insert l;
        Lead fresh = [SELECT Id, FirstName, LastName, Company, Email, State, Status, LeadSource,
                             AnnualRevenue, DoNotCall, HasOptedOutOfEmail, IsConverted,
                             CreatedDate, LastActivityDate FROM Lead WHERE Id = :l.Id];
        OmnishiftEngine.Outcome o = OmnishiftEngine.score(fresh);
        System.assertEquals('New and unworked', o.topDriver,
            'Timing outweighs web intake for a brand new lead - that is the model.');
        System.assert(o.whyNow.contains('inbound web enquiry'),
            'But the advisor still has to be told it came from a form: ' + o.whyNow);
        System.assert(o.whyNow.contains('five-minute'), o.whyNow);
    }

    @isTest static void aReferralThatLosesOnTimingIsStillNamedAReferral() {
        Lead l = new Lead(FirstName='Soren', LastName='Blackwood', Company='Blackwood Holdings',
                          LeadSource='Partner Referral', Status='Open - Not Contacted',
                          AnnualRevenue=50000000);
        insert l;
        Lead fresh = [SELECT Id, FirstName, LastName, Company, Email, State, Status, LeadSource,
                             AnnualRevenue, DoNotCall, HasOptedOutOfEmail, IsConverted,
                             CreatedDate, LastActivityDate FROM Lead WHERE Id = :l.Id];
        OmnishiftEngine.Outcome o = OmnishiftEngine.score(fresh);
        if (o.topDriver != 'Referral') {
            System.assert(o.whyNow.contains('referral'),
                'A referral must never disappear from the explanation: ' + o.whyNow);
        }
    }

    // ---- Contacts ----------------------------------------------------------
    // The existing-client half. CreatedDate and LastActivityDate are read-only,
    // so the rules that turn on them are exercised through Prospect directly;
    // everything reachable from a real record is exercised on one.

    private static Contact client(String first, String last, String source, String title, Id accountId) {
        return new Contact(FirstName=first, LastName=last, Email=first.toLowerCase()+'.'+last.toLowerCase()+'@example.com',
                           LeadSource=source, Title=title, AccountId=accountId,
                           MailingCountry='United States', MailingState='Illinois');
    }

    private static final String CONTACT_FIELDS =
        'Id, FirstName, LastName, Email, MailingState, Title, LeadSource, AccountId, '
      + 'Account.AnnualRevenue, DoNotCall, HasOptedOutOfEmail, CreatedDate, LastActivityDate';

    @isTest static void aClientIsScoredLikeAClientNotAProspect() {
        Account a = new Account(Name='Vexley Holdings', AnnualRevenue=5000000);
        insert a;
        Contact c = client('Greta','Vexley','Purchased List','CFO', a.Id);
        insert c;
        Contact fresh = (Contact) Database.query('SELECT ' + CONTACT_FIELDS + ' FROM Contact')[0];
        OmnishiftEngine.Outcome o = OmnishiftEngine.score(fresh);

        System.assert(o.score > 0, 'A Contact must come out of the engine with a score, not a blank');
        System.assert(!o.whyNow.contains('five-minute'),
            'A client must never be told they filed an inbound enquiry: ' + o.whyNow);
        System.assert(!o.whyNow.contains('never contacted'),
            'A client is not an unworked lead: ' + o.whyNow);
        System.assertNotEquals('New and unworked', o.topDriver,
            'A client has no intake event to be new against; that driver is prospect-only');
    }

    @isTest static void anIntroducedClientOutranksOneOffAList() {
        Account a = new Account(Name='Same Account', AnnualRevenue=5000000);
        insert a;
        Contact introduced = client('Ferris','Ollerton','External Referral','CFO', a.Id);
        Contact listed     = client('Orsola','Blackwood','Purchased List','CFO', a.Id);
        insert new List<Contact>{ introduced, listed };
        Map<Id, Contact> byId = new Map<Id, Contact>(
            (List<Contact>) Database.query('SELECT ' + CONTACT_FIELDS + ' FROM Contact'));
        Integer intro = OmnishiftEngine.score(byId.get(introduced.Id)).score;
        Integer cold  = OmnishiftEngine.score(byId.get(listed.Id)).score;
        System.assert(intro > cold,
            'Same account, same seniority: the household that arrived by introduction must rank higher ('
            + intro + ' vs ' + cold + ')');
        System.assertEquals('Referral', OmnishiftEngine.score(byId.get(introduced.Id)).topDriver,
            'An introduced client is driven by the introduction, not by profile');
    }

    @isTest static void seniorityLiftsFitWhenTheAccountIsTheSame() {
        Account a = new Account(Name='One Account', AnnualRevenue=600000);
        insert a;
        Contact chief = client('Maeve','Netherby','Other','Chief Investment Officer', a.Id);
        Contact staff = client('Piers','Ironwood','Other','Warehouse Coordinator', a.Id);
        insert new List<Contact>{ chief, staff };
        Map<Id, Contact> byId = new Map<Id, Contact>(
            (List<Contact>) Database.query('SELECT ' + CONTACT_FIELDS + ' FROM Contact'));
        System.assert(OmnishiftEngine.score(byId.get(chief.Id)).score
                    > OmnishiftEngine.score(byId.get(staff.Id)).score,
            'Company revenue is the same, so the decision-maker has to be the better fit');
    }

    @isTest static void aClientPastTheAnnualReviewIsCalledOverdue() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.objectType = 'Contact';
        p.isClient = true;
        p.firstName = 'Niall'; p.lastName = 'Ullswater';
        p.intakeChannel = 'Other';
        p.fitValue = 400000;
        p.createdDate = Datetime.now().addDays(-900);
        p.lastActivityDate = Date.today().addDays(-400);

        OmnishiftEngine.Outcome o = OmnishiftEngine.score(p);
        System.assertEquals('Review overdue', o.topDriver,
            'Thirteen months of silence on a client relationship is the strongest thing on the record');
        System.assert(o.whyNow.contains('annual review'),
            'The advisor has to be told which standard was missed: ' + o.whyNow);
        System.assertEquals('Passed',
            OmnishiftEngine.complianceCheck(
                OmnishiftEngine.draft(p, o.topDriver).draftSubject,
                OmnishiftEngine.draft(p, o.topDriver).draftBody).complianceStatus,
            'The overdue-review template must clear compliance like every other one');
    }

    @isTest static void clientDraftsAreCleanAndNeverGreetAClientAsAStranger() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.isClient = true; p.firstName = 'Thea'; p.lastName = 'Mossgrove';
        for (String d : new List<String>{'Referral','Review overdue','Existing relationship','Dormant','ICP fit'}) {
            OmnishiftEngine.Outcome o = OmnishiftEngine.draft(p, d);
            System.assertEquals('Passed',
                OmnishiftEngine.complianceCheck(o.draftSubject, o.draftBody).complianceStatus,
                'Client templates must pass compliance: ' + d);
            System.assert(!o.draftBody.contains('thank you for getting in touch'),
                'That is the reply to a web form, not a note to a client: ' + d);
            System.assert(!o.draftBody.contains('I work with families on planning'),
                'A client already knows what the firm does: ' + d);
        }
    }

    // ---- Contact suppression ----------------------------------------------

    @isTest static void aClientIsNotSuppressedAsADuplicateOfItself() {
        Contact c = new Contact(FirstName='Dashiell', LastName='Ainsleigh',
                                Email='dashiell.ainsleigh@example.com');
        // Exactly the sets the batch builds: every Contact is in them by construction.
        OmnishiftEngine.Outcome o = OmnishiftEngine.suppressionCheck(
            c,
            new Set<String>{'dashiell.ainsleigh@example.com'},
            new Set<String>{'dashiell ainsleigh'});
        System.assert(!o.suppressed,
            'The duplicate rule matches Leads against owned Contacts. Run over Contacts it '
            + 'would suppress the entire client base against itself: ' + o.suppressReason);
    }

    @isTest static void aClientWhoRefusedBothChannelsIsStillSuppressed() {
        Contact c = new Contact(FirstName='Hollis', LastName='Carrowmore',
                                DoNotCall=true, HasOptedOutOfEmail=true);
        OmnishiftEngine.Outcome o = OmnishiftEngine.suppressionCheck(
            c, new Set<String>(), new Set<String>());
        System.assert(o.suppressed, 'Consent applies to a client exactly as it does to a stranger');
        System.assertEquals('Do not call and opted out of email', o.suppressReason);
    }

    @isTest static void aRecentlyContactedClientIsInTheCoolingPeriod() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.isClient = true; p.firstName = 'Isolde'; p.lastName = 'Jessamy';
        p.lastActivityDate = Date.today().addDays(-3);
        OmnishiftEngine.Outcome o = OmnishiftEngine.suppressionCheck(
            p, new Set<String>(), new Set<String>());
        System.assert(o.suppressed, 'Two advisors reaching one household in a fortnight is the bug');
        System.assert(o.suppressReason.contains('cooling period'), o.suppressReason);
    }

    @isTest static void theBatchWritesASuppressedClientBackAsSuppressed() {
        Account a = new Account(Name='Suppressed Co', AnnualRevenue=8000000);
        insert a;
        Contact c = client('Kestrel','Yarrowby','External Referral','CFO', a.Id);
        c.DoNotCall = true;
        c.HasOptedOutOfEmail = true;
        insert c;
        Test.startTest();
        OmnishiftEngineBatch.runNow();
        Test.stopTest();
        Contact after = [SELECT Omnishift_Score__c, Omnishift_Rank__c, Omnishift_Why_Now__c,
                                Omnishift_Draft_Body__c, Omnishift_Scored_On__c
                         FROM Contact WHERE Id = :c.Id];
        System.assertEquals(0, after.Omnishift_Score__c,
            'A suppressed client must be written back at zero, not left at yesterday score');
        System.assertEquals(null, after.Omnishift_Rank__c, 'A suppressed client holds no place in the queue');
        System.assertEquals(null, after.Omnishift_Draft_Body__c,
            'No draft may survive on a record the engine has decided not to contact');
        System.assert(after.Omnishift_Why_Now__c.startsWith('Suppressed:'),
            'The advisor has to be told why it dropped out: ' + after.Omnishift_Why_Now__c);
        System.assertNotEquals(null, after.Omnishift_Scored_On__c,
            'A suppressed record was still looked at, and the run has to say so');
    }

    // ---- cross-object ranking ----------------------------------------------

    @isTest static void theBatchScoresBothObjectsUnderOneRanking() {
        Account a = new Account(Name='Ranking Co', AnnualRevenue=8000000);
        insert a;
        List<Contact> cs = new List<Contact>();
        for (Integer i = 0; i < 6; i++) {
            cs.add(client('Client'+i, 'Household'+i,
                (Math.mod(i,2)==0 ? 'External Referral' : 'Purchased List'),
                (Math.mod(i,3)==0 ? 'CFO' : 'Analyst'), a.Id));
        }
        insert cs;
        List<Lead> ls = new List<Lead>();
        for (Integer i = 0; i < 6; i++) {
            ls.add(new Lead(FirstName='Prospect'+i, LastName='Enquiry'+i, Company='C'+i,
                LeadSource = (Math.mod(i,2)==0 ? 'Partner Referral' : 'Purchased List'),
                AnnualRevenue = 1000000 * (i + 1)));
        }
        insert ls;

        Test.startTest();
        Database.executeBatch(new OmnishiftEngineBatch(), 200);
        Test.stopTest();

        Integer scoredContacts = [SELECT COUNT() FROM Contact WHERE Omnishift_Score__c > 0];
        Integer scoredLeads    = [SELECT COUNT() FROM Lead    WHERE Omnishift_Score__c > 0];
        System.assertEquals(6, scoredContacts, 'Every eligible Contact must be scored, not just the Leads');
        System.assert(scoredLeads > 0, 'The Lead half must keep working');

        List<Decimal> ranks = new List<Decimal>();
        for (Lead l : [SELECT Omnishift_Rank__c FROM Lead WHERE Omnishift_Rank__c != null]) {
            ranks.add(l.Omnishift_Rank__c);
        }
        Integer contactRanks = 0;
        for (Contact c : [SELECT Omnishift_Rank__c FROM Contact WHERE Omnishift_Rank__c != null]) {
            ranks.add(c.Omnishift_Rank__c);
            contactRanks++;
        }
        System.assertEquals(6, contactRanks, 'Contacts must appear in the ranking, not only in the scoring');
        System.assertEquals(scoredContacts + scoredLeads, ranks.size(),
            'Everything scored must be ranked exactly once');
        Set<Decimal> distinct = new Set<Decimal>(ranks);
        System.assertEquals(ranks.size(), distinct.size(),
            'The rank is a single ordering across both objects - no number may be used twice');
        System.assert(distinct.contains(1), 'The ordering has to start at 1');
        System.assertEquals(ranks.size(), (Integer) collapse(distinct),
            'The ordering must be contiguous from 1, with no gaps left by the merge');
    }

    // Highest rank present, used to prove 1..n is contiguous.
    private static Decimal collapse(Set<Decimal> ranks) {
        Decimal top = 0;
        for (Decimal r : ranks) if (r > top) top = r;
        return top;
    }

    @isTest static void oneRankOneAcrossBothObjects() {
        Account a = new Account(Name='Tie Co', AnnualRevenue=8000000);
        insert a;
        insert client('Rosalind','Wexford','External Referral','CFO', a.Id);
        insert new Lead(FirstName='Soren', LastName='Blackwood', Company='Blackwood Holdings',
                        LeadSource='Partner Referral', AnnualRevenue=50000000);
        Test.startTest();
        OmnishiftEngineBatch.runNow();
        Test.stopTest();
        Integer atOne = [SELECT COUNT() FROM Lead WHERE Omnishift_Rank__c = 1]
                      + [SELECT COUNT() FROM Contact WHERE Omnishift_Rank__c = 1];
        System.assertEquals(1, atOne,
            'A Contact and a Lead must not both be rank 1 - that is the whole point of one queue');
    }

    @isTest static void aRunNeverLeavesAVerdictContradictingItself() {
        Lead l = new Lead(FirstName='Wren', LastName='Ashcombe', Company='Ashcombe Partners',
                          LeadSource='Partner Referral', Status='Open - Not Contacted');
        insert l;
        // An advisor edits a violation in, then the nightly run passes over it.
        OmnishiftAction.saveDraft(l.Id, 'A note', 'We deliver guaranteed returns every year.');
        Test.startTest();
        OmnishiftEngineBatch.runNow();
        Test.stopTest();
        Lead after = [SELECT Omnishift_Compliance_Status__c, Omnishift_Compliance_Reason__c,
                             Omnishift_Draft_Body__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Blocked', after.Omnishift_Compliance_Status__c,
            'The edited draft still contains the violation, so it stays blocked.');
        System.assert(after.Omnishift_Compliance_Reason__c.startsWith('Blocked'),
            'The reason must agree with the status, not describe a draft that was '
            + 'thrown away: ' + after.Omnishift_Compliance_Reason__c);
        System.assert(after.Omnishift_Draft_Body__c.contains('guaranteed'),
            'The advisor edit must survive the run.');
    }

    @isTest static void aRecentEventOutranksAPlainReferral() {
        OmnishiftEngine.Prospect ref = new OmnishiftEngine.Prospect();
        ref.firstName='Wren'; ref.lastName='Ashcombe'; ref.intakeChannel='Partner Referral';
        ref.createdDate=Datetime.now(); ref.fitValue=12000000;
        OmnishiftEngine.Outcome refOut = OmnishiftEngine.score(ref);

        OmnishiftEngine.Prospect ev = new OmnishiftEngine.Prospect();
        ev.firstName='Soren'; ev.lastName='Blackwood'; ev.intakeChannel='Other';
        ev.createdDate=Datetime.now(); ev.fitValue=12000000;
        ev.signalType='Business sale'; ev.signalOn=Date.today().addDays(-5);
        ev.signalConfidence=90; ev.signalSource='WealthFeed';
        OmnishiftEngine.Outcome evOut = OmnishiftEngine.score(ev);

        System.assert(evOut.score > refOut.score,
            'Someone who just sold a business is a better call than someone who merely '
            + 'arrived by referral. event=' + evOut.score + ' referral=' + refOut.score);
        System.assertEquals('Event', evOut.topDriver);
        System.assert(evOut.whyNow.contains('WealthFeed'),
            'The advisor has to know which feed made the claim: ' + evOut.whyNow);
        System.assert(evOut.whyNow.contains('5 days ago'), evOut.whyNow);
    }

    @isTest static void aStaleOrWeakSignalDoesNotTakeOver() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.firstName='Thea'; p.lastName='Marlowe'; p.intakeChannel='Partner Referral';
        p.createdDate=Datetime.now(); p.fitValue=12000000;
        p.signalType='Business sale'; p.signalOn=Date.today().addDays(-400);
        p.signalConfidence=95; p.signalSource='WealthFeed';
        OmnishiftEngine.Outcome o = OmnishiftEngine.score(p);
        System.assertNotEquals('Event', o.topDriver,
            'An event from over a year ago is history, not a reason to call today.');
    }

    @isTest static void theEventDraftDoesNotAssertWhatHappened() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.firstName='Ida'; p.lastName='Vexley';
        OmnishiftEngine.Outcome d = OmnishiftEngine.draft(p, 'Event');
        System.assert(!d.draftBody.toLowerCase().contains('congratulations'),
            'A feed is not certainty. Congratulating someone on a sale that did not '
            + 'happen is unrecoverable: ' + d.draftBody);
        System.assert(d.draftBody.contains('Ida'), d.draftBody);
    }

    @isTest static void anActivelyWorkedProspectIsNotSuppressedForBeingContacted() {
        // The advisors work a live prospect on a two-week rhythm. A flat
        // fourteen-day cooling period hid exactly the people they were working.
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.firstName='Tom'; p.lastName='Marlowe';
        p.lastActivityDate = Date.today().addDays(-6);
        p.hasOpenFollowUp = false;
        OmnishiftEngine.Outcome o =
            OmnishiftEngine.suppressionCheck(p, new Set<String>(), new Set<String>());
        System.assert(!o.suppressed,
            'Contacted six days ago with nothing scheduled is where things fall '
            + 'through - that is the agent job, not a suppression: ' + o.suppressReason);
    }

    @isTest static void aRecordWithAPlanIsLeftAlone() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.firstName='Tom'; p.lastName='Marlowe';
        p.lastActivityDate = Date.today().addDays(-6);
        p.hasOpenFollowUp = true;
        OmnishiftEngine.Outcome o =
            OmnishiftEngine.suppressionCheck(p, new Set<String>(), new Set<String>());
        System.assert(o.suppressed, 'Someone already has a next step booked.');
        System.assert(o.suppressReason.contains('Already being worked'), o.suppressReason);
    }

    @isTest static void contactedThisMorningIsStillHeldBack() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.firstName='Tom'; p.lastName='Marlowe';
        p.lastActivityDate = Date.today();
        OmnishiftEngine.Outcome o =
            OmnishiftEngine.suppressionCheck(p, new Set<String>(), new Set<String>());
        System.assert(o.suppressed, 'Nobody should be contacted twice in a morning.');
    }

    @isTest static void aSuppressedRecordIsQuarantinedRatherThanSilentlyDropped() {
        Lead l = new Lead(FirstName='Ada', LastName='Byron', Company='Engines',
                          Status='Closed - Not Converted', LeadSource='Web');
        insert l;
        Test.startTest();
        OmnishiftEngineBatch.runNow();
        Test.stopTest();
        Lead after = [SELECT Omnishift_Quarantined__c, Omnishift_Quarantine_Reason__c
                      FROM Lead WHERE Id = :l.Id];
        System.assertEquals(true, after.Omnishift_Quarantined__c,
            'A suppression nobody can filter for is indistinguishable from a record '
            + 'the agent never saw.');
        System.assertNotEquals(null, after.Omnishift_Quarantine_Reason__c);
    }

    @isTest static void theDriverIsStoredSoOutcomesCanBeGroupedByIt() {
        Lead l = new Lead(FirstName='Soren', LastName='Blackwood', Company='Blackwood',
                          LeadSource='Partner Referral', Status='Open - Not Contacted');
        insert l;
        Test.startTest();
        OmnishiftEngineBatch.runNow();
        Test.stopTest();
        Lead after = [SELECT Omnishift_Driver__c FROM Lead WHERE Id = :l.Id];
        System.assertNotEquals(null, after.Omnishift_Driver__c,
            'A 200-character sentence cannot be grouped in a report; the driver can.');
    }

    @isTest static void staleEngagementDoesNotDriveButAFreshOneDoes() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.firstName='Thea'; p.lastName='Marlowe'; p.intakeChannel='Other';
        p.createdDate=Datetime.now().addDays(-40); p.fitValue=3000000;
        p.signalType='Email engagement'; p.signalConfidence=90; p.signalSource='Account Engagement';
        p.signalOn=Date.today().addDays(-59);
        System.assertNotEquals('Event', OmnishiftEngine.score(p).topDriver,
            'Email opened two months ago is not a reason to call today.');
        p.signalOn=Date.today().addDays(-6);
        System.assertEquals('Event', OmnishiftEngine.score(p).topDriver,
            'Email opened last week is.');
        System.assertEquals(21, OmnishiftEngine.windowFor('Website research'));
        System.assertEquals(120, OmnishiftEngine.windowFor('Business sale'));
    }

    @isTest static void aParkedCadenceYieldsToAFreshFiling() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.firstName='Tom'; p.lastName='Marlowe'; p.hasOpenFollowUp = true;
        p.lastActivityDate = Date.today().addDays(-20);
        OmnishiftEngine.Outcome held = OmnishiftEngine.suppressionCheck(p, new Set<String>(), new Set<String>());
        System.assert(held.suppressed, 'Nothing new: the parked follow-up stands.');
        p.signalType='Business sale'; p.signalOn=Date.today().addDays(-4); p.signalConfidence=88; p.signalSource='WealthFeed';
        OmnishiftEngine.Outcome early = OmnishiftEngine.suppressionCheck(p, new Set<String>(), new Set<String>());
        System.assert(!early.suppressed, 'A business sale this week is exactly the reason to bring it forward.');
        p.signalType='Email engagement';
        System.assert(OmnishiftEngine.suppressionCheck(p, new Set<String>(), new Set<String>()).suppressed,
            'Opening an email is not enough to override a plan.');
    }

    @isTest static void aWrongPersonStaysHeldUntilTheAdvisorSaysOtherwise() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.lastName = 'Pemberton'; p.disposition = 'Wrong person';
        OmnishiftEngine.Outcome o = OmnishiftEngine.suppressionCheck(p, new Set<String>(), new Set<String>());
        System.assert(o.suppressed, 'the advisor said no; the model does not get a vote');
        System.assert(o.suppressReason.contains('wrong person'), o.suppressReason);
    }

    @isTest static void aBookedMeetingTakesTheRecordOffTheList() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.lastName = 'Marlowe'; p.outcome = 'Meeting booked';
        OmnishiftEngine.Outcome o = OmnishiftEngine.suppressionCheck(p, new Set<String>(), new Set<String>());
        System.assert(o.suppressed);
        System.assert(o.suppressReason.startsWith('Meeting booked'), o.suppressReason);
    }

    @isTest static void theWhyNowSaysWhatTheFeedActuallySaw() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.firstName = 'Wren'; p.lastName = 'Ashcombe'; p.intakeChannel = 'Web';
        p.createdDate = Datetime.now().addDays(-40); p.lastActivityDate = Date.today().addDays(-10);
        p.fitValue = 12000000;
        Omnishift_Signal__c s = new Omnishift_Signal__c(Signal_Type__c = 'Business sale', Source__c = 'WealthFeed',
            Occurred_On__c = Date.today(), Confidence__c = 95,
            Evidence__c = 'Form D filed, total offering $18.4m. Filer address matches the household. [Generated demonstration record.]');
        OmnishiftEngine.attachSignal(p, s);
        OmnishiftEngine.Outcome o = OmnishiftEngine.score(p);
        System.assertEquals('Event', o.topDriver);
        System.assert(o.whyNow.contains('Form D filed, total offering $18.4m.'), o.whyNow);
        System.assert(!o.whyNow.contains('Generated'), 'the data notice is not part of the reason');
    }

    @isTest static void theDraftPicksUpWhatTheProspectSaidInTheirEnquiry() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.firstName = 'Pamela'; p.lastName = 'Whitaker'; p.intakeChannel = 'Web';
        p.createdDate = Datetime.now().addDays(-3); p.fitValue = 3200000;
        OmnishiftEngine.attachSignal(p, new Omnishift_Signal__c(Signal_Type__c = 'Marketplace enquiry', Source__c = 'SmartAsset AMP',
            Occurred_On__c = Date.today().addDays(-1), Confidence__c = 90,
            Evidence__c = 'Matched enquiry 9/1/2026, self-reported investable assets $5m+, stated goal "college funding for two", timeframe "within 3 months"; marketplace lead, not exclusive.'));
        OmnishiftEngine.Outcome d = OmnishiftEngine.draft(p, OmnishiftEngine.score(p).topDriver);
        System.assert(d.draftBody.contains('You mentioned "college funding for two" in your enquiry'), d.draftBody);
        System.assertEquals('Passed', OmnishiftEngine.complianceCheck(d.draftSubject, d.draftBody).complianceStatus);
    }

    @isTest static void aProspectsOwnGuaranteeIsCaughtBeforeTheFirmRepeatsIt() {
        OmnishiftEngine.Prospect p = new OmnishiftEngine.Prospect();
        p.firstName = 'Theo'; p.lastName = 'Nakamura'; p.intakeChannel = 'Web';
        p.createdDate = Datetime.now().addDays(-3); p.fitValue = 3200000;
        OmnishiftEngine.attachSignal(p, new Omnishift_Signal__c(Signal_Type__c = 'Marketplace enquiry', Source__c = 'SmartAsset AMP',
            Occurred_On__c = Date.today().addDays(-1), Confidence__c = 90,
            Evidence__c = 'Matched enquiry 9/1/2026, self-reported investable assets $5m+, stated goal "guaranteed income in retirement", timeframe "within 3 months"; marketplace lead, not exclusive.'));
        OmnishiftEngine.Outcome d = OmnishiftEngine.draft(p, OmnishiftEngine.score(p).topDriver);
        OmnishiftEngine.Outcome c = OmnishiftEngine.complianceCheck(d.draftSubject, d.draftBody);
        System.assertEquals('Blocked', c.complianceStatus, 'the prospect said it; the firm still may not repeat it');
        System.assert(c.complianceReason.contains('guarantee'), c.complianceReason);
    }

    @isTest static void aRecentFilingOutranksANewerWebsiteVisit() {
        Omnishift_Signal__c visit = new Omnishift_Signal__c(Signal_Type__c='Website research', Occurred_On__c=Date.today().addDays(-3), Confidence__c=84);
        Omnishift_Signal__c filing = new Omnishift_Signal__c(Signal_Type__c='Inheritance filing', Occurred_On__c=Date.today().addDays(-5), Confidence__c=90);
        Omnishift_Signal__c picked = OmnishiftEngine.pickSignal(new List<Omnishift_Signal__c>{ visit, filing });
        System.assertEquals('Inheritance filing', picked.Signal_Type__c, 'the filing is the reason to call; the visit is the reminder');
    }

    @isTest static void withNoRecentEventTheNewestSignalWins() {
        Omnishift_Signal__c visit = new Omnishift_Signal__c(Signal_Type__c='Website research', Occurred_On__c=Date.today().addDays(-3), Confidence__c=84);
        Omnishift_Signal__c oldSale = new Omnishift_Signal__c(Signal_Type__c='Business sale', Occurred_On__c=Date.today().addDays(-70), Confidence__c=95);
        System.assertEquals('Website research', OmnishiftEngine.pickSignal(new List<Omnishift_Signal__c>{ visit, oldSale }).Signal_Type__c);
        System.assertEquals(null, OmnishiftEngine.pickSignal(new List<Omnishift_Signal__c>()));
    }

    @isTest static void theLearningLoopReadsBookingRatesPerDriver() {
        List<Lead> ls = new List<Lead>();
        for (Integer i = 0; i < 6; i++) ls.add(new Lead(FirstName='L'+i, LastName='Learn', Company='Learn Co', Email='learn'+i+'@example.com',
            Omnishift_Driver__c = 'Event', Omnishift_Outcome__c = (i < 3) ? 'Meeting booked' : 'No response'));
        ls.add(new Lead(FirstName='R', LastName='Ref', Company='Ref Co', Email='ref@example.com', Omnishift_Driver__c='Referral', Omnishift_Outcome__c='Not interested'));
        insert ls;
        Map<String, OmnishiftLearning.DriverStat> stats = OmnishiftLearning.driverStats();
        System.assertEquals(6, stats.get('Event').surfaced);
        System.assertEquals(3, stats.get('Event').booked);
        System.assert(stats.get('Event').multiplier > 1, 'a driver that books above the prior is trusted more: ' + stats.get('Event').multiplier);
        System.assert(stats.get('Referral').multiplier < 1, 'one miss and no bookings shrinks toward the prior, below it');
        System.assert(stats.get('Event').multiplier <= 1.15 && stats.get('Referral').multiplier >= 0.85, 'bounded');
        System.assertEquals(false, stats.get('Event').enoughEvidence, 'six records is not evidence');
        List<OmnishiftLearning.DriverStat> sorted = OmnishiftLearning.getDriverStats();
        System.assertEquals('Event', sorted[0].driver, 'most evidence first');
        System.assertEquals(stats.get('Event').multiplier, OmnishiftLearning.multipliers().get('Event'));
    }

    @isTest static void escalationMarksTheRecordOnceAndFormatsTheMoney() {
        Lead big = new Lead(FirstName='Vesper', LastName='Ironwood', Company='Ironwood Capital', Email='vesper@example.com', AnnualRevenue=12000000);
        insert big;
        System.assert(OmnishiftEscalation.qualifies(12000000));
        System.assert(!OmnishiftEscalation.qualifies(9999999));
        System.assert(!OmnishiftEscalation.qualifies(null));
        Integer sent = OmnishiftEscalation.escalate(new List<OmnishiftEscalation.Candidate>{
            new OmnishiftEscalation.Candidate(big.Id, 'Vesper Ironwood', 12000000, 'Business sale picked up today by WealthFeed. ' + 'x'.repeat(200))
        });
        System.assertEquals(0, sent, 'tests never ring the bell');
        Lead after = [SELECT Omnishift_Escalated__c, Omnishift_Escalated_On__c FROM Lead WHERE Id = :big.Id];
        System.assertEquals(true, after.Omnishift_Escalated__c);
        System.assertNotEquals(null, after.Omnishift_Escalated_On__c);
        System.assertEquals(0, OmnishiftEscalation.escalate(null));
        System.assertEquals(0, OmnishiftEscalation.escalate(new List<OmnishiftEscalation.Candidate>()));
    }
}
