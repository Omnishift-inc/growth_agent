import { LightningElement, api, wire } from 'lwc';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { getListRecordsByName } from 'lightning/uiListsApi';
import { NavigationMixin } from 'lightning/navigation';
import recordDisposition from '@salesforce/apex/OmnishiftAction.recordDisposition';
import recordOutcome from '@salesforce/apex/OmnishiftAction.recordOutcome';
import clearDisposition from '@salesforce/apex/OmnishiftAction.clearDisposition';
import getPanelContext from '@salesforce/apex/OmnishiftAction.getPanelContext';
import saveDraft from '@salesforce/apex/OmnishiftAction.saveDraft';
import sendDraft from '@salesforce/apex/OmnishiftAction.sendDraft';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Field API names are identical on Lead and Contact, so we build the qualified list
// from objectApiName at runtime and one component serves both.
const OMNISHIFT_FIELDS = [
    'Omnishift_Score__c',
    'Omnishift_Rank__c',
    'Omnishift_Why_Now__c',
    'Omnishift_Next_Action_Date__c',
    'Omnishift_Recommended_Owner__c',
    'Omnishift_Compliance_Status__c',
    'Omnishift_Compliance_Reason__c',
    'Omnishift_Escalated__c',
    'Omnishift_Outcome__c',
    'Omnishift_Quarantined__c',
    'Omnishift_Draft_Subject__c',
    'Omnishift_Draft_Body__c',
    'Omnishift_Disposition__c',
    'Omnishift_Disposition_Reason__c',
    'Omnishift_Scored_On__c',
    'Omnishift_Run_Id__c',
    'Omnishift_Draft_Edited__c',
    'Omnishift_Dispositioned_On__c'
];

// The advisor picks when to come back. recordDisposition takes the date, so the
// choice is written in the same transaction as the disposition.
const SNOOZE_PRESETS = [
    { label: 'Tomorrow', value: '1' },
    { label: 'In 3 days', value: '3' },
    { label: 'Next week', value: '7' },
    { label: 'In 2 weeks', value: '14' },
    { label: 'In a month', value: '30' },
    { label: 'Pick a date', value: 'custom' }
];

const DISPOSITIONS = [
    { key: 'Approved and sent', label: 'Approve & send' },
    { key: 'Edited before send', label: 'Edit first' },
    { key: 'Call logged', label: 'Log call' },
    { key: 'Snoozed', label: 'Not now' },
    { key: 'Wrong person', label: 'Wrong person' }
];

// Local calendar days throughout. Round-tripping through Date.parse on an ISO
// string reads it as UTC midnight, which lands on the wrong day west of Greenwich.
function isoOf(d) {
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
function daysFromToday(n) {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() + n);
    return d;
}
function fromIso(iso) {
    const [y, m, d] = String(iso).split('-').map(Number);
    return new Date(y, m - 1, d);
}

export default class OmnishiftPanel extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    record;
    error;
    isSaving = false;
    showDraft = false;
    isEditing = false;
    editedSubject;
    editedBody;
    wasEdited = false;
    liveEmail = false;
    personAccounts = false;
    signals = [];

    showSnooze = false;
    snoozeChoice = '7';
    snoozeCustomIso;

    // Snapshot, not a live read: the point of the queue walk is that the advisor
    // keeps their place, and dispositioned records drop straight out of the list.
    queueSnapshot;
    queueUnavailable = false;
    justDispositioned = false;

    get fieldList() {
        const obj = this.objectApiName || 'Lead';
        // IsPersonAccount only exists on Contact; requesting it on Lead would error,
        // so it is only added for Contact.
        // Contact.IsPersonAccount only exists in an org with Person Accounts on.
        // Asking for it anywhere else fails the whole getRecord, which surfaced as
        // a field-level-security error that had nothing to do with the cause.
        const extra =
            obj === 'Contact' && this.personAccounts ? ['Contact.IsPersonAccount'] : [];
        // The lookup's own displayValue comes back null for a User lookup, which
        // put a raw 005... id on screen where the advisor's name belongs. Ask for
        // the spanning field instead.
        extra.push(`${obj}.Omnishift_Recommended_Owner__r.Name`);
        extra.push(`${obj}.Name`);
        return OMNISHIFT_FIELDS.map((f) => `${obj}.${f}`).concat(extra);
    }

    get hasSignals() {
        return this.signals && this.signals.length > 0;
    }

    // ---- the draft, shown as the email it will become ----------------------
    get emailFrom() {
        return this.recommendedOwner && this.recommendedOwner !== 'Unassigned'
            ? this.recommendedOwner
            : 'Unassigned';
    }
    get emailTo() {
        return this.val('Name') || 'the prospect';
    }

    get hasTimeline() {
        return this.timeline && this.timeline.length > 0;
    }
    get upcomingSend() {
        return this.timeline.find((r) => r.upcoming) || null;
    }
    get isEscalated() {
        return Boolean(this.raw('Omnishift_Escalated__c'));
    }

    // The Home queue merges both list views on the global rank. The walk here
    // has to do the same, or the panel says "3 of 20" while the queue says 31 -
    // which is exactly the mismatch the advisor noticed.
    leadQueue;
    contactQueue;

    @wire(getListRecordsByName, {
        objectApiName: 'Lead',
        listViewApiName: 'Omnishift_Today',
        fields: ['Lead.Name', 'Lead.Omnishift_Rank__c'],
        sortBy: ['Lead.Omnishift_Rank__c'],
        pageSize: 50
    })
    wiredLeadQueue({ data, error }) {
        if (error) { this.queueUnavailable = true; return; }
        if (!data) return;
        this.leadQueue = this.readQueue(data, 'Lead');
        this.mergeQueue();
    }

    @wire(getListRecordsByName, {
        objectApiName: 'Contact',
        listViewApiName: 'Omnishift_Today',
        fields: ['Contact.Name', 'Contact.Omnishift_Rank__c'],
        sortBy: ['Contact.Omnishift_Rank__c'],
        pageSize: 50
    })
    wiredContactQueue({ data, error }) {
        if (error) { this.queueUnavailable = true; return; }
        if (!data) return;
        this.contactQueue = this.readQueue(data, 'Contact');
        this.mergeQueue();
    }

    readQueue(data, objectApiName) {
        const rows = Array.isArray(data.records) ? data.records : null;
        if (!rows) { this.queueUnavailable = true; return []; }
        return rows.map((r) => ({
            id: r.id,
            objectApiName,
            name: r.fields && r.fields.Name ? r.fields.Name.value : 'the next record',
            rank: r.fields && r.fields.Omnishift_Rank__c ? Number(r.fields.Omnishift_Rank__c.value) : Number.MAX_SAFE_INTEGER
        }));
    }

    // Snapshot once both halves have answered, so dispositioning a record does
    // not shift the advisor's place mid-walk.
    mergeQueue() {
        if (this.queueSnapshot || !this.leadQueue || !this.contactQueue) return;
        this.queueSnapshot = this.leadQueue.concat(this.contactQueue).sort((a, b) => a.rank - b.rank);
    }

    // One round trip for everything that is not on the record. The timeline
    // already carries the signals, so the separate signals call went too.
    timeline = [];
    signals = [];
    showAllTimeline = false;
    _ctx;
    @wire(getPanelContext, { recordId: '$recordId' })
    wiredContext(result) {
        // kept so the timeline can be re-read after the advisor acts; the
        // cacheable wire otherwise serves yesterday's history back to them
        this._ctx = result;
        const { data } = result;
        if (!data) return;
        this.personAccounts = Boolean(data.personAccounts);
        this.liveEmail = Boolean(data.liveEmail);
        const srcClass = (src) =>
            src === 'WealthFeed' ? 'src src_filing'
            : src === 'VisitIQ' || src === 'Account Engagement' ? 'src src_web'
            : src === 'SmartAsset AMP' || src === 'LinkedIn' ? 'src src_third'
            : src === 'Omnishift' ? 'src src_agent'
            : 'src';
        this.timeline = (data.timeline || []).map((r, i) => ({
            key: `${r.kind}-${i}`,
            ...r,
            rowClass: r.upcoming ? 'tl tl_upcoming' : `tl tl_${r.kind}`,
            iconName: r.upcoming ? 'utility:event'
                : r.kind === 'signal' ? 'utility:trending'
                : r.kind === 'marketing' ? 'utility:email'
                : r.kind === 'activity' ? 'utility:call'
                : r.kind === 'outcome' ? 'utility:success'
                : 'utility:sparkles',
            sourceClass: srcClass(r.source)
        }));
        this.signals = this.timeline.filter((r) => r.kind === 'signal');
    }
    get visibleTimeline() {
        return this.showAllTimeline ? this.timeline : this.timeline.slice(0, 6);
    }
    get timelineHasMore() {
        return this.timeline.length > 6;
    }
    get timelineToggleLabel() {
        return this.showAllTimeline ? 'Show less' : `Show all ${this.timeline.length}`;
    }
    toggleTimeline() {
        this.showAllTimeline = !this.showAllTimeline;
    }

    // ---- what happened: the label the ranking learns from ----
    get outcome() {
        return this.val('Omnishift_Outcome__c');
    }
    get outcomeOptions() {
        const cur = this.outcome;
        return [
            'Meeting booked', 'Replied, no meeting', 'No response',
            'Not interested', 'Too early', 'Should not have been surfaced'
        ].map((o) => ({
            key: o, label: o,
            variant: o === cur ? 'brand' : 'neutral',
            cls: o === cur ? 'pill pill_on' : 'pill',
            pressed: o === cur ? 'true' : 'false',
            disabled: this.isSaving
        }));
    }
    async handleOutcome(event) {
        const outcome = event.currentTarget.dataset.outcome;
        this.isSaving = true;
        try {
            const msg = await recordOutcome({ recordId: this.recordId, outcome });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            if (this._ctx) await refreshApex(this._ctx);
            this.toast('Outcome recorded', msg, 'success');
        } catch (e) {
            this.toast('Could not record the outcome', this.messageOf(e), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fieldList' })
    wiredRecord({ data, error }) {
        if (data) {
            this.record = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.record = undefined;
        }
    }

    val(field) {
        const f = this.record && this.record.fields && this.record.fields[field];
        if (!f) return null;
        return f.displayValue !== null && f.displayValue !== undefined
            ? f.displayValue
            : f.value;
    }

    raw(field) {
        const f = this.record && this.record.fields && this.record.fields[field];
        return f ? f.value : null;
    }

    // ---- state -------------------------------------------------------------
    get isLoading() {
        return !this.record && !this.error;
    }
    get hasError() {
        return Boolean(this.error);
    }
    get isScored() {
        return Boolean(this.record && this.raw('Omnishift_Scored_On__c'));
    }
    get notScored() {
        return Boolean(this.record) && !this.isScored;
    }
    get isPersonContact() {
        return Boolean(this.raw('IsPersonAccount'));
    }

    // ---- display -----------------------------------------------------------
    get score() {
        return this.raw('Omnishift_Score__c');
    }
    get rank() {
        const r = this.raw('Omnishift_Rank__c');
        return r === null ? null : String(r).padStart(2, '0');
    }
    get whyNow() {
        return this.val('Omnishift_Why_Now__c');
    }
    get nextActionDate() {
        return this.val('Omnishift_Next_Action_Date__c');
    }
    get recommendedOwner() {
        const rel =
            this.record &&
            this.record.fields &&
            this.record.fields.Omnishift_Recommended_Owner__r;
        const name = rel && rel.value && rel.value.fields && rel.value.fields.Name;
        if (name && name.value) return name.value;
        // Nobody routed to, rather than routed to an id we could not resolve.
        return this.raw('Omnishift_Recommended_Owner__c') ? 'Unresolved user' : 'Unassigned';
    }
    get runId() {
        return this.val('Omnishift_Run_Id__c');
    }
    get scoredOn() {
        return this.val('Omnishift_Scored_On__c');
    }
    get draftHeadline() {
        if (this.draftSubject) return this.workingSubject;
        return this.raw('Omnishift_Quarantined__c') ? 'No draft - this record was held back' : 'No draft yet';
    }
    get draftSubject() {
        return this.val('Omnishift_Draft_Subject__c');
    }
    get draftBody() {
        return this.val('Omnishift_Draft_Body__c');
    }
    get lastDisposition() {
        return this.val('Omnishift_Disposition__c');
    }
    get dispositionReason() {
        return this.val('Omnishift_Disposition_Reason__c');
    }
    get hasDisposition() {
        return Boolean(this.lastDisposition);
    }

    get complianceStatus() {
        return this.val('Omnishift_Compliance_Status__c') || 'Not checked';
    }
    get complianceReason() {
        // The status says what happened; the reason says why. A blocked draft is
        // useless to an advisor without the term that blocked it.
        return this.val('Omnishift_Compliance_Reason__c');
    }
    get complianceIsBlocked() {
        return this.raw('Omnishift_Compliance_Status__c') === 'Blocked';
    }
    get complianceTheme() {
        const s = this.raw('Omnishift_Compliance_Status__c');
        if (s === 'Blocked') return 'slds-theme_error';
        if (s === 'Flagged') return 'slds-theme_warning';
        return 'slds-theme_success';
    }
    get complianceIcon() {
        const s = this.raw('Omnishift_Compliance_Status__c');
        if (s === 'Blocked') return 'utility:error';
        if (s === 'Flagged') return 'utility:warning';
        if (s === 'Auto-corrected') return 'utility:edit';
        return 'utility:success';
    }

    get draftButtonLabel() {
        return this.showDraft ? 'Hide draft' : 'Show draft';
    }

    // Every action carries equal visual weight. Salesforce publishes the opposite as an
    // anti-pattern: send must not outrank edit, so nobody sends AI copy unread.
    // The recommended action is the send. Six identical buttons made every choice
    // look equally likely, which is the opposite of a recommendation - so the
    // send is the only brand button, editing sits beside it, and the rest drop
    // to a quieter row.
    // ---- where this record is in the advisor's hands ----------------------
    // The footer used to show every button on every visit, so a record that
    // had been snoozed yesterday looked exactly like one nobody had touched.
    // One state at a time: what was done, and what is left to do.
    get stage() {
        const d = this.raw('Omnishift_Disposition__c');
        const o = this.raw('Omnishift_Outcome__c');
        if (d === 'Wrong person') return 'wrong';
        if (o === 'Meeting booked') return 'booked';
        if (d === 'Snoozed') return 'snoozed';
        if (o) return 'closed';
        if (d === 'Approved and sent' || d === 'Edited before send' || d === 'Call logged') return 'sent';
        return 'open';
    }
    get isOpenStage() { return this.stage === 'open'; }
    get isSentStage() { return this.stage === 'sent'; }
    get isSnoozedStage() { return this.stage === 'snoozed'; }
    get isWrongStage() { return this.stage === 'wrong'; }
    get showOutcome() { return ['sent', 'closed', 'booked'].includes(this.stage); }
    get showQuietActions() { return ['sent', 'closed'].includes(this.stage); }
    get touchVerb() {
        return this.raw('Omnishift_Disposition__c') === 'Call logged' ? 'called' : 'emailed';
    }
    get dispositionedOn() { return this.val('Omnishift_Dispositioned_On__c'); }
    get outcomeOn() { return this.val('Omnishift_Outcome_On__c'); }
    get stageBanner() {
        const when = this.dispositionedOn ? ` on ${this.dispositionedOn}` : '';
        const note = this.dispositionReason ? ` ${this.dispositionReason}` : '';
        switch (this.stage) {
            case 'sent':
                return { cls: 'dstate dstate_sent', icon: 'utility:email',
                    title: (this.touchVerb === 'called' ? 'Call logged' : 'Email sent') + when,
                    text: (note || ' Sent as drafted.') + ' Record what happened when you hear back.' };
            case 'snoozed':
                return { cls: 'dstate dstate_snoozed', icon: 'utility:clock',
                    title: 'Not now' + (this.nextActionDate ? ` - comes back ${this.nextActionDate}` : ''),
                    text: note || ' Off today\'s list until then.' };
            case 'wrong':
                return { cls: 'dstate dstate_wrong', icon: 'utility:ban',
                    title: 'Marked as the wrong person' + when,
                    text: ' Held off the list until you undo it.' };
            case 'booked':
                return { cls: 'dstate dstate_booked', icon: 'utility:event',
                    title: 'Meeting booked' + (this.outcomeOn ? ` - recorded ${this.outcomeOn}` : ''),
                    text: ' Off the list until the outcome changes.' };
            case 'closed':
                return { cls: 'dstate dstate_closed', icon: 'utility:check',
                    title: `Outcome: ${this.outcome}` + (this.outcomeOn ? ` - recorded ${this.outcomeOn}` : ''),
                    text: ' Change it below if things move.' };
            default:
                return null;
        }
    }
    get outcomePrompt() {
        if (this.stage === 'sent') {
            return `What happened after the ${this.touchVerb === 'called' ? 'call' : 'email'}${this.dispositionedOn ? ' on ' + this.dispositionedOn : ''}?`;
        }
        return 'What happened';
    }
    get quietActions() {
        return [
            { key: 'Call logged', label: 'Log another call' },
            { key: 'Snoozed', label: 'Not now' }
        ].map((d) => ({ ...d, disabled: this.isSaving }));
    }
    async handleUndo() {
        this.isSaving = true;
        try {
            const message = await clearDisposition({ recordId: this.recordId });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            if (this._ctx) await refreshApex(this._ctx);
            this.showSnooze = false;
            this.toast('Back on the list', message, 'success');
        } catch (e) {
            this.toast('Could not undo', this.messageOf(e), 'error');
        } finally {
            this.isSaving = false;
        }
    }
    handleChangeDate() {
        this.showSnooze = true;
    }

    get primaryAction() {
        return {
            key: 'Approved and sent',
            label: this.liveEmail ? 'Approve & send' : 'Approve',
            // A compliance block stops the send. It must never stop the phone call.
            disabled: this.isSaving || this.complianceIsBlocked
        };
    }
    get secondaryActions() {
        return [
            { key: 'Edited before send', label: 'Edit first' },
            { key: 'Call logged', label: 'Log a call' },
            { key: 'Snoozed', label: 'Not now' }
        ].map((d) => ({ ...d, disabled: this.isSaving }));
    }
    get wrongPersonDisabled() {
        return this.isSaving;
    }

    // What the advisor should read first: how strong, why, and whether it can go.
    // One sentence per label, for the tooltip. The chip is the headline; this
    // is what it means to the person reading it.
    get driverHelp() {
        const h = {
            'Event': 'A confirmed event from a data feed - a filing, a sale, a role change - is the strongest thing on this record.',
            'Referral': 'Arrived through an introduction. Referred prospects convert better than any other intake.',
            'Inbound web': 'Came in through the website. The stated SLA is a response inside five minutes.',
            'New and unworked': 'Created recently and nobody has contacted them yet.',
            'Review overdue': 'An existing client past the annual review.',
            'Dormant': 'Nothing recorded for a long time. Ageing out unworked.',
            'Profile fit': 'No timing signal. Surfaced on profile alone: seniority and size against the ideal client.'
        };
        return 'Why this record is on the list today. ' + (h[this.driverLabel] || '');
    }
    // The check's verdict in the advisor's terms. "Passed" named the check;
    // "Cleared to send" says what to do.
    get complianceLabel() {
        return {
            'Passed': 'Draft cleared to send',
            'Auto-corrected': 'Draft corrected - re-read it',
            'Flagged': 'Draft needs a principal\'s review',
            'Blocked': 'Draft blocked - rewrite it'
        }[this.complianceStatus] || 'No draft checked yet';
    }
    get complianceHelp() {
        const h = {
            'Passed': 'The draft was checked against the SEC marketing rule - no guarantees, no performance claims, no superlatives - and nothing was found. Send as written.',
            'Auto-corrected': 'A prohibited term was removed from the draft automatically. Read the corrected sentence before sending.',
            'Flagged': 'The draft contains something a principal should look at before it goes out.',
            'Blocked': 'The draft cannot be sent as written. Rewrite it first.',
            'Not checked': 'No draft has been checked yet.'
        };
        return h[this.complianceStatus] || h['Not checked'];
    }
    get driverLabel() {
        const w = this.whyNow || '';
        if (w.includes('picked up')) return 'Event';
        if (w.startsWith('Referral') || w.includes('introduction')) return 'Referral';
        if (w.includes('inbound web enquiry') || w.startsWith('Inbound web')) return 'Inbound web';
        if (w.startsWith('Created')) return 'New and unworked';
        if (w.startsWith('Nothing recorded')) return 'Review overdue';
        if (w.startsWith('Dormant')) return 'Dormant';
        return 'Profile fit';
    }
    get scoreBand() {
        const n = Number(this.score);
        if (n >= 80) return 'band band_high';
        if (n >= 60) return 'band band_mid';
        return 'band band_low';
    }
    get complianceChipClass() {
        const s = this.complianceStatus;
        return s === 'Blocked' ? 'chip chip_block'
            : s === 'Flagged' ? 'chip chip_flag'
            : s === 'Auto-corrected' ? 'chip chip_info'
            : 'chip chip_pass';
    }
    // The verdict in words an advisor can act on: what was found, what the
    // rule says about it, and what to do. The raw reason is a rule citation.
    get draftWasEdited() {
        return this.raw('Omnishift_Draft_Edited__c') === true;
    }
    get complianceNoteClass() {
        return this.complianceIsBlocked ? 'note note_block' : 'note note_flag';
    }
    get complianceNoteTitle() {
        const s = this.raw('Omnishift_Compliance_Status__c');
        if (s === 'Blocked') return 'Blocked: this draft cannot be sent as written.';
        if (s === 'Flagged') return 'Needs a principal\'s review before it goes out.';
        return 'Corrected automatically - re-read it before sending.';
    }
    get complianceNoteText() {
        const r = this.complianceReason || '';
        const m = r.match(/"([^"]+)"/);
        const term = m ? m[1] : null;
        const s = this.raw('Omnishift_Compliance_Status__c');
        if (s === 'Blocked' && term) {
            // Where the phrase came from matters: the agent's templates are
            // built to pass, so a block almost always sits on an edit.
            const origin = this.draftWasEdited
                ? ` The agent's own draft passed. "${term}" was added when the draft was edited, so the block is on the edited version.`
                : ` It is in the draft the agent wrote, which should not happen - please flag it.`;
            return `${origin} Under the SEC marketing rule (206(4)-1) it is a claim the firm cannot substantiate, so the send button is off until the phrase is gone. Edit the draft and remove it; the check runs again when you save.`;
        }
        if (s === 'Auto-corrected' && term) {
            return ` "${term}" was removed from the draft. Read the corrected sentence so it still makes sense.`;
        }
        return ' ' + r;
    }
    get complianceNeedsAttention() {
        return this.complianceStatus !== 'Passed' && this.complianceStatus !== 'Not checked';
    }
    get sendFootnote() {
        return this.complianceIsBlocked ? 'Blocked until the draft is edited.' : '';
    }

    get workingSubject() {
        return this.editedSubject !== undefined ? this.editedSubject : this.draftSubject;
    }
    get workingBody() {
        return this.editedBody !== undefined ? this.editedBody : this.draftBody;
    }
    get sendModeNote() {
        return this.liveEmail ? '' : 'Live email is off: sending logs the outreach without delivering it.';
    }

    // ---- today's queue -----------------------------------------------------
    get queueIndex() {
        if (!this.queueSnapshot) return -1;
        return this.queueSnapshot.findIndex((q) => q.id === this.recordId);
    }
    get inQueue() {
        return this.queueIndex >= 0;
    }
    get queuePosition() {
        return `#${this.queueIndex + 1} of ${this.queueSnapshot.length} today`;
    }
    // Shown beside the global rank so the two numbers an advisor sees - the
    // position on the Home queue and the rank on the record - can be read
    // together instead of looking like a disagreement.
    get rankChip() {
        return this.inQueue ? `Rank ${this.rank} · #${this.queueIndex + 1} today` : `Rank ${this.rank}`;
    }
    get positionChip() {
        return this.inQueue ? `#${this.queueIndex + 1} today` : null;
    }
    get nextInQueue() {
        const i = this.queueIndex;
        return i >= 0 && this.queueSnapshot[i + 1] ? this.queueSnapshot[i + 1] : null;
    }
    get hasNext() {
        return Boolean(this.nextInQueue);
    }
    get nextLabel() {
        return `Next: ${this.nextInQueue.name}`;
    }
    get atQueueEnd() {
        return this.inQueue && !this.hasNext;
    }
    // Once something has been recorded, moving on is the obvious next step, so
    // it stops competing with the disposition buttons and starts leading.
    get nextVariant() {
        return this.justDispositioned ? 'brand' : 'neutral';
    }

    handleNext() {
        const n = this.nextInQueue;
        if (!n) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: n.id, objectApiName: n.objectApiName, actionName: 'view' }
        });
    }

    handleBackToQueue() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'home' }
        });
    }

    // ---- snooze ------------------------------------------------------------
    get snoozeOptions() {
        return SNOOZE_PRESETS;
    }
    get snoozeIsCustom() {
        return this.snoozeChoice === 'custom';
    }
    get todayIso() {
        return isoOf(daysFromToday(0));
    }
    get snoozeDate() {
        if (this.snoozeIsCustom) {
            return this.snoozeCustomIso ? fromIso(this.snoozeCustomIso) : null;
        }
        return daysFromToday(Number(this.snoozeChoice));
    }
    get snoozeIso() {
        const d = this.snoozeDate;
        return d ? isoOf(d) : null;
    }
    get snoozeLabel() {
        const d = this.snoozeDate;
        return d ? d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) : null;
    }
    get snoozeIsPast() {
        const d = this.snoozeDate;
        return Boolean(d) && isoOf(d) < this.todayIso;
    }
    get snoozeConfirmLabel() {
        return this.snoozeLabel ? `Snooze until ${this.snoozeLabel}` : 'Snooze';
    }
    get snoozeConfirmDisabled() {
        return this.isSaving || !this.snoozeDate || this.snoozeIsPast;
    }

    handleSnoozeChoice(event) {
        this.snoozeChoice = event.detail.value;
    }
    handleSnoozeDate(event) {
        this.snoozeCustomIso = event.detail.value;
    }
    handleCancelSnooze() {
        this.showSnooze = false;
    }

    async handleConfirmSnooze() {
        if (this.snoozeConfirmDisabled) return;
        if (this.isPersonContact) {
            this.toast(
                'Person account',
                'Salesforce requires changes to a person account to go through the Account, not the Contact.',
                'warning'
            );
            return;
        }
        const iso = this.snoozeIso;
        const label = this.snoozeLabel;
        this.isSaving = true;
        try {
            // One write. recordDisposition takes the date now, so the disposition,
            // the reason and the return date land in the same transaction - there
            // is no window where the record is snoozed for a week the advisor
            // never asked for.
            const message = await recordDisposition({
                recordId: this.recordId,
                disposition: 'Snoozed',
                reason: `Snoozed until ${label} from the Growth Agent panel.`,
                subject: null,
                body: null,
                snoozeUntil: iso
            });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            if (this._ctx) await refreshApex(this._ctx);
            this.showSnooze = false;
            this.justDispositioned = true;
            this.toast('Snoozed', message, 'success');
            this.dispatchEvent(
                new CustomEvent('dispositioned', {
                    detail: { recordId: this.recordId, disposition: 'Snoozed', until: iso },
                    bubbles: true,
                    composed: true
                })
            );
        } catch (e) {
            this.toast('Could not snooze', this.messageOf(e), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // ---- behaviour ---------------------------------------------------------
    toggleDraft() {
        this.showDraft = !this.showDraft;
        if (!this.showDraft) this.isEditing = false;
    }

    handleDraftChange(event) {
        const which = event.currentTarget.dataset.field;
        if (which === 'subject') this.editedSubject = event.detail.value;
        else this.editedBody = event.detail.value;
    }

    handleCancelEdit() {
        this.editedSubject = undefined;
        this.editedBody = undefined;
        this.isEditing = false;
    }

    async handleSaveDraft() {
        this.isSaving = true;
        try {
            const res = await saveDraft({
                recordId: this.recordId,
                subject: this.workingSubject,
                body: this.workingBody
            });
            // Compliance may have cleaned the text; show what was actually stored.
            this.editedSubject = res.subject;
            this.editedBody = res.body;
            this.wasEdited = true;
            this.isEditing = false;
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            if (this._ctx) await refreshApex(this._ctx);
            this.toast(
                res.blocked ? 'Saved, but blocked' : 'Draft saved',
                res.reason,
                res.blocked ? 'warning' : 'success'
            );
        } catch (e) {
            this.toast('Could not save the draft', this.messageOf(e), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSend() {
        this.isSaving = true;
        try {
            const message = await sendDraft({
                recordId: this.recordId,
                subject: this.workingSubject,
                body: this.workingBody,
                wasEdited: this.wasEdited
            });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            if (this._ctx) await refreshApex(this._ctx);
            this.justDispositioned = true;
            this.toast('Done', message, 'success');
        } catch (e) {
            this.toast('Not sent', this.messageOf(e), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    messageOf(e) {
        return (
            (e && e.body && (e.body.message || JSON.stringify(e.body))) ||
            (e && e.message) ||
            'Unknown error'
        );
    }

    async handleDisposition(event) {
        const disposition = event.currentTarget.dataset.disposition;
        // These two are not plain dispositions: one sends, one opens the editor.
        if (disposition === 'Approved and sent') {
            this.showDraft = true;
            return this.handleSend();
        }
        if (disposition === 'Edited before send') {
            this.showDraft = true;
            this.isEditing = true;
            return undefined;
        }
        // A snooze needs a date before it means anything, so this opens the
        // chooser rather than committing a week nobody asked for.
        if (disposition === 'Snoozed') {
            this.showSnooze = true;
            return undefined;
        }
        if (this.isPersonContact) {
            this.toast(
                'Person account',
                'Salesforce requires changes to a person account to go through the Account, not the Contact.',
                'warning'
            );
            return;
        }
        this.isSaving = true;
        const reason =
            disposition === 'Wrong person'
                ? 'Marked wrong person from the Omnishift panel.'
                : null;
        try {
            // Apex, not updateRecord: approving has to log the activity and clear
            // the next action date in the same transaction as the disposition,
            // or the lead comes back in tomorrow's queue as though nothing happened.
            const message = await recordDisposition({
                recordId: this.recordId,
                disposition,
                reason,
                subject: this.draftSubject,
                body: this.draftBody,
                snoozeUntil: null
            });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            if (this._ctx) await refreshApex(this._ctx);
            this.justDispositioned = true;
            this.toast('Recorded', message, 'success');
            this.dispatchEvent(
                new CustomEvent('dispositioned', {
                    detail: { recordId: this.recordId, disposition },
                    bubbles: true,
                    composed: true
                })
            );
        } catch (e) {
            const msg =
                (e && e.body && (e.body.message || JSON.stringify(e.body))) ||
                (e && e.message) ||
                'Unknown error';
            this.toast('Could not save', msg, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
