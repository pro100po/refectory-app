const { chromium } = require('playwright');
(async () => {
  const f = process.argv[2]; const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 900 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file://' + __dirname + '/' + f); await p.locator('#pj-screen button', { hasText: 'Открыть пример' }).click(); await p.waitForTimeout(500);
  for (const st of ['5', '4']) { await p.locator(`button[data-step="${st}"]`).first().click(); await p.waitForTimeout(500); }
  const r = await p.evaluate(() => {
    const buyItems = P.items.filter(i => i.src === 'buy').reduce((s, i) => s + i.qty, 0);
    const ins = insertItems().reduce((s, i) => s + i.qty, 0);
    const cost = costCalc().rows.filter(x => x.src === 'buy').reduce((s, x) => s + x.qty, 0);
    const pos = positions().list.filter(x => x.src === 'buy').reduce((s, x) => s + x.qty, 0);
    const meter = [...document.querySelectorAll('.meter .state')].map(e => e.textContent.trim()).find(t => t.includes('купить'));
    return { buyItems, ins, cost, pos, meter };
  });
  console.log(f, JSON.stringify(r), 'errors', errs.length); await b.close();
})();
