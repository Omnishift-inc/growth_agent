import { LightningElement, api, track } from 'lwc';
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class OmnishiftPanel extends LightningElement {
    @api recordId;
    @track showDraft = false;
    @track lastDisposition = '';
    @track isSaving = false;

    // SAMPLE DATA — Pamela Whitaker fictional case (not live WealthFeed / VisitIQ)
    sampleName = 'Pamela Whitaker';
    sampleSubtitle = 'SAMPLE · Lead / Prospect · Wealth Management';
    recommendedAction = 'Call today';
    whyNowChips = [
        { id: '1', label: 'Website visit 2h ago', tone: 'warning' },
        { id: '2', label: 'AUM signal ↑', tone: 'success' },
        { id: '3', label: 'Life event: retirement window', tone: 'info' }
    ];
    note2018 =
        '2018 note (SAMPLE): Pam mentioned rolling a 401(k) after a corporate exit. ' +
        'Preferred mornings. Husband Deana on joint decisions for $10M+ households.';
    journeySteps = [
        { id: 'j1', label: 'Home', detail: 'Visited /wealth overview', active: false },
        { id: 'j2', label: 'Team', detail: 'Viewed advisor bios', active: false },
        { id: 'j3', label: 'Family office', detail: 'Downloaded FO one-pager', active: true }
    ];
    talkTrack =
        'Hi Pam — saw you were looking at our family-office materials. ' +
        'Happy to walk through how we coordinate multi-entity households and ' +
        'whether a short intro call this week would help.';
    complianceChecks = [
        { id: 'c1', label: 'Do-not-call cleared', ok: true },
        { id: 'c2', label: 'Email consent on file', ok: true },
        { id: 'c3', label: 'FINRA / firm policy OK for soft pitch', ok: true },
        { id: 'c4', label: 'No open complaint flag', ok: true }
    ];
    draftEmail =
        'Subject: Following up on your family-office research\n\n' +
        'Hi Pam,\n\nThank you for visiting our site. Based on your interest in ' +
        'family-office coordination, I wanted to offer a brief call to compare notes ' +
        'on multi-entity planning without any commitment.\n\nBest regards';
    identityStrip = [
        { id: 'i1', label: 'CRM ID', value: '00Q-SAMPLE-PAM-001' },
        { id: 'i2', label: 'VisitIQ SID', value: 'viq_x9k2m_sample' },
        { id: 'i3', label: 'WealthFeed', value: 'wf-demo-pw-8841' },
        { id: 'i4', label: 'Household', value: 'Whitaker · $10M+ rule' }
    ];

    get draftButtonLabel() {
        return this.showDraft ? 'Hide draft' : 'Show draft';
    }

    get whyNowItems() {
        return this.whyNowChips.map((c) => ({
            ...c,
            className: `chip chip_${c.tone}`
        }));
    }

    get journeyItems() {
        return this.journeySteps.map((s) => ({
            ...s,
            className: s.active ? 'journey-step journey-step_active' : 'journey-step'
        }));
    }

    get complianceItems() {
        return this.complianceChecks.map((c) => ({
            ...c,
            icon: c.ok ? 'utility:success' : 'utility:warning',
            variant: c.ok ? 'success' : 'warning'
        }));
    }

    handleToggleDraft() {
        this.showDraft = !this.showDraft;
    }

    async handleDisposition(event) {
        const disposition = event.currentTarget.dataset.disposition;
        let reason = '';
        if (disposition === 'Wrong person') {
            reason = 'Marked wrong person from Omnishift panel (SAMPLE).';
        }
        await this.writeDisposition(disposition, reason);
    }

    async writeDisposition(disposition, reason) {
        if (!this.recordId) {
            this.toast(
                'No record Id',
                'Open this panel on a Lead or Contact record page.',
                'warning'
            );
            return;
        }
        this.isSaving = true;
        const fields = {
            Id: this.recordId,
            Omnishift_Disposition__c: disposition
        };
        if (reason) {
            fields.Omnishift_Disposition_Reason__c = reason;
        }
        try {
            await updateRecord({ fields });
            this.lastDisposition = disposition;
            this.toast(
                'Disposition saved',
                `Omnishift_Disposition__c = "${disposition}"`,
                'success'
            );
        } catch (e) {
            const msg =
                (e && e.body && (e.body.message || JSON.stringify(e.body))) ||
                (e && e.message) ||
                'Unknown error';
            this.toast(
                'Could not update disposition',
                `Check fields Omnishift_Disposition__c and Omnishift_Disposition_Reason__c on Lead/Contact. ${msg}`,
                'error'
            );
        } finally {
            this.isSaving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
