// No dependencies: Node.js 22+ and an installed Chromium browser (CHROME_PATH optional).
// node tests/project-download.cjs [--unit-only]
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const http = require('node:http');
const { spawn } = require('node:child_process');
const { once } = require('node:events');
const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const source = html.slice(html.indexOf('let dlP=null;'), html.indexOf('// Общий клавиатурный контур'));
const unit = async () => {
  function setup({ code, acquisition, browserError, markError, saveError, renderError } = {}) {
    const calls = { clicks: 0, removed: 0, revoked: [], timers: [], marks: [], messages: [], fallback: [], provider: 0, saves: 0, blobs: [] };
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
    if (code || acquisition) context.window.claude = { use: () => {
      if (acquisition) throw acquisition instanceof Error ? acquisition : { code: acquisition };
      return Promise.resolve({ save: async () => { calls.provider++; if (code instanceof Error) throw code; if (code !== 'success') throw { code }; } });
    } };
    vm.runInContext(html.split('\n').find(line => line.startsWith('function safeName(')), context);
    vm.runInContext(source, context);
    return { calls, context, run: id => context.downloadProject(id) };
  }
  for (const code of [undefined, 'success', 'unavailable', 'not_granted', 'capability_disabled', 'capability_removed', 'declined', 'rate_limited', 'unknown', Error('save failed')]) {
    const { calls: c, run } = setup({ code }); await run();
    const browser = !code || ['unavailable', 'not_granted', 'capability_disabled', 'capability_removed'].includes(code);
    const success = browser || code === 'success';
    assert.equal(c.clicks, +browser, String(code)); assert.equal(c.provider, code ? 1 : 0);
    assert.equal(c.marks.length, +success); assert.equal(c.fallback.length, 0);
    if (success) { assert.equal(c.messages[0], 'Скачивание файла проекта начато'); assert.ok(Date.parse(c.marks[0].meta.exportedAt)); }
    if (code === 'declined') assert.equal(c.messages.length, 0);
    if (code === 'rate_limited') assert.match(c.messages[0], /подождите/);
    if (browser) { assert.equal(c.removed, 1); assert.equal(c.revoked.length, 0); assert.equal(c.timers[0].ms, 60000); c.timers[0].fn(); assert.deepEqual(c.revoked, ['blob:test']); }
  }
  for (const acquisition of ['unavailable', 'declined', 'rate_limited', 'unknown', Error('capability failed')]) {
    const { calls: c, run } = setup({ acquisition }); await run();
    const browser = !['declined', 'rate_limited'].includes(acquisition);
    assert.equal(c.clicks, +browser); assert.equal(c.provider, 0);
    assert.equal(c.marks.length, +browser); assert.equal(c.fallback.length, 0);
    if (acquisition === 'declined') assert.equal(c.messages.length, 0);
    if (acquisition === 'rate_limited') assert.match(c.messages[0], /подождите/);
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
  console.log('PASS unit: provider branches, cancellation, errors, cleanup, marks after queued save, save failure, other project, JSON/name');
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
    if (req.url === '/' || req.url === '/index.html') { res.setHeader('Content-Type', 'text/html; charset=utf-8'); res.end(html); }
    else { res.writeHead(404); res.end(); }
  });
  let child, socket, chromeLog = '';
  try {
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    const origin = `http://127.0.0.1:${server.address().port}`;
    child = spawn(executable, ['--headless=new', '--disable-gpu', '--in-process-gpu', '--disable-extensions', '--enable-logging=stderr', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0', `--user-data-dir=${path.join(temp, 'profile')}`, 'about:blank'], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
    child.stderr.on('data', data => { chromeLog += data; });
    const endpoint = await new Promise((resolve, reject) => {
      let stderr = '';
      const timer = setTimeout(() => reject(Error(`Chromium did not start in 20s: ${stderr.slice(-2000)}`)), 20000);
      const fail = e => { clearTimeout(timer); reject(e); };
      child.once('error', fail); child.once('exit', code => fail(Error(`Chromium exited ${code}: ${stderr.slice(-2000)}`)));
      child.stderr.on('data', data => { stderr += data; const m = stderr.match(/DevTools listening on (ws:\/\/\S+)/); if (m) { clearTimeout(timer); resolve(m[1]); } });
    });
    socket = new WebSocket(endpoint); await once(socket, 'open');
    let seq = 0; const pending = new Map(), events = new Set();
    socket.addEventListener('message', event => {
      const m = JSON.parse(event.data);
      if (m.id) { const p = pending.get(m.id); if (p) { pending.delete(m.id); clearTimeout(p.timer); m.error ? p.reject(Error(JSON.stringify(m.error))) : p.resolve(m.result); } }
      else for (const fn of events) fn(m);
    });
    const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
      const id = ++seq, timer = setTimeout(() => { pending.delete(id); reject(Error(`CDP timeout: ${method}`)); }, 20000);
      pending.set(id, { resolve, reject, timer }); socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
    const waitEvent = (method, predicate = () => true) => new Promise((resolve, reject) => {
      const fn = m => { if (m.method === method && predicate(m.params)) { clearTimeout(timer); events.delete(fn); resolve(m.params); } };
      const timer = setTimeout(() => { events.delete(fn); reject(Error(`Event timeout: ${method}`)); }, 20000); events.add(fn);
    });
    const target = await send('Target.createTarget', { url: origin });
    const { sessionId } = await send('Target.attachToTarget', { targetId: target.targetId, flatten: true });
    const evaluate = async expression => {
      let r; try { r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, sessionId); }
      catch (e) { throw Error(`${e.message}; expression: ${expression.slice(0,400)}`); }
      if (r.exceptionDetails) throw Error(JSON.stringify(r.exceptionDetails)); return r.result.value;
    };
    const until = async expression => {
      for (let i = 0; i < 100; i++) { if (await evaluate(expression)) return; await new Promise(r => setTimeout(r, 100)); }
      throw Error(`Condition timeout: ${expression}`);
    };
    await until('typeof downloadProject === "function" && typeof STORE !== "undefined"');
    await send('Browser.setDownloadBehavior', { behavior: 'allowAndName', downloadPath: downloads, eventsEnabled: true });
    const downloadEvents = []; events.add(m => { if (m.method === 'Browser.downloadWillBegin') downloadEvents.push(m.params); });
    // Track real URL release without waiting a minute for each case.
    await evaluate(`window.__urls=[];window.__revoked=[];window.__release=[];
      const originalCreate=URL.createObjectURL.bind(URL), originalRevoke=URL.revokeObjectURL.bind(URL), originalTimeout=window.setTimeout.bind(window);
      URL.createObjectURL=b=>{const u=originalCreate(b);__urls.push(u);return u};
      URL.revokeObjectURL=u=>{__revoked.push(u);originalRevoke(u)};
      window.setTimeout=(fn,ms,...args)=>{if(ms===60000){__release.push(fn);return 0}return originalTimeout(fn,ms,...args)};`);
    async function download(expression, expected) {
      const before = downloadEvents.length;
      const began = waitEvent('Browser.downloadWillBegin');
      const complete = waitEvent('Browser.downloadProgress', p => p.state === 'completed');
      await evaluate(expression); const event = await began; await complete;
      const file = path.join(downloads, event.guid);
      const data = JSON.parse(fs.readFileSync(file, 'utf8'));
      assert.deepEqual(data.project, expected); assert.equal(data.app, 'kuhnya-trapeznoy'); assert.equal(data.format, 1); assert.ok(Date.parse(data.savedAt));
      assert.match(event.suggestedFilename, /^.+ — \d{4}-\d{2}-\d{2}\.json$/u);
      assert.equal(event.suggestedFilename, await evaluate(`projectFileName(${JSON.stringify(expected)})`));
      await until(`document.querySelectorAll('a[download][href^="blob:"]').length === 0`);
      await evaluate('Promise.all([saveQueue])');
      assert.equal(downloadEvents.length, before + 1);
      assert.equal(await evaluate('!!document.getElementById("pj-json")'), false);
      return { file, data, name: event.suggestedFilename };
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
    const { root } = await send('DOM.getDocument', {}, sessionId);
    const { nodeId } = await send('DOM.querySelector', { nodeId: root.nodeId, selector: '#pj-file' }, sessionId);
    await send('DOM.setFileInputFiles', { nodeId, files: [first.file] }, sessionId);
    await until('!!document.getElementById("pj-replace")');
    await evaluate(`document.getElementById('pj-replace').click()`); await until('saveInfo.ok && !document.getElementById("pj-ov")');
    const meaningful = data => JSON.parse(JSON.stringify(data, (k, v) => ['pid', 'createdAt', 'updatedAt', 'variantOf', 'cur'].includes(k) ? undefined : v));
    assert.deepEqual(meaningful(await evaluate('JSON.parse(JSON.stringify(S))')), meaningful(first.data.project));
    // Real browser provider branches: no duplicate native download after success/cancel.
    for (const code of ['success', 'declined', 'rate_limited', 'unavailable', 'not_granted', 'capability_disabled', 'capability_removed', 'unknown']) {
      const before = downloadEvents.length;
      await evaluate(`dlP=null;window.__providerCalls=0;window.claude={use:async()=>({save:async()=>{__providerCalls++;${code === 'success' ? '' : `throw {code:${JSON.stringify(code)}}`} }})}`);
      const fallback = ['unavailable', 'not_granted', 'capability_disabled', 'capability_removed'].includes(code);
      if (fallback) await download('downloadProject()', await evaluate('JSON.parse(JSON.stringify(S))'));
      else { await evaluate('downloadProject()'); assert.equal(downloadEvents.length, before); }
      assert.equal(await evaluate('__providerCalls'), 1);
    }
    await evaluate(`dlP=null;window.claude={use:async()=>{throw Error('capability failed')}}`);
    await download('downloadProject()', await evaluate('JSON.parse(JSON.stringify(S))'));
    {
      const before = downloadEvents.length;
      const priorMark = await evaluate('STORE.meta(S.pid).exportedAt');
      await evaluate(`dlP=null;window.__providerCalls=0;window.claude={use:async()=>({save:async()=>{__providerCalls++;throw Error('save failed')}})};downloadProject()`);
      assert.equal(downloadEvents.length, before);
      assert.equal(await evaluate('__providerCalls'), 1);
      assert.equal(await evaluate('STORE.meta(S.pid).exportedAt'), priorMark);
    }
    await evaluate(`window.claude=undefined;dlP=null;window.__originalClick=HTMLAnchorElement.prototype.click;HTMLAnchorElement.prototype.click=function(){throw Error('test click failure')};`);
    const priorMark = await evaluate('STORE.meta(S.pid).exportedAt');
    await evaluate('downloadProject()'); assert.equal(await evaluate('!!document.getElementById("pj-json")'), true);
    assert.equal(await evaluate('STORE.meta(S.pid).exportedAt'), priorMark);
    assert.equal(await evaluate('JSON.parse(document.getElementById("pj-json").value).project.people'), 74);
    await evaluate('HTMLAnchorElement.prototype.click=__originalClick;closePjDialog();__release.forEach(fn=>fn())');
    assert.deepEqual(await evaluate('__revoked.slice().sort()'), await evaluate('__urls.slice().sort()'));
    console.log('PASS Chromium: real downloads from menu/estimate/list/other project; filename/JSON; file-input import; provider branches; failure fallback; URL cleanup; no duplicates');
  } finally {
    fs.writeFileSync(path.join(temp, 'chromium.log'), chromeLog);
    if (socket && socket.readyState === WebSocket.OPEN) socket.close();
    if (child && child.exitCode === null) { child.kill(); await Promise.race([once(child, 'exit').catch(() => {}), new Promise(r => setTimeout(r, 3000))]); }
    server.close();
    // Keep browser output for diagnosing a failed run; all artifacts are temporary.
    console.log(`Browser artifacts: ${temp}`);
  }
}
(async () => { await unit(); if (!process.argv.includes('--unit-only')) await browserTests(); })().catch(e => { console.error('FAIL', e.stack || e); process.exitCode = 1; });
