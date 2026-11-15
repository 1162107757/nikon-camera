(() => {
  const config = {surface:'connection', theme:'compare', transport:'wifi', state:'idle', source:'sync', panel:'closed', queue:'empty', remoteState:'ready', disconnected:false};
  const wifiStates = [['idle','未连接 · 准备步骤'],['connecting','连接中 · 检查网络'],['confirm','连接中 · 等待机身确认'],['permission','等待系统授权'],['denied','权限未允许 · 引导恢复'],['timeout','连接超时 · 可重试'],['failed','连接失败 · 可重试'],['success','连接成功 · 已返回来源页']];
  const usbStates = [['idle','未连接 · USB 准备'],['usbempty','未发现 USB 相机'],['usbfound','检测到设备 · 待连接'],['usbpermission','等待 USB 访问授权'],['confirm','连接中 · 等待机身确认'],['denied','USB 访问未允许'],['timeout','USB 连接超时'],['failed','USB 连接失败'],['success','连接成功 · 已返回来源页']];
  const notes = {
    connection:['先选连接方式，再做一件事','Wi-Fi 引导用户先连接相机网络；USB 独立呈现设备检测和授权。过程只呈现当前阶段，失败后保留连接方式。','点“开始连接”走完演示流程；可切换相机类型、打开连接设置，或用左侧固定查看异常状态。'],
    closed:['工具退到右下角，照片仍是主角','采用你选择的单个 52px 圆形工具按钮（方案 B）。没有任务时不显示 0 或空进度；有任务时只补充数量。仅在同步页出现。','点击手机里的“相机工具”；切换底部导航，检查工具是否随同步页一起收起。'],
    tools:['三个入口，读一眼就懂','下载队列、遥控拍照、相机预设槽位集中在一个 252px 宽的浮动面板。点外部或关闭收起；不会再叠一层工具菜单。','点击任一工具，面板就地替换为对应内容；空队列副文案保持一行。'],
    downloads:['空队列只占 176px，高度随内容变化','空状态没有大插画和空白占位。下载中显示当前文件、整体数量与暂停；连接中断保留队列并提供重试。','左侧切换下载状态；下载中可暂停 / 继续，中断时可重试，动作均为本地演示。'],
    remote:['独立全屏取景，画面先行','沿用原遥控摄影暗色界面。上方取景，下方参数和快门；保留网格、亮度直方图、点按对焦、最近拍摄与拍摄设置。画面为本地演示，不是真实相机。','点击取景区对焦，切换网格 / 直方图或暂停取景；左上角返回同步，保留连接。快门只在点击后短暂反馈。'],
    presets:['九个槽位，一屏看全','C1–C9 使用固定 3 × 3 网格。未读取状态直接写明，不把空槽位误报为可用预设；选择后再进入读取与写入的下一步。','点击任一槽位查看选择状态；“读取 / 写入”展示下一步说明，不会触发任何相机操作。']
  };
  function populateStates(){
    const list=config.transport==='usb'?usbStates:wifiStates;
    if(!list.some(x=>x[0]===config.state))config.state='idle';
    const el=document.querySelector('#connection-state');
    el.replaceChildren(...list.map(([value,label])=>{const o=document.createElement('option');o.value=value;o.textContent=label;return o}));el.value=config.state;
  }
  function render(){
    document.querySelector('#connection-options').hidden=config.surface!=='connection';
    document.querySelector('#sync-options').hidden=config.surface!=='sync';
    document.querySelector('#remote-options').hidden=config.panel!=='remote';
    for(const group of document.querySelectorAll('[data-control]')) for(const b of group.querySelectorAll('button')){const active=b.dataset.value===config[group.dataset.control];b.classList.toggle('selected',active);b.setAttribute('aria-pressed',active)}
    for(const platform of ['android','ios']){
      const theme=config.theme==='compare'?(platform==='android'?'light':'dark'):config.theme;
      const p=new URLSearchParams({...config,platform,theme});
      const url='screen.html?'+p.toString();
      document.querySelector('#'+platform+'-frame').src=url;
      document.querySelector('#'+platform+'-open').href=url;
      document.querySelector('#'+platform+'-theme').textContent=(config.surface==='sync'&&config.panel==='remote'?'摄影深色':theme==='dark'?'深色':'浅色')+' · 375 × 812';
    }
    const n=notes[config.surface==='connection'?'connection':config.panel];
    document.querySelector('#note-title').textContent=n[0];document.querySelector('#note-body').textContent=n[1];document.querySelector('#interaction-hint').textContent=n[2];
    const reviewUrl=new URL(location.href);for(const [k,v] of Object.entries(config))reviewUrl.searchParams.set(k,v);history.replaceState(null,'',reviewUrl);
  }
  const query=new URLSearchParams(location.search);
  for(const k of Object.keys(config)) if(query.has(k)) config[k]=k==='disconnected'?query.get(k)==='true':query.get(k);
  if(!['connection','sync'].includes(config.surface))config.surface='connection';
  if(!['light','dark','compare'].includes(config.theme))config.theme='compare';
  if(!['wifi','usb'].includes(config.transport))config.transport='wifi';
  if(!Object.keys(notes).includes(config.panel))config.panel='closed';
  populateStates();
  for(const k of ['source','panel','queue'])document.getElementById(k).value=config[k];document.querySelector('#disconnected').checked=config.disconnected;document.querySelector('#remote-state').value=config.remoteState;
  document.querySelectorAll('[data-control] button').forEach(b=>b.addEventListener('click',()=>{const key=b.closest('[data-control]').dataset.control;config[key]=b.dataset.value;if(key==='transport'){config.state='idle';populateStates()}render()}));
  for(const id of ['connection-state','source','panel','queue','disconnected','remote-state']) document.getElementById(id).addEventListener('change',e=>{config[id==='connection-state'?'state':id==='remote-state'?'remoteState':id]=id==='disconnected'?e.target.checked:e.target.value;render()});
  document.querySelector('#reset').addEventListener('click',render);
  render();
})();
