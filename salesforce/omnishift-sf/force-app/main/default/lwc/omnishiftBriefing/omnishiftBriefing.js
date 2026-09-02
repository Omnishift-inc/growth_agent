import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getBriefing from '@salesforce/apex/OmnishiftAction.getBriefing';

// Sits beside the standard Assistant, which only ever lists leads assigned
// today. This answers the questions an advisor actually opens Salesforce with:
// how much is waiting, how much is already done, and what is stuck.
export default class OmnishiftBriefing extends NavigationMixin(LightningElement) {
    data;
    error;

    @wire(getBriefing)
    wired({ data, error }) {
        if (data) {
            this.data = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.data = undefined;
        }
    }

    get isLoading() {
        return !this.data && !this.error;
    }
    get hasError() {
        return Boolean(this.error);
    }
    get errorText() {
        const e = this.error;
        return (e && e.body && (e.body.message || JSON.stringify(e.body))) || 'Unknown error';
    }

    get stats() {
        const d = this.data;
        if (!d) return [];
        return [
            { key: 'due', n: d.due, label: 'to work today', cls: 'stat stat_lead' },
            { key: 'worked', n: d.worked, label: 'handled today', cls: 'stat' },
            { key: 'blocked', n: d.blocked, label: 'blocked by compliance', cls: d.blocked > 0 ? 'stat stat_warn' : 'stat' },
            { key: 'supp', n: d.suppressed, label: 'suppressed', cls: 'stat' }
        ];
    }

    get split() {
        const d = this.data;
        if (!d) return '';
        return `${d.dueLeads} Leads · ${d.dueContacts} Contacts`;
    }

    get sources() {
        const d = this.data;
        if (!d || !d.sources) return [];
        return d.sources.map((s) => ({
            ...s,
            key: s.name,
            cls: s.name === 'WealthFeed' ? 'src src_filing' : s.name === 'VisitIQ' ? 'src src_web' : 'src'
        }));
    }
    get hasSources() {
        return this.sources.length > 0;
    }

    get runLine() {
        const d = this.data;
        if (!d || !d.runId) return '';
        const when = d.scoredOn ? new Date(d.scoredOn).toLocaleString() : '';
        return `${d.runId} · ${when}`;
    }

    // One list, both objects. The old target was the Lead list view, which
    // is half of today - the clients live on Contact and were not on it.
    openQueue() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Omnishift_Today' }
        });
    }
    openListView(event) {
        const objectApiName = event.currentTarget.dataset.object;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName, actionName: 'list' },
            state: { filterName: 'Omnishift_Today' }
        });
    }
}
