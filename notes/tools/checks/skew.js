const {chromium}=require('playwright');
(async()=>{ const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1400,height:1000}});
  const errs=[]; p.on('pageerror',e=>errs.push('PE '+String(e).slice(0,200))); p.on('console',m=>{ if(m.type()==='error') errs.push('console: '+m.text().slice(0,200)); });
  await p.goto('file://'+process.cwd()+'/index.html'); await p.waitForTimeout(400);
  const key=await p.evaluate(()=>{ closeProjects(); const R=S.rooms[0]; S.cur=R.id; setRoomShape(R,{tpl:'trap',rot:0,p:{kind:'right',side:'l',a:6,b:4,h:4}}); S.layoutSig=null; recompute(); step=5; render();
    const u=curUnitsOf(R).find(x=>x.c.mount==='floor'&&!x.parts&&S.layout[x.key]&&Math.abs(x.c.w-0.8)<0.01&&Math.abs(x.c.d-0.8)<0.01)||curUnitsOf(R).find(x=>x.c.mount==='floor'&&!x.parts&&S.layout[x.key]);
    sel=u.key; selSet=new Set([u.key]); render(); return u.key; });
  const st=()=>p.evaluate(k=>{ const R=S.rooms[0], u=P.units.find(x=>x.key===k), pos=S.layout[k], w=roomWalls(R).find(x=>!x.axis), poly=unitPoly(u.c,pos), b=bbox(u.c,pos);
    const dist=q=>+((q.x-w.x1)*w.nx+(q.y-w.y1)*w.ny).toFixed(4);
    const iss=checkUnit(S,curUnitsOf(R),S.layout,k).filter(q=>q.key===k).map(q=>q.lbl);
    return {n:u.c.s, wd:[u.c.w,u.c.d], pos:{rot:pos.rot,ang:pos.ang,sw:pos.sw===w.id}, center:[+(b.x+b.w/2).toFixed(3),+(b.y+b.h/2).toFixed(3)], wallDist:poly.map(dist), inRoom:poly.every(q=>pointInRoom(R,q.x,q.y,0.004)), iss,
      btn:[...document.querySelectorAll('[data-act="skew"],[data-act="unskew"]')].map(x=>x.textContent)}; },key);
  console.log('before', JSON.stringify(await st()));
  await p.click('.sel-bar [data-act="skew"]'); await p.waitForTimeout(150); console.log('skew', JSON.stringify(await st()));
  await p.screenshot({path:'shots/skew-plan.png',clip:{x:150,y:330,width:1100,height:650},fullPage:true});
  for(let i=0;i<6;i++) await p.evaluate(()=>planAct('d')); console.log('down x6', JSON.stringify(await st()));
  // перетаскивание мышью
  const box=await (await p.$(`.it[data-key="${key}"]`)).boundingBox(); await p.mouse.move(box.x+box.width/2,box.y+box.height/2); await p.mouse.down(); for(let i=1;i<=8;i++) await p.mouse.move(box.x+box.width/2-5*i,box.y+box.height/2-12*i); await p.mouse.up(); await p.waitForTimeout(150);
  console.log('drag', JSON.stringify(await st()));
  await p.evaluate(()=>{ sel=sel; render(); });
  const c0=(await st()).center; await p.evaluate(()=>planAct('rot')); const r1=await st(); console.log('rot', JSON.stringify(r1), 'centerKept', JSON.stringify(c0), JSON.stringify(r1.center));
  await p.evaluate(()=>planAct('skew')); const c1=(await st()).center; await p.evaluate(()=>planAct('unskew')); const r2=await st(); console.log('unskew', JSON.stringify(r2), JSON.stringify(c1));
  await p.evaluate(()=>planAct('skew'));
  await p.evaluate(()=>openReport()); await p.waitForTimeout(500); await p.click('#rep-prev-btn'); await p.waitForTimeout(2500);
  const idx=await p.evaluate(()=>[...document.querySelectorAll('.rep-pagewrap')].findIndex(w=>/Расстановка оборудования/.test(w.textContent||'')&&w.querySelector('svg')));
  if(idx>=0){ const el=(await p.$$('.rep-pagewrap'))[idx]; await el.scrollIntoViewIfNeeded(); await el.screenshot({path:'shots/skew-print.png'}); }
  console.log('errors',errs); await b.close(); })();
