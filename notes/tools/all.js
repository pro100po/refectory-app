const {chromium}=require('playwright');
(async()=>{ const b=await chromium.launch(); const p=await b.newPage(); const res={};
for(const f of ['m.html','r.html']){ await p.goto('file://'+__dirname+'/'+f); await p.waitForTimeout(400);
 res[f]=await p.evaluate(()=>{ const base=JSON.stringify(S), out={}; for(const sh of [null,...['L','U','T'].flatMap(t=>[0,1,2,3].map(r=>t+r))]){ S=migrate(JSON.parse(base)); if(sh){ const R=S.rooms[0]; setRoomShape(R,{tpl:sh[0],rot:+sh[1],p:shapeDefaults(sh[0],R.w,R.d)}); }
  for(let s=0;s<8;s++){ step=s; S.layoutSig=null; recompute(); render(); }
  const iss=checkLayout(curGeom(),curUnits());
  out[sh||'ex']={non:Object.keys(S.layout).filter(k=>!k.startsWith('ins:')).sort().map(k=>k+JSON.stringify(S.layout[k])), ins:S.inserts.map(i=>Math.round(i.w*1000)+'×'+Math.round(i.d*1000)).join(' '), bad:iss.filter(i=>i.t==='bad').length, warn:iss.filter(i=>i.t==='warn').length, res:Object.keys(S.layout).length}; } return out; }); }
for(const k in res['m.html']){ const a=res['m.html'][k], c=res['r.html'][k]; const moved=a.non.filter((x,i)=>x!==c.non[i]).map(x=>x.split('{')[0]);
 console.log(k.padEnd(3), 'moved:',moved.join(',')||'-', '| bad',a.bad,'→',c.bad,'| warn',a.warn,'→',c.warn,'| ins',a.ins,'→',c.ins); }
await b.close(); })();
