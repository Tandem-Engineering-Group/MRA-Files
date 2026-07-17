/* Maintenance — Fleetio-sourced: KPIs, in-shop assets, return calendar, open
   issues (sort/filter/expand/detail), GPS truth. */
(function(){
  let SORT='all', SHOWALL=false;
  window.mtSetSort=function(v){ SORT=v; render(); };
  window.mtToggleAll=function(){ SHOWALL=!SHOWALL; render(); };

  function issueRow(it){ const age=_fioAge(it); const asg=fAsg(it);
    return `<div class="issue click" onclick="mtTicket('${escA(String(it.num))}')" title="Open detail">
      <div><b><span class="fionum">#${esc(it.num)}</span> ${esc(it.summary||'Issue')}</b>${_fioIsNew(it)?' <span class="badge">🆕 new</span>':''}${it.overdue?' <span class="danger">overdue</span>':''}
        <div class="muted" style="font-size:11px">${esc(it.asset||'')}${it.jobNum?' · '+esc(it.jobNum):''}</div></div>
      <span>${esc(it.priority||'')}</span>
      <span class="${asg.length?'pill':'tag danger'}">${asg.length?esc(asg.join(', ')):'Unassigned'}</span></div>`; }

  window.mtTicket=function(num){ const it=fioIssue(num); if(!it) return; const m=_modal('mtModal'); const age=_fioAge(it);
    const docs=it.docs||[], imgs=docs.filter(x=>/^image\//i.test(x.mime||'')), files=docs.filter(x=>!/^image\//i.test(x.mime||''));
    m.innerHTML=`<div class="modalbox"><div class="cardhead"><h2><span class="fionum">#${esc(it.num)}</span> ${esc(it.summary||'Issue')}</h2><button class="btn" onclick="closeModal('mtModal')">Close</button></div>
      <div class="det"><div class="detrow"><span class="lbl">Asset</span>${esc(it.asset||'—')}${it.jobNum?' · '+esc(it.jobNum):''}</div>
      <div class="chips">${it.overdue?'<span class="danger">overdue</span>':''}${age!=null?ageBadge(age):''}${fAsg(it).length?'<span class="pill">'+esc(fAsg(it).join(', '))+'</span>':'<span class="tag danger">Unassigned</span>'}</div>
      ${it.reporter?`<div class="detrow"><span class="lbl">Reporter</span>${esc(it.reporter)}${it.openedISO?' · opened '+esc(it.openedISO):''}</div>`:''}
      <div class="detrow"><span class="lbl">Description</span><div class="cmt">${it.detail?esc(it.detail):'(none)'}</div></div>
      ${imgs.length?`<div class="thumbs">${imgs.map(x=>`<a href="${escA(x.url)}" target="_blank" rel="noopener"><img src="${escA(x.url)}"></a>`).join('')}</div>`:''}
      ${files.length?`<div class="detrow">${files.map(x=>`<a class="btn" href="${escA(x.url)}" target="_blank" rel="noopener">📎 ${esc((x.n||'file').slice(0,40))}</a>`).join(' ')}</div>`:''}
      <div class="detrow"><a class="btn primary" href="${fioHref('issue',it.num)}" target="_blank" rel="noopener">↗ Open / resolve in Fleetio</a>
      ${mtBoardJob(it)?`<button class="btn" onclick="mtAddToBoard('${escA(String(it.num))}')">➕ Add to board</button>`:''}</div></div></div>`;
    m.classList.add('open'); };
  function mtBoardJob(it){ const jn=String(it.jobNum||'').toUpperCase().replace(/[^0-9]/g,''); if(!jn) return null;
    return (D().jobs||[]).find(j=>isLive(j)&&String(j.jobNum||'').toUpperCase().replace(/[^0-9]/g,'')===jn)||null; }
  window.mtAddToBoard=function(num){ const it=fioIssue(num); const j=mtBoardJob(it); if(!it||!j) return;
    if(!ensureAuth('add this to the board', ()=>mtAddToBoard(num))) return;
    const task='🔧 #'+it.num+' '+(it.summary||'Issue');
    shopWrite({action:'addTask', project:j.project, jobNum:j.jobNum||'', bay:j.bay||'', task:task, assigned:'', milestone:'', comments:'Fleetio issue #'+it.num, due:'', pin:CLOSE_PIN||'1974', user:CURRENT_USER});
    if(!j.tasks) j.tasks=[]; j.tasks.push({t:task, who:'', op:localISO(Date.now()), cl:null, st:'Open', done:false, ml:'', cm:'Fleetio issue #'+it.num, due:null, files:null});
    oRecompute(j); closeModal('mtModal'); alert('Added to '+j.project+'.'); oApply(); };

  function render(){ const sec=document.getElementById('maintenance'); if(!sec) return;
    const fl=D().fleetio||{}; let issues=(fl.issues||[]).slice();
    const openN=issues.length, odN=issues.filter(i=>i.overdue).length;
    const svc=(fl.service||[]); const svcDue=svc.length, svcOd=svc.filter(s=>s.overdue).length||0;
    // in-shop assets: units on active bay jobs with open fleet issues
    const assets=[]; (D().jobs||[]).forEach(j=>{ if(!jobIsActiveLane(j)) return; const jn=String(j.jobNum||'').toUpperCase().replace(/[^0-9]/g,''); if(!jn) return;
      const its=issues.filter(i=>String(i.jobNum||'').toUpperCase().replace(/[^0-9]/g,'')===jn); if(!its.length) return;
      assets.push({job:j, its:its, un:its.filter(i=>!fAsg(i).length).length}); });
    // return calendar
    const rets=issues.filter(i=>i.backMRA||i.leaveMRA).slice(0,40);
    // filter + sort issues
    let show=issues.filter(i=>{ if(SORT==='all') return true; const p=(i.priority||'')+' '+(i.summary||''); if(SORT==='safety') return /safety|brake|light|belt/i.test(p); if(SORT==='service') return /service|pm|oil|inspect/i.test(p); if(SORT==='equipment') return /equip|door|sensor|hydraul|gen/i.test(p); return true; });
    show.sort(_fioIssCmp); const cap=SHOWALL?show.length:12;

    sec.innerHTML=`<div class="head"><div><h1>Maintenance</h1><div class="muted">Fleetio-sourced work, assignments and returns.</div></div><span class="pill">Fleetio Connected</span></div>
    <div class="grid kpis"><div class="card"><span class="muted">Open Issues</span><div class="num">${openN}</div></div>
      <div class="card"><span class="muted">Overdue Issues</span><div class="num danger">${odN}</div></div>
      <div class="card"><span class="muted">Service Records</span><div class="num">${svcDue}</div></div>
      <div class="card"><span class="muted">Service Overdue</span><div class="num danger">${svcOd}</div></div></div>
    <div class="grid maintgrid">
      <div class="card"><div class="cardhead"><h2>In the Shop</h2><span class="muted">Open work by asset</span></div>
        <div class="assetcards">${assets.slice(0,24).map(a=>`<div class="asset ${a.un?'unassigned':''} click" onclick="goShopJob('${escA(a.job.row)}')" title="Open ${escA(a.job.project)}">
          <b>${esc(a.job.jobNum||a.job.project)}</b><p class="muted">${esc(a.job.project)}</p>
          <div class="crewtag">${a.its.length} issue${a.its.length>1?'s':''}${a.un?' · '+a.un+' unassigned':''}</div>${locChip(a.job)}</div>`).join('')||'<div class="emptystate">No fleet issues on floor jobs.</div>'}</div></div>
      <div class="card"><div class="cardhead"><h2>Return Calendar</h2><span class="muted">Back to MRA → Leaving</span></div>
        ${rets.length?rets.slice(0,14).map(r=>`<div class="taskrow"><div><b>${esc(r.asset||r.jobNum||('#'+r.num))}</b><div class="muted">${esc(r.jobNum||'')}</div></div><span class="pill">${esc(r.backMRA||'')}${r.leaveMRA?' → '+esc(r.leaveMRA):''}</span></div>`).join(''):'<div class="emptystate">No scheduled returns.</div>'}</div>
      <div class="card full"><div class="cardhead"><h2>⚠ Open Issues</h2><div>
        <select class="btn" onchange="mtSetSort(this.value)"><option value="all"${SORT==='all'?' selected':''}>All Areas</option><option value="service"${SORT==='service'?' selected':''}>Service</option><option value="safety"${SORT==='safety'?' selected':''}>Safety</option><option value="equipment"${SORT==='equipment'?' selected':''}>Equipment</option></select>
        <button class="btn" onclick="mtToggleAll()">${SHOWALL?'Show less':'Show all ('+show.length+')'}</button></div></div>
        <div>${show.slice(0,cap).map(issueRow).join('')||'<div class="emptystate">No issues.</div>'}${!SHOWALL&&show.length>cap?`<div class="muted" style="padding:8px">+${show.length-cap} more…</div>`:''}</div></div></div>`;
  }
  window.MRA_PAGES.maintenance={render:render};
})();
