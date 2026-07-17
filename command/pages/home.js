/* Home — live monitor canvas: bay overview + weekly overlap + upcoming tasks. */
(function(){
  function goShopJob(row){ showPage('shop'); setTimeout(()=>{ const el=document.getElementById('job-'+row); if(el){ el.scrollIntoView({behavior:'smooth',block:'center'}); el.classList.add('flash'); setTimeout(()=>el.classList.remove('flash'),1400); } },80); }
  window.goShopJob=goShopJob;

  function card(pos, j, back){ const k=kindOf(j), open=openTasksOf(j).length, pct=jobPct(j);
    return `<div class="slot click ${back?'back':''}" onclick="goShopJob('${escA(j.row)}')" title="Open ${escA(j.project)} on Shop">
      <div class="between"><span class="pos">${esc(pos)}</span><span class="tag ${k}">${KIND_LABEL[k]}</span></div>
      <div class="job">${esc(j.project)}${j.jobNum?` <span class="fnum">${esc(j.jobNum)}</span>`:''}</div>
      <div class="pctline"><span>${esc(j.pm||'—')}</span><span>${open} open</span></div>
      <div class="progress"><span style="width:${pct}%"></span></div></div>`; }
  function empty(pos, back){ return `<div class="slot ${back?'back':''}"><div class="pos">${esc(pos)}</div><div class="job muted">Available</div></div>`; }
  // Render every job in a position (a bay position can hold several trailers); Front/Back show Available when empty.
  function posCards(arr, pos, back){ if(!arr||!arr.length) return (pos==='Middle')?'':empty(pos,back); return arr.map(j=>card(pos,j,back)).join(''); }

  function render(){
    const sec=document.getElementById('home'); if(!sec) return;
    const grid=bayGridModel();
    const hr=new Date().getHours(); const greet=hr<12?'Good morning':hr<17?'Good afternoon':'Good evening';
    const name=(CURRENT_USER? (' '+(CURRENT_USER.split(' ')[0])) : '');
    // upcoming tasks across active jobs
    const up=[]; (D().jobs||[]).forEach(j=>{ if(!jobIsActiveLane(j)) return; openTasksOf(j).forEach(t=>{ if(isSalesT(t)) return; if(t.due) up.push({j,t}); }); });
    up.sort((a,b)=>String(a.t.due).localeCompare(String(b.t.due)));
    const today=todayISO();
    const taskRows = up.slice(0,7).map(x=>{ const od=String(x.t.due)<today;
      return `<div class="taskrow click" onclick="goShopJob('${escA(x.j.row)}')" title="Open ${escA(x.j.project)}">
        <div><b>${x.j.jobNum?esc(x.j.jobNum)+' · ':''}${esc(_mwCleanCm(x.t.t)||x.t.t)}</b><div class="muted">${esc(x.j.project)}${x.t.who?' · '+esc(x.t.who):''}</div></div>
        <span class="duebadge ${od?'od':''}">${esc(fmtMD(x.t.due))}</span></div>`; }).join('') || '<div class="emptystate">No dated tasks.</div>';
    // weekly overlap gantt (active bay/parking jobs with dates)
    const ganttItems=(D().jobs||[]).filter(j=>jobIsActiveLane(j) && j.startISO && j.completionISO).map(j=>({
      label:j.project, sub:j.jobNum||'', startISO:j.startISO, endISO:j.completionISO,
      color:HEALTH_COLOR.ontrack, onclick:`goShopJob('${escA(j.row)}')`,
      title:j.project+' · '+fmtMDY(j.startISO)+' → '+fmtMDY(j.completionISO) }));

    sec.innerHTML=`<div class="head"><div><h1>${greet}${esc(name)}</h1><div class="muted">Live bay occupancy, this week's overlap and what's coming due.</div></div><span class="pill">● Systems Operational · ${esc(D().generatedText||'')}</span></div>
    <div class="grid homegrid">
      <div class="card overview"><div class="cardhead"><h2>Bay Overview</h2><span class="muted">Bays 2–5 · Front and Back</span></div>
        <div class="baygrid">${grid.map(b=>`<div class="baycol"><div class="bayname">Bay ${b.bay}</div>${posCards(b.Front,'Front',0)}${posCards(b.Middle,'Middle',0)}${posCards(b.Back,'Back',1)}</div>`).join('')||'<div class="emptystate">No jobs in bays.</div>'}</div>
        <div class="note">Middle positions appear only when occupied. Click a bay to open it on Shop.</div></div>
      <div class="card"><div class="cardhead"><h2>Weekly Task Overlap</h2><span class="muted">Active bay & parking jobs</span></div>
        <div class="gantt" id="homeGantt"></div></div>
      <div class="card"><div class="cardhead"><h2>Coming Due</h2><button class="btn" onclick="showPage('tasks')">View all</button></div>${taskRows}</div>
    </div>`;
    ganttDates(document.getElementById('homeGantt'), ganttItems, {labelW:130});
  }
  window.MRA_PAGES.home={render:render, homeMode:true};
})();
