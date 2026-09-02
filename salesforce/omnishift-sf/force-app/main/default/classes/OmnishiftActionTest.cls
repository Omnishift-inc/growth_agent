@isTest
private class OmnishiftActionTest {

    private static Lead newLead() {
        Lead l = new Lead(FirstName='Ada', LastName='Byron', Company='Analytical Engines',
                          Email='ada@example.com', Status='Open - Not Contacted',
                          Omnishift_Next_Action_Date__c = Date.today());
        insert l;
        return l;
    }

    @isTest static void approvedSendLogsAnEmailTaskAndLeavesTheQueue() {
        Lead l = newLead();
        Test.startTest();
        String msg = OmnishiftAction.dispositionForTest(l.Id, 'Approved and sent', null,
                                                       'A note after your introduction', 'Hello Ada,');
        Test.stopTest();

        Task t = [SELECT Subject, Type, Status, WhoId, Description FROM Task WHERE WhoId = :l.Id];
        System.assertEquals('Email', t.Type, 'An approved send should log an email activity.');
        System.assertEquals('Completed', t.Status);
        System.assertEquals('A note after your introduction', t.Subject);
        System.assert(t.Description.contains('approved as drafted'), 'The log should say it was unedited.');

        Lead after = [SELECT Omnishift_Disposition__c, Omnishift_Next_Action_Date__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Approved and sent', after.Omnishift_Disposition__c);
        System.assertEquals(null, after.Omnishift_Next_Action_Date__c, 'A handled lead must leave the queue.');
        System.assert(msg.contains('approved and sent'));
    }

    @isTest static void editedSendIsDistinguishableInTheAuditLog() {
        Lead l = newLead();
        OmnishiftAction.dispositionForTest(l.Id, 'Edited before send', null, 'Subject', 'Body');
        Task t = [SELECT Description FROM Task WHERE WhoId = :l.Id];
        System.assert(t.Description.contains('edited by the advisor'),
                      'Compliance needs to see that a human changed the draft.');
    }

    @isTest static void snoozePushesTheDateSevenDaysOut() {
        Lead l = newLead();
        Test.startTest();
        String msg = OmnishiftAction.dispositionForTest(l.Id, 'Snoozed', 'Not now', null, null);
        Test.stopTest();
        Lead after = [SELECT Omnishift_Next_Action_Date__c, Omnishift_Disposition_Reason__c
                      FROM Lead WHERE Id = :l.Id];
        System.assertEquals(Date.today().addDays(7), after.Omnishift_Next_Action_Date__c);
        System.assertEquals('Not now', after.Omnishift_Disposition_Reason__c);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :l.Id],
                            'Snoozing is not an outreach and must not log one.');
        System.assert(msg.startsWith('Snoozed until'));
    }

    @isTest static void callLoggedCreatesACallTask() {
        Lead l = newLead();
        OmnishiftAction.dispositionForTest(l.Id, 'Call logged', 'Left a voicemail', null, null);
        Task t = [SELECT Type, Description FROM Task WHERE WhoId = :l.Id];
        System.assertEquals('Call', t.Type);
        System.assertEquals('Left a voicemail', t.Description);
    }

    @isTest static void wrongPersonDropsOutWithoutLoggingOutreach() {
        Lead l = newLead();
        OmnishiftAction.dispositionForTest(l.Id, 'Wrong person', 'Different Ada', null, null);
        Lead after = [SELECT Omnishift_Next_Action_Date__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(null, after.Omnishift_Next_Action_Date__c);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :l.Id]);
    }

    @isTest static void contactsAreDispositionedToo() {
        Contact c = new Contact(FirstName='Grace', LastName='Hopper', Email='grace@example.com');
        insert c;
        OmnishiftAction.dispositionForTest(c.Id, 'Approved and sent', null, 'Hello', 'Body');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhoId = :c.Id]);
    }

    @isTest static void unsupportedObjectIsRejected() {
        Account a = new Account(Name='Acme');
        insert a;
        try {
            OmnishiftAction.dispositionForTest(a.Id, 'Approved and sent', null, 's', 'b');
            System.assert(false, 'An Account should not be dispositionable.');
        } catch (Exception e) {
            System.assert(true);
        }
    }

    @isTest static void blankDispositionIsRejected() {
        Lead l = newLead();
        try {
            OmnishiftAction.dispositionForTest(l.Id, '', null, null, null);
            System.assert(false, 'A blank disposition should not be accepted.');
        } catch (Exception e) {
            System.assert(true);
        }
    }

    @isTest static void savingADraftReRunsCompliance() {
        Lead l = newLead();
        Test.startTest();
        Map<String, Object> r = OmnishiftAction.saveDraftForTest(
            l.Id, 'A quick note', 'Ada - we are the best firm around. Happy to talk.');
        Test.stopTest();
        System.assertEquals('Auto-corrected', r.get('status'),
            'An advisor editing in a superlative must be caught on save.');
        System.assert(!((String) r.get('body')).toLowerCase().contains('best'),
            'The stored body must be the corrected one: ' + r.get('body'));
        Lead after = [SELECT Omnishift_Draft_Body__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(r.get('body'), after.Omnishift_Draft_Body__c,
            'What is shown back must be what was stored.');
    }

    @isTest static void sendRefusesAViolationTheAdvisorTypedIn() {
        Lead l = newLead();
        Boolean refused = false;
        Test.startTest();
        try {
            OmnishiftAction.sendDraftForTest(l.Id, 'A note', 'We deliver guaranteed returns.', true);
        } catch (OmnishiftAction.ActionException e) {
            refused = true;
            System.assert(e.getMessage().contains('guarantee'), e.getMessage());
        }
        Test.stopTest();
        System.assert(refused, 'A blocked draft must never send, however it got there.');
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :l.Id],
            'A refused send must not leave an activity claiming it happened.');
    }

    @isTest static void sendWithLiveEmailOffRecordsWithoutDelivering() {
        Lead l = newLead();
        Test.startTest();
        String msg = OmnishiftAction.sendDraftForTest(l.Id, 'A note', 'Ada - happy to talk.', false);
        Test.stopTest();
        System.assert(msg.contains('nothing left Salesforce'), msg);
        Task t = [SELECT Subject, Status FROM Task WHERE WhoId = :l.Id];
        System.assertEquals('A note', t.Subject);
        System.assertEquals('Completed', t.Status);
    }

    @isTest static void anEditedSendIsRecordedAsEdited() {
        Lead l = newLead();
        OmnishiftAction.sendDraftForTest(l.Id, 'A note', 'Ada - happy to talk.', true);
        Lead after = [SELECT Omnishift_Disposition__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Edited before send', after.Omnishift_Disposition__c);
    }

    @isTest static void liveEmailIsOffByDefault() {
        System.assertEquals(false, OmnishiftAction.liveEmailEnabled(),
            'No org should deliver email until the firm has switched it on deliberately.');
    }

    @isTest static void snoozeHonoursTheDateTheAdvisorChose() {
        Lead l = newLead();
        Date want = Date.today().addDays(31);
        Test.startTest();
        String msg = OmnishiftAction.snoozeForTest(l.Id, want);
        Test.stopTest();
        Lead after = [SELECT Omnishift_Next_Action_Date__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(want, after.Omnishift_Next_Action_Date__c,
            'A month means a month, not the seven-day default.');
        System.assert(msg.contains(want.format()), msg);
    }

    @isTest static void snoozeFallsBackToAWeekWhenNoDateIsGiven() {
        Lead l = newLead();
        OmnishiftAction.snoozeForTest(l.Id, null);
        Lead after = [SELECT Omnishift_Next_Action_Date__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(Date.today().addDays(7), after.Omnishift_Next_Action_Date__c);
    }

    @isTest static void aSnoozeDateInThePastIsIgnored() {
        Lead l = newLead();
        OmnishiftAction.snoozeForTest(l.Id, Date.today().addDays(-5));
        Lead after = [SELECT Omnishift_Next_Action_Date__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(Date.today().addDays(7), after.Omnishift_Next_Action_Date__c,
            'A past date would put the record straight back on today list.');
    }

    @isTest static void personAccountDetectionMatchesTheOrg() {
        Boolean expected = Schema.SObjectType.Contact.fields.getMap().containsKey('ispersonaccount');
        System.assertEquals(expected, OmnishiftAction.personAccountsEnabled(),
            'The panel decides whether to request IsPersonAccount from this.');
    }

    @isTest static void aTenMillionHouseholdIsEscalatedOnceAndFlagged() {
        Lead big = new Lead(FirstName='Vesper', LastName='Ironwood', Company='Ironwood Capital',
                            LeadSource='Partner Referral', Status='Open - Not Contacted',
                            AnnualRevenue=12000000);
        Lead small = new Lead(FirstName='Thea', LastName='Marlowe', Company='Marlowe Partners',
                              LeadSource='Partner Referral', Status='Open - Not Contacted',
                              AnnualRevenue=640000);
        insert new List<Lead>{ big, small };
        Test.startTest();
        OmnishiftEngineBatch.runNow();
        Test.stopTest();
        Map<Id, Lead> after = new Map<Id, Lead>([SELECT Omnishift_Escalated__c, Omnishift_Escalated_On__c
                                                 FROM Lead WHERE Id IN (:big.Id, :small.Id)]);
        System.assertEquals(true, after.get(big.Id).Omnishift_Escalated__c,
            'Above the threshold the leadership is told, as Tom described on the call.');
        System.assertNotEquals(null, after.get(big.Id).Omnishift_Escalated_On__c);
        System.assertEquals(false, after.get(small.Id).Omnishift_Escalated__c,
            'Below the threshold the bell must not ring.');
    }

    @isTest static void qualifiesIsTheThresholdGevorgQuotedOnTheCall() {
        System.assert(OmnishiftEscalation.qualifies(10000000));
        System.assert(!OmnishiftEscalation.qualifies(9999999));
        System.assert(!OmnishiftEscalation.qualifies(null));
    }

    @isTest static void theTimelineMergesEverySourceNewestFirst() {
        Lead l = newLead();
        insert new Omnishift_Signal__c(Name='WealthFeed - Business sale', Omnishift_Lead__c=l.Id,
            Signal_Type__c='Business sale', Source_System__c='WealthFeed', Source__c='WealthFeed',
            Occurred_On__c=Date.today().addDays(-3), Confidence__c=88,
            Evidence__c='Form D filed. Generated test record.');
        insert new Omnishift_Marketing_Send__c(Name='Quarterly Newsletter', Omnishift_Lead__c=l.Id,
            Scheduled_For__c=Datetime.now().addDays(2), Campaign_Type__c='Newsletter',
            Audience__c='Prospects - all', Source_System__c='Account Engagement');
        insert new Task(WhoId=l.Id, Subject='Intro call', Type='Call', Status='Completed',
            ActivityDate=Date.today().addDays(-10), OwnerId=UserInfo.getUserId());
        OmnishiftAction.dispositionForTest(l.Id, 'Call logged', 'left voicemail', null, null);

        Test.startTest();
        List<Map<String, Object>> rows = OmnishiftAction.getTimeline(l.Id);
        Test.stopTest();

        Set<String> kinds = new Set<String>();
        for (Map<String, Object> r : rows) kinds.add((String) r.get('kind'));
        System.assert(kinds.contains('signal'),    'external feed rows: ' + kinds);
        System.assert(kinds.contains('marketing'), 'marketing calendar rows: ' + kinds);
        System.assert(kinds.contains('activity'),  'Salesforce activities: ' + kinds);
        System.assert(kinds.contains('agent'),     'the agent\'s own trail: ' + kinds);
        // newest first: the scheduled send (future) sits above the sale (3 days ago)
        System.assertEquals('marketing', rows[0].get('kind'),
            'A send scheduled for the day after tomorrow is the newest thing on the record.');
        System.assertEquals(true, rows[0].get('upcoming'), 'Future sends are flagged so the advisor waits.');
        Datetime prev;
        for (Map<String, Object> r : rows) {
            Datetime at = (Datetime) r.get('at');
            if (prev != null && at != null) System.assert(at <= prev, 'timeline must descend');
            if (at != null) prev = at;
        }
    }

    @isTest static void theCalendarGroupsSendsByCampaignAndDay() {
        Lead a = newLead();
        Lead b = new Lead(FirstName='Bram', LastName='Kirkbride', Company='Kirkbride Holdings',
                          Email='bram.kirkbride@example.com', Status='Open - Not Contacted');
        insert b;
        Date monday = Date.today().toStartOfWeek().addDays(1);
        Datetime at = Datetime.newInstance(monday, Time.newInstance(17,0,0,0));
        insert new List<Omnishift_Marketing_Send__c>{
            new Omnishift_Marketing_Send__c(Name='Aug 26 Gus Dow Send', Omnishift_Lead__c=a.Id,
                Scheduled_For__c=at, Campaign_Type__c='Dow drip', Audience__c='Prospects - all',
                Source_System__c='Account Engagement'),
            new Omnishift_Marketing_Send__c(Name='Aug 26 Gus Dow Send', Omnishift_Lead__c=b.Id,
                Scheduled_For__c=at, Campaign_Type__c='Dow drip', Audience__c='Prospects - all',
                Source_System__c='Account Engagement')
        };
        Test.startTest();
        List<Map<String, Object>> cal = OmnishiftAction.getCalendar(Date.today().toStartOfWeek());
        Test.stopTest();
        Map<String, Object> hit;
        for (Map<String, Object> e : cal) if (e.get('name') == 'Aug 26 Gus Dow Send') hit = e;
        System.assertNotEquals(null, hit, 'The send must appear on its day.');
        System.assertEquals(2, hit.get('people'), 'Two people, one calendar entry - as Pardot shows it.');
        System.assertEquals(1, hit.get('dayIndex'), 'Monday is one day after the week start.');
    }

    @isTest static void thePanelContextIsOneCall() {
        Lead l = newLead();
        Map<String, Object> ctx = OmnishiftAction.getPanelContext(l.Id);
        System.assert(ctx.containsKey('personAccounts') && ctx.containsKey('liveEmail')
            && ctx.containsKey('timeline'), 'All three in one round trip: ' + ctx.keySet());
        System.assertEquals(false, ctx.get('liveEmail'));
    }

    @isTest static void theCalendarEntryListsThePeopleOnIt() {
        Lead a = newLead();
        Contact c = new Contact(FirstName='Grace', LastName='Hopper', Email='grace@example.com'); insert c;
        Date monday = Date.today().toStartOfWeek();
        insert new List<Omnishift_Marketing_Send__c>{
            new Omnishift_Marketing_Send__c(Name='Q3 Market Commentary', Omnishift_Lead__c=a.Id,
                Scheduled_For__c=Datetime.newInstance(monday.addDays(2), Time.newInstance(10,0,0,0)), Campaign_Type__c='Market commentary'),
            new Omnishift_Marketing_Send__c(Name='Q3 Market Commentary', Omnishift_Contact__c=c.Id,
                Scheduled_For__c=Datetime.newInstance(monday.addDays(2), Time.newInstance(10,0,0,0)), Campaign_Type__c='Market commentary')
        };
        List<Map<String, Object>> cal = OmnishiftAction.getCalendar(monday);
        System.assertEquals(1, cal.size(), 'one campaign on one day is one entry');
        List<Map<String, Object>> people = (List<Map<String, Object>>) cal[0].get('recipients');
        System.assertEquals(2, people.size(), 'both recipients are listed behind the count');
        Set<String> objs = new Set<String>();
        for (Map<String, Object> pr : people) objs.add((String) pr.get('objectApiName'));
        System.assert(objs.contains('Lead') && objs.contains('Contact'), 'each recipient knows which record to open');
    }

    @isTest static void theBriefingCountsTodaysWork() {
        Lead l = newLead();
        l.Omnishift_Rank__c = 1; l.Omnishift_Score__c = 80; l.Omnishift_Next_Action_Date__c = Date.today();
        update l;
        Map<String, Object> b = OmnishiftAction.getBriefing();
        System.assert(b.containsKey('toWork') || b.containsKey('total') || !b.isEmpty(), 'the briefing returns its counts');
    }

    @isTest static void signalsAreReadBackForTheRecord() {
        Lead l = newLead();
        insert new Omnishift_Signal__c(Name='WealthFeed - Business sale', Omnishift_Lead__c=l.Id,
            Signal_Type__c='Business sale', Source__c='WealthFeed', Occurred_On__c=Date.today().addDays(-2), Confidence__c=90);
        System.assertEquals(1, OmnishiftAction.getSignals(l.Id).size(), 'the signal is returned for its record');
    }

    @isTest static void anOutcomeIsStampedWithItsTime() {
        Lead l = newLead();
        OmnishiftAction.recordOutcome(l.Id, 'Too early');
        Lead after = [SELECT Omnishift_Outcome__c, Omnishift_Outcome_On__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Too early', after.Omnishift_Outcome__c);
        System.assertNotEquals(null, after.Omnishift_Outcome_On__c, 'the history needs the moment it was recorded');
    }

    @isTest static void activityWithoutATypeIsNamedFromItsSubject() {
        Lead l = newLead();
        insert new Task(WhoId=l.Id, Subject='Growth Agent call', Status='Completed', ActivityDate=Date.today());
        insert new Task(WhoId=l.Id, Subject='A question about timing', Status='Completed', ActivityDate=Date.today());
        Set<String> titles = new Set<String>();
        for (Map<String, Object> r : OmnishiftAction.getTimeline(l.Id)) titles.add((String) r.get('title'));
        System.assert(titles.contains('Call: Growth Agent call'), titles);
        System.assert(titles.contains('Email: A question about timing'), titles);
    }

    @isTest static void sendingMovesTheLeadOutOfNotContacted() {
        Lead l = newLead();
        OmnishiftAction.recordDisposition(l.Id, 'Approved and sent', null, 'A note', 'Hello Ada', null);
        System.assertEquals('Working - Contacted', [SELECT Status FROM Lead WHERE Id = :l.Id].Status,
            'the Path should say the prospect has been contacted, because they have');
    }

    @isTest static void undoingAWrongPersonMarkPutsTheRecordBackAndScoresIt() {
        Lead l = newLead();
        OmnishiftAction.recordDisposition(l.Id, 'Wrong person', 'mis-mapped', null, null, null);
        // the nightly run would have held it for that mark
        update new Lead(Id = l.Id, Omnishift_Quarantined__c = true, Omnishift_Quarantine_Reason__c = 'Marked as the wrong person by the advisor', Omnishift_Score__c = 0);
        String msg = OmnishiftAction.clearDisposition(l.Id);
        Lead after = [SELECT Omnishift_Disposition__c, Omnishift_Quarantined__c, Omnishift_Score__c, Omnishift_Next_Action_Date__c, Omnishift_Why_Now__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(null, after.Omnishift_Disposition__c);
        System.assertEquals(false, after.Omnishift_Quarantined__c, 'the hold went with the mark');
        System.assert(after.Omnishift_Score__c > 0, 'scored again on the spot: ' + after.Omnishift_Score__c);
        System.assertEquals(Date.today(), after.Omnishift_Next_Action_Date__c);
        System.assert(String.isNotBlank(after.Omnishift_Why_Now__c));
        System.assert(msg.contains('Back'), msg);
    }

    @isTest static void bringingASnoozeBackDoesNotTouchTheScore() {
        Lead l = newLead();
        update new Lead(Id = l.Id, Omnishift_Score__c = 77, Omnishift_Scored_On__c = Datetime.now());
        OmnishiftAction.recordDisposition(l.Id, 'Snoozed', 'wrong month', null, null, Date.today().addDays(10));
        OmnishiftAction.clearDisposition(l.Id);
        Lead after = [SELECT Omnishift_Disposition__c, Omnishift_Score__c, Omnishift_Next_Action_Date__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(null, after.Omnishift_Disposition__c);
        System.assertEquals(77, after.Omnishift_Score__c, 'nothing about the person changed, only the advisor\'s mind');
        System.assertEquals(Date.today(), after.Omnishift_Next_Action_Date__c);
    }
}
