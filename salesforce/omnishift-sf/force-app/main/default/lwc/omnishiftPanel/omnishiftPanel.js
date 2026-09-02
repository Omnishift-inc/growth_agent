import { LightningElement, api, wire } from 'lwc';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { getListRecordsByName } from 'lightning/uiListsApi';
import { NavigationMixin } from 'lightning/navigation';
import recordDisposition from '@salesforce/apex/OmnishiftAction.recordDisposition';
import recordOutcome from '@salesforce/apex/OmnishiftAction.recordOutcome';
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
    'Omnishift_Run_Id__c'
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
    get complianceHelp() {
        const h = {
            'Passed': 'The draft passed every SEC marketing-rule check. It can be sent as written.',
            'Auto-corrected': 'A prohibited term was removed automatically. Re-read the sentence before sending.',
            'Flagged': 'Something a principal should look at before it goes out.',
            'Blocked': 'Cannot be sent as written. Rewrite it first.',
            'Not checked': 'No draft has been checked yet.'
        };
        return 'Result of the compliance check on the draft. ' + (h[this.complianceStatus] || '');
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
