const {chromium}=require('playwright');
(async()=>{ const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1400,height:1000}});
  const errs=[]; p.on('pageerror',e=>errs.push('PE '+String(e).slice(0,200))); p.on('console',m=>{ if(m.type()==='error') errs.push('console: '+m.text().slice(0,200)); });
  await p.goto('file://'+process.cwd()+'/index.html'); await p.waitForTimeout(400);
  const r=await p.evaluate(()=>{ closeProjects(); const R=S.rooms[0]; S.cur=R.id; setRoomShape(R,{tpl:'trap',rot:0,p:{kind:'right',side:'l',a:6,b:4,h:4}}); S.layoutSig=null; recompute(); step=5; render(); S.layoutManual=true;
    const w=roomWalls(R).find(x=>!x.axis), u=curUnitsOf(R).find(x=>x.c.mount==='floor'&&!x.parts&&S.layout[x.key]&&x.c.dr);
    for(const k of Object.keys(S.layout)) if(k!==u.key && (()=>{ const q=curUnitsOf(R).find(z=>z.key===k); if(!q) return false; const bb=bbox(q.c,S.layout[k]); return bb.x+bb.w>3.2; })()) delete S.layout[k];
    const pos=S.layout[u.key], bb=bbox(u.c,pos); const t=2.0; pos.x=w.x1+w.dir.x*t+w.nx*0.5-bb.w/2; pos.y=w.y1+w.dir.y*t+w.ny*0.5-bb.h/2; skewPlace(R,u,pos,w.id);
    sel=u.key; selSet=new Set([u.key]); recompute(); render();
    const out={unit:u.c.s+' '+u.c.w+'x'+u.c.d};
    const ch=equipChains(R,curUnitsOf(R),S.layout); out.chain=(ch.sides[w.id]||[]).map(g=>g.kind+':'+Math.round((g.e-g.a)*1000)+(g.bold?'B':''));
    const pl=unitPlace(u,R); out.place=[pl.kind,wallName(R,pl.s),Math.round(pl.a*1000)];
    out.field=[...document.querySelectorAll('[data-pos]')].map(x=>x.dataset.pos+'|'+x.closest('label').textContent.trim()+'|'+x.value);
    const dr=swDrain(roomGeom(S,R),u.c,pos); out.drain={side:dr.side===w.id, stub:+dr.stub.toFixed(3), p:[+dr.p.x.toFixed(3),+dr.p.y.toFixed(3)], distToWall:+((dr.p.x-w.x1)*w.nx+(dr.p.y-w.y1)*w.ny).toFixed(4)};
    out.needGroup=!!document.querySelector('.need-layer g[transform*="rotate"]');
    return out; });
  console.log(JSON.stringify(r));
  // поле «От угла» — изменить на 1000
  const f=await p.$('[data-pos="skt"]'); if(f){ await f.fill('1000'); await f.dispatchEvent('change'); await p.waitForTimeout(150);
    console.log('after skt', JSON.stringify(await p.evaluate(()=>{ const u=P.units.find(x=>x.key===sel), pl=unitPlace(u,S.room); return [pl.kind, Math.round(pl.a*1000), S.layout[sel].sw?1:0, unitPoly(u.c,S.layout[sel]).map(q=>{ const w=wallById(S.room,S.layout[sel].sw); return +((q.x-w.x1)*w.nx+(q.y-w.y1)*w.ny).toFixed(4); })]; }))); }
  await p.screenshot({path:'shots/s3-plan.png',clip:{x:150,y:330,width:1100,height:650},fullPage:true});
  await p.evaluate(()=>openReport()); await p.waitForTimeout(400); await p.click('#rep-prev-btn'); await p.waitForTimeout(2500);
  const rep=await p.evaluate(()=>{ const t=[...document.querySelectorAll('.rep-pagewrap')].map(w=>w.textContent).join(' '); return (t.match(/[^|]{0,60}от угла со стеной \d/g)||[]).slice(0,3); });
  console.log('report', JSON.stringify(rep));
  const idx=await p.evaluate(()=>[...document.querySelectorAll('.rep-pagewrap')].findIndex(w=>/Требуемые подключения/.test(w.textContent||'')&&w.querySelector('svg polygon')));
  if(idx>=0){ const el=(await p.$$('.rep-pagewrap'))[idx]; await el.scrollIntoViewIfNeeded(); await el.screenshot({path:'shots/s3-need.png'}); }
  console.log('needIdx',idx,'errors',errs); await b.close(); })();
