/* Sales — committed + prospective portfolio. Prospects ride [SALES]-tagged tasks
   on the General job (hidden from the floor); committed = real projects. */
(function(){
  let MONTHS_N=3;
  window.salesRange=function(m){ MONTHS_N=m; render(); };

  function prospects(){ const out=[]; (D().jobs||[]).forEach(j=>{ (j.tasks||[]).forEach(t=>{ if(!isSalesT(t)) return;
    let meta={}; const m=String(t.cm||'').match(/\[sales\]\s*(\{[\s\S]*\})/i); if(m){ try{ meta=JSON.parse(m[1]); }catch(e){} }
    out.push({name:(meta.name||String(t.t).replace(/^\s*\[sales\]\s*/i,'')), vehicle:meta.vehicle||'', scope:meta.scope||'', prob:meta.prob||meta.probability||null,
      startISO:meta.startISO||meta.start||t.startISO||null, finISO:meta.finISO||meta.finish||t.due||null, pm:meta.pm||''}); }); });
    return out; }

  function render(){ const sec=document.getElementById('sales'); if(!sec) return;
    const committed=(D().projects||[]).filter(p=>!p.parked && projHealth(p).state!=='done');
    const pros=prospects();
    const expNew=pros.reduce((a,p)=>a+((+p.prob||0)/100),0);
    const winRate=(committed.length+pros.length)?Math.round(committed.length/(committed.length+pros.length)*100):0;
    const pmLoad={}; committed.forEach(p=>{ const k=p.pm||'—'; pmLoad[k]=(pmLoad[k]||0)+1; });
    const pmRows=Object.keys(pmLoad).sort((a,b)=>pmLoad[b]-pmLoad[a]);
    const items=[]; committed.filter(p=>p.startISO&&p.finishISO).forEach(p=>items.push({label:'✅ '+p.name, sub:(p.pm||'—'), startISO:p.startISO, endISO:p.finishISO, color:HEALTH_COLOR.ontrack, onclick:`openProjectEditor('${escJsAttr(p.name)}')`, title:p.name}));
    pros.filter(p=>p.startISO&&p.finISO).forEach(p=>items.push({label:'◇ '+p.name, sub:(p.vehicle||'prospect')+(p.prob?' · '+p.prob+'%':''), startISO:p.startISO, endISO:p.finISO, color:'#8b5cf6', cls:'hatch', title:(p.scope||p.name)}));

    sec.innerHTML=`<div class="head"><div><h1>Sales &amp; Planning</h1><div class="muted">Committed and prospective portfolio.</div></div></div>
    <div class="grid" style="grid-template-columns:repeat(4,1fr);margin-bottom:16px">
      <div class="card"><span class="muted">Committed</span><div class="num">${committed.length}</div></div>
      <div class="card"><span class="muted">Prospects</span><div class="num">${pros.length}</div></div>
      <div class="card"><span class="muted">Expected new builds</span><div class="num">${expNew.toFixed(1)}</div></div>
      <div class="card"><span class="muted">Win rate</span><div class="num">${winRate}%</div></div></div>
    <div class="grid salesgrid">
      <div class="card"><div class="cardhead"><h2>PM Load</h2></div>${pmRows.map(k=>`<div class="pmrow"><b>${esc(k)}</b><span>${pmLoad[k]} project${pmLoad[k]>1?'s':''}</span></div>`).join('')||'<div class="emptystate">No committed projects.</div>'}</div>
      <div class="card"><div class="cardhead"><h2>Prospects</h2></div>${pros.length?pros.map(p=>`<div class="pmrow"><div><b>${esc(p.name)}</b><div class="muted">${esc(p.vehicle||'')}${p.scope?' · '+esc(p.scope):''}</div></div><span class="badge">${p.prob?p.prob+'%':'—'}</span></div>`).join(''):'<div class="emptystate">No prospects logged. Add them on the classic board\'s Sales tab.</div>'}</div>
      <div class="card full"><div class="cardhead"><h2>Portfolio Gantt</h2><div><button class="btn salesrange ${MONTHS_N===3?'active':''}" onclick="salesRange(3)">3 Months</button> <button class="btn salesrange ${MONTHS_N===6?'active':''}" onclick="salesRange(6)">6 Months</button> <button class="btn salesrange ${MONTHS_N===12?'active':''}" onclick="salesRange(12)">12 Months</button></div></div>
        <div class="gantt" id="salesGantt"></div></div></div>`;
    ganttDates(document.getElementById('salesGantt'), items, {labelW:200});
  }
  window.MRA_PAGES.sales={render:render};
})();
