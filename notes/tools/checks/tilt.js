const {chromium}=require('playwright');
(async()=>{ const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1400,height:1000}});
  const errs=[]; p.on('pageerror',e=>errs.push('PE '+String(e).slice(0,200))); p.on('console',m=>{ if(m.type()==='error') errs.push('console: '+m.text().slice(0,200)); });
  await p.goto('file://'+process.cwd()+'/index.html'); await p.waitForTimeout(400);
  const setup=()=>p.evaluate(()=>{ closeProjects(); const R=S.rooms[0]; S.cur=R.id; setRoomShape(R,{tpl:'rect',p:{W:6,D:4}});
    const d=R.openings.find(o=>o.type==='door'); R.openings=R.openings.filter(o=>o.id!=='dx1'); R.openings.push({...d,id:'dx1',side:'r',off:1.0,w:0.9});
    step=1; rpOpen=true; tiltWallSel='r'; render(); return true; });
  const doTilt=async(end,dir,shift)=>{ await p.evaluate(([e,d])=>{ tiltEndSel=e; tiltDirSel=d; render(); },[end,dir]);
    await p.fill('[data-tilt-shift]',String(shift)); await p.click('[data-tilt-apply]'); await p.waitForTimeout(100);
    return p.evaluate(()=>{ const R=S.rooms[0], o=R.openings.find(x=>x.id==='dx1'); let door=null; if(o){ const q=wallPoint(R,o.side,o.off+o.w/2); door=[o.side, wallName(R,o.side), +q.x.toFixed(3), +q.y.toFixed(3)]; }
      return {poly:R.poly?R.poly.map(v=>[v.x,v.y]):'rect', tpl:R.shape&&R.shape.tpl, door, err:(document.querySelector('.shp-warn')||{}).textContent||null, block:!!document.querySelector('[data-tilt-apply]'), ends:[...document.querySelectorAll('[data-seg="tilt-end"] button')].map(x=>x.textContent)}; }); };
  await setup(); console.log('ends', JSON.stringify(await p.evaluate(()=>[...document.querySelectorAll('[data-seg="tilt-end"] button')].map(x=>x.textContent))));
  console.log('door before', JSON.stringify(await p.evaluate(()=>{ const R=S.rooms[0], o=R.openings.find(x=>x.id==='dx1'), q=wallPoint(R,o.side,o.off+o.w/2); return [q.x,q.y]; })));
  console.log('short 1500', JSON.stringify(await doTilt('end','short',1500)));
  await setup(); console.log('long 1000', JSON.stringify(await doTilt('end','long',1000)));
  await setup(); console.log('5mm', JSON.stringify(await doTilt('end','short',5)));
  await setup(); console.log('short 5900', JSON.stringify(await doTilt('end','short',5900)));
  await setup(); console.log('long 10000', JSON.stringify(await doTilt('end','long',10000)));
  await setup(); console.log('start short 1000', JSON.stringify(await doTilt('start','short',1000)));
  // Г-образное: наклон стены у входящего угла
  const L=await p.evaluate(()=>{ const R=S.rooms[0]; setRoomShape(R,{tpl:'L',rot:0,p:shapeDefaults('L',6,4)}); const ws=roomWalls(R), w=ws.find(x=>x.cornerStart==='reflex'); tiltWallSel=w.id; render(); return wallName(R,w.id); });
  await p.fill('[data-tilt-shift]','500'); await p.click('[data-tilt-apply]'); await p.waitForTimeout(100);
  console.log('L reflex', L, JSON.stringify(await p.evaluate(()=>({poly:S.rooms[0].poly.map(v=>[v.x,v.y]), err:(document.querySelector('.shp-warn')||{}).textContent||null}))));
  await p.screenshot({path:'shots/tilt.png',clip:{x:1000,y:180,width:400,height:820}});
  console.log('errors',errs); await b.close(); })();
