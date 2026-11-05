// отпечаток печати: node fpprint.js <index.html> <out.json>
const {chromium}=require('playwright'); const fs=require('fs');
(async()=>{ const b=await chromium.launch(); const out={}, errs=[];
  const shapes=[null,...['L','U','T'].flatMap(t=>[0,1,2,3].map(r=>({tpl:t,rot:r})))];
  for(const sh of shapes){ const p=await b.newPage({viewport:{width:1400,height:1000}}); p.on('pageerror',e=>errs.push(String(e).slice(0,150)));
    await p.goto('file://'+require('path').resolve(process.argv[2])); await p.waitForTimeout(300);
    await p.evaluate(sh=>{ closeProjects(); if(sh){ const R=S.rooms[0]; setRoomShape(R,{tpl:sh.tpl,rot:sh.rot,p:shapeDefaults(sh.tpl,R.w,R.d)}); } S.layoutSig=null; step=5; recompute(); render(); openReport(); },sh);
    await p.waitForTimeout(300); await p.click('#rep-prev-btn'); await p.waitForTimeout(2200);
    out[sh?sh.tpl+sh.rot:'ex']=await p.evaluate(()=>{ const h=s=>{let x=0;for(let i=0;i<s.length;i++)x=(x*31+s.charCodeAt(i))|0;return x;}; return [...document.querySelectorAll('.rep-pagewrap')].map(w=>h(w.innerHTML.replace(/\d{2}\.\d{2}\.\d{4}/g,''))).join(','); });
    await p.close(); }
  out.errors=errs; fs.writeFileSync(process.argv[3],JSON.stringify(out)); await b.close(); console.log('ok', Object.keys(out).length); })();
