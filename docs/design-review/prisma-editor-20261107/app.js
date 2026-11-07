/* Interactive visual prototype. CSS colour effects are illustrative, not Nikon/Prisma rendering. */
const $ = (root, selector) => root.querySelector(selector);
const $$ = (root, selector) => [...root.querySelectorAll(selector)];
const icon = name => `<svg class="ico" aria-hidden="true"><use href="#i-${name}"></use></svg>`;
const clone = value => JSON.parse(JSON.stringify(value));
const PHOTO = window.PROTOTYPE_PHOTO;
const looks = [
  {id:'original',name:'原图',group:'portrait',b:1,c:1,s:1,w:0,h:0},
  {id:'sunny',name:'晴日',group:'portrait',b:1.05,c:1.1,s:1.25,w:.10,h:-2},
  {id:'film',name:'旧时光',group:'film',b:1.03,c:.89,s:.78,w:.22,h:-5},
  {id:'airy',name:'柔光',group:'portrait',b:1.12,c:.91,s:.82,w:.05,h:0},
  {id:'forest',name:'森野',group:'film',b:.98,c:1.12,s:1.17,w:.09,h:-12},
  {id:'mono',name:'银盐',group:'mono',b:1.02,c:1.22,s:0,w:0,h:0},
  {id:'noir',name:'黑白电影',group:'mono',b:.99,c:1.42,s:0,w:0,h:0},
  {id:'dusk',name:'暮色',group:'film',b:.96,c:1.09,s:.86,w:.23,h:-8},
];
const tools = [ ['filters','filter','滤镜'],['adjust','adjust','调节'],['crop','crop','裁切'],['portrait','person','人像'],['frame','frame','边框'] ];
const parameters = [ ['exposure','sun','曝光'],['contrast','contrast','对比度'],['saturation','droplet','饱和度'],['warmth','temp','色温'] ];
const sourceImage = new Image();
sourceImage.src = PHOTO;
const imageReady = sourceImage.decode();

function baseState(tool) {
  return {tool,look:'sunny',strength:70,category:'all',parameter:'exposure',exposure:tool==='adjust'?12:0,contrast:0,saturation:0,warmth:0,ratio:.8,rotation:0,flip:false,frame:'none',portrait:'natural',portraitStrength:30,compare:tool==='adjust',seam:50,preview:false};
}
function effect(s) {
  const l=looks.find(l=>l.id===s.look), t=s.strength/100;
  const mix=x=>1+(x-1)*t;
  let b=mix(l.b)*(1+s.exposure*.003), c=mix(l.c)*(1+s.contrast*.004), sat=mix(l.s)*(1+s.saturation*.008);
  let sepia=l.w*t+Math.max(0,s.warmth)*.003, hue=l.h*t-s.warmth*.10;
  if(s.portrait==='bright') b*=1+s.portraitStrength*.0015;
  if(s.portrait==='warm') sepia+=s.portraitStrength*.002;
  return `brightness(${b}) contrast(${c}) saturate(${sat}) sepia(${Math.min(.8,sepia)}) hue-rotate(${hue}deg)`;
}
function filterFor(look) { return effect({...baseState('filters'),look:look.id,strength:100}); }
function number(value) { return value>0?'+'+value:String(value); }
function rangeMarkup({value=70,min=0,max=100,label,kind}) {
  return `<input class="slider" type="range" min="${min}" max="${max}" value="${value}" style="--pct:${(value-min)/(max-min)*100}%" aria-label="${label}" data-range="${kind}">`;
}
function geometry(s) {
  const rotated=document.createElement('canvas'), context=rotated.getContext('2d');
  const swapped=s.rotation%180!==0;
  rotated.width=swapped?sourceImage.naturalHeight:sourceImage.naturalWidth;
  rotated.height=swapped?sourceImage.naturalWidth:sourceImage.naturalHeight;
  context.translate(rotated.width/2,rotated.height/2);
  context.rotate(s.rotation*Math.PI/180);
  context.scale(s.flip?-1:1,1);
  context.drawImage(sourceImage,-sourceImage.naturalWidth/2,-sourceImage.naturalHeight/2);
  const target=document.createElement('canvas');
  target.width=Math.round(Math.min(rotated.width,rotated.height*s.ratio));
  target.height=Math.round(target.width/s.ratio);
  const targetContext=target.getContext('2d');
  targetContext.drawImage(rotated,(rotated.width-target.width)/2,(rotated.height-target.height)/2,target.width,target.height,0,0,target.width,target.height);
  return target;
}

class Editor {
  constructor(element) {
    this.el=element; this.s=baseState(element.dataset.initial); this.past=[]; this.future=[]; this.pending=null;
    this.id='editor-'+element.dataset.initial;
    element.style.setProperty('--photo',`url("${PHOTO}")`);
    element.innerHTML=`
      <div class="status-bar" aria-hidden="true"><span>9:41</span><span class="status-icons">${icon('signal')}${icon('battery')}</span></div>
      <header class="top-bar"><button class="icon-button" data-action="close" aria-label="退出编辑，查看照片">${icon('close')}</button><div class="photo-title"><strong>DSC_0728.JPG</strong><small>编辑照片</small></div><button class="export-button" data-action="export">导出</button></header>
      <div class="photo-stage"><div class="photo-wrap"><img class="after-photo" src="${PHOTO}" alt="湖畔人像示意照片，当前编辑效果" draggable="false"><img class="before-photo" src="${PHOTO}" alt="" draggable="false"><div class="crop-grid" aria-hidden="true"><i class="crop-corner"></i><i class="crop-corner"></i><i class="crop-corner"></i><i class="crop-corner"></i></div><div class="comparison-labels"><span>原图</span><span>效果</span></div><div class="compare-line"><span class="seam-handle">‹ ›</span></div><input class="compare-input" type="range" min="0" max="100" value="50" aria-label="原图与效果对比分割位置"></div><button class="icon-button compare-toggle" data-action="compare" aria-label="对比原图" title="点击切换原图对比，可拖动分割线" aria-pressed="false">${icon('compare')}</button></div>
      <div class="history-bar"><div class="history-actions"><button data-action="undo" aria-label="撤销" title="撤销" disabled>${icon('undo')}</button><button data-action="redo" aria-label="重做" title="重做" disabled>${icon('redo')}</button></div><span class="effect-name"></span><button class="icon-button reset-button" data-action="reset" aria-label="重置编辑" title="重置编辑">${icon('reset')}</button></div>
      <nav class="tool-nav" role="tablist" aria-label="编辑工具">${tools.map(([key,name,label])=>`<button class="tool" id="${this.id}-${key}" role="tab" aria-selected="false" aria-controls="${this.id}-panel" data-tool="${key}"><span class="tool-circle">${icon(name)}</span><span>${label}</span></button>`).join('')}</nav>
      <div class="workspace" id="${this.id}-panel" role="tabpanel"></div><div class="home-space" aria-hidden="true"><div class="home-indicator"></div></div><div class="snackbar" role="status" aria-live="polite"></div>`;
    element.addEventListener('click',e=>this.click(e));
    element.addEventListener('input',e=>this.input(e));
    element.addEventListener('change',e=>{if(e.target.dataset.range) this.commit();});
    $(element,'.tool-nav').addEventListener('keydown',e=>{
      if(!['ArrowRight','ArrowLeft','Home','End'].includes(e.key))return;
      e.preventDefault();
      const current=tools.findIndex(t=>t[0]===this.s.tool);
      const next=e.key==='Home'?0:e.key==='End'?tools.length-1:(current+(e.key==='ArrowRight'?1:-1)+tools.length)%tools.length;
      this.commit();this.s.tool=tools[next][0];this.render();$(element,`[data-tool=${this.s.tool}]`).focus();
    });
    const seam=$(element,'.compare-input');
    seam.addEventListener('input',()=>{this.s.seam=+seam.value;this.updateComparison();});
    new ResizeObserver(()=>this.fit()).observe($(element,'.photo-stage'));
    imageReady.then(()=>{this.refreshGeometry();this.render();}).catch(()=>this.message('示意照片载入失败，请重新打开原型。'));
    this.render();
  }
  remember(){this.past.push(clone(this.s));if(this.past.length>40)this.past.shift();this.future=[];}
  change(update){this.remember();Object.assign(this.s,update);this.render();}
  commit(){if(this.pending){this.past.push(this.pending);this.pending=null;this.future=[];this.updateHistory();}}
  render(){
    this.el.classList.toggle('crop-mode',this.s.tool==='crop'&&!this.s.compare&&!this.s.preview);
    this.el.classList.toggle('preview-only',this.s.preview);
    $$(this.el,'[data-tool]').forEach(b=>{b.setAttribute('aria-selected',String(b.dataset.tool===this.s.tool));b.tabIndex=b.dataset.tool===this.s.tool?0:-1;});
    $(this.el,'.workspace').setAttribute('aria-labelledby',this.id+'-'+this.s.tool);
    $(this.el,'.tool-nav').style.visibility=this.s.preview?'hidden':'';
    $(this.el,'.photo-title small').textContent=this.s.preview?'照片预览':'编辑照片';
    $(this.el,'[data-action=close]').setAttribute('aria-label',this.s.preview?'返回编辑':'退出编辑，查看照片');
    this.renderPanel();this.updateVisual();this.fit();
  }
  renderPanel(){
    const s=this.s, workspace=$(this.el,'.workspace');
    if(s.preview){workspace.innerHTML='<section style="align-items:center;justify-content:center"><button class="export-button" data-action="continue">继续编辑</button></section>';return;}
    if(s.tool==='filters') {
      const categories=[['all','精选'],['film','胶片'],['portrait','人像'],['mono','黑白']];
      const selected=s.category==='all'?looks.slice(0,6):looks.filter(l=>l.group===s.category);
      workspace.innerHTML=`<section aria-label="滤镜选项"><div class="category-row">${categories.map(([id,name])=>`<button data-category="${id}" aria-pressed="${id===s.category}">${name}</button>`).join('')}</div><div class="filter-rail" aria-label="滤镜列表">${selected.map(l=>`<button class="filter-card ${l.id===s.look?'selected':''}" data-look="${l.id}" aria-label="${l.name}滤镜" aria-pressed="${l.id===s.look}"><img src="${PHOTO}" alt="" style="filter:${filterFor(l)}">${icon('check').replace('class="ico"','class="ico selected-check"')}<span>${l.name}</span></button>`).join('')}</div><label class="strength-row"><span>强度</span>${rangeMarkup({value:s.strength,label:'滤镜强度',kind:'strength'})}<output class="value">${s.strength}</output></label></section>`;
    }else if(s.tool==='adjust') {
      const parameter=parameters.find(p=>p[0]===s.parameter);
      workspace.innerHTML=`<section aria-label="照片调节"><div class="adjust-head"><strong>${parameter[2]}</strong><output>${number(s[s.parameter])}</output></div><div class="adjust-slider">${rangeMarkup({value:s[s.parameter],min:-100,max:100,label:parameter[2],kind:s.parameter})}</div><div class="parameter-rail">${parameters.map(([key,name,label])=>`<button class="parameter" data-parameter="${key}" aria-pressed="${key===s.parameter}">${icon(name)}<span>${label}</span></button>`).join('')}</div><p class="panel-note">双击参数图标，恢复此项。</p></section>`;
      $$(workspace,'[data-parameter]').forEach(b=>b.addEventListener('dblclick',()=>this.change({[b.dataset.parameter]:0})));
    }else if(s.tool==='crop') {
      const ratios=[['.8','原比例'],['1','1:1'],['.666667','2:3'],['1.5','3:2'],['.5625','9:16']];
      workspace.innerHTML=`<section aria-label="裁切构图"><div class="crop-ratios">${ratios.map(([ratio,label])=>`<button class="ratio-button" data-ratio="${ratio}" aria-pressed="${Math.abs(+ratio-s.ratio)<.001}"><i class="ratio-shape"></i><span>${label}</span></button>`).join('')}</div><div class="crop-options"><button class="text-tool" data-action="rotate">${icon('rotate')}<span>旋转 90°</span></button><button class="text-tool" data-action="flip">${icon('flip')}<span>水平翻转</span></button><button class="text-tool" data-action="resetCrop">${icon('reset')}<span>重置</span></button></div><p class="crop-help">切换比例，预览居中裁切效果</p></section>`;
    }else if(s.tool==='portrait') {
      workspace.innerHTML=`<section aria-label="人像色彩示意"><div class="simple-options">${[['natural','自然'],['bright','明亮'],['warm','暖肤']].map(([id,label])=>`<button class="option-button" data-portrait="${id}" aria-pressed="${id===s.portrait}">${label}</button>`).join('')}</div><div class="portrait-label"><span>色彩强度</span><output>${s.portraitStrength}</output></div><div class="simple-slider">${rangeMarkup({value:s.portraitStrength,label:'人像色彩强度',kind:'portraitStrength'})}</div><p class="panel-note">仅示意色彩变化，未接入人像精修。</p></section>`;
    }else if(s.tool==='frame') {
      workspace.innerHTML=`<section aria-label="照片边框"><div class="simple-options">${[['none','无边框'],['white','留白'],['black','黑框']].map(([id,label])=>`<button class="option-button" data-frame="${id}" aria-pressed="${id===s.frame}">${label}</button>`).join('')}</div><p class="panel-note">边框随导出保留；示意宽度为照片短边的 5%。</p></section>`;
    }
  }
  updateVisual(){
    $(this.el,'.after-photo').style.filter=effect(this.s);
    const look=looks.find(l=>l.id===this.s.look);
    $(this.el,'.effect-name').textContent=this.s.look==='original'?'原图':`${look.name} · ${this.s.strength}%`;
    this.updateComparison();this.updateHistory();
  }
  updateComparison(){
    const wrap=$(this.el,'.photo-wrap');wrap.classList.toggle('compare-on',this.s.compare);
    $(this.el,'.before-photo').style.clipPath=`inset(0 ${100-this.s.seam}% 0 0)`;
    $(this.el,'.compare-line').style.left=this.s.seam+'%';
    $(this.el,'.compare-input').value=this.s.seam;
    $(this.el,'[data-action=compare]').setAttribute('aria-pressed',String(this.s.compare));
    this.el.classList.toggle('crop-mode',this.s.tool==='crop'&&!this.s.compare&&!this.s.preview);
  }
  updateHistory(){
    $(this.el,'[data-action=undo]').disabled=!this.past.length;
    $(this.el,'[data-action=redo]').disabled=!this.future.length;
  }
  refreshGeometry(){
    if(!sourceImage.complete||!sourceImage.naturalWidth)return;
    this.baseCanvas=geometry(this.s);
    const uri=this.baseCanvas.toDataURL('image/jpeg',.96);
    $$(this.el,'.photo-wrap img').forEach(img=>img.src=uri);
    const pad=this.s.frame==='none'?0:5;
    $(this.el,'.photo-wrap').style.background=this.s.frame==='white'?'#fff':'#0c0c0c';
    $$(this.el,'.photo-wrap img').forEach(img=>{img.style.padding=pad+'%';img.style.background='transparent';});
    this.fit();
  }
  fit(){
    const stage=$(this.el,'.photo-stage'), wrap=$(this.el,'.photo-wrap');
    const width=Math.min(stage.clientWidth,stage.clientHeight*this.s.ratio);
    wrap.style.width=width+'px';wrap.style.height=(width/this.s.ratio)+'px';
  }
  input(event){
    const key=event.target.dataset.range;if(!key)return;
    if(!this.pending)this.pending=clone(this.s);
    this.s[key]=+event.target.value;
    const min=+event.target.min,max=+event.target.max;
    event.target.style.setProperty('--pct',(this.s[key]-min)/(max-min)*100+'%');
    const output=$(this.el,'.workspace output');if(output)output.textContent=parameters.some(p=>p[0]===key)?number(this.s[key]):this.s[key];
    this.updateVisual();
  }
  click(event){
    const button=event.target.closest('button');if(!button)return;
    const d=button.dataset;
    if(d.tool){this.commit();this.s.tool=d.tool;this.s.preview=false;this.render();return;}
    if(d.look){this.change({look:d.look});return;}
    if(d.category){this.s.category=d.category;this.renderPanel();return;}
    if(d.parameter){this.s.parameter=d.parameter;this.renderPanel();return;}
    if(d.ratio){this.change({ratio:+d.ratio,compare:false});this.refreshGeometry();return;}
    if(d.frame){this.change({frame:d.frame});this.refreshGeometry();return;}
    if(d.portrait){this.change({portrait:d.portrait});return;}
    switch(d.action){
      case 'compare': this.s.compare=!this.s.compare;this.updateComparison();break;
      case 'undo': this.commit();if(this.past.length){this.future.push(clone(this.s));this.s=this.past.pop();this.refreshGeometry();this.render();}break;
      case 'redo': if(this.future.length){this.past.push(clone(this.s));this.s=this.future.pop();this.refreshGeometry();this.render();}break;
      case 'reset': this.remember();this.s=baseState(this.s.tool);this.s.exposure=0;this.s.compare=false;this.s.look='original';this.refreshGeometry();this.render();this.message('已恢复原图，可撤销');break;
      case 'rotate': this.change({rotation:(this.s.rotation+90)%360});this.refreshGeometry();break;
      case 'flip': this.change({flip:!this.s.flip});this.refreshGeometry();break;
      case 'resetCrop': this.change({ratio:.8,rotation:0,flip:false});this.refreshGeometry();break;
      case 'close': this.s.preview=!this.s.preview;this.render();break;
      case 'continue': this.s.preview=false;this.render();break;
      case 'export': this.export();break;
    }
  }
  message(text){
    const el=$(this.el,'.snackbar');el.textContent=text;el.classList.add('visible');clearTimeout(this.timer);
    this.timer=setTimeout(()=>el.classList.remove('visible'),3200);
  }
  async export(){
    const button=$(this.el,'[data-action=export]');button.disabled=true;button.textContent='导出中';
    try{
      await imageReady;
      const canvas=geometry(this.s), out=document.createElement('canvas');
      out.width=canvas.width;out.height=canvas.height;
      const context=out.getContext('2d');
      context.fillStyle=this.s.frame==='white'?'#fff':'#0c0c0c';context.fillRect(0,0,out.width,out.height);
      context.filter=effect(this.s);
      const pad=this.s.frame==='none'?0:Math.round(Math.min(out.width,out.height)*.05);
      context.drawImage(canvas,pad,pad,out.width-pad*2,out.height-pad*2);
      const blob=await new Promise((resolve,reject)=>out.toBlob(b=>b?resolve(b):reject(new Error('encode')),'image/jpeg',.94));
      const url=URL.createObjectURL(blob), link=document.createElement('a');
      link.href=url;link.download='Huevia_编辑原型_'+Date.now()+'.jpg';document.body.append(link);link.click();link.remove();
      setTimeout(()=>URL.revokeObjectURL(url),30000);this.message('示意 JPEG 已导出为新文件');
    }catch{this.message('导出失败，请重试或重新打开原型。');}
    finally{button.disabled=false;button.textContent='导出';}
  }
}
const editors=$$(document,'.editor').map(el=>new Editor(el));
$$(document,'[data-view]').forEach(button=>button.addEventListener('click',()=>{
  document.body.classList.toggle('single-view',button.dataset.view==='single');
  $$(document,'[data-view]').forEach(b=>{b.classList.toggle('selected',b===button);b.setAttribute('aria-pressed',String(b===button));});
  editors.forEach(e=>e.fit());
}));
