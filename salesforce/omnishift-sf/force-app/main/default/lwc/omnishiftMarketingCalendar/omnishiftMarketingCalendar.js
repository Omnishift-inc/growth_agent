import { LightningElement, wire, track } from 'lwc';
import getCalendar from '@salesforce/apex/OmnishiftAction.getCalendar';

// The week grid Deana had on screen from Account Engagement, with one thing it
// does not show: how many people the agent held back from advisor outreach on
// each send, so the firm does not arrive twice in one inbox.
const DAY_NAMES = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

function startOfWeek(d) {
    const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    x.setDate(x.getDate() - x.getDay());
    return x;
}
function iso(d) {
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
}

export default class OmnishiftMarketingCalendar extends LightningElement {
    @track weekStart = startOfWeek(new Date());
    entries = [];
    error;

    get weekStartIso() {
        return iso(this.weekStart);
    }

    @wire(getCalendar, { weekStart: '$weekStartIso' })
    wired({ data, error }) {
        if (data) {
            this.entries = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.entries = [];
        }
    }

    get rangeLabel() {
        const end = new Date(this.weekStart);
        end.setDate(end.getDate() + 6);
        const f = (d) => d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
        return `${f(this.weekStart)} – ${f(end)}, ${end.getFullYear()}`;
    }

    get days() {
        const today = iso(new Date());
        return DAY_NAMES.map((name, i) => {
            const d = new Date(this.weekStart);
            d.setDate(d.getDate() + i);
            const sends = this.entries
                .filter((e) => e.dayIndex === i)
                .map((e) => ({
                    ...e,
                    label: `${e.time} · ${e.name}`,
                    peopleLabel: `${e.people} ${e.people === 1 ? 'person' : 'people'}`,
                    hasDeferred: e.deferred > 0,
                    deferredLabel: `${e.deferred} deferred`,
                    cls: `send send_${String(e.type || '').toLowerCase().replace(/\s+/g, '-')}`
                }));
            const isToday = iso(d) === today;
            return {
                key: iso(d),
                name,
                num: d.getDate(),
                cls: isToday ? 'day day_today' : 'day',
                sends,
                empty: sends.length === 0
            };
        });
    }

    get totalSends() {
        return this.entries.length;
    }
    get totalDeferred() {
        return this.entries.reduce((n, e) => n + (e.deferred || 0), 0);
    }
    get summary() {
        const s = this.totalSends;
        const d = this.totalDeferred;
        if (!s) return 'Nothing scheduled this week.';
        return `${s} send${s === 1 ? '' : 's'} · ${d} deferred`;
    }

    prev() {
        const d = new Date(this.weekStart);
        d.setDate(d.getDate() - 7);
        this.weekStart = d;
    }
    next() {
        const d = new Date(this.weekStart);
        d.setDate(d.getDate() + 7);
        this.weekStart = d;
    }
    today() {
        this.weekStart = startOfWeek(new Date());
    }
}
