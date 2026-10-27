import {chromium} from 'file:///C:/Users/11621/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';

const root=fileURLToPath(new URL('./',import.meta.url));
const images=fileURLToPath(new URL('./screenshots/',import.meta.url));
await mkdir(images,{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',args:['--allow-file-access-from-files']});
const page=await browser.newPage({viewport:{width:1300,height:960},deviceScaleFactor:1});
const errors=[],checks=[];
page.on('pageerror',error=>errors.push(error.message));
const check=(label,condition=true)=>{assert.ok(condition,label);checks.push(label);};
const url=(query='')=>pathToFileURL(root+'prototype.html').href+query;
async function ready(query=''){await page.goto(url(query));await page.waitForFunction(()=>window.designReady&&[...document.images].every(image=>image.complete&&image.naturalWidth));}
async function deviceShot(name){await page.locator('#device').screenshot({path:images+name+'.png'});}
try{
 await ready();check('portrait default ready scene',await page.locator('#device').getAttribute('data-scene')==='ready');
 check('four separate live values',await page.locator('.parameters .value').count()===4);
 check('camera identity remains small',await page.locator('.device-name-row').evaluate(e=>parseFloat(getComputedStyle(e).fontSize)<=12));
 await deviceShot('portrait');
 check('current histogram visible by default',await page.locator('.histogram-panel').isVisible());
 check('demonstration bins match sample pixel count',await page.evaluate(()=>Object.values(window.remoteHistogramData.bins).every(values=>values.reduce((a,b)=>a+b,0)===window.remoteHistogramData.pixels)));
 const beforeHistogram=await page.locator('.photo-plane').boundingBox();
 await page.locator('#device').getByRole('button',{name:'显示或收起直方图',exact:true}).click();
 check('histogram can collapse',await page.locator('.histogram-panel').count()===0);
 check('collapsing histogram preserves image bounds',JSON.stringify(beforeHistogram)===JSON.stringify(await page.locator('.photo-plane').boundingBox()));
 await page.locator('#device').getByRole('button',{name:'显示或收起直方图',exact:true}).click();
 await page.locator('.histogram-panel').click();
 check('histogram opens readable detail',await page.getByRole('dialog',{name:'取景直方图',exact:true}).isVisible());
 await page.locator('#device').getByRole('button',{name:'RGB',exact:true}).click();
 check('RGB mode displays three labelled channels',await page.locator('.histogram-legend span').count()===3);
 await deviceShot('histogram-detail');await page.keyboard.press('Escape');await deviceShot('histogram-rgb');
 check('histogram mode switch preserves image bounds',JSON.stringify(beforeHistogram)===JSON.stringify(await page.locator('.photo-plane').boundingBox()));
 const histogramBox=await page.locator('.histogram-panel').boundingBox();
 await page.mouse.move(histogramBox.x+60,histogramBox.y+15);await page.mouse.down();await page.mouse.move(histogramBox.x+175,histogramBox.y-90,{steps:8});await page.mouse.up();
 check('histogram can move without opening detail',await page.locator('.histogram-panel').evaluate((e,x)=>e.getBoundingClientRect().x>x+80,histogramBox.x)&&await page.getByRole('dialog').count()===0);
 check('moving histogram preserves image bounds',JSON.stringify(beforeHistogram)===JSON.stringify(await page.locator('.photo-plane').boundingBox()));
 await deviceShot('histogram-moved');
 await page.locator('.photo-plane').click({position:{x:126,y:96}});
 check('tap moves focus within photo',await page.locator('.focus-rect').evaluate(e=>e.classList.contains('visible')&&parseFloat(e.style.left)>25&&parseFloat(e.style.left)<45));
 await page.waitForFunction(()=>window.remoteCaptureDesign.getState().focus?.locked);check('focus feedback reaches complete');
 await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).click();
 check('in-flight shutter disables repeats',await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).isDisabled());
 check('capture pauses histogram until a new frame',await page.locator('.histogram-panel').evaluate(e=>e.classList.contains('paused')));
 const counted=await page.evaluate(()=>{window.remoteCaptureDesign.act('capture');return window.remoteCaptureDesign.getState().shotCount;});
 check('repeated dispatch is guarded',counted===1);
 await page.waitForFunction(()=>window.remoteCaptureDesign.getState().photo);check('capture confirmation updates recent photo');
 await deviceShot('captured');
 await page.locator('#device').getByRole('button',{name:'查看最近拍摄',exact:true}).click();check('recent photo opens',await page.locator('#device').getByRole('dialog').isVisible());
 await page.locator('#device').getByRole('button',{name:'传入 App',exact:true}).click();check('explicit transfer reports imported',await page.locator('#device').getByRole('heading',{name:'已传入 App',exact:true}).isVisible());
 await page.keyboard.press('Escape');check('system escape closes panel',await page.locator('#device').getByRole('dialog').count()===0);
 await page.evaluate(()=>window.remoteCaptureDesign.setScene('options'));await deviceShot('options');
 check('settings include independent live-view switch',await page.locator('#device').getByRole('switch',{name:'实时取景',exact:true}).count()===1);
 await page.locator('#device').getByRole('switch',{name:'拍后传入 App',exact:true}).click();check('transfer is independent',await page.locator('#device').getByRole('switch',{name:'拍后传入 App',exact:true}).getAttribute('aria-checked')==='true');
 await page.keyboard.press('Escape');
 await page.evaluate(()=>window.remoteCaptureDesign.setScene('ready'));
 await page.locator('#device').getByRole('switch',{name:'拍后传入 App',exact:true}).click();await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).click();
 await page.waitForFunction(()=>window.remoteCaptureDesign.getState().imported);check('optional capture then transfer completes');
 await page.evaluate(()=>window.remoteCaptureDesign.setScene('view-lost'));await deviceShot('view-lost');
 check('live-view interruption keeps advertised shutter available',await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).isEnabled());
 check('live-view interruption disables point focus',await page.locator('#device').getByRole('button',{name:'自动对焦',exact:true}).isDisabled());
 check('interrupted view marks histogram paused',await page.locator('.histogram-state').textContent()==='已暂停');
 await page.locator('#device').getByRole('button',{name:'重新开启取景',exact:true}).click();await page.waitForFunction(()=>window.remoteCaptureDesign.getState().scene==='ready');check('retry view restores ready');
 await page.evaluate(()=>window.remoteCaptureDesign.setScene('offline'));await deviceShot('offline');
 check('disconnection disables shutter',await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).isDisabled());
 check('disconnection cannot label old histogram live',await page.locator('.histogram-caption').textContent().then(text=>text.includes('上次取景')&&text.includes('已暂停')));
 check('disconnected readings show dashes',await page.locator('.parameter .value').allTextContents().then(values=>values.every(value=>value==='—')));
 await page.locator('#device').getByRole('button',{name:'返回同步',exact:true}).click();
 check('back does not invent connection',await page.locator('.sync-camera-name small').textContent().then(text=>text.includes('尚未连接')));
 await page.locator('#device').getByRole('button',{name:/遥控拍摄/}).click();
 check('reopening work area does not reconnect implicitly',await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).isDisabled());
 await page.locator('#device').getByRole('button',{name:'重新连接',exact:true}).click();await page.waitForFunction(()=>window.remoteCaptureDesign.getState().scene==='ready');check('reconnect restores controls');
 await page.evaluate(()=>window.remoteCaptureDesign.setScene('timeout'));await deviceShot('timeout');
 check('unknown capture result blocks repeat',await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).isDisabled());
 await page.locator('#device').getByRole('button',{name:'拍摄结果待确认 · 查看相机照片',exact:true}).click();
 check('timeout recovery explains no repeat',await page.locator('#device').getByRole('dialog').textContent().then(t=>t.includes('不会自动重发快门')));
 await page.locator('#device').getByRole('button',{name:'查看相机照片',exact:true}).click();await page.keyboard.press('Escape');
 check('confirmed result restores capture',await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).isEnabled());
 await page.evaluate(()=>window.remoteCaptureDesign.setScene('ready'));
 await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).click();
 await page.locator('#device').getByRole('button',{name:'拍摄设置',exact:true}).click();
 await page.locator('#device').getByRole('button',{name:'断开相机连接',exact:true}).click();
 check('disconnect during capture preserves unknown result',await page.evaluate(()=>window.remoteCaptureDesign.getState().request==='unknown'));
 await page.locator('#device').getByRole('button',{name:'重新连接',exact:true}).click();await page.waitForFunction(()=>window.remoteCaptureDesign.getState().connection==='connected');
 check('reconnect cannot silently repeat uncertain capture',await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).isDisabled());
 await page.evaluate(()=>window.remoteCaptureDesign.setScene('entry'));await deviceShot('entry');
 await page.locator('#device').getByRole('button',{name:/遥控拍摄/}).click();check('Sync entry opens camera work area',await page.locator('.appbar h2').textContent()==='遥控拍摄');
 await page.locator('#device').getByRole('button',{name:'返回同步',exact:true}).click();check('Back returns to Sync',await page.locator('.sync-heading').textContent()==='同步');
 const geometry=[];
 for(const orientation of ['portrait','landscape'])for(const large of [false,true]){
  await page.evaluate(({orientation,large})=>{window.remoteCaptureDesign.setScene('ready');window.remoteCaptureDesign.setOrientation(orientation);window.remoteCaptureDesign.setLarge(large);},{orientation,large});
  const metrics=await page.locator('#device').evaluate(e=>{const device=e.getBoundingClientRect();const selectors=['.appbar','.view-area','.parameters','.camera-feedback','.release-row','.transfer-row'];return {device:{x:device.x,y:device.y,width:device.width,height:device.height},parts:Object.fromEntries(selectors.map(selector=>{const part=e.querySelector(selector);const r=part.getBoundingClientRect();return [selector,{x:r.x-device.x,y:r.y-device.y,width:r.width,height:r.height,scrollWidth:part.scrollWidth,clientWidth:part.clientWidth}];}))};});
  for(const [selector,r]of Object.entries(metrics.parts)){check(`${orientation}${large?' font1.3':''} ${selector} inside frame`,r.y>=24&&r.y+r.height<=metrics.device.height-12&&r.x>=0&&r.x+r.width<=metrics.device.width+1);}
  geometry.push({orientation,large,...metrics});
  const parameterLabelSize=await page.locator('.parameter .label').first().evaluate(e=>parseFloat(getComputedStyle(e).fontSize));
  check(`${orientation}${large?' font1.3':''} parameter labels honor requested scale`,Math.abs(parameterLabelSize-11*(large?1.3:1))<.02);
  if(orientation==='landscape'){
   const typeSizes=await page.locator('#device').evaluate(e=>({title:parseFloat(getComputedStyle(e.querySelector('.appbar h2')).fontSize),identity:parseFloat(getComputedStyle(e.querySelector('.device-identity')).fontSize),battery:parseFloat(getComputedStyle(e.querySelector('.battery-status')).fontSize)}));
   check(`landscape${large?' font1.3':''} identity battery and title honor scale`,Math.abs(typeSizes.title-15*(large?1.3:1))<.02&&Math.abs(typeSizes.identity-10*(large?1.3:1))<.02&&Math.abs(typeSizes.battery-10*(large?1.3:1))<.02);
  }
  check(`${orientation}${large?' font1.3':''} image aspect retained`,await page.locator('.photo-plane').evaluate(e=>Math.abs(e.clientWidth/e.clientHeight-4/3)<.01));
  check(`${orientation}${large?' font1.3':''} app targets reach 48px`,await page.locator('#workspace button:not(:disabled)').evaluateAll(items=>items.every(e=>{const r=e.getBoundingClientRect();return r.width>=48&&r.height>=48;})));
  await deviceShot(orientation+(large?'-large-font':''));
 }
 await page.evaluate(()=>window.remoteCaptureDesign.act('options'));
 await deviceShot('landscape-settings-large-font');
 await page.locator('#device').getByRole('button',{name:'断开相机连接',exact:true}).scrollIntoViewIfNeeded();
 check('landscape large-font settings scroll to disconnect',await page.locator('#device').getByRole('button',{name:'断开相机连接',exact:true}).isVisible());
 await page.locator('#device').getByRole('button',{name:'断开相机连接',exact:true}).click();
 check('landscape large-font setting is actionable',await page.locator('#device').getByRole('button',{name:'拍照',exact:true}).isDisabled());
 await page.setViewportSize({width:360,height:1000});await ready();
 check('phone browser review has no document horizontal overflow',await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.screenshot({path:images+'review-mobile.png',fullPage:true});
 for(const kind of ['main','states','landscape','histogram']){
  await page.setViewportSize({width:kind==='landscape'?1100:1320,height:kind==='landscape'?720:1100});
  await page.goto(pathToFileURL(root+'board.html').href+'?kind='+kind);await page.waitForFunction(()=>window.boardReady);
  for(const frame of page.frames().slice(1))await frame.waitForFunction(()=>window.designReady&&[...document.images].every(image=>image.complete&&image.naturalWidth));
  await page.screenshot({path:images+'board-'+kind+'.png',fullPage:true});
 }
 check('no browser script errors',errors.length===0);
 await writeFile(root+'REVIEW-CHECKS.json',JSON.stringify({scope:'Browser-rendered interactive design mockup, not native Android or real camera validation',status:'PASS',checks:checks.length,assertions:checks,errors,geometry},null,2));
 console.log('PASS: '+checks.length+' prototype checks');
}catch(error){await page.screenshot({path:images+'failure.png',fullPage:true}).catch(()=>{});await writeFile(root+'REVIEW-CHECKS.json',JSON.stringify({status:'FAIL',scope:'HTML design prototype only',failure:error.message,checks:checks.length,assertions:checks,errors},null,2));throw error;}
finally{await browser.close();}
