#!/usr/bin/env python3
"""Build the full multi-page MRA Healthcare Canada site.
Emits: real per-page HTML files into /home/user/MRA-Files/health/site/
plus a single-file SPA preview (same content, JS page routing) for the artifact."""
import json, pathlib, re

P = json.load(open('/tmp/claude-0/-home-user-MRA-Files/2e72fe60-532f-5b36-9ca1-2dffa40dafd0/scratchpad/photos/photo-uris.json'))
OUT = pathlib.Path('/home/user/MRA-Files/health/site'); OUT.mkdir(exist_ok=True)
SPA = pathlib.Path('/tmp/claude-0/-home-user-MRA-Files/2e72fe60-532f-5b36-9ca1-2dffa40dafd0/scratchpad/mra-healthcare-site.html')

CSS = """
:root{--red:#D8482A;--red-dark:#B93A20;--cyan:#2FC4E4;--cyan-deep:#1BA9C9;--ink:#1B1B1E;
--char:#58595B;--paper:#FFFFFF;--mist:#F4F5F6;--line:#E4E6E8}
*{margin:0;padding:0;box-sizing:border-box}
html{scroll-behavior:smooth}
[id]{scroll-margin-top:90px}
body{font-family:'Segoe UI',system-ui,-apple-system,Roboto,'Helvetica Neue',Arial,sans-serif;color:var(--ink);background:var(--paper);line-height:1.62;-webkit-font-smoothing:antialiased}
img{max-width:100%}
a{color:inherit}
.wrap{max-width:1180px;margin:0 auto;padding:0 24px}
h1,h2,h3{line-height:1.12;text-wrap:balance}
.logo{display:flex;align-items:center;gap:14px;text-decoration:none}
.logo .mra{font-weight:900;font-size:28px;letter-spacing:-.5px;color:var(--red);line-height:.9}
.logo .sub{font-weight:400;font-size:9px;letter-spacing:.42em;color:var(--char);text-transform:uppercase;display:block;margin-top:2px}
.logo .bar{width:2px;height:32px;background:#C9CBCD}
.logo .tag{font-size:10px;line-height:1.35;letter-spacing:.14em;text-transform:uppercase;font-weight:600}
.logo .tag .t1{color:var(--red)}
.logo .tag .t2{color:var(--cyan-deep)}
header.site{position:sticky;top:0;z-index:50;background:rgba(255,255,255,.97);backdrop-filter:blur(8px);border-bottom:1px solid var(--line)}
.nav{display:flex;align-items:center;justify-content:space-between;height:76px;gap:18px}
.nav-links{display:flex;align-items:center;gap:26px;list-style:none}
.nav-links a{text-decoration:none;font-size:12px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--ink);padding:6px 0;border-bottom:2px solid transparent;white-space:nowrap}
.nav-links a:hover{border-bottom-color:var(--red)}
.nav-links a.on{color:var(--red);border-bottom-color:var(--red)}
.btn{display:inline-block;background:var(--red);color:#fff;text-decoration:none;font-weight:800;font-size:12.5px;letter-spacing:.12em;text-transform:uppercase;padding:13px 26px;border:0;border-radius:3px;cursor:pointer;text-align:center}
.btn:hover{background:var(--red-dark)}
.btn.ghost{background:transparent;color:#fff;box-shadow:inset 0 0 0 2px rgba(255,255,255,.85)}
.btn.ghost:hover{background:rgba(255,255,255,.12)}
.btn.dark{background:var(--ink)}
.btn.dark:hover{background:#000}
.menu-btn{display:none;background:none;border:0;cursor:pointer;padding:8px}
.menu-btn span{display:block;width:24px;height:3px;background:var(--ink);margin:5px 0;border-radius:2px}
/* page hero */
.phero{position:relative;background:var(--red);color:#fff;overflow:hidden}
.phero .ph-in{position:relative;z-index:2;padding:74px 0 66px}
.phero .kicker{font-size:11.5px;font-weight:700;letter-spacing:.28em;text-transform:uppercase;color:#FFD9CE;margin-bottom:14px}
.phero h1{font-size:clamp(32px,4.4vw,54px);font-weight:900;text-transform:uppercase;letter-spacing:-.5px;max-width:22ch}
.phero .lede{margin-top:16px;font-size:16.5px;color:#FFE9E3;max-width:64ch}
.phero.photo{background:var(--ink)}
.phero.photo .bg{position:absolute;inset:0;background-size:cover;background-position:center;opacity:.42}
.phero.photo .shade{position:absolute;inset:0;background:linear-gradient(90deg,rgba(20,20,23,.88) 25%,rgba(20,20,23,.45))}
.crumb{position:relative;z-index:2;font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:rgba(255,255,255,.65);padding-top:22px}
.crumb a{text-decoration:none}
.crumb a:hover{color:#fff}
/* sections */
section{padding:78px 0}
.eyebrow{display:inline-block;background:var(--red);color:#fff;font-size:11px;font-weight:800;letter-spacing:.24em;text-transform:uppercase;padding:6px 15px;margin-bottom:18px}
.eyebrow.cy{background:var(--cyan-deep)}
.h2{font-size:clamp(26px,3.2vw,40px);font-weight:900;text-transform:uppercase;letter-spacing:-.3px}
.lede{max-width:68ch;color:var(--char);font-size:16px;margin-top:14px}
.center{text-align:center}
.center .lede{margin-left:auto;margin-right:auto}
.mist{background:var(--mist)}
/* stat strip */
.stat-strip{background:var(--red-dark);color:#fff}
.stat-strip .row{display:grid;grid-template-columns:repeat(4,1fr)}
.stat{padding:20px 16px;text-align:center;border-left:1px solid rgba(255,255,255,.16)}
.stat:first-child{border-left:0}
.stat b{display:block;font-size:24px;font-weight:900;font-variant-numeric:tabular-nums}
.stat span{font-size:10.5px;letter-spacing:.16em;text-transform:uppercase;color:#FFD9CE}
/* pillars/cards */
.pillars{display:grid;grid-template-columns:repeat(3,1fr);gap:0}
.pillar{position:relative;min-height:320px;display:flex;align-items:flex-end;padding:26px;color:#fff;text-decoration:none;overflow:hidden}
.pillar .art{position:absolute;inset:0;background-size:cover;background-position:center;transition:transform .35s}
.pillar:hover .art{transform:scale(1.04)}
.pillar::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,rgba(20,20,22,.15) 20%,rgba(20,20,22,.87))}
.pillar>span:last-child{position:relative;z-index:2}
.pillar h3{font-size:19px;font-weight:900;text-transform:uppercase;letter-spacing:.05em;text-shadow:0 2px 10px rgba(0,0,0,.5)}
.pillar p{font-size:13px;color:#E8E9EA;margin-top:6px;max-width:36ch}
.pillar .more{display:inline-block;margin-top:12px;font-size:11.5px;font-weight:800;letter-spacing:.14em;text-transform:uppercase;color:var(--cyan)}
.cardgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:18px;margin-top:42px;text-align:left}
.card{background:#fff;border:1px solid var(--line);padding:26px 24px;border-top:4px solid var(--cyan)}
.card h3{font-size:16px;font-weight:800}
.card p{font-size:13.5px;color:var(--char);margin-top:8px}
.card .tag{display:inline-block;margin-top:14px;font-size:10.5px;font-weight:800;letter-spacing:.16em;text-transform:uppercase;color:var(--cyan-deep)}
/* package cards */
.pack-grid{display:grid;grid-template-columns:1fr 1fr;gap:26px;margin-top:42px;text-align:left}
.pack{border:1px solid var(--line);background:#fff}
.pack .phead{background:var(--cyan-deep);color:#fff;padding:20px 26px}
.pack.alt .phead{background:var(--char)}
.pack .phead h3{font-size:17px;font-weight:800;letter-spacing:.04em;text-transform:uppercase}
.pack .phead p{font-size:12.5px;color:rgba(255,255,255,.92);margin-top:4px}
.pack ul{list-style:none;padding:22px 26px}
.pack li{position:relative;padding:7px 0 7px 30px;font-size:14px;border-bottom:1px dashed var(--line)}
.pack li:last-child{border-bottom:0}
.pack li::before{content:"";position:absolute;left:2px;top:13px;width:14px;height:14px;border-radius:50%;background:var(--cyan-deep)}
.pack li::after{content:"";position:absolute;left:6.5px;top:16.5px;width:5px;height:8px;border:solid #fff;border-width:0 2px 2px 0;transform:rotate(42deg)}
.pack.alt li::before{background:var(--red)}
.pack li b{font-weight:700}
.pack li span{color:var(--char)}
.pack .subhead{padding:14px 26px 0;font-size:11.5px;font-weight:800;letter-spacing:.18em;text-transform:uppercase;color:var(--red)}
/* steps */
.steps{display:grid;grid-template-columns:repeat(3,1fr);gap:40px;margin-top:40px;text-align:left}
.step .num{font-size:72px;font-weight:900;line-height:.8;color:var(--red)}
.step h3{font-size:14.5px;font-weight:800;letter-spacing:.13em;text-transform:uppercase;margin:12px 0 8px}
.step p{font-size:14px;color:var(--char)}
/* photo band */
.photo-band{position:relative}
.photo-band img{display:block;width:100%;height:clamp(280px,44vw,520px);object-fit:cover}
.photo-band .pb-cap{position:absolute;left:0;right:0;bottom:0;background:linear-gradient(180deg,transparent,rgba(15,15,17,.82));color:#fff;padding:44px 24px 16px;font-size:12.5px;letter-spacing:.08em;text-transform:uppercase;text-align:center}
/* split rows */
.split{display:grid;grid-template-columns:1fr 1fr;gap:56px;align-items:center}
.split img{width:100%;border-radius:6px;box-shadow:0 24px 50px -28px rgba(20,25,35,.4)}
.split h2{font-size:clamp(24px,2.8vw,34px);font-weight:900;text-transform:uppercase}
.split p{color:var(--char);margin-top:12px;font-size:15px}
.split ul{margin:16px 0 0 2px;list-style:none}
.split li{padding:6px 0 6px 28px;position:relative;font-size:14.5px}
.split li::before{content:"✓";position:absolute;left:2px;color:var(--red);font-weight:900}
/* stats cards */
.why-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin-top:40px;text-align:left}
.why-card{background:#fff;border:1px solid var(--line);border-radius:8px;padding:26px 24px}
.why-card .big{font-size:34px;font-weight:900;color:var(--red);letter-spacing:-1px;font-variant-numeric:tabular-nums}
.why-card h3{font-size:15px;margin-top:8px}
.why-card p{font-size:13px;color:var(--char);margin-top:8px}
.why-card .src{display:block;font-size:10.5px;color:#9AA0A6;margin-top:10px}
/* case cards */
.case{background:#fff;border:1px solid var(--line);border-left:5px solid var(--cyan-deep);padding:24px 26px;margin:14px 0;text-align:left}
.case .where{font-size:10.5px;font-weight:800;letter-spacing:.18em;text-transform:uppercase;color:var(--cyan-deep)}
.case h3{margin:6px 0 8px;font-size:16.5px}
.case p{font-size:14px;color:#33383F}
/* orgs */
.orgs{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;margin-top:36px}
.org{border:1px solid var(--line);padding:24px 20px;text-align:center;font-weight:700;font-size:14.5px;color:var(--char);background:#fff}
.org small{display:block;margin-top:6px;font-size:10.5px;letter-spacing:.16em;text-transform:uppercase;color:#9A9C9E;font-weight:600}
.plogos{margin-top:26px;display:flex;flex-wrap:wrap;justify-content:center;gap:12px 42px;align-items:center}
.plogos span{font-size:19px;font-weight:800;color:#B9BBBD}
/* faq */
.faq details{border-top:1px solid var(--line);padding:2px 0;text-align:left}
.faq details:last-child{border-bottom:1px solid var(--line)}
.faq summary{cursor:pointer;font-weight:700;font-size:15.5px;padding:16px 34px 16px 4px;list-style:none;position:relative}
.faq summary::-webkit-details-marker{display:none}
.faq summary::after{content:"+";position:absolute;right:8px;top:12px;font-size:23px;color:var(--red);font-weight:400}
.faq details[open] summary::after{content:"–"}
.faq .a{padding:0 4px 18px;color:var(--char);font-size:14px;max-width:75ch}
/* cta band */
.cta-band{background:linear-gradient(140deg,#1B1B1E,#2A2B2E);color:#fff}
.cta-band .inner{display:grid;grid-template-columns:1.2fr .8fr;gap:40px;align-items:center;padding:64px 0}
.cta-band h2{font-size:clamp(24px,3vw,38px);font-weight:900;text-transform:uppercase}
.cta-band p{color:#C9CBCD;margin-top:10px;max-width:52ch}
.cta-band .phone{display:block;font-size:28px;font-weight:900;color:var(--cyan);text-decoration:none;margin-top:16px}
.cta-band .actions{display:flex;flex-direction:column;gap:12px;justify-self:end;min-width:260px}
/* form */
.qform{background:#fff;color:var(--ink);padding:32px;border-radius:6px;border:1px solid var(--line)}
.qform h3{font-size:14.5px;font-weight:800;letter-spacing:.14em;text-transform:uppercase;margin-bottom:16px}
.qform .frow{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.qform label{display:block;font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--char);margin:12px 0 5px}
.qform input,.qform select,.qform textarea{width:100%;padding:11px 12px;border:1px solid #CFD1D3;border-radius:3px;font:inherit;font-size:14px;background:#fff;color:var(--ink)}
.qform input:focus,.qform select:focus,.qform textarea:focus{outline:2px solid var(--cyan);outline-offset:1px}
.qform .btn{width:100%;margin-top:18px}
/* gallery */
.gal{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px;margin-top:40px;text-align:left}
.gal figure{margin:0;background:#fff;border:1px solid var(--line);border-radius:6px;overflow:hidden}
.gal img{display:block;width:100%;height:220px;object-fit:cover;transition:transform .3s}
.gal figure:hover img{transform:scale(1.04)}
.gal figcaption{padding:12px 16px;font-size:12.5px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--char)}
/* prov grid */
.prov-grid{margin-top:36px;display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;text-align:left}
.prov{border:1px solid var(--line);border-left:4px solid var(--red);background:var(--mist);padding:11px 13px;font-size:13px;font-weight:700}
.prov small{display:block;font-weight:400;color:var(--char)}
footer.site{background:#0F0F11;color:#8E9092;padding:52px 0 36px;font-size:13px}
.f-grid{display:grid;grid-template-columns:2fr 1fr 1fr 1fr;gap:38px}
footer.site .logo .sub{color:#8E9092}
footer.site .logo .bar{background:#3A3B3E}
footer.site h4{color:#fff;font-size:11px;letter-spacing:.2em;text-transform:uppercase;margin-bottom:13px}
footer.site ul{list-style:none}
footer.site li{margin:7px 0}
footer.site a{text-decoration:none}
footer.site a:hover{color:#fff}
.f-bottom{border-top:1px solid #232427;margin-top:40px;padding-top:20px;display:flex;justify-content:space-between;gap:18px;flex-wrap:wrap;font-size:11.5px}
.leaf{color:var(--red)}
@media (max-width:960px){
  .pillars,.steps,.why-grid{grid-template-columns:1fr}
  .pack-grid,.split,.cta-band .inner{grid-template-columns:1fr}
  .cta-band .actions{justify-self:start}
  .stat-strip .row{grid-template-columns:repeat(2,1fr)}
  .stat{border-left:0;border-top:1px solid rgba(255,255,255,.16)}
  .f-grid{grid-template-columns:1fr 1fr}
  .nav-links{display:none;position:absolute;top:76px;left:0;right:0;background:#fff;flex-direction:column;gap:0;padding:8px 24px 18px;border-bottom:1px solid var(--line)}
  .nav-links.open{display:flex}
  .nav-links li{width:100%}
  .nav-links a{display:block;padding:12px 0}
  .nav .btn{display:none}
  .menu-btn{display:block}
}
@media (prefers-reduced-motion:no-preference){
  .reveal{opacity:0;transform:translateY(16px);transition:opacity .55s ease,transform .55s ease}
  .reveal.in{opacity:1;transform:none}
}
"""

LOGO = """<a class="logo" href="index.html">
  <span><span class="mra">MRA</span><span class="sub">Healthcare</span></span>
  <span class="bar"></span>
  <span class="tag"><span class="t1">Mobile Medical</span><br><span class="t2">Canada</span></span>
</a>"""

def header(active):
    items = [('index.html','Home'),('services.html','Services'),('units.html','Units & Programs'),
             ('why-mobile.html','Why Mobile'),('about.html','About Us'),('contact.html','Contact')]
    ON = ' class="on"'
    lis = '\n'.join(f'<li><a href="{h}"{ON if h==active else ""}>{t}</a></li>' for h,t in items)
    return f"""<header class="site"><div class="wrap nav">
  {LOGO}
  <ul class="nav-links" id="navLinks">
{lis}
  </ul>
  <a class="btn" href="contact.html">Get a Quote</a>
  <button class="menu-btn" aria-label="Open menu" onclick="document.getElementById('navLinks').classList.toggle('open')"><span></span><span></span><span></span></button>
</div></header>"""

FOOTER = f"""<footer class="site"><div class="wrap f-grid">
  <div>
    {LOGO}
    <p style="margin-top:16px;max-width:40ch">Mobile healthcare environments and logistical services that extend
    clinical capacity across Canada — since 1989.</p>
  </div>
  <div><h4>Site</h4><ul>
    <li><a href="services.html">Services</a></li>
    <li><a href="units.html">Units &amp; Programs</a></li>
    <li><a href="why-mobile.html">Why Mobile</a></li>
    <li><a href="about.html">About Us</a></li>
  </ul></div>
  <div><h4>Services</h4><ul>
    <li><a href="services.html#essential">Essential Maintenance</a></li>
    <li><a href="services.html#ondemand">On-Demand &amp; Operations</a></li>
    <li><a href="services.html#logistics">À La Carte Logistics</a></li>
    <li><a href="units.html">Equipment Lease</a></li>
  </ul></div>
  <div><h4>Contact</h4><ul>
    <li><a href="tel:1-800-676-3520">1.800.676.3520</a></li>
    <li><a href="contact.html">Request a quote</a></li>
    <li>mrahealthcare.ca</li>
  </ul></div>
</div>
<div class="wrap f-bottom">
  <span>© 2026 MRA Healthcare · Mobile Medical Solutions</span>
  <span>Proudly serving Canada <span class="leaf">🍁</span> coast to coast to coast · Service en français disponible</span>
</div></footer>"""

CTA = """<div class="cta-band"><div class="wrap inner">
  <div>
    <h2>Deliver care anywhere.<br>Improve access everywhere.</h2>
    <p>One call gets you real solutions and a clear, itemized quote — unit, transport, maintenance and operations.</p>
    <a class="phone" href="tel:1-800-676-3520">1.800.676.3520</a>
  </div>
  <div class="actions">
    <a class="btn" href="contact.html">Request a Quote</a>
    <a class="btn ghost" href="services.html">Explore Service Packages</a>
  </div>
</div></div>"""

def phero(kicker, title, lede, photo=None, crumb=None):
    c = f'<div class="wrap crumb"><a href="index.html">Home</a> / {crumb}</div>' if crumb else ''
    if photo:
        return f"""<div class="phero photo"><div class="bg" style="background-image:url({photo})"></div><div class="shade"></div>{c}
<div class="wrap ph-in"><div class="kicker">{kicker}</div><h1>{title}</h1><p class="lede">{lede}</p></div></div>"""
    return f"""<div class="phero">{c}<div class="wrap ph-in"><div class="kicker">{kicker}</div><h1>{title}</h1><p class="lede">{lede}</p></div></div>"""

PAGES = {}

# ------------------------------------------------ HOME
PAGES['index.html'] = ('MRA Healthcare — Mobile Medical Solutions Canada', f"""
<div class="phero photo"><div class="bg" style="background-image:url({P['hcimg']});background-position:center 60%;opacity:.5"></div><div class="shade"></div>
  <div class="wrap ph-in" style="padding:96px 0 88px">
    <div class="kicker">🍁 Mobile Medical Solutions · Coast to Coast to Coast</div>
    <h1 style="max-width:16ch">Supporting Mobile Health Canada</h1>
    <p class="lede">Creating reliability and maximizing treatment time. MRA provides mobile healthcare environments
    and logistical services that extend clinical capacity and bring care directly to underserved communities.</p>
    <div style="margin-top:30px;display:flex;gap:14px;flex-wrap:wrap">
      <a class="btn" style="background:#fff;color:var(--red)" href="contact.html">Get a Quote</a>
      <a class="btn ghost" href="services.html">Our Services</a>
    </div>
    <div style="margin-top:14px;font-size:12px;color:#FFD9CE;font-style:italic">Des soins mobiles, d’un océan à l’autre.</div>
  </div>
</div>
<div class="stat-strip"><div class="wrap row">
  <div class="stat"><b>1989</b><span>Serving healthcare since</span></div>
  <div class="stat"><b>10+3</b><span>Provinces &amp; territories served</span></div>
  <div class="stat"><b>24/7</b><span>On-demand support</span></div>
  <div class="stat"><b>100%</b><span>Turn-key operations</span></div>
</div></div>

<div class="pillars">
  <a class="pillar reveal" href="services.html#logistics">
    <span class="art" style="background-image:url({P['fleet_driver']})"></span>
    <span><h3>À La Carte Logistics</h3><p>CDL-A drivers, transport prep, permits, fuel, insurance and site placement.</p><span class="more">See logistics →</span></span>
  </a>
  <a class="pillar reveal" href="services.html#essential">
    <span class="art" style="background-image:url({P['mechanic']})"></span>
    <span><h3>Preventative Maintenance</h3><p>Semi-annual inspections across every system — generator to hydraulics to DOT.</p><span class="more">See maintenance →</span></span>
  </a>
  <a class="pillar reveal" href="units.html">
    <span class="art" style="background-image:url({P['galleri']})"></span>
    <span><h3>Equipment Lease &amp; Operations</h3><p>Fully customizable medical trailers with operations sized to your mandate.</p><span class="more">See units →</span></span>
  </a>
</div>

<section class="center">
  <div class="wrap">
    <span class="eyebrow">Who We Are</span>
    <h2 class="h2">Servicing All of Canada <span class="leaf">🍁</span></h2>
    <p class="lede">Since 1989, MRA has been providing the healthcare industry with turn-key solutions for a variety of
    mobile applications. Our fully customizable medical trailers go directly to the location of your choice —
    eliminating the inconvenience of travel for your patients, without new provincial infrastructure.</p>
    <div style="margin-top:26px"><a class="btn dark" href="about.html">More About MRA</a></div>
  </div>
</section>

<section class="mist center">
  <div class="wrap">
    <span class="eyebrow cy">Why Mobile</span>
    <h2 class="h2">Canada's care gap is a distance problem.</h2>
    <div class="why-grid">
      <div class="why-card reveal"><div class="big">6.5M+</div><h3>Canadians without a regular primary-care provider</h3><p>Mobile outreach units extend clinician reach into communities with no permanent clinic.</p></div>
      <div class="why-card reveal"><div class="big">1 in 5</div><h3>Canadians live in rural &amp; remote communities</h3><p>Far from screening, diagnostics and specialist care — the gap mobile programs close.</p></div>
      <div class="why-card reveal"><div class="big">30 wks</div><h3>median wait, referral to treatment</h3><p>Mobile diagnostic capacity helps work down backlogs without waiting years for new buildings.</p></div>
    </div>
    <div style="margin-top:28px"><a class="btn" href="why-mobile.html">Why Mobile Works in Canada</a></div>
  </div>
</section>

<section class="center">
  <div class="wrap">
    <span class="eyebrow">How It Works</span>
    <h2 class="h2">Easy As 1 · 2 · 3</h2>
    <div class="steps">
      <div class="step reveal"><div class="num">1</div><h3>Call</h3><p>Speak with a service representative about your
      challenges — no obligation, straight answers. The first step is often the hardest.</p></div>
      <div class="step reveal"><div class="num">2</div><h3>Choose Your Service Pack</h3><p>Pick from our logistical
      services or custom-design a lease with an operational program. Big or small, we'll shape the right package.</p></div>
      <div class="step reveal"><div class="num">3</div><h3>Get a Quote</h3><p>Clear, itemized pricing for the unit,
      transport, maintenance and operations — built for health-system budgeting and approvals.</p></div>
    </div>
  </div>
</section>

<div class="photo-band">
  <img src="{P['facility']}" alt="A mobile clinic returns to the MRA facility for scheduled maintenance">
  <div class="pb-cap">Home base — a mobile clinic in for scheduled service before its next Canadian deployment</div>
</div>

<section class="center">
  <div class="wrap">
    <span class="eyebrow">Trusted Systems</span>
    <h2 class="h2">Trusted by healthcare organizations across Canada</h2>
    <div class="orgs">
      <div class="org reveal">Saskatchewan Health Authority<small>Saskatchewan</small></div>
      <div class="org reveal">Winnipeg Regional Health Authority<small>Manitoba</small></div>
      <div class="org reveal">Essex-Windsor EMS<small>Ontario</small></div>
      <div class="org reveal">Thunder Bay Regional Health Sciences Centre<small>Ontario</small></div>
    </div>
    <div class="plogos"><span>ABB</span><span>Boston Scientific</span><span>Beazley</span><span>Hyperfine</span><span>Baxter</span></div>
  </div>
</section>
{CTA}
""")

# ------------------------------------------------ SERVICES
PAGES['services.html'] = ('Services — MRA Healthcare Canada', phero(
 "Bulletproof Logistical Services",
 "Maintenance, repair &amp; operations for mobile medical units",
 "Already own a medical trailer? MRA keeps it reliable, compliant and on-site. Start with the Essential Package; layer on-demand repair and full vehicle operations on top when your program needs the road handled too.",
 photo=P['mechanic'], crumb="Services") + f"""
<section>
  <div class="wrap center">
    <span class="eyebrow">Our Solution</span>
    <h2 class="h2">Two packages. One reliable unit.</h2>
    <p class="lede">Your clinical team should never have to think about tires, generators or permits — treatment time
    should never be lost to downtime.</p>
    <div class="pack-grid">
      <div class="pack reveal" id="essential">
        <div class="phead"><h3>Essential Maintenance Package</h3><p>Semi-annual preventative maintenance inspections — every system reviewed and documented</p></div>
        <ul>
          <li><b>Tires</b> <span>— proper inflation, cuts, tread depth and wear</span></li>
          <li><b>Generator inspection</b> <span>— filter, oil, plugs, belts and more</span></li>
          <li><b>Electrical system test</b> <span>— shore power inspection</span></li>
          <li><b>Axle bearings</b> <span>— wear and fluid levels</span></li>
          <li><b>Trailer HVAC systems</b> <span>— filters, coil cleaning, freon &amp; pressure levels</span></li>
          <li><b>Plumbing &amp; water systems</b> <span>— pumps, drainage, holding tanks, filtration</span></li>
          <li><b>Brakes</b> <span>— pads, discs, drums, lines and all associated components</span></li>
          <li><b>Hydraulics</b> <span>— operation, leaks and fluid levels</span></li>
          <li><b>Slide rails</b> <span>— cleaned &amp; maintained per manufacturer specs</span></li>
          <li><b>Rubber seals</b> <span>— expandables, door frames, belly boxes, windows</span></li>
          <li><b>Annual DOT inspection</b> <span>— of the trailer, documented</span></li>
        </ul>
      </div>
      <div class="pack alt reveal" id="ondemand">
        <div class="phead"><h3>On-Demand Service &amp; Operational Package</h3><p>Pairs with the Essential Package — repairs on demand plus full turn-key vehicle operations</p></div>
        <div class="subhead">On-Demand Repair Services</div>
        <ul style="padding-bottom:6px">
          <li><b>HVAC system</b></li>
          <li><b>Electrical systems</b></li>
          <li><b>Plumbing systems</b></li>
          <li><b>Cabinetry, furnishings &amp; flooring</b></li>
        </ul>
        <div class="subhead">Operational Services</div>
        <ul>
          <li><b>MRA CDL-A driver</b> <span>+ all associated driver expenses (lodging, per diem)</span></li>
          <li><b>Fuel for the vehicle</b></li>
          <li><b>Insurance</b></li>
          <li><b>Permit management</b> <span>— across jurisdictions</span></li>
          <li><b>Appropriate tow vehicle</b> <span>— tractor etc., if required</span></li>
          <li><b>Storage between locations</b> <span>— for multi-day transport</span></li>
          <li><b>Structural &amp; mechanical inspection</b> <span>+ full transport prep before departure</span></li>
          <li><b>Delivery &amp; placement</b> <span>— at the host site location</span></li>
        </ul>
      </div>
    </div>
  </div>
</section>

<section class="mist" id="logistics">
  <div class="wrap split">
    <div class="reveal">
      <span class="eyebrow">À La Carte Logistics</span>
      <h2>Book exactly the legs you need.</h2>
      <p>Not every program needs the full package. Our logistics services are available à la carte — a single
      inter-provincial move, seasonal storage, or a driver for a six-city screening tour.</p>
      <ul>
        <li>Inter-provincial transport with MRA CDL-A drivers</li>
        <li>Permits, insurance and fuel handled end-to-end</li>
        <li>Full transport prep + structural inspection before departure</li>
        <li>Delivery, placement and set-up at the host site</li>
        <li>Storage between locations on multi-stop tours</li>
      </ul>
      <div style="margin-top:22px"><a class="btn" href="contact.html">Plan a Move</a></div>
    </div>
    <img class="reveal" src="{P['fleet_driver']}" alt="MRA driver with the transport fleet">
  </div>
</section>

<section class="center">
  <div class="wrap">
    <span class="eyebrow cy">Questions</span>
    <h2 class="h2">Frequently asked</h2>
    <div class="faq" style="max-width:860px;margin:26px auto 0">
      <details><summary>Do you service units you didn't build?</summary><div class="a">Yes. Our maintenance and repair
      packages cover mobile medical trailers and coaches of any make — chassis, generator, HVAC, plumbing, electrical,
      slide systems and seals, fully documented.</div></details>
      <details><summary>Can you move a unit between provinces?</summary><div class="a">That's our specialty. The
      operational package includes an MRA CDL-A driver, the right tow vehicle, fuel, insurance, permit management
      across jurisdictions, storage between locations, full transport prep and placement at the host site.</div></details>
      <details><summary>How often are maintenance inspections?</summary><div class="a">The Essential Package reviews
      every system semi-annually, plus the annual DOT inspection of the trailer — with documentation your compliance
      team can file.</div></details>
      <details><summary>We don't own a unit — can we still run a mobile program?</summary><div class="a">Yes — see
      <a href="units.html">Units &amp; Programs</a>. We lease fully customizable medical trailers with an operational
      program sized to your mandate.</div></details>
      <details><summary>What does a quote look like?</summary><div class="a">Itemized: the unit (if leased), transport
      legs, maintenance schedule and operations — line by line, built for health-system budgeting and approvals.</div></details>
    </div>
  </div>
</section>
{CTA}
""")

# ------------------------------------------------ UNITS & PROGRAMS
PAGES['units.html'] = ('Units & Programs — MRA Healthcare Canada', phero(
 "Equipment Lease &amp; Operations",
 "One platform. Every program.",
 "Fully customizable medical trailers, leased with an operational program sized to your mandate. Your clinicians walk into a working clinic — we own every mechanical and logistical detail behind it.",
 photo=P['galleri'], crumb="Units &amp; Programs") + f"""
<section class="center">
  <div class="wrap">
    <span class="eyebrow">Programs</span>
    <h2 class="h2">What runs on our wheels</h2>
    <p class="lede">If it can be delivered in a clinical room, it can usually be delivered on wheels — with the
    reliability of a purpose-built clinical environment.</p>
    <div class="cardgrid">
      <div class="card reveal"><h3>Diagnostic Imaging</h3><p>Mobile MRI, CT and X-ray suites that add imaging capacity
      where waitlists are longest — capacity that arrives in months, not years.</p><span class="tag">Backlog relief</span></div>
      <div class="card reveal"><h3>Screening &amp; Prevention</h3><p>Mammography, cancer screening and community health
      clinics delivered directly to rural and remote populations.</p><span class="tag">Earlier detection</span></div>
      <div class="card reveal"><h3>Primary &amp; Urgent Care</h3><p>Exam-room environments for family-practice outreach,
      EMS surge support and community paramedicine.</p><span class="tag">Access restored</span></div>
      <div class="card reveal"><h3>Mental Health &amp; Addictions</h3><p>Discreet, purpose-built spaces for counselling,
      harm reduction and addiction-medicine outreach.</p><span class="tag">Care without stigma</span></div>
      <div class="card reveal"><h3>Dental &amp; Vision</h3><p>Fully plumbed operatory and exam layouts for school,
      workplace and community programs.</p><span class="tag">Whole-person health</span></div>
      <div class="card reveal"><h3>Blood, Vaccines &amp; Public Health</h3><p>High-throughput collection and
      immunization layouts proven in large-scale campaigns.</p><span class="tag">Population scale</span></div>
    </div>
  </div>
</section>

<section class="mist">
  <div class="wrap split">
    <img class="reveal" src="{P['teal']}" alt="An MRA healthcare unit deployed on site with awning and entry ramp">
    <div class="reveal">
      <span class="eyebrow cy">Built for Clinics</span>
      <h2>A clinical environment, not a truck with a desk.</h2>
      <p>Every unit is configured to the program it serves — layouts, power, water and access are designed around the
      patient visit.</p>
      <ul>
        <li>Reception and private dressing / consult areas</li>
        <li>Exam and procedure rooms built to clinical spec</li>
        <li>Wheelchair lifts and accessible entries</li>
        <li>Expandable slide-outs for interior space on site</li>
        <li>Generator + shore power, HVAC, plumbing and holding tanks</li>
        <li>Graphics-wrapped exteriors for program visibility</li>
      </ul>
    </div>
  </div>
</section>

<section>
  <div class="wrap split">
    <div class="reveal">
      <span class="eyebrow">Lease + Operate</span>
      <h2>Scale up, scale down, stay treated.</h2>
      <p>Leasing means your capital goes to care, not depreciation — and MRA's operational program keeps the unit
      compliant, maintained and where it needs to be.</p>
      <ul>
        <li>Custom clinical layouts, delivered ready to treat</li>
        <li>Operated &amp; supported by MRA — driver, permits, fuel, insurance</li>
        <li>Semi-annual preventative maintenance + annual DOT inspection</li>
        <li>On-demand repair so treatment time is never lost</li>
        <li>Seasonal and multi-year terms</li>
      </ul>
      <div style="margin-top:22px"><a class="btn" href="contact.html">Design My Program</a></div>
    </div>
    <img class="reveal" src="{P['baxter']}" alt="A deployed MRA-supported mobile unit welcoming visitors">
  </div>
</section>

<div class="photo-band">
  <img src="{P['or_wide']}" alt="Inside an MRA-built mobile surgical suite">
  <div class="pb-cap">Inside an MRA-built mobile surgical training suite — full OR environment, on wheels</div>
</div>

<section class="center">
  <div class="wrap">
    <span class="eyebrow">Recent Builds</span>
    <h2 class="h2">Built by MRA</h2>
    <p class="lede">A few of the mobile clinical environments we've designed, built and kept on the road.</p>
    <div class="gal">
      <figure><img src="{P['deployed']}" alt="Deployed mobile healthcare unit with stairs and awning"><figcaption>Connected-care demo unit, deployed</figcaption></figure>
      <figure><img src="{P['or_table']}" alt="Surgical table inside a mobile OR suite"><figcaption>Mobile surgical suite</figcaption></figure>
      <figure><img src="{P['touch']}" alt="Clinician using a touchscreen in a mobile unit"><figcaption>Interactive clinical training</figcaption></figure>
      <figure><img src="{P['scans']}" alt="Diagnostic imaging displays in a mobile unit"><figcaption>Mobile diagnostics &amp; imaging</figcaption></figure>
      <figure><img src="{P['darkunit']}" alt="Expandable premium mobile unit"><figcaption>Expandable platform</figcaption></figure>
      <figure><img src="{P['facility']}" alt="Mobile clinic at the MRA facility"><figcaption>In for service at home base</figcaption></figure>
    </div>
  </div>
</section>
{CTA}
""")

# ------------------------------------------------ WHY MOBILE
PAGES['why-mobile.html'] = ('Why Mobile — MRA Healthcare Canada', phero(
 "Why Mobile · Canada",
 "The fastest new clinic in Canada arrives on wheels.",
 "Canada doesn't have a care shortage everywhere — it has a care distance problem. Mobile clinical units close that distance, and Canadian health systems are already proving it at provincial scale.",
 crumb="Why Mobile") + f"""
<section class="center">
  <div class="wrap">
    <span class="eyebrow">The Need</span>
    <h2 class="h2">Four forces pushing care onto wheels</h2>
    <div class="why-grid" style="grid-template-columns:repeat(auto-fit,minmax(230px,1fr))">
      <div class="why-card reveal"><div class="big">68%</div><h3>of hip replacements met the 6-month benchmark in 2024</h3>
      <p>Surgical backlogs persist below pre-pandemic levels even as volumes rise — demand is outpacing fixed capacity.</p><span class="src">CIHI, 2025 release</span></div>
      <div class="why-card reveal"><div class="big">+15 days</div><h3>growth in median MRI wait, 2019–2024</h3>
      <p>Even though scan volumes rose 16%. Mobile MRI/CT adds capacity in months, not construction years.</p><span class="src">CIHI, 2025 release</span></div>
      <div class="why-card reveal"><div class="big">1 in 5</div><h3>Ontario hospitals with ERs saw temporary closures, 2022–2024</h3>
      <p>Overwhelmingly rural. Mobile units help concentrate scarce staff where the patients are.</p><span class="src">CBC News analysis, Dec 2024</span></div>
      <div class="why-card reveal"><div class="big">~3×</div><h3>per-capita health spend in the territories vs national average</h3>
      <p>Much of it on moving patients to care. Mobile programs move the care instead.</p><span class="src">CIHI 2024 · peer-reviewed studies</span></div>
    </div>
  </div>
</section>

<div class="photo-band">
  <img src="{P['scans']}" alt="Diagnostic imaging displays inside a mobile unit">
  <div class="pb-cap">Hospital-grade diagnostics, anywhere the road goes</div>
</div>

<section class="mist">
  <div class="wrap">
    <div class="center">
      <span class="eyebrow cy">Proven in Canada</span>
      <h2 class="h2">Provinces already run mobile health at scale</h2>
      <p class="lede">This isn't a pilot-project idea. Mobile clinical delivery is load-bearing infrastructure in
      Canadian healthcare today.</p>
    </div>
    <div style="max-width:900px;margin:30px auto 0">
      <div class="case reveal"><div class="where">British Columbia</div><h3>~10% of ALL screening mammograms in BC happen on mobile coaches</h3>
      <p>BC Cancer's three mobile mammography units visit 170+ rural communities — including 40+ First Nations
      communities — every year.</p></div>
      <div class="case reveal"><div class="where">British Columbia</div><h3>Mobile MRI &amp; CT trailers booked six months out</h3>
      <p>The provincial health authority rotates two mobile imaging trailers among hospitals on a reservation system —
      demand outstrips the fleet, and sites plan deployments half a year ahead.</p></div>
      <div class="case reveal"><div class="where">Alberta</div><h3>120+ rural &amp; Indigenous communities screened every year — since 1991</h3>
      <p>Alberta's Screen Test program operates 53-foot mobile mammography trailers, with two brand-new
      foundation-funded units delivered in 2025. Over 500,000 mammograms and counting.</p></div>
      <div class="case reveal"><div class="where">Saskatchewan</div><h3>Health authorities already lease mobile units</h3>
      <p>The Saskatchewan Health Authority leases the Regina General Hospital's mobile MRI from a third-party,
      Indigenous-owned provider — the exact partnership model MRA offers Canadian health systems.</p></div>
      <div class="case reveal"><div class="where">British Columbia</div><h3>A 24/7-ready "hospital on wheels"</h3>
      <p>BC keeps a Mobile Medical Unit deployment-ready around the clock for emergencies, facility backstops and
      clinical education — proof that standby mobile capacity is worth funding.</p></div>
    </div>
  </div>
</section>

<section class="center">
  <div class="wrap">
    <span class="eyebrow">The MRA Fit</span>
    <h2 class="h2">Keep the clinical program. Hand us everything else.</h2>
    <p class="lede">Health authorities and foundations own the mission; MRA handles the unit, the road, the compliance
    and the uptime — lease, transport, maintenance and full operations from one partner, since 1989.</p>
    <div class="steps" style="text-align:left;max-width:980px;margin-left:auto;margin-right:auto">
      <div class="step reveal"><div class="num">›</div><h3>For health authorities</h3><p>Surge imaging capacity,
      screening tours and outreach programs — leased and operated, or logistics-only for units you own.</p></div>
      <div class="step reveal"><div class="num">›</div><h3>For foundations</h3><p>Turn a capital gift into a working
      clinical program: we design, build, deliver and maintain the unit your donors fund.</p></div>
      <div class="step reveal"><div class="num">›</div><h3>For communities &amp; EMS</h3><p>Community paramedicine,
      vaccination and public-health platforms placed where they're needed, kept bulletproof year-round.</p></div>
    </div>
  </div>
</section>
{CTA}
""")

# ------------------------------------------------ ABOUT
PAGES['about.html'] = ('About Us — MRA Healthcare Canada', phero(
 "About MRA Healthcare",
 "Reliability, delivered — since 1989.",
 "MRA provides mobile healthcare environments and logistical services that extend clinical capacity and bring services directly to underserved communities across Canada.",
 photo=P['facility'], crumb="About Us") + f"""
<section>
  <div class="wrap split">
    <div class="reveal">
      <span class="eyebrow">Our Story</span>
      <h2>Thirty-seven years on the road with healthcare.</h2>
      <p>Since 1989, MRA has provided the healthcare industry with turn-key solutions for a variety of mobile
      applications — design, build, transport, maintenance and full operations.</p>
      <p>With increasing pressure on healthcare access and delivery timelines, mobile solutions provide a flexible,
      scalable way to extend care without new provincial infrastructure. That's the problem we solve every day:
      creating reliability and maximizing treatment time, so clinical teams can focus on patients.</p>
      <p>Our Canadian operation is dedicated to this market — its health systems, its distances, its communities.
      <i>Des soins mobiles, d'un océan à l'autre.</i></p>
    </div>
    <img class="reveal" src="{P['hero_pink']}" alt="MRA technician operating the lift on a mobile screening unit" style="max-height:480px;object-fit:cover;object-position:center 25%">
  </div>
</section>

<section class="mist center">
  <div class="wrap">
    <span class="eyebrow cy">What We Stand For</span>
    <h2 class="h2">Creating reliability. Maximizing treatment time.</h2>
    <div class="cardgrid" style="grid-template-columns:repeat(auto-fit,minmax(240px,1fr))">
      <div class="card reveal"><h3>Bulletproof, by design</h3><p>Semi-annual multi-point inspections, documented DOT
      compliance and on-demand repair — downtime is the enemy of treatment time.</p></div>
      <div class="card reveal"><h3>Turn-key, truly</h3><p>Driver, fuel, permits, insurance, storage, placement. When we
      say we handle the road, we mean all of it.</p></div>
      <div class="card reveal"><h3>Canada-first</h3><p>Built around Canadian health systems: provincial procurement,
      foundation funding models, northern distances and bilingual service.</p></div>
    </div>
  </div>
</section>

<section class="center">
  <div class="wrap">
    <span class="eyebrow">Trusted Systems</span>
    <h2 class="h2">The company we keep</h2>
    <div class="orgs">
      <div class="org reveal">Saskatchewan Health Authority<small>Saskatchewan</small></div>
      <div class="org reveal">Winnipeg Regional Health Authority<small>Manitoba</small></div>
      <div class="org reveal">Essex-Windsor EMS<small>Ontario</small></div>
      <div class="org reveal">Thunder Bay Regional Health Sciences Centre<small>Ontario</small></div>
    </div>
    <div class="plogos"><span>ABB</span><span>Boston Scientific</span><span>Beazley</span><span>Hyperfine</span><span>Baxter</span></div>
  </div>
</section>

<section class="mist center">
  <div class="wrap">
    <span class="eyebrow">Coverage</span>
    <h2 class="h2">Coast to coast to coast <span class="leaf">🍁</span></h2>
    <div class="prov-grid">
      <div class="prov">BC <small>British Columbia</small></div>
      <div class="prov">AB <small>Alberta</small></div>
      <div class="prov">SK <small>Saskatchewan</small></div>
      <div class="prov">MB <small>Manitoba</small></div>
      <div class="prov">ON <small>Ontario</small></div>
      <div class="prov">QC <small>Québec</small></div>
      <div class="prov">Atlantic <small>NB · NS · PE · NL</small></div>
      <div class="prov">North <small>YT · NT · NU</small></div>
    </div>
  </div>
</section>
{CTA}
""")

# ------------------------------------------------ CONTACT
PAGES['contact.html'] = ('Contact — MRA Healthcare Canada', phero(
 "Contact",
 "Let's talk about your program.",
 "One call. Real solutions. Whether you're planning a screening tour, standing up an outreach unit, or need a maintenance partner for a unit you already own.",
 crumb="Contact") + f"""
<section>
  <div class="wrap" style="display:grid;grid-template-columns:1fr 1.1fr;gap:56px;align-items:start">
    <div class="reveal">
      <span class="eyebrow">Reach Us</span>
      <h2 class="h2" style="font-size:clamp(24px,2.6vw,32px)">We answer the phone.</h2>
      <p class="lede" style="margin-top:14px">The first step is often the hardest — call us today and speak with a
      service representative to discuss your challenges and get real solutions.</p>
      <p style="margin-top:26px;font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--char);font-weight:700">Call toll-free</p>
      <a href="tel:1-800-676-3520" style="font-size:34px;font-weight:900;color:var(--red);text-decoration:none">1.800.676.3520</a>
      <p style="margin-top:8px;color:var(--char);font-size:14px">Monday–Friday · 8am–6pm ET<br>Service en français disponible</p>
      <p style="margin-top:24px;font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--char);font-weight:700">On the web</p>
      <p style="font-size:15px">goMRA.com &nbsp;·&nbsp; mrahealthcare.ca</p>
      <div style="margin-top:30px;background:var(--mist);border-left:4px solid var(--cyan-deep);padding:16px 20px;font-size:14px;color:#33383F">
        <b>Planning a tender or foundation proposal?</b> Ask us for itemized budget numbers — unit, transport,
        maintenance and operations, line by line, built for approvals.
      </div>
    </div>
    <form class="qform reveal" onsubmit="event.preventDefault();this.querySelector('.btn').textContent='✓ Request received — we\\'ll be in touch within one business day';">
      <h3>Request a Quote</h3>
      <div class="frow">
        <div><label for="q-name">Name</label><input id="q-name" required autocomplete="name"></div>
        <div><label for="q-org">Organization</label><input id="q-org" autocomplete="organization"></div>
      </div>
      <div class="frow">
        <div><label for="q-email">Email</label><input id="q-email" type="email" required autocomplete="email"></div>
        <div><label for="q-phone">Phone</label><input id="q-phone" type="tel" autocomplete="tel"></div>
      </div>
      <div class="frow">
        <div><label for="q-prov">Province / Territory</label>
        <select id="q-prov"><option>Ontario</option><option>Québec</option><option>British Columbia</option><option>Alberta</option><option>Saskatchewan</option><option>Manitoba</option><option>New Brunswick</option><option>Nova Scotia</option><option>Prince Edward Island</option><option>Newfoundland &amp; Labrador</option><option>Yukon</option><option>Northwest Territories</option><option>Nunavut</option></select></div>
        <div><label for="q-int">I'm interested in</label>
        <select id="q-int"><option>Equipment lease &amp; operations</option><option>À la carte logistics</option><option>Preventative maintenance</option><option>On-demand repair</option><option>Not sure yet — let's talk</option></select></div>
      </div>
      <label for="q-msg">Tell us about your program</label>
      <textarea id="q-msg" rows="4" placeholder="e.g. We're planning a 12-community screening tour next spring…"></textarea>
      <button class="btn" type="submit">Send Request</button>
      <p style="font-size:11.5px;color:#9A9C9E;margin-top:12px;text-align:center">We respond within one business day.</p>
    </form>
  </div>
</section>
{CTA}
""")

JS = """
<script>
  const io=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}}),{threshold:.1});
  document.querySelectorAll('.reveal').forEach(el=>io.observe(el));
</script>"""

# ---- emit real multi-page files ----
for fname,(title,body) in PAGES.items():
    active = fname
    html = f"""<!DOCTYPE html>
<html lang="en-CA">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>{CSS}</style>
</head>
<body>
{header(active)}
<main>{body}</main>
{FOOTER}
{JS}
</body>
</html>"""
    (OUT/fname).write_text(html)
    print(fname, len(html)//1024, 'KB')

# ---- emit single-file SPA preview (hash routing, same content) ----
sections = []
for fname,(title,body) in PAGES.items():
    pid = fname.replace('.html','')
    sections.append(f'<div class="pg" id="pg-{pid}" data-title="{title}">{body}</div>')
spa_body = '\n'.join(sections)
spa = f"""<!DOCTYPE html>
<html lang="en-CA">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MRA Healthcare — Mobile Medical Solutions Canada</title>
<style>{CSS}
.pg{{display:none}}
.pg.on{{display:block}}
</style>
</head>
<body>
{header('index.html')}
<main>{spa_body}</main>
{FOOTER}
<script>
  function route(page){{
    var id = (page||'index').replace('.html','');
    if(!document.getElementById('pg-'+id)) id='index';
    document.querySelectorAll('.pg').forEach(function(p){{p.classList.toggle('on', p.id==='pg-'+id)}});
    document.querySelectorAll('.nav-links a').forEach(function(a){{
      a.classList.toggle('on', (a.getAttribute('href')||'')===id+'.html');
    }});
    var pg=document.getElementById('pg-'+id);
    document.title = pg.dataset.title;
    window.scrollTo(0,0);
    var nl=document.getElementById('navLinks'); if(nl) nl.classList.remove('open');
    pg.querySelectorAll('.reveal').forEach(function(el){{el.classList.add('in')}});
  }}
  document.addEventListener('click', function(e){{
    var a=e.target.closest('a'); if(!a) return;
    var href=a.getAttribute('href')||'';
    if(href.indexOf('.html')>-1){{
      e.preventDefault();
      var parts=href.split('#');
      route(parts[0]);
      if(parts[1]){{
        var t=document.getElementById(parts[1]);
        if(t) setTimeout(function(){{t.scrollIntoView({{behavior:'smooth',block:'start'}})}},60);
      }}
    }} else if(href.charAt(0)==='#'){{
      var t=document.getElementById(href.slice(1));
      if(t){{e.preventDefault();t.scrollIntoView({{behavior:'smooth',block:'start'}});}}
    }}
  }});
  document.querySelectorAll('.reveal').forEach(function(el){{el.classList.add('in')}});
  route('index');
</script>
</body>
</html>"""
SPA.write_text(spa)
print('SPA:', len(spa)//1024, 'KB ->', SPA)
