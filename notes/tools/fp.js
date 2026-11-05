// отпечаток: node fp.js <index.html> <out.json>
const {chromium}=require('playwright'); const fs=require('fs'), crypto=require('crypto');
(async()=>{ const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1400,height:900}});
  const errs=[]; p.on('pageerror',e=>errs.push(String(e)));
  await p.goto('file://'+require('path').resolve(process.argv[2])); await p.waitForTimeout(500);
  const r=await p.evaluate(()=>{ const h=s=>{let x=0;for(let i=0;i<s.length;i++)x=(x*31+s.charCodeAt(i))|0;return x;};
    const out={tpl:h(JSON.stringify(['rect','L','U','T'].flatMap(t=>[0,1,2,3].map(r=>shapeTemplate(t,r,shapeDefaults(t,6,4))))))};
    const base=JSON.stringify(S); const shapes=[null,...['L','U','T'].flatMap(t=>[0,1,2,3].map(r=>({tpl:t,rot:r})))];
    for(const sh of shapes){ S=migrate(JSON.parse(base)); const key=sh?sh.tpl+sh.rot:'ex';
      try{ if(sh){ const R=S.rooms[0]; const res=setRoomShape(R,{tpl:sh.tpl,rot:sh.rot,p:shapeDefaults(sh.tpl,R.w,R.d)}); if(res.error){out[key]='err:'+res.error; continue;} }
        const v=[]; for(let i=0;i<STEPS.length;i++){ step=i; S.layoutSig=null; recompute(); render(); v.push(h([...document.body.children].filter(e=>e.tagName!=="SCRIPT"&&e.tagName!=="STYLE").map(e=>e.outerHTML).join(""))); }
        v.push(h(JSON.stringify(S.layout))); out[key]=v.join(','); }catch(e){ out[key]='EXC '+e.message; } }
    return out; });
  r.errors=errs; fs.writeFileSync(process.argv[3],JSON.stringify(r,null,1)); console.log(JSON.stringify(r).slice(0,600)); await b.close(); })();
