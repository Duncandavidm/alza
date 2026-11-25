const { chromium } = require('playwright');
const [mode,out]=process.argv.slice(2);
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:600,height:450},deviceScaleFactor:1.3});
await p.goto('file://'+__dirname+'/cat.html');
const fr=mode==='all'?[...Array(48).keys()]:[0,8,16,30];
require('fs').mkdirSync(out,{recursive:true});
for(const f of fr){await p.evaluate(x=>render(x),f);await p.screenshot({path:`${out}/f${String(f).padStart(3,'0')}.png`,omitBackground:true});}
await b.close();})();
