const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 900 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file://' + __dirname + '/result.html'); await p.locator('#pj-screen button', { hasText: 'Открыть пример' }).click(); await p.waitForTimeout(600);
  await p.locator('button[data-step="1"]').first().click();
  await p.waitForTimeout(500);
  await p.evaluate(() => { openRoomPanel(S.cur); render(); }); await p.waitForTimeout(500);
  const room = await p.evaluate(() => { const r = S.rooms.find(q => q.id === S.cur); return { name: r.name, w: r.w, d: r.d }; }); console.log('room', JSON.stringify(room));
  let h = p.locator('.shp-handle');
  if (!(await h.count())) { const r = p.locator('#plan [data-room]').first(); if (await r.count()) await r.click(); await p.waitForTimeout(400); h = p.locator('.shp-handle'); }
  console.log('handles', await h.count());
  const out = [];
  for (let i = 0; i < await h.count(); i++) {
    const g = h.nth(i), id = await g.getAttribute('data-wall-handle'), bb = await g.boundingBox(); if (!bb) continue;
    const cur = await g.evaluate(e => e.style.cursor), cx = bb.x + bb.width / 2, cy = bb.y + bb.height / 2;
    const dirs = cur === 'ns-resize' ? [[0, 40], [0, -40]] : [[40, 0], [-40, 0]];
    for (const [dx, dy] of dirs) {
      await p.mouse.move(cx, cy); await p.mouse.down(); await p.mouse.move(cx + dx / 2, cy + dy / 2); await p.mouse.move(cx + dx, cy + dy); await p.waitForTimeout(150);
      const lbl = await p.locator('#shp-drag-label').textContent().catch(() => null);
      const ghost = await p.locator('#shp-ghost').getAttribute('points').catch(() => '');
      await p.keyboard.press('Escape'); await p.evaluate(() => window.dispatchEvent(new PointerEvent('pointercancel', { pointerId: 1 })));
      await p.mouse.up(); await p.waitForTimeout(200);
      out.push({ id, cur, dx, dy, lbl, ghost });
    }
  }
  console.log(JSON.stringify(out, null, 1)); console.log('errors', errs);
  await b.close();
})();
