const { chromium } = require('playwright');
(async () => {
  const f=process.argv[2]; const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1366,height:900}});
  const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.goto('file://'+__dirname+'/'+f); await p.locator('#pj-screen button',{hasText:'Открыть пример'}).click(); await p.waitForTimeout(400);
  await p.evaluate(()=>{ window.__t=[]; const o=toast; toast=function(m){ window.__t.push(m); return o(m); }; });
  const go=async n=>{ await p.locator(`button[data-step="${n}"]`).first().click(); await p.waitForTimeout(300); };
  const log=async l=>{ const t=await p.evaluate(()=>{ const x=window.__t; window.__t=[]; return x; }); console.log(l.padEnd(34), JSON.stringify(t)); };
  await go(5); await log('пример → План');
  await go(0); await p.evaluate(()=>{ S.people=120; touch(); render(); }); await log('Исходные 120');
  await go(4); await log('→ Подбор');
  await go(5); await log('→ План');
  await go(4); await go(5); await log('туда-обратно');
  await p.evaluate(()=>{ const x=document.getElementById('auto-lay'); x&&x.click(); }); await p.waitForTimeout(300); await log('Расставить автоматически');
  await go(0); await p.evaluate(()=>{ S.people=80; touch(); render(); }); await go(5); await log('80 → План');
  await p.evaluate(()=>{ S.layoutManual=true; touch(); }); await go(0); await p.evaluate(()=>{ S.people=150; touch(); render(); }); await go(5); await log('ручная правка, 150 → План');
  console.log('errors', errs); await b.close(); })();
