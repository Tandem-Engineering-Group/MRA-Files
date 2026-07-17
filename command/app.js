/* ============================================================================
   MRA Command Center — core (app.js)
   Modular build: this file is the engine. It provides
     • the data layer (loads ../data.js, polls, holds optimistic edits)
     • shared helpers ported faithfully from MRA_Dashboard.html (the live board)
     • shared render primitives (task line, gantt, media, health) so every page
       carries the SAME bells (hover, click-through, Fleetio detail, photos,
       added-by, struck original due, etc.)
     • the full edit-engine port (shopWrite / _listOps / _findId / _wq) that
       writes to the same SharePoint Lists via the same Power Automate flow
     • the router (nav / crumb / home-mode / deep-links) + theme + floor + modals
   Page modules (pages/*.js) register into window.MRA_PAGES and draw into the
   section shells declared in index.html.  Load order (index.html): ../data.js →
   app.js → pages/*.js.  Everything here is global on purpose so page modules and
   inline onclick handlers can reach it.
   ============================================================================ */

/* ---------- data layer ---------- */
const DATA_URL = '../data.js';
function D(){ return window.MRA_DATA || {}; }
function todayISO(){ return D().todayISO || localISO(Date.now()); }

let ACTIVE_PAGE = 'home';
window.MRA_PAGES = window.MRA_PAGES || {};

// Optimistic-hold watermark: after a local edit, don't let the poll revert it
// until a strictly-newer Lists snapshot (taken >=2min after the edit) arrives.
let EDIT_PENDING=false, EDIT_TS=0, EDIT_LISTS_BASE='';
function markPending(){ const d=D(); EDIT_TS=Date.now(); EDIT_LISTS_BASE=d.listsAsOf||''; EDIT_PENDING=true; }
function listsCaughtUp(incoming){ if(!EDIT_LISTS_BASE) return true; const la=(incoming&&incoming.listsAsOf)||''; if(!la) return false;
  return la>EDIT_LISTS_BASE && Date.parse(la)>=(EDIT_TS||0)+120000; }

async function pollData(){
  try{
    const r=await fetch(DATA_URL+'?t='+Date.now(),{cache:'no-store'}); if(!r||!r.ok) return;
    const txt=await r.text(); let incoming=null;
    try{ incoming=(new Function('var window={};'+txt+';return window.MRA_DATA;'))(); }catch(e){ return; }
    if(!incoming) return;
    if(EDIT_PENDING){ if(!listsCaughtUp(incoming)) return; EDIT_PENDING=false; }
    window.MRA_DATA=incoming; window._PJBYROW=null; window._PTCOV=null;
    try{ prwRetry(); }catch(e){}   // fire any stranded by-id edits now that rows may have synced
    renderCurrent();
  }catch(e){}
}

/* ---------- utils ---------- */
function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }
function escA(s){ return esc(s).replace(/'/g,'&#39;'); }
function escJsAttr(s){ return String(s==null?'':s).replace(/\\/g,'\\\\').replace(/'/g,"\\'").replace(/"/g,'&quot;').replace(/[\r\n]/g,' '); }
function parseISO(s){ if(!s) return null; const m=String(s).match(/^(\d{4})-(\d{2})-(\d{2})/); if(m) return new Date(+m[1],+m[2]-1,+m[3]);
  const d=new Date(s); return isNaN(d)?null:d; }
function localISO(ms){ const d=(ms instanceof Date)?ms:new Date(ms); return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'); }
function daysBetween(aISO,bISO){ const a=parseISO(aISO),b=parseISO(bISO); if(!a||!b) return null; return Math.round((a-b)/86400000); }
function fmtMD(iso){ const d=parseISO(iso); if(!d) return ''; return (d.getMonth()+1)+'/'+d.getDate(); }
function fmtMDY(iso){ const d=parseISO(iso); if(!d) return ''; return (d.getMonth()+1)+'/'+d.getDate()+'/'+String(d.getFullYear()).slice(-2); }
const MONTHS=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
function fmtMon(iso){ const d=parseISO(iso); if(!d) return ''; return MONTHS[d.getMonth()]+' '+d.getDate(); }
const DAY=86400000;
function _isoAddDays(iso,days){ const d=parseISO(iso); if(!d) return iso; return localISO(d.getTime()+(+days||0)*DAY); }
function clampN(n,lo,hi){ return Math.max(lo,Math.min(hi,n)); }

/* ---------- comment machine-tags (ported verbatim from the board) ----------
   State rides inside the Comments column so it needs no schema/flow change.
   Every edit that rewrites Comments MUST strip-then-reapply; every display strips. */
function repeatOf(cm){ const m=String(cm||'').match(/\[repeat:([a-z]+)(?::(\d))?\]/i); if(!m) return null; return {kind:m[1].toLowerCase(), dow:(m[2]!=null?+m[2]:null)}; }
function stripRepeat(cm){ return String(cm||'').replace(/\s*\[repeat:[^\]]*\]/ig,'').trim(); }
function _withRepeat(cm,val){ cm=stripRepeat(cm); if(val){ const p=String(val).split(':'); const tag='[repeat:'+p[0]+(p[0]==='weekly'?(':'+(p[1]!=null?p[1]:1)):'')+']'; cm=(cm?cm+' ':'')+tag; } return cm; }
function _repVal(cm){ const r=repeatOf(cm); if(!r) return ''; return r.kind==='weekly'?('weekly:'+(r.dow!=null?r.dow:1)):r.kind; }
function isSnzRep(t){ try{ if(!t||t.done||!t.due) return false; if(!repeatOf(t.cm)) return false;
  const today=todayISO(); const lim=_isoAddDays(today,3); return String(t.due)>lim; }catch(e){ return false; } }
function _taskBy(cm){ const m=String(cm||'').match(/\[by:([^\]]+)\]/i); return m?m[1].trim():''; }
function stripBy(cm){ return String(cm||'').replace(/\s*\[by:[^\]]*\]/ig,'').trim(); }
function _withBy(cm,by){ cm=stripBy(cm); if(by){ cm=(cm?cm+' ':'')+'[by:'+String(by).replace(/[\]]/g,'').trim()+']'; } return cm; }
function _byLine(cm){ const b=_taskBy(cm); return b?('<div class="cby" title="Who added this task — ask them if you have questions">\u{1F9D1} added by '+esc(b)+'</div>'):''; }
function _taskDue0(cm){ const m=String(cm||'').match(/\[due0:(\d{4}-\d{2}-\d{2})\]/i); return m?m[1]:''; }
function stripDue0(cm){ return String(cm||'').replace(/\s*\[due0:[^\]]*\]/ig,'').trim(); }
function _withDue0(cm,iso){ cm=stripDue0(cm); if(/^\d{4}-\d{2}-\d{2}$/.test(String(iso||''))){ cm=(cm?cm+' ':'')+'[due0:'+iso+']'; } return cm; }
function _due0Strike(cm, curISO){ const o=_taskDue0(cm); if(!o||!curISO||o===String(curISO)) return '';
  return '<span class="due0" title="Original due date — pushed out">'+esc(fmtMD(o))+'</span> → '; }
function _ptTag(proj, handle){ return '[pt:'+String(proj).replace(/[\[\]|]/g,' ').trim()+'|'+String(handle)+']'; }
// The canonical display strip — reproduce exactly so no raw [tag:] leaks into visible text.
function _mwCleanCm(cm){ return String(cm||'').replace(/\[(?:repeat|pt|sales|mtg|subjob|sub|by|due0)[^\]]*\]/gi,'').replace(/\[sales\]\s*\{[\s\S]*$/i,'').trim(); }

/* ---------- classification (data-mapping edge cases) ---------- */
function isLive(j){ return !!j && j.category!=='leave' && String(j.status||'').toLowerCase()!=='shipped'; }
function isParkingBay(b){ return /^\s*parking\s*lot\s*$/i.test(b||''); }
function bayIsParts(b){ return /parts/i.test(b||''); }
function bayIsHeld(b){ return !bayIsParts(b) && /next\s*up|on\s*hold|off.?site/i.test(b||''); }
function isHeldBay(b){ return bayIsHeld(b); }
function isGeneralBay(b){ return /^\s*general\s*$/i.test(b||''); }
const MIDDLE_BAYS=['Bay 3 Middle','Bay 4 Middle'];
// A task counts toward crew load / open work only when its job is on an active bay
// (a real bay, the Parking Lot, or Off Site / Parts). Held-bay work is latent.
function jobIsActiveLane(j){ return isLive(j) && !isOrphan(j) && !bayIsHeld(j.bay); }
function isSalesT(t){ const s=(t&&(t.t!=null?t.t:t))||''; return /^\s*\[sales\]/i.test(String(s)); }
function projIsPendingVerify(t){ return /pending verification/i.test((t&&t.st)||''); }
function jobIsSub(j){ return /\[subjob\]/i.test((j&&j.notesRaw)||''); }
function isOrphan(j){ return !!j && (String(j.row||'').indexOf('orphan:')===0 || j.category==='pipeline'); }

const CREW_ALIAS = { 'masterwraps':'Wrap Team','master wraps':'Wrap Team','wraps':'Wrap Team','wrap team':'Wrap Team',
  'electrician':'Electricians','electricians':'Electricians','maintenance':'Maintenance','mra design':'MRA Design' };
const CREW_GROUPS = ['MRA Design','MRA Shop','Electricians','Wrap Team','Maintenance'];
function crewCanon(part){ const k=(part||'').trim().toLowerCase(); return CREW_ALIAS[k] || (part||'').trim(); }
function crewWhoList(who){ who=(who||'').trim(); if(!who) return [];
  return [...new Set(who.split(/\s+\/\s+/).map(crewCanon).filter(Boolean))]; }
// The board's six print crews + MRA Shop, used for the by-assignee lanes.
const ASSIGNEE_OPTIONS = ['Sal','Wrap Team','Electricians','Doug','Josh','Jeff','Vendor'];
function _combineAssignees(a1,a2){ a1=(a1||'').trim(); a2=(a2||'').trim(); return (a2 && a2.toLowerCase()!==a1.toLowerCase()) ? (a1?(a1+' / '+a2):a2) : a1; }

/* ---------- Fleetio + media + GPS (ported) ---------- */
const FLEETIO_BASE='https://secure.fleetio.com/8cf2193b5d';
function fioHref(kind,num){ if(kind==='wo') return FLEETIO_BASE+'/work_orders'+((num!=null&&num!=='')?('/'+encodeURIComponent(num)):'');
  if(kind==='svc') return FLEETIO_BASE+'/service_reminders';
  return FLEETIO_BASE+'/issues'+((num!=null&&num!=='')?('/'+encodeURIComponent(num)):''); }
function fioIssue(num){ return (((D().fleetio&&D().fleetio.issues)||[]).find(i=>String(i.num)===String(num)))||null; }
function _taskFnum(t){ const s=String((t&&(t.t!=null?t.t:t))||''); let m=s.match(/\u{1F527}\s*#(\d+)/u); if(m) return m[1]; m=s.match(/#(\d+)/); return m?m[1]:''; }
function fAsg(it){ return (it&&(it.assignees||[]))||[]; }
function fioTitle(kind,num,label){ return `<a class="fiotitle" href="${fioHref(kind,num)}" target="_blank" rel="noopener" onclick="event.stopPropagation()" title="Open in Fleetio${num?' to close it there':''} ↗">${num?`<span class="fionum">#${esc(num)}</span> `:''}${esc(label)}<span class="fioarrow"> ↗</span></a>`; }
function fioDetHtml(num){ const it=fioIssue(num); const d=(it&&it.detail)?String(it.detail).trim():'';
  return d?`<div class="fl-det" onclick="event.stopPropagation();this.classList.toggle('open')" title="${escA(d)}">${esc(d)}</div>`:''; }
function _taskMedia(files,num){ let a=[]; try{ a=(typeof files==='string')?(JSON.parse(files)||[]):((files||[]).slice()); }catch(e){ a=[]; }
  if(!Array.isArray(a)) a=[]; const it=num?fioIssue(num):null;
  ((it&&it.docs)||[]).forEach(d=>{ if(!a.some(x=>x.url===d.url)) a.push(d); }); return a; }
function mediaHtml(docs){ docs=docs||[]; if(!docs.length) return '';
  const imgs=docs.filter(x=>/^image\//i.test(x.mime||'')), files=docs.filter(x=>!/^image\//i.test(x.mime||''));
  let h='<span class="fmedia">';
  imgs.slice(0,3).forEach(x=>{ h+=`<img class="fthumb" loading="lazy" src="${escA(x.url)}" alt="" onmouseenter="fthumbZoom(event,this.src)" onmouseleave="fthumbHide()" onclick="event.stopPropagation();fthumbHide();window.open('${escJsAttr(x.url)}','_blank')" title="Click to open full size">`; });
  files.slice(0,2).forEach(x=>{ h+=`<a class="fdoc" href="${escA(x.url)}" target="_blank" rel="noopener" onclick="event.stopPropagation()" title="${escA(x.n||'attachment')}">\u{1F4CE}</a>`; });
  const extra=(imgs.length>3?imgs.length-3:0)+(files.length>2?files.length-2:0);
  if(extra) h+=`<span class="fmore">+${extra}</span>`;
  return h+'</span>'; }
function fthumbZoom(ev,src){ let z=document.getElementById('fzoom'); if(!z){ z=document.createElement('div'); z.id='fzoom'; document.body.appendChild(z); }
  z.innerHTML=`<img src="${escA(src)}">`;
  const x=Math.min((ev&&ev.clientX||200)+18, innerWidth-430), y=Math.max(10, Math.min((ev&&ev.clientY||200)-120, innerHeight-330));
  z.style.left=Math.max(8,x)+'px'; z.style.top=y+'px'; z.style.display='block'; }
function fthumbHide(){ const z=document.getElementById('fzoom'); if(z) z.style.display='none'; }
function _fioAge(i){ if(i&&i.openedISO){ const d=daysBetween(todayISO(),i.openedISO); return (d==null||isNaN(d))?null:Math.max(0,d); } return (i&&i.ageDays!=null)?i.ageDays:null; }
function _fioIsNew(i){ const a=_fioAge(i); return a!=null&&a<=7; }
function ageBadge(age){ if(age==null) return ''; const cls=age>90?'danger':age>=30?'badge':'pill'; return `<span class="${cls}">${age}d open</span>`; }
// Sort: overdue -> 🆕 new -> priority -> oldest (the board default).
function _fioIssCmp(a,b){ const ao=_fioAge(a), bo=_fioAge(b);
  if(!!b.overdue !== !!a.overdue) return (b.overdue?1:0)-(a.overdue?1:0);
  const an=_fioIsNew(a), bn=_fioIsNew(b); if(an!==bn) return (bn?1:0)-(an?1:0);
  const pr=s=>/high|emergency/i.test(s||'')?0:/medium/i.test(s||'')?1:2;
  const pd=pr(a.priority)-pr(b.priority); if(pd) return pd;
  return (bo||0)-(ao||0); }

function _normKey(s){ let t=String(s||'').trim().split(/\s+/)[0]||''; const m=t.match(/^(\d+)G$/i); return (m?m[1]:t).toUpperCase(); }
function _ynAgo(atISO){ if(!atISO) return ''; const t=new Date(atISO).getTime(); if(!t||isNaN(t)) return ''; const ms=Date.now()-t; if(ms<0) return 'just now';
  const h=ms/3600000; if(h<1) return Math.max(1,Math.round(ms/60000))+'m ago'; if(h<48) return Math.round(h)+'h ago'; return Math.round(h/24)+'d ago'; }
function _gpsStale(loc){ if(!loc||!loc.atISO) return false; const t=new Date(loc.atISO).getTime(); if(!t||isNaN(t)) return false; return (Date.now()-t)>14*DAY; }
function _gpsStaleTxt(loc){ if(!loc) return ''; const wh=String(loc.yard||loc.place||'?').trim(), ago=_ynAgo(loc.atISO);
  let days=null; try{ const t=new Date(loc.atISO).getTime(); if(t&&!isNaN(t)) days=Math.round((Date.now()-t)/DAY); }catch(e){}
  const word=(days!=null&&days>60)?'tracker DEAD':'GPS stale';
  return word+' · last '+wh+(ago?(' ('+ago+')'):'')+((loc.src==='fleetio')?' · per Fleetio':''); }
function _ynLoc(name, jobNum){ const locs=(D().fleetio&&D().fleetio.locations)||{};
  const byKey=k=>{ for(const kk in locs){ if(_normKey(kk)===k) return locs[kk]; } return null; };
  const m=String(name||'').trim().match(/^(\d{2,5})\b/); if(m){ const l=byKey(_normKey(m[1])); if(l) return l; }
  const jn=String(jobNum||'').toUpperCase().replace(/[^0-9]/g,'');
  if(jn){ const fleet=(D().fleetio&&D().fleetio.fleet)||[]; const digits=s=>String(s||'').toUpperCase().replace(/[^0-9]/g,'');
    const cands=fleet.filter(f=>digits(f.tour).includes(jn) || digits(f.nm).includes(jn));
    const words=String(name||'').toUpperCase().split(/\s+/).filter(w=>w.length>=4); let best=null,bestScore=-1;
    cands.forEach(f=>{ const fn=String(f.nm||'').toUpperCase(); let s=0; words.forEach(w=>{ if(fn.includes(w)) s+=2; });
      if(byKey(_normKey(f.f))) s+=1; if(s>bestScore){ bestScore=s; best=f; } });
    if(best){ const l=byKey(_normKey(best.f)); if(l) return l; } }
  return null; }
// A single location chip for a job — honest about stale / dead / no-fix.
function locChip(job){ if(jobIsSub(job)) return ''; const loc=_ynLoc(job.project, job.jobNum);
  if(!loc) return '<span class="gpschip none" title="No live tracker for this unit">📡 no GPS</span>';
  if(_gpsStale(loc)) return '<span class="gpschip stale" title="'+escA(_gpsStaleTxt(loc))+'">📡 '+esc(_gpsStaleTxt(loc))+'</span>';
  const wh=esc(loc.yard||loc.place||'GPS'); return '<span class="gpschip live" title="Live GPS · '+escA(_ynAgo(loc.atISO))+'">📍 '+wh+'</span>'; }

/* ---------- project health (ported) ---------- */
function projHealth(p, today){ today=today||todayISO();
  if(p.parked) return {state:'parked'};
  if(p.pct>=100) return {state:'done'};
  if(p.startISO && p.startISO>today) return {state:'upcoming'};
  let exp=null;
  if(p.startISO && p.finishISO && p.finishISO>p.startISO){ const s=parseISO(p.startISO).getTime(), f=parseISO(p.finishISO).getTime(), n=parseISO(today).getTime();
    exp=Math.max(0,Math.min(100,Math.round((n-s)/(f-s)*100))); }
  const behindBy=(exp!=null)?exp-p.pct:null;
  if(p.finishISO && p.finishISO<today && p.pct<100) return {state:'late', expectedPct:exp, behindBy};
  if(behindBy!=null && behindBy>=15) return {state:'behind', expectedPct:exp, behindBy};
  return {state:'ontrack', expectedPct:exp, behindBy}; }
const HEALTH_RANK={late:0, behind:1, ontrack:2, upcoming:3, parked:4, done:9};
const HEALTH_COLOR={late:'#e34b59', behind:'#f59e0b', ontrack:'#18a875', upcoming:'#2166f3', parked:'#64748b', done:'#18a875'};
const HEALTH_LABEL={late:'Late', behind:'Behind', ontrack:'On track', upcoming:'Upcoming', parked:'Parked', done:'Complete'};
function nextGate(p, today){ today=today||todayISO(); return (p.milestones||[]).filter(m=>!m.done && m.dateISO>=today).sort((a,b)=>a.dateISO.localeCompare(b.dateISO))[0]||null; }
function _pmtBehindBits(p, today){ today=today||todayISO();
  const od=(p.tasks||[]).filter(t=>!t.done && (t.finISO||'') && t.finISO<today);
  const who={}; od.forEach(t=>{ const w=(t.who||'').split('/')[0].trim()||'—'; who[w]=(who[w]||0)+1; });
  const whoTxt=Object.keys(who).slice(0,4).map(w=>w+' ('+who[w]+')').join(', ');
  return {odN:od.length, od:od, whoTxt, gate:nextGate(p,today)}; }
function canVerify(projName){ if(!CLOSE_PIN) return false; const p=(D().projects||[]).find(x=>x.name===projName);
  if(VERIFY_ADMINS.indexOf(CURRENT_USER)>=0) return true;
  if(!p) return false; const pm=(p.pm||'').toLowerCase().trim(), me=(CURRENT_USER||'').toLowerCase().trim();
  if(!pm||!me) return false; return pm===me || pm.indexOf(me)>=0 || me.indexOf(pm)>=0 || pm.split(' ')[0]===me.split(' ')[0]; }
const VERIFY_ADMINS=['Rich Miller'];
const PROJ_VERIFY_STATUS='Pending Verification';

/* ---------- project <-> floor-job linking (J#-first) ---------- */
function _projJobsFor(pname){ const p=(D().projects||[]).find(x=>x.name===pname); if(!p) return [];
  const dig=s=>String(s||'').toUpperCase().replace(/[^0-9]/g,''); const norm=s=>String(s||'').toLowerCase().replace(/[^a-z0-9]/g,'');
  const pj=dig(p.jobNum), pn=norm(pname);
  return (D().jobs||[]).filter(j=>{ if(j.category==='leave'||(j.status||'').toLowerCase()==='shipped') return false;
    if(pj) return dig(j.jobNum)===pj; const jn=norm(j.project); if(!jn||!pn) return false; return jn.indexOf(pn)>=0 || pn.indexOf(jn)>=0; }); }
function _projMainJob(pname){ const list=_projJobsFor(pname); if(!list.length) return null;
  const rank=j=>{ const b=String(j.bay||''); if(bayIsHeld(b)) return 3; if(/parking|next\s*up/i.test(b)) return 2; return jobIsSub(j)?1:0; };
  const norm=s=>String(s||'').toLowerCase().replace(/[^a-z0-9]/g,''); const extra=j=>Math.abs(norm(j.project).length-norm(pname).length);
  return list.slice().sort((a,b)=>rank(a)-rank(b)||extra(a)-extra(b)||String(a.row).localeCompare(String(b.row)))[0]; }
function _ptCov(){ if(window._PTCOV) return window._PTCOV; const tags=new Set(); const txt={};
  (D().jobs||[]).forEach(j=>{ (j.tasks||[]).forEach(t=>{ if(t.done) return;
    const m=String(t.cm||'').match(/\[pt:([^|\]]+)\|([^\]]+)\]/); if(m) tags.add(m[1].trim()+'|'+m[2].trim());
    const k=String(j.row); (txt[k]=txt[k]||new Set()).add(String(t.t||'').toLowerCase().replace(/[^a-z0-9]/g,'')); }); });
  return (window._PTCOV={tags:tags, txt:txt}); }
function _ptCovered(projName, handle, taskText, mainRow){ const cov=_ptCov();
  if(handle && cov.tags.has(projName+'|'+String(handle))) return true;
  if(mainRow!=null){ const s=cov.txt[String(mainRow)]; if(s && s.has(String(taskText||'').toLowerCase().replace(/[^a-z0-9]/g,''))) return true; }
  return false; }
function projTaskHandle(t){ return (t.id!=null&&t.id!=='')?String(t.id):(t._id!=null?('s'+t._id):null); }
// Build the per-job map of project schedule lines to surface on bay cards (once per paint).
function _pjRebuild(){ window._PTCOV=null; const map={};
  try{ const today=todayISO(); const lim=_isoAddDays(today,14); const CRW=/\bsal\b|wrap|electr|doug|josh|jeff|maintenance|mra\s*shop/i;
    (D().projects||[]).forEach(p=>{ const rows=[];
      (p.tasks||[]).forEach(t=>{ if(t.done===true||/complete/i.test(String(t.st||''))) return; if(/yes/i.test(String(t.ml||''))) return;
        const w=String(t.who||'').trim(); if(!w||!CRW.test(w)) return; const dt=t.startISO||t.finISO; if(!dt||dt>lim) return;
        rows.push({proj:p.name, t:String(t.t||''), who:w, st0:t.startISO||null, fin:t.finISO||null, handle:projTaskHandle(t),
          pv:projIsPendingVerify(t)}); });
      if(!rows.length) return; const mj=_projMainJob(p.name); if(!mj) return;
      const kept=rows.filter(r=>!_ptCovered(p.name, r.handle, r.t, mj.row)); if(!kept.length) return;
      const k=String(mj.row); map[k]=(map[k]||[]).concat(kept); });
    Object.keys(map).forEach(k=>map[k].sort((a,b)=>String(a.fin||'9999').localeCompare(String(b.fin||'9999')))); }catch(e){}
  window._PJBYROW=map; }
function _projTasksForJob(j){ if(!window._PJBYROW) _pjRebuild(); return (window._PJBYROW||{})[String(j.row)]||[]; }

/* ---------- bay-grid model (shared by home / shop / floor) ---------- */
function bayNumOf(b){ const m=String(b||'').match(/bay\s*(\d+)/i); return m?+m[1]:null; }
function bayPosOf(b){ if(/front/i.test(b)) return 'Front'; if(/middle/i.test(b)) return 'Middle'; if(/back|loading/i.test(b)) return 'Back'; return ''; }
function bayGridModel(){ const bays={};
  (D().jobs||[]).forEach(j=>{ if(!isLive(j)) return; const n=bayNumOf(j.bay); if(n==null) return; const pos=bayPosOf(j.bay)||'Front';
    const B=(bays[n]=bays[n]||{bay:n,Front:null,Middle:null,Back:null});
    if(!B[pos]) B[pos]=j; else if(!B.Back) B.Back=j; else if(!B.Middle) B.Middle=j; });
  return Object.keys(bays).map(Number).sort((a,b)=>a-b).map(n=>bays[n]); }
function jobsInBay(pred){ return (D().jobs||[]).filter(j=>isLive(j) && pred(j.bay)); }
function openTasksOf(j){ return (j.tasks||[]).filter(t=>!t.done && !isSnzRep(t)); }
function jobPct(j){ const d=(j.tasks||[]).filter(t=>t.done).length, o=openTasksOf(j).length; const tot=d+o; return tot?Math.round(d/tot*100):0; }
function kindOf(j){ const s=(j.status||'')+' '+(j.project||''); const b=j.bay||'';
  if(/decomm/i.test(s)) return 'decommission'; if(/storage/i.test(b)||/storage/i.test(s)) return 'storage';
  if(/parts/i.test(b)) return 'maintenance'; return 'project'; }
const KIND_LABEL={project:'Project',maintenance:'Maintenance',storage:'Storage',decommission:'Decommission'};
// Fleetio "Back to MRA → Leaving MRA" range for a job by J# (from its issues), skips sub-jobs.
function fioMraRange(job){ if(jobIsSub(job)) return ''; const jn=String(job.jobNum||'').toUpperCase().replace(/[^0-9]/g,''); if(!jn) return '';
  const it=((D().fleetio&&D().fleetio.issues)||[]).find(i=>String(i.jobNum||'').toUpperCase().replace(/[^0-9]/g,'')===jn && (i.backMRA||i.leaveMRA));
  if(!it) return ''; const a=it.backMRA||'', b=it.leaveMRA||''; if(!a&&!b) return ''; return '🗓 '+(a||'?')+(b?(' → '+b):''); }

/* ============================================================================
   EDIT ENGINE (ported from MRA_Dashboard.html — same Lists, same flow)
   ============================================================================ */
const CLOSE_FLOW_URL = "https://default57714027b784449484126e3b00c9bf.2c.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/c7056430c8f645719ac5d29038822b04/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=YXL0v51JH_hIax3z1WpKKyxY3BYSQ5bCl7U6O50VSpg";
const LISTS_WRITE_URL = "https://default57714027b784449484126e3b00c9bf.2c.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/12d3826052ea4f5584ec2921fc83172c/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=sFy30x3sqmmrAYw64u6fytwIXUSZ9DQwn7fVsfvC_cQ";
const SHOP_WRITE_URL = CLOSE_FLOW_URL;
const USE_LISTS_WRITE = true;

const _LF = {
  Jobs:         { list:"MRA Jobs",          cols:{Project:"Title",Bay:"field_1",Client:"field_2",JobNum:"field_3",Start:"field_4",Finish:"field_5",Status:"field_6",PM:"field_7",Notes:"field_8",Ord:"JobOrd"} },
  ShopTasks:    { list:"MRA Shop Tasks",    cols:{Task:"Title",Project:"field_1",JobNum:"field_2",Bay:"field_3",Assigned:"field_4",Status:"field_5",Opened:"field_6",Closed:"field_7",Comments:"field_9",Due:"Due",Files:"Files"} },
  ProjectTasks: { list:"MRA Project Tasks", cols:{Task:"Title",Project:"field_1",TaskID:"field_2",Phase:"field_3",Type:"TaskType",JobNum:"JobNum",Assigned:"field_5",Start:"field_6",Finish:"field_7",Status:"field_9",PM:"field_10",Milestone:"field_11",Comments:"field_12",Sub:"field_14",NonOfficial:"NonOfficial",Parked:"Parked"} },
  Users:        { list:"MRA Users",         cols:{Name:"Title",Code:"field_1",Role:"field_2",Active:"field_3"} },
  Holidays:     { list:"MRA Holidays",      cols:{Name:"Title",Date:"field_1",Country:"field_2"} }
};
function _odEsc(v){ return String(v).replace(/'/g,"''"); }
function _odSafe(v){ const s=String(v==null?'':v); return /^[ -~]*$/.test(s) && !/[#&%+]/.test(s); }
function _defs(o){ const r={}; for(const k in o){ if(o[k]!==undefined && o[k]!==null) r[k]=o[k]; } return r; }
function _doneStatus(s){ return /done|complete|closed/i.test(s||''); }
function _listToday(){ return localISO(Date.now()); }

function _findId(listKey, match){ if(!match) return null; if(match.__id!=null && match.__id!=='') return match.__id;
  const d=D(), P=match.Project, T=match.Task;
  if(listKey==='Jobs'){ const j=(d.jobs||[]).find(x=>x.project===P); return j&&j._id!=null?j._id:null; }
  if(listKey==='ShopTasks'){ for(const j of (d.jobs||[])){ if(j.project!==P) continue; const all=(j.tasks||[]).filter(t=>t.t===T); if(!all.length) continue;
    const tk=all.filter(t=>!t.done).sort((a,b)=>String(a.due||'9999').localeCompare(String(b.due||'9999')))[0]||all[0]; if(tk&&tk._id!=null) return tk._id; } return null; }
  if(listKey==='ProjectTasks'){ const pr=(d.projects||[]).find(x=>x.name===P); if(!pr) return null; const tk=(pr.tasks||[]).find(t=>t.t===T); return tk&&tk._id!=null?tk._id:null; }
  return null; }

function _listOpsRaw(p){ const today=_listToday(); const a=p.action || (p.closedDate!=null ? 'closeTask' : '');
  const O=(verb,list,match,set)=>({verb,list,match:match?_defs(match):null,set:set?_defs(set):null});
  switch(a){
    case 'closeTask':        return [O('update','ShopTasks',{Project:p.project,Task:p.task},{Status:'Done',Closed:today})];
    case 'addTask':          return [O('create','ShopTasks',null,{Task:p.task,Project:p.project,JobNum:p.jobNum,Bay:p.bay,Assigned:p.assigned,Opened:today,Status:'Open',Milestone:p.milestone,Comments:p.comments,Due:(p.due||undefined)})];
    case 'editTask':         return [O('update','ShopTasks',{Project:p.project,Task:p.taskOld},{Task:p.task,Assigned:p.assigned,Status:p.status,Milestone:p.milestone,Comments:p.comments,Due:(p.due||undefined),Closed:(_doneStatus(p.status)?today:'')})];
    case 'deleteTask':       return [O('delete','ShopTasks',{Project:p.project,Task:p.task})];
    case 'reopenTask':       return [O('update','ShopTasks',{Project:p.project,Task:p.task},{Status:'Open',Closed:''})];
    case 'setTaskFiles':     return [O('update','ShopTasks',{Project:p.project,Task:p.task,__id:p._id},{Files:JSON.stringify(p.files||[])})];
    case 'addProjectTask':   return [O('create','ProjectTasks',null,{Task:p.task,Project:p.project,Phase:p.phase,Type:p.type,Assigned:p.assigned,Status:p.status,Start:p.start,Finish:p.finish,Milestone:p.milestone,Sub:(p.sub?'x':''),Comments:p.comments})];
    case 'editProjectTask':  return [O('update','ProjectTasks',{Project:p.project,Task:p.taskOld,__id:p._id},{Task:p.task,Phase:p.phase,Type:p.type,Assigned:p.assigned,Status:p.status,Start:p.start,Finish:p.finish,Milestone:p.milestone,Sub:(p.sub?'x':''),Comments:p.comments})];
    case 'deleteProjectTask':return [O('delete','ProjectTasks',{Project:p.project,Task:p.task,__id:p._id})];
    case 'closeProjectTask': return [O('update','ProjectTasks',{Project:p.project,Task:p.task,__id:p._id},{Status:'Completed'})];
    case 'reopenProjectTask':return [O('update','ProjectTasks',{Project:p.project,Task:p.task,__id:p._id},{Status:'In Progress'})];
    case 'editJob':          return [O('update','Jobs',{Project:p.project},{Bay:p.bay,Start:p.start,Finish:p.finish,Status:p.status,PM:p.pm,Notes:p.notes,Client:p.client})];
    default: return null;
  } }
function _listOps(p){ const raw=_listOpsRaw(p); if(!raw) return null; const out=[];
  for(const o of raw){ const lf=_LF[o.list]; if(!lf) continue; const r={verb:o.verb, list:lf.list};
    if(o.set){ const b={}; for(const k in o.set){ if(lf.cols[k]) b[lf.cols[k]]=o.set[k]; } r.body=b; }
    let id=null; if((o.verb==='update'||o.verb==='delete')) id=_findId(o.list,o.match);
    if(id!=null){ r.verb=(o.verb==='delete')?'deleteById':'mergeById'; r.id=id; }
    else if(o.match){
      const canQueue=(o.list==='ShopTasks'||o.list==='ProjectTasks') && o.match.Task!=null;
      const unsafe=Object.keys(o.match).some(k=>{ const col=lf.cols[k]||k; return !(col==='Id'||col==='ID') && !_odSafe(o.match[k]); });
      // Row has no _id yet (just added, not synced back) => queue a by-id retry so the edit isn't lost.
      if(o.verb==='update' && canQueue && r.body && Object.keys(r.body).length) pendRewrite(o.list, o.match.Project, o.match.Task, r.body);
      if(canQueue && unsafe){ if(o.verb==='delete') pendDelete(o.list, o.match.Project, o.match.Task); if(o.verb==='update'||o.verb==='delete') continue; }  // emoji/#/&/– break OData -> only the by-id retry can land it
      r.filter=Object.keys(o.match).map(k=>{ const col=lf.cols[k]||k; const v=o.match[k];
        return (col==='Id'||col==='ID')?(col+' eq '+v):(col+" eq '"+_odEsc(v)+"'"); }).join(' and '); }
    out.push(r); }
  return out; }

/* Pending by-id retry queue — an edit/delete on a task whose SharePoint _id isn't in
   data.js yet (just added, not synced) can't match by OData (emoji/# break it). Stash it;
   re-fire by id the moment the row appears with an _id (on the next poll + on sign-in). */
const PRW_KEY='cc_pending_rewrite_v1';
function _prwLoad(){ try{ return JSON.parse(localStorage.getItem(PRW_KEY)||'[]'); }catch(e){ return []; } }
function _prwSave(a){ try{ localStorage.setItem(PRW_KEY, JSON.stringify(a)); }catch(e){} }
function pendRewrite(listKey, project, task, body){ const a=_prwLoad(); a.push({v:'merge', listKey, project, task, body, ts:Date.now()}); _prwSave(a); }
function pendDelete(listKey, project, task){ const a=_prwLoad(); a.push({v:'del', listKey, project, task, ts:Date.now()}); _prwSave(a); }
function prwRetry(){ let a=_prwLoad(); if(!a.length) return; const keep=[];
  for(const e of a){ if(Date.now()-(e.ts||0) > 3*86400000) continue;   // give up after 3 days
    const id=_findId(e.listKey, {Project:e.project, Task:e.task});
    if(id==null){ keep.push(e); continue; }                            // row still not synced -> keep waiting
    const list=(_LF[e.listKey]||{}).list; if(!list){ continue; }
    if(e.v==='del') _wq.push({op:{verb:'deleteById', list, id}, pin:CLOSE_PIN||'1974', user:CURRENT_USER});
    else _wq.push({op:{verb:'mergeById', list, id, body:e.body}, pin:CLOSE_PIN||'1974', user:CURRENT_USER}); }
  _prwSave(keep); if(keep.length<a.length) _wqDrain(); }

const WRITE_GAP_MS=1500; let _wq=[], _wqBusy=false;
function _wqDrain(){ if(_wqBusy) return; _wqBusy=true; (async()=>{ while(_wq.length){ const payload=_wq.shift();
  const _toLists=(payload && (payload.op||payload.ops) && LISTS_WRITE_URL); const _url=_toLists?LISTS_WRITE_URL:SHOP_WRITE_URL;
  try{ await fetch(_url,{method:"POST",mode:"no-cors",headers:{"Content-Type":"text/plain;charset=UTF-8"},body:JSON.stringify(payload)}); }catch(e){}
  if(_wq.length) await new Promise(r=>setTimeout(r,_toLists?250:WRITE_GAP_MS)); } _wqBusy=false; })(); }
function shopWrite(payload){
  try{ if(payload && /^(addTask|addProjectTask)$/.test(payload.action||'') && payload.user
      && !/^(shop|design team)$/i.test(String(payload.user).trim()) && !/\[by:/i.test(payload.comments||'')){
    payload.comments=_withBy(payload.comments||'', payload.user); } }catch(e){}
  if(USE_LISTS_WRITE){ const ops=_listOps(payload); if(ops && ops.length){ ops.forEach(op=>_wq.push({op:op, pin:payload.pin, user:payload.user})); _wqDrain(); return Promise.resolve(); } }
  _wq.push(payload); _wqDrain(); return Promise.resolve(); }

/* ============================================================================
   AUTH — SAME rules as the classic board: Microsoft (@gomra.com) sign-in + roles,
   FAIL-OPEN off the live host (previews/sandbox behave un-gated), code fallback
   for shared shop screens. Ported verbatim from MRA_Dashboard.html so the two
   boards gate login + viewing identically.
   ============================================================================ */
let CLOSE_PIN=null, CURRENT_USER='';
const CLOSE_PIN_HASH=1516293;
function pinHash(s){ let h=0; for(let i=0;i<s.length;i++){ h=(h*31 + s.charCodeAt(i))>>>0; } return h; }
function findUser(code){ const us=(D().users)||[]; const h=pinHash(code);
  if(us.length){ const u=us.find(x=>x.h===h); if(u) return u.name||''; } return (h===CLOSE_PIN_HASH)?'':null; }
let _authRetry=null;
function _nmKey(s){ return String(s||'').toLowerCase().replace(/[^a-z ]/g,' ').split(/\s+/).filter(Boolean).sort().join(' '); }
function _whoMatch(who,name){ if(!who||!name) return false; const n=_nmKey(name), f=String(name).toLowerCase().split(/\s+/)[0];
  return crewWhoList(who).some(p=>{ const pk=_nmKey(p), pf=String(p).toLowerCase().split(/\s+/)[0]; return pk===n||pf===f||(pk&&n&&(pk.indexOf(n)>=0||n.indexOf(pk)>=0)); }); }

const ROLE_BY_EMAIL = {
  'rmiller@gomra.com':'admin','akarloff@gomra.com':'admin','luciana.giglio@gomra.com':'admin','qolivito@gomra.com':'admin',
  'megan.fraser@gomra.com':'editor','bchoy@gomra.com':'editor',
  'swilliams@gomra.com':'design','markm@gomra.com':'design',
  'cindyi@gomra.com':'shopedit','rwheeler@gomra.com':'shopedit',
  'tony@gomra.com':'exec','johnr@gomra.com':'exec','gbitonti@gomra.com':'exec',
  'jeberhart@gomra.com':'closer','jsellers@gomra.com':'closer'
};
const BOARD_NAME_BY_EMAIL={ 'jeberhart@gomra.com':'Josh','jsellers@gomra.com':'Jeff','shopsupport@gomra.com':'Sal','dcooley@gomra.com':'Doug' };
function boardNameFor(){ try{ const em=(SSO&&SSO.email&&SSO.email())||''; if(BOARD_NAME_BY_EMAIL[em]) return BOARD_NAME_BY_EMAIL[em]; return (SSO&&SSO.name&&SSO.name())||CURRENT_USER||''; }catch(e){ return CURRENT_USER||''; } }
const ROLE_BY_NAME = (function(){ const m={}, g={
  admin:['Rich Miller','Al Karloff','Luciana Giglio','Quintin Olivito'], editor:['Megan Fraser','Brandon Choy'],
  design:['Sarah Williams','Mark Mustonen'], exec:['Tony Amato','John Renaud','Gino Bitonti'],
  shopedit:['Cindy Irland','Robin Wheeler'], closer:['Joshua Eberhart','Jeff Sellers'] };
  for(const role in g) g[role].forEach(n=>{ m[_nmKey(n)]=role; }); return m; })();
// CC page visibility per role (maps the classic tabs: floor->home/shop, fleetio->maintenance, mywork->tasks).
const CC_PAGES_BY_ROLE = {
  anon:    ['home','shop'],
  staff:   ['home','shop','tasks','maintenance','tools'],
  closer:  ['home','shop','tasks','maintenance','tools'],
  shopedit:['home','shop','tasks','maintenance','tools'],
  design:  ['home','shop','projects','tasks','maintenance','tools'],
  exec:    ['home','shop','projects','tasks','maintenance','tools','sales'],
  editor:  ['home','shop','projects','tasks','maintenance','tools','sales'],
  admin:   ['home','shop','projects','tasks','maintenance','tools','sales']
};
const MYWORK_EMAILS=['megan.fraser@gomra.com','akarloff@gomra.com','luciana.giglio@gomra.com','bchoy@gomra.com','markm@gomra.com','swilliams@gomra.com','shopsupport@gomra.com','jsellers@gomra.com','jeberhart@gomra.com','dcooley@gomra.com','spearce@gomra.com'];
const MYWORK_NAMES=['Megan Fraser','Al Karloff','Luciana Giglio','Brandon Choy','Mark Mustonen','Sarah Williams','Sal','Jeff Sellers','Joshua Eberhart','Doug Cooley','Stephanie Pearce'].map(_nmKey);
function mwTabAllowed(){ if(!ssoEnforcing()) return true; if(!SSO.user) return false; if(isSuperAdmin()) return true;
  const em=SSO.email(); if(MYWORK_EMAILS.indexOf(em)>=0) return true; return MYWORK_NAMES.indexOf(_nmKey(SSO.name()))>=0; }

const SSO = (function(){
  const TENANT='1dc2dfee-5d93-4f0c-aa97-2344b72fe6b0';
  const CLIENT='fad6a2aa-2dab-4c46-ad3a-29e7040036ae';
  const HOSTS=['mrashopdash.z13.web.core.windows.net'];
  let pca=null, user=null, ready=false, failed=false;
  function active(){ return HOSTS.indexOf(location.hostname)>=0; }
  function domainOK(e){ return /@gomra\.com$/i.test(String(e||'')); }
  function done(){ ready=true; try{ applyRoleUI(); }catch(e){} try{ renderCurrent(); }catch(e){} }
  function loadMsal(cb){ if(window.msal) return cb();
    const urls=['https://alcdn.msftauth.net/browser/2.38.1/js/msal-browser.min.js','https://cdn.jsdelivr.net/npm/@azure/msal-browser@2.38.3/lib/msal-browser.min.js'];
    let i=0; const tryNext=()=>{ if(i>=urls.length){ cb(new Error('msal')); return; } const s=document.createElement('script'); s.async=true; s.src=urls[i++];
      s.onload=()=>{ window.msal?cb():tryNext(); }; s.onerror=tryNext; document.head.appendChild(s); }; tryNext(); }
  function init(){ if(!active()){ done(); return; } let settled=false; const finish=(f)=>{ if(settled) return; settled=true; if(f) failed=true; done(); };
    setTimeout(()=>finish(true), 6000);
    loadMsal(err=>{ if(err || !window.msal){ finish(true); return; }
      try{ pca=new msal.PublicClientApplication({ auth:{ clientId:CLIENT, authority:'https://login.microsoftonline.com/'+TENANT, redirectUri: location.origin+location.pathname }, cache:{ cacheLocation:'localStorage' } });
        pca.handleRedirectPromise().then(resp=>{ if(resp && resp.account) pca.setActiveAccount(resp.account);
          const a=pca.getActiveAccount()||(pca.getAllAccounts()[0]||null);
          if(a){ if(domainOK(a.username)) user=a; else { finish(false); pca.logoutRedirect({account:a}); return; } } finish(false);
        }).catch(()=>finish(false));
      }catch(e){ finish(true); } }); }
  function signIn(){ if(!pca){ if(active()) alert('Sign-in is still loading — one moment, then try again.'); return; }
    try{ pca.loginRedirect({ scopes:['openid','profile','email'] }); }catch(e){ alert('Could not start sign-in: '+(e&&e.message||e)); } }
  function ssoSignOut(){ if(!pca){ return; } const a=pca.getActiveAccount(); user=null; try{ pca.logoutRedirect(a?{account:a}:{}); }catch(e){ try{ applyRoleUI(); }catch(_){} } }
  return { init, signIn, signOut:ssoSignOut, active, email:()=>user?String(user.username||'').toLowerCase():'', name:()=>user?(user.name||user.username||''):'', get user(){return user;}, get ready(){return ready;}, get failed(){return failed;} };
})();
function ssoEnforcing(){ return SSO.active() && SSO.ready && !SSO.failed; }
function ssoRole(){ if(!SSO.active() || SSO.failed) return null; if(!SSO.ready) return 'anon'; if(!SSO.user) return 'anon';
  const em=SSO.email(); if(ROLE_BY_EMAIL[em]) return ROLE_BY_EMAIL[em]; const nk=_nmKey(SSO.name()); if(ROLE_BY_NAME[nk]) return ROLE_BY_NAME[nk]; return 'staff'; }
function ssoCanEdit(){ const r=ssoRole(); return !!(SSO&&SSO.user)&&(r==='admin'||r==='editor'||r==='design'||r==='shopedit'); }
function ssoIsCloser(){ try{ return ssoEnforcing() && !!(SSO&&SSO.user) && ssoRole()==='closer'; }catch(e){ return false; } }
function isSuperAdmin(){ try{ if(!(ssoEnforcing()&&SSO.user)) return false; return SSO.email()==='rmiller@gomra.com' || _nmKey(SSO.name())===_nmKey('Rich Miller'); }catch(e){ return false; } }
function ccAllowedPages(){ const r=ssoRole(); return r?CC_PAGES_BY_ROLE[r]||CC_PAGES_BY_ROLE.staff:null; }
function pageAllowed(name){ if(name==='tasks' && !mwTabAllowed()) return false; const a=ccAllowedPages(); return !a || a.indexOf(name)>=0; }

function ensureAuth(action, retry){ if(CLOSE_PIN) return true;
  if(ssoEnforcing()){ if(ssoCanEdit()){ CLOSE_PIN='1974'; CURRENT_USER=SSO.name()||'Signed in'; syncAuthUI(); _resetIdle(); return true; }
    if(SSO.user){ alert('Your sign-in is view-only — ask Rich if you need edit access.'); return false; } }
  _authRetry=(typeof retry==='function')?retry:null; openSignIn(action||'edit'); return false; }

// Apply the role's page visibility + edit gating (no-op when not enforcing).
function applyRoleUI(){ const enforce=ssoEnforcing();
  document.querySelectorAll('.nav button').forEach(b=>{ b.style.display = pageAllowed(b.dataset.page) ? '' : 'none'; });
  if(enforce && ssoCanEdit() && !CLOSE_PIN){ CLOSE_PIN='1974'; CURRENT_USER=SSO.name()||'Signed in'; }
  document.body.classList.toggle('viewonly', enforce && !ssoCanEdit() && !ssoIsCloser());
  document.body.classList.toggle('closeronly', ssoIsCloser());
  if(!pageAllowed(ACTIVE_PAGE)){ const a=ccAllowedPages()||['home']; showPage(a[0]||'home'); return; }
  syncAuthUI();
}
function syncAuthUI(){ const b=document.getElementById('userBtn'); if(!b) return;
  if(ssoEnforcing()){ if(SSO.user) b.textContent='👤 '+(SSO.name()||'Signed in')+' ▾'; else b.textContent='🔐 Sign in'; return; }
  b.textContent=(CLOSE_PIN?('👤 '+(CURRENT_USER||'Signed in')+' ▾'):'Sign in'); }
let _idleT=null;
function _resetIdle(){ if(_idleT){ clearTimeout(_idleT); _idleT=null; } if(CLOSE_PIN && !ssoEnforcing()) _idleT=setTimeout(()=>{ if(CLOSE_PIN) signOut(); }, 5*60*1000); }
function signOut(){ if(ssoEnforcing() && SSO.user){ SSO.signOut(); return; } CLOSE_PIN=null; CURRENT_USER=''; if(_idleT){ clearTimeout(_idleT); _idleT=null; } syncAuthUI(); renderCurrent(); }

/* ---------- optimistic + reconcile ---------- */
function oJob(proj){ return (D().jobs||[]).find(j=>j.project===proj)||null; }
function oProj(name){ return (D().projects||[]).find(p=>p.name===name)||null; }
function oRecompute(j){ if(j&&j.tasks){ const op=j.tasks.filter(t=>!t.done&&!isSnzRep(t)), dn=j.tasks.filter(t=>t.done);
  j.openCount=op.length; j.doneCount=dn.length; j.openTasks=op.map(t=>t.t); j.doneTasks=dn.map(t=>t.t); } }
function oRecomputeProject(p){ if(p&&p.tasks){ const done=p.tasks.filter(t=>t.done).length; p.doneCount=done; p.taskCount=p.tasks.length;
  p.pct=p.tasks.length?Math.round(done/p.tasks.length*100):0; } }
function oApply(){ markPending(); window._PJBYROW=null; window._PTCOV=null; renderCurrent(); }
const _closedMem={}; function rememberClosed(proj,task){ _closedMem[proj+'|'+task]=Date.now(); }

/* ---------- action call sites ---------- */
// Recurring shop task: closing one spawns the next occurrence (ported from the board).
function nextRepeatISO(rep, fromISO){ const b=parseISO(fromISO)||new Date(); const d=new Date(b.getFullYear(),b.getMonth(),b.getDate());
  if(rep.kind==='daily'){ d.setDate(d.getDate()+1); }
  else if(rep.kind==='weekly'){ const want=(rep.dow!=null?rep.dow:1); do{ d.setDate(d.getDate()+1); }while(d.getDay()!==want); }
  else if(rep.kind==='monthly'){ const dom=d.getDate(); d.setMonth(d.getMonth()+1); if(d.getDate()!==dom) d.setDate(0); }
  else return ''; return localISO(d); }
function spawnRepeat(j,t){ try{ const rep=repeatOf(t&&t.cm); if(!rep||!j||!t) return; const today=todayISO();
  const from=(t.due&&t.due>today)?t.due:today; const nextISO=nextRepeatISO(rep,from); if(!nextISO) return;
  if((j.tasks||[]).some(x=>!x.done && x!==t && x.t===t.t)) return;   // an open copy already exists — never stack
  shopWrite({action:'addTask', project:j.project, jobNum:j.jobNum||'', bay:j.bay||'', task:t.t, assigned:t.who||'', milestone:'', comments:t.cm||'', due:nextISO, pin:CLOSE_PIN||'1974', user:CURRENT_USER});
  if(!j.tasks) j.tasks=[]; j.tasks.push({t:t.t, who:t.who||'', op:localISO(Date.now()), cl:null, st:'Open', done:false, ml:'', cm:t.cm||'', due:nextISO, files:null});
  }catch(e){} }
function _canCloseHere(project, raw){ if(!ssoIsCloser()) return true; const j=oJob(project), t=j&&(j.tasks||[]).find(x=>x.t===raw);
  return !!(t && _whoMatch(t.who, boardNameFor())); }
function closeHandle(project, raw){ if(!raw) return ''; if(WALL) return '';
  if(ssoIsCloser() && !_canCloseHere(project,raw)) return '';   // closer sees ✓ only on their own tasks
  return `<span class="closebtn" data-proj="${escA(project)}" data-task="${escA(raw)}" onclick="closeTaskBtn(this)" title="Mark this task done">✓ close</span>`; }
function closeTaskBtn(el){ closeTaskByName(el.dataset.proj, el.dataset.task, el); }
function closeTaskByName(proj, task, el){
  const _closer=ssoIsCloser();
  if(_closer && !_canCloseHere(proj,task)){ alert('You can only close tasks assigned to you.'); return; }
  if(!_closer){ if(!ensureAuth("close a task", ()=>closeTaskByName(proj,task))) return; }
  const _pin=CLOSE_PIN||(_closer?'1974':''); const _user=CURRENT_USER||boardNameFor()||'';
  const d=new Date(), cd=(d.getMonth()+1)+"/"+d.getDate()+"/"+d.getFullYear();
  if(el){ el.textContent='…'; el.style.pointerEvents='none'; }
  shopWrite({project:proj, task:task, closedDate:cd, pin:_pin, user:_user});
  rememberClosed(proj, task);
  const j=oJob(proj); if(j&&j.tasks){ const t=j.tasks.filter(x=>!x.done&&x.t===task).sort((a,b)=>String(a.due||'9999').localeCompare(String(b.due||'9999')))[0];
    if(t){ t.done=true; t.st='Done'; t.cl=localISO(Date.now()); spawnRepeat(j,t); } oRecompute(j); }
  oApply(); }

function qaReassign(proj, raw, who){ if(!ensureAuth('re-assign a task', ()=>qaReassign(proj,raw,who))) return;
  const j=oJob(proj); const t=j&&(j.tasks||[]).find(x=>x.t===raw); if(!t) return;
  shopWrite({ action:'editTask', project:proj, taskOld:raw, task:raw, assigned:who, status:t.st||'Open',
    milestone:(/yes/i.test(t.ml||'')?'Yes':''), comments:t.cm||'', due:t.due||'', pin:CLOSE_PIN||'1974', user:CURRENT_USER });
  t.who=who; oRecompute(j); oApply(); }

function verifyTask(proj, handle){ const p=oProj(proj); const t=p&&projTaskByAnyId(p,handle); if(!t) return;
  if(!ensureAuth('verify a task', ()=>verifyTask(proj,handle))) return;
  if(!canVerify(proj)){ alert('Only '+((p&&p.pm)||'the PM')+' or admin can verify this.'); return; }
  const d=new Date(), cd=(d.getMonth()+1)+"/"+d.getDate()+"/"+d.getFullYear();
  shopWrite({action:'closeProjectTask', project:proj, id:t.id, _id:(t._id!=null?t._id:undefined), task:t.t, closedDate:cd, pin:CLOSE_PIN||'1974', user:CURRENT_USER});
  t.done=true; t.st='Completed'; if(!t.finISO) t.finISO=localISO(Date.now()); oRecomputeProject(p); oApply(); }
function sendBackTask(proj, handle){ const p=oProj(proj); const t=p&&projTaskByAnyId(p,handle); if(!t) return;
  if(!ensureAuth('send a task back', ()=>sendBackTask(proj,handle))) return;
  if(!canVerify(proj)){ alert('Only '+((p&&p.pm)||'the PM')+' or admin can do this.'); return; }
  shopWrite({action:'reopenProjectTask', project:proj, id:t.id, _id:(t._id!=null?t._id:undefined), task:t.t, pin:CLOSE_PIN||'1974', user:CURRENT_USER});
  t.done=false; t.st='In Progress'; oRecomputeProject(p); oApply(); }
function projTaskByAnyId(p, ref){ if(!p) return null; ref=String(ref);
  return (p.tasks||[]).find(t=>String(t.id)===ref || ('s'+t._id)===ref || String(t._id)===ref)||null; }

/* ---------- shared render primitive: the rich task line ----------
   Used by Shop cards, Floor wall, and My Work so the bells are identical:
   close ✓ · text (Fleetio # clickable) · 🔁 repeat · 📅 due (with struck original) ·
   Fleetio one-line description (expandable) · photo/file thumbs (hover-zoom) ·
   🧑 added-by · 📝 comments · 👤 quick-assign. */
function _dueBadge(t){ const due=t.due; if(!due) return ''; const od=String(due)<todayISO() && !t.done;
  const strike=_due0Strike(t.cm, due); return `<span class="duebadge ${od?'od':''}" title="Due ${escA(fmtMDY(due))}">${strike}${esc(fmtMD(due))}</span>`; }
function taskLineHtml(t, job, opts){ opts=opts||{}; const proj=job.project, raw=t.t; const fnum=_taskFnum(t);
  const cm=_mwCleanCm(t.cm); const canQ=!WALL && opts.assign!==false;
  let title = fnum ? fioTitle('issue', fnum, String(raw).replace(/^\s*\u{1F527}\s*#\d+\s*/u,'').trim()||raw) : esc(raw);
  let h='<div class="ctask'+(t.done?' done':'')+(opts.hot?' hot':'')+'">';
  h+='<div class="ctask-main">';
  h+='<div class="ctask-top">';
  if(!WALL) h+=closeHandle(proj, raw);
  h+='<span class="ctask-t">'+(repeatOf(t.cm)?'<span class="repeat" title="Recurring task">🔁</span> ':'')+title+'</span>';
  h+=_dueBadge(t);
  h+='</div>';
  const det=fnum?fioDetHtml(fnum):''; if(det) h+=det;
  const media=mediaHtml(_taskMedia(t.files, fnum)); if(media) h+=media;
  h+=_byLine(t.cm);
  if(cm) h+='<div class="ccm" title="'+escA(cm)+'">📝 '+esc(cm)+'</div>';
  h+='</div>';
  h+='<div class="ctask-side">';
  const who=t.who||''; if(who) h+='<span class="crewtag" title="Assigned to '+escA(who)+'">'+esc(who)+'</span>';
  if(canQ) h+=' <span class="qa" onclick="qaLine(this,event)" data-proj="'+escA(proj)+'" data-task="'+escA(raw)+'" title="Assign / re-assign">👤</span>';
  h+='</div></div>';
  return h; }

/* ---------- gantt (mockup helper kept verbatim + a dated builder) ---------- */
function gantt(el,rows,labels,cls){ if(!el) return; cls=cls||'';
  el.innerHTML=`<div class="${cls} ghead"><div></div>${labels.map(x=>`<div>${esc(x)}</div>`).join('')}</div>`
    +rows.map(r=>`<div class="${cls} grow"><div class="glabel" title="${escA(r[0])}">${esc(r[0])}</div>`
      +labels.map((_,i)=>`<div>${i==r[1]?`<div class="bar ${r[4]||''}" ${r[5]?`title="${escA(r[5])}"`:''} ${r[6]?`onclick="${r[6]}" style="cursor:pointer;width:${r[2]*100}%"`:`style="width:${r[2]*100}%"`}>${esc(r[3]||'')}</div>`:''}</div>`).join('')
      +`</div>`).join(''); }
// Dated gantt: absolute-positioned bars over a real date horizon (pixel accurate),
// items=[{label,sub,startISO,endISO,color,barLabel,onclick,title,milestones,cls}].
function ganttDates(el, items, opts){ opts=opts||{}; if(!el) return;
  items=(items||[]).filter(x=>x&&x.startISO&&x.endISO);
  if(!items.length){ el.innerHTML='<div class="emptystate">Nothing dated to chart.</div>'; return; }
  const today=todayISO(); let lo=Date.parse(today)-7*DAY, hi=Date.parse(today)+30*DAY;
  items.forEach(x=>{ const s=parseISO(x.startISO), f=parseISO(x.endISO); if(s&&s.getTime()<lo) lo=s.getTime(); if(f&&f.getTime()>hi) hi=f.getTime(); });
  const span=Math.max(DAY*14, hi-lo); const LABELW=opts.labelW||170;
  // month tick columns across the header
  const ticks=[]; let d=new Date(lo); d.setDate(1);
  while(d.getTime()<=hi){ ticks.push(new Date(d)); d.setMonth(d.getMonth()+1); }
  const frac=ms=>clampN((ms-lo)/span,0,1);
  let head=`<div class="gdhead"><div class="gdlabel"></div><div class="gdtrack">`;
  ticks.forEach(t=>{ head+=`<span class="gdtick" style="left:${(frac(t.getTime())*100).toFixed(2)}%">${MONTHS[t.getMonth()]}</span>`; });
  head+=`<span class="gdtoday" style="left:${(frac(Date.parse(today))*100).toFixed(2)}%" title="Today"></span></div></div>`;
  const rows=items.map(x=>{ const s=frac(parseISO(x.startISO).getTime()), e=frac(parseISO(x.endISO).getTime());
    const left=(s*100).toFixed(2), w=(Math.max(0.6,(e-s)*100)).toFixed(2);
    const ms=(x.milestones||[]).filter(m=>m.dateISO).map(m=>`<span class="gdmile" style="left:${(frac(parseISO(m.dateISO).getTime())*100).toFixed(2)}%" title="◆ ${escA(m.name+' · '+fmtMDY(m.dateISO))}"></span>`).join('');
    return `<div class="gdrow ${x.cls||''}"><div class="gdlabel" title="${escA(x.label)}">${esc(x.label)}${x.sub?`<span class="gdsub">${esc(x.sub)}</span>`:''}</div>`
      +`<div class="gdtrack"><span class="gdtoday" style="left:${(frac(Date.parse(today))*100).toFixed(2)}%"></span>${ms}`
      +`<div class="gdbar" style="left:${left}%;width:${w}%;background:${x.color||'#2166f3'}" ${x.onclick?`onclick="${x.onclick}"`:''} title="${escA(x.title||(x.label+' · '+fmtMDY(x.startISO)+' → '+fmtMDY(x.endISO)))}">${esc(x.barLabel||'')}</div></div></div>`; });
  el.innerHTML=head+rows.join(''); }

/* ---------- quick-assign popover ---------- */
function qaLine(el,ev){ const proj=el.dataset.proj, raw=el.dataset.task;
  if(!ensureAuth('re-assign a task', ()=>qaOpen(null, w=>qaReassign(proj,raw,w)))) return;
  qaOpen(ev, w=>qaReassign(proj,raw,w)); }
let _qaCb=null;
function qaOpen(ev, cb){ _qaCb=cb; let pop=document.getElementById('qaPop');
  if(!pop){ pop=document.createElement('div'); pop.id='qaPop'; pop.className='qapop'; document.body.appendChild(pop); }
  pop.innerHTML=ASSIGNEE_OPTIONS.map(n=>`<button onclick="qaPick('${escJsAttr(n)}')">${esc(n)}</button>`).join('')
    +`<div class="qaother"><input id="qaOther" placeholder="Type a name…" onkeydown="if(event.key==='Enter')qaGoOther()"><button onclick="qaGoOther()">➤</button></div>`;
  pop.style.display='block';
  const x=ev?Math.min(ev.clientX, innerWidth-220):innerWidth/2-100, y=ev?Math.min(ev.clientY+8, innerHeight-260):120;
  pop.style.left=Math.max(8,x)+'px'; pop.style.top=Math.max(8,y)+'px';
  setTimeout(()=>document.addEventListener('click', qaAway, {once:true}),0); }
function qaAway(e){ const pop=document.getElementById('qaPop'); if(pop && !pop.contains(e.target)) pop.style.display='none'; else if(pop) setTimeout(()=>document.addEventListener('click',qaAway,{once:true}),0); }
function qaPick(n){ const pop=document.getElementById('qaPop'); if(pop) pop.style.display='none'; if(_qaCb) _qaCb(n); }
function qaGoOther(){ const v=(document.getElementById('qaOther')||{}).value||''; if(!v.trim()) return; qaPick(v.trim()); }

/* ============================================================================
   MODALS: sign-in, add task, edit task
   ============================================================================ */
function _modal(id){ let m=document.getElementById(id); if(!m){ m=document.createElement('div'); m.id=id; m.className='modal'; document.body.appendChild(m); } return m; }
function closeModal(id){ const m=document.getElementById(id); if(m) m.classList.remove('open'); }

function openSignIn(action){ const m=_modal('signInModal'); const enforce=ssoEnforcing();
  m.innerHTML=`<div class="modalbox"><div class="cardhead"><h2>Sign in</h2><button class="btn" onclick="closeModal('signInModal')">Close</button></div>
    ${enforce?`<p class="muted">Sign in with your @gomra.com account to ${esc(action||'edit')}. (Shared shop screens can use the code below.)</p>
      <button class="btn primary" style="width:100%;background:#1a56db;border-color:#1a56db" onclick="SSO.signIn()">🔐 Sign in with Microsoft</button>
      <div style="text-align:center;color:var(--muted);margin:10px 0;font-size:12px">— or shared-screen code —</div>`
      :`<p class="muted">Enter your code to ${esc(action||'make changes')}.</p>`}
    <input id="siCode" type="password" inputmode="numeric" placeholder="Code" style="width:100%;padding:11px;border:1px solid var(--line);border-radius:9px;font-size:18px;letter-spacing:3px" onkeydown="if(event.key==='Enter')siSubmit()">
    <div id="siErr" class="muted" style="color:var(--red);min-height:18px;margin:6px 2px"></div>
    <button class="btn primary" style="width:100%" onclick="siSubmit()">Sign in with code</button></div>`;
  m.classList.add('open'); setTimeout(()=>{ const i=document.getElementById('siCode'); if(i) i.focus(); },60); }
function siSubmit(){ const code=((document.getElementById('siCode')||{}).value||'').trim(); if(!code){ const e=document.getElementById('siErr'); if(e) e.textContent='Enter your code.'; return; }
  const name=findUser(code);
  if(name==null){ const e=document.getElementById('siErr'); if(e) e.textContent='That code was not recognized.'; return; }
  CLOSE_PIN=code; CURRENT_USER=name; syncAuthUI(); _resetIdle(); closeModal('signInModal');
  try{ prwRetry(); }catch(e){}   // flush stranded edits the moment someone authenticates
  const r=_authRetry; _authRetry=null; if(typeof r==='function'){ try{ r(); }catch(e){} } else renderCurrent(); }

// Add / edit shop task modal (shared shell).
let _etCtx=null;
function openAddTask(job){ if(!ensureAuth('add a task', ()=>openAddTask(job))) return; _etCtx={mode:'add', job:job};
  _taskModal('Add task to '+(job?job.project:''), {task:'',who:'',due:'',cm:'',status:'Open',ml:''}); }
function openEditTaskModal(job, t){ if(!ensureAuth('edit a task', ()=>openEditTaskModal(job,t))) return;
  _etCtx={mode:'edit', job:job, t:t, old:t.t};
  _taskModal('Edit task', {task:t.t, who:t.who||'', due:t.due||'', cm:stripDue0(stripBy(stripRepeat(t.cm))), status:t.st||'Open', ml:(/yes/i.test(t.ml||'')?'Yes':''), rep:_repVal(t.cm)}); }
function _taskModal(title, v){ const m=_modal('taskModal'); const isEdit=_etCtx&&_etCtx.mode==='edit';
  m.innerHTML=`<div class="modalbox"><div class="cardhead"><h2>${esc(title)}</h2><button class="btn" onclick="closeModal('taskModal')">Close</button></div>
    <label class="fld"><span>Task</span><input id="etTask" value="${escA(v.task)}"></label>
    <label class="fld"><span>Assigned to</span><input id="etWho" list="asgNames" value="${escA(v.who)}" placeholder="Sal, Doug, Wrap Team…"></label>
    <label class="fld"><span>Due</span><input id="etDue" type="date" value="${escA(v.due)}">
      <span class="pushbar"><button class="btn" onclick="etPushDue(7)">+1wk</button><button class="btn" onclick="etPushDue(14)">+2wk</button><button class="btn" onclick="etPushDue(30)">+1mo</button></span></label>
    ${isEdit?`<label class="fld"><span>Status</span><select id="etStatus"><option${/open/i.test(v.status)?' selected':''}>Open</option><option${/progress/i.test(v.status)?' selected':''}>In Progress</option><option${_doneStatus(v.status)?' selected':''}>Done</option></select></label>`:''}
    <label class="fld"><span>Repeat</span><select id="etRep"><option value="">None</option><option value="daily"${v.rep==='daily'?' selected':''}>Daily</option><option value="weekly:1"${/^weekly/.test(v.rep||'')?' selected':''}>Weekly</option><option value="monthly"${v.rep==='monthly'?' selected':''}>Monthly</option></select>
      <label class="ck"><input type="checkbox" id="etMl" ${/yes/i.test(v.ml)?'checked':''}> Milestone</label></label>
    <label class="fld"><span>Comments</span><textarea id="etCm" rows="2">${esc(v.cm)}</textarea></label>
    <datalist id="asgNames">${_asgNamesOpts()}</datalist>
    <div style="display:flex;gap:8px;margin-top:12px">${isEdit?`<button class="btn danger" onclick="submitDeleteTask()">🗑 Delete</button>`:''}<button class="btn primary" style="flex:1" onclick="submitTaskModal()">${isEdit?'Save':'Add task'}</button></div></div>`;
  m.classList.add('open'); setTimeout(()=>{ const i=document.getElementById('etTask'); if(i) i.focus(); },60); }
function _asgNamesOpts(){ const s=new Set(ASSIGNEE_OPTIONS); (D().jobs||[]).forEach(j=>(j.tasks||[]).forEach(t=>{ if(t.who) String(t.who).split(/\s*\/\s*/).forEach(w=>s.add(w.trim())); }));
  return [...s].filter(Boolean).map(n=>`<option value="${escA(n)}">`).join(''); }
function submitTaskModal(){ const job=_etCtx.job; const task=(document.getElementById('etTask')||{}).value.trim(); if(!task){ alert('Enter a task.'); return; }
  const who=(document.getElementById('etWho')||{}).value.trim(); const due=(document.getElementById('etDue')||{}).value||'';
  const rep=(document.getElementById('etRep')||{}).value||''; const ml=(document.getElementById('etMl')||{}).checked?'Yes':'';
  const cmBox=(document.getElementById('etCm')||{}).value||'';
  if(_etCtx.mode==='add'){ const cm=_withRepeat(cmBox, rep);
    shopWrite({action:'addTask', project:job.project, jobNum:job.jobNum||'', bay:job.bay||'', task:task, assigned:who, milestone:ml, comments:cm, due:due, pin:CLOSE_PIN||'1974', user:CURRENT_USER});
    const tobj={t:task, who:who, op:localISO(Date.now()), cl:null, st:'Open', done:false, ml:ml, cm:_withBy(cm,CURRENT_USER), due:due||null, files:null};
    if(!job.tasks) job.tasks=[]; job.tasks.push(tobj); oRecompute(job);
  } else { const t=_etCtx.t; const status=(document.getElementById('etStatus')||{}).value||'Open';
    const keepBy=_taskBy(t.cm); const keepD0=_taskDue0(t.cm) || ((t.due && due && due>t.due)?t.due:'');
    const cm=_withDue0(_withBy(_withRepeat(cmBox, rep), keepBy), keepD0);
    shopWrite({action:'editTask', project:job.project, taskOld:_etCtx.old, task:task, assigned:who, status:status, milestone:ml, comments:cm, due:due, pin:CLOSE_PIN||'1974', user:CURRENT_USER});
    t.t=task; t.who=who; t.st=status; t.ml=ml; t.cm=cm; t.due=due||null; if(_doneStatus(status)){ t.done=true; t.cl=localISO(Date.now()); } oRecompute(job); }
  closeModal('taskModal'); oApply(); }
function submitDeleteTask(){ if(!_etCtx||_etCtx.mode!=='edit') return; if(!confirm('Delete this task?')) return; const job=_etCtx.job, t=_etCtx.t;
  shopWrite({action:'deleteTask', project:job.project, task:_etCtx.old, pin:CLOSE_PIN||'1974', user:CURRENT_USER});
  job.tasks=(job.tasks||[]).filter(x=>x!==t); oRecompute(job); closeModal('taskModal'); oApply(); }
function etPushDue(days){ const el=document.getElementById('etDue'); if(!el) return; const base=el.value||todayISO(); el.value=_isoAddDays(base, days); }

// Job editor — move bay / dates / status / PM / notes (real editJob write).
const BAY_OPTIONS=['Bay 2 Front','Bay 2 Back / Loading Dock','Bay 3 Front','Bay 3 Middle','Bay 3 Back','Bay 4 Front','Bay 4 Middle','Bay 4 Back','Bay 5 Front','Bay 5 Back','Parking Lot','Next Up','On Hold','On Hold/Off-Site','Off Site / Parts','General'];
const STATUS_OPTIONS=['Active','Scheduled','On Hold','TBD','Shipped'];
let _jeJob=null;
function openJobEditor(row){ const job=(D().jobs||[]).find(j=>String(j.row)===String(row)); if(!job) return;
  if(!ensureAuth('edit this job', ()=>openJobEditor(row))) return; _jeJob=job; const m=_modal('jobModal');
  const bayOpts=BAY_OPTIONS.map(b=>`<option${b===job.bay?' selected':''}>${esc(b)}</option>`).join('')+(BAY_OPTIONS.indexOf(job.bay)<0&&job.bay?`<option selected>${esc(job.bay)}</option>`:'');
  const stOpts=STATUS_OPTIONS.map(s=>`<option${s===job.status?' selected':''}>${esc(s)}</option>`).join('')+(STATUS_OPTIONS.indexOf(job.status)<0&&job.status?`<option selected>${esc(job.status)}</option>`:'');
  m.innerHTML=`<div class="modalbox"><div class="cardhead"><h2>${esc(job.project)}${job.jobNum?' · '+esc(job.jobNum):''}</h2><button class="btn" onclick="closeModal('jobModal')">Close</button></div>
    <div class="tdmeta"><label class="fld"><span>Bay</span><select id="jeBay">${bayOpts}</select></label>
    <label class="fld"><span>Status</span><select id="jeStatus">${stOpts}</select></label>
    <label class="fld"><span>Start</span><input id="jeStart" type="date" value="${escA(job.startISO||'')}"></label>
    <label class="fld"><span>Finish</span><input id="jeFinish" type="date" value="${escA(job.completionISO||'')}"></label>
    <label class="fld"><span>PM</span><input id="jePM" value="${escA(job.pm||'')}"></label>
    <label class="fld"><span>Client</span><input id="jeClient" value="${escA(job.client||'')}"></label></div>
    <label class="fld"><span>Notes</span><textarea id="jeNotes" rows="2">${esc(job.notesRaw||'')}</textarea></label>
    <button class="btn primary" style="width:100%;margin-top:10px" onclick="submitJobEditor()">Save</button></div>`;
  m.classList.add('open'); }
function submitJobEditor(){ const j=_jeJob; if(!j) return; const bay=(document.getElementById('jeBay')||{}).value||j.bay;
  const status=(document.getElementById('jeStatus')||{}).value||j.status; const start=(document.getElementById('jeStart')||{}).value||'';
  const finish=(document.getElementById('jeFinish')||{}).value||''; const pm=(document.getElementById('jePM')||{}).value||'';
  const client=(document.getElementById('jeClient')||{}).value||''; const notes=(document.getElementById('jeNotes')||{}).value||'';
  shopWrite({action:'editJob', project:j.project, bay:bay, status:status, start:start, finish:finish, pm:pm, client:client, notes:notes, pin:CLOSE_PIN||'1974', user:CURRENT_USER});
  j.bay=bay; j.status=status; j.startISO=start||null; j.completionISO=finish||null; j.pm=pm; j.client=client; j.notesRaw=notes;
  closeModal('jobModal'); oApply(); }
window.openJobEditor=openJobEditor;

/* ============================================================================
   ROUTER + theme + floor + init
   ============================================================================ */
let WALL=false;
function renderCurrent(){ const pg=window.MRA_PAGES[ACTIVE_PAGE]; if(pg && typeof pg.render==='function'){ try{ pg.render(); }catch(e){ console.error('page render failed',ACTIVE_PAGE,e); } } }
function showPage(name){ if(!window.MRA_PAGES[name]) name='home';
  if(!pageAllowed(name)){ const a=ccAllowedPages()||['home']; name=(a.indexOf(name)>=0)?name:(a[0]||'home'); }
  ACTIVE_PAGE=name;
  document.querySelectorAll('.nav button').forEach(b=>b.classList.toggle('active', b.dataset.page===name));
  document.querySelectorAll('.page').forEach(s=>s.classList.toggle('active', s.id===name));
  const cr=document.querySelector('.crumb'); if(cr){ const b=document.querySelector('.nav button[data-page="'+name+'"]'); cr.textContent=b?b.textContent.trim():name; }
  document.body.classList.toggle('home-mode', name==='home');
  try{ const u=new URL(location.href); u.searchParams.set('view',name); history.replaceState(null,'',u); }catch(e){}
  window.scrollTo(0,0); renderCurrent(); }

function toggleTheme(){ const dark=document.body.classList.toggle('dark'); const b=document.getElementById('theme'); if(b) b.textContent=dark?'☀ Light':'☾ Dark';
  try{ localStorage.setItem('cc_theme', dark?'dark':'light'); }catch(e){} }
function openFloor(){ const f=document.getElementById('floor'); if(!f) return; WALL=true; if(window.MRA_PAGES.floor) window.MRA_PAGES.floor.render(); f.classList.add('open'); }
function closeFloor(){ const f=document.getElementById('floor'); if(f) f.classList.remove('open'); WALL=false; }

function initCC(){
  // theme
  try{ if(localStorage.getItem('cc_theme')==='dark'){ document.body.classList.add('dark'); const b=document.getElementById('theme'); if(b) b.textContent='☀ Light'; } }catch(e){}
  // nav
  document.querySelectorAll('.nav button').forEach(b=>b.onclick=()=>showPage(b.dataset.page));
  const th=document.getElementById('theme'); if(th) th.onclick=toggleTheme;
  const q=document.getElementById('quick'); const qb=document.getElementById('quickBtn'); if(qb&&q) qb.onclick=()=>q.classList.toggle('open');
  const fo=document.getElementById('floorOpen'); if(fo) fo.onclick=openFloor;
  const fc=document.getElementById('floorClose'); if(fc) fc.onclick=closeFloor;
  const ub=document.getElementById('userBtn'); if(ub) ub.onclick=()=>{
    if(ssoEnforcing()){ if(SSO.user){ if(confirm('Sign out '+(SSO.name()||'')+'?')) SSO.signOut(); } else SSO.signIn(); return; }
    if(CLOSE_PIN){ if(confirm('Sign out '+(CURRENT_USER||'')+'?')) signOut(); } else openSignIn('sign in'); };
  document.addEventListener('keydown',e=>{ if(e.key==='Escape'){ if(document.getElementById('floor')&&document.getElementById('floor').classList.contains('open')) closeFloor(); document.querySelectorAll('.modal.open').forEach(m=>m.classList.remove('open')); } });
  ['mousemove','keydown','click','touchstart'].forEach(ev=>document.addEventListener(ev,_resetIdle,{passive:true}));
  syncAuthUI();
  // deep-link ?view=
  let start='home'; try{ const v=new URL(location.href).searchParams.get('view'); if(v && window.MRA_PAGES[v]) start=v; }catch(e){}
  showPage(start);
  try{ SSO.init(); }catch(e){}   // Microsoft sign-in + role gating (fail-open off the live host)
  setInterval(pollData, 60000);
}
if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', initCC); else initCC();
