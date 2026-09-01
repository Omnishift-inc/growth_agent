import { LightningElement } from 'lwc';

export default class OmnishiftTodayQueue extends LightningElement {
    greeting = 'Good morning';
    workCountLabel = 'Today you should work 17 people';

    scoreboard = [
        { id: 's1', label: 'Due now', value: '6' },
        { id: 's2', label: 'SLA risk', value: '2' },
        { id: 's3', label: 'Referrals', value: '3' },
        { id: 's4', label: 'Quarantine', value: '1' }
    ];

    // SAMPLE rows — Pamela Whitaker fictional case + peers (no Claire-vs-Gus matching)
    rows = [
        {
            id: 'r1',
            name: 'Pamela Whitaker',
            reason: 'Website SLA · Family office page 2h ago',
            tag: 'SLA',
            tagClass: 'tag tag_red',
            action: 'Call today',
            detail: 'VisitIQ journey: Home → Team → Family office'
        },
        {
            id: 'r2',
            name: 'Marcus Chen',
            reason: 'Website SLA · Contact form unanswered 4h',
            tag: 'SLA',
            tagClass: 'tag tag_red',
            action: 'Call / email',
            detail: 'Inbound web lead — response SLA breached'
        },
        {
            id: 'r3',
            name: 'Elena Rostova',
            reason: 'Referral · skip-ranker (partner intro)',
            tag: 'Referral',
            tagClass: 'tag tag_blue',
            action: 'Call referrer first',
            detail: 'Skip normal rank — warm intro from RIA partner'
        },
        {
            id: 'r4',
            name: 'John & Deana Hale',
            reason: '$10M+ household rule · joint decision',
            tag: '$10M+',
            tagClass: 'tag tag_gold',
            action: 'Schedule joint call',
            detail: 'Rule: involve both spouses before proposal'
        },
        {
            id: 'r5',
            name: 'Theo Nakamura',
            reason: 'Quarantine · incomplete KYC packet',
            tag: 'Quarantine',
            tagClass: 'tag tag_gray',
            action: 'Hold outreach',
            detail: 'Do not contact until compliance clears docs'
        },
        {
            id: 'r6',
            name: 'Sofia Alvarez',
            reason: 'Life event · equity vest window',
            tag: 'Signal',
            tagClass: 'tag tag_green',
            action: 'Call this week',
            detail: 'Sample WealthFeed-style event (not live)'
        },
        {
            id: 'r7',
            name: 'David Okonkwo',
            reason: 'Referral · skip-ranker (COI)',
            tag: 'Referral',
            tagClass: 'tag tag_blue',
            action: 'Thank + book',
            detail: 'Attorney COI — prioritize acknowledgment'
        },
        {
            id: 'r8',
            name: 'Priya Desai',
            reason: 'Re-engage · dormant 180d + site visit',
            tag: 'Re-engage',
            tagClass: 'tag tag_green',
            action: 'Soft email',
            detail: 'Approved template only — SAMPLE queue'
        }
    ];
}
