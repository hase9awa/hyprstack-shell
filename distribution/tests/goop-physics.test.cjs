const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const crypto=require('node:crypto'),assert=require('node:assert/strict'),{test}=require('node:test');
const root=path.resolve(__dirname,'../..'),context=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root,'shell/utils/vendor/goopui/core.js'),'utf8')
    .replace(/^\.pragma library\s*/,''),context);
const C=context.GoopCore,plain=v=>JSON.parse(JSON.stringify(v));
const random=seed=>()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};

test('production runtime matches its pinned provenance and retains the MIT notice',()=>{
 const vendor=path.join(root,'shell/utils/vendor/goopui'),meta=JSON.parse(fs.readFileSync(path.join(vendor,'UPSTREAM.json')));
 assert.equal(meta.commit,'4859a8b5e8272b479ac2c22899234065ff626fe4');
 assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(vendor,'core.js'))).digest('hex'),meta.bundleSha256);
 assert.match(fs.readFileSync(path.join(vendor,'LICENSE'),'utf8'),/MIT License/);
 assert.match(fs.readFileSync(path.join(root,'shell/utils/vendor/goopui/core.js'),'utf8'),/Copyright \(c\) 2026 Timothy McMasters/);
});

test('Qt panel frames equal the original Emerge and EmergeMomentum circle commands',()=>{
 for(const side of ['top','right','bottom','left'])for(const [width,height]of [[200,52],[854,420]]){
  const panel={x:120,y:180,width,height},span=Math.min(['top','bottom'].includes(side)?width:height,96),th=28;
  const anchor=side==='bottom'?{x:panel.x+(width-span)/2,y:panel.y-th,width:span,height:th}:
    side==='top'?{x:panel.x+(width-span)/2,y:panel.y+height,width:span,height:th}:
    side==='right'?{x:panel.x-th,y:panel.y+(height-span)/2,width:th,height:span}:
    {x:panel.x+width,y:panel.y+(height-span)/2,width:th,height:span};
  const b=C.emergeBridge(anchor,panel,side,C.EMERGE_FEEL.playful);
  const shift=Math.max(0,.6*C.qtFlowDuration-.12),seed=13;
  for(let f=0;f<=120;f++){
   const t=f/120,seconds=t*C.qtFlowDuration,sec=seconds-shift;
   let expected=C.emergePose(t,b,'open',C.EMERGE_FEEL.playful,C.qtFlowEffects,seed);
   if(sec>=0&&sec<C.emergeMomentumEnd('open'))expected=C.emergeMomentum(expected,b,'open',sec,{},{
    preset:'playful',seed,bodyAt:s=>C.emergePose((s+shift)/C.qtFlowDuration,b,'open',C.EMERGE_FEEL.playful,C.qtFlowEffects,seed).body});
   const actual=C.qtPanelFrame(panel,side,t,seconds,seed,false,-1,[]);
   assert.deepEqual(plain(actual.body),plain({cx:panel.x+expected.body.cx,cy:panel.y+expected.body.cy,w:expected.body.w,h:expected.body.h}));
   assert.deepEqual(plain(actual.circles),plain(expected.circles.filter(c=>c.r>0).map(c=>({x:panel.x+c.x,y:panel.y+c.y,r:c.r,opacity:1,sx:1,sy:1}))));
   assert.equal(actual.content,expected.content);
   assert.ok(actual.circles.length<=128,'Qt renderer discarded upstream circles');
  }
 }
});

test('hover rendering matches an independent original DripField including necks and recoil',()=>{
 const rand=random(42),referenceRandom=random(42),model=C.createQtDrips(rand),blobs=new Set();
 const renderer={layer:null,setParams(){},setPadding(){},setBodyScale(){},flush(){},destroy(){},
  createBlob(){const c={x:0,y:0,r:0,opacity:1,sx:1,sy:1};blobs.add(c);return{
   set(x,y,r,opacity=1,sx=1,sy=1){Object.assign(c,{x,y,r,opacity,sx,sy})},remove(){blobs.delete(c)}}}};
 const reference=new C.DripField(renderer);
 let held=false,spawned=0;
 for(let frame=0;frame<900;frame++){
  const hover=frame<360,body={cx:200+(frame>120?60:0),cy:200,w:320,h:120},dt=1/120;
  if(hover!==held){reference.setFed(hover);held=hover;}
  model.step(dt,hover,body);
  if(model.spawned>spawned){
   referenceRandom(); // Qt supplies a random edge coordinate, then calls public spawn.
   reference.spawn(model.tuning,{x:model.field.drips[model.field.drips.length-1].x0,random:referenceRandom});
   spawned=model.spawned;
  }
  reference.step(dt,{tuning:model.tuning,width:body.w,height:body.h,sx:1,sy:1,pressed:false,
   anchor:x=>({x:body.cx-body.w/2+x,y:body.cy+body.h/2})});
  assert.deepEqual(plain(model.circles()),plain([...blobs].filter(c=>c.r>0&&c.opacity>0)),String(frame));
 }
 assert.ok(model.spawned>=3);
 assert.equal(model.active,false,'hover leave did not let upstream simulation settle');
 assert.equal(blobs.size,0);
});

test('attached drawers keep their near edge inside the desktop frame throughout the flow',()=>{
 const frame={x:16,y:52,width:1248,height:980},overlap=15;
 for(const side of ['top','right','bottom','left'])for(const gap of [0,48]){
  const panel=side==='bottom'?{x:400,y:frame.y+gap,width:420,height:310}:
   side==='top'?{x:400,y:frame.y+frame.height-310-gap,width:420,height:310}:
   side==='right'?{x:frame.x+gap,y:300,width:420,height:310}:
   {x:frame.x+frame.width-420-gap,y:300,width:420,height:310};
  const attachment={innerRect:frame,overlap,keepJoined:true};
  for(let f=0;f<=240;f++){
   const progress=Math.min(1,f/120),sec=f/240*C.qtAnimationEnd;
   const original=C.qtPanelFrame(panel,side,progress,sec,13,false,-1,[]);
   const attached=C.qtPanelFrame(panel,side,progress,sec,13,false,-1,[],attachment),b=attached.body;
   assert.ok(Object.values(b).every(Number.isFinite));
   assert.ok(b.w>=0&&b.h>=0);
   assert.deepEqual(plain(attached.dripBody),plain(original.body),'approved hover-drip anchor changed');
   assert.ok(attached.content<=original.content,'content appeared before the liquid host');
   assert.ok(attached.circles.length<=128,'renderer capacity exceeded');
   assert.ok(attached.bodyShape.rx>=0 && attached.bodyShape.rx<=b.w/2+.000001);
   assert.ok(attached.bodyShape.ry>=0 && attached.bodyShape.ry<=b.h/2+.000001);
   if(progress>0&&b.w>0&&b.h>0){
    if(side==='bottom')assert.ok(b.cy-b.h/2<=frame.y+.000001);
    if(side==='top')assert.ok(b.cy+b.h/2>=frame.y+frame.height-.000001);
    if(side==='right')assert.ok(b.cx-b.w/2<=frame.x+.000001);
    if(side==='left')assert.ok(b.cx+b.w/2>=frame.x+frame.width-.000001);
   }
   // Only the host and its attached rim change. All freely emitted spray
   // commands are still the original EmergeMomentum output, at the same time.
   const span=Math.min(['top','bottom'].includes(side)?panel.width:panel.height,96);
   const anchor=side==='bottom'?{x:panel.x+(panel.width-span)/2,y:panel.y-28,width:span,height:28}:
    side==='top'?{x:panel.x+(panel.width-span)/2,y:panel.y+panel.height,width:span,height:28}:
    side==='right'?{x:panel.x-28,y:panel.y+(panel.height-span)/2,width:28,height:span}:
    {x:panel.x+panel.width,y:panel.y+(panel.height-span)/2,width:28,height:span};
   const bridge=C.emergeBridge(anchor,panel,side,C.qtFlowFeel);
   const roots=C.emergePose(progress,bridge,'open',C.qtFlowFeel,C.qtFlowEffects,13).circles.filter(c=>c.r>0).length;
   const spray=plain(original.circles).slice(roots);
   if(spray.length)assert.deepEqual(plain(attached.circles).slice(-spray.length),spray,'approved free splashes changed');
  }
 }
});

test('frame flow advances in depth and width together, then settles from a rounded mass',()=>{
 for(const side of ['top','right','bottom','left'])for(const [width,height]of [[854,420],[200,140],[58,410]]){
  const f={x:16,y:52,width:1248,height:980},panel={x:120,y:180,width,height};
  if(side==='bottom')panel.y=f.y;
  else if(side==='top')panel.y=f.y+f.height-height;
  else if(side==='right')panel.x=f.x;
  else panel.x=f.x+f.width-width;
  const attachment={innerRect:f,overlap:15,keepJoined:true,radius:26};
  let previous=0;
  for(let i=0;i<=1000;i++){
   const t=i/1000,frame=C.qtPanelFrame(panel,side,t,t*C.qtFlowDuration,13,false,-1,[],attachment),b=frame.body;
   const vertical=['top','bottom'].includes(side),breadth=vertical?width:height,depth=vertical?height:width;
   const wide=(vertical?b.w:b.h)/breadth;
   const reach=side==='bottom'?b.cy+b.h/2-f.y:side==='top'?f.y+f.height-b.cy+b.h/2:
     side==='right'?b.cx+b.w/2-f.x:f.x+f.width-b.cx+b.w/2;
   if(wide>.05&&wide<.75)assert.ok(reach/depth<.94,'body already full depth while still expanding sideways');
   assert.ok(Math.abs(reach-previous)<Math.max(width,height)*.02,'leading edge jumped');
   previous=reach;
   if(i===0)assert.equal(b.w*b.h,0,'initial mass popped in');
   if(i===120){assert.ok(frame.bodyShape.rx>b.w*.35);assert.ok(frame.bodyShape.ry>b.h*.35);}
   if(i===1000){assert.ok(Math.abs(frame.bodyShape.rx-Math.min(26,b.w/2))<1e-6);assert.equal(frame.content,1);}
  }
 }
});

test('the initial mass is born inside the actual frame on all four sides',()=>{
 const f={x:16,y:52,width:1248,height:980};
 for(const side of ['top','right','bottom','left'])for(const inset of [0,3,5])for(const gap of [0,48]){
  const panel={x:400,y:300,width:420,height:310},vertical=['top','bottom'].includes(side);
  if(side==='bottom')panel.y=f.y+gap;
  else if(side==='top')panel.y=f.y+f.height-panel.height-gap;
  else if(side==='right')panel.x=f.x+gap;
  else panel.x=f.x+f.width-panel.width-gap;
  const sign=side==='bottom'||side==='right'?1:-1;
  const plane=side==='bottom'?f.y:side==='top'?f.y+f.height:side==='right'?f.x:f.x+f.width;
  for(const t of [.005,.02,.04,.06]){
   const frame=C.qtPanelFrame(panel,side,t,t*C.qtFlowDuration,13,false,-1,[],
    {innerRect:f,overlap:15,keepJoined:true,radius:26,originInset:inset});
   assert.ok(frame.body.w>0&&frame.body.h>0);
   const center=vertical?frame.body.cy:frame.body.cx;
   if(t>=.01)assert.ok(Math.abs(center-(plane-sign*inset))<1e-6,'first blob appeared outside the frame');
   else assert.ok(sign*(center-plane)<=1e-6,'first pixels appeared outside the frame');
  }
 }
});

test('floating shell dialogs retain the upstream spray and settle without frame attachment',()=>{
 const panel={x:140,y:225,width:1000,height:600};
 for(const [width,height]of [[1000,600],[480,280],[440,660]]) {
  Object.assign(panel,{width,height});
  for(let i=0;i<=240;i++){
   const progress=Math.min(1,i/120),sec=i/240*C.qtAnimationEnd;
   const original=C.qtPanelFrame(panel,'bottom',progress,sec,7,false,-1,[]);
   const floating=C.qtPanelFrame(panel,'bottom',progress,sec,7,false,-1,[],
    {innerRect:panel,overlap:0,keepJoined:false,floating:true,radius:26});
   assert.ok(Object.values(floating.body).every(Number.isFinite));
   assert.ok(floating.body.w>=0&&floating.body.h>=0);
   assert.deepEqual(plain(floating.dripBody),plain(original.dripBody),'hover drips changed');
   if(i===0)assert.equal(floating.body.w*floating.body.h,0);
   if(i===240){
    assert.deepEqual(plain(floating.body),{cx:panel.x+width/2,cy:panel.y+height/2,w:width,h:height});
    assert.equal(floating.bodyShape.rx,26);
    assert.equal(floating.bodyShape.ry,26);
   }
  }
 }
});

test('menu morph splashes equal upstream momentum at rest and keep released drops in world space',()=>{
 const panel={x:600,y:60,width:352,height:285};
 for(const side of ['top','bottom','left','right'])for(let i=0;i<=120;i++) {
  const sec=i/120*C.emergeMomentumEnd('open');
  const expected=C.qtPanelFrame(panel,side,1,sec,19,true,-1,[]).circles;
  const actual=C.qtMorphCircles(side,sec,19,[{time:0,rect:panel},{time:sec,rect:panel}]);
  assert.deepEqual(plain(actual),plain(expected),'morph used a different splash algorithm');
 }
 const samples=[{time:0,rect:panel},{time:.3,rect:panel},{time:.6,rect:panel}];
 const moved=[samples[0],samples[1],{time:.31,rect:panel},
  {time:.6,rect:{x:1000,y:60,width:352,height:80}}];
 const original=plain(C.qtMorphCircles('bottom',.6,23,samples));
 const detached=original.filter(c=>c.y>panel.y+panel.height+25);
 assert.ok(detached.length>1,'no detached drops to check');
 const shifted=plain(C.qtMorphCircles('bottom',.6,23,moved));
 for(const c of detached)assert.ok(shifted.some(d=>Math.abs(d.x-c.x)<1e-5 && Math.abs(d.y-c.y)<1e-5
  && Math.abs(d.r-c.r)<1e-5),'detached spray followed the resized menu');
});

test('upstream Gaussian kernel remains normalized at desktop scale factors',()=>{
 for(const dpr of [1,1.25,1.5,2,3]){
  const sigma=C.qtFilterParams.blur*dpr/C.fieldScale(C.qtFilterParams.blur*dpr),k=C.gaussianTaps(sigma);
  let energy=k.w0;
  for(let i=0;i<k.count;i++){assert.ok(k.taps[i*2]>0);energy+=2*k.taps[i*2+1];}
  assert.ok(Math.abs(energy-1)<.000001);
  assert.ok(k.count<=32);
 }
});
