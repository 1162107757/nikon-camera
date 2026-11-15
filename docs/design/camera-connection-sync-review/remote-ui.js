/* Fullscreen remote composition; all frames/parameters are synthetic local UI data. */
window.HueviaRemoteView = (() => {
  function render(m,ui){
    const {action,icon,ib}=ui;
    const state=m.remoteLive;
    const offline=m.disconnected;
    const pending=m.remoteCaptureUncertain;
    const imageVisible=!offline&&!['waiting','unsupported'].includes(state);
    const focused=m.focusPoint&&state==='ready';
    const values=offline?['—','—','—','—']:['1/250','f/4','400','0.0'];
    let overlay='';
    if(offline)overlay=`<div class="live-empty">${icon('network')}<h2>相机连接已断开</h2><p>重新连接后，再恢复取景。</p>${action('go-connect','重新连接相机','live-retry')}</div>`;
    else if(state==='waiting')overlay=`<div class="live-empty">${icon('camera')}<h2>等待相机画面</h2><p>连接仍保持，正在等待取景帧。</p>${action('remote-resume','重新获取画面','live-retry')}</div>`;
    else if(state==='unsupported')overlay=`<div class="live-empty">${icon('camera')}<h2>此相机未提供实时取景</h2><p>请使用机身取景。<br>遥控拍摄能力以机型为准。</p></div>`;
    else if(state==='paused')overlay=`<div class="live-pause"><span>取景已暂停</span>${action('remote-resume','恢复取景','live-retry')}</div>`;
    const status=offline?'连接后可继续拍摄':pending?'拍摄结果待核对，不会自动重拍':m.remoteBusy?'正在发送拍摄指令…':m.remoteSent?'已发送拍摄指令（演示）':m.focusSent?'已发送对焦指令（演示）':'参数请在机身调整';
    return `<main class="remote-page" aria-label="遥控拍照全屏取景"><header class="remote-header">${ib('exit-remote','back','返回同步，结束取景')}<h1>遥控拍照</h1>${ib('remote-parameters','info','查看机身参数')}</header><div class="remote-camera-line"><span><span class="status-dot ${offline?'offline':''}"></span>${offline?'未连接相机':'Nikon Z f'}<small>${m.transport==='usb'?'USB':'Wi-Fi'}</small></span><span>${icon('battery')} ${offline?'—':'78%'}</span></div><div class="remote-tool-row"><span>M · AF-S · 单张</span><div>${ib('remote-settings','tools','拍摄设置')}${action('remote-histogram',icon('histogram'),'icon-button '+(m.remoteHistogram?'active':''),`aria-label="显示或收起直方图" aria-pressed="${m.remoteHistogram}"`)}${action('remote-grid',icon('grid-lines'),'icon-button '+(m.remoteGrid?'active':''),`aria-label="显示或收起构图网格" aria-pressed="${m.remoteGrid}"`)}</div></div><section class="live-stage" aria-label="遥控取景画面"><span class="demo-frame-label">取景演示</span>${imageVisible?`<div class="live-image-wrap ${state==='paused'?'paused':''}" data-action="focus-point" role="button" tabindex="0" aria-label="点按取景画面发送对焦指令"><img id="remote-frame" src="assets/alpine-lake.jpg" alt="山间湖泊取景演示素材，不是真实相机画面">${m.remoteGrid?'<div class="thirds-grid" aria-hidden="true"><i></i><i></i><i></i><i></i></div>':''}${focused?`<span class="focus-reticle" style="left:${m.focusPoint.x}%;top:${m.focusPoint.y}%" aria-hidden="true"></span>`:''}</div>`:''}${overlay}${m.remoteHistogram&&imageVisible?`<div class="live-histogram" aria-label="示例照片的亮度直方图"><span>示例 · 亮度</span><canvas width="280" height="94"></canvas></div>`:''}${!offline&&state==='ready'?action('remote-pause',icon('pause')+'暂停','live-pause-button'):''}</section><section class="remote-capture-controls"><div class="remote-parameters">${['快门','光圈','ISO','曝光补偿'].map((label,i)=>`<div><strong>${values[i]}</strong><span>${label}</span></div>`).join('')}</div><div class="remote-feedback ${pending?'pending':''}" role="status"><span>${status}</span>${pending?action('remote-review','核对结果'+icon('chevron')):''}</div><div class="remote-actions">${action('remote-recent',`<span class="recent-thumb">${icon('image')}</span><span>最近拍摄</span>`,'remote-side-action')}${action('shutter','<span></span>','shutter remote-shutter',`aria-label="发送拍摄指令" ${offline||pending||m.remoteBusy?'disabled':''}`)}${action('remote-focus',icon('focus')+'<span>对焦</span>','remote-side-action',offline||m.remoteBusy||pending||state!=='ready'?'disabled':'')}</div><p class="remote-frame-note">${state==='paused'?'显示上次演示画面':'画面与参数均为本地演示'} · 不代表相机实测</p></section></main><div class="system-bottom" aria-hidden="true"></div>`;
  }
  function overlay(m,ui){
    const {action,icon,ib}=ui;
    const top=title=>`<div class="panel-top"><h2 id="panel-title">${title}</h2>${ib('close-panel','close','关闭面板')}</div>`;
    let title='',content='';
    if(m.panel==='remote-settings'){
      title='拍摄设置';content=`<div class="remote-setting-row"><span><strong>实时取景</strong><small>只控制当前遥控取景</small></span>${action('remote-toggle-view',`<span class="switch ${m.remoteLive==='ready'?'on':''}"></span>`,'remote-switch',`aria-label="切换实时取景" aria-pressed="${m.remoteLive==='ready'}" ${m.disconnected||m.remoteLive==='unsupported'?'disabled':''}`)}</div><div class="remote-setting-row"><span><strong>拍摄后传入 App</strong><small>只接收已核对的新 JPEG</small></span>${action('remote-toggle-transfer',`<span class="switch ${m.remoteTransfer?'on':''}"></span>`,'remote-switch',`aria-label="拍摄后传入 App" aria-pressed="${m.remoteTransfer}"`)}</div><p class="sheet-explanation">返回同步会结束取景，保留相机连接。参数在机身调整；原文件保留在相机。</p><p class="sheet-annotation">此原型只演示开关，不发送相机或传输请求。</p>`;
    } else if(m.panel==='remote-parameters'){
      title='机身当前参数';content=`<p class="sheet-explanation">参数只读，请在相机上调整。<br>未提供的项目显示“—”。</p><dl class="remote-detail-list">${[['机型','Nikon Z f'],['拍摄模式','M'],['快门','1/250'],['光圈','f/4'],['ISO','400'],['曝光补偿','0.0'],['对焦模式','AF-S'],['释放模式','单张']].map(([a,b])=>`<div><dt>${a}</dt><dd>${m.disconnected?'—':b}</dd></div>`).join('')}</dl><p class="sheet-annotation">以上为界面演示值。</p>`;
    } else if(m.panel==='remote-recent'){
      title='最近拍摄';content=`<div class="empty-queue">${icon('image')}<div><strong>尚无已核对的新照片</strong><p>拍摄后，先核对相机中的照片。</p></div></div><p class="sheet-annotation">发送快门指令不等于确认拍摄成功。</p>`;
    } else {
      title='核对拍摄结果';content=`<p class="sheet-explanation">上次快门结果尚未核对。为避免重复拍摄，不会自动重发快门。<br><br>请先在相机中核对最近照片，再确认继续。</p>${action('remote-acknowledge','已核对相机，恢复拍摄','primary')}<p class="sheet-annotation">此处仅演示异常恢复路径。</p>`;
    }
    return action('close-panel','','panel-dismiss','aria-label="收起面板" tabindex="-1"')+`<section class="sheet glass remote-overlay" aria-labelledby="panel-title">${top(title)}${content}</section>`;
  }
  function drawHistogram(root){
    const image=root.querySelector('#remote-frame'),canvas=root.querySelector('.live-histogram canvas');
    if(!image||!canvas)return;
    const draw=()=>{
      const sample=document.createElement('canvas');sample.width=128;sample.height=84;
      const sc=sample.getContext('2d',{willReadFrequently:true});sc.drawImage(image,0,0,128,84);
      const pixels=sc.getImageData(0,0,128,84).data,bins=Array(48).fill(0);
      for(let i=0;i<pixels.length;i+=4)bins[Math.min(47,Math.floor((pixels[i]*.2126+pixels[i+1]*.7152+pixels[i+2]*.0722)/256*48))]++;
      const cx=canvas.getContext('2d'),peak=Math.max(...bins);cx.clearRect(0,0,canvas.width,canvas.height);cx.fillStyle='#e1d9cd';
      bins.forEach((v,i)=>{const h=v/peak*canvas.height;cx.fillRect(i*canvas.width/48,canvas.height-h,canvas.width/48-.7,h)});
    };
    if(image.complete&&image.naturalWidth)draw();else image.addEventListener('load',draw,{once:true});
  }
  return {render,overlay,drawHistogram};
})();
