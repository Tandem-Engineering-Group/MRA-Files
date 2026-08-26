# Stop·Down — Live Gear Desk

A free, self-hosted camera-gear search desk that **actually shows listings in the page**,
**saves searches**, **runs them every morning**, and **alerts you** to new finds and price drops.

Runs entirely on **Cloudflare's free tier**: one Worker (hosts the page + API + the daily
cron) + one KV namespace (storage). Optional: an eBay developer key (sturdy live results)
and a Resend key (email alerts).

## What it does
- **Live search** across eBay (Browse API) and Craigslist (Detroit, 100 mi of 48371), shown in-page.
- **Deal score** — each listing flagged as % below the median price of that search.
- **Saved searches** with per-search alert toggle, max price, and exclude words.
- **Daily cron (~7am ET)** re-runs every saved search, detects **new listings** and **price drops**.
- **Alerts** land in the in-app feed and (if configured) your email.

## Deploy (all in the Cloudflare dashboard — no command line needed)
1. Create a free account at **dash.cloudflare.com**.
2. **Workers & Pages → Create → Workers → Import a repository**, and point it at this folder
   (`camera-gear-dash`). (Or create a blank Worker and use `wrangler deploy` from this folder.)
3. **Storage & Databases → KV → Create namespace** (name it `stopdown`). Copy its ID into
   `wrangler.toml` (`kv_namespaces.id`) **and** bind it to the Worker under
   **Worker → Settings → Bindings → KV namespace**, variable name `KV`.
4. **Worker → Settings → Variables & Secrets** — add secrets:
   - `APP_TOKEN` — any access word you choose (you'll type it into the site once).
   - *(optional, for eBay)* `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET` — from
     **developer.ebay.com → Application Keys → Production**.
   - *(optional, for email)* `RESEND_API_KEY` — from **resend.com** (free tier).
5. The **cron** is already declared in `wrangler.toml` (`0 11 * * *`). Confirm it under
   **Worker → Settings → Triggers → Cron Triggers**.
6. Open the Worker's URL. Enter your `APP_TOKEN` when prompted. Search away.

## Notes
- Works in **stages**: with nothing but `APP_TOKEN` + KV it runs on Craigslist immediately.
  Add the eBay key for the main source; add Resend for email. Each is independent.
- eBay results use the official **Browse API** (stable). Craigslist uses its RSS feed (best-effort;
  skips quietly if unavailable). Other dealers (KEH/MPB) block automated reads — use the
  launcher dashboard's "open in tab" tiles for those.
- The daily run's **first** pass per search only records a baseline (no alert flood); alerts start
  on the next run.
- Cron time is UTC; `0 11 * * *` ≈ 7am US Eastern in summer (6am in winter — cron can't do DST).
