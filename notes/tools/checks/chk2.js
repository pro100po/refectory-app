const {chromium}=require('playwright');
(async()=>{ const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1400,height:1000}});
  const errs=[]; p.on('pageerror',e=>errs.push('PE '+String(e).slice(0,200))); p.on('console',m=>{ if(m.type()==='error') errs.push('console: '+m.text().slice(0,200)); });
  await p.goto('file://'+process.cwd()+'/index.html'); await p.waitForTimeout(400);
  const r=await p.evaluate(()=>{ closeProjects(); const R=S.rooms[0]; S.cur=R.id; setRoomShape(R,{tpl:'trap',rot:0,p:{kind:'right',side:'l',a:6,b:4,h:4}}); S.layoutSig=null; recompute(); step=5; render(); S.layoutManual=true;
    const w=roomWalls(R).find(x=>!x.axis), us=curUnitsOf(R).filter(x=>x.c.mount==='floor'&&!x.parts&&S.layout[x.key]&&x.c.w<=0.9), A=us[0], B=us[1], C=us[2];
    const putAt=(u,t)=>{ const pos=S.layout[u.key]; delete pos.ang; delete pos.sw; const bb=bbox(u.c,pos), cx=w.x1+w.dir.x*t+w.nx*0.5, cy=w.y1+w.dir.y*t+w.ny*0.5; pos.x=cx-bb.w/2; pos.y=cy-bb.h/2; return skewPlace(R,u,pos,w.id); };
    const iss=k=>checkUnit(S,curUnitsOf(R),S.layout,k).filter(q=>q.key===k).map(q=>q.lbl);
    const pair=()=>checkUnit(S,curUnitsOf(R),S.layout).filter(q=>(q.key===A.key||q.key===B.key)).map(q=>q.key===A.key?'A:'+q.lbl:'B:'+q.lbl);
    // убрать прочие аппараты подальше от косой стены: в резерв не трогаем, просто проверяем пары
    for(const k of Object.keys(S.layout)) if(![A.key,B.key,C.key].includes(k)) delete S.layout[k];
    const out={A:A.c.s+' '+A.c.w+'x'+A.c.d, B:B.c.s+' '+B.c.w+'x'+B.c.d};
    putAt(A,1.0); putAt(B,1.0+(A.c.w+B.c.w)/2+0.002);
    out.side=pair().filter(x=>/Наложение|Выходит/.test(x));
    out.aabbOverlap=ov(bbox(A.c,S.layout[A.key]),bbox(B.c,S.layout[B.key]));
    putAt(B,1.0+(A.c.w+B.c.w)/2-0.2); out.overlap=pair().filter(x=>/Наложение/.test(x));
    putAt(B,3.4);
    // обычный аппарат C перед A на 500 мм
    const pa=S.layout[A.key], d=frontDir(pa), F=frontPoly(A.c,pa,0), mx=F.reduce((s,v)=>s+v.x,0)/4, my=F.reduce((s,v)=>s+v.y,0)/4;
    const pc=S.layout[C.key]; delete pc.ang; delete pc.sw; pc.rot=0; const bc=bbox(C.c,pc); const cx=mx+d.x*(0.5+Math.max(bc.w,bc.h)/2), cy=my+d.y*(0.5+Math.max(bc.w,bc.h)/2); pc.x=cx-bc.w/2; pc.y=cy-bc.h/2;
    out.front=iss(A.key); const g=frontGap(A,R); out.gap={dist:+g.dist.toFixed(3), ray:g.ray?[+g.ray.dx.toFixed(3),+g.ray.dy.toFixed(3)]:null, hit:g.hit?g.hit.o.c.s:null, dir:[+d.x.toFixed(3),+d.y.toFixed(3)], wallN:[+w.nx.toFixed(3),+w.ny.toFixed(3)]};
    sel=A.key; selSet=new Set([A.key]); render(); return out; });
  console.log(JSON.stringify(r));
  await p.screenshot({path:'shots/chk2.png',clip:{x:150,y:330,width:1100,height:650},fullPage:true});
  console.log('errors',errs); await b.close(); })();
