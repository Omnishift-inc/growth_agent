/**
 * Reads outcomes back into the ranking.
 *
 * The client's opening sentence on both calls was an agent that "continuously
 * learns". Until now the loop was open: dispositions and outcomes were written
 * and nothing ever read them. This closes it.
 *
 * Deliberately not a model. It is an observed booking rate per driver, with the
 * firm's prior mixed in until there is enough evidence to trust the data. That
 * is defensible to a compliance officer, explainable to an advisor, and honest
 * about how little it knows early on - which a fitted model on forty records
 * would not be.
 */
public with sharing class OmnishiftLearning {

    // How much evidence a driver needs before its own rate outweighs the prior.
    // Below this the estimate is mostly the prior, which is the correct
    // behaviour when eight records are all you have seen.
    @TestVisible
    private static final Decimal PRIOR_STRENGTH = 20;

    // What the firm believed before any evidence: a booking rate the weights
    // were originally set to imply.
    @TestVisible
    private static final Decimal PRIOR_RATE = 0.15;

    // Apex will not sort a list of custom objects that cannot compare
    // themselves. Most-evidence first, because that is the row a reader should
    // weigh most.
    public class DriverStat implements Comparable {
        @AuraEnabled public String driver;
        @AuraEnabled public Integer surfaced = 0;
        @AuraEnabled public Integer booked = 0;
        @AuraEnabled public Decimal observedRate = 0;
        @AuraEnabled public Decimal smoothedRate = 0;
        @AuraEnabled public Decimal multiplier = 1;
        @AuraEnabled public Boolean enoughEvidence = false;

        public Integer compareTo(Object other) {
            DriverStat o = (DriverStat) other;
            if (o.surfaced == this.surfaced) return this.driver.compareTo(o.driver);
            return (o.surfaced > this.surfaced) ? 1 : -1;
        }
    }

    /**
     * Booking rate per why-now driver, from records that have an outcome.
     * A record with no outcome recorded is not evidence of failure - it is
     * absence of evidence, and counting it as a miss would punish every
     * recommendation nobody got round to.
     */
    public static Map<String, DriverStat> driverStats() {
        Map<String, DriverStat> out = new Map<String, DriverStat>();
        for (String obj : new List<String>{ 'Lead', 'Contact' }) {
            String soql =
                'SELECT Omnishift_Driver__c, Omnishift_Outcome__c FROM ' + obj +
                ' WHERE Omnishift_Outcome__c != null AND Omnishift_Driver__c != null LIMIT 50000';
            for (sObject r : Database.query(soql)) {
                String d = (String) r.get('Omnishift_Driver__c');
                DriverStat s = out.get(d);
                if (s == null) { s = new DriverStat(); s.driver = d; out.put(d, s); }
                s.surfaced++;
                if (r.get('Omnishift_Outcome__c') == 'Meeting booked') s.booked++;
            }
        }
        for (DriverStat s : out.values()) {
            s.observedRate = (s.surfaced == 0) ? 0
                : (Decimal.valueOf(s.booked) / s.surfaced).setScale(4);
            // Shrink toward the prior in proportion to how little we have seen.
            s.smoothedRate = ((s.booked + PRIOR_RATE * PRIOR_STRENGTH)
                              / (s.surfaced + PRIOR_STRENGTH)).setScale(4);
            s.multiplier = (s.smoothedRate / PRIOR_RATE).setScale(3);
            // Bound it. One good fortnight should tilt the ranking, not rebuild it.
            // Tighter than it was. At 1.5 the multiplier alone drove every
            // strong record to the display ceiling, which is evidence
            // overriding the model rather than adjusting it.
            if (s.multiplier > 1.15) s.multiplier = 1.15;
            if (s.multiplier < 0.85) s.multiplier = 0.85;
            s.enoughEvidence = s.surfaced >= PRIOR_STRENGTH;
        }
        return out;
    }

    /** Multipliers only, in the shape the batch wants. */
    public static Map<String, Decimal> multipliers() {
        Map<String, Decimal> m = new Map<String, Decimal>();
        for (DriverStat s : driverStats().values()) m.put(s.driver, s.multiplier);
        return m;
    }

    @AuraEnabled(cacheable=true)
    public static List<DriverStat> getDriverStats() {
        List<DriverStat> l = driverStats().values();
        l.sort();
        return l;
    }
}
