/* Floor View — shop-TV wall. Read-only, high-contrast: bay slots + crew columns.
   WALL is set true while the overlay is open so no edit/close handles render. */
(function(){
  function fslot(pos, j){
    if(!j) return `<div class="floorslot empty">${pos} · Available</div>`;
    const open=openTasksOf(j).slice(0,6);
    return `<div class="floorslot"><div class="fpos">${esc(pos)}</div>
      <div class="ftitle">${esc(j.project)}</div>
      <div class="fjnum">${j.jobNum?esc(j.jobNum):''}${j.client?' · '+esc(j.client):''} · ${esc(j.status||'')}</div>
      <div class="ftasks">${open.map(t=>`<div>• ${esc(_mwCleanCm(t.t)||t.t)}${t.who?` <span class="who">${esc(t.who)}</span>`:''}</div>`).join('')||'<div class="fmore">no open tasks</div>'}${openTasksOf(j).length>6?`<div class="fmore">+${openTasksOf(j).length-6} more</div>`:''}</div></div>`;
  }
  function posSlots(arr, pos){ if(!arr||!arr.length) return (pos==='Middle')?'':fslot(pos,null); return arr.map(j=>fslot(pos,j)).join(''); }
  function render(){
    const grid=bayGridModel();
    const bays=document.getElementById('floorBays');
    if(bays) bays.innerHTML=grid.map(b=>`<div class="floorbay"><h2>Bay ${b.bay}</h2>${posSlots(b.Front,'Front')}${posSlots(b.Middle,'Middle')}${posSlots(b.Back,'Back')}</div>`).join('')||'<div class="floorslot empty">No jobs in bays</div>';
    // crew columns: the six print crews + MRA Shop, open tasks on active lanes
    const CREWS=['Sal','Doug','Wrap Team','Electricians','Josh','Jeff'];
    const byCrew={}; CREWS.forEach(c=>byCrew[c]=[]);
    (D().jobs||[]).forEach(j=>{ if(!jobIsActiveLane(j)) return; openTasksOf(j).forEach(t=>{ if(isSalesT(t)) return;
      crewWhoList(t.who).forEach(w=>{ if(byCrew[w]) byCrew[w].push({j,t}); }); }); });
    const today=todayISO();
    const crews=document.getElementById('floorCrews');
    if(crews) crews.innerHTML=CREWS.map(c=>{ const rows=byCrew[c].sort((a,b)=>String(a.t.due||'9999').localeCompare(String(b.t.due||'9999')));
      return `<div class="crewcol"><h3>${esc(c)} <span class="cnt">${rows.length}</span></h3><div class="crewscroll"><div class="inner">${rows.map(x=>{ const od=x.t.due&&String(x.t.due)<today;
        return `<div class="crewtask ${od?'od':''}"><div>${esc(_mwCleanCm(x.t.t)||x.t.t)}</div><div class="cjob">${esc(x.j.jobNum||x.j.project)}${x.t.due?' · '+esc(fmtMD(x.t.due)):''}</div></div>`; }).join('')||'<div class="crewempty">All clear</div>'}</div></div></div>`; }).join('');
  }
  window.MRA_PAGES.floor={render:render, wall:true};
})();
