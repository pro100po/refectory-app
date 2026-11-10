// node tests/equipment-validation.cjs [--unit-only]
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const vm = require('node:vm');
const { once } = require('node:events');
const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
function unit() {
  for (const [, script] of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)) new vm.Script(script);
  assert.match(html, /Number\.isInteger\(Number\(result\.value\)\)/);
  console.log('PASS unit: inline JavaScript syntax and integer quantity guard');
}
async function browserTests() {
  const runtime = 'C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1104-2876-0_26.1104.2876.0_x64__3k8sg7r9htsxt/dependencies/node/node_modules';
  const { chromium } = require(path.join(process.env.CODEX_NODE_MODULES || runtime, 'playwright'));
  const executable = process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'equipment-validation-'));
  const server = http.createServer((req, res) => {
    const name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.resolve(root, name);
    if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
    fs.readFile(file, (err, data) => { if (err) { res.writeHead(404).end(); return; } res.end(data); });
  });
  let browser;
  try {
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    const origin = 'http://127.0.0.1:' + server.address().port;
    browser = await chromium.launchPersistentContext(path.join(temp, 'profile'), { executablePath: executable, headless: true });
    const page = browser.pages()[0]; const external=[];
    page.on('request', r => { if (!r.url().startsWith(origin)) external.push(r.url()); });
    await page.goto(origin); await page.waitForFunction('typeof go === "function"');
    await page.evaluate(async () => { closeProjects(); await createProject(blankProject('Тест',40)); S.existing=[]; go(3); });
    const state = () => page.evaluate(() => JSON.stringify(S.existing));
    const fill = (id, value) => page.locator('#it-'+id).fill(value);
    const newForm = async () => { await page.locator('#ex-new').click(); await page.locator('[data-seg="it-src"] [data-v="own"]').click(); await page.locator('#it-role').selectOption('_other'); await fill('w','500'); await fill('d','600'); await fill('h','700'); };
    const reject = async (field, value, enter=false) => {
      await page.evaluate(() => saveQueue); const before=await state(); const stored=await page.evaluate(() => JSON.stringify(STORE.load(S.pid))); await fill(field,value);
      if (enter) await page.locator('#it-'+field).press('Enter'); else await page.locator('#it-save').click();
      assert.equal(await state(),before,field+' mutated project'); await page.evaluate(() => saveQueue); assert.equal(await page.evaluate(() => JSON.stringify(STORE.load(S.pid))),stored,field+' mutated saved project');
      assert.equal(await page.evaluate(() => document.activeElement.id),'it-'+field);
      assert.equal(await page.locator('#it-'+field).getAttribute('aria-invalid'),'true');
      assert.ok(await page.locator('#it-'+field+' + .field-err-msg').textContent());
    };
    await page.locator('#ex-new').click(); await page.locator('#it-save').click(); assert.equal(await page.evaluate(() => document.activeElement.id),'it-role'); assert.ok(await page.locator('#it-role + .field-err-msg').textContent()); await page.locator('#it-cancel').click();
    await newForm();
    for (const [field, bad, good] of [['w','99999','500'],['w','49','500'],['d','3001','600'],['d','49','600'],['h','19','700'],['h','3501','700'],['kw','-5',''],['kw','101',''],['q','','1'],['q','0','1'],['q','-1','1'],['q','1.5','1'],['q','51','1']]) { await reject(field,bad,field==='q'); await fill(field,good); }
    await fill('w','1'); await fill('q','0'); const before=await state(); await page.locator('#it-save').click();
    assert.equal(await state(),before); assert.equal(await page.evaluate(() => document.activeElement.id),'it-w');
    await fill('w','50'); await fill('d','3000'); await fill('h','3500'); await fill('q','50'); await fill('kw','2,5'); await page.locator('#it-q').press('Enter');
    let item=await page.evaluate(() => S.existing[0]); assert.equal(item.w,50); assert.equal(item.d,3000); assert.equal(item.h,3500); assert.equal(item.qty,50); assert.equal(item.kw,2.5);
    await page.locator('[data-edit]').first().click();
    for (const [field,bad,good] of [['w','99999','6000'],['w','49','6000'],['w','6001','6000'],['d','0','50'],['h','99999','20'],['h','19','20'],['kw','-5','100'],['kw','101','100'],['q','','1'],['q','0','1'],['q','-1','1'],['q','1.5','1'],['q','51','1']]) { await reject(field,bad); await fill(field,good); }
    await page.locator('[data-seg="it-ph"] [data-v="0"]').click(); await page.locator('#it-save').click();
    item=await page.evaluate(() => S.existing[0]); assert.equal(item.kw,0); assert.equal(item.w,6000);
    await page.locator('[data-edit]').first().click();
    await page.locator('#it-role').selectOption(await page.evaluate(() => Object.keys(ROLE_INFO).find(k => k !== 'burners' && ROLE_INFO[k].cap && !ROLE_INFO[k].cap.options)));
    const limits=await page.locator('#it-cap').evaluate(el=>({min:+el.min,max:+el.max}));
    await reject('cap',''); await reject('cap',String(limits.min-1)); await reject('cap',String(limits.max+1)); await fill('cap',String(Math.max(limits.min,1)));
    await page.locator('#it-save').click(); await page.locator('#it-save').waitFor({state:'detached'});
    await page.locator('[data-edit]').first().click(); await page.locator('#it-more').evaluate(el => el.open=true); await page.locator('#it-gas').check();
    await reject('gkw','-5'); await reject('gkw','201'); await fill('gkw',''); await page.locator('#it-gas').uncheck(); await page.locator('#it-save').click();
    await page.locator('#it-save').waitFor({state:'detached'});
    await page.locator('#ex-new').click(); await page.locator('#it-cq').fill('плита'); await page.locator('#it-cq').press('Enter'); await page.waitForFunction(() => document.querySelector('#it-n')?.value); await page.locator('#it-save').click(); await page.locator('#it-save').waitFor({state:'detached'});
    await newForm(); await page.locator('#it-role').selectOption('kettle'); await reject('cap',''); await reject('cap','9'); await reject('cap','501'); await fill('cap','500'); await page.locator('#it-save').click(); await page.locator('#it-save').waitFor({state:'detached'}); assert.equal(await page.evaluate(() => S.existing.at(-1).cap),500);
    assert.deepEqual(external, []);
    console.log('PASS browser: click/Enter, creation/edit, validation, focus, state, optional power, gas, catalog and local requests');
  } finally { if(browser) await browser.close(); await new Promise(resolve => server.close(resolve)); console.log('Browser artifacts: '+temp); }
}
(async()=>{ unit(); if(!process.argv.includes('--unit-only')) await browserTests(); })().catch(e=>{ console.error('FAIL',e.stack||e); process.exitCode=1; });




