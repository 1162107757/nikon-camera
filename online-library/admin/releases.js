/** The host supplies its authenticated, CSRF-protected api.request function. */
export function mountReleases(container, { api, onError = () => {} } = {}) {
  if (typeof api?.request !== 'function') throw new Error('版本模块需要 api.request。');
  const request = api.request.bind(api), controller = new AbortController();
  const node = (tag, className = '', text = '') => { const value = document.createElement(tag); value.className = className; value.textContent = text; return value; };
  const button = (text, callback, className = 'button secondary') => { const value = node('button', className, text); value.type = 'button'; value.addEventListener('click', callback, { signal: controller.signal }); return value; };
  const formatSize = size => `${(size / 1048576).toFixed(2)} MiB`;
  const time = value => value ? new Date(value).toLocaleString('zh-CN', {hour12:false}) : '尚未上架';
  const statusLabels = {draft:'草稿', published:'已上架', withdrawn:'已撤回'};
  const platforms = {
    next: {label:'Android 新版', prefix:'/api/next/releases', extension:'apk', maxBytes:134217728, description:'最大 128 MiB。自动校验新版包名、版本、架构和签名。'},
    ios: {label:'iOS', prefix:'/api/ios/releases', extension:'ipa', maxBytes:134217728, description:'最大 128 MiB。接收未签名的 iPhoneOS ARM64 IPA，自动读取应用标识、版本和最低 iOS 版本。'},
    legacy: {label:'Android 原版', prefix:'/api/releases', extension:'apk', maxBytes:104857600, description:'最大 100 MiB。自动校验原版包名、版本和签名，更新渠道与新版独立。'},
  };
  let activePlatform = 'next', data = null, busy = false, destroyed = false, refreshSerial = 0;
  const shell = node('section', 'releases'), heading = node('div', 'page-heading'), headingCopy = node('div');
  headingCopy.append(node('h1', '', 'App 版本'), node('p', '', '分别管理 Android 与 iOS。上传后先保存草稿，确认上架后才开放下载。'));
  const uploadButton = button('上传新版本', () => { uploadForm.hidden = !uploadForm.hidden; if (!uploadForm.hidden) file.focus(); }, 'button');
  heading.append(headingCopy, uploadButton); shell.append(heading);
  const platformTabs = node('div', 'release-platforms');platformTabs.setAttribute('role','group');platformTabs.setAttribute('aria-label','应用平台');
  for (const [key, config] of Object.entries(platforms)) {
    const tab = button(config.label, () => {if(busy || activePlatform === key)return;activePlatform=key;uploadForm.reset();updatePlatform();refresh();}, 'release-platform');
    tab.dataset.releasePlatform=key;platformTabs.append(tab);
  }
  shell.append(platformTabs);
  const error = node('div', 'error-banner'); error.hidden = true; error.setAttribute('role', 'alert'); shell.append(error);
  const message = node('p', 'release-message'); message.setAttribute('role','status'); shell.append(message);
  const uploadForm = node('form', 'release-upload'); uploadForm.hidden = true;
  const fileField = node('div','field'), fileLabel = node('label'), file = node('input'), fileHint=node('small'); file.type='file';file.id='release-package';fileLabel.htmlFor=file.id;file.required=true;
  fileField.append(fileLabel,file,fileHint);
  const channelField = node('div','field'), channelLabel = node('label','','发布渠道'), channel = node('select'); channel.id='release-channel'; channelLabel.htmlFor=channel.id;
  for(const [value,label] of [['stable','正式版'],['beta','测试版']]){ const option=node('option','',label);option.value=value;channel.append(option); }
  channelField.append(channelLabel,channel);
  const notesField = node('div','field'), notesLabel=node('label','','更新说明'), notes=node('textarea'); notes.id='release-notes';notesLabel.htmlFor=notes.id;notes.required=true;notes.maxLength=6000;notes.rows=5;notes.placeholder='写下本次版本的改进，以及用户需要了解的变化。';notesField.append(notesLabel,notes);
  const submit=node('button','button','上传并校验');submit.type='submit'; const cancel=button('取消',()=>{uploadForm.hidden=true;},'button secondary');
  const formActions=node('div','release-actions');formActions.append(submit,cancel);uploadForm.append(fileField,channelField,notesField,formActions);shell.append(uploadForm);
  const toolbar=node('div','release-toolbar'), downloadLink=node('a','','打开下载页');downloadLink.target='_blank';downloadLink.rel='noopener';
  toolbar.append(node('p','muted','上架后的安装包不可覆盖。撤回会立即停止新的下载。'),downloadLink);shell.append(toolbar);
  const list=node('div','release-list'); shell.append(list);container.replaceChildren(shell);
  function report(err){if(destroyed)return;error.hidden=false;error.textContent=err.message||'操作未完成，请重试。';onError(err);}
  function updatePlatform(){
    const config=platforms[activePlatform];
    for(const tab of platformTabs.children)tab.setAttribute('aria-pressed',String(tab.dataset.releasePlatform===activePlatform));
    fileLabel.textContent=config.extension==='ipa'?'未签名 IPA':'已签名 APK';
    file.accept=config.extension==='ipa'?'.ipa':'.apk,application/vnd.android.package-archive';fileHint.textContent=config.description;
    const url=new URL('https://huevia.cc/');url.searchParams.set('platform',activePlatform==='ios'?'ios':'android');
    if(activePlatform!=='ios')url.searchParams.set('edition',activePlatform);downloadLink.href=url.href;
  }
  async function refresh(){
    const serial=++refreshSerial, config=platforms[activePlatform];
    error.hidden=true;message.textContent='正在读取版本…';
    list.replaceChildren();
    try{const result=await request(config.prefix);if(destroyed||serial!==refreshSerial)return;data=result;renderList();message.textContent='';}
    catch(err){if(destroyed||serial!==refreshSerial)return;message.textContent='';report(err);}
  }
  function renderList(){
    list.replaceChildren();
    const config=platforms[activePlatform];
    if(!data.items.length){const empty=node('div','empty-state');empty.append(node('h2','',`${config.label} 暂无版本`),node('p','','上传安装包后，先保存为草稿。只有经过确认上架的版本才会出现在下载页。'));list.append(empty);return;}
    for(const release of data.items){
      const row=node('article','release-row'),main=node('div','release-row-copy'),name=node('h2','',`Huevia ${release.versionName}`);
      const system=activePlatform==='ios'?`iOS ${release.minimumIOS}+ · 未签名 IPA`:`Android API ${release.minSdk}+`;
      const policy=activePlatform==='legacy'?` · ${release.mandatory?'强制更新':'普通更新'}`:'';
      const meta=node('p','muted',`${release.channel==='stable'?'正式版':'测试版'}${policy} · 构建 ${release.versionCode} · ${formatSize(release.byteLength)} · ${system}`);
      main.append(name,meta,node('p','release-row-time',release.status==='withdrawn'?`撤回于 ${time(release.withdrawnAt)}`:`上架时间 ${time(release.publishedAt)}`));
      const status=node('span',`status ${release.status==='published'?'published':''}`,statusLabels[release.status]);
      row.append(main,status,button('查看版本',()=>openRelease(release,config),'row-edit'));list.append(row);
    }
  }
  uploadForm.addEventListener('submit',async event=>{
    event.preventDefault();if(busy)return; const apk=file.files[0], config=platforms[activePlatform];
    if(!apk||!apk.name.toLowerCase().endsWith('.'+config.extension)||apk.size<1||apk.size>config.maxBytes){report(new Error(`请选择不超过 ${config.maxBytes/1048576} MiB 的 ${config.extension.toUpperCase()}。`));return;}
    if(!notes.value.trim()){notes.focus();return;}
    busy=true;submit.disabled=true;uploadButton.disabled=true;cancel.disabled=true;error.hidden=true;
    for(const input of [file,channel,notes,...platformTabs.children])input.disabled=true;
    try{
      const task=await request(config.prefix+'/uploads',{method:'POST',body:{byteLength:apk.size,channel:channel.value,notes:notes.value.trim()}});
      for(let offset=0,index=0;offset<apk.size;offset+=task.chunkBytes,index++){
        if(destroyed)return;
        message.textContent=`正在上传 ${Math.floor(offset/apk.size*100)}%…`;
        await request(`${config.prefix}/uploads/${task.uploadId}/chunks/${index}`,{method:'PUT',raw:true,type:'application/octet-stream',body:apk.slice(offset,offset+task.chunkBytes)});
      }
      if(destroyed)return;message.textContent=config.extension==='ipa'?'正在校验 IPA 应用标识、版本与完整性…':'正在校验 APK 签名、版本与完整性…';
      const result=await request(`${config.prefix}/uploads/${task.uploadId}/complete`,{method:'POST',body:{}});
      if(destroyed)return;uploadForm.reset();uploadForm.hidden=true;await refresh();if(destroyed)return;openRelease(result.release,config);message.textContent=`${config.extension.toUpperCase()} 已校验并保存为草稿。`;
    }catch(err){message.textContent='';report(err);}finally{busy=false;submit.disabled=false;uploadButton.disabled=false;cancel.disabled=false;for(const input of [file,channel,notes,...platformTabs.children])input.disabled=false;}
  },{signal:controller.signal});
  function openRelease(initial,config){
    let release=initial;
    const legacy=config===platforms.legacy, ios=config===platforms.ios;
    const dialog=node('dialog','release-dialog'),title=node('h2','',`Huevia ${release.versionName}`),close=button('关闭',()=>dialog.close(),'button quiet');
    title.id=`release-title-${release.id}`;dialog.setAttribute('aria-labelledby',title.id);
    const header=node('div','release-dialog-heading');header.append(title,close);dialog.append(header);
    const status=node('p','release-dialog-status',`${config.label} · ${release.channel==='stable'?'正式版':'测试版'} · ${statusLabels[release.status]}`);dialog.append(status);
    const details=node('dl','release-facts');
    const facts=ios?[['应用标识',release.bundleId],['构建版本',release.versionCode],['最低 iOS',release.minimumIOS],['文件类型','未签名 IPA · 用户自行签名后安装']]:[['包名',release.packageName],['构建版本',release.versionCode],['最低 Android',`API ${release.minSdk}`],['签名 SHA-256',release.signerSha256]];
    facts.push(['大小',`${formatSize(release.byteLength)}（${release.byteLength.toLocaleString()} 字节）`],['SHA-256',release.sha256]);
    for(const [label,value] of facts)details.append(node('dt','',label),node('dd','',String(value)));
    dialog.append(details);
    const draftNotes=node('textarea');draftNotes.value=release.notes;draftNotes.maxLength=6000;draftNotes.rows=5;draftNotes.disabled=!legacy||release.status!=='draft';draftNotes.id=`notes-${release.id}`;
    const field=node('div','field'),label=node('label','','更新说明');label.htmlFor=draftNotes.id;field.append(label,draftNotes);dialog.append(field);
    const policyField=node('div','field'),policyLabel=node('label','','更新方式'),policy=node('select');
    policy.id=`policy-${release.id}`;policyLabel.htmlFor=policy.id;policy.disabled=release.status==='withdrawn';
    for(const [value,text] of [['optional','普通更新'],['mandatory','强制更新']]){const option=node('option','',text);option.value=value;policy.append(option);}
    policy.value=release.mandatory?'mandatory':'optional';
    policyField.append(policyLabel,policy,node('small','','普通更新可稍后；强制更新要求旧版用户更新后继续。已上架版本可随时改回普通更新，下次检查生效。'));if(legacy)dialog.append(policyField);
    const dialogError=node('p','field-error');dialogError.setAttribute('role','alert');dialog.append(dialogError);
    const actions=node('div','release-actions');dialog.append(actions);
    const confirmArea=node('div','release-confirm');confirmArea.hidden=true;dialog.append(confirmArea);
    async function run(action,body){
      dialogError.textContent='';for(const item of dialog.querySelectorAll('button'))item.disabled=true;
      try{const result=await request(`${config.prefix}/${release.id}${action==='edit'?'':`/${action}`}`,{method:['edit','policy'].includes(action)?'PUT':'POST',body:{expectedRevision:release.revision,...body}});if(destroyed)return;release=result.release;await refresh();dialog.close();if(!destroyed)openRelease(release,config);}
      catch(err){dialogError.textContent=err.message;onError(err);for(const item of dialog.querySelectorAll('button'))item.disabled=false;}
    }
    function showConfirmation(action){
      if(action==='publish'&&draftNotes.value!==release.notes){dialogError.textContent='更新说明尚未保存，请先保存草稿。';return;}
      if(legacy&&action==='publish'&&(policy.value==='mandatory')!==(release.mandatory===true)){dialogError.textContent='更新方式尚未保存，请先保存更新方式。';return;}
      const mandatory=policy.value==='mandatory';
      confirmArea.hidden=false;confirmArea.replaceChildren();
      const text=action==='policy'?(mandatory?`将 ${release.versionName} 设为强制更新。同渠道、同包名且系统兼容的旧版用户，下次检查后需更新才能继续。`:`将 ${release.versionName} 改为普通更新。用户下次检查后可选择稍后更新。`):action==='publish'?`即将上架 ${config.label} ${release.channel==='stable'?'正式版':'测试版'} ${release.versionName}（${release.versionCode}）。${ios?'下载页将提供 IPA 文件，由用户自行签名后安装。':'请确认安装包和更新说明无误。'}`:`撤回后，这个版本立即停止新的下载。修复时需上传更高构建版本，不会自动回退旧版本。`;
      confirmArea.append(node('p','',text));const checkLabel=node('label','release-check'),check=node('input');check.type='checkbox';checkLabel.append(check,document.createTextNode(action==='policy'?'我确认调整这个版本的更新方式':action==='publish'?'我已复核这个版本的信息':'我确认撤回这个版本'));confirmArea.append(checkLabel);
      const confirmation=action==='policy'?`${mandatory?'REQUIRE':'OPTIONAL'} ${release.versionCode} ${release.sha256}`:action==='publish'?`PUBLISH ${release.versionCode} ${release.sha256}`:`WITHDRAW ${release.versionCode}${legacy?'':` ${release.sha256}`}`;
      const confirm=button(action==='policy'?'确认保存':action==='publish'?'确认上架':'确认撤回',()=>run(action,{confirmation,...(action==='policy'?{mandatory}:{})}),action==='withdraw'?'button danger':'button');confirm.disabled=true;
      check.addEventListener('change',()=>{confirm.disabled=!check.checked;},{signal:controller.signal});confirmArea.append(confirm);check.focus();
    }
    if(release.status==='draft'){if(legacy)actions.append(button('保存说明',()=>run('edit',{notes:draftNotes.value.trim()}),'button secondary'));actions.append(button('上架版本',()=>showConfirmation('publish'),'button'));}
    if(release.status==='published')actions.append(button('撤回版本',()=>showConfirmation('withdraw'),'button danger'));
    if(legacy&&['draft','published'].includes(release.status))actions.append(button('保存更新方式',()=>showConfirmation('policy'),'button secondary'));
    const audit=node('details','release-audit');audit.append(node('summary','','操作记录'));const auditBody=node('div');audit.append(auditBody);dialog.append(audit);
    audit.addEventListener('toggle',async()=>{if(!audit.open||auditBody.childNodes.length)return;auditBody.textContent='正在读取…';try{const result=await request(`${config.prefix}/${release.id}/audit`);auditBody.replaceChildren();for(const item of result.items)auditBody.append(node('p','',`${time(item.created_at)} · ${item.actor} · ${{upload_verified:'上传并校验',edit:'保存说明',publish:'上架',withdraw:'撤回',policy:item.details?.mandatory?'设为强制更新':'设为普通更新'}[item.action]||item.action}`));}catch(err){auditBody.textContent=err.message;}},{signal:controller.signal});
    dialog.addEventListener('close',()=>dialog.remove(),{once:true});shell.append(dialog);dialog.showModal();close.focus();
  }
  updatePlatform();refresh();
  return {refresh,destroy(){destroyed=true;controller.abort();for(const dialog of shell.querySelectorAll('dialog'))dialog.close();shell.remove();}};
}
