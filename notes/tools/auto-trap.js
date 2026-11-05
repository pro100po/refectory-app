const {chromium}=require('playwright');
(async()=>{ const b=await chromium.launch(); const errs=[];
  const shapes={right:{tpl:'trap',rot:0,p:{kind:'right',side:'l',a:6,b:4,h:4}}, iso:{tpl:'trap',rot:1,p:{kind:'iso',a:6,b:4,c:4.2}}, free:{tpl:'trap',rot:2,p:{kind:'free',a:7,b:4,c:4.5,d:5}}, longSkew:{tpl:'trap',rot:0,p:{kind:'right',side:'l',a:3,b:1.5,h:6}}};
  for(const [nm,sh] of Object.entries(shapes)){ const p=await b.newPage({viewport:{width:1400,height:1000}}); p.on('pageerror',e=>errs.push(nm+' PE '+String(e).slice(0,200))); p.on('console',m=>{ if(m.type()==='error') errs.push(nm+' console: '+m.text().slice(0,200)); });
    await p.goto('file://'+process.cwd()+'/index.html'); await p.waitForTimeout(300);
    const r=await p.evaluate(sh=>{ closeProjects(); const R=S.rooms[0]; S.cur=R.id; const e=setRoomShape(R,sh); S.layoutManual=false; S.layoutSig=null; step=5; recompute(); render();
      const us=curUnitsOf(R).filter(u=>S.layout[u.key]); const skew=us.filter(u=>S.layout[u.key].sw);
      const iss=checkUnit(S,curUnitsOf(R),S.layout).filter(q=>/Выходит за стену|Наложение/.test(q.lbl)).map(q=>{ const u=P.units.find(x=>x.key===q.key); return (u?u.c.s:q.key)+': '+q.lbl; });
      const hot=us.filter(u=>u.c.hot), hotSkew=hot.filter(u=>S.layout[u.key].sw);
      let gaps=null; if(hotSkew.length>1){ const w=wallById(R,S.layout[hotSkew[0].key].sw); const sp=hotSkew.map(u=>unitWallSpan(R,w.id,u.c,S.layout[u.key])).sort((a,b)=>a[0]-b[0]); gaps=sp.slice(1).map((s,i)=>+(s[0]-sp[i][1]).toFixed(3)); }
      const backs=skew.map(u=>{ const pos=S.layout[u.key], w=wallById(R,pos.sw); return +Math.min(...unitPoly(u.c,pos).map(q=>(q.x-w.x1)*w.nx+(q.y-w.y1)*w.ny)).toFixed(3); });
      return {err:e.error||null, placed:us.length, skew:skew.map(u=>u.c.s), hot:hot.map(u=>u.c.s+(S.layout[u.key].sw?'@skew':'')), hotGaps:gaps, backDist:backs, bad:iss}; },sh);
    console.log(nm, JSON.stringify(r));
    await p.screenshot({path:`shots/auto-${nm}.png`,clip:{x:150,y:330,width:1100,height:650},fullPage:true}); await p.close(); }
  console.log('errors',errs); await b.close(); })();
