const {chromium}=require('./.review-tools/node_modules/playwright');
const fs=require('node:fs'),path=require('node:path');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:375,height:812}}),checks=[];
  const check=(name,passed)=>checks.push({name,passed});
  await page.goto('http://127.0.0.1:4319/screen.html?surface=sync&theme=light');
  await page.evaluate(()=>Promise.all([...document.images].map(x=>x.decode())));
  check('375px toolbar has no horizontal overflow',await page.evaluate(()=>document.documentElement.scrollWidth===375));
  check('RAW, sorting and select actions are on the same line',await page.locator('.photo-actions button').evaluateAll(xs=>Math.max(...xs.map(x=>x.getBoundingClientRect().top))-Math.min(...xs.map(x=>x.getBoundingClientRect().top))<2));
  await page.screenshot({path:path.join(__dirname,'review/sync-toolbar-sort-375.png')});
  await page.locator('[data-action=photo-sort]').click();
  check('Four requested time/name sort choices exist',await page.locator('.sort-row').count()===4);
  await page.screenshot({path:path.join(__dirname,'review/sync-toolbar-sort-menu.png')});
  await page.locator('[data-action=sort-nameAscending]').click();
  check('Ascending file-name option reorders the example grid',(await page.locator('.photo-caption').first().textContent())==='DSC_4816.JPG');
  await page.locator('[data-action=photo-sort]').click();await page.locator('[data-action=sort-newest]').click();
  check('Newest example order can be restored',(await page.locator('.photo-caption').first().textContent())==='DSC_4821.JPG');
  const result={scope:'Standalone HTML sorting preview only; not native product UI validation',checks};
  fs.writeFileSync(path.join(__dirname,'review/sort-preview-check.json'),JSON.stringify(result,null,2));
  console.log(JSON.stringify({checks:checks.length,passed:checks.filter(x=>x.passed).length}));
  if(checks.some(x=>!x.passed))process.exitCode=1;
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
