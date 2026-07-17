/* My Work — per-person one-pager: overdue / due / awaiting sign-off / my projects
   / milestones / completed, plus team workload. Person picker for admins. */
(function(){
  let WHO=null;
  window.mwSetWho=function(v){ WHO=v; render(); };
  window.mwGo=function(kind,ref){ if(kind==='shop') goShopJob(ref); else if(kind==='proj') openProjectEditor(ref); };
  window.mwTile=function(id){ const el=document.getElementById(id); if(el) el.scrollIntoView({behavior:'smooth',block:'start'}); };

  function nmKey(s){ return String(s||'').toLowerCase().replace(/[^a-z]/g,''); }
  function whoMatch(who, name){ if(!who||!name) return false; const parts=crewWhoList(who).map(nmKey); const n=nmKey(name), f=nmKey(name.split(' ')[0]);
    return parts.some(p=>p===n||p===f||(p&&n&&(p.indexOf(n)>=0||n.indexOf(p)>=0))); }

  function myWorkFor(name){ const today=todayISO(); const od=[], due=[], later=[], doneRecent=[], awaitingMe=[], pendingMine=[], ms=[];
    const wk=_isoAddDays(today,7), m30=_isoAddDays(today,30), ago7=_isoAddDays(today,-7);
    (D().jobs||[]).forEach(j=>{ if(!isLive(j)) return; (j.tasks||[]).forEach(t=>{ if(isSalesT(t)||isSnzRep(t)) return; if(!whoMatch(t.who,name)) return;
      const item={kind:'shop', ref:j.row, t:t, job:j, who:t.who, due:t.due, text:t.t};
      if(t.done){ if(t.cl&&t.cl>=ago7) doneRecent.push(item); return; }
      if(t.due&&t.due<today) od.push(item); else if(t.due&&t.due<=wk) due.push(item); else later.push(item); }); });
    (D().projects||[]).forEach(p=>{ (p.tasks||[]).forEach(t=>{
      if(projIsPendingVerify(t)){ if(canVerify(p.name)) awaitingMe.push({p,t}); if(whoMatch(t.who,name)) pendingMine.push({p,t}); return; }
      if(!whoMatch(t.who,name)) return; const item={kind:'proj', ref:p.name, t:t, proj:p, who:t.who, due:t.finISO, text:t.t};
      if(t.done){ if(t.finISO&&t.finISO>=ago7) doneRecent.push(item); return; }
      if(t.finISO&&t.finISO<today) od.push(item); else if(t.finISO&&t.finISO<=wk) due.push(item); else later.push(item); }); });
    const myProjects=(D().projects||[]).filter(p=>whoMatch(p.pm,name)).sort((a,b)=>HEALTH_RANK[projHealth(a).state]-HEALTH_RANK[projHealth(b).state]);
    myProjects.forEach(p=>(p.milestones||[]).forEach(mm=>{ if(!mm.done&&mm.dateISO>=today&&mm.dateISO<=m30) ms.push({p,m:mm}); }));
    od.sort(byDue); due.sort(byDue);
    return {od,due,later,doneRecent,awaitingMe,pendingMine,myProjects,ms}; }
  function byDue(a,b){ return String(a.due||'9999').localeCompare(String(b.due||'9999')); }

  function itemRow(x){ if(x.kind==='shop') return `<div class="mwrow click" onclick="mwGo('shop','${escA(x.ref)}')" title="Open ${escA(x.job.project)}">${taskLineInner(x)}</div>`;
    return `<div class="mwrow click" onclick="mwGo('proj','${escJsAttr(x.ref)}')" title="Open ${escA(x.proj.name)}">${taskLineInner(x)}</div>`; }
  function taskLineInner(x){ const t=x.t, od=x.due&&String(x.due)<todayISO()&&!t.done; const fnum=x.kind==='shop'?_taskFnum(t):'';
    const cm=_mwCleanCm(t.cm); const where=x.kind==='shop'?(x.job.jobNum||x.job.project):x.proj.name;
    let h=`<div class="mwrow-main"><div class="mwrow-top"><span class="ic">${x.kind==='shop'?'🔧':'📋'}</span><b>${esc(_mwCleanCm(t.t)||t.t)}</b>${x.due?`<span class="duebadge ${od?'od':''}">${_due0Strike(t.cm,x.due)}${esc(fmtMD(x.due))}</span>`:''}</div>
      <div class="muted mwrow-sub">${esc(where)}${x.kind==='proj'&&t.phase?' · '+esc(t.phase):''}${x.kind==='proj'&&x.t.startISO?' · ▶ '+esc(fmtMD(x.t.startISO)):''}</div>`;
    const det=fnum?fioDetHtml(fnum):''; if(det) h+=det; const media=x.kind==='shop'?mediaHtml(_taskMedia(t.files,fnum)):''; if(media) h+=media;
    h+=_byLine(t.cm); if(cm) h+=`<div class="ccm">📝 ${esc(cm)}</div>`; h+='</div>';
    h+='<span class="chev">›</span>'; return h; }

  function section(id,title,items,extra){ if(!items.length) return ''; return `<div class="card" id="${id}"><div class="cardhead"><h2>${title}</h2><span class="crewtag">${items.length}</span></div>${items.map(itemRow).join('')}${extra||''}</div>`; }

  function render(){ const sec=document.getElementById('tasks'); if(!sec) return;
    // person list
    const names=new Set(); if(CURRENT_USER) names.add(CURRENT_USER); ASSIGNEE_OPTIONS.forEach(n=>names.add(n));
    (D().projects||[]).forEach(p=>{ if(p.pm) names.add(p.pm); });
    (D().users||[]).forEach(u=>{ if(u.name) names.add(u.name); });
    const person=WHO||CURRENT_USER||[...names][0]||'Sal';
    const w=myWorkFor(person);
    const openN=w.od.length+w.due.length+w.later.length;
    const tiles=[['mwsec-od','Overdue',w.od.length,'danger'],['mwsec-due','Due this week',w.due.length,''],['mwsec-verify','To verify',w.awaitingMe.length,''],['mwsec-pend','Marked ready',w.pendingMine.length,''],['mwsec-proj','My projects',w.myProjects.length,''],['','Open',openN,'']];
    const pickOpts=[...names].filter(Boolean).sort().map(n=>`<option${n===person?' selected':''}>${esc(n)}</option>`).join('');

    const awaitingHtml = w.awaitingMe.length?`<div class="card" id="mwsec-verify"><div class="cardhead"><h2>✅ Awaiting your sign-off</h2><span class="crewtag">${w.awaitingMe.length}</span></div>
      ${w.awaitingMe.map(x=>`<div class="highlight"><div><b>${esc(x.t.t)}</b><div class="muted">${esc(x.p.name)}${_taskBy(x.t.cm)?' · marked by '+esc(_taskBy(x.t.cm)):''}</div></div>
        <button class="btn primary" onclick="verifyTask('${escJsAttr(x.p.name)}','${escJsAttr(projTaskHandle(x.t))}')">✓ Verify</button>
        <button class="btn" onclick="sendBackTask('${escJsAttr(x.p.name)}','${escJsAttr(projTaskHandle(x.t))}')">↩ Back</button></div>`).join('')}</div>`:'';
    const projHtml = w.myProjects.length?`<div class="card" id="mwsec-proj"><div class="cardhead"><h2>📊 My Projects</h2><span class="crewtag">${w.myProjects.length}</span></div>
      ${w.myProjects.map(p=>{ const h=projHealth(p), b=_pmtBehindBits(p); const c=HEALTH_COLOR[h.state];
        return `<div class="mwrow click" onclick="mwGo('proj','${escJsAttr(p.name)}')"><div class="mwrow-main"><div class="mwrow-top"><span class="hchip" style="background:${c}22;color:${c}">${HEALTH_LABEL[h.state]}</span><b>${esc(p.name)}</b><span class="crewtag">${p.pct}%</span></div>
        <div class="muted mwrow-sub">${p.finishISO?'target '+esc(fmtMDY(p.finishISO)):''}${b.odN?' · ⚠ '+b.odN+' past-due'+(b.whoTxt?' (with '+esc(b.whoTxt)+')':''):''}</div></div><span class="chev">›</span></div>`; }).join('')}</div>`:'';
    const msHtml = w.ms.length?`<div class="card"><div class="cardhead"><h2>◆ Milestones (30d)</h2><span class="crewtag">${w.ms.length}</span></div>
      ${w.ms.map(x=>`<div class="taskrow"><div><b>◆ ${esc(x.m.name)}</b><div class="muted">${esc(x.p.name)}</div></div><span class="duebadge">${esc(fmtMD(x.m.dateISO))}</span></div>`).join('')}</div>`:'';

    // team workload
    const load={}; (D().jobs||[]).forEach(j=>{ if(!jobIsActiveLane(j)) return; openTasksOf(j).forEach(t=>crewWhoList(t.who).forEach(c=>load[c]=(load[c]||0)+1)); });
    (D().projects||[]).forEach(p=>(p.tasks||[]).forEach(t=>{ if(t.done) return; crewWhoList(t.who).forEach(c=>load[c]=(load[c]||0)+1); }));
    const team=Object.keys(load).sort((a,b)=>load[b]-load[a]).slice(0,14);
    const maxL=Math.max(1,...team.map(c=>load[c]));

    sec.innerHTML=`<div class="head"><div><h1>My Work</h1><div class="muted">Everything on ${esc(person)}'s plate.</div></div>
      <select class="btn" onchange="mwSetWho(this.value)">${pickOpts}</select></div>
    <div class="grid kpis" style="grid-template-columns:repeat(6,1fr)">${tiles.map(t=>`<div class="card click" ${t[0]?`onclick="mwTile('${t[0]}')"`:''}><span class="muted">${t[1]}</span><div class="num ${t[3]}">${t[2]}</div></div>`).join('')}</div>
    ${awaitingHtml}
    ${section('mwsec-od','⚠ Overdue',w.od)}
    ${section('mwsec-due','📅 Due this week',w.due)}
    ${w.pendingMine.length?`<div class="card" id="mwsec-pend"><div class="cardhead"><h2>🟡 Marked ready (awaiting PM)</h2><span class="crewtag">${w.pendingMine.length}</span></div>${w.pendingMine.map(x=>`<div class="taskrow click" onclick="mwGo('proj','${escJsAttr(x.p.name)}')"><b>${esc(x.t.t)}</b><span class="muted">${esc(x.p.name)}</span></div>`).join('')}</div>`:''}
    ${projHtml}
    ${msHtml}
    ${section('mwsec-later','Everything else',w.later.slice(0,20), w.later.length>20?`<div class="muted" style="padding:8px">+${w.later.length-20} more…</div>`:'')}
    ${w.doneRecent.length?`<div class="card"><div class="cardhead"><h2>✅ Completed (7d)</h2><span class="crewtag">${w.doneRecent.length}</span></div>${w.doneRecent.slice(0,12).map(x=>`<div class="taskrow"><b>${esc(_mwCleanCm(x.t.t)||x.t.t)}</b><span class="muted">${esc(x.kind==='shop'?(x.job.jobNum||x.job.project):x.proj.name)}</span></div>`).join('')}</div>`:''}
    <div class="card"><div class="cardhead"><h2>Team Workload</h2><span class="muted">Open items per crew/person</span></div>
      ${team.map(c=>`<div class="teamrow"><div><b>${esc(c)}</b></div><div class="loadbar"><i style="width:${Math.round(load[c]/maxL*100)}%"></i></div><span class="crewtag">${load[c]}</span></div>`).join('')||'<div class="emptystate">No open work.</div>'}</div>`;
  }
  window.MRA_PAGES.tasks={render:render};
})();
