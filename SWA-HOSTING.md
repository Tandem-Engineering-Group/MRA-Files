# Command Center on Azure Static Web Apps — separate, password-protected copy

**URL:** https://wonderful-desert-0a27f7010.7.azurestaticapps.net
**Azure resource:** Static Web App **MRA-Command-Center** (created by the Tandem partner in the
same Azure account as the `mrashopdash` storage).
**What it is:** a full, independently-hosted copy of the MRA dashboard, protected by a password.
The public board at https://mrashopdash.z13.web.core.windows.net/ is completely unaffected.

---

## Turning the password on (one-time, Azure Portal — needs the partner's Azure login)

1. Azure Portal → the **MRA-Command-Center** Static Web App.
2. **Settings → Configuration → General** tab → **Password protection**.
3. Select **Protect both staging and production environments**.
4. Enter the visitor password (this is the one password everyone will type) → **Save**.
5. If the section is greyed out, the app is on the **Free** hosting plan — switch it first:
   **Settings → Hosting plan → Standard** (also needed later for the Entra/M365 sign-in in Step 4).

After saving, every visit to the SWA URL shows an Azure password page before anything loads.
To change or remove the password, come back to the same screen. The password is stored only in
Azure — it is not in this repo, the workflow, or GitHub secrets.

## How it deploys

`.github/workflows/swa.yml` publishes the app using the **AZURE_SWA_TOKEN** repo secret (the
SWA's deployment token). It runs:

- automatically, on any push to the default branch that changes `MRA_Dashboard.html`,
  `index.html`, `staticwebapp.config.json`, or `catalogue/**`;
- on demand: GitHub → Actions → *Deploy to Azure Static Web App (Command Center)* → Run workflow.

If the SWA is ever recreated, grab the new deployment token (Portal → the SWA → **Overview →
Manage deployment token**) and replace the **AZURE_SWA_TOKEN** secret in the GitHub repo.

## How the data stays live (no redeploys needed)

The copy is the same code as the live board, but at deploy time its runtime reads are rewritten
to absolute URLs on the live site:

- `data.js` (the 30-second board poll) → `https://mrashopdash.z13.web.core.windows.net/data.js`
- `eotm.txt` / `eotm.png` (Employee of the Month) → same origin as above
- `design.json` (design board) → same origin as above

So the password-protected copy always shows the same live data as the public board, updated by
the existing export pipeline — nothing about the pipeline changed. Those cross-origin reads work
because the workflow sets a **GET/HEAD-only CORS rule** on the `mrashopdash` blob service (public
data, so this widens nothing) and verifies it with a real Origin-header request on every deploy.
A `data.js` snapshot is also baked in as a first-paint fallback.

**Writes/edits work too:** board edits post to the Power Automate flows (absolute URLs, no-cors),
which don't care what origin the page is on. Someone with the password can edit exactly like on
the live board.

## Relationship to Step 4 (real M365 sign-in)

This password is the interim lock while the Entra client secret is pending from MRA's IT.
When the real gomra.com sign-in ships (SWA custom Entra provider + role gating), it replaces the
single shared password on this same Static Web App — the hosting, workflow, and URL stay put.

## Removing it

Portal → the Static Web App → Delete (the public board is unaffected), and delete
`.github/workflows/swa.yml` + `staticwebapp.config.json` from the repo.
