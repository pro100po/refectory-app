const {chromium}=require('playwright');
(async()=>{ const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1400,height:900}});
  const errs=[]; p.on('pageerror',e=>errs.push(String(e).slice(0,200)));
  await p.goto('file://'+require('path').resolve(process.argv[2])); await p.waitForTimeout(500);
  const r=await p.evaluate(()=>{ const out={}; const base=JSON.stringify(S);
    const polys={iso:[{x:0,y:0},{x:6,y:0},{x:5,y:4},{x:1,y:4}], right:[{x:0,y:0},{x:6,y:0},{x:4,y:4},{x:0,y:4}], acute:[{x:0,y:0},{x:8,y:0},{x:8,y:4},{x:1.1,y:4}]};
    for(const k in polys){ S=migrate(JSON.parse(base)); const R=S.rooms[0]; R.poly=polys[k]; R.w=Math.max(...R.poly.map(q=>q.x)); R.d=Math.max(...R.poly.map(q=>q.y)); delete R.shape;
      const o={exc:[]};
      for(let i=0;i<STEPS.length;i++){ try{ step=i; S.layoutSig=null; recompute(); render(); }catch(e){ o.exc.push(i+': '+e.message); } }
      try{ const ws=roomWalls(R), sk=ws.filter(w=>!w.axis); o.skew=sk.map(w=>w.id+' rot='+wallRot(w));
        const us=curUnitsOf(R).filter(u=>S.layout[u.key]); o.placed=us.length; o.wh=JSON.stringify(S.layout["b:wh80:0"]||null); o.ins=Object.keys(S.layout).filter(k=>k.startsWith("ins:")).length;
        o.atSkew=us.filter(u=>{ const bb=bbox(u.c,S.layout[u.key]); return sk.some(w=>backDist(R,w,bb)<0.05); }).map(u=>u.key+(u.c.mount||''));
        o.outside=us.filter(u=>!rectInRoom(R,bbox(u.c,S.layout[u.key]),0.01)).map(u=>u.key);
        o.fg=us.filter(u=>u.c.mount==='floor').map(u=>{ try{ const g=frontGap(u,R); return Number.isFinite(g.dist)?null:u.key+':nan'; }catch(e){ return u.key+':'+e.message; } }).filter(Boolean);
        const T=30, P=contourPts(R,T/2); o.thick=ws.map((w,i)=>{ const a=P[i], c=P[(i+1)%P.length]; const d=x=>(x.x/100-w.x1)*w.nx+(x.y/100-w.y1)*w.ny; return [d(a),d(c)].map(v=>+(-v*100).toFixed(3)).join('/'); });
      }catch(e){ o.exc.push('check: '+e.message); }
      out[k]=o; }
    return out; });
  console.log(JSON.stringify(r,null,1)); console.log('pageerrors',errs); await b.close(); })();
