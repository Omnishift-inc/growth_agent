// Diane Okafor is the person the Universal Integrator demo researches. What
// Salesforce holds about her must be what the integrator's sandboxes return:
// WealthFeed catalyst 29 Aug, est. $5.2M inheritance; one VisitIQ visit on
// 30 Aug (organic, "/" and "/our-team", 3 minutes); directory headline
// "Senior Counsel at Truist" with the probate note; net worth $5.2m; Charlotte, NC.
String NOTE = ' [Generated demonstration record - no real person or event.]';
Lead d = [SELECT Id FROM Lead WHERE Name = 'Diane Okafor' LIMIT 1];
d.Title = 'Senior Counsel'; d.Company = 'Truist'; d.City = 'Charlotte'; d.CountryCode = 'US'; d.StateCode = 'NC'; d.AnnualRevenue = 5200000;
d.Description = 'Corporate law, Charlotte NC. Recent probate filing links her to the Okafor family trust (public record). Researched by the Universal Integrator across WealthFeed, VisitIQ and the public directory.' + NOTE;
d.Omnishift_Escalated__c = false; d.Omnishift_Escalated_On__c = null;   // $5.2m is under the $10m escalation threshold
update d;
delete [SELECT Id FROM Omnishift_Signal__c WHERE Omnishift_Lead__c = :d.Id];
insert new List<Omnishift_Signal__c>{
    new Omnishift_Signal__c(Name = 'WealthFeed - Inheritance filing', Omnishift_Lead__c = d.Id, Signal_Type__c = 'Inheritance filing', Source__c = 'WealthFeed', Source_System__c = 'WealthFeed',
        Occurred_On__c = Date.newInstance(2026, 8, 29), Observed_On__c = Datetime.newInstance(2026, 8, 29, 14, 10, 0), Confidence__c = 90, External_Id__c = 'WEA-DIANE',
        Evidence__c = 'Sudden-wealth event, est. $5.2M inheritance. Probate filing 8/29/2026 links the household to the Okafor family trust; court record, matched on surname, county and decedent address.' + NOTE,
        Detail__c = 'Sudden-wealth event, est. $5.2M inheritance. Probate filing 8/29/2026 links the household to the Okafor family trust.' + NOTE),
    new Omnishift_Signal__c(Name = 'VisitIQ - Website research', Omnishift_Lead__c = d.Id, Signal_Type__c = 'Website research', Source__c = 'VisitIQ', Source_System__c = 'VisitIQ',
        Occurred_On__c = Date.newInstance(2026, 8, 30), Observed_On__c = Datetime.newInstance(2026, 8, 30, 20, 5, 0), Confidence__c = 84, External_Id__c = 'VIS-DIANE',
        Evidence__c = 'One organic visit on 8/30/2026: "/" then "/our-team", 3 minutes on site; de-anonymised by IP-to-company match to Truist.' + NOTE,
        Detail__c = 'One organic visit on 8/30/2026: "/" then "/our-team", 3 minutes on site; de-anonymised by IP-to-company match to Truist.' + NOTE),
    new Omnishift_Signal__c(Name = 'Public web - Role change', Omnishift_Lead__c = d.Id, Signal_Type__c = 'Role change', Source__c = 'Public web', Source_System__c = 'Public web',
        Occurred_On__c = Date.newInstance(2026, 7, 24), Observed_On__c = Datetime.newInstance(2026, 7, 24, 9, 0, 0), Confidence__c = 70, External_Id__c = 'PUB-DIANE',
        Evidence__c = 'Directory profile: "Senior Counsel at Truist". Corporate law, Charlotte NC. Recent probate filing links her to the Okafor family trust (public record).' + NOTE,
        Detail__c = 'Directory profile: "Senior Counsel at Truist". Corporate law, Charlotte NC.' + NOTE)
};
System.debug('DIANE aligned'); System.debug(OmnishiftEngineBatch.runNow());
