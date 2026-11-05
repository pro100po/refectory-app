const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 900 } });
  await p.goto('file://' + __dirname + '/m.html'); await p.locator('#pj-screen button', { hasText: 'Открыть пример' }).click(); await p.waitForTimeout(500);
  const info = await p.evaluate(() => S.openings.filter(o => o.type === 'door').map(o => ({ id: o.id, side: o.side, off: o.off, w: o.w, swing: o.swing, to: o.to, lab: doorLabel(o), room: o.room })));
  console.log(JSON.stringify(info));
  for (const st of ['1', '5']) {
    await p.locator(`button[data-step="${st}"]`).first().click(); await p.waitForTimeout(700);
    const svg = p.locator('#plan'); await svg.screenshot({ path: `door-step${st}.png` });
  }
  await b.close();
})();
