// Stop·Down — live camera-gear search desk (Cloudflare Worker)
// Serves the static UI, exposes a small JSON API, and runs a daily cron that
// re-runs saved searches and flags new listings + price drops.
//
// Bindings expected (see wrangler.toml):
//   ASSETS   - static assets (the /public folder)
//   KV       - Workers KV namespace for state
// Secrets (set in the Cloudflare dashboard, NOT in wrangler.toml):
//   APP_TOKEN            - access word the UI must send (leave unset = open)
//   EBAY_CLIENT_ID       - eBay developer App ID     (optional; enables eBay)
//   EBAY_CLIENT_SECRET   - eBay developer Cert ID     (optional)
//   RESEND_API_KEY       - Resend key                 (optional; enables email)
// Vars (wrangler.toml [vars]):
//   CRAIGSLIST_REGION (e.g. "detroit"), CRAIGSLIST_POSTAL, CRAIGSLIST_DISTANCE

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,x-app-token",
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    if (url.pathname.startsWith("/api/")) {
      try { return await handleApi(request, env, url); }
      catch (e) { return json({ error: String(e && e.message || e) }, 500); }
    }
    // everything else = static UI
    if (env.ASSETS) return env.ASSETS.fetch(request);
    return new Response("Not found", { status: 404 });
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runDaily(env));
  },
};

/* ----------------------------- helpers ----------------------------- */
function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status: status || 200,
    headers: Object.assign({ "Content-Type": "application/json" }, CORS),
  });
}
function authed(request, env, url) {
  if (!env.APP_TOKEN) return true; // open if no token configured
  const t = url.searchParams.get("token") || request.headers.get("x-app-token");
  return t === env.APP_TOKEN;
}
function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}
function decodeXml(s) {
  return String(s || "")
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#38;/g, "&").replace(/&#39;/g, "'").trim();
}

/* ----------------------------- API ----------------------------- */
async function handleApi(request, env, url) {
  const p = url.pathname;
  if (p === "/api/ping") {
    if (!authed(request, env, url)) return json({ ok: false }, 401);
    return json({ ok: true, ebay: !!env.EBAY_CLIENT_ID, email: !!env.RESEND_API_KEY });
  }
  if (!authed(request, env, url)) return json({ error: "unauthorized" }, 401);

  if (p === "/api/search") {
    const q = (url.searchParams.get("q") || "").trim();
    if (!q) return json({ items: [], median: null });
    const opts = {
      max: num(url.searchParams.get("max")),
      exclude: url.searchParams.get("exclude") || "",
      sort: url.searchParams.get("sort") || "deal",
    };
    const sources = (url.searchParams.get("sources") || "ebay,craigslist").split(",");
    return json(await search(env, q, opts, sources));
  }

  if (p === "/api/saved") {
    if (request.method === "GET") return json({ items: await getSaved(env) });
    if (request.method === "POST") {
      const body = await request.json();
      const list = await getSaved(env);
      const clean = {
        q: (body.q || "").trim(),
        max: body.max || "", exclude: body.exclude || "",
        ebay: body.ebay !== false, cl: body.cl !== false,
        alert: body.alert !== false,
      };
      if (!clean.q) return json({ error: "empty query" }, 400);
      // match by id, else by normalized query
      const key = clean.q.toLowerCase();
      let existing = list.find((x) => x.id === body.id) ||
        list.find((x) => (x.q || "").toLowerCase() === key);
      if (existing) Object.assign(existing, clean, { id: existing.id });
      else list.unshift(Object.assign({ id: uid() }, clean));
      await env.KV.put("saved", JSON.stringify(list));
      return json({ ok: true, items: list });
    }
    if (request.method === "DELETE") {
      const id = url.searchParams.get("id");
      let list = await getSaved(env);
      list = list.filter((x) => x.id !== id);
      await env.KV.put("saved", JSON.stringify(list));
      await env.KV.delete("seen:" + id);
      return json({ ok: true, items: list });
    }
  }

  if (p === "/api/alerts") {
    const items = (await env.KV.get("alerts", "json")) || [];
    const lastRun = await env.KV.get("lastRun");
    return json({ items, lastRun });
  }
  if (p === "/api/alerts/clear" && request.method === "POST") {
    await env.KV.put("alerts", "[]");
    return json({ ok: true });
  }

  if (p === "/api/settings") {
    if (request.method === "GET") return json((await env.KV.get("settings", "json")) || {});
    if (request.method === "POST") {
      const body = await request.json();
      const s = { email: (body.email || "").trim(), emailOn: !!body.emailOn };
      await env.KV.put("settings", JSON.stringify(s));
      return json({ ok: true });
    }
  }

  return json({ error: "not found" }, 404);
}

function num(v) { const n = parseFloat(v); return isNaN(n) ? null : n; }
function uid() { return "s" + Math.random().toString(16).slice(2, 10); }
async function getSaved(env) { return (await env.KV.get("saved", "json")) || []; }

/* ----------------------------- search ----------------------------- */
async function search(env, q, opts, sources) {
  let items = [];
  const notes = [];
  if (sources.includes("ebay")) {
    if (env.EBAY_CLIENT_ID) {
      try { items = items.concat(await ebaySearch(env, q, opts)); }
      catch (e) { notes.push("eBay error"); }
    } else notes.push("eBay key not set");
  }
  if (sources.includes("craigslist")) {
    try { items = items.concat(await craigslistSearch(env, q, opts)); }
    catch (e) { notes.push("Craigslist unavailable"); }
  }
  items = applyExclude(items, opts.exclude);
  items = dedupe(items);
  const median = computeMedian(items);
  items.forEach((it) => {
    if (it.price != null && median) it.belowPct = Math.round((1 - it.price / median) * 100);
  });
  items = sortItems(items, opts.sort);
  return { items, median, notes: notes.join("; ") };
}

function applyExclude(items, exclude) {
  if (!exclude) return items;
  const words = exclude.toLowerCase().split(/[\s,]+/).filter(Boolean);
  return items.filter((i) => {
    const t = (i.title || "").toLowerCase();
    return !words.some((w) => t.includes(w));
  });
}
function dedupe(items) {
  const seen = {};
  return items.filter((i) => (seen[i.id] ? false : (seen[i.id] = 1)));
}
function computeMedian(items) {
  const ps = items.filter((i) => i.price > 0).map((i) => i.price).sort((a, b) => a - b);
  if (!ps.length) return null;
  return ps[Math.floor(ps.length / 2)];
}
function sortItems(items, sort) {
  const a = items.slice();
  if (sort === "price") a.sort((x, y) => (x.price ?? 1e12) - (y.price ?? 1e12));
  else if (sort === "newest") a.sort((x, y) => (Date.parse(y.posted || 0) || 0) - (Date.parse(x.posted || 0) || 0));
  else a.sort((x, y) => (y.belowPct ?? -999) - (x.belowPct ?? -999)); // best deals
  return a;
}

/* ----------------------------- eBay ----------------------------- */
async function getEbayToken(env) {
  const cached = await env.KV.get("ebay_token", "json");
  if (cached && cached.exp > Date.now() + 60000) return cached.tok;
  const cred = btoa(env.EBAY_CLIENT_ID + ":" + env.EBAY_CLIENT_SECRET);
  const r = await fetch("https://api.ebay.com/identity/v1/oauth2/token", {
    method: "POST",
    headers: { Authorization: "Basic " + cred, "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=client_credentials&scope=" + encodeURIComponent("https://api.ebay.com/oauth/api_scope"),
  });
  if (!r.ok) throw new Error("ebay token " + r.status);
  const j = await r.json();
  const tok = j.access_token, ttl = j.expires_in || 7200;
  await env.KV.put("ebay_token", JSON.stringify({ tok, exp: Date.now() + ttl * 1000 }), { expirationTtl: ttl });
  return tok;
}
async function ebaySearch(env, q, opts) {
  const tok = await getEbayToken(env);
  const params = new URLSearchParams({ q, limit: "50" });
  if (opts.max) params.set("filter", "price:[.." + opts.max + "],priceCurrency:USD");
  if (opts.sort === "price") params.set("sort", "price");
  else if (opts.sort === "newest") params.set("sort", "newlyListed");
  const r = await fetch("https://api.ebay.com/buy/browse/v1/item_summary/search?" + params.toString(), {
    headers: {
      Authorization: "Bearer " + tok,
      "X-EBAY-C-MARKETPLACE-ID": "EBAY_US",
      "X-EBAY-C-ENDUSERCTX": "contextualLocation=country=US",
    },
  });
  if (!r.ok) throw new Error("ebay search " + r.status);
  const j = await r.json();
  return (j.itemSummaries || []).map((it) => ({
    id: "ebay:" + it.itemId,
    source: "eBay",
    title: it.title || "",
    price: it.price ? Number(it.price.value) : null,
    currency: it.price ? it.price.currency : "USD",
    condition: it.condition || "",
    url: it.itemWebUrl || "",
    image: (it.image && it.image.imageUrl) ||
      (it.thumbnailImages && it.thumbnailImages[0] && it.thumbnailImages[0].imageUrl) || "",
    posted: it.itemCreationDate || null,
  }));
}

/* ----------------------------- Craigslist (RSS, best-effort) ----------------------------- */
async function craigslistSearch(env, q, opts) {
  const region = env.CRAIGSLIST_REGION || "detroit";
  const u = "https://" + region + ".craigslist.org/search/sss?query=" +
    encodeURIComponent(q) + "&format=rss&sort=date" +
    "&search_distance=" + (env.CRAIGSLIST_DISTANCE || "100") +
    "&postal=" + (env.CRAIGSLIST_POSTAL || "48371");
  const r = await fetch(u, { headers: { "User-Agent": "Mozilla/5.0 (compatible; StopDown/1.0)" } });
  if (!r.ok) throw new Error("cl " + r.status);
  const xml = await r.text();
  const items = [];
  const re = /<item[\s\S]*?<\/item>|<item[\s\S]*?\/>/g;
  let m;
  while ((m = re.exec(xml)) && items.length < 60) {
    const b = m[0];
    const title = decodeXml((b.match(/<title>([\s\S]*?)<\/title>/) || [])[1] || "");
    let link = (b.match(/<link>([\s\S]*?)<\/link>/) || [])[1] ||
      (b.match(/rdf:about="([^"]+)"/) || [])[1] || "";
    link = decodeXml(link);
    const date = (b.match(/<dc:date>([\s\S]*?)<\/dc:date>/) || [])[1] || null;
    const pm = title.match(/\$[\d,]+/);
    const price = pm ? Number(pm[0].replace(/[$,]/g, "")) : null;
    if (!title || !link) continue;
    if (opts.max && price != null && price > opts.max) continue;
    items.push({
      id: "cl:" + link, source: "Craigslist", title,
      price, currency: "USD", condition: "", url: link, image: "", posted: date,
    });
  }
  return items;
}

/* ----------------------------- daily run ----------------------------- */
async function runDaily(env) {
  const saved = (await getSaved(env)).filter((s) => s.alert !== false);
  const newAlerts = [];
  for (const s of saved) {
    const sources = [];
    if (s.ebay !== false && env.EBAY_CLIENT_ID) sources.push("ebay");
    if (s.cl !== false) sources.push("craigslist");
    let res;
    try { res = await search(env, s.q, { max: num(s.max), exclude: s.exclude, sort: "newest" }, sources); }
    catch (e) { continue; }
    const items = res.items || [];
    const seenKey = "seen:" + s.id;
    const prior = await env.KV.get(seenKey, "json");
    const now = {};
    for (const it of items) now[it.id] = it.price;
    if (prior) {
      for (const it of items) {
        if (!(it.id in prior)) newAlerts.push(Object.assign({}, it, { q: s.q, searchId: s.id, kind: "new" }));
        else if (it.price != null && prior[it.id] != null && it.price < prior[it.id] * 0.95)
          newAlerts.push(Object.assign({}, it, { q: s.q, searchId: s.id, kind: "drop", was: prior[it.id] }));
      }
    }
    // first run: just set the baseline, don't flood alerts
    await env.KV.put(seenKey, JSON.stringify(now));
  }
  if (newAlerts.length) {
    const prev = (await env.KV.get("alerts", "json")) || [];
    await env.KV.put("alerts", JSON.stringify(newAlerts.concat(prev).slice(0, 200)));
    await sendEmail(env, newAlerts);
  }
  await env.KV.put("lastRun", new Date().toISOString());
}

async function sendEmail(env, alerts) {
  if (!env.RESEND_API_KEY) return;
  const settings = (await env.KV.get("settings", "json")) || {};
  if (!settings.emailOn || !settings.email) return;
  const rows = alerts.slice(0, 50).map((a) => {
    const kind = a.kind === "drop" ? "price drop from $" + a.was : "NEW";
    const price = a.price != null ? "$" + a.price : "—";
    return '<tr><td style="padding:6px 10px">' + esc(a.q) + '</td>' +
      '<td style="padding:6px 10px">' + esc(a.source) + '</td>' +
      '<td style="padding:6px 10px">' + price + " (" + kind + ")</td>" +
      '<td style="padding:6px 10px"><a href="' + esc(a.url) + '">' + esc((a.title || "").slice(0, 80)) + "</a></td></tr>";
  }).join("");
  const html = '<h2 style="font-family:Arial">Stop·Down — ' + alerts.length +
    " new find" + (alerts.length === 1 ? "" : "s") + "</h2>" +
    '<table style="border-collapse:collapse;font-family:Arial;font-size:14px" border="1">' + rows + "</table>";
  try {
    await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: "Bearer " + env.RESEND_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: "Stop·Down <onboarding@resend.dev>",
        to: [settings.email],
        subject: "Stop·Down: " + alerts.length + " new camera find" + (alerts.length === 1 ? "" : "s"),
        html,
      }),
    });
  } catch (e) { /* email is best-effort */ }
}
