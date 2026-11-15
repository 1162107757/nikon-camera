const {chromium}=require('./.review-tools/node_modules/playwright');
const fs=require('node:fs'),path=require('node:path');
const out=path.join(__dirname,'review'),base='http://127.0.0.1:4319/';
let browser;
(async()=>{
 browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 const page=await browser.newPage({viewport:{width:375,height:812}}),checks=[],errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 const check=(name,ok)=>checks.push({name,passed:!!ok});
 const frames=[['remote','ready',false],['remote-paused','paused',false],['remote-waiting','waiting',false],['remote-unsupported','unsupported',false],['remote-uncertain','uncertain',false],['remote-offline','ready',true]];
 let captures=0;
 for(const platform of ['android','ios'])for(const theme of ['light','dark'])for(const [name,remoteState,offline] of frames){
  await page.goto(base+'screen.html?'+new URLSearchParams({platform,theme,surface:'sync',panel:'remote',remoteState,disconnected:String(offline)}));
  await page.evaluate(()=>Promise.all([...document.images].map(x=>x.decode().catch(()=>{}))));
  await page.screenshot({path:path.join(out,`${platform}-${theme}-${name}.png`)});captures++;
  if(platform==='android'&&theme==='light'){
   check(name+' focus affordance matches ready capability',await page.locator('[data-action=remote-focus]').isDisabled()===(offline||remoteState!=='ready'));
   if(remoteState==='uncertain')check('Uncertain result blocks shutter initially',await page.locator('[data-action=shutter]').isDisabled());
  }
 }
 await page.goto(base+'screen.html?surface=sync&panel=remote&remoteState=uncertain&theme=dark');
 await page.locator('[data-action=remote-settings]').click();
 await page.locator('[data-action=remote-toggle-view]').click();
 await page.locator('[data-action=remote-toggle-view]').click();
 await page.getByRole('button',{name:'关闭面板',exact:true}).click();
 check('Changing view off and on cannot clear capture uncertainty',await page.locator('[data-action=shutter]').isDisabled()&&(await page.locator('.remote-feedback').textContent()).includes('待核对'));
 await page.screenshot({path:path.join(out,'remote-uncertain-after-view-toggle.png')});
 await page.locator('[data-action=exit-remote]').click();await page.locator('[data-action=open-tools]').click();await page.locator('[data-action=panel-remote]').click();
 check('Leaving and re-entering remote retains capture uncertainty',await page.locator('[data-action=shutter]').isDisabled()&&(await page.evaluate(()=>window.__review.getState())).remoteCaptureUncertain===true);
 await page.screenshot({path:path.join(out,'remote-uncertain-after-reentry.png')});
 await page.locator('[data-action=remote-review]').click();await page.keyboard.press('Escape');
 check('Dismissing verification sheet does not acknowledge result',await page.locator('[data-action=shutter]').isDisabled());
 await page.locator('[data-action=remote-review]').click();await page.locator('[data-action=remote-acknowledge]').click();
 check('Only explicit acknowledgement restores shutter',await page.locator('[data-action=shutter]').isEnabled()&&(await page.evaluate(()=>window.__review.getState())).remoteCaptureUncertain===false);
 await page.locator('[data-action=shutter]').click();await page.waitForTimeout(950);
 check('Single deliberate shutter produces one stable send confirmation',(await page.locator('.remote-feedback').textContent()).includes('已发送拍摄指令')&&await page.locator('[data-action=shutter]').isEnabled());
 const report={scope:'Targeted HTML remote recovery/state pass after independent review; all data synthetic; no camera or native product was tested.',captures,checks,errors};
 fs.writeFileSync(path.join(out,'remote-recovery-check.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify({captures,checks:checks.length,passed:checks.filter(x=>x.passed).length,errors}));
 await browser.close();if(checks.some(x=>!x.passed)||errors.length)process.exitCode=1;
})().catch(async e=>{console.error(e);await browser?.close();process.exitCode=1});
