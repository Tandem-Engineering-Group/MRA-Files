/* Shop — the working board: bay cards with full task bells, parking, on-hold,
   task bubbles (by job / by assignee), highlighted/risk, bay-calendar gantt. */
(function(){
  let SORT='job';           // task-bubble grouping
  let CAL='month';          // bay-calendar range
  const OPEN=new Set();     // remembered-open held/parking sections (per render)

  function schedLine(r){ const od=r.fin&&String(r.fin)<todayISO();
    return `<div class="ctask sched click" onclick="openProjectEditor('${escJsAttr(r.proj)}')" title="Open ${escA(r.proj)} schedule">
      <div class="ctask-main"><div class="ctask-top"><span class="tag project">📋</span>
        <span class="ctask-t">${esc(r.t)}</span>${r.pv?'<span class="badge">🟡 awaiting verify</span>':''}
        ${(r.st0||r.fin)?`<span class="duebadge ${od?'od':''}">${r.st0?'▶ '+esc(fmtMD(r.st0)):''}${r.fin?' → '+esc(fmtMD(r.fin)):''}</span>`:''}</div></div>
      <div class="ctask-side"><span class="crewtag">${esc(r.who)}</span></div></div>`; }

  function bayCard(j, pos){
    const k=kindOf(j), pct=jobPct(j), open=openTasksOf(j), mra=fioMraRange(j);
    const tasks=open.map(t=>taskLineHtml(t, j)).join('');
    const sched=_projTasksForJob(j).map(schedLine).join('');
    const done=(j.tasks||[]).filter(t=>t.done).length;
    return `<div class="slot detail click ${pos==='Back'?'back':''}" id="job-${escA(j.row)}">
      <div class="between"><span class="pos">${esc(pos)}</span><span class="tag ${k}">${KIND_LABEL[k]}</span></div>
      <div class="job">${esc(j.project)}${j.jobNum?` <span class="fnum">${esc(j.jobNum)}</span>`:''}${jobIsSub(j)?' <span class="badge" title="Sub-job — shares a J#">🧩</span>':''}</div>
      <div class="pctline"><span>${esc(j.client||'')}${j.pm?' · PM '+esc(j.pm):''}</span><span>${open.length} open · ${done} done</span></div>
      ${mra||locChip(j)?`<div class="chips">${mra?`<span class="pill" title="Fleetio: back to MRA → leaving">${esc(mra)}</span>`:''}${locChip(j)}</div>`:''}
      <div class="progress"><span style="width:${pct}%"></span></div>
      <div class="ctasks">${tasks||'<div class="muted" style="padding:6px 0;font-size:12px">No open tasks.</div>'}${sched}</div>
      <div class="actions"><button class="btn" onclick="event.stopPropagation();openJobEditor('${escA(j.row)}')">✎ Edit job</button>
        <button class="btn" onclick="event.stopPropagation();addTaskTo('${escA(j.row)}')">➕ Task</button></div></div>`;
  }
  function addTaskTo(row){ const j=(D().jobs||[]).find(x=>String(x.row)===String(row)); if(j) openAddTask(j); }
  window.addTaskTo=addTaskTo;

  function parkCard(j){ const k=kindOf(j), open=openTasksOf(j);
    return `<div class="parking click" id="job-${escA(j.row)}" onclick="openJobEditor('${escA(j.row)}')" title="Edit ${escA(j.project)}">
      <div class="between"><b>${esc(j.project)}</b><span class="tag ${k}">${KIND_LABEL[k]}</span></div>
      <div class="muted">${j.jobNum?esc(j.jobNum)+' · ':''}${open.length} open${j.pm?' · '+esc(j.pm):''}</div>
      ${locChip(j)?`<div class="chips">${locChip(j)}</div>`:''}
      ${open.slice(0,3).map(t=>`<div class="miniline">• ${esc(_mwCleanCm(t.t)||t.t)}${t.who?` <span class="crewtag">${esc(t.who)}</span>`:''}</div>`).join('')}</div>`; }

  function setSort(v){ SORT=v; window.MRA_PAGES.shop.render(); }
  function setCal(v){ CAL=v; drawCal(); }
  window.shopSetSort=setSort; window.shopSetCal=setCal;

  function bubbles(){
    // active-lane open shop tasks
    const items=[]; (D().jobs||[]).forEach(j=>{ if(!jobIsActiveLane(j)) return; openTasksOf(j).forEach(t=>{ if(isSalesT(t)) return; items.push({j,t}); }); });
    const g={};
    if(SORT==='job'){ items.forEach(x=>{ const k=x.j.project; (g[k]=g[k]||{sub:x.j.jobNum||'',rows:[]}).rows.push(x); }); }
    else { items.forEach(x=>{ crewWhoList(x.t.who).forEach(w=>{ (g[w]=g[w]||{sub:'',rows:[]}).rows.push(x); }); if(!x.t.who){ (g['— unassigned —']=g['— unassigned —']||{sub:'',rows:[]}).rows.push(x); } }); }
    const keys=Object.keys(g).sort((a,b)=>g[b].rows.length-g[a].rows.length||a.localeCompare(b));
    if(!keys.length) return '<div class="emptystate">No open shop tasks.</div>';
    return keys.map(k=>`<div class="bubble"><div class="bubblehead"><b>${esc(k)}</b>${g[k].sub?` <span class="fnum">${esc(g[k].sub)}</span>`:''} <span class="crewtag">${g[k].rows.length}</span></div>
      ${g[k].rows.map(x=>`<div class="bubbletask">${taskLineHtml(x.t, x.j)}${SORT==='job'?'':`<div class="muted" style="font-size:11px">${esc(x.j.project)}</div>`}</div>`).join('')}</div>`).join('');
  }

  function drawCal(){ const el=document.getElementById('bayGantt'); if(!el) return;
    const jobs=(D().jobs||[]).filter(j=>jobIsActiveLane(j)&&j.startISO&&j.completionISO);
    const items=jobs.map(j=>({label:(bayNumOf(j.bay)?'Bay '+bayNumOf(j.bay)+' · ':'')+j.project, sub:j.jobNum||'', startISO:j.startISO, endISO:j.completionISO,
      color:HEALTH_COLOR[projHealthForJob(j)]||'#2166f3', onclick:`goShopJob('${escA(j.row)}')`, title:j.project+' · '+fmtMDY(j.startISO)+' → '+fmtMDY(j.completionISO)}));
    ganttDates(el, items, {labelW:180});
    document.querySelectorAll('#shop .range').forEach(b=>b.classList.toggle('active', b.dataset.range===CAL));
  }
  function projHealthForJob(j){ const c=String(j.completionISO||''); if(c&&c<todayISO()) return 'late'; return 'ontrack'; }

  function render(){
    const sec=document.getElementById('shop'); if(!sec) return;
    _pjRebuild();
    const grid=bayGridModel();
    const parking=jobsInBay(isParkingBay), held=jobsInBay(bayIsHeld), parts=jobsInBay(bayIsParts);
    const activeJobs=(D().jobs||[]).filter(jobIsActiveLane);
    let open=0, od=0, future=0; const today=todayISO();
    activeJobs.forEach(j=>openTasksOf(j).forEach(t=>{ if(isSalesT(t)) return; open++; if(t.due&&String(t.due)<today) od++; else if(t.due) future++; }));
    // highlighted (overdue) + risk (assignee overload / bay conflicts)
    const odTasks=[]; activeJobs.forEach(j=>openTasksOf(j).forEach(t=>{ if(t.due&&String(t.due)<today&&!isSalesT(t)) odTasks.push({j,t}); }));
    odTasks.sort((a,b)=>String(a.t.due).localeCompare(String(b.t.due)));
    const load={}; activeJobs.forEach(j=>openTasksOf(j).forEach(t=>crewWhoList(t.who).forEach(w=>load[w]=(load[w]||0)+1)));
    const overloaded=Object.keys(load).filter(w=>load[w]>=8).sort((a,b)=>load[b]-load[a]);

    sec.innerHTML=`<div class="head"><div><h1>Shop Overview</h1><div class="muted">Bays, tasks and scheduling — the working board.</div></div><button class="btn primary" onclick="openFloor()">▣ Floor View</button></div>
    <div class="grid kpis">
      <div class="card"><span class="muted">Jobs on the floor</span><div class="num">${activeJobs.length}</div></div>
      <div class="card"><span class="muted">Open tasks</span><div class="num">${open}</div></div>
      <div class="card"><span class="muted">Overdue</span><div class="num danger">${od}</div></div>
      <div class="card"><span class="muted">Upcoming</span><div class="num">${future}</div></div></div>
    <div class="shopactions">
      <button class="btn" onclick="showPage('projects')">Projects &amp; Gantt</button>
      <button class="btn" onclick="showPage('maintenance')">Maintenance</button>
      <button class="btn" onclick="openFloor()">Floor View</button>
      <a class="btn" href="../MRA_Dashboard.html?wo=all" target="_blank" rel="noopener">🖨 Work orders ↗</a></div>
    <div class="grid shopgrid">
      <div class="card full"><div class="cardhead"><h2>Bay Overview</h2><span class="muted">Click a card to open the job editor</span></div>
        <div class="baygrid detailgrid">${grid.map(b=>`<div class="baycol"><div class="bayname">Bay ${b.bay}</div>${b.Front?bayCard(b.Front,'Front'):emptySlot('Front')}${b.Middle?bayCard(b.Middle,'Middle'):''}${b.Back?bayCard(b.Back,'Back'):emptySlot('Back')}</div>`).join('')||'<div class="emptystate">No jobs in bays.</div>'}</div>
        ${parts.length?`<div class="cardhead" style="margin-top:18px"><h2>Off Site / Parts</h2><span class="muted">Away — but we're building parts</span></div><div class="parkinggrid">${parts.map(parkCard).join('')}</div>`:''}
        <div class="cardhead" style="margin-top:18px"><h2>Parking Lot</h2><span class="muted">⏭ ${parking.length} on the lot</span></div>
        <div class="parkinggrid">${parking.map(parkCard).join('')||'<div class="emptystate">Empty.</div>'}</div>
        <button class="btn expand" onclick="this.nextElementSibling.classList.toggle('open')"><span>On Hold / Next Up</span><span>⏸ ${held.length} held ▾</span></button>
        <div class="collapse">${held.map(j=>`<div class="hold click" onclick="openJobEditor('${escA(j.row)}')"><b>${esc(j.project)}</b><div class="muted">${esc(j.bay)}${j.jobNum?' · '+esc(j.jobNum):''} · ${openTasksOf(j).length} open</div></div>`).join('')||'<div class="emptystate">None.</div>'}</div></div>
      <div class="card full"><div class="cardhead"><h2>Tasks</h2><div><button class="btn ${SORT==='job'?'active':''}" onclick="shopSetSort('job')">By Job</button> <button class="btn ${SORT==='person'?'active':''}" onclick="shopSetSort('person')">By Assignee</button></div></div>
        <div class="bubbles">${bubbles()}</div></div>
      <div class="card"><div class="cardhead"><h2>⚠ Overdue</h2><span class="crewtag">${odTasks.length}</span></div>
        ${odTasks.slice(0,10).map(x=>`<div class="highlight click" onclick="goShopJob('${escA(x.j.row)}')"><b>${esc(_mwCleanCm(x.t.t)||x.t.t)}</b><span>${esc(x.j.jobNum||x.j.project)}</span><span class="duebadge od">${esc(fmtMD(x.t.due))}</span></div>`).join('')||'<div class="emptystate">Nothing overdue 🎉</div>'}</div>
      <div class="card"><div class="cardhead"><h2>Risk</h2></div>
        ${overloaded.length?overloaded.slice(0,6).map(w=>`<div class="taskrow"><b>Heavy load</b><span class="badge">${esc(w)} · ${load[w]}</span></div>`).join(''):'<div class="emptystate">Load looks balanced.</div>'}</div>
      <div class="card full"><div class="cardhead"><h2>Bay Calendar</h2><div><button class="btn range" data-range="month" onclick="shopSetCal('month')">1 Month</button> <button class="btn range" data-range="quarter" onclick="shopSetCal('quarter')">3 Months</button></div></div>
        <div class="gantt" id="bayGantt"></div></div></div>`;
    drawCal();
  }
  function emptySlot(pos){ return `<div class="slot detail ${pos==='Back'?'back':''}"><div class="pos">${pos}</div><div class="job muted">Available</div></div>`; }
  window.MRA_PAGES.shop={render:render};
})();
