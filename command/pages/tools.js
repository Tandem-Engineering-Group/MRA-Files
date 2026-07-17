/* Tools — launcher for connected apps/resources. Real deep-links, no dead cards. */
(function(){
  const TOOLS=[
    {name:'Product Catalogue', desc:'Parts lookup & pricing', href:'../catalogue/index.html', ext:true},
    {name:'Infowheel 3D', desc:'Build & configure a unit', href:'../builder.html', ext:true},
    {name:'Fleetio', desc:'Asset management', href:'https://secure.fleetio.com/8cf2193b5d/dashboard', ext:true},
    {name:'Classic Board', desc:'The full existing dashboard', href:'../MRA_Dashboard.html', ext:true},
    {name:'Work Orders', desc:'Print crew work orders', href:'../MRA_Dashboard.html?wo=all', ext:true},
    {name:'PM Report', desc:'Project manager report', href:'../MRA_Dashboard.html?recap=1', ext:true}
  ];
  function render(){ const sec=document.getElementById('tools'); if(!sec) return;
    sec.innerHTML=`<div class="head"><div><h1>Tools</h1><div class="muted">Connected applications and resources.</div></div></div>
    <div class="toolgrid">${TOOLS.map(t=>`<a class="card toolcard" href="${escA(t.href)}" ${t.ext?'target="_blank" rel="noopener"':''} title="${escA(t.desc)}"><h2>${esc(t.name)}${t.ext?' ↗':''}</h2><p class="muted">${esc(t.desc)}</p></a>`).join('')}</div>`;
  }
  window.MRA_PAGES.tools={render:render};
})();
