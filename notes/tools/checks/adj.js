const {chromium}=require('playwright');
(async()=>{ const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1400,height:1000}});
  const errs=[]; p.on('pageerror',e=>errs.push('PE '+String(e).slice(0,200))); p.on('console',m=>{ if(m.type()==='error') errs.push('console: '+m.text().slice(0,200)); });
  await p.goto('file://'+process.cwd()+'/index.html'); await p.waitForTimeout(400);
  const r=await p.evaluate(()=>{ closeProjects(); const out={rooms:S.rooms.length};
    const A=S.rooms[0]; S.rooms.push({id:'rB', name:'Соседнее', autoName:false, x:0, y:0, w:3, d:3, roles:[], openings:[], points:[]}); const B=S.rooms[S.rooms.length-1]; S.rooms.slice(1,-1).forEach(o=>{ o.x+=60; });
    setRoomShape(A,{tpl:'trap',rot:0,p:{kind:'right',side:'l',a:6,b:4,h:4}}); A.x=0; A.y=0;
    let res=setRoomShape(B,{tpl:'custom',pts:[{x:0,y:0},{x:4,y:0},{x:4,y:4},{x:-2,y:4}]}); out.setB=res.error||'ok';
    const g=0.12, n={x:0.894427191,y:0.447213595}; const P0=roomWalls(B).find(w=>!w.axis); B.x=6+n.x*g-P0.x2; B.y=0+0.447213595*0.12-P0.y2; out.Bp=[P0.x1,P0.y1,P0.x2,P0.y2];
    const wa=roomWalls(A).find(w=>!w.axis), wb=roomWalls(B).find(w=>!w.axis);
    out.walls=[wa.id,wb.id, +(wa.nx+wb.nx).toFixed(6), +(wa.ny+wb.ny).toFixed(6)];
    // дверь на косой стене A, ведёт в B
    A.openings=A.openings.filter(o=>o.id!=='dk'); B.openings=B.openings.filter(o=>!(o.to==='room:'+A.id));
    const d0=A.openings.find(o=>o.type==='door')||{type:'door',swing:'in',hinge:'l'};
    const d={...d0,id:'dk',side:wa.id,off:1.5,w:0.9,to:'room:'+B.id}; A.openings.push(d);
    const m=mapDoor(A,d,B); out.mapDoor=m?[m.side===wb.id,+m.off.toFixed(3)]:null;
    if(m){ const pa=wallPoint(A,d.side,d.off), pa2=wallPoint(A,d.side,d.off+d.w), q1=wallPoint(B,m.side,m.off), q2=wallPoint(B,m.side,m.off+m.w);
      const G=(R,q)=>[R.x+q.x,R.y+q.y]; out.doorGlobal={A:[G(A,pa),G(A,pa2)].map(v=>v.map(x=>+x.toFixed(3))), B:[G(B,q1),G(B,q2)].map(v=>v.map(x=>+x.toFixed(3)))}; }
    out.derived=roomGeom(S,B).openings.filter(o=>o.derived).map(o=>o.side+':'+o.off.toFixed(3));
    out.shared=sharedSpans(A,B).map(s=>s.side+':'+s.lo.toFixed(2)+'-'+s.hi.toFixed(2));
    out.blockedA=[...blockedSides(A)]; out.blockedB=[...blockedSides(B)];
    // связь без двери → ensureDoor
    A.openings=A.openings.filter(o=>o.id!=='dk'); out.ensure=ensureDoor(A.id,B.id); const nd=A.openings.find(o=>o.to==='room:'+B.id); out.ensureDoor=nd?[nd.side,+nd.off.toFixed(2)]:null;
    // прилипание
    const bx=B.x, by=B.y; B.x+=n.x*0.2+0.05*(-n.y); B.y+=n.y*0.2+0.05*n.x; snapRoom(B);
    const x=(B.x+wb.x1)-(A.x+wa.x1), y=(B.y+wb.y1)-(A.y+wa.y1); out.snapGap=+(-(x*wa.nx+y*wa.ny)).toFixed(4); out.snapMoved=[+(B.x-bx).toFixed(3),+(B.y-by).toFixed(3)];
    step=1; render(); return out; });
  console.log(JSON.stringify(r,null,0));
  await p.screenshot({path:'shots/adj.png'});
  console.log('errors',errs); await b.close(); })();
