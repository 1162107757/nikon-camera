const icon=(name,extra='')=>`<svg class="icon ${extra}" aria-hidden="true"><use href="#i-${name}"/></svg>`;
const photos=[['山间湖泊',0,0],['雨后的街道',50,0],['山野',100,0],['海岸',0,100],['林间',50,100],['雪山木屋',100,100],['湖畔',0,0],['夜街',50,0]];
const demos=[];
function tell(text){document.querySelector('#review-status').textContent='演示：'+text;}
function build(slot){
  const type=slot.dataset.demo,app=type==='app-selected';
  const model={slot,source:app?'app':'phone',selecting:type!=='browse',selected:new Set(type==='browse'?[]:[0,1,3]),access:'full'};
  slot.innerHTML=`<section class="phone" aria-label="${app?'App 内':'手机'}相册设计预览"><div class="statusbar"><time>9:41</time><span class="status-icons"><span class="network">5G</span>${icon('signal')}<span class="battery"></span></span></div><header class="page-head"><h2>相册</h2><button class="icon-button more-toggle" aria-label="相册更多操作" aria-expanded="false">${icon('more')}</button></header><div class="source-switch" role="group" aria-label="照片来源"><button data-source="app">App 内</button><button data-source="phone">手机</button></div><div class="count-row"><p>共 128 张</p><button class="small-action enter-select">选择</button></div><div class="gallery"><div class="gallery-content"><h3 class="date-label">今天</h3><div class="gallery-grid">${photos.slice(0,4).map((p,i)=>photo(p,i)).join('')}</div><h3 class="date-label">昨天</h3><div class="gallery-grid">${photos.slice(4).map((p,i)=>photo(p,i+4)).join('')}</div></div><div class="empty-access">${icon('photo')}<h3>浏览手机照片</h3><p>允许访问后，即可在这里浏览照片。</p><button class="access-primary">允许访问照片</button><button class="access-alternative">选择指定照片</button></div></div><nav class="floating-nav" aria-label="底部导航">${[['photo','预设'],['camera','同步'],['album','相册'],['settings','设置']].map(([i,t])=>`<button class="${t==='相册'?'active':''}" ${t==='相册'?'aria-current="page"':''}>${icon(i)}<span>${t}</span></button>`).join('')}</nav><div class="action-dock" role="group" aria-label="所选照片操作"><button class="dock-cancel" aria-label="取消选择">${icon('close')}<span>取消</span></button><span class="selection-total" role="status" aria-live="polite"></span><button class="dock-save" aria-label="将所选照片保存到手机">${icon('download')}<span>保存</span></button><button class="dock-primary"></button></div><div class="home-indicator" aria-hidden="true"></div><div class="more-menu"><button data-action="refresh">刷新</button><button data-action="raw">RAW 显影</button><button data-action="permission">照片访问范围</button></div></section>`;
  const phone=slot.querySelector('.phone');model.phone=phone;
  phone.querySelector('.enter-select').onclick=()=>{model.selecting=true;model.selected.clear();render(model);};
  phone.querySelector('.dock-cancel').onclick=()=>{model.selecting=false;model.selected.clear();render(model);tell('已退出选择，底部导航恢复。');};
  phone.querySelectorAll('.photo').forEach(tile=>tile.onclick=()=>{const id=Number(tile.dataset.id);if(!model.selecting){tell('浏览状态点击照片进入现有编辑流程。');return;}model.selected.has(id)?model.selected.delete(id):model.selected.add(id);render(model);});
  phone.querySelectorAll('[data-source]').forEach(b=>b.onclick=()=>{model.source=b.dataset.source;model.selected.clear();render(model);});
  phone.querySelector('.dock-primary').onclick=()=>tell(`将 ${model.selected.size} 张照片带入现有批量编辑流程。`);
  phone.querySelector('.dock-save').onclick=()=>tell(`将 ${model.selected.size} 张照片带入现有保存到手机流程。`);
  phone.querySelector('.more-toggle').onclick=()=>{const menu=phone.querySelector('.more-menu');const open=menu.classList.toggle('open');phone.querySelector('.more-toggle').setAttribute('aria-expanded',open);};
  phone.querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>{phone.querySelector('.more-menu').classList.remove('open');phone.querySelector('.more-toggle').setAttribute('aria-expanded','false');tell(`保留现有“${b.textContent}”入口。`);});
  phone.querySelectorAll('.floating-nav button').forEach(b=>b.onclick=()=>tell(b.textContent.trim()==='相册'?'当前为相册页。':`保留现有“${b.textContent.trim()}”导航。`));
  phone.querySelector('.access-primary').onclick=()=>{model.access='full';document.querySelector('#access-full').click();tell('模拟获得照片访问权限，直接显示手机相册。');};
  phone.querySelector('.access-alternative').onclick=()=>tell('仅在无权限时提供系统选择器替代入口，不常驻工具栏。');
  phone.onkeydown=e=>{if(e.key==='Escape'&&model.selecting)phone.querySelector('.dock-cancel').click();};
  render(model);demos.push(model);
}
function photo(p,i){return `<button class="photo" data-id="${i}" aria-label="${p[0]}" aria-pressed="false"><span class="photo-image" style="--px:${p[1]}%;--py:${p[2]}%"></span><span class="tick">${icon('check')}</span></button>`;}
function render(m){
  const p=m.phone,denied=m.source==='phone'&&m.access==='none';p.classList.toggle('selecting',m.selecting);p.classList.toggle('denied',denied);
  p.querySelectorAll('[data-source]').forEach(b=>{b.classList.toggle('active',b.dataset.source===m.source);b.setAttribute('aria-pressed',String(b.dataset.source===m.source));b.disabled=m.selecting;});
  p.querySelector('.count-row p').textContent=denied?'未授权':m.source==='app'?'共 24 张':'共 128 张';
  p.querySelectorAll('.photo').forEach(b=>{const selected=m.selecting&&m.selected.has(Number(b.dataset.id));b.classList.toggle('selected',selected);b.setAttribute('aria-pressed',String(selected));});
  p.querySelector('.selection-total').textContent=m.selected.size?'已选 '+m.selected.size+' 张':'未选择';
  p.querySelector('.action-dock').classList.toggle('app-actions',m.source==='app');p.querySelector('.dock-save').hidden=m.source!=='app';
  const main=p.querySelector('.dock-primary');main.textContent=m.source==='app'?'编辑':'批量编辑';main.setAttribute('aria-label','批量编辑所选照片');main.disabled=m.selected.size===0;p.querySelector('.dock-save').disabled=m.selected.size===0;
  p.querySelector('.more-menu').classList.remove('open');
  p.querySelector('.more-toggle').setAttribute('aria-expanded','false');
}
document.querySelectorAll('.phone-slot').forEach(build);
document.querySelector('#theme-toggle').onclick=e=>{const on=document.body.classList.toggle('dark');e.currentTarget.setAttribute('aria-pressed',String(on));e.currentTarget.textContent=on?'浅色预览':'深色预览';};
document.querySelector('#font-toggle').onclick=e=>{const on=document.body.classList.toggle('large-font');e.currentTarget.setAttribute('aria-pressed',String(on));e.currentTarget.textContent=on?'恢复字体':'放大字体';};
for(const state of ['full','none'])document.querySelector('#access-'+state).onclick=()=>{const m=demos[0];m.source='phone';m.selecting=false;m.selected.clear();m.access=state;render(m);for(const x of ['full','none']){const b=document.querySelector('#access-'+x);b.classList.toggle('chosen',x===state);b.setAttribute('aria-pressed',String(x===state));}};
