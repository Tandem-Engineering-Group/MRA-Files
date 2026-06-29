# Employee of the Month — edit from the dashboard (flow setup)

Lets the **🏆 Employee of the Month** name + photo be changed right from the board
(☰ Menu → 🏆 Employee of the Month, admin/Rich only), instead of running
`Push-Photo.bat`. The dashboard editor is already live; this is the one-time
back-end flow that actually writes the files.

**How it works:** the editor POSTs `{name, on, photoB64?}` to a Power Automate
HTTP flow, which writes **`eotm.txt`** (the name, or `off`) and **`eotm.png`**
(the photo) into the site's **`$web`** blob container. The board re-reads them.

This is **independent** of the SharePoint Lists work and of the task Save flow —
its own little flow, no dependency.

---

## Already done (Claude)
- Dashboard editor: name field, photo picker + live preview, On/Off, Save —
  gated to the admin login (Rich Miller). Photo URL cache-busts per load so a new
  photo shows on refresh. (rev 4.89)
- `EOTM_WRITE_URL` placeholder in `MRA_Dashboard.html` — Claude pastes the flow
  URL here once you send it, then redeploys.

## You build this once (~15 min)

1. **Power Automate** → **Create → Instant cloud flow** → pick trigger
   **"When an HTTP request is received."** Name it **MRA EOTM**.

2. In that trigger, click **"Use sample payload to generate schema"** and paste:
   ```json
   {"action":"setEOTM","name":"x","on":"on","photoB64":"","contentType":"image/png","pin":"1974","user":"Rich Miller"}
   ```

3. **+ New step → Control → Condition.** Set: **`pin`** *is equal to* **`1974`**
   (your code — this stops anyone else from posting). Everything below goes in the
   **If yes** branch.

4. **If yes → + Add an action → Azure Blob Storage → "Create blob (V2)".**
   - First time, it asks for a connection: **Storage account name = `mrashopdash`**,
     **Authentication = Access Key**, paste the storage **account key** (same
     `AZURE_STORAGE_KEY` the deploy uses).
   - **Folder path / container:** `$web`
   - **Blob name:** `eotm.txt`
   - **Blob content:** switch to expression (the *fx* button) and paste:
     ```
     if(equals(triggerBody()?['on'],'off'),'off',triggerBody()?['name'])
     ```
   *(If "Create blob (V2)" errors because the file already exists, use
   **"Update blob"** instead — same fields.)*

5. **Still in If yes → + Add → Control → Condition.** Set: **`photoB64`**
   *is not equal to* (leave the value box blank). In **that** condition's
   **If yes → Azure Blob Storage → "Create blob (V2)":**
   - **Container:** `$web`  ·  **Blob name:** `eotm.png`
   - **Blob content:** expression (*fx*):
     ```
     base64ToBinary(triggerBody()?['photoB64'])
     ```

6. **Save.** Open the **"When an HTTP request is received"** trigger again and
   **copy the HTTP POST URL** it now shows.

7. **Send Claude that URL.** Claude pastes it into `EOTM_WRITE_URL` and redeploys —
   then **Save** in the editor works end-to-end.

---

## Notes
- **Azure Blob Storage** is a **standard** connector — no premium license needed.
- **Security:** the flow URL lives in the page, so the `pin = 1974` condition in
  step 3 is what keeps it locked to you. (Same model as the task Save flow.)
- **Photo format:** any image works; it's written as `eotm.png` and the board's
  `<img>` renders it regardless of the original format. Keep photos under ~4 MB
  (the editor enforces this).
- **Cache:** the board requests the photo with a per-load cache-buster, so a new
  photo appears on the next refresh; the always-on TV may need one refresh.
- Once this works, you can stop using `Push-Photo.bat`.
