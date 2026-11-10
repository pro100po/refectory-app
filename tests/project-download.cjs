// Node.js 22+, Codex runtime Playwright and installed Chrome (CHROME_PATH optional).
// node tests/project-download.cjs [--unit-only]
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const http = require('node:http');
const { once } = require('node:events');
const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const source = html.slice(html.indexOf('function projectFile(data)'), html.indexOf('// Общий клавиатурный контур'));
const unit = async () => {
  function setup({ browserError, markError, saveError, renderError } = {}) {
    const calls = { clicks: 0, removed: 0, revoked: [], timers: [], marks: [], messages: [], fallback: [], saves: 0, blobs: [] };
    const state = { pid: 'current', name: 'Трапезная', people: 73, rooms: [{ w: 7, d: 4 }] };
    const context = vm.createContext({
      window: {}, S: state, PJ_APP: 'kuhnya-trapeznoy', PJ_FORMAT: 1, Blob,
      safeName: t => t, saveQueue: Promise.resolve(),
      save: () => { calls.saves++; return Promise.resolve(!saveError); },
      STORE: { load: id => id === 'other' ? { ...state, pid: id, name: 'Другой проект', people: 19 } : null,
        mark: async (id, meta) => { calls.marks.push({ id, meta }); if (markError === 'throw') throw Error('mark'); return { ok: !markError }; } },
      URL: { createObjectURL: blob => { assert.match(blob.type, /application\/json/); calls.blobs.push(blob); return 'blob:test'; }, revokeObjectURL: url => calls.revoked.push(url) },
      document: { body: { appendChild: () => {} }, createElement: () => ({ click() { if (browserError) throw Error('browser'); calls.clicks++; }, remove() { calls.removed++; } }), getElementById: () => true },
      renderProjects: () => { if (renderError) throw Error('render'); },
      setTimeout: (fn, ms) => calls.timers.push({ fn, ms }), toast: msg => calls.messages.push(msg),
      showJsonFallback: (text, name) => calls.fallback.push({ text, name })
    });
    vm.runInContext(html.split('\n').find(line => line.startsWith('function safeName(')), context);
    vm.runInContext(source, context);
    return { calls, context, run: id => context.downloadProject(id) };
  }
  {
    const { calls: c, run } = setup(); await run();
    assert.equal(c.clicks, 1); assert.equal(c.marks.length, 1); assert.equal(c.fallback.length, 0);
    assert.equal(c.messages[0], 'Скачивание файла проекта начато');
    assert.ok(Date.parse(c.marks[0].meta.exportedAt));
    assert.equal(c.removed, 1); assert.equal(c.revoked.length, 0); assert.equal(c.timers[0].ms, 60000);
    c.timers[0].fn(); assert.deepEqual(c.revoked, ['blob:test']);
  }
  {
    const { calls: c, run } = setup({ browserError: true }); await run();
    assert.equal(c.fallback.length, 1); assert.equal(c.marks.length, 0); assert.equal(c.removed, 1); assert.deepEqual(c.revoked, ['blob:test']);
    assert.equal(JSON.parse(c.fallback[0].text).project.people, 73);
  }
  for (const options of [{ markError: 'throw' }, { markError: 'false' }, { renderError: true }, { saveError: true }]) {
    const { calls: c, run } = setup(options); await run();
    assert.equal(c.clicks, 1); assert.equal(c.fallback.length, 0);
    assert.equal(JSON.parse(await c.blobs[0].text()).project.people, 73);
    assert.ok(c.messages.every(m => m.startsWith('Скачивание файла проекта начато')));
  }
  {
    const { calls: c, run } = setup(); await run('other'); assert.equal(c.saves, 0); assert.equal(c.marks[0].id, 'other');
    await run('missing'); assert.equal(c.clicks, 1); assert.equal(c.messages.at(-1), 'Проект не найден');
  }
  {
    const { calls: c, context, run } = setup();
    let finishSave; context.saveQueue = new Promise(resolve => { finishSave = resolve; });
    const done = run(); await new Promise(resolve => setImmediate(resolve));
    assert.equal(c.clicks, 1); assert.equal(c.marks.length, 0);
    finishSave(); await done; assert.equal(c.marks.length, 1);
    const name = context.projectFileName({ name: 'Храм / Покрова: кухня' });
    assert.match(name, /^Храм Покрова кухня — \d{4}-\d{2}-\d{2}\.json$/u);
    const data = JSON.parse(await c.blobs[0].text());
    assert.equal(data.app, 'kuhnya-trapeznoy'); assert.equal(data.format, 1); assert.ok(Date.parse(data.savedAt));
  }
  console.log('PASS unit: browser download, errors, cleanup, marks after queued save, save failure, other project, JSON/name');
};

async function browserTests() {
  const executable = process.env.CHROME_PATH || [
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    '/usr/bin/chromium', '/usr/bin/google-chrome'
  ].find(p => fs.existsSync(p));
  if (!executable) throw Error('Chromium not found; set CHROME_PATH');
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'project-download-'));
  const downloads = path.join(temp, 'downloads'); fs.mkdirSync(downloads);
  const server = http.createServer((req, res) => {
    const root = path.resolve(__dirname, '..');
    let requested;
    try { requested = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); } catch { res.writeHead(400); res.end(); return; }
    if(requested==='/' || requested.endsWith('/')) requested += 'index.html';
    const file=path.resolve(root, '.'+requested);
    const relative=path.relative(root,file);
    if(relative.startsWith('..') || path.isAbsolute(relative) || !/^(index\.html|(?:fonts|vendor)\/[^/]+)$/.test(relative.split(path.sep).join('/'))){res.writeHead(404);res.end();return;}
    const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.ttf':'font/ttf','.txt':'text/plain; charset=utf-8'};
    fs.readFile(file,(err,data)=>{if(err){res.writeHead(404);res.end();return;}res.setHeader('Content-Type',mime[path.extname(file)]||'application/octet-stream');res.end(data);});
  });
  const runtime = 'C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1104-2876-0_26.1104.2876.0_x64__3k8sg7r9htsxt/dependencies/node/node_modules';
  const { chromium } = require(path.join(process.env.CODEX_NODE_MODULES || runtime, 'playwright'));
  let browser;
  try {
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    const origin = 'http://127.0.0.1:' + server.address().port;
    browser = await chromium.launchPersistentContext(path.join(temp, 'profile'), { executablePath: executable, headless: true, acceptDownloads: true });
    const page = browser.pages()[0];
    const evaluate = expression => page.evaluate(expression);
    const until = expression => page.waitForFunction(expression);
    await page.goto(origin); await until('typeof downloadProject === "function" && typeof STORE !== "undefined"');
    const downloadEvents=[]; page.on('download', event=>downloadEvents.push(event));
    await evaluate(`window.__urls=[];window.__revoked=[];window.__release=[];
      const originalCreate=URL.createObjectURL.bind(URL), originalRevoke=URL.revokeObjectURL.bind(URL), originalTimeout=window.setTimeout.bind(window);
      URL.createObjectURL=b=>{const u=originalCreate(b);__urls.push(u);return u};
      URL.revokeObjectURL=u=>{__revoked.push(u);originalRevoke(u)};
      window.setTimeout=(fn,ms,...args)=>{if(ms===60000){__release.push(fn);return 0}return originalTimeout(fn,ms,...args)};`);
    async function download(expression, expected) {
      const before=downloadEvents.length, event=page.waitForEvent('download');
      await evaluate(expression); const result=await event; assert.equal(await result.failure(),null);
      const file=path.join(downloads, String(before)+'.json'); await result.saveAs(file);
      const data=JSON.parse(fs.readFileSync(file,'utf8'));
      assert.deepEqual(data.project,expected); assert.equal(data.app,'kuhnya-trapeznoy'); assert.equal(data.format,1); assert.ok(Date.parse(data.savedAt));
      assert.match(result.suggestedFilename(), /^.+ — \d{4}-\d{2}-\d{2}\.json$/u);
      assert.equal(result.suggestedFilename(),await evaluate('projectFileName('+JSON.stringify(expected)+')'));
      await until(`document.querySelectorAll('a[download][href^="blob:"]').length===0`);
      await evaluate('saveQueue'); assert.equal(downloadEvents.length,before+1);
      assert.equal(await evaluate('!!document.getElementById("pj-json")'),false);
      return {file,data,name:result.suggestedFilename()};
    }
    await evaluate(`closeProjects(); createProject(blankProject('Трапезная Покрова',73))`);
    await until('S.pid && saveInfo.ok');
    // Unsaved edits must be in the file, even while saving is queued.
    await evaluate(`S.people=74; S.report.meta.note='Проверка скачивания'; document.getElementById('proj-menu-btn').click()`);
    let expected = await evaluate('JSON.parse(JSON.stringify(S))');
    const first = await download(`document.querySelector('[data-pm="download"], [data-pj="download"]').click()`, expected);
    assert.match(first.name, /^Трапезная Покрова — /u);
    await until('!!STORE.meta(S.pid).exportedAt');
    await evaluate('step=7; render()'); expected = await evaluate('JSON.parse(JSON.stringify(S))');
    await download(`document.querySelector('#main [data-proj="download"], main [data-proj="download"]').click()`, expected);
    await evaluate('openProjects()'); expected = await evaluate('JSON.parse(JSON.stringify(S))');
    await download(`document.querySelector('.pj-inline [data-pa="download"][data-id="'+S.pid+'"]').click()`, expected);
    const current = await evaluate('S.pid');
    await evaluate(`createProject(blankProject('Другой проект',19))`); await until('saveInfo.ok');
    const other = await evaluate('S.pid');
    await evaluate(`openProjectId(${JSON.stringify(current)})`); await until(`S.pid===${JSON.stringify(current)} && saveInfo.ok`);
    await evaluate('openProjects()'); expected = await evaluate(`STORE.load(${JSON.stringify(other)})`);
    await download(`document.querySelector('.pj-inline [data-pa="download"][data-id="${other}"]').click()`, expected);
    assert.equal(await evaluate('S.pid'), current);
    // Import the actual downloaded bytes through the application's real input.
    await evaluate('closeProjects()');
    await page.locator('#pj-file').setInputFiles(first.file);
    await until('!!document.getElementById("pj-replace")');
    await evaluate(`document.getElementById('pj-replace').click()`); await until('saveInfo.ok && !document.getElementById("pj-ov")');
    const meaningful = data => JSON.parse(JSON.stringify(data, (k, v) => ['pid', 'createdAt', 'updatedAt', 'variantOf', 'cur'].includes(k) ? undefined : v));
    assert.deepEqual(meaningful(await evaluate('JSON.parse(JSON.stringify(S))')), meaningful(first.data.project));
    await evaluate(`window.__originalClick=HTMLAnchorElement.prototype.click;HTMLAnchorElement.prototype.click=function(){throw Error('test click failure')};`);
    const priorMark = await evaluate('STORE.meta(S.pid).exportedAt');
    await evaluate('downloadProject()'); assert.equal(await evaluate('!!document.getElementById("pj-json")'), true);
    assert.equal(await evaluate('STORE.meta(S.pid).exportedAt'), priorMark);
    assert.equal(await evaluate('JSON.parse(document.getElementById("pj-json").value).project.people'), 74);
    await evaluate('HTMLAnchorElement.prototype.click=__originalClick;closePjDialog();__release.forEach(fn=>fn())');
    assert.deepEqual(await evaluate('__revoked.slice().sort()'), await evaluate('__urls.slice().sort()'));
    console.log('PASS Chromium: real downloads from menu/estimate/list/other project; filename/JSON; file-input import; failure fallback; URL cleanup; no duplicates');
  } finally {
    if(browser) await browser.close();
    await new Promise(resolve=>server.close(resolve));
    console.log('Browser artifacts: '+temp);
  }
}
(async () => { await unit(); if (!process.argv.includes('--unit-only')) await browserTests(); })().catch(e => { console.error('FAIL', e.stack || e); process.exitCode = 1; });
