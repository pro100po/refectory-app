const {chromium}=require('playwright');
(async()=>{ const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1400,height:1000}});
  const errs=[]; p.on('pageerror',e=>errs.push('PE '+String(e).slice(0,200))); p.on('console',m=>{ if(m.type()==='error') errs.push('console: '+m.text().slice(0,200)); });
  await p.goto('file://'+process.cwd()+'/index.html'); await p.waitForTimeout(400);
  const r=await p.evaluate(()=>{ closeProjects(); const R=S.rooms[0]; S.cur=R.id; setRoomShape(R,{tpl:'trap',rot:2,p:{kind:'free',a:7,b:4,c:4.5,d:5}}); S.layoutSig=null; recompute(); step=5; render();
    const H=hoodsAll(), svg=document.getElementById('plan'); const g=svg&&[...svg.querySelectorAll('g[clip-path]')].map(x=>x.getAttribute('clip-path')+':'+x.querySelectorAll('rect').length);
    return {hoods:H.list.length, clipped:g, clipDefs:svg?[...svg.querySelectorAll('clipPath')].map(c=>c.id):null}; });
  console.log('free', JSON.stringify(r));
  await p.screenshot({path:'shots/h5.png',clip:{x:150,y:330,width:1100,height:700},fullPage:true});
  await p.evaluate(()=>openReport()); await p.waitForTimeout(500); await p.click('#rep-prev-btn'); await p.waitForTimeout(2500);
  const pr=await p.evaluate(()=>[...document.querySelectorAll('.rep-pagewrap')].map((w,i)=>[i,[...w.querySelectorAll('g[clip-path]')].map(x=>x.getAttribute('clip-path')).join(','), (w.textContent||'').slice(26,60)]).filter(x=>x[1]));
  console.log('print', JSON.stringify(pr));
  if(pr.length){ const el=(await p.$$('.rep-pagewrap'))[pr[pr.length-1][0]]; await el.scrollIntoViewIfNeeded(); await el.screenshot({path:'shots/hprint.png'}); }
  // ручная постановка у косой
  await p.goto('file://'+process.cwd()+'/index.html'); await p.waitForTimeout(400);
  const m=await p.evaluate(()=>{ closeProjects(); const R=S.rooms[0]; S.cur=R.id; setRoomShape(R,{tpl:'trap',rot:0,p:{kind:'right',side:'l',a:6,b:4,h:4}}); S.layoutSig=null; recompute(); step=5; render();
    const u=curUnitsOf(R).find(x=>x.c.mount==='floor'&&!x.parts&&S.layout[x.key]&&x.c.w<=1.2); const c=u.c; S.layoutManual=true; S.layout[u.key]={x:6-c.d/2-0.02-c.w,y:0,rot:0}; recompute();
    const iss=checkUnit(S,curUnitsOf(R),S.layout,u.key).filter(q=>q.key===u.key).map(q=>q.lbl+': '+q.m);
    return {unit:u.c.s||u.key, inRoom:rectInRoom(R,bbox(c,S.layout[u.key])), iss}; });
  console.log('manual', JSON.stringify(m));
  console.log('errors',errs); await b.close(); })();
