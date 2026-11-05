// node doors.js <file> <prefix> [trap] — кропы вокруг подписей дверей: шаг 1, шаг 5, печать
const { chromium } = require('playwright');
(async () => {
  const [f, pre, trap] = process.argv.slice(2); const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 1 });
  const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  await p.goto('file://' + __dirname + '/' + f); await p.locator('#pj-screen button', { hasText: 'Открыть пример' }).click(); await p.waitForTimeout(500);
  if (trap) await p.evaluate(() => { const R=S.rooms[0]; const r=setRoomShape(R,{tpl:'trap',rot:0,p:shapeDefaults('trap',R.w,R.d)}); S.layoutSig=null; recompute(); render(); });
  const labs = await p.evaluate(() => S.openings.filter(o => o.type === 'door').map(o => doorLabel(o)).filter(Boolean));
  const shoot = async (root, tag) => {
    const n = await p.evaluate(([root, labs]) => { window.__dt=[...document.querySelectorAll(root + ' text')].filter(t => labs.includes(t.textContent.trim())); return window.__dt.length; }, [root, labs]);
    const boxes=[]; for (let i=0;i<n;i++){ const bx = await p.evaluate(i => { const t=window.__dt[i]; t.scrollIntoView({block:'center',inline:'center'}); const r = t.getBoundingClientRect(); return { l: t.textContent.trim(), x: r.x, y: r.y, w: r.width, h: r.height }; }, i); await p.waitForTimeout(150);
      const pad = 90; await p.screenshot({ path: `shots/${pre}-${tag}-${i}.png`, clip: { x: Math.max(0, bx.x - pad), y: Math.max(0, bx.y - pad), width: bx.w + 2 * pad, height: bx.h + 2 * pad } }); boxes.push(bx); }
    return boxes.map(b => b.l);
  };
  const out = {};
  for (const st of ['1', '5']) { await p.locator(`button[data-step="${st}"]`).first().click(); await p.waitForTimeout(700); out['s' + st] = await shoot('#plan', 's' + st); }
  await p.evaluate(() => openReport()); await p.waitForTimeout(300); await p.click('#rep-prev-btn'); await p.waitForTimeout(2500);
  out.print = await shoot('.rep-pagewrap', 'pr');
  console.log(JSON.stringify(out), errs); await b.close();
})();
