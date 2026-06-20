# Cloud export setup — run the board off your PC

Goal: the dashboard stays fresh **without your PC on**. We reuse your existing
`Export-Data.ps1` (workbook + Fleetio + Samsara + the Azure push) — it just runs
in the cloud instead of on your machine.

How it fits together:

```
 Power Automate flow (your login)          GitHub Action (free, scheduled)
 every ~15 min:                            every ~15 min:
   workbook.xlsx  --->  Azure blob   --->    download workbook  --->  run Export-Data.ps1
   (SharePoint)         "pipeline"           (Fleetio + Samsara + Excel)  --->  push data.js -> live site
```

Nothing about how you EDIT the workbook changes — you still edit it in Excel
(PC or browser); the flow just copies it up for the cloud job to read.

---

## One-time setup (≈15 min)

### 1) Add the API tokens as GitHub repo secrets
GitHub → this repo → **Settings → Secrets and variables → Actions → New repository secret**. Add:

| Secret name | Value (from your local files next to Export-Data.ps1) |
|---|---|
| `FLEETIO_API_KEY` | **line 1** of `fleetio.txt` |
| `FLEETIO_ACCOUNT_TOKEN` | **line 2** of `fleetio.txt` |
| `SAMSARA_TOKEN` | the token in `samsara.txt` |
| `AZURE_STORAGE_KEY` | *should already exist* (deploy.yml uses it). If not: `az storage account keys list --account-name mrashopdash --query "[0].value" -o tsv` |

These are encrypted and masked in logs — never printed, never committed.

### 2) The private "pipeline" container — AUTO-CREATED, nothing to do
The GitHub job creates the `pipeline` container itself using the account key, so
you do **not** need Azure portal access for this. (If you ever want to make it by
hand anyway: portal → storage account **mrashopdash** → Containers → + Container →
`pipeline` → Private.)

> No Azure portal access? You don't need it. Everything Azure-side runs off the
> **account key** (your `azure-key.txt` / the `AZURE_STORAGE_KEY` secret) — creating
> the container, the shuttle flow's connection, and the upload/download all use the
> key, not a portal login. Nothing has to be transferred from your partner.

### 3) Build the shuttle flow (Power Automate)
make.powerautomate.com → **+ Create → Scheduled cloud flow**:
1. **Recurrence** trigger — every **15 minutes**.
2. **+ New step → SharePoint → Get file content** — Site = *MRA Site Project*, File = the live workbook
   `…/MRA Claude Code/01.1 RL Claude Bot/MRA_Shop_Board_v6_9_7.xlsx`.
3. **+ New step → Azure Blob Storage → Create blob (V2)** — connect with **account name `mrashopdash` + the account key**:
   - Folder path: `/pipeline`
   - Blob name: `MRA_Shop_Board.xlsx`
   - Blob content: the **File Content** from step 2.
   - (Create-blob overwrites by default; if your version errors on an existing blob, add a **Delete blob** before it, or use "Update blob".)
4. **Save.** All three are **standard** connectors — no premium, no admin.

### 4) Test it (no schedule yet)
1. In Power Automate, **Run** the shuttle flow once → confirm `MRA_Shop_Board.xlsx` lands in the `pipeline` container.
2. GitHub → **Actions → "Cloud export (data.js)" → Run workflow** (pick this branch) → watch it go green. The last step prints `Last run: … OK`.
3. Open the dashboard → the "data as of" time should be brand new. 🎉

### 5) Go live
- The **schedule only runs from the repo's default branch**, so this `export.yml` has to be merged to the default branch for the every‑15‑min run to kick in (tell me when you want that — I won't push to your default branch without the OK).
- Once it's running on its own, **turn off the PC's "MRA Dashboard Auto-Push" scheduled task** — the cloud job has it now. Your PC can sleep.

---

## Notes / known v1 gaps
- **Logistics "at / arriving" status (`mraStatus`)** comes from local OneDrive *Logistics Calendar* files, which the cloud runner can't see — so that one panel will be blank in the cloud build. Everything else (board, projects, Fleetio, Samsara/GPS) is unaffected. We can add it next by shuttling those files too.
- **Timing:** GitHub's scheduler can run a few minutes late under load, so "every 15 min" is really "about every 15–25 min." Fine for the board; we can tighten if needed.
- **Security:** tokens live only as encrypted GitHub secrets and in your local `.txt` files (which are git-ignored). The cloud job writes them to throwaway files inside the runner and the runner is destroyed after each run.
