const { chromium } = require('playwright');
(async () => {
  const f = process.argv[2]; const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 900 } });
  await p.goto('file://' + __dirname + '/' + f); await p.locator('#pj-screen button', { hasText: 'Открыть пример' }).click(); await p.waitForTimeout(500);
  await p.locator('button[data-step="5"]').first().click(); await p.waitForTimeout(600);
  const r = await p.evaluate(() => S.inserts.map(i => {
    const u = P.units.find(x => x.key === i.key), pos = S.layout[i.key];
    return { key: i.key, w: i.w, d: i.d, room: i.room, name: u && u.c.n, x: pos && pos.x, y: pos && pos.y, rot: pos && pos.rot };
  }));
  console.log(JSON.stringify(r, null, 1)); await b.close();
})();
