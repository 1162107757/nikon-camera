// Browser-only verification of a synthetic HTML prototype. No product runtime.
const { chromium } = require('./.review-tools/node_modules/playwright');
const fs = require('node:fs');
const path = require('node:path');
const out=path.join(__dirname,'review');
const base='http://127.0.0.1:4319/';
const cases=[
 ['wifi-ready',{surface:'connection',transport:'wifi',state:'idle'}],
 ['usb-ready',{surface:'connection',transport:'usb',state:'idle'}],
 ['usb-found',{surface:'connection',transport:'usb',state:'usbfound'}],
 ['usb-missing',{surface:'connection',transport:'usb',state:'usbempty'}],
 ['connecting',{surface:'connection',state:'connecting'}],
 ['camera-confirm',{surface:'connection',state:'confirm'}],
 ['permission',{surface:'connection',state:'permission'}],
 ['permission-denied',{surface:'connection',state:'denied'}],
 ['timeout',{surface:'connection',state:'timeout'}],
 ['failed',{surface:'connection',state:'failed'}],
 ['success-return',{surface:'connection',state:'success'}],
 ['sync-entry',{surface:'sync',panel:'closed'}],
 ['sync-tools',{surface:'sync',panel:'tools'}],
 ['queue-empty',{surface:'sync',panel:'downloads',queue:'empty'}],
 ['queue-active',{surface:'sync',panel:'downloads',queue:'active'}],
 ['queue-failed',{surface:'sync',panel:'downloads',queue:'failed'}],
 ['remote',{surface:'sync',panel:'remote'}],
 ['remote-paused',{surface:'sync',panel:'remote',remoteState:'paused'}],
 ['remote-waiting',{surface:'sync',panel:'remote',remoteState:'waiting'}],
 ['remote-unsupported',{surface:'sync',panel:'remote',remoteState:'unsupported'}],
 ['remote-uncertain',{surface:'sync',panel:'remote',remoteState:'uncertain'}],
 ['slots',{surface:'sync',panel:'presets'}],
 ['remote-offline',{surface:'sync',panel:'remote',disconnected:'true'}],
];
let activeBrowser;
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 activeBrowser=browser;
 const page=await browser.newPage({viewport:{width:375,height:812},deviceScaleFactor:1});
 const issues=[];let captures=0;
 page.on('pageerror',e=>issues.push('JS: '+e.message));
 page.on('response',r=>{if(r.status()>=400)issues.push('HTTP '+r.status()+': '+r.url())});
 for(const platform of ['android','ios'])for(const theme of ['light','dark'])for(const [name,options] of cases){
  await page.goto(base+'screen.html?'+new URLSearchParams({platform,theme,...options}));
  await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode().catch(()=>{}))));
  const dims=await page.evaluate(()=>({width:innerWidth,appWidth:document.querySelector('.screen').getBoundingClientRect().width,overflow:document.documentElement.scrollWidth>innerWidth,broken:[...document.images].filter(x=>!x.complete||!x.naturalWidth).length,panel:document.querySelector('.sheet,.tools-panel')?.getBoundingClientRect().toJSON()}));
  if(dims.overflow||dims.broken||dims.width!==375||dims.appWidth!==375)issues.push(`${platform}-${theme}-${name}: ${JSON.stringify(dims)}`);
  if(dims.panel&&(dims.panel.x<0||dims.panel.right>375||dims.panel.top<44))issues.push('Panel overflow: '+name);
  await page.screenshot({path:path.join(out,`${platform}-${theme}-${name}.png`)});captures++;
 }
 const checks=[];
 const check=(name,ok)=>{checks.push({name,passed:!!ok});if(!ok)issues.push('Interaction: '+name)};
 await page.goto(base+'screen.html?surface=connection&platform=ios&theme=light');
 check('iOS Wi-Fi action names guidance without promising a deep link',await page.locator('[data-action=wifi-settings]').textContent()==='查看 Wi-Fi 连接指引');
 check('iOS idle advanced settings fits within visible content',await page.locator('[data-action=settings]').evaluate(x=>x.getBoundingClientRect().bottom<=x.closest('main').getBoundingClientRect().bottom));
 await page.locator('[data-action=wifi-settings]').click();
 check('iOS Wi-Fi guide describes manual Settings > Wi-Fi and return',await page.locator('.sheet-explanation').textContent()==='打开 iPhone 的“设置” → “Wi-Fi”，选择相机网络并完成连接，然后返回 Huevia，点击“开始连接”。');
 await page.screenshot({path:path.join(out,'ios-light-wifi-guide.png')});
 await page.goto(base+'screen.html?surface=connection&platform=ios&theme=dark');await page.locator('[data-action=wifi-settings]').click();
 await page.screenshot({path:path.join(out,'ios-dark-wifi-guide.png')});
 await page.goto(base+'screen.html?surface=connection&platform=ios&source=sync');
 await page.locator('[data-action=connect]').click();
 await page.waitForTimeout(4100);
 let state=await page.evaluate(()=>window.__review.getState());
 check('Connection success returns to caller without loading photo list',state.page==='sync'&&!state.loaded&&!state.disconnected);
 check('No photo grid exists after successful connection',await page.locator('.photo-grid').count()===0);
 await page.locator('[data-action=browse]').click();
 check('Photos appear only after explicit browse',await page.locator('.photo-grid').count()===1);
 await page.locator('[data-action=open-tools]').click();
 check('Single button expands three tool entries',await page.locator('.tool-row').count()===3);
 await page.locator('[data-action=panel-downloads]').click();
 const emptyHeight=await page.locator('.sheet').evaluate(x=>x.getBoundingClientRect().height);
 check('Empty download queue is compact (<=185px)',emptyHeight<=185);
 await page.locator('[data-action=nav-presets]').click();
 check('Camera tools disappear outside Sync',await page.locator('.dock-button,.tools-panel,.sheet').count()===0);
 await page.locator('[data-action=go-connect]').click();
 await page.locator('[data-action=connect]').click();await page.waitForTimeout(4100);
 state=await page.evaluate(()=>window.__review.getState());check('Preset caller receives successful connection back',state.page==='presets'&&!state.loaded);
 await page.goto(base+'screen.html?surface=connection&platform=android');
 await page.locator('[data-action=connect]').click();await page.locator('[data-action=cancel-connect]').click();await page.waitForTimeout(4100);
 state=await page.evaluate(()=>window.__review.getState());check('Cancelled connection cannot return late as success',state.page==='connection'&&state.state==='idle');
 await page.goto(base+'screen.html?surface=sync&panel=remote');
 const staticAnimations=await page.locator('.shutter,.remote-ready').evaluateAll(els=>els.flatMap(x=>x.getAnimations({subtree:true})).length);
 check('Ready shutter and camera status have no looping animations',staticAnimations===0);
 await page.locator('[data-action=shutter]').click();check('Shutter briefly disables after one press',await page.locator('[data-action=shutter]').isDisabled());
 await page.waitForTimeout(1000);check('Shutter returns to enabled state with one confirmation',await page.locator('[data-action=shutter]').isEnabled()&&(await page.locator('.remote-feedback').textContent()).includes('已发送拍摄指令（演示）'));
 check('Remote route has a full live-view stage and hides Sync navigation',await page.locator('.live-stage img').count()===1&&await page.locator('.bottom-tabs,.dock-button').count()===0);
 await page.locator('[data-action=remote-grid]').click();check('Composition grid can be hidden',await page.locator('.thirds-grid').count()===0);
 await page.locator('[data-action=remote-grid]').click();await page.locator('[data-action=remote-histogram]').click();
 check('Histogram is computed from the local demonstration image',await page.locator('.live-histogram canvas').evaluate(x=>[...x.getContext('2d').getImageData(0,0,x.width,x.height).data].some(v=>v!==0)));
 await page.locator('[data-action=focus-point]').click({position:{x:220,y:120}});check('Point focus displays a reticle only after a tap',await page.locator('.focus-reticle').count()===1);
 await page.screenshot({path:path.join(out,'android-light-remote-histogram.png')});
 await page.locator('[data-action=remote-pause]').click();check('Paused view explicitly labels its retained demo frame',(await page.locator('.live-pause').textContent()).includes('取景已暂停'));
 await page.locator('[data-action=remote-resume]').click();check('Paused view can resume',await page.locator('.live-pause').count()===0);
 await page.locator('[data-action=remote-parameters]').click();check('Camera parameters are read-only',await page.locator('.remote-detail-list div').count()===8&&await page.locator('.sheet input').count()===0);
 await page.screenshot({path:path.join(out,'android-light-remote-parameters.png')});
 await page.getByRole('button',{name:'关闭面板',exact:true}).click();await page.locator('[data-action=remote-settings]').click();
 await page.locator('[data-action=remote-toggle-transfer]').click();check('Capture import setting is an explicit local toggle',await page.locator('[data-action=remote-toggle-transfer]').getAttribute('aria-pressed')==='true');
 await page.screenshot({path:path.join(out,'android-light-remote-settings.png')});
 await page.getByRole('button',{name:'关闭面板',exact:true}).click();await page.locator('[data-action=exit-remote]').click();
 state=await page.evaluate(()=>window.__review.getState());check('Closing remote returns to Sync and retains connection',state.page==='sync'&&!state.disconnected&&state.panel==='closed');
 await page.goto(base+'screen.html?surface=sync&panel=remote&remoteState=uncertain');check('Uncertain capture result prevents duplicate shutter',await page.locator('[data-action=shutter]').isDisabled());
 await page.locator('[data-action=remote-review]').click();check('Uncertain result requires explicit camera verification',(await page.locator('.sheet-explanation').textContent()).includes('不会自动重发快门'));
 await page.goto(base+'screen.html?surface=sync&panel=presets');check('All nine slots are visible',await page.locator('.slot').count()===9);
 check('Back-to-tools touch target is at least 44px square',await page.locator('.back-tool').evaluate(x=>x.getBoundingClientRect().width>=44&&x.getBoundingClientRect().height>=44));
 await page.locator('[data-action=slot-C9]').click();check('C9 selection updates target',await page.locator('.slot-selection strong').textContent()==='已选择 C9');
 await page.keyboard.press('Escape');check('Escape closes tool content',await page.locator('.sheet').count()===0);
 await page.goto(base+'screen.html?surface=sync&panel=remote&disconnected=true');check('Disconnected shutter is disabled',await page.locator('[data-action=shutter]').isDisabled());
 await page.emulateMedia({reducedMotion:'reduce'});await page.goto(base+'screen.html?surface=connection&state=confirm&theme=dark');
 check('Reduced motion has no active animation',await page.locator('.screen').evaluate(x=>x.getAnimations({subtree:true}).length)===0);
 await page.setViewportSize({width:320,height:740});await page.goto(base+'screen.html?surface=sync&panel=presets&theme=dark');
 check('320px fallback has no horizontal overflow',await page.evaluate(()=>document.documentElement.scrollWidth===innerWidth));
 await page.screenshot({path:path.join(out,'narrow-320.png')});
 await page.setViewportSize({width:1320,height:1280});await page.goto(base);await page.waitForTimeout(300);
 await page.screenshot({path:path.join(out,'review-board-connection.png'),fullPage:true});
 await page.goto(base+'?surface=sync&panel=tools');await page.waitForTimeout(300);
 await page.screenshot({path:path.join(out,'review-board-tools.png'),fullPage:true});
 await page.setViewportSize({width:1233,height:990});await page.goto(base+'review-cover.html');
 await page.screenshot({path:path.join(out,'review-cover.png'),fullPage:true});
 const report={scope:'Standalone HTML mockup only. All data synthetic. No camera or product runtime was tested.',viewport:{width:375,height:812},captures,checks,issues:[...new Set(issues)],emptyQueueHeight:emptyHeight};
 fs.writeFileSync(path.join(out,'browser-check.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify({captures,checks:checks.length,passed:checks.filter(x=>x.passed).length,emptyQueueHeight:emptyHeight,issues:report.issues}));
 await browser.close();if(issues.length)process.exitCode=1;
})().catch(async e=>{console.error(e);await activeBrowser?.close();process.exitCode=1});
