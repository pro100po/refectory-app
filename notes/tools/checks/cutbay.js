const {chromium}=require('playwright');
(async()=>{
const b=await chromium.launch();
const errs=[];
async function open(f,w=1400,h=1000){const p=await b.newPage({viewport:{width:w,height:h}});p.on('pageerror',e=>errs.push(f+' pageerror '+e.message));p.on('console',m=>{if(m.type()==='error')errs.push(f+' console '+m.text())});await p.goto('file://'+process.cwd()+'/'+f);await p.waitForTimeout(500);return p;}
const expr="JSON.stringify(['rect','L','U','T','trap','quad'].flatMap(t=>[0,1,2,3].map(r=>shapeTemplate(t,r,shapeDefaults(t,6,4)))))";
const pb=await open('base.html'),pn=await open('new.html');
const a=await pb.evaluate(expr),c=await pn.evaluate(expr);
console.log('1 shapeTemplate equal:',a===c,a.length);
const setup=async p=>p.evaluate(()=>{closeProjects();const R=S.rooms[0];S.cur=R.id;setRoomShape(R,{tpl:'rect',p:{W:6,D:4}});step=1;rpOpen=true;render();});
await setup(pn);
const info=()=>({p:JSON.stringify(S.room.shape.p),n:S.room.poly.length,poly:JSON.stringify(S.room.poly),hint:document.querySelector('[data-rpsec="shape"] p.hint')?.textContent,labels:[...document.querySelectorAll('[data-rpsec="shape"] [data-shp-param]')].map(i=>i.dataset.shpParam+':'+(i.closest('label')?.textContent||i.parentElement.textContent).trim().replace(/\s+/g,' '))});
await pn.click('[data-shape-tpl="cut"]');await pn.waitForTimeout(200);
console.log('2a',JSON.stringify(await pn.evaluate(info),null,1));
for(const r of [1,2,3]){console.log('cut rot',r,await pn.evaluate(r=>{const R=S.room;const x=setRoomShape(R,{tpl:'cut',rot:r,p:{W:6,D:4,ca:1.3,cb:1.3}});return JSON.stringify(x)+JSON.stringify(R.poly)},r));}
console.log('cut err',await pn.evaluate(()=>shapeParamsError('cut',{W:6,D:4,ca:5.9,cb:1.3})));
await pn.evaluate(()=>{setRoomShape(S.room,{tpl:'cut',rot:0,p:{W:6,D:4,ca:1.3,cb:1.3}});render();});
await pn.fill('[data-shp-param="ca"]','5900');await pn.dispatchEvent('[data-shp-param="ca"]','change');await pn.waitForTimeout(200);
console.log('ca 5900 warn:',await pn.evaluate(()=>[...document.querySelectorAll('.shp-warn')].map(e=>e.textContent)));
await pn.screenshot({path:'shots/cut-err-1400.png'});
await setup(pn);
await pn.click('[data-shape-tpl="bay"]');await pn.waitForTimeout(200);
console.log('2b',JSON.stringify(await pn.evaluate(info),null,1),'shapeError',await pn.evaluate(()=>JSON.stringify(shapeError(S.room.poly))));
console.log('bf=bw',await pn.evaluate(()=>{const R=S.room;const x=setRoomShape(R,{tpl:'bay',p:{W:6,D:4,bw:3,bd:1,bf:3,bo:1.5}});render();return JSON.stringify(x)+JSON.stringify(R.poly)+'|'+document.querySelector('[data-rpsec="shape"] p.hint')?.textContent}));
console.log('bo0',await pn.evaluate(()=>JSON.stringify(setRoomShape(S.room,{tpl:'bay',p:{W:6,D:4,bw:3,bd:1,bf:1.8,bo:0}}))));
console.log('bf3.5',await pn.evaluate(()=>JSON.stringify(setRoomShape(S.room,{tpl:'bay',p:{W:6,D:4,bw:3,bd:1,bf:3.5,bo:1.5}}))));
for(const r of [1,2,3])console.log('bay rot',r,await pn.evaluate(r=>JSON.stringify(setRoomShape(S.room,{tpl:'bay',rot:r,p:{W:6,D:4,bw:3,bd:1,bf:1.8,bo:1.5}}))+' err='+shapeError(S.room.poly),r));
const auto=async(tpl,rot,p)=>pn.evaluate(([tpl,rot,p])=>{setRoomShape(S.room,{tpl,rot,p});S.layoutManual=false;S.layoutSig=null;step=5;rpOpen=false;recompute();render();const us=curUnitsOf(S.room);return {n:us.filter(u=>S.layout[u.key]).length,tot:us.length,bad:checkUnit(S,us,S.layout).filter(q=>/Выходит|Наложение/.test(q.lbl)).length}},[tpl,rot,p]);
const cp={W:6,D:4,ca:1.3,cb:1.3},bp={W:6,D:4,bw:3,bd:1,bf:1.8,bo:1.5};
console.log('2в cut0',JSON.stringify(await auto('cut',0,cp)),'cut1',JSON.stringify(await auto('cut',1,cp)),'bay0',JSON.stringify(await auto('bay',0,bp)));
await pn.screenshot({path:'shots/bay-plan-step5.png'});
console.log('bay1',JSON.stringify(await auto('bay',1,bp)));
// screenshots form
for(const w of [1400,390]){await pn.setViewportSize({width:w,height:w==390?900:1000});await pn.evaluate(()=>{setRoomShape(S.room,{tpl:'bay',p:{W:6,D:4,bw:3,bd:1,bf:1.8,bo:1.5}});step=1;rpOpen=true;render();});await pn.waitForTimeout(300);
const el=await pn.$('[data-rpsec="shape"]');await el.scrollIntoViewIfNeeded();await el.screenshot({path:`shots/shape-${w}.png`});
console.log('btns',w,await pn.evaluate(()=>[...document.querySelectorAll('[data-shape-tpl]')].map(e=>{const r=e.getBoundingClientRect();return e.textContent.trim()+'@'+Math.round(r.x)+','+Math.round(r.y)+' w'+Math.round(r.width)+' clip='+(e.scrollWidth>e.clientWidth)})));}
console.log('ERRS',JSON.stringify(errs));
await b.close();})();
