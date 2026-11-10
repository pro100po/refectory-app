// node tests/app-autonomy.cjs [--unit-only]
// Browser dependencies are supplied by Codex runtime; no project install is needed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const vm = require('node:vm');
const { once } = require('node:events');
const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

async function unit() {
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)];
  for (const [, source] of scripts) new vm.Script(source);
  assert.doesNotMatch(html, /window\.claude|claude:|getDl\(|repDlState|fonts\.googleapis|https:\/\/(?:cdnjs|cdn\.jsdelivr)/);
  const libs = vm.runInNewContext(html.match(/const PDF_LIBS=(\[[^;]+\]);/)[1]);
  for (const file of libs) assert.ok(fs.statSync(path.join(root, file)).size > 30000, file);
  const css = fs.readFileSync(path.join(root, 'fonts/ui-fonts.css'), 'utf8');
  for (const [, file] of css.matchAll(/url\('\.\/([^']+)'\)/g)) assert.ok(fs.statSync(path.join(root, 'fonts', file)).size > 100000, file);
  const buttons = [{}, {}], progress = [], messages = [];
  let release, builds = 0, downloads = 0, fail = false;
  const context = vm.createContext({
    document: { querySelectorAll: () => buttons },
    setProg: t => progress.push(t), toast: t => messages.push(t), console: { error() {} },
    reportFileName: () => 'Трапезная.pdf',
    buildReportPdf: async () => { builds++; await new Promise(resolve => { release = resolve; }); if (fail) throw Error('local asset failed'); return new Blob(['%PDF-test']); },
    downloadBrowserPdf: () => { downloads++; }
  });
  vm.runInContext(html.slice(html.indexOf('function updRepDl()'), html.indexOf('function repEstimate()')), context);
  vm.runInContext(html.slice(html.indexOf('async function downloadReport()'), html.indexOf('function openPreview()')), context);
  let pending = context.downloadReport();
  assert.ok(buttons.every(b => b.disabled));
  await context.downloadReport(); assert.equal(builds, 1);
  release(); await pending;
  assert.equal(downloads, 1); assert.ok(buttons.every(b => !b.disabled));
  fail = true; pending = context.downloadReport(); release(); await pending;
  assert.equal(downloads, 1); assert.match(progress.at(-1), /Не удалось собрать PDF/);
  assert.ok(buttons.every(b => !b.disabled));
  fail = false; pending = context.downloadReport(); release(); await pending;
  assert.equal(downloads, 2); assert.equal(messages.at(-1), 'Скачивание PDF начато');
  // Actual loader promises reset after a rejected asset and can be retried.
  let scriptFailures = 1, fontFailures = 1;
  const loader = vm.createContext({
    window: { jspdf: { jsPDF() {} } },
    document: { createElement: () => ({}), head: { appendChild(s) { queueMicrotask(() => scriptFailures-- > 0 ? s.onerror() : s.onload()); } }, fonts: { add() {} } },
    fetch: async () => ({ ok: fontFailures-- <= 0, arrayBuffer: async () => new ArrayBuffer(4) }),
    FontFace: class { async load() {} }, btoa: s => Buffer.from(s, 'binary').toString('base64')
  });
  vm.runInContext(html.slice(html.indexOf('const PDF_LIBS='), html.indexOf('const hex=c=>')), loader);
  await assert.rejects(loader.loadPdfLibs(), /Не загрузилась библиотека/);
  await loader.loadPdfLibs();
  await assert.rejects(loader.loadPdfFonts(), /Не загрузился шрифт/);
  await loader.loadPdfFonts();
  console.log('PASS autonomy unit: script syntax, local assets, PDF busy/double click/error/retry, library/font retry');
}

async function browser() {
  const runtime = 'C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1104-2876-0_26.1104.2876.0_x64__3k8sg7r9htsxt/dependencies/node/node_modules';
  const { chromium } = require(path.join(process.env.CODEX_NODE_MODULES || runtime, 'playwright'));
  const artifacts = fs.mkdtempSync(path.join(os.tmpdir(), 'app-autonomy-'));
  const server = http.createServer((req, res) => {
    let pathname;
    try { pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); } catch { res.writeHead(400).end(); return; }
    if (pathname === '/refectory-app/') pathname += 'index.html';
    if (!pathname.startsWith('/refectory-app/')) { res.writeHead(404).end(); return; }
    const file = path.resolve(root, pathname.slice('/refectory-app/'.length));
    const relative = path.relative(root, file).split(path.sep).join('/');
    if (!/^(index\.html|(?:fonts|vendor)\/[^/]+)$/.test(relative)) { res.writeHead(404).end(); return; }
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404).end(); return; }
      res.setHeader('Content-Type', ({ '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.ttf': 'font/ttf', '.txt': 'text/plain; charset=utf-8' })[path.extname(file)] || 'application/octet-stream');
      res.end(data);
    });
  });
  let chrome;
  try {
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    const origin = `http://127.0.0.1:${server.address().port}`;
    // Every run gets a fresh, disposable profile. Routing and CDP both disable cache.
    chrome = await chromium.launchPersistentContext(path.join(artifacts, 'profile'), {
      executablePath: process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
      headless: true, acceptDownloads: true, viewport: { width: 1440, height: 1000 },
      args: ['--disable-extensions', '--disable-background-networking']
    });
    const external = [], errors = [], requests = [];
    await chrome.route('**/*', async route => {
      const url = route.request().url(); requests.push(url);
      if (/^https?:/.test(url) && new URL(url).origin !== origin) { external.push(url); await route.abort(); }
      else await route.continue();
    });
    const page = chrome.pages()[0]; page.on('pageerror', e => errors.push(e.message));
    const cdp = await chrome.newCDPSession(page); await cdp.send('Network.enable'); await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
    await page.goto(origin + '/refectory-app/');
    await page.waitForFunction(() => typeof downloadProject === 'function');
    await page.evaluate(async () => { closeProjects(); await createProject(blankProject('Автономная трапезная', 60)); });
    await page.waitForFunction(() => S.pid && saveInfo.ok);
    // Render calculation, room/plan and estimate through the normal render dispatcher.
    for (const n of [0, 1, 3, 4, 5, 7]) {
      await page.evaluate(n => { step = n; render(); }, n);
      assert.ok((await page.locator('#main').innerText()).length > 50);
    }
    await page.evaluate(() => document.fonts.ready);
    assert.deepEqual(await page.evaluate(() => [document.fonts.check('500 16px Alegreya', 'Трапезная'), document.fonts.check('600 16px "IBM Plex Sans"', 'Кухня'), document.fonts.check('500 16px "IBM Plex Mono"', 'Смета')]), [true, true, true]);
    await page.screenshot({ path: path.join(artifacts, 'desktop.png'), fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: path.join(artifacts, 'mobile.png'), fullPage: true });
    await page.setViewportSize({ width: 1440, height: 1000 });
    const jsonEvent = page.waitForEvent('download'); await page.evaluate(() => downloadProject());
    const json = await jsonEvent; assert.match(json.suggestedFilename(), /^Автономная трапезная — .*\.json$/u);
    const data = JSON.parse(fs.readFileSync(await json.path(), 'utf8')); assert.equal(data.project.people, 60);
    await page.evaluate(() => openReport());
    // Fail an actual local library request once; retry must succeed without reload.
    await page.route('**/vendor/jspdf.umd.min.js', route => route.abort(), { times: 1 });
    await page.locator('#rep-dl').click();
    await page.waitForFunction(() => !repBusy && document.getElementById('rep-prog').textContent.includes('Не удалось'));
    async function pdfDownload(selector, filename) {
      const downloads = []; const record = d => downloads.push(d); page.on('download', record);
      try {
        const event = page.waitForEvent('download'); await page.locator(selector).click();
        await page.waitForFunction(() => repBusy);
        assert.ok(await page.locator('[data-rep-dl]').evaluateAll(bs => bs.every(b => b.disabled)));
        await page.evaluate(() => downloadReport()); // Duplicate while busy must do nothing.
        const result = await event; assert.equal(await result.failure(), null);
        const bytes = fs.readFileSync(await result.path()); assert.equal(bytes.subarray(0, 5).toString(), '%PDF-');
        assert.ok(bytes.length > 10000); assert.match(bytes.toString('latin1'), /\/Type\s*\/Page\b/);
        await result.saveAs(path.join(artifacts, filename));
        await page.waitForFunction(() => !repBusy);
        assert.ok(await page.locator('[data-rep-dl]').evaluateAll(bs => bs.every(b => !b.disabled)));
        assert.equal(downloads.length, 1);
      } finally { page.off('download', record); }
    }
    await pdfDownload('#rep-dl', 'dialog.pdf');
    await page.locator('#rep-prev-btn').click();
    await page.waitForFunction(() => document.querySelector('#rep-prev-scroll .rp-page'));
    await pdfDownload('#rep-prev-dl', 'preview.pdf');
    // Force a real font reload failure, then retry the download.
    await page.evaluate(() => { pdfFontsP = null; });
    await page.route('**/fonts/IBMPlexSans-Regular.ttf', route => route.abort(), { times: 1 });
    await page.locator('#rep-prev-dl').click();
    await page.waitForFunction(() => !repBusy && document.getElementById('rep-prev-prog').textContent.includes('Не удалось'));
    await pdfDownload('#rep-prev-dl', 'font-retry.pdf');
    assert.equal(requests.filter(u => u.includes('/vendor/')).length > 0, true);
    assert.deepEqual(external, [], 'External network requests attempted'); assert.deepEqual(errors, []);
    console.log('PASS clean Chrome: nested URL, no external requests, project/calculation/plan/estimate/preview, JSON/PDF, PDF busy/repeat/local asset retry, font checks and screenshots');
  } finally {
    if (chrome) await chrome.close();
    await new Promise(resolve => server.close(resolve));
    console.log(`Autonomy artifacts for PDF rendering and visual comparison: ${artifacts}`);
  }
}
(async () => { await unit(); if (!process.argv.includes('--unit-only')) await browser(); })().catch(e => { console.error('FAIL', e.stack || e); process.exitCode = 1; });
