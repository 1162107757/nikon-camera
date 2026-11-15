(() => {
  const q = new URLSearchParams(location.search);
  const pick=(key,values,fallback)=>values.includes(q.get(key))?q.get(key):fallback;
  const c={platform:pick('platform',['android','ios'],'android'),theme:pick('theme',['light','dark'],'light'),surface:pick('surface',['connection','sync'],'connection'),transport:pick('transport',['wifi','usb'],'wifi'),state:pick('state',['idle','connecting','confirm','permission','denied','timeout','failed','usbempty','usbfound','usbpermission','success'],'idle'),source:pick('source',['sync','presets'],'sync'),panel:pick('panel',['closed','tools','downloads','remote','presets'],'closed'),queue:pick('queue',['empty','active','failed'],'empty'),disconnected:q.get('disconnected')==='true'};
  const model={...c,page:c.surface==='connection'?'connection':'sync',brand:'nikon',loaded:c.surface==='sync',selection:false,selected:new Set(),raw:false,paused:false,slot:'C1',toast:'',successToast:false,remoteBusy:false,remoteSent:false,sourceTab:'camera',generation:0,preview:-1};
  Object.assign(model,{remoteLive:pick('remoteState',['ready','paused','waiting','unsupported','uncertain'],'ready'),remoteCaptureUncertain:q.get('remoteState')==='uncertain',remoteGrid:true,remoteHistogram:false,remoteTransfer:false,focusPoint:null,focusSent:false,photoSort:'newest'});
  if(model.remoteLive==='uncertain')model.remoteLive='ready';
  if(model.surface==='sync'&&model.panel==='remote'){model.page='remote';model.panel='closed'}
  document.documentElement.dataset.theme=c.theme;
  document.documentElement.style.colorScheme=c.theme;
  const root=document.getElementById('app');
  const paths={
    back:'<path d="m14 5-7 7 7 7"/>',close:'<path d="m6 6 12 12M18 6 6 18"/>',chevron:'<path d="m9 6 6 6-6 6"/>',external:'<path d="M14 4h6v6m0-6-9 9"/><path d="M10 5H5a1 1 0 0 0-1 1v13a1 1 0 0 0 1 1h13a1 1 0 0 0 1-1v-5"/>',
    wifi:'<path d="M3 9a14 14 0 0 1 18 0M6 12a9 9 0 0 1 12 0m-9 3a4.8 4.8 0 0 1 6 0"/><circle cx="12" cy="18.5" r=".8" fill="currentColor" stroke="none"/>',
    usb:'<path d="M12 21V4m-3 3 3-3 3 3M12 16l-6-4V9m6 4 6-4V6"/><circle cx="6" cy="7" r="2"/><path d="M16 3h4v3h-4z"/><circle cx="12" cy="21" r="1"/>',
    camera:'<path d="M8 6 9.5 3.5h5L16 6h4a1.5 1.5 0 0 1 1.5 1.5v12A1.5 1.5 0 0 1 20 21H4a1.5 1.5 0 0 1-1.5-1.5v-12A1.5 1.5 0 0 1 4 6z"/><circle cx="12" cy="13" r="4.5"/>',
    tools:'<path d="M4 6h3m5 0h8M4 12h9m5 0h2M4 18h2m5 0h9"/><circle cx="9.5" cy="6" r="2.5"/><circle cx="15.5" cy="12" r="2.5"/><circle cx="8.5" cy="18" r="2.5"/>',
    download:'<path d="M12 3v12m-4-4 4 4 4-4M4 16v4h16v-4"/>',grid:'<rect x="3.5" y="3.5" width="6" height="6" rx="1.3"/><rect x="14.5" y="3.5" width="6" height="6" rx="1.3"/><rect x="3.5" y="14.5" width="6" height="6" rx="1.3"/><rect x="14.5" y="14.5" width="6" height="6" rx="1.3"/>',
    check:'<path d="m5 12 4 4L19 6"/>',clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',shield:'<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6z"/><path d="m8.5 11.5 2.5 2.5 4.5-5"/>',
    warning:'<path d="m10.5 4-8 14a1.5 1.5 0 0 0 1.3 2.2h16.4a1.5 1.5 0 0 0 1.3-2.2l-8-14a1.7 1.7 0 0 0-3 0Z"/><path d="M12 9v4m0 3h.01"/>',
    network:'<path d="M8 16 6.5 17.5a4.2 4.2 0 0 1-6-6L5 7a4.2 4.2 0 0 1 6 0m2 10a4.2 4.2 0 0 0 6 0l4.5-4.5a4.2 4.2 0 0 0-6-6L16 8M7 17 17 7" transform="translate(0 -1) scale(.94)"/>',
    info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10h.01"/>',refresh:'<path d="M20 7v5h-5M4 17v-5h5"/><path d="M5.5 7.5a7.5 7.5 0 0 1 12.8-2L20 8M4 16l1.7 2.5a7.5 7.5 0 0 0 12.8-2"/>',
    pause:'<path d="M8 5v14M16 5v14"/>',play:'<path d="m8 4 12 8-12 8z"/>',image:'<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8.2" cy="8.2" r="1.7"/><path d="m3 17 5-5 4 4 4-6 5 7"/>',
    settings:'<path d="m9 3-.8 3-2.7 1-2.6-.6-1.5 2.7 2.1 2 .2 2.9-1.7 2.2 1.7 2.6 2.8-.5 2.4 1.3.8 2.4h3l.9-2.5 2.6-1 2.6.5 1.6-2.7-1.8-2.1.1-2.8 1.8-2.2-1.7-2.6-2.7.5-2.5-1.2L12.8 3z" transform="translate(1 -1) scale(.92)"/><circle cx="12" cy="12" r="3"/>',
    sliders:'<path d="M6 3v3m0 4v11M12 3v10m0 4v4M18 3v4m0 4v10"/><path d="M3 6h6v4H3zM9 13h6v4H9zM15 7h6v4h-6z"/>',
    spinner:'<path d="M20 12a8 8 0 1 1-8-8"/>',signal:'<path d="M3 17v3m5-7v7m5-11v11m5-15v15"/>',battery:'<rect x="2" y="6" width="18" height="12" rx="2.6"/><path d="M22 10v4"/><rect x="4" y="8" width="13" height="8" rx="1" fill="currentColor" stroke="none"/>',help:'<circle cx="12" cy="12" r="9"/><path d="M9.5 8.5a2.5 2.5 0 1 1 4 2c-1.5.8-1.5 1.5-1.5 2.5m0 3h.01"/>'
  };
  Object.assign(paths,{focus:'<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/><circle cx="12" cy="12" r="3.5"/>',histogram:'<path d="M3 20h18M5 17v-4m4 4V7m4 10V4m4 13v-7m4 7v-2"/>','grid-lines':'<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18m6-18v18M3 9h18M3 15h18"/>'});
  const icon=(name,cls='')=>`<svg class="icon ${cls}" viewBox="0 0 24 24" aria-hidden="true">${paths[name]||paths.info}</svg>`;
  const action=(name,label,cls='',extra='')=>`<button type="button" data-action="${name}" class="${cls}" ${extra}>${label}</button>`;
  const ib=(name,symbol,label,cls='')=>action(name,icon(symbol),`icon-button ${cls}`,`aria-label="${label}"`);
  const photos=[['alpine-lake.jpg','DSC_4821.JPG','山间湖泊'],['portrait-smile.jpg','DSC_4820.JPG','户外人像'],['coastal-water.jpg','DSC_4819.JPG','海岸'],['sunlit-forest.jpg','DSC_4818.JPG','林间光线'],['pink-tulips.jpg','DSC_4817.JPG','粉色郁金香'],['rainy-tokyo.jpg','DSC_4816.JPG','雨中的街道']];
  Object.assign(paths,{sort:'<path d="M8 4v16m-4-4 4 4 4-4M16 20V4m-4 4 4-4 4 4"/>'});
  const brandName=()=>model.brand==='nikon'?'尼康':'富士 X-T20';
  const busy=()=>['connecting','confirm','permission','usbpermission'].includes(model.state);
  const statusbar=()=>`<div class="statusbar"><span>9:41</span>${c.platform==='android'?'<span class="camera-hole" aria-hidden="true"></span>':''}<span class="status-icons">${icon('signal')}${icon('wifi')}${icon('battery','battery')}</span></div>`;
  const systemBottom=()=>'<div class="system-bottom" aria-hidden="true"></div>';
  function transport(){return `<div class="transport" role="tablist" aria-label="连接方式">${['wifi','usb'].map(t=>action('transport-'+t,icon(t)+(t==='wifi'?'Wi-Fi':'USB'),' ',`role="tab" aria-selected="${model.transport===t}" ${busy()?'disabled':''}`)).join('')}</div>`}
  function connection(){
    const usb=model.transport==='usb';
    const state=model.state;
    const intro=state==='idle'?'选择连接方式，保持相机开启。':usb?'USB 数据线连接':'Wi-Fi 无线连接';
    let body='',footer='';
    if(state==='idle'){
      body=usb?`<ol class="steps"><li><span class="step-number">1</span><div><strong>用数据线连接相机与手机</strong><p>使用支持数据传输的线缆，保持相机电源开启。</p></div></li><li><span class="step-number">2</span><div><strong>在相机上确认 USB 用途</strong><p>如有提示，选择照片传输或机身支持的连接模式。</p></div></li><li><span class="step-number">3</span><div><strong>检测设备并允许访问</strong><p>按系统和相机上的提示完成授权。</p></div></li></ol><p class="usb-tip">相机需要支持对应的 USB 连接能力。未检测到设备时，可检查线缆和机身 USB 设置。</p>`:`${action('brand',`<span>相机类型</span><span>${brandName()}${icon('chevron')}</span>`,'camera-type','aria-label="选择相机类型"')}<ol class="steps"><li><span class="step-number">1</span><div><strong>在相机上开启 Wi-Fi</strong><p>保持机身的无线连接界面开启。</p></div></li><li><span class="step-number">2</span><div><strong>让手机连接相机的 Wi-Fi</strong><p>在系统 Wi-Fi 设置中选择相机网络。</p>${action('wifi-settings',(c.platform==='ios'?'查看 Wi-Fi 连接指引':'前往 Wi-Fi 设置')+icon('external'),'text-action')}</div></li><li><span class="step-number">3</span><div><strong>回到 Huevia，开始连接</strong><p>${model.brand==='fuji'?'请在 X-T20 机身按 OK 确认连接。':'机身出现连接提示时，请在相机上确认。'}</p></div></li></ol>${c.platform==='ios'?`<p class="permission-note">${icon('shield')}<span>首次连接请允许“本地网络”访问。</span></p>`:''}${action('settings','连接设置'+icon('chevron'),'connection-settings')}`;
      footer=action(usb?'detect-usb':'connect',usb?'检测 USB 相机':'开始连接','primary')+'<p class="footnote">连接成功后，直接返回上一页。</p>';
    } else if(state==='usbfound'){
      body=`<div class="state-content"><div class="state-mark">${icon('usb')}</div><h2>检测到 USB 相机</h2><p class="state-description">选择此相机继续连接。首次连接时，请允许系统访问此设备。</p>${action('usb-select',icon('camera')+'<span><strong>Nikon Z f</strong><small>USB 设备 · 等待连接</small></span>'+icon('check','end-icon'),'device-row','aria-label="选择 Nikon Z f USB 相机"')}<p class="usb-tip">如果设备不符，可以重新检测。</p>${action('detect-usb',icon('refresh')+'重新检测','text-action')}</div>`;
      footer=action('connect','连接此相机','primary')+'<p class="footnote">连接成功后，直接返回上一页。</p>';
    } else if(state==='usbempty'){
      body=`<div class="state-content"><div class="state-mark">${icon('usb')}</div><h2>尚未发现 USB 相机</h2><p class="state-description">检查数据线和机身设置后，再检测一次。</p><ul class="help-list"><li>${icon('check')}<span>确认线缆支持数据传输，而非仅充电。</span></li><li>${icon('check')}<span>保持相机开启，重新插拔线缆或转接头。</span></li><li>${icon('check')}<span>按机身提示选择可用的 USB 传输模式。</span></li></ul></div>`;
      footer=action('detect-usb',icon('refresh')+'重新检测','primary')+action('transport-wifi','改用 Wi-Fi 连接','text-action');
    } else if(['connecting','confirm','permission','usbpermission'].includes(state)){
      const local=state==='permission',usbPermission=state==='usbpermission';
      const title=usbPermission?'请允许访问 USB 相机':local?(c.platform==='ios'?'请允许本地网络访问':'等待网络连接确认'):state==='confirm'?'请在相机上确认连接':usb?'正在连接 USB 相机':'正在连接相机';
      const desc=usbPermission?'请在系统的 USB 访问提示中允许 Huevia 访问此相机。':local?(c.platform==='ios'?'请在系统弹窗中选择“允许”。本地网络权限用于发现和连接相机。':'请在系统连接提示中允许连接相机网络，然后返回 Huevia。'):state==='confirm'?'查看相机屏幕，并按机身提示确认。连接过程中请保持相机开启。':usb?'正在打开相机会话，请保持数据线连接。':'正在检查相机网络并建立连接。请保持手机连接相机的 Wi-Fi。';
      body=`<div class="state-content"><div class="state-mark ${local||usbPermission?'permission':''}">${icon(local||usbPermission?'shield':state==='confirm'?'camera':usb?'usb':'network')}</div><h2>${title}</h2><p class="state-description">${desc}</p><p class="state-meta">${icon('clock')}已用 ${state==='confirm'?'18':'12'} 秒 · 可随时取消</p><div class="phase-list">${phase('检查连接与权限',state==='confirm'?'done':'current')}${phase('机身确认与建立会话',state==='confirm'?'current':'future')}${phase('完成连接并返回','future')}</div>${local||usbPermission?'<p class="subtle-state">授权提示由系统显示。若未看到弹窗，可取消后重新连接。</p>':''}</div>`;
      footer=action('cancel-connect','取消连接','secondary-button')+'<p class="footnote">取消后停止本次连接，保留连接方式。</p>';
    } else {
      const denied=state==='denied',timed=state==='timeout';
      const title=denied?(usb?'尚未允许 USB 访问':c.platform==='ios'?'本地网络访问未开启':'网络连接未获允许'):timed?'连接等待已超时':'未能连接相机';
      const desc=denied?(usb?'此次连接已停止。允许 Huevia 访问 USB 相机后，再试一次。':c.platform==='ios'?'此次连接已停止。请在 iPhone 设置中，允许 Huevia 访问“本地网络”。':'此次连接已停止。请重新发起连接，并在系统网络提示中允许连接。'):timed?(usb?'本次连接已停止。检查线缆、USB 授权和机身确认后重试。':'本次连接已停止。检查相机 Wi-Fi、本地网络权限和机身确认后重试。'):(usb?'相机会话未能建立。请重新插拔数据线，并核对相机的 USB 模式。':'未能建立相机会话。请确认手机连接了正确的相机 Wi-Fi，且相机仍在等待连接。');
      body=`<div class="state-content"><div class="state-mark error">${icon(denied?'shield':timed?'clock':'warning')}</div><h2>${title}</h2><p class="state-description">${desc}</p><ul class="help-list">${denied?'':`<li>${icon('check')}<span>${usb?'保持相机开启，检查数据线与转接头。':'相机的 Wi-Fi 需要保持开启，手机保持连接。'}</span></li><li>${icon('check')}<span>${usb?'按系统提示允许 USB 访问。':c.platform==='ios'?'在 iPhone 设置中允许“本地网络”访问。':'按系统网络连接提示允许连接。'}</span></li><li>${icon('check')}<span>检查机身屏幕上是否有待确认的连接提示。</span></li>`}</ul>${denied&&c.platform==='ios'&&!usb?'<p class="subtle-state">返回 Huevia 后，点击“已开启，重新连接”。</p>':action('help','查看连接帮助'+icon('chevron'),'text-action')}</div>`;
      footer=denied&&c.platform==='ios'&&!usb?action('permission-settings','前往权限设置'+icon('external'),'primary')+action('connect','已开启，重新连接','text-action'):action('connect',icon('refresh')+'重新连接','primary')+action(usb?'detect-usb':'settings',usb?'重新检测 USB 设备':'检查连接设置','text-action');
    }
    return `<div class="topbar">${ib('back','back','返回上一页')}<span class="top-note">${usb?'USB':'Wi-Fi'}</span></div><main class="connection-main"><h1>连接相机</h1><p class="intro">${intro}</p>${transport()}${body}</main><div class="connection-footer">${footer}</div>${systemBottom()}`;
  }
  function phase(text,state){return `<div class="phase-row ${state}"><span class="phase-symbol">${state==='done'?icon('check'):state==='current'?'<span class="status-dot"></span>':''}</span>${text}</div>`}
  function gallery(){return `<div class="gallery-scroll"><div class="photo-toolbar"><span class="photo-count">${model.sourceTab==='camera'?'相机照片':'最近接收'}<small>128 张</small></span><div class="photo-actions">${action('raw',`RAW 原片 <span class="switch ${model.raw?'on':''}" aria-hidden="true"></span>`,'small-control',`aria-pressed="${model.raw}"`)}${action('photo-sort',icon('sort'),'small-control sort-control','aria-label="照片排序"')}${action('selection',model.selection?'取消':'选择','small-control')}</div></div><div class="photo-grid">${photos.map((photo,i)=>({photo,i})).sort((a,b)=>model.photoSort==='oldest'||model.photoSort==='nameAscending'?a.photo[1].localeCompare(b.photo[1],undefined,{numeric:true}):b.photo[1].localeCompare(a.photo[1],undefined,{numeric:true})).map(({photo:[src,name,alt],i})=>action('photo-'+i,`<img src="assets/${src}" alt="${alt}" loading="eager"><span class="photo-caption">${model.raw?name.replace('.JPG','.NEF'):name}</span>${model.selection?`<span class="selection-circle ${model.selected.has(i)?'checked':''}">${model.selected.has(i)?icon('check'):''}</span>`:''}`,'photo',`aria-label="${model.selection?'选择':'查看'} ${name}" ${model.selection?`aria-pressed="${model.selected.has(i)}"`:''}`)).join('')}</div></div>`}
  function sync(){
    const head=`<div class="browse-head"><div class="browse-heading"><h1>同步</h1>${action('camera-info',icon('camera')+`<span>${model.disconnected?'未连接':'Nikon Z f'}</span>${model.disconnected?'':'<span class="status-dot"></span>'}`,'camera-status','aria-label="查看相机连接状态"')}</div><p class="browse-subtitle">让相机与照片，在这里接上。</p>${model.disconnected?`<div class="camera-disconnected">${icon('warning')}<span>相机连接已断开<br>下载队列已保留</span>${action('go-connect','重新连接')}</div>`:''}<div class="source-tabs" role="tablist" aria-label="照片来源">${action('source-receive','拍摄接收',model.sourceTab==='receive'?'active':'',`role="tab" aria-selected="${model.sourceTab==='receive'}"`)}${action('source-camera','相机照片',model.sourceTab==='camera'?'active':'',`role="tab" aria-selected="${model.sourceTab==='camera'}"`)}</div></div>`;
    const content=model.loaded?gallery():`<div class="sync-empty">${icon('camera')}<h2>${model.disconnected?'连接相机，开始浏览':'相机已连接'}</h2><p>${model.disconnected?'通过 Wi-Fi 或 USB 连接相机，\n然后选择需要浏览的照片。':'Nikon Z f 已准备好。\n需要浏览时，再读取相机照片。'}</p>${action(model.disconnected?'go-connect':'browse',model.disconnected?'连接相机':'浏览相机照片','primary')}</div>`;
    return `<main class="browse-page">${head}${content}</main><div class="scroll-edge"></div>${tabs()}${model.panel==='closed'?action('open-tools',icon('tools')+(model.queue!=='empty'?'<span class="queue-count">6</span>':''),'dock-button glass','aria-label="相机工具" title="相机工具" aria-expanded="false" aria-controls="camera-tools"'):''}`;
  }
  function tabs(){return `<div class="tabbar-wrap"><nav class="bottom-tabs glass" aria-label="主导航">${[['presets','grid','预设'],['album','image','相册'],['sync','camera','同步'],['settings','settings','设置']].map(([name,symbol,label])=>action('nav-'+name,icon(symbol)+label,model.page===name?'active':'',model.page===name?'aria-current="page"':'')).join('')}</nav><div class="tabbar-home" aria-hidden="true"></div></div>`}
  function otherPage(){
    if(model.page==='presets')return `<main class="plain-page"><h1>预设</h1><p class="source-explanation">把喜欢的色彩，带到下一次拍摄。</p><div class="preset-list">${[['portrait-smile.jpg','柔和人像'],['sunlit-forest.jpg','林间日光'],['coastal-water.jpg','海岸清晨']].map(([src,name])=>action('preset-item',`<img src="assets/${src}" alt="${name}示例"><span><strong>${name}</strong><small>本地预设 · 演示内容</small></span>`,'preset-preview')).join('')}</div>${action('go-connect',icon('camera')+(model.disconnected?'连接相机，写入预设':'管理相机连接'),'primary')}</main>${tabs()}`;
    if(model.page==='album')return `<main class="browse-page"><div class="browse-head"><div class="browse-heading"><h1>相册</h1></div><p class="browse-subtitle">留在手机里的影像。</p></div>${gallery()}</main>${tabs()}`;
    return `<main class="plain-page"><h1>设置</h1><p class="source-explanation">按自己的习惯使用 Huevia。</p><div class="plain-settings">${['外观','照片与存储','连接与权限','关于 Huevia'].map(t=>action('settings-preview',t+icon('chevron'))).join('')}</div></main>${tabs()}`;
  }
  const panelTop=(title,back=false,extra='')=>`<div class="panel-top"><div class="panel-heading-left">${back?action('back-tools',icon('back'),'back-tool','aria-label="返回相机工具"'):''}<h2 id="panel-title">${title}${extra}</h2></div>${ib('close-panel','close','关闭面板')}</div>`;
  function panel(){
    const p=model.panel;if(p==='closed')return '';
    if(model.page==='remote')return window.HueviaRemoteView.overlay(model,{action,icon,ib});
    const dismiss=action('close-panel','','panel-dismiss','aria-label="收起面板" tabindex="-1"');
    if(p==='tools')return dismiss+`<section id="camera-tools" class="tools-panel glass" aria-labelledby="panel-title">${panelTop('相机工具')}${[['downloads','download','下载队列',model.queue==='empty'?'暂无进行中的下载':model.queue==='failed'?'连接中断 · 6 项待继续':model.paused?'已暂停 · 6 项':'正在下载 · 6 项'],['remote','camera','遥控拍照',model.disconnected?'连接相机后使用':'快门与拍摄参数'],['presets','grid','相机预设槽位','查看与写入 C1–C9']].map(([name,symbol,title,sub])=>action('panel-'+name,icon(symbol)+`<span><strong>${title}</strong><small>${sub}</small></span>`+icon('chevron','chevron'),'tool-row')).join('')}</section>`;
    if(p==='downloads')return dismiss+`<section class="sheet glass" aria-labelledby="panel-title">${panelTop('下载队列',true,`<span class="mini-count">${model.queue==='empty'?'0':'6'}</span>`)}${model.queue==='empty'?`<div class="empty-queue">${icon('download')}<div><strong>暂无下载任务</strong><p>选择相机照片后，即可加入队列。</p></div></div>`:`<div class="queue-summary"><span>${model.queue==='failed'?'等待重新连接':model.paused?'已暂停':'正在下载'}</span><span>2 / 6 项完成</span></div><div class="progress-track" role="progressbar" aria-label="下载进度" aria-valuenow="38" aria-valuemin="0" aria-valuemax="100"><span></span></div><div class="download-row"><img class="download-thumb" src="assets/alpine-lake.jpg" alt="正在下载的山间湖泊照片"><div class="download-info"><strong>DSC_4821.JPG</strong><p>${model.queue==='failed'?'下载未完成':'4.6 / 12.1 MB'}</p></div></div>${model.queue==='failed'?'<p class="queue-failed">连接中断，队列已保留。连接后可重试。</p>':'<p class="download-tail">其余 3 项等待下载</p>'}${action(model.queue==='failed'?'retry-downloads':'pause-downloads',icon(model.queue==='failed'?'refresh':model.paused?'play':'pause')+(model.queue==='failed'?'重新连接并重试':model.paused?'继续下载':'暂停全部'),'sheet-button')}`}</section>`;
    if(p==='presets')return dismiss+`<section class="sheet glass" aria-labelledby="panel-title">${panelTop('相机预设槽位',true)}<p class="preset-caption">选择一个槽位，读取内容或写入预设。<br>${model.disconnected?'相机未连接，连接后可继续。':'槽位内容尚未读取。'}</p><div class="slot-grid" role="group" aria-label="相机预设槽位 C1 至 C9">${Array.from({length:9},(_,i)=>'C'+(i+1)).map(s=>action('slot-'+s,`<strong>${s}</strong><small>未读取</small>`,`slot ${model.slot===s?'active':''}`,`aria-pressed="${model.slot===s}" aria-label="${s}，未读取"`)).join('')}</div><div class="slot-selection"><strong>已选择 ${model.slot}</strong><span>先选择，再操作</span></div><div class="slot-actions">${action('read-slot','读取此槽位','sheet-button',model.disconnected?'disabled':'')}${action('write-slot','写入预设','sheet-button emphasis',model.disconnected?'disabled':'')}</div>${model.disconnected?action('go-connect','连接相机','inline-connect'):''}<p class="sheet-annotation">写入前需再次核对目标槽位与覆盖内容。</p></section>`;
    if(p==='sort')return dismiss+`<section class="sheet glass" aria-labelledby="panel-title">${panelTop('照片排序')}<p class="preset-caption">排序已读取的照片，新页按当前规则插入。</p>${[['newest','拍摄时间 · 新到旧'],['oldest','拍摄时间 · 旧到新'],['nameAscending','名称 · 升序'],['nameDescending','名称 · 降序']].map(([value,label])=>action('sort-'+value,`<span>${label}</span>${model.photoSort===value?icon('check'):''}`,'sort-row',`aria-pressed="${model.photoSort===value}"`)).join('')}</section>`;
    if(p==='settings')return dismiss+`<section class="sheet settings-panel glass" aria-labelledby="panel-title">${panelTop('连接设置')}<p class="sheet-explanation">通常无需修改。仅在相机连接说明明确要求时调整地址。</p><label class="form-field">IP 地址<input name="host" inputmode="decimal" placeholder="例如 192.168.1.1" autocomplete="off"></label><label class="form-field">端口<input name="port" type="number" inputmode="numeric" value="15740" min="1" max="65535"></label>${action('save-settings','保存设置','primary')}<p class="sheet-annotation">此原型仅保存本次预览中的输入。</p></section>`;
    if(p==='brand')return dismiss+`<section class="sheet settings-panel glass" aria-labelledby="panel-title">${panelTop('相机类型')}${[['nikon','尼康','按相机的 Wi-Fi 连接提示操作'],['fuji','富士 X-T20','JPEG 浏览与下载']].map(([name,title,sub])=>action('brand-'+name,icon('camera')+`<span><strong>${title}</strong><small>${sub}</small></span>`+(model.brand===name?icon('check','end-icon'):''),'brand-option')).join('')}</section>`;
    if(p==='wifi-settings'||p==='permission-settings')return dismiss+`<section class="sheet settings-panel glass" aria-labelledby="panel-title">${panelTop(p==='wifi-settings'?'连接相机的 Wi-Fi':'开启本地网络访问')}<p class="sheet-explanation">${p==='wifi-settings'?(c.platform==='ios'?'打开 iPhone 的“设置” → “Wi-Fi”，选择相机网络并完成连接，然后返回 Huevia，点击“开始连接”。':'在系统 Wi-Fi 设置中选择相机网络，完成连接后返回 Huevia，点击“开始连接”。'):'在正式产品中，这里将打开系统允许的应用设置入口。开启 Huevia 的“本地网络”权限后，返回并重试。'}</p>${action('close-panel','返回预览','primary')}<p class="sheet-annotation">当前为独立原型，不会打开系统设置。</p></section>`;
    if(p==='camera-info')return dismiss+`<section class="sheet glass" aria-labelledby="panel-title">${panelTop('相机连接')}<p class="sheet-explanation">${model.disconnected?'当前没有连接相机。':'Nikon Z f · '+(model.transport==='usb'?'USB':'Wi-Fi')+' 连接'}<br>连接后，可按需要浏览照片或使用相机工具。</p>${action('go-connect',model.disconnected?'连接相机':'管理连接','primary')}${!model.disconnected?action('disconnect','断开相机','text-action'):''}</section>`;
    if(p==='write-slot'||p==='read-slot')return dismiss+`<section class="sheet glass" aria-labelledby="panel-title">${panelTop((p==='write-slot'?'写入':'读取')+' '+model.slot)}<p class="sheet-explanation">${p==='write-slot'?'下一步将选择本地预设，再核对相机与槽位。写入会覆盖目标槽位，需在确认后执行。':'下一步将从所选槽位读取相机预设。读取成功后，再展示真实名称与参数。'}</p>${action('panel-presets','返回槽位选择','primary')}<p class="sheet-annotation">仅演示操作路径，不读取或写入相机。</p></section>`;
    return dismiss+`<section class="sheet settings-panel glass" aria-labelledby="panel-title">${panelTop('连接帮助')}<p class="sheet-explanation">${model.transport==='usb'?'检查相机供电、数据线与转接头，按机身提示选择 USB 模式，并允许系统访问相机。':'确认手机连接的是相机网络，保持机身 Wi-Fi 界面开启；iPhone 需允许本地网络访问。'}<br><br>如果连接持续失败，可重新开启相机连接界面，再回到 Huevia 重试。</p>${action('close-panel','知道了','primary')}</section>`;
  }
  function render(){
    root.innerHTML=`<div class="screen ${c.platform} ${model.page==='remote'?'remote-mode':''}">${statusbar()}${model.page==='connection'?connection():model.page==='sync'?sync():model.page==='remote'?window.HueviaRemoteView.render(model,{action,icon,ib}):otherPage()}${panel()}${model.preview>=0?photoPreview():''}${model.toast?`<div class="toast ${model.successToast?'is-success':''}" role="status">${icon('check')}<span>${model.toast}</span></div>`:''}</div>`;
    if(model.page==='remote')window.HueviaRemoteView.drawHistogram(root);
  }
  function photoPreview(){const [src,name,alt]=photos[model.preview];return `<section class="photo-preview" aria-label="照片预览"><div class="topbar">${ib('close-photo','back','返回照片列表')}<strong>${name}</strong><span style="width:44px"></span></div><img src="assets/${src}" alt="${alt}"><div class="photo-foot">示例照片用于审核工具的遮挡与层级。<br>未读取或下载相机照片。</div></section>`}
  let toastTimer;
  function notify(text,success=false,persist=false){clearTimeout(toastTimer);model.toast=text;model.successToast=success;render();if(!persist)toastTimer=setTimeout(()=>{model.toast='';render()},2600)}
  function closePanel(){model.panel='closed';render();root.querySelector('[data-action="open-tools"]')?.focus({preventScroll:true})}
  function openPanel(name){model.panel=name;render();root.querySelector('.sheet .icon-button,.tools-panel .icon-button')?.focus({preventScroll:true})}
  function cancelFlow(){model.generation++;model.state='idle';model.panel='closed';model.remoteBusy=false}
  function finishConnection(persist=false){model.generation++;model.page=model.source;model.state='idle';model.panel='closed';model.disconnected=false;model.loaded=false;if(model.source==='remote')model.remoteLive='ready';notify('相机已连接',true,persist)}
  function beginConnection(){
    cancelFlow();const token=model.generation;
    model.state=model.transport==='usb'?'usbpermission':'connecting';render();
    if(model.transport==='usb')setTimeout(()=>{if(token!==model.generation)return;model.state='connecting';render()},900);
    setTimeout(()=>{if(token!==model.generation)return;model.state='confirm';render()},1700);
    setTimeout(()=>{if(token!==model.generation)return;finishConnection()},3900);
  }
  root.addEventListener('click',event=>{
    const target=event.target.closest('[data-action]');if(!target||target.disabled)return;
    const a=target.dataset.action;
    if(a.startsWith('transport-')){cancelFlow();model.transport=a.slice(10);model.state='idle';render();return}
    if(a==='connect'){beginConnection();return}
    if(a==='cancel-connect'){cancelFlow();render();return}
    if(a==='back'){cancelFlow();model.page=model.source;model.loaded=false;model.disconnected=true;render();return}
    if(a==='detect-usb'){cancelFlow();model.state='usbpermission';render();const token=model.generation;setTimeout(()=>{if(token!==model.generation)return;model.state='usbfound';render()},700);return}
    if(a==='usb-select'){notify('已选择 Nikon Z f');return}
    if(['settings','brand','wifi-settings','permission-settings','help','camera-info'].includes(a)){openPanel(a);return}
    if(a==='close-panel'){closePanel();return}
    if(a==='open-tools'||a==='back-tools'){openPanel('tools');return}
    if(a==='panel-remote'){model.panel='closed';model.page='remote';model.remoteLive='ready';render();return}
    if(a==='exit-remote'){cancelFlow();model.page='sync';model.remoteSent=false;model.focusSent=false;render();return}
    if(['remote-settings','remote-parameters','remote-recent','remote-review'].includes(a)){openPanel(a);return}
    if(a==='remote-grid'){model.remoteGrid=!model.remoteGrid;render();return}
    if(a==='remote-histogram'){model.remoteHistogram=!model.remoteHistogram;render();return}
    if(a==='remote-pause'||a==='remote-resume'||a==='remote-toggle-view'){model.remoteLive=a==='remote-pause'||(a==='remote-toggle-view'&&model.remoteLive==='ready')?'paused':'ready';render();return}
    if(a==='remote-toggle-transfer'){model.remoteTransfer=!model.remoteTransfer;render();return}
    if(a==='remote-acknowledge'){model.remoteCaptureUncertain=false;model.panel='closed';render();return}
    if(a==='remote-focus'||a==='focus-point'){if(model.disconnected||model.remoteBusy||model.remoteCaptureUncertain||model.remoteLive!=='ready')return;const b=target.getBoundingClientRect();model.focusPoint=a==='focus-point'?{x:Math.max(5,Math.min(95,(event.clientX-b.left)/b.width*100)),y:Math.max(5,Math.min(95,(event.clientY-b.top)/b.height*100))}:{x:50,y:50};model.focusSent=true;model.remoteSent=false;render();return}
    if(a.startsWith('panel-')){openPanel(a.slice(6));return}
    if(a.startsWith('brand-')){model.brand=a.slice(6);model.panel='closed';render();return}
    if(a==='save-settings'){
      const host=root.querySelector('[name=host]').value.trim(),port=Number(root.querySelector('[name=port]').value);
      if(!Number.isInteger(port)||port<1||port>65535){root.querySelector('[name=port]').reportValidity();return}
      model.host=host;model.port=port;model.panel='closed';notify('已保存本次预览的连接设置');return;
    }
    if(a==='go-connect'){cancelFlow();model.source=model.page==='remote'?'remote':model.page==='presets'?'presets':'sync';model.page='connection';model.toast='';render();return}
    if(a==='disconnect'){model.disconnected=true;model.panel='closed';notify('相机连接已断开');return}
    if(a==='browse'){model.loaded=true;model.toast='';render();return}
    if(a.startsWith('nav-')){cancelFlow();model.page=a.slice(4);model.selection=false;model.toast='';render();return}
    if(a==='photo-sort'){openPanel('sort');return}
    if(a.startsWith('sort-')){model.photoSort=a.slice(5);model.panel='closed';render();return}
    if(a==='raw'){model.raw=!model.raw;render();return}
    if(a==='selection'){model.selection=!model.selection;model.selected.clear();render();return}
    if(a.startsWith('source-')){model.sourceTab=a.slice(7)==='camera'?'camera':'receive';model.panel='closed';model.loaded=false;render();return}
    if(a.startsWith('photo-')){const i=Number(a.slice(6));if(model.selection){model.selected.has(i)?model.selected.delete(i):model.selected.add(i);render()}else{model.preview=i;model.panel='closed';render()}return}
    if(a==='close-photo'){model.preview=-1;render();return}
    if(a==='pause-downloads'){model.paused=!model.paused;render();return}
    if(a==='retry-downloads'){if(model.disconnected){model.source='sync';model.panel='closed';model.page='connection';model.state='idle';render()}else{model.queue='active';model.paused=false;render()}return}
    if(a==='shutter'){
      model.focusSent=false;
      model.remoteBusy=true;model.remoteSent=false;render();const token=model.generation;
      setTimeout(()=>{if(token!==model.generation)return;model.remoteBusy=false;model.remoteSent=true;render()},850);return;
    }
    if(a.startsWith('slot-')){model.slot=a.slice(5);render();return}
    if(a==='read-slot'||a==='write-slot'){openPanel(a);return}
    if(a==='preset-item'||a==='settings-preview'){notify('此处仅展示返回页面与导航关系');return}
  });
  document.addEventListener('keydown',event=>{if((event.key==='Enter'||event.key===' ')&&event.target.matches('[data-action=focus-point]')){event.preventDefault();model.focusPoint={x:50,y:50};model.focusSent=true;render();return}if(event.key==='Escape'){if(model.preview>=0){model.preview=-1;render()}else if(model.panel!=='closed')closePanel();else if(model.page==='connection'&&busy()){cancelFlow();render()}}});
  render();
  if(c.state==='success')finishConnection(true);
  window.__review={getState:()=>({...model,selected:[...model.selected]})};
})();
