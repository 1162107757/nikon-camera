(() => {
  'use strict';
  const query = new URLSearchParams(location.search);
  const device = document.getElementById('device');
  const allowedScenes = ['entry','ready','captured','options','view-lost','offline','timeout','histogram'];
  const state = {scene:'ready',connection:'connected',orientation:query.get('orientation') === 'landscape' ? 'landscape':'portrait',large:query.get('large')==='1',transfer:false,grid:false,live:true,photo:false,imported:false,request:'idle',sheet:null,focus:null,feedback:'已连接，可以拍摄',shotCount:0,histogram:true,histogramMode:query.get('hist')==='rgb'?'rgb':'luma',histogramPosition:null};
  const timers = new Set();
  let focusReturn = null, captureGeneration = 0;
  const iconPaths = {
    back:'<path d="m14 6-6 6 6 6"/><path d="M8 12h12"/>',
    close:'<path d="m6 6 12 12M18 6 6 18"/>',
    more:'<circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>',
    camera:'<path d="M4 6h4l2-2h4l2 2h4v13H4z"/><circle cx="12" cy="12" r="4"/>',
    battery:'<rect x="2" y="7" width="18" height="10" rx="2"/><path d="M22 10v4M5 10h10v4H5z"/>',
    wifi:'<path d="M3 9a14 14 0 0 1 18 0M6 12a9 9 0 0 1 12 0M9 15a4 4 0 0 1 6 0"/><circle cx="12" cy="18" r=".7"/>',
    grid:'<rect x="3" y="3" width="18" height="18" rx="1"/><path d="M9 3v18M15 3v18M3 9h18M3 15h18"/>',
    focus:'<path d="M8 3H3v5M16 3h5v5M21 16v5h-5M8 21H3v-5"/><circle cx="12" cy="12" r="3"/>',
    image:'<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8" cy="9" r="1.5"/><path d="m4 18 5-5 4 3 3-4 5 6"/>',
    info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
    chevron:'<path d="m9 5 7 7-7 7"/>',
    retry:'<path d="M20 6v5h-5M4 18v-5h5"/><path d="M6 8a7 7 0 0 1 12-2l2 3M4 15l2 3a7 7 0 0 0 12-2"/>',
    connection:'<path d="m9 8 6 8M7 14l-2 2a4 4 0 0 0 6 6l2-2M17 10l2-2a4 4 0 0 0-6-6l-2 2M3 3l18 18"/>',
    settings:'<path d="m10 3-1 3-3 1-3 3 2 3-1 3 3 3 3-1 3 2 3-3 1-3 3-1-1-4-3-1-1-3z"/><circle cx="12" cy="12" r="3"/>',
    cards:'<rect x="5" y="3" width="15" height="15" rx="2"/><path d="M2 7v13a2 2 0 0 0 2 2h12"/><path d="m8 14 4-4 5 5"/>',
    check:'<path d="m5 12 4 4L19 6"/>',
    rotate:'<path d="m7 3-4 4 4 4M3 7h10a7 7 0 0 1 7 7v3"/><path d="m16 17 4 4 4-4"/>',
    warning:'<path d="m12 3 10 18H2z"/><path d="M12 9v5M12 17h.01"/>'
  };
  iconPaths.histogram='<path d="M3 20h18M5 18v-4h3V8h3V4h3v7h3v5h3v2"/>';
  const svg = (name) => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${iconPaths[name]||iconPaths.camera}</svg>`;
  const iconButton = (name,label,action,extra='') => `<button class="icon-button" type="button" aria-label="${label}" data-action="${action}" ${extra}>${svg(name)}</button>`;
  const toggle = (action,label,value,extraClass='') => `<button type="button" class="transfer-switch ${extraClass}" role="switch" aria-label="${label}" aria-checked="${value}" data-action="${action}"><span class="switch-track" aria-hidden="true"><span class="switch-knob"></span></span></button>`;
  const connected = () => state.connection==='connected';
  const canCapture = () => connected() && state.request === 'idle';
  const canFocus = () => connected() && state.live && !['view-lost','view-loading'].includes(state.scene) && state.request==='idle';
  const later = (fn,ms) => {const id=setTimeout(()=>{timers.delete(id);fn();},ms);timers.add(id);return id;};
  function clearTimers(){for(const id of timers)clearTimeout(id);timers.clear();captureGeneration++;}
  function statusBar(){return `<div class="statusbar"><span>14:32</span><div class="status-icons">${svg('wifi')}${svg('battery')}</div></div>`;}
  function bottomBar(){return '<div class="systembar" aria-hidden="true"><span></span></div>';}
  function renderEntry(){
    return `${statusBar()}<div class="sync-workspace" id="workspace"><h2 class="sync-heading">同步</h2><div class="sync-tabs"><span>相机</span><span>直播</span><span>已下载</span></div><div class="sync-camera"><div class="sync-camera-name">${svg('camera')}<div><strong>Nikon Z6 II</strong><small><i class="connection-dot"></i>${connected()?'Wi-Fi 已连接':'尚未连接'}</small></div></div><span>${connected()?'电量 68%':'电量 —'}</span></div><button type="button" class="remote-entry" data-action="enter"><span><strong>遥控拍摄</strong><small>查看实时画面、机身参数并拍照</small></span>${svg('chevron')}</button><div class="sync-section-title">相机照片<span>示例 · 24 张</span></div><div class="sync-grid"><figure><img src="assets/live-view.png" alt="合成示例：湖边人像"><figcaption>DSC_6192.JPG</figcaption></figure><figure><img src="assets/live-view.png" alt="同一合成示例，仅用于界面排版"><figcaption>DSC_6191.JPG</figcaption></figure></div>${state.request==='capturing'?'<p class="sync-section-title">正在等待相机拍摄结果…</p>':state.request==='unknown'?'<p class="sync-section-title">拍摄结果待确认，进入遥控拍摄核对</p>':''}<div class="sync-bottom-nav" aria-label="现有根导航示意"><span>${svg('image')}预设</span><span class="selected">${svg('camera')}同步</span><span>${svg('cards')}相册</span><span>${svg('settings')}设置</span></div></div>${bottomBar()}`;
  }
  function curtain(){
    let title='',copy='',button='',action='',symbol='connection';
    if(state.scene==='offline'){title='相机连接已断开';copy='画面和参数已停止更新。<br>重新连接后再继续拍摄。';button='重新连接';action='reconnect';}
    else if(state.scene==='connecting'){title='正在连接 Nikon Z6 II';copy='请保持相机开机，手机连接相机 Wi-Fi。';}
    else if(state.scene==='view-lost'){title='实时取景已中断';copy='机身仍已连接，可继续使用快门。<br>画面恢复前无法点按对焦。';button='重新开启取景';action='retry-view';symbol='camera';}
    else if(state.scene==='view-loading'){title='正在重新开启取景';copy='快门功能仍可使用。';symbol='camera';}
    else if(!state.live){title='实时取景已关闭';copy='可以继续查看机身参数和遥控拍摄。';button='开启实时取景';action='live';symbol='camera';}
    if(!title)return '';
    return `<div class="image-curtain" role="status">${svg(symbol)}<strong>${title}</strong><p>${copy}</p>${button?`<button type="button" class="small-action" data-action="${action}">${button}</button>`:''}</div>`;
  }
  function feedback(){
    if(state.scene==='offline')return {text:'连接已断开，快门不可用',kind:'warning'};
    if(state.scene==='connecting')return {text:'正在连接相机…',kind:''};
    if(state.request==='unknown')return {text:'拍摄结果待确认 · 查看相机照片',kind:'warning',action:'check-result'};
    if(state.request==='capturing')return {text:'正在拍摄，请等待相机响应…',kind:''};
    return {text:state.feedback,kind:state.photo?'success':''};
  }
  function histogramFresh(){return connected()&&state.live&&!['view-lost','view-loading'].includes(state.scene)&&state.request!=='capturing';}
  function histogramGraphic(large=false){
    const channels=state.histogramMode==='rgb'?['r','g','b']:['luma'];
    const colors={r:'#F0787D',g:'#81B68E',b:'#7AA5EC',luma:'#D9D3CB'};
    const bins=window.remoteHistogramData.bins;const max=Math.max(...channels.flatMap(channel=>bins[channel]));
    const paths=channels.map(channel=>{const points=bins[channel].map((value,i)=>`${(i*240/63).toFixed(2)},${(52-value/max*46).toFixed(2)}`);return `<path d="M0,52 L${points.join(' L')} L240,52Z" fill="${colors[channel]}" fill-opacity="${channels.length===1?'.7':'.14'}" stroke="${colors[channel]}" stroke-width="${large?'1.4':'1.6'}" stroke-linejoin="round"/>`;}).join('');
    return `<svg class="histogram-graph" viewBox="0 0 240 56" preserveAspectRatio="none" aria-label="${state.histogramMode==='rgb'?'红绿蓝三通道':'亮度'}示例取景像素分布" role="img">${paths}<path d="M0 53h240" stroke="#6B655F" stroke-width="1"/></svg>`;
  }
  function histogramWidget(){
    if(!state.histogram)return '';
    const fresh=histogramFresh();const title=state.histogramMode==='rgb'?'RGB':'亮度';
    const position=state.histogramPosition?`left:${state.histogramPosition.x}%;top:${state.histogramPosition.y}%;bottom:auto;`:'';
    return `<button type="button" class="histogram-panel ${fresh?'':'paused'}" data-action="histogram-detail" aria-label="当前取景直方图，${title}，${fresh?'取景更新中':'已暂停'}；点按放大，拖动可移动" style="${position}"><span class="histogram-caption"><span>${fresh?'取景':'上次取景'} · ${title}</span><span class="histogram-state">${fresh?'<i></i>':'已暂停'}</span></span>${histogramGraphic()}</button>`;
  }
  function renderCamera(){
    const unavailable=!connected(),busy=state.request==='capturing';const f=feedback();
    const focus=state.focus;
    const values=unavailable?['—','—','—','—']:['1/250','F2.8','320','0.0'];
    const labels=['快门','光圈','ISO','曝光补偿'];
    return `${statusBar()}<div class="workspace" id="workspace"><header class="appbar">${iconButton('back','返回同步','back')}<h2>遥控拍摄</h2>${iconButton('more','拍摄设置','options')}</header><div class="device-name-row"><div class="device-identity"><i class="connection-dot"></i><span>Nikon Z6 II${unavailable?' · 已断开':' · Wi-Fi'}</span></div><span class="battery-status">${svg('battery')}${unavailable?'—':'68%'}</span></div><div class="camera-layout"><div class="view-area"><div class="photo-plane ${canFocus()?'can-focus':''}" ${canFocus()?'role="button" tabindex="0" aria-label="取景画面，点按选择对焦位置"':''}><img class="view-image" src="assets/live-view.png" alt="合成示例取景画面：湖边人像，不代表真实相机连接" draggable="false">${state.grid?'<div class="grid-lines" aria-hidden="true"></div>':''}<div class="focus-rect ${focus?'visible':''} ${focus&&focus.locked?'locked':''}" style="left:${focus?focus.x:50}%;top:${focus?focus.y:50}%" aria-hidden="true"></div>${curtain()}</div><div class="view-tools"><span class="view-mode"><b class="mode">${unavailable?'—':'M'}</b><span>${unavailable?'参数未更新':'AF-S · 单张'}</span></span><div class="tool-buttons">${iconButton('histogram','显示或收起直方图','histogram-toggle',`aria-pressed="${state.histogram}"`)}${iconButton('grid','切换构图网格','grid',`aria-pressed="${state.grid}"`)}${iconButton('info','查看机身参数','parameters')}</div></div>${!state.histogram&&!curtain()&&state.request!=='unknown'?'<div class="view-instruction">'+(focus&&focus.locked?'对焦完成':'点按画面对焦')+'</div>':''}${histogramWidget()}</div><div class="control-area"><div class="parameters" aria-label="机身当前参数，只读">${values.map((value,i)=>`<div class="parameter"><div class="value">${value}${i===3&&connected()?'<span class="unit">EV</span>':''}</div><div class="label">${labels[i]}</div></div>`).join('')}</div><div class="camera-feedback ${f.kind}" role="status" aria-live="polite">${f.action?`<button class="feedback-action" type="button" data-action="${f.action}">${f.text}</button>`:f.text}</div><div class="release-row"><button type="button" class="side-control ${state.photo?'':'recent-empty'}" data-action="recent" aria-label="查看最近拍摄" ${state.photo?'':'disabled'}><span class="side-icon">${state.photo?'<img src="assets/live-view.png" alt="最近拍摄的合成示例缩略图">':svg('image')}</span><span>最近拍摄</span></button><div class="shutter-container"><button type="button" class="shutter ${busy?'pending':''}" data-action="capture" aria-label="拍照" ${canCapture()?'':'disabled'}><span class="shutter-center">${busy?'<span class="busy-mark" aria-hidden="true"></span>':''}</span></button></div><button type="button" class="side-control" data-action="focus" aria-label="自动对焦" ${canFocus()?'':'disabled'}><span class="side-icon">${svg('focus')}</span><span>对焦</span></button></div><div class="transfer-row"><div class="save-target">照片保存到相机</div><button type="button" class="transfer-switch" role="switch" aria-checked="${state.transfer}" aria-label="拍后传入 App" data-action="transfer"><span>拍后传入 App</span><span class="switch-track" aria-hidden="true"><span class="switch-knob"></span></span></button></div></div></div></div>${bottomBar()}<div class="capture-flash" aria-hidden="true"></div>`;
  }
  function sheetContent(name){
    if(name==='histogram')return {title:'取景直方图',body:`<p class="sheet-copy">${histogramFresh()?'根据当前取景帧更新。':'取景未更新，直方图已暂停。'}</p><div class="histogram-segment" role="group" aria-label="直方图通道"><button type="button" aria-pressed="${state.histogramMode==='luma'}" data-action="hist-luma">亮度</button><button type="button" aria-pressed="${state.histogramMode==='rgb'}" data-action="hist-rgb">RGB</button></div><div class="histogram-expanded ${histogramFresh()?'':'paused'}">${histogramGraphic(true)}</div><div class="histogram-tone"><span>暗部</span><span>亮部</span></div>${state.histogramMode==='rgb'?'<div class="histogram-legend"><span class="red">R 红</span><span class="green">G 绿</span><span class="blue">B 蓝</span></div>':''}<div class="setting-line"><div class="setting-label">显示在取景页<small>点按放大，拖动小图可调整位置</small></div>${toggle('histogram-toggle','显示当前取景直方图',state.histogram)}</div><p class="setting-footer">取景帧经过相机处理，分布仅供取景曝光参考；不是 RAW 原始数据。<br>此原型由合成示例画面计算曲线，没有连接真实相机。</p>`};
    if(name==='options')return {title:'拍摄设置',body:`<p class="sheet-copy">取景和参数来自当前连接的相机。</p><div class="setting-line"><div class="setting-label">实时取景<small>关闭后仍可查看参数和按快门</small></div>${toggle('live','实时取景',state.live)}</div><div class="setting-line"><div class="setting-label">构图网格<small>仅辅助构图，不写入照片</small></div>${toggle('grid','构图网格',state.grid)}</div><div class="setting-line"><div class="setting-label">拍后传入 App<small>照片仍保存在相机，JPEG 另传入 App</small></div>${toggle('transfer','拍后传入 App',state.transfer)}</div><button type="button" class="setting-action" data-action="parameters"><span>查看机身参数</span>${svg('chevron')}</button><button type="button" class="setting-action danger" data-action="disconnect"><span>断开相机连接</span>${svg('chevron')}</button><p class="setting-footer">返回同步会结束取景，保留相机连接。<br>原始文件和拍后传入遵循现有同步设置。</p>`};
    if(name==='parameters'){
      const fresh=connected();const rows=[['拍摄模式','M'],['快门速度','1/250 秒'],['光圈','F2.8'],['ISO','320'],['曝光补偿','0.0 EV'],['对焦模式','AF-S'],['释放模式','单张'],['图像品质','RAW + JPEG']];
      return {title:'机身当前参数',body:`<p class="sheet-copy">${fresh?'读取相机当前值；这一版在机身上调整。':'连接已断开。重新连接后读取当前值。'}</p><dl class="parameter-detail">${rows.map(([label,value])=>`<div><dt>${label}</dt><dd>${fresh?value:'—'}</dd></div>`).join('')}</dl><p class="setting-footer">相机未提供的项目显示“—”，不会用照片 EXIF 补成实时参数。</p>`};
    }
    if(name==='recent')return {title:'最近拍摄',body:`<img class="sheet-photo" src="assets/live-view.png" alt="最近拍摄的合成示例"><dl class="parameter-detail"><div><dt>文件</dt><dd>DSC_6193.JPG</dd></div><div><dt>状态</dt><dd>${state.imported?'已传入 App':'已保存到相机'}</dd></div></dl>${!state.imported?'<button type="button" class="primary-sheet-button" data-action="download-recent">传入 App</button>':'<button type="button" class="primary-sheet-button" data-action="open-album">查看已传入照片</button>'}<p class="setting-footer">示例照片仅演示拍摄后的查看和传入流程。</p>`};
    if(name==='check-result')return {title:'核对拍摄结果',body:'<p class="sheet-copy">快门请求没有收到完整响应。为避免重复拍摄，不会自动重发快门。</p><div class="notice-heading">先查看相机的最近照片</div><p class="sheet-copy">确认有无新照片，再恢复拍摄。这里将模拟查询到一张新照片。</p><button type="button" class="primary-sheet-button" data-action="confirm-result">查看相机照片</button>'};
    if(name==='downloaded')return {title:'已传入 App',body:'<p class="sheet-copy">示例 JPEG 已加入“同步 → 已下载”，可继续查看、加边框或编辑。</p><img class="sheet-photo" src="assets/live-view.png" alt="已传入的合成示例"><button type="button" class="primary-sheet-button" data-action="close-sheet">返回拍摄</button>'};
    return {title:'',body:''};
  }
  function renderSheet(){
    if(!state.sheet)return '';
    const content=sheetContent(state.sheet);
    return `<div class="sheet-host"><button type="button" class="sheet-backdrop" aria-label="关闭面板" data-action="close-sheet" tabindex="-1"></button><section class="sheet-dialog" role="dialog" aria-modal="true" aria-labelledby="sheet-title" tabindex="-1"><div class="sheet-handle" aria-hidden="true"></div><div class="sheet-heading"><h3 id="sheet-title">${content.title}</h3>${iconButton('close','关闭面板','close-sheet')}</div>${content.body}</section></div>`;
  }
  function render(){
    const active=document.activeElement;const action=active&&device.contains(active)?active.dataset.action:null;
    device.dataset.orientation=state.orientation;device.dataset.scene=state.scene;device.dataset.connected=String(connected());device.classList.toggle('large-type',state.large);
    device.innerHTML=(state.scene==='entry'?renderEntry():renderCamera())+renderSheet();
    const workspace=device.querySelector('#workspace');if(workspace){workspace.inert=Boolean(state.sheet);if(state.sheet)workspace.setAttribute('aria-hidden','true');}
    if(state.sheet){device.querySelector('.sheet-dialog').focus({preventScroll:true});}
    else if(action){const next=device.querySelector(`[data-action="${action}"]`);if(next&&!next.disabled)next.focus({preventScroll:true});}
    for(const button of document.querySelectorAll('[data-scene]'))if(button!==device)button.setAttribute('aria-current',button.dataset.scene===(state.sheet==='options'?'options':state.sheet==='histogram'?'histogram':state.scene)?'true':'false');
    for(const button of document.querySelectorAll('[data-orientation]'))if(button!==device)button.setAttribute('aria-pressed',button.dataset.orientation===state.orientation?'true':'false');
    document.getElementById('large-type').checked=state.large;
  }
  function openSheet(name){focusReturn=document.activeElement?.dataset.action||'options';state.sheet=name;render();}
  function closeSheet(){state.sheet=null;render();const target=device.querySelector(`[data-action="${focusReturn||'options'}"]`);if(target&&!target.disabled)target.focus({preventScroll:true});}
  function setScene(scene){
    clearTimers();state.focus=null;state.sheet=null;state.histogramPosition=null;state.request='idle';state.live=true;state.feedback='已连接，可以拍摄';state.photo=false;state.imported=false;state.transfer=false;
    state.scene=allowedScenes.includes(scene)?scene:'ready';state.connection=scene==='offline'?'disconnected':'connected';
    if(scene==='captured'){state.scene='captured';state.photo=true;state.feedback='已保存到相机';}
    if(scene==='view-lost')state.feedback='机身仍已连接，可继续拍摄';
    if(scene==='timeout'){state.request='unknown';state.feedback='拍摄结果待确认';}
    if(scene==='options'){state.scene='ready';state.sheet='options';}
    if(scene==='histogram'){state.scene='ready';state.sheet='histogram';state.histogram=true;}
    render();
  }
  function focusAt(x=50,y=50){
    if(!canFocus())return;
    state.focus={x:Math.max(8,Math.min(92,x)),y:Math.max(10,Math.min(90,y)),locked:false};state.feedback='正在对焦…';render();
    const current=state.focus;later(()=>{if(state.focus!==current||!canFocus())return;state.focus.locked=true;state.feedback='对焦完成，可以拍摄';render();},650);
  }
  function capture(){
    if(!canCapture())return false;
    state.request='capturing';state.focus=null;state.feedback='正在拍摄，请等待相机响应…';state.shotCount++;const generation=++captureGeneration;
    render();device.querySelector('.capture-flash')?.classList.add('active');
    later(()=>{
      if(generation!==captureGeneration||!connected())return;
      state.request='idle';state.photo=true;state.feedback=state.transfer?'已拍摄，正在传入 App…':'已保存到相机';
      const shouldTransfer=state.transfer;render();
      if(shouldTransfer)later(()=>{if(generation!==captureGeneration)return;state.imported=true;state.feedback='已传入 App · DSC_6193.JPG';render();},1100);
    },1200);return true;
  }
  function act(action){
    switch(action){
      case 'enter':state.scene=connected()?'ready':'offline';state.feedback=state.photo?'已保存到相机':'已连接，可以拍摄';render();break;
      case 'back':state.scene='entry';state.sheet=null;state.focus=null;render();break;
      case 'options':openSheet('options');break;
      case 'parameters':openSheet('parameters');break;
      case 'histogram-detail':openSheet('histogram');break;
      case 'histogram-toggle':state.histogram=!state.histogram;render();break;
      case 'hist-luma':state.histogramMode='luma';render();break;
      case 'hist-rgb':state.histogramMode='rgb';render();break;
      case 'recent':if(state.photo)openSheet('recent');break;
      case 'close-sheet':closeSheet();break;
      case 'grid':state.grid=!state.grid;render();break;
      case 'transfer':state.transfer=!state.transfer;render();break;
      case 'focus':focusAt();break;
      case 'capture':capture();break;
      case 'live':state.live=!state.live;if(state.live&&state.scene==='view-lost')state.scene='ready';state.focus=null;render();break;
      case 'disconnect':{const uncertain=state.request==='capturing'||state.request==='unknown';clearTimers();state.connection='disconnected';state.scene='offline';state.request=uncertain?'unknown':'idle';state.sheet=null;state.focus=null;render();break;}
      case 'reconnect':state.connection='connecting';state.scene='connecting';render();later(()=>{state.connection='connected';state.scene='ready';state.feedback='已重新连接，可以拍摄';render();},1000);break;
      case 'retry-view':state.scene='view-loading';render();later(()=>{state.scene='ready';state.feedback='实时取景已恢复';render();},850);break;
      case 'check-result':openSheet('check-result');break;
      case 'confirm-result':state.request='idle';state.scene='captured';state.photo=true;state.feedback='已核对新照片 · 未重复发送快门';state.sheet='recent';render();break;
      case 'download-recent':state.imported=true;state.feedback='已传入 App · DSC_6193.JPG';state.sheet='downloaded';render();break;
      case 'open-album':state.sheet='downloaded';render();break;
    }
  }
  let draggingHistogram=null,suppressHistogramClick=false;
  device.addEventListener('pointerdown',event=>{const panel=event.target.closest('.histogram-panel');if(!panel)return;const area=panel.closest('.view-area').getBoundingClientRect(),rect=panel.getBoundingClientRect();draggingHistogram={id:event.pointerId,element:panel,startX:event.clientX,startY:event.clientY,left:rect.left-area.left,top:rect.top-area.top,area,width:rect.width,height:rect.height,moved:false};panel.setPointerCapture(event.pointerId);});
  device.addEventListener('pointermove',event=>{const drag=draggingHistogram;if(!drag||drag.id!==event.pointerId)return;const dx=event.clientX-drag.startX,dy=event.clientY-drag.startY;if(Math.hypot(dx,dy)>7)drag.moved=true;if(!drag.moved)return;const x=Math.max(4,Math.min(drag.area.width-drag.width-4,drag.left+dx)),y=Math.max(4,Math.min(drag.area.height-drag.height-4,drag.top+dy));state.histogramPosition={x:x/drag.area.width*100,y:y/drag.area.height*100};Object.assign(drag.element.style,{left:state.histogramPosition.x+'%',top:state.histogramPosition.y+'%',bottom:'auto'});});
  device.addEventListener('pointerup',event=>{if(draggingHistogram?.id!==event.pointerId)return;suppressHistogramClick=draggingHistogram.moved;draggingHistogram=null;});
  device.addEventListener('pointercancel',()=>{draggingHistogram=null;suppressHistogramClick=false;});
  device.addEventListener('click',(event)=>{
    const button=event.target.closest('[data-action]');if(button){if(button.dataset.action==='histogram-detail'&&suppressHistogramClick){suppressHistogramClick=false;return;}if(!button.disabled)act(button.dataset.action);return;}
    const plane=event.target.closest('.photo-plane.can-focus');if(plane&&!state.sheet){const box=plane.getBoundingClientRect();focusAt(event.detail?(event.clientX-box.left)/box.width*100:50,event.detail?(event.clientY-box.top)/box.height*100:50);}
  });
  device.addEventListener('keydown',(event)=>{
    if(event.key==='Escape'&&state.sheet){event.preventDefault();closeSheet();return;}
    if(event.target.classList.contains('can-focus')&&['Enter',' '].includes(event.key)){event.preventDefault();focusAt();return;}
    if(event.key==='Tab'&&state.sheet){const items=[...device.querySelectorAll('.sheet-dialog button:not(:disabled),.sheet-dialog [tabindex="0"]')];const first=items[0],last=items[items.length-1];if(!items.length)return;if(event.shiftKey&&(document.activeElement===first||document.activeElement===device.querySelector('.sheet-dialog'))){event.preventDefault();last.focus();}else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}}
  });
  document.querySelectorAll('.scenario-nav button').forEach(button=>button.addEventListener('click',()=>setScene(button.dataset.scene)));
  document.querySelectorAll('.orientation-control button').forEach(button=>button.addEventListener('click',()=>{state.orientation=button.dataset.orientation;state.histogramPosition=null;render();}));
  document.getElementById('large-type').addEventListener('change',event=>{state.large=event.target.checked;render();});
  if(query.get('embed')==='1')document.body.classList.add('embed');
  setScene(query.get('scene')||'ready');
  window.remoteCaptureDesign={getState:()=>JSON.parse(JSON.stringify(state)),setScene,setOrientation:(value)=>{state.orientation=value;state.histogramPosition=null;render();},setLarge:(value)=>{state.large=value;render();},act};
  window.designReady=true;
})();
