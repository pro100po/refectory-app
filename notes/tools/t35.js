const { chromium } = require('playwright');
(async () => {
  const f = process.argv[2]; const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 900 } });
  const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.goto('file://' + __dirname + '/' + f); await p.locator('#pj-screen button', { hasText: 'Открыть пример' }).click(); await p.waitForTimeout(500);
  await p.locator('button[data-step="5"]').first().click(); await p.waitForTimeout(600);
  const out={};
  out.insLen = await p.evaluate(()=>typeof insLen==='function'?[1.004,0.9996,0.9994,1.3].map(insLen):null);
  out.ex = await p.evaluate(()=>S.inserts.map(i=>[Math.round(i.w*1000),Math.round(i.d*1000),i.gap]));
  out.exBad = await p.evaluate(()=>checkLayout(curGeom(),curUnits()).map(i=>i.t+':'+i.m).filter(m=>/налож|пересек|заход/i.test(m)));
  out.rooms = await p.evaluate(()=>[S.room, JSON.stringify(S.rooms[0]).slice(0,400)]);
  // widen kitchen
  await p.evaluate(()=>{ const r=S.rooms.find(r=>/кухн/i.test(r.name))||S.rooms[0]; r.w=+(r.w+0.004).toFixed(3); if(r.shape&&r.shape.p&&r.shape.p.W) r.shape.p.W=r.w; S.layoutSig=''; recompute(); render(); });
  await p.waitForTimeout(400);
  out.wide = await p.evaluate(()=>S.inserts.map(i=>[Math.round(i.w*1000),Math.round(i.d*1000),i.gap]));
  await p.locator('button[data-step="4"]').first().click(); await p.waitForTimeout(500);
  out.sel = await p.evaluate(()=>[...document.querySelectorAll('.irow .nm')].map(e=>e.textContent).filter(t=>/вставк|угол или/.test(t)));
  out.errs=errs; console.log(JSON.stringify(out)); await b.close();
})();
