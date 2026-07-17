/* Projects — portfolio + per-project panels + editor + awaiting-verification. */
(function(){
  const OPEN=new Set();          // which project panels are expanded
  const LOD={};                  // per-project level of detail: tasks|phases|milestones
  let started=false;

  function healthChip(p){ const h=projHealth(p); const c=HEALTH_COLOR[h.state]||'#64748b';
    const extra=h.behindBy!=null&&h.behindBy>0?(' · '+h.behindBy+'% behind'):(h.state==='late'?' · past due':'');
    return `<span class="hchip" style="background:${c}22;color:${c}">${HEALTH_LABEL[h.state]||h.state}${extra}</span>`; }

  function panelHtml(p){ const h=projHealth(p), bits=_pmtBehindBits(p), gate=nextGate(p);
    const lod=LOD[p.name]||'tasks'; const today=todayISO();
    let tasks=(p.tasks||[]).filter(t=>!t.sub || lod==='tasks');
    if(lod==='milestones') tasks=(p.tasks||[]).filter(t=>/yes/i.test(t.ml||''));
    else if(lod==='phases') { /* show one row per phase header + milestones */ }
    const taskRows = lod==='phases' ? phaseRows(p) : tasks.map(t=>ptRow(p,t)).join('');
    return `<article class="card projectpanel" id="pp-${cssId(p.name)}">
      <div class="paneltop"><div class="cardhead"><div><h2>${esc(p.name)}${p.jobNum?' · '+esc(p.jobNum):''} ${healthChip(p)}</h2>
        <span class="muted">${esc(p.pm||'—')} · ${p.pct}%${p.finishISO?' · target '+esc(fmtMDY(p.finishISO)):''}${gate?' · next ◆ '+esc(gate.name)+' '+esc(fmtMD(gate.dateISO)):''}${bits.odN?' · ⚠ '+bits.odN+' past-due'+(bits.whoTxt?' (with '+esc(bits.whoTxt)+')':''):''}</span></div>
        <div><select class="btn" onchange="prjLod('${escJsAttr(p.name)}',this.value)"><option value="tasks"${lod==='tasks'?' selected':''}>All tasks</option><option value="phases"${lod==='phases'?' selected':''}>Phases</option><option value="milestones"${lod==='milestones'?' selected':''}>Milestones</option></select>
        <button class="btn editaff" onclick="openProjectEditor('${escJsAttr(p.name)}')">✎ Edit</button>
        <button class="btn" onclick="prjToggle('${escJsAttr(p.name)}')">Close</button></div></div></div>
      <div class="projectbody"><div class="module"><h3>Task List</h3>${taskRows||'<div class="emptystate">No tasks.</div>'}</div>
        <div class="module"><h3>Detailed Gantt</h3><div class="gantt projectgantt" id="pg-${cssId(p.name)}"></div></div></div></article>`; }

  function phaseRows(p){ const ph={}, order=[]; (p.tasks||[]).forEach(t=>{ const k=t.phase||'—'; if(!(k in ph)){ph[k]={n:0,done:0,od:0};order.push(k);} ph[k].n++; if(t.done) ph[k].done++; if(!t.done&&t.finISO&&t.finISO<todayISO()) ph[k].od++; });
    return order.map(k=>`<div class="ptask"><b>${esc(k)}</b><span>${ph[k].done}/${ph[k].n}</span><span class="${ph[k].od?'':'muted'}">${ph[k].od?ph[k].od+' od':''}</span></div>`).join(''); }

  function ptRow(p,t){ const od=!t.done&&t.finISO&&t.finISO<todayISO(); const pv=projIsPendingVerify(t); const cm=_mwCleanCm(t.cm);
    const range=(t.startISO||t.finISO)?`${t.startISO?'▶ '+fmtMD(t.startISO):''}${t.finISO?' → '+fmtMD(t.finISO):''}`:'';
    return `<div class="ptask click ${od?'overdue':''}" onclick="openProjectEditor('${escJsAttr(p.name)}')" title="Open editor">
      <div><b>${/yes/i.test(t.ml||'')?'◆ ':''}${esc(t.t)}</b>${t.phase?` <span class="crewtag">${esc(t.phase)}</span>`:''}${pv?' <span class="badge">🟡 verify</span>':''}${cm?`<div class="muted" style="font-size:11px">📝 ${esc(cm)}</div>`:''}</div>
      <span>${esc(t.who||'—')}</span><span class="${od?'':'muted'}">${esc(range)}</span></div>`; }

  function drawPanelGantt(p){ const el=document.getElementById('pg-'+cssId(p.name)); if(!el) return;
    const items=(p.tasks||[]).filter(t=>t.startISO&&t.finISO).map(t=>({label:(/yes/i.test(t.ml||'')?'◆ ':'')+t.t, sub:t.who||'', startISO:t.startISO, endISO:t.finISO,
      color:t.done?HEALTH_COLOR.done:(t.finISO<todayISO()?HEALTH_COLOR.late:HEALTH_COLOR.ontrack), title:t.t+' · '+fmtMDY(t.startISO)+' → '+fmtMDY(t.finISO)}));
    ganttDates(el, items, {labelW:170}); }

  function cssId(s){ return String(s).replace(/[^a-z0-9]/gi,'_'); }
  window.prjToggle=function(name){ if(OPEN.has(name)) OPEN.delete(name); else OPEN.add(name); render(); };
  window.prjLod=function(name,v){ LOD[name]=v; render(); };

  const PF={nonoff:true, parked:false, archived:false};   // hide non-official (default); show parked; hide completed
  window.prjFilter=function(k){ PF[k]=!PF[k]; render(); };
  function render(){ const sec=document.getElementById('projects'); if(!sec) return;
    // PIVOT (Rich): unreadable rebuilt gantts -> embed the real Projects tab (full gantt engine).
    if(sec.querySelector('.ccframe')) return;   // already embedded — don't reload on poll
    sec.innerHTML='<iframe class="ccframe" src="../MRA_Dashboard.html?view=projects" title="MRA projects"></iframe>';
    return;
    const all=(D().projects||[]).slice();
    const nonoffN=all.filter(p=>p.nonOfficial).length, parkedN=all.filter(p=>p.parked).length, doneN=all.filter(p=>projHealth(p).state==='done').length;
    let projs=all;
    if(PF.nonoff) projs=projs.filter(p=>!p.nonOfficial);
    if(!PF.parked) { /* show parked by default */ }
    if(!PF.archived) projs=projs.filter(p=>projHealth(p).state!=='done');
    projs=projs.sort((a,b)=>HEALTH_RANK[projHealth(a).state]-HEALTH_RANK[projHealth(b).state]||String(a.finishISO||'9999').localeCompare(String(b.finishISO||'9999')));
    const filterBar=`<div class="selrow">
      <button class="btn ${PF.nonoff?'active':''}" onclick="prjFilter('nonoff')" title="Hide 🏷 non-official / pipeline projects">🏷 ${PF.nonoff?'Non-official hidden':'Non-official shown'} (${nonoffN})</button>
      <button class="btn ${PF.archived?'active':''}" onclick="prjFilter('archived')" title="Show completed projects">🗄 ${PF.archived?'Completed shown':'Completed hidden'} (${doneN})</button></div>`;
    if(!started){ projs.slice(0,3).forEach(p=>OPEN.add(p.name)); started=true; }
    // awaiting verification
    const pend=[]; projs.forEach(p=>(p.tasks||[]).forEach(t=>{ if(projIsPendingVerify(t)) pend.push({p,t}); }));
    const pendHtml = pend.length?`<div class="card"><div class="cardhead"><h2>🟡 Awaiting verification</h2><span class="crewtag">${pend.length}</span></div>
      ${pend.map(x=>`<div class="highlight"><div><b>${esc(x.t.t)}</b><div class="muted">${esc(x.p.name)} · PM ${esc(x.p.pm||'—')}${_taskBy(x.t.cm)?' · marked by '+esc(_taskBy(x.t.cm)):''}</div></div>
        <button class="btn primary editaff" onclick="verifyTask('${escJsAttr(x.p.name)}','${escJsAttr(projTaskHandle(x.t))}')">✓ Verify</button>
        <button class="btn editaff" onclick="sendBackTask('${escJsAttr(x.p.name)}','${escJsAttr(projTaskHandle(x.t))}')">↩ Back</button></div>`).join('')}</div>`:'';

    sec.innerHTML=`<div class="head"><div><h1>Projects</h1><div class="muted">Portfolio, per-project schedules and sign-off.</div></div><a class="btn" href="../MRA_Dashboard.html#projects" target="_blank" rel="noopener">Classic Projects ↗</a></div>
    ${filterBar}
    ${pendHtml}
    <div class="projecttabs">${projs.map(p=>`<button class="projecttab" onclick="prjToggle('${escJsAttr(p.name)}')" title="${escA(p.name)}">${healthChip(p)}<b>${esc(p.jobNum||p.name)}</b><div class="muted">${esc(p.name)}</div><div class="progress" style="margin-top:9px"><span style="width:${p.pct}%"></span></div></button>`).join('')}</div>
    <div id="projectPanels">${projs.filter(p=>OPEN.has(p.name)).map(panelHtml).join('')||'<div class="emptystate">Click a project above to open it.</div>'}</div>
    <div class="card"><div class="cardhead"><h2>Concurrent Project Timeline</h2><span class="muted">Portfolio Gantt</span></div><div class="gantt" id="portfolioGantt"></div></div>`;
    projs.filter(p=>OPEN.has(p.name)).forEach(drawPanelGantt);
    const items=projs.filter(p=>p.startISO&&p.finishISO).map(p=>({label:p.name, sub:(p.pm||'—')+' · '+p.pct+'%', startISO:p.startISO, endISO:p.finishISO,
      color:HEALTH_COLOR[projHealth(p).state]||'#2166f3', onclick:`openProjectEditor('${escJsAttr(p.name)}')`, milestones:p.milestones,
      title:p.name+' · '+fmtMDY(p.startISO)+' → '+fmtMDY(p.finishISO)}));
    ganttDates(document.getElementById('portfolioGantt'), items, {labelW:200});
  }

  /* ---------- project editor ---------- */
  let _peName=null;
  window.openProjectEditor=function(name){ if(!ensureAuth('edit this project', ()=>openProjectEditor(name))) return; _peName=name; peRender(); };
  function peRender(){ const p=oProj(_peName); if(!p) return; const m=_modal('projModal'); const today=todayISO();
    const ph={}, order=[]; (p.tasks||[]).forEach(t=>{ const k=t.phase||'—'; if(!(k in ph)){ph[k]=[];order.push(k);} ph[k].push(t); });
    m.innerHTML=`<div class="modalbox wide"><div class="cardhead"><h2>${esc(p.name)} · edit</h2><button class="btn" onclick="closeModal('projModal')">Close</button></div>
      <div class="peList">${order.map(k=>`<div class="pePhase"><h4>${esc(k)}</h4>${ph[k].map(t=>peRow(p,t)).join('')}</div>`).join('')||'<div class="emptystate">No tasks yet.</div>'}</div>
      <div class="peAdd"><h4>Add task</h4><div class="tdmeta">
        <input id="ptaTask" placeholder="Task"><input id="ptaPhase" placeholder="Phase" value="">
        <input id="ptaWho" list="asgNames" placeholder="Assigned"><input id="ptaStart" type="date"><input id="ptaFinish" type="date">
        <label class="ck"><input type="checkbox" id="ptaMl"> Milestone</label></div>
        <button class="btn primary" onclick="ptAdd()">➕ Add task</button></div></div>`;
    m.classList.add('open'); }
  function peRow(p,t){ const od=!t.done&&t.finISO&&t.finISO<today(); const pv=projIsPendingVerify(t);
    const hnd=projTaskHandle(t);
    return `<div class="peRow ${od?'od':''}"><div class="peRow-t"><b>${/yes/i.test(t.ml||'')?'◆ ':''}${esc(t.t)}</b>${pv?' <span class="badge">🟡</span>':''}<div class="muted" style="font-size:11px">${esc(t.who||'—')}${t.finISO?' · '+esc(fmtMD(t.finISO)):''} · ${esc(t.st||'')}</div></div>
      <div class="peRow-a">${t.done?`<button class="btn" onclick="ptReopen('${escJsAttr(p.name)}','${escJsAttr(hnd)}')">↩</button>`:`<button class="btn" onclick="ptClose('${escJsAttr(p.name)}','${escJsAttr(hnd)}')" title="Mark complete">✓</button>`}
      <button class="btn" onclick="ptEditOpen('${escJsAttr(p.name)}','${escJsAttr(hnd)}')">✎</button>
      <button class="btn danger" onclick="ptDelete('${escJsAttr(p.name)}','${escJsAttr(hnd)}')">🗑</button></div></div>`; }
  function today(){ return todayISO(); }

  window.ptAdd=function(){ const p=oProj(_peName); if(!p) return; const task=(document.getElementById('ptaTask')||{}).value.trim(); if(!task) return;
    const phase=(document.getElementById('ptaPhase')||{}).value||''; const who=(document.getElementById('ptaWho')||{}).value||'';
    const start=(document.getElementById('ptaStart')||{}).value||''; const finish=(document.getElementById('ptaFinish')||{}).value||'';
    const ml=(document.getElementById('ptaMl')||{}).checked?'Yes':'';
    shopWrite({action:'addProjectTask', project:p.name, task:task, phase:phase, type:'', assigned:who, status:'Not Started', start:start, finish:finish, milestone:ml, comments:'', pin:CLOSE_PIN||'1974', user:CURRENT_USER});
    p.tasks=p.tasks||[]; p.tasks.push({id:'', _id:null, t:task, phase:phase, type:'', who:who, startISO:start||null, finISO:finish||null, st:'Not Started', ml:ml, cm:'', done:false});
    oRecomputeProject(p); markPending(); peRender(); };
  window.ptClose=function(name,h){ verifyOrClose(name,h,'closeProjectTask','Completed',true); };
  window.ptReopen=function(name,h){ verifyOrClose(name,h,'reopenProjectTask','In Progress',false); };
  function verifyOrClose(name,h,action,st,done){ const p=oProj(name); const t=projTaskByAnyId(p,h); if(!t) return;
    const d=new Date(), cd=(d.getMonth()+1)+"/"+d.getDate()+"/"+d.getFullYear();
    shopWrite({action:action, project:name, id:t.id, _id:(t._id!=null?t._id:undefined), task:t.t, closedDate:cd, pin:CLOSE_PIN||'1974', user:CURRENT_USER});
    t.done=done; t.st=st; if(done&&!t.finISO) t.finISO=localISO(Date.now()); oRecomputeProject(p); markPending(); peRender(); };
  window.ptDelete=function(name,h){ const p=oProj(name); const t=projTaskByAnyId(p,h); if(!t) return; if(!confirm('Delete "'+t.t+'"?')) return;
    shopWrite({action:'deleteProjectTask', project:name, task:t.t, _id:(t._id!=null?t._id:undefined), pin:CLOSE_PIN||'1974', user:CURRENT_USER});
    p.tasks=(p.tasks||[]).filter(x=>x!==t); oRecomputeProject(p); markPending(); peRender(); };
  let _pte=null;
  window.ptEditOpen=function(name,h){ const p=oProj(name); const t=projTaskByAnyId(p,h); if(!t) return; _pte={name,t};
    const m=_modal('ptEditModal'); m.innerHTML=`<div class="modalbox"><div class="cardhead"><h2>Edit task</h2><button class="btn" onclick="closeModal('ptEditModal')">Close</button></div>
      <label class="fld"><span>Task</span><input id="pteTask" value="${escA(t.t)}"></label>
      <label class="fld"><span>Phase</span><input id="ptePhase" value="${escA(t.phase||'')}"></label>
      <label class="fld"><span>Assigned</span><input id="pteWho" list="asgNames" value="${escA(t.who||'')}"></label>
      <div class="tdmeta"><label class="fld"><span>Start</span><input id="pteStart" type="date" value="${escA(t.startISO||'')}"></label>
      <label class="fld"><span>Finish</span><input id="pteFinish" type="date" value="${escA(t.finISO||'')}"></label></div>
      <label class="fld"><span>Status</span><input id="pteStatus" value="${escA(t.st||'')}"></label>
      <label class="ck"><input type="checkbox" id="pteMl" ${/yes/i.test(t.ml||'')?'checked':''}> Milestone</label>
      <button class="btn primary" style="width:100%;margin-top:10px" onclick="ptEditSave()">Save</button></div>`;
    m.classList.add('open'); };
  window.ptEditSave=function(){ if(!_pte) return; const p=oProj(_pte.name), t=_pte.t;
    const task=(document.getElementById('pteTask')||{}).value.trim()||t.t; const phase=(document.getElementById('ptePhase')||{}).value||'';
    const who=(document.getElementById('pteWho')||{}).value||''; const start=(document.getElementById('pteStart')||{}).value||'';
    const finish=(document.getElementById('pteFinish')||{}).value||''; const status=(document.getElementById('pteStatus')||{}).value||t.st;
    const ml=(document.getElementById('pteMl')||{}).checked?'Yes':'';
    shopWrite({action:'editProjectTask', project:_pte.name, taskOld:t.t, _id:(t._id!=null?t._id:undefined), task:task, phase:phase, type:t.type||'', assigned:who, status:status, start:start, finish:finish, milestone:ml, comments:t.cm||'', pin:CLOSE_PIN||'1974', user:CURRENT_USER});
    t.t=task; t.phase=phase; t.who=who; t.startISO=start||null; t.finISO=finish||null; t.st=status; t.ml=ml; t.done=/complete/i.test(status);
    oRecomputeProject(p); closeModal('ptEditModal'); markPending(); peRender(); };

  window.MRA_PAGES.projects={render:render};
})();
