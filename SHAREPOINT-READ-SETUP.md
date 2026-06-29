# SharePoint Lists READ — setup for IT (Step 3, read path)

**Goal:** let the automated export (GitHub Actions) read the 4 MRA SharePoint Lists
headlessly, so the dashboard's `data.js` is generated **from the Lists instead of the
Excel workbook.** This is the only piece that needs an admin; everything else is ready.

The app needs **read-only** access to **one site** (MRA Site Project). Writes do NOT
use this app — they go through Power Automate. So this is least-privilege, read-only.

---

## Part A — IT does this once (~10 minutes), in the morning

1. **Entra admin center** → https://entra.microsoft.com → **Applications → App registrations → New registration**
   - **Name:** `MRA Dashboard Lists Reader`
   - **Supported account types:** *Accounts in this organizational directory only (single tenant)*
   - Redirect URI: leave blank → **Register**

2. On the app's **Overview** page, copy these two (give them to Rich):
   - **Application (client) ID**
   - **Directory (tenant) ID**

3. **API permissions → Add a permission → Microsoft Graph → Application permissions** →
   search **`Sites.Selected`** → check it → **Add permissions** →
   then click **Grant admin consent for <org>** (the row should show a green check).

4. **Grant this app READ on just the MRA Site Project site** (Sites.Selected does
   nothing until you grant a specific site). Easiest with PnP PowerShell:
   ```powershell
   Install-Module PnP.PowerShell -Scope CurrentUser   # if needed
   Connect-PnPOnline -Url "https://snptechnical.sharepoint.com/sites/MRASiteProject" -Interactive
   Grant-PnPAzureADAppSitePermission `
     -AppId "<Application (client) ID from step 2>" `
     -DisplayName "MRA Dashboard Lists Reader" `
     -Site "https://snptechnical.sharepoint.com/sites/MRASiteProject" `
     -Permissions Read
   ```
   *(Graph alternative if you prefer: `GET /sites/snptechnical.sharepoint.com:/sites/MRASiteProject`
   to get the site id, then `POST /sites/{siteId}/permissions` with
   `{"roles":["read"],"grantedToIdentities":[{"application":{"id":"<clientId>","displayName":"MRA Dashboard Lists Reader"}}]}`.)*

5. **Certificates & secrets → New client secret** → description `MRA export`, expiry
   **24 months** → **Add** → **copy the Value immediately** (it's shown only once). Give to Rich.
   ⚠ It expires — calendar a reminder to rotate it (same as the existing GitHub PAT).

**IT hands Rich three things:** Tenant ID, Client ID, Client Secret (value).

---

## Part B — Rich does this once (2 minutes), after IT

Add these as **GitHub repository secrets** (repo → Settings → Secrets and variables →
Actions → New repository secret):

| Secret name | Value |
|---|---|
| `SP_TENANT_ID` | the Directory (tenant) ID |
| `SP_CLIENT_ID` | the Application (client) ID |
| `SP_CLIENT_SECRET` | the client secret **value** |

*(The site URL is already hard-coded: `https://snptechnical.sharepoint.com/sites/MRASiteProject`.)*

---

## Part C — Claude does this (once A + B are done)

- Wire the export to read the 4 Lists via Microsoft Graph using those secrets, emit the
  **same `data.js`** the dashboard already uses (fleet/Samsara + logistics calendars stay
  as they are — they were never in Excel).
- Run it and **diff the output against the current Excel-based `data.js`** until they
  match, then switch `export.yml` over.
- **Nothing visible changes for users** — same dashboard, same data file, new source.

---

## Reference — the Lists and their columns (already loaded)

- **MRA Users** — Title(Name), Code, Active, Role
- **MRA Jobs** — Title(Project), Bay, Client, JobNum, JobStatus, Category, ShipISO, SortOrder
- **MRA Shop Tasks** — Title(Task), Project, Assigned, Status, Milestone, Comments
- **MRA Project Tasks** — Title(Task), Project, TaskID, Phase, Type, Assigned, StartISO,
  FinishISO, Duration, Status, PM, Milestone, Comments, Predecessor (+ optional extras)
