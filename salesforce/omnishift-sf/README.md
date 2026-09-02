# Omnishift Growth Agent - Salesforce DX project

The Growth Agent inside Salesforce: a nightly engine that decides who each advisor should contact today and why, a panel on every Lead and Contact that shows the reasoning and lets them act, a merged queue on Home, a marketing calendar, a compliance check on every draft, and the reports to tell whether it works.

- What is built: `../../docs/features.md`
- Demo script with links: `../../docs/demo-script.md`
- What is left: `../../docs/whats-next.md`
- Demo data scripts: `scripts/apex/demo/README.md`

All data in the org is generated: emails `@example.com`, phones 555-01xx, invented names and events. Live email is behind `Omnishift_Config__mdt.Send_Live_Email__c` and is off.

## Prerequisites

1. A Salesforce **Developer Edition** (or sandbox) org.
2. **My Domain** must be deployed (Setup → My Domain).
3. Install Salesforce CLI if needed:

```bash
npm install -g @salesforce/cli
```

---

## Auth

```bash
sf org login web --alias omnishift-dev
```

Log in to the target Dev Edition org in the browser window that opens.

---

## Deploy

From this project root (`omnishift-sf/`):

```bash
sf project deploy start --target-org omnishift-dev
```

Optional package.json scripts: login, deploy, open.

### What gets deployed

| Metadata | Purpose |
|----------|---------|
Disposition buttons on the panel call lightning/uiRecordApi updateRecord. If fields are missing, a toast shows the API names (Omnishift_Disposition__c, Omnishift_Disposition_Reason__c) — the Stu Maggs / learning-loop point.

---

## Lightning App Builder — Lead (and Contact) record tab named **Omnishift**

This is a **RECORD page tab**, not a Setup → Tabs → Lightning Component Tab.

1. Open any **Lead** record → gear icon → **Edit Page** (Lightning App Builder).
2. In the canvas, select the **Tabs** region (or add a Tabs component if needed).
3. Click **Add Tab** → set tab label to **Omnishift** (Tab Label → Custom → Omnishift).
4. With the Omnishift tab selected, drag **Omnishift Panel** (`omnishiftPanel`) from the Custom components list onto the tab body.
5. Click **Save** → **Activation…** → assign as **Org Default** (and/or App Default / App & Profile as needed) → Save.

Repeat the same steps on a **Contact** record page (same component targets Lead and Contact).

---

## Lightning App Builder — Home: Today Queue

1. App Launcher → open an app with a Home page (e.g. Sales) → gear → **Edit Page**.
2. Drag **Omnishift Today Queue** (`omnishiftTodayQueue`) onto the Home page canvas.
3. **Save** → **Activation…** → set as **Org Default** (or App Default).
4. **Save**.

---

## Assign page as Org Default

In App Builder after Save:

- **Activation…** → **ORG DEFAULT** → assign for desktop (and phone if offered) → **Save**.

Do this for both the Lead (and Contact) record page(s) and the Home page you edited.

---

## Clarifications

| Topic | Guidance |
|-------|----------|
| Record tab vs Setup Tabs | This prototype is meant as a **tab on the Lead/Contact Lightning record page** (Pardot-style). You do **not** need Setup → Tabs → Lightning Component Tab unless you also want the component in the **app nav bar**. |
| Sample data | Labels say SAMPLE / EXAMPLE DATA. Pam Whitaker and queue rows are fictional. |
| Integrations | **Not** connected to WealthFeed or VisitIQ in this build. |
| FlexiPages | Not shipped in metadata — edit pages manually via App Builder as above. |

---

## Project layout

```
omnishift-sf/
  README.md
  sfdx-project.json
  package.json
  force-app/main/default/
    lwc/omnishiftPanel/
    lwc/omnishiftTodayQueue/
    objects/Lead/fields/
    objects/Contact/fields/
```

API version: **62.0**.
