// Render the same fixed commands with goopUI's original browser SVG filter.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {spawnSync}=require('node:child_process');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(__dirname,'../..'),directory=path.resolve(process.argv[2]);
const context=vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root,'shell/utils/vendor/goopui/core.js'),'utf8').replace(/^\.pragma library\s*/,''),context);
const C=context.GoopCore;
(async()=>{
 const snapshots=JSON.parse(fs.readFileSync(path.join(directory,'parity-frames.json')));
 const browser=await chromium.launch({headless:true});
 try{
  const page=await browser.newPage({viewport:{width:800,height:1000},deviceScaleFactor:1});
  for(const snapshot of snapshots){
   const {body:b,panel:p,circles}=snapshot.frame;
   const rect='<g transform="translate('+b.cx+' '+b.cy+') scale('+b.w/p.width+' '+b.h/p.height+')">'+
    '<rect x="'+(-p.width/2)+'" y="'+(-p.height/2)+'" width="'+p.width+'" height="'+p.height+'" rx="'+snapshot.rounding+'"/></g>';
   const blobs=circles.map(c=>'<ellipse cx="'+c.x+'" cy="'+c.y+'" rx="'+c.r*(c.sx??1)+'" ry="'+c.r*(c.sy??1)+'" opacity="'+(c.opacity??1)+'"/>').join('');
   const svg='<svg xmlns="http://www.w3.org/2000/svg" width="800" height="1000"><defs>'+
    C.gooFilterMarkup(C.qtFilterParams,'original-goop')+'</defs>'+
    '<rect width="800" height="1000" fill="#141a1e"/><rect x="140" y="200" width="240" height="80" fill="#20282d"/>'+
    '<g filter="url(#original-goop)" fill="#b4e57b"><rect width="800" height="1000" fill="transparent"/>'+rect+blobs+'</g></svg>';
   fs.writeFileSync(path.join(directory,'browser-'+snapshot.label+'.svg'),svg);
   await page.setContent('<html><head><style>*{margin:0;padding:0}svg{display:block}</style></head><body>'+svg+'</body></html>');
   await page.screenshot({path:path.join(directory,'browser-'+snapshot.label+'.png')});
  }
 }finally{await browser.close();}
 const report=spawnSync('python3',[path.join(__dirname,'compare_goopui_masks.py'),directory],{encoding:'utf8'});
 process.stdout.write(report.stdout);process.stderr.write(report.stderr);
 if(report.status!==0)process.exitCode=report.status||1;
})().catch(error=>{console.error(error);process.exitCode=1;});
