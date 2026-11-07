package cc.huevia.ui;

import android.app.*;
import android.content.res.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import cc.huevia.ncp.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** Photo-local tentative workspace. Both input and renderer output are EXIF-oriented, pre-crop. */
public final class PhotoLocalEditDialog extends Dialog {
    /** Returns a fresh owned bitmap; the dialog releases it when replaced or dismissed. */
    public interface Renderer { Bitmap render(PhotoLocalEdits edits,boolean interactive)throws Exception; }
    private static final int TEXT=0xfff4f5f7,MUTED=PhotoPrismaStyle.MUTED,ACCENT=PhotoPrismaStyle.YELLOW,PANEL=Color.TRANSPARENT,OVERLAY=0xff79d5ef;
    private final Activity activity;private final Consumer<PhotoLocalEdits> commit;private final Renderer renderer;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<>(1),r->{Thread t=new Thread(r,"photo-local-preview");t.setDaemon(true);return t;},new ThreadPoolExecutor.DiscardOldestPolicy());
    private final LatestPreviewQueue<PhotoLocalEdits,Bitmap> queue;
    private final ArrayDeque<PhotoLocalEdits> undo=new ArrayDeque<>(),redo=new ArrayDeque<>();
    private PhotoLocalEdits edits,gestureStart;private Bitmap rendered;private final Bitmap initial;
    private final PhotoCanvas photo;private TextView status;private Button apply,selection,newButton,moreButton,regionButton,adjustButton,undoButton,redoButton,overlayButton;
    private final Button[] tools=new Button[4];private final SeekBar[] sliders=new SeekBar[3];private final TextView[] labels=new TextView[3],values=new TextView[3];private final View[] sliderRows=new View[3];
    private final Button[] parameterTabs=new Button[5];
    private LinearLayout body,controls;private FrameLayout stage;private ScrollView controlScroll;
    private HorizontalScrollView parameterScroll,toolScroll;private boolean workspaceArranged,workspaceLandscape;private int workspaceWidth,workspaceHeight,parameter=3;
    private int revealedParameter=-1,revealedParameters=-1,parameterRailWidth=-1,revealedTool=-1,toolRailWidth=-1;
    private boolean needsParameterReveal,needsToolReveal;
    private int tool,selectedMask=-1,selectedClone=-1;private double brushRadius=.06,feather=.6,sourceX=.35,sourceY=.4;private boolean sourceSet,adding=true,region,showOverlay=true,updating,dragging,disposed;
    /** initial is borrowed and must stay alive until dismissal; it is never recycled by this dialog. */
    public PhotoLocalEditDialog(Activity activity,Bitmap orientedFullImage,PhotoLocalEdits edits,Renderer renderer,Consumer<PhotoLocalEdits> commit){
        super(activity,cc.huevia.R.style.AppThemeDark);if(orientedFullImage==null||edits==null||renderer==null||commit==null)throw new IllegalArgumentException("局部编辑参数无效。");
        this.activity=activity;this.initial=orientedFullImage;this.edits=edits;this.renderer=renderer;this.commit=commit;photo=new PhotoCanvas();
        if(!edits.masks().isEmpty()){selectedMask=0;tool=edits.masks().get(0).kind.ordinal();adding=false;}else if(!edits.clones().isEmpty()){selectedClone=0;tool=3;adding=false;sourceSet=true;sourceX=edits.clones().get(0).sourceX;sourceY=edits.clones().get(0).sourceY;}
        queue=new LatestPreviewQueue<>(worker,task->main.post(task),renderer::render,new LatestPreviewQueue.Listener<PhotoLocalEdits,Bitmap>(){
            public void frame(PhotoLocalEdits value,Bitmap image,boolean interactive,boolean latest){if(disposed){image.recycle();return;}Bitmap old=rendered;rendered=image;photo.invalidate();if(old!=null&&old!=image)old.recycle();if(latest&&!interactive){status.setText("");status.setVisibility(View.INVISIBLE);status.setOnClickListener(null);apply.setEnabled(true);apply.setAlpha(1);}}
            public void discard(Bitmap image){image.recycle();}
            public void error(Throwable failure){if(disposed)return;status.setText("预览失败 · 重试");status.setVisibility(View.VISIBLE);status.setOnClickListener(v->changed(false));apply.setEnabled(false);apply.setAlpha(.45f);}
        });
    }
    public PhotoLocalEdits settings(){return edits;}
    @Override protected void onCreate(Bundle state){
        super.onCreate(state);requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout root=column();root.setBackgroundColor(0xff0c0b0a);root.setTag("photo-local-workspace");
        LinearLayout top=row();top.setPadding(dp(4),0,dp(8),0);
        Button cancel=PhotoWorkspaceUi.icon(getContext(),"close","取消局部调整","local-cancel",this::dismiss);
        top.addView(cancel,new LinearLayout.LayoutParams(dp(48),dp(52)));
        TextView title=text(edits.portrait.bodyShape.isNeutral()?"局部调整":"局部 · 塑形前定位",edits.portrait.bodyShape.isNeutral()?16:12,TEXT);title.setSingleLine(true);title.setGravity(Gravity.CENTER);
        top.addView(title,new LinearLayout.LayoutParams(0,dp(52),1));
        apply=button("应用",()->{if(!disposed&&apply.isEnabled()){commit.accept(edits);dismiss();}});apply.setTextColor(0xff211812);apply.setTag("local-apply");
        GradientDrawable applyFace=new GradientDrawable();applyFace.setColor(ACCENT);applyFace.setCornerRadius(dp(10));
        apply.setBackground(new InsetDrawable(applyFace,dp(4),dp(8),dp(4),dp(8)));
        top.addView(apply,new LinearLayout.LayoutParams(dp(72),dp(52)));root.addView(top);
        body=new LinearLayout(getContext()){
            @Override protected void onSizeChanged(int w,int h,int oldw,int oldh){
                super.onSizeChanged(w,h,oldw,oldh);
                if(w>0&&h>0)post(()->{if(!disposed)arrangeWorkspace(getWidth()>getHeight()&&getWidth()>=dp(480),getWidth(),getHeight());});
            }
        };
        body.setTag("local-body");
        root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
        stage=new FrameLayout(getContext());stage.setTag("local-stage");stage.setBackgroundColor(Color.TRANSPARENT);stage.addView(photo,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout floating=row();floating.setTag("local-photo-toolbar");
        GradientDrawable scrim=new GradientDrawable();scrim.setColor(0xb30c0b0a);scrim.setCornerRadius(dp(24));floating.setBackground(scrim);
        undoButton=PhotoWorkspaceUi.icon(getContext(),"undo","撤销","local-undo",this::undo);
        redoButton=PhotoWorkspaceUi.icon(getContext(),"redo","重做","local-redo",this::redo);
        Button fit=PhotoWorkspaceUi.icon(getContext(),"fit","适应照片","local-fit",photo::resetViewport);
        overlayButton=PhotoWorkspaceUi.icon(getContext(),"mask","显示蒙版叠色","local-overlay",()->{showOverlay=!showOverlay;refresh();});
        for(Button b:new Button[]{undoButton,redoButton,fit,overlayButton})floating.addView(b,new LinearLayout.LayoutParams(dp(48),dp(48)));
        FrameLayout.LayoutParams floatingSize=new FrameLayout.LayoutParams(-2,dp(48),Gravity.BOTTOM|Gravity.END);floatingSize.setMargins(dp(8),0,dp(8),dp(8));stage.addView(floating,floatingSize);
        status=text("",12,MUTED);status.setGravity(Gravity.START|Gravity.CENTER_VERTICAL);status.setPadding(dp(12),0,dp(12),0);status.setVisibility(View.INVISIBLE);
        GradientDrawable statusScrim=new GradientDrawable();statusScrim.setColor(0xb30c0b0a);statusScrim.setCornerRadius(dp(12));status.setBackground(statusScrim);
        FrameLayout.LayoutParams statusSize=new FrameLayout.LayoutParams(-1,dp(48),Gravity.BOTTOM|Gravity.START);statusSize.setMargins(dp(8),0,dp(208),dp(8));stage.addView(status,statusSize);
        controls=column();controls.setBackgroundColor(PANEL);controls.setPadding(dp(12),dp(8),dp(12),dp(8));controls.setTag("local-dock");
        LinearLayout selectionRow=row();
        selection=button("新蒙版",this::choose);selection.setTag("local-selection");selection.setGravity(Gravity.START|Gravity.CENTER_VERTICAL);selection.setTextSize(13);
        selectionRow.addView(selection,new LinearLayout.LayoutParams(0,dp(48),1));
        newButton=PhotoWorkspaceUi.icon(getContext(),"add","新建蒙版","local-new",this::newSelection);
        selectionRow.addView(newButton,new LinearLayout.LayoutParams(dp(48),dp(48)));
        moreButton=PhotoWorkspaceUi.icon(getContext(),"more","蒙版操作","local-more",this::more);
        selectionRow.addView(moreButton,new LinearLayout.LayoutParams(dp(48),dp(48)));
        GradientDrawable selectionScrim=new GradientDrawable();selectionScrim.setColor(0xb30c0b0a);selectionScrim.setCornerRadius(dp(24));selectionRow.setBackground(selectionScrim);selectionRow.setPadding(dp(8),0,0,0);
        FrameLayout.LayoutParams selectionSize=new FrameLayout.LayoutParams(-1,dp(48),Gravity.TOP|Gravity.START);selectionSize.setMargins(dp(8),dp(8),dp(8),0);stage.addView(selectionRow,selectionSize);
        parameterScroll=new HorizontalScrollView(getContext());parameterScroll.setHorizontalScrollBarEnabled(false);parameterScroll.setFillViewport(true);
        parameterScroll.addOnLayoutChangeListener((v,l,t,r,b,oldL,oldT,oldR,oldB)->{if(r-l!=oldR-oldL)revealParameterChoice();});
        LinearLayout parameters=row();parameters.setGravity(Gravity.CENTER);
        String[] parameterNames={"曝光","冷暖","饱和","大小","羽化"};
        for(int i=0;i<parameterTabs.length;i++){
            final int index=i;Button tab=parameterButton(parameterNames[i],()->chooseParameter(index));tab.setTag("local-parameter-"+i);parameterTabs[i]=tab;
            parameters.addView(tab,new LinearLayout.LayoutParams(parameterWidth(),dp(48)));
        }
        adjustButton=parameterTabs[0];regionButton=parameterTabs[3];
        parameterScroll.addView(parameters,new HorizontalScrollView.LayoutParams(-2,dp(48)));controls.addView(parameterScroll,new LinearLayout.LayoutParams(-1,dp(48)));
        for(int i=0;i<3;i++){
            final int axis=i;LinearLayout line=row();labels[i]=text("",12,TEXT);line.addView(labels[i],new LinearLayout.LayoutParams(dp(48),dp(48)));
            SeekBar slider=new SeekBar(getContext());slider.setTag("local-axis-"+i);slider.setProgressTintList(ColorStateList.valueOf(ACCENT));slider.setThumbTintList(ColorStateList.valueOf(ACCENT));sliders[i]=slider;
            line.addView(slider,new LinearLayout.LayoutParams(0,dp(48),1));values[i]=text("",12,ACCENT);values[i].setGravity(Gravity.END|Gravity.CENTER_VERTICAL);line.addView(values[i],new LinearLayout.LayoutParams(dp(44),dp(48)));
            controls.addView(line);sliderRows[i]=line;
            slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar bar,int progress,boolean user){if(user&&!updating)adjust(axis,progress);}public void onStartTrackingTouch(SeekBar bar){gestureStart=edits;dragging=true;}public void onStopTrackingTouch(SeekBar bar){dragging=false;remember(gestureStart);gestureStart=null;changed(false);}});
        }
        toolScroll=new HorizontalScrollView(getContext());toolScroll.setHorizontalScrollBarEnabled(false);toolScroll.setFillViewport(true);
        toolScroll.addOnLayoutChangeListener((v,l,t,r,b,oldL,oldT,oldR,oldB)->{if(r-l!=oldR-oldL)revealToolChoice();});
        LinearLayout toolRow=row();toolRow.setTag("local-primary-tools");toolRow.setGravity(Gravity.CENTER);String[] names={"画笔","径向","渐变","修复"},icons={"brush","radial","linear","clone"};
        for(int i=0;i<4;i++){
            final int t=i;tools[i]=PhotoWorkspaceUi.tool(getContext(),names[i],"local-tool-"+i,icons[i],()->selectTool(t));
            toolRow.addView(tools[i],new LinearLayout.LayoutParams(toolWidth(),toolHeight()));
        }
        toolScroll.addView(toolRow,new HorizontalScrollView.LayoutParams(-2,toolHeight()));controls.addView(toolScroll,new LinearLayout.LayoutParams(-1,toolHeight()));
        controlScroll=new ScrollView(getContext());controlScroll.setFillViewport(false);controlScroll.setVerticalScrollBarEnabled(false);controlScroll.addView(controls,new ScrollView.LayoutParams(-1,-2));
        int initialWidth=activity.getResources().getDisplayMetrics().widthPixels;
        int initialHeight=Math.max(1,activity.getResources().getDisplayMetrics().heightPixels-dp(52));
        arrangeWorkspace(activity.getResources().getConfiguration().orientation==Configuration.ORIENTATION_LANDSCAPE&&initialWidth>=dp(480),initialWidth,initialHeight);
        root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){Insets safe=insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());root.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else root.setPadding(insets.getStableInsetLeft(),insets.getStableInsetTop(),insets.getStableInsetRight(),insets.getStableInsetBottom());return insets;});
        PhotoPrismaStyle.workspace(root,initial);setContentView(root);if(getWindow()!=null){getWindow().setBackgroundDrawableResource(android.R.color.transparent);getWindow().setLayout(-1,-1);}root.requestApplyInsets();refresh();changed(false);
    }
    private void arrangeWorkspace(boolean landscape,int width,int height){
        if(width<1||height<2)return;
        if(workspaceArranged&&workspaceLandscape==landscape&&workspaceWidth==width&&workspaceHeight==height)return;
        workspaceLandscape=landscape;workspaceWidth=width;workspaceHeight=height;body.setOrientation(landscape?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL);
        if(!workspaceArranged){body.addView(stage);body.addView(controlScroll);workspaceArranged=true;}
        LinearLayout.LayoutParams stageParams=(LinearLayout.LayoutParams)stage.getLayoutParams();int stageWidth=landscape?0:-1,stageHeight=landscape?-1:0;
        if(stageParams.width!=stageWidth||stageParams.height!=stageHeight||stageParams.weight!=1)stage.setLayoutParams(new LinearLayout.LayoutParams(stageWidth,stageHeight,1));
        // The photograph retains at least 54% of a narrow landscape workspace.
        int sideLimit=Math.min(dp(300),Math.round(width*.46f));int side=Math.min(sideLimit,Math.max(dp(240),Math.round(width*.4f)));
        int essential=dp(48)*2+toolHeight();
        int paddingTotal=landscape?dp(16):Math.max(0,Math.min(dp(16),(int)(height*2L/5)-essential));
        int paddingTop=paddingTotal/2,paddingBottom=paddingTotal-paddingTop;
        if(controls.getPaddingTop()!=paddingTop||controls.getPaddingBottom()!=paddingBottom)controls.setPadding(controls.getPaddingLeft(),paddingTop,controls.getPaddingRight(),paddingBottom);
        int naturalDock=essential+paddingTotal;
        int controlsWidth=landscape?side:-1,controlsHeight=landscape?-1:Math.max(1,Math.min(naturalDock,height/2));
        LinearLayout.LayoutParams controlParams=(LinearLayout.LayoutParams)controlScroll.getLayoutParams();
        if(controlParams.width!=controlsWidth||controlParams.height!=controlsHeight||controlParams.weight!=0)controlScroll.setLayoutParams(new LinearLayout.LayoutParams(controlsWidth,controlsHeight));
    }
    private void revealParameterChoice(){
        if(disposed||parameterScroll==null)return;int width=parameterScroll.getWidth()-parameterScroll.getPaddingLeft()-parameterScroll.getPaddingRight();if(width<1)return;
        int visible=0;for(int i=0;i<parameterTabs.length;i++)if(parameterTabs[i]!=null&&parameterTabs[i].getVisibility()==View.VISIBLE)visible|=1<<i;
        if(!needsParameterReveal&&parameter==revealedParameter&&visible==revealedParameters&&width==parameterRailWidth)return;
        if(dragging){needsParameterReveal=true;return;}
        needsParameterReveal=false;revealedParameter=parameter;revealedParameters=visible;parameterRailWidth=width;PhotoWorkspaceUi.revealChoice(parameterScroll,parameterTabs[parameter]);
    }
    private void revealToolChoice(){
        if(disposed||toolScroll==null)return;int width=toolScroll.getWidth()-toolScroll.getPaddingLeft()-toolScroll.getPaddingRight();if(width<1)return;
        if(!needsToolReveal&&tool==revealedTool&&width==toolRailWidth)return;
        if(dragging){needsToolReveal=true;return;}
        needsToolReveal=false;revealedTool=tool;toolRailWidth=width;PhotoWorkspaceUi.revealChoice(toolScroll,tools[tool]);
    }
    private void selectTool(int next){tool=next;selectedMask=selectedClone=-1;adding=true;if(next==3){sourceSet=false;if(parameter<3)parameter=3;}refresh();}
    private void newSelection(){adding=true;selectedMask=selectedClone=-1;if(tool==3)sourceSet=false;refresh();}
    private void chooseParameter(int next){parameter=next;region=next>=3;refresh();}
    private void more(){
        PopupMenu menu=new PopupMenu(getContext(),moreButton);PhotoLocalEdits.Mask m=mask();PhotoLocalEdits.Clone c=patch();boolean selected=m!=null||c!=null;
        menu.getMenu().add("新建"+(tool==3?"修复":"蒙版")).setEnabled(newButton.isEnabled()).setOnMenuItemClickListener(item->{newSelection();return true;});
        menu.getMenu().add(selected&&(m!=null?m.enabled:c.enabled)?"停用":"启用").setEnabled(selected).setOnMenuItemClickListener(item->{toggleEnabled();return true;});
        menu.getMenu().add("反选蒙版").setCheckable(true).setChecked(m!=null&&m.inverted).setEnabled(m!=null).setOnMenuItemClickListener(item->{PhotoLocalEdits.Mask current=mask();if(current!=null)replace(edits.withMask(selectedMask,current.inverted(!current.inverted)),true);return true;});
        menu.getMenu().add("删除"+(c!=null?"修复":"蒙版")).setEnabled(selected).setOnMenuItemClickListener(item->{remove();return true;});menu.show();
    }
    @Override public void show(){super.show();if(getWindow()!=null)getWindow().setLayout(-1,-1);}
    @Override public void dismiss(){if(!disposed){disposed=true;queue.close();worker.shutdownNow();photo.invalidate();if(rendered!=null){rendered.recycle();rendered=null;}}super.dismiss();}
    private PhotoLocalEdits.Mask mask(){return selectedMask>=0&&selectedMask<edits.masks().size()?edits.masks().get(selectedMask):null;}
    private PhotoLocalEdits.Clone patch(){return selectedClone>=0&&selectedClone<edits.clones().size()?edits.clones().get(selectedClone):null;}
    private void remember(PhotoLocalEdits old){if(old==null||old.equals(edits))return;undo.addLast(old);while(undo.size()>32)undo.removeFirst();redo.clear();}
    private void replace(PhotoLocalEdits next,boolean history){PhotoLocalEdits old=edits;edits=next;if(history)remember(old);changed(false);}
    private void changed(boolean interactive){if(disposed||status==null)return;refresh();status.setText("预览中");status.setVisibility(View.VISIBLE);apply.setEnabled(false);apply.setAlpha(.45f);queue.offer(edits,interactive||dragging);}
    private void undo(){if(undo.isEmpty())return;redo.addLast(edits);edits=undo.removeLast();normalizeSelection();changed(false);}
    private void redo(){if(redo.isEmpty())return;undo.addLast(edits);edits=redo.removeLast();normalizeSelection();changed(false);}
    private void normalizeSelection(){if(selectedMask>=edits.masks().size())selectedMask=edits.masks().isEmpty()?-1:edits.masks().size()-1;if(selectedClone>=edits.clones().size())selectedClone=edits.clones().isEmpty()?-1:edits.clones().size()-1;if(tool==3)selectedMask=-1;else{selectedClone=-1;if(mask()!=null)tool=mask().kind.ordinal();}adding=mask()==null&&patch()==null;}
    private void choose(){PopupMenu menu=new PopupMenu(getContext(),selection);int i=0;for(PhotoLocalEdits.Mask m:edits.masks())menu.getMenu().add(0,i++,i,label(m.kind)+" "+i+(m.enabled?"":" · 停用"));int n=edits.masks().size();for(int j=0;j<edits.clones().size();j++)menu.getMenu().add(0,n+j,n+j,"修复 "+(j+1)+(edits.clones().get(j).enabled?"":" · 停用"));if(i+edits.clones().size()==0)menu.getMenu().add("在照片上拖动新建").setEnabled(false);menu.setOnMenuItemClickListener(item->{int id=item.getItemId();if(id<n){selectedMask=id;selectedClone=-1;tool=mask().kind.ordinal();}else{selectedClone=id-n;selectedMask=-1;tool=3;PhotoLocalEdits.Clone c=patch();sourceX=c.sourceX;sourceY=c.sourceY;sourceSet=true;}adding=false;refresh();return true;});menu.show();}
    private void remove(){if(mask()!=null)replace(edits.removeMask(selectedMask),true);else if(patch()!=null)replace(edits.removeClone(selectedClone),true);normalizeSelection();refresh();}
    private void toggleEnabled(){PhotoLocalEdits.Mask m=mask();PhotoLocalEdits.Clone c=patch();if(m!=null)replace(edits.withMask(selectedMask,m.enabled(!m.enabled)),true);else if(c!=null)replace(edits.withClone(selectedClone,c.enabled(!c.enabled)),true);}
    private void adjust(int axis,int progress){PhotoLocalEdits old=edits;PhotoLocalEdits.Mask m=mask();PhotoLocalEdits.Clone c=patch();if(region||tool==3){if(axis==0){double size=(progress+1)/1000.0;brushRadius=Math.min(.5,size);if(m!=null){if(m.kind==PhotoLocalEdits.Kind.RADIAL){double ratio=size/m.x1;edits=edits.withMask(selectedMask,m.shape(m.x0,m.y0,size,Math.max(.001,Math.min(1,m.y1*ratio)),m.radius,m.feather));}else if(m.kind==PhotoLocalEdits.Kind.BRUSH)edits=edits.withMask(selectedMask,m.shape(m.x0,m.y0,m.x1,m.y1,brushRadius,m.feather));}else if(c!=null)edits=edits.withClone(selectedClone,c.size(Math.min(.25,brushRadius),c.feather));}else if(axis==1){feather=progress/100.0;if(m!=null)edits=edits.withMask(selectedMask,m.shape(m.x0,m.y0,m.x1,m.y1,m.radius,feather));else if(c!=null)edits=edits.withClone(selectedClone,c.size(c.radius,feather));}}else if(m!=null){int e=m.exposure,t=m.temperature,s=m.saturation;if(axis==0)e=progress-30;else if(axis==1)t=progress-100;else s=progress-100;edits=edits.withMask(selectedMask,m.parameters(e,t,s));}if(!dragging)remember(old);changed(false);}
    private void refresh(){
        if(selection==null)return;updating=true;PhotoLocalEdits.Mask m=mask();PhotoLocalEdits.Clone c=patch();
        if((tool==3||m==null)&&parameter<3)parameter=3;if(tool==2&&parameter==3)parameter=4;region=parameter>=3;
        for(int i=0;i<4;i++)select(tools[i],tool==i);
        String selectionText=m!=null?label(m.kind)+" "+(selectedMask+1)+" / "+edits.masks().size():c!=null?"修复 "+(selectedClone+1)+" / "+edits.clones().size():tool==3?sourceSet?"点目标位置 · 羽化克隆":"先点取样位置":"拖动新建"+label(PhotoLocalEdits.Kind.values()[tool])+"蒙版";
        selection.setText(selectionText);selection.setContentDescription("选择蒙版，"+selectionText);
        moreButton.setContentDescription(c!=null?"修复操作":"蒙版操作");newButton.setContentDescription(tool==3?"新建修复":"新建蒙版");
        select(overlayButton,showOverlay);overlayButton.setContentDescription(showOverlay?"隐藏蒙版叠色":"显示蒙版叠色");
        undoButton.setEnabled(!undo.isEmpty());redoButton.setEnabled(!redo.isEmpty());newButton.setEnabled(tool==3?edits.clones().size()<PhotoLocalEdits.MAX_CLONES:edits.masks().size()<PhotoLocalEdits.MAX_MASKS);select(newButton,adding);
        for(int i=0;i<parameterTabs.length;i++){
            boolean visible=!(i<3&&(tool==3||m==null))&&!(tool==2&&i==3);parameterTabs[i].setVisibility(visible?View.VISIBLE:View.GONE);
            boolean enabled=i>=3||m!=null;parameterTabs[i].setEnabled(enabled);parameterTabs[i].setAlpha(enabled?1f:.4f);select(parameterTabs[i],parameter==i);
        }
        boolean shape=region||tool==3;int visibleAxis=shape?parameter-3:parameter;
        String[] names=shape?new String[]{"大小","羽化",""}:new String[]{"曝光","冷暖","饱和"};
        for(int i=0;i<3;i++){
            sliderRows[i].setVisibility(i==visibleAxis?View.VISIBLE:View.GONE);labels[i].setText(names[i]);
            int max=shape?i==0?m!=null&&m.kind==PhotoLocalEdits.Kind.RADIAL?999:tool==3?249:499:100:i==0?60:200;sliders[i].setMax(max);
            int value;if(shape){double r=c!=null?c.radius:m!=null?m.kind==PhotoLocalEdits.Kind.RADIAL?m.x1:m.radius:brushRadius;value=i==0?(int)Math.round(r*1000)-1:(int)Math.round((c!=null?c.feather:m!=null?m.feather:feather)*100);}else value=m==null?i==0?30:100:i==0?m.exposure+30:i==1?m.temperature+100:m.saturation+100;
            sliders[i].setProgress(Math.max(0,Math.min(max,value)));boolean enabled=shape?i!=0||m==null||m.kind!=PhotoLocalEdits.Kind.LINEAR:m!=null;sliders[i].setEnabled(enabled);
            values[i].setText(shape?Math.round(i==0?(value+1)/10.0:value)+"%":i==0?String.format(Locale.ROOT,"%+.1f",(value-30)/10.0):String.format(Locale.ROOT,"%+d",value-100));sliders[i].setContentDescription(names[i]+"，"+values[i].getText());
        }
        photo.setContentDescription(tool==3?"克隆修复：双指缩放移动；先点取样位置，再点目标。":"局部蒙版：拖动新建，双指缩放移动，拖动控制点调整。");updating=false;revealParameterChoice();revealToolChoice();photo.invalidate();
    }
    private static String label(PhotoLocalEdits.Kind kind){return kind==PhotoLocalEdits.Kind.BRUSH?"画笔":kind==PhotoLocalEdits.Kind.RADIAL?"径向":"渐变";}
    private void select(Button b,boolean selected){b.setSelected(selected);b.setTextColor(selected?ACCENT:TEXT);}

    private final class PhotoCanvas extends View {
        private final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);private final RectF frame=new RectF();private final ArrayList<Double> path=new ArrayList<>();private double downX,downY,beforeSourceX,beforeSourceY;private int handle,beforeMask,beforeClone;private boolean creating,navigating,beforeAdding,beforeSourceSet;private float zoom=1,panX,panY,lastFocusX,lastFocusY;private PhotoLocalEdits.Mask originalMask;private PhotoLocalEdits.Clone originalClone;
        private final ScaleGestureDetector scale;
        PhotoCanvas(){super(PhotoLocalEditDialog.this.getContext());setFocusable(true);setTag("local-canvas");scale=new ScaleGestureDetector(getContext(),new ScaleGestureDetector.SimpleOnScaleGestureListener(){@Override public boolean onScale(ScaleGestureDetector detector){float next=Math.max(1,Math.min(8,zoom*detector.getScaleFactor())),ratio=next/zoom,fx=detector.getFocusX()-getWidth()/2f,fy=detector.getFocusY()-getHeight()/2f;panX=fx-(fx-panX)*ratio;panY=fy-(fy-panY)*ratio;zoom=next;clampPan();bounds();invalidate();return true;}});}
        @Override protected void onSizeChanged(int w,int h,int oldw,int oldh){super.onSizeChanged(w,h,oldw,oldh);if(w>0&&h>0){clampPan();bounds();}}
        void resetViewport(){zoom=1;panX=panY=0;bounds();invalidate();}
        private void clampPan(){Bitmap image=rendered==null?initial:rendered;float fit=Math.min(getWidth()/(float)image.getWidth(),getHeight()/(float)image.getHeight()),mx=Math.max(0,(image.getWidth()*fit*zoom-getWidth())/2),my=Math.max(0,(image.getHeight()*fit*zoom-getHeight())/2);panX=Math.max(-mx,Math.min(mx,panX));panY=Math.max(-my,Math.min(my,panY));}
        private void bounds(){Bitmap image=rendered==null?initial:rendered;float fit=Math.min(getWidth()/(float)image.getWidth(),getHeight()/(float)image.getHeight()),w=image.getWidth()*fit*zoom,h=image.getHeight()*fit*zoom;frame.set((getWidth()-w)/2+panX,(getHeight()-h)/2+panY,(getWidth()+w)/2+panX,(getHeight()+h)/2+panY);}
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);if(disposed)return;bounds();Bitmap image=rendered==null?initial:rendered;if(!image.isRecycled()){ink.setAlpha(255);canvas.drawBitmap(image,null,frame,ink);}if(frame.isEmpty())return;canvas.save();canvas.clipRect(frame);PhotoLocalEdits.Mask m=mask();PhotoLocalEdits.Clone c=patch();if(m!=null)drawMask(canvas,m);if(c!=null)drawClone(canvas,c);else if(tool==3&&sourceSet)circle(canvas,sourceX,sourceY,dp(10),false);// Creation guidance lives once in the native top selection label, clear of the bottom toolbar.
            canvas.restore();}
        private void drawMask(Canvas c,PhotoLocalEdits.Mask m){float x=(float)(frame.left+m.x0*frame.width()),y=(float)(frame.top+m.y0*frame.height());ink.setShader(null);ink.setColor(OVERLAY);ink.setStrokeWidth(dp(1));ink.setStyle(Paint.Style.STROKE);if(m.kind==PhotoLocalEdits.Kind.RADIAL){RectF oval=new RectF(x-(float)m.x1*frame.width(),y-(float)m.y1*frame.height(),x+(float)m.x1*frame.width(),y+(float)m.y1*frame.height());if(showOverlay){ink.setStyle(Paint.Style.FILL);ink.setColor(m.enabled?0x3579d5ef:0x1579d5ef);if(m.inverted){Path selected=new Path();selected.addRect(frame,Path.Direction.CW);selected.addOval(oval,Path.Direction.CW);selected.setFillType(Path.FillType.EVEN_ODD);c.drawPath(selected,ink);}else c.drawOval(oval,ink);}ink.setStyle(Paint.Style.STROKE);ink.setColor(OVERLAY);c.drawOval(oval,ink);RectF inner=new RectF(oval);inner.inset((float)(oval.width()*.5*m.feather),(float)(oval.height()*.5*m.feather));ink.setColor(0x8079d5ef);c.drawOval(inner,ink);circle(c,m.x0,m.y0,dp(5),true);circle(c,Math.min(1,m.x0+m.x1),Math.min(1,m.y0+m.y1),dp(6),true);}
            else if(m.kind==PhotoLocalEdits.Kind.LINEAR){float bx=(float)(frame.left+m.x1*frame.width()),by=(float)(frame.top+m.y1*frame.height());if(showOverlay){ink.setStyle(Paint.Style.FILL);ink.setShader(new LinearGradient(x,y,bx,by,m.inverted?0x5579d5ef:0x0079d5ef,m.inverted?0x0079d5ef:0x5579d5ef,Shader.TileMode.CLAMP));c.drawRect(frame,ink);ink.setShader(null);}ink.setStyle(Paint.Style.STROKE);ink.setColor(OVERLAY);c.drawLine(x,y,bx,by,ink);circle(c,m.x0,m.y0,dp(6),true);circle(c,m.x1,m.y1,dp(6),true);}
            else{double[] points=m.points();Path p=new Path();for(int i=0;i<points.length;i+=2){float px=(float)(frame.left+points[i]*frame.width()),py=(float)(frame.top+points[i+1]*frame.height());if(i==0)p.moveTo(px,py);else p.lineTo(px,py);}if(showOverlay){ink.setStyle(Paint.Style.STROKE);ink.setStrokeCap(Paint.Cap.ROUND);ink.setStrokeJoin(Paint.Join.ROUND);ink.setStrokeWidth((float)(m.radius*2*Math.min(frame.width(),frame.height())));ink.setColor(m.enabled?0x5579d5ef:0x2279d5ef);if(m.inverted){Path selected=new Path();if(points.length==2)selected.addCircle((float)(frame.left+points[0]*frame.width()),(float)(frame.top+points[1]*frame.height()),ink.getStrokeWidth()/2,Path.Direction.CW);else ink.getFillPath(p,selected);selected.addRect(frame,Path.Direction.CW);selected.setFillType(Path.FillType.EVEN_ODD);ink.setStyle(Paint.Style.FILL);c.drawPath(selected,ink);}else if(points.length==2){ink.setStyle(Paint.Style.FILL);c.drawCircle((float)(frame.left+points[0]*frame.width()),(float)(frame.top+points[1]*frame.height()),ink.getStrokeWidth()/2,ink);}else c.drawPath(p,ink);}ink.setStrokeWidth(dp(1));circle(c,points[0],points[1],dp(5),true);}}
        private void drawClone(Canvas c,PhotoLocalEdits.Clone p){ink.setStyle(Paint.Style.STROKE);ink.setStrokeWidth(dp(1));ink.setColor(0xaaffffff);float x=(float)(frame.left+p.sourceX*frame.width()),y=(float)(frame.top+p.sourceY*frame.height()),tx=(float)(frame.left+p.targetX*frame.width()),ty=(float)(frame.top+p.targetY*frame.height());c.drawLine(x,y,tx,ty,ink);float radius=(float)(p.radius*Math.min(frame.width(),frame.height()));circle(c,p.sourceX,p.sourceY,radius,false);circle(c,p.targetX,p.targetY,radius,true);}
        private void circle(Canvas c,double x,double y,float radius,boolean target){ink.setShader(null);ink.setStrokeWidth(dp(1));ink.setColor(target?ACCENT:OVERLAY);ink.setStyle(Paint.Style.STROKE);float px=(float)(frame.left+x*frame.width()),py=(float)(frame.top+y*frame.height());c.drawCircle(px,py,radius,ink);c.drawLine(px-dp(3),py,px+dp(3),py,ink);c.drawLine(px,py-dp(3),px,py+dp(3),ink);}
        private double px(float x){return Math.max(0,Math.min(1,(x-frame.left)/frame.width()));}private double py(float y){return Math.max(0,Math.min(1,(y-frame.top)/frame.height()));}
        private double distance(double x,double y,double a,double b){return Math.hypot((x-a)*frame.width(),(y-b)*frame.height());}
        private void restoreGesture(){if(gestureStart==null)return;edits=gestureStart;selectedMask=beforeMask;selectedClone=beforeClone;adding=beforeAdding;sourceSet=beforeSourceSet;sourceX=beforeSourceX;sourceY=beforeSourceY;gestureStart=null;}
        @Override public boolean onTouchEvent(android.view.MotionEvent e){if(disposed||frame.isEmpty())return false;int action=e.getActionMasked();if(e.getPointerCount()>1){float fx=(e.getX(0)+e.getX(1))/2,fy=(e.getY(0)+e.getY(1))/2;if(!navigating){dragging=false;if(gestureStart!=null){restoreGesture();changed(false);}navigating=true;lastFocusX=fx;lastFocusY=fy;}else{panX+=fx-lastFocusX;panY+=fy-lastFocusY;lastFocusX=fx;lastFocusY=fy;}scale.onTouchEvent(e);clampPan();bounds();invalidate();getParent().requestDisallowInterceptTouchEvent(true);return true;}scale.onTouchEvent(e);if(navigating){if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL){navigating=false;getParent().requestDisallowInterceptTouchEvent(false);}return true;}double x=px(e.getX()),y=py(e.getY());if(action==MotionEvent.ACTION_DOWN){if(!frame.contains(e.getX(),e.getY()))return false;gestureStart=edits;beforeMask=selectedMask;beforeClone=selectedClone;beforeAdding=adding;beforeSourceSet=sourceSet;beforeSourceX=sourceX;beforeSourceY=sourceY;dragging=true;downX=x;downY=y;originalMask=mask();originalClone=patch();creating=adding||originalMask==null;handle=0;path.clear();getParent().requestDisallowInterceptTouchEvent(true);
                if(tool==3){if(originalClone!=null&&!adding){handle=distance(x,y,originalClone.sourceX,originalClone.sourceY)<dp(28)?1:2;}else if(!sourceSet){sourceX=x;sourceY=y;sourceSet=true;handle=3;refresh();return true;}else if(edits.clones().size()<PhotoLocalEdits.MAX_CLONES){PhotoLocalEdits.Clone c=new PhotoLocalEdits.Clone(sourceX,sourceY,x,y,Math.min(.25,brushRadius),feather,true);edits=edits.add(c);selectedClone=edits.clones().size()-1;selectedMask=-1;originalClone=c;adding=false;handle=2;changed(true);}}
                else if(adding||originalMask==null){if(edits.masks().size()>=PhotoLocalEdits.MAX_MASKS){dragging=false;return false;}PhotoLocalEdits.Mask m;if(tool==0){path.add(x);path.add(y);m=PhotoLocalEdits.Mask.brush(new double[]{x,y},brushRadius,feather);}else if(tool==1)m=PhotoLocalEdits.Mask.radial(x,y);else m=PhotoLocalEdits.Mask.linear(Math.max(0,x-.01),y,Math.min(1,x+.01),y);edits=edits.add(m);selectedMask=edits.masks().size()-1;selectedClone=-1;originalMask=m;adding=false;handle=tool==0?4:2;changed(true);}
                else{if(tool==1)handle=distance(x,y,Math.min(1,originalMask.x0+originalMask.x1),Math.min(1,originalMask.y0+originalMask.y1))<dp(32)?2:1;else if(tool==2)handle=distance(x,y,originalMask.x0,originalMask.y0)<distance(x,y,originalMask.x1,originalMask.y1)?1:2;else handle=1;}return true;}
            if(action==MotionEvent.ACTION_MOVE){try{if(tool==3&&originalClone!=null){PhotoLocalEdits.Clone c=originalClone;edits=edits.withClone(selectedClone,new PhotoLocalEdits.Clone(handle==1?x:c.sourceX,handle==1?y:c.sourceY,handle==2?x:c.targetX,handle==2?y:c.targetY,c.radius,c.feather,c.enabled));}
                    else if(originalMask!=null){PhotoLocalEdits.Mask m=originalMask;if(tool==0&&handle==4){if(path.size()<PhotoLocalEdits.MAX_BRUSH_POINTS*2&&distance(x,y,path.get(path.size()-2),path.get(path.size()-1))>dp(2)){path.add(x);path.add(y);}double[] points=new double[path.size()];for(int i=0;i<points.length;i++)points[i]=path.get(i);edits=edits.withMask(selectedMask,PhotoLocalEdits.Mask.brush(points,m.radius,m.feather).parameters(m.exposure,m.temperature,m.saturation));}
                        else if(tool==0){double[] points=m.points();double dx=x-downX,dy=y-downY;for(int i=0;i<points.length;i+=2){points[i]=Math.max(0,Math.min(1,points[i]+dx));points[i+1]=Math.max(0,Math.min(1,points[i+1]+dy));}edits=edits.withMask(selectedMask,new PhotoLocalEdits.Mask(m.kind,0,0,0,0,m.radius,m.feather,m.inverted,m.enabled,m.exposure,m.temperature,m.saturation,points));}
                        else if(tool==1){edits=edits.withMask(selectedMask,handle==2?m.shape(m.x0,m.y0,Math.max(.005,Math.min(1,creating?Math.abs(x-m.x0):m.x1+x-downX)),Math.max(.005,Math.min(1,creating?Math.abs(y-m.y0):m.y1+y-downY)),m.radius,m.feather):m.shape(Math.max(0,Math.min(1,m.x0+x-downX)),Math.max(0,Math.min(1,m.y0+y-downY)),m.x1,m.y1,m.radius,m.feather));}
                        else{double ax=handle==1?x:m.x0,ay=handle==1?y:m.y0,bx=handle==2?x:m.x1,by=handle==2?y:m.y1;if(Math.hypot(bx-ax,by-ay)>=.001)edits=edits.withMask(selectedMask,m.shape(ax,ay,bx,by,m.radius,m.feather));}}
                    if(handle!=3)changed(true);else refresh();}catch(IllegalArgumentException ignored){}return true;}
            if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL){dragging=false;if(action==MotionEvent.ACTION_CANCEL)restoreGesture();else remember(gestureStart);gestureStart=null;getParent().requestDisallowInterceptTouchEvent(false);changed(false);performClick();return true;}return true;}
        @Override public boolean performClick(){super.performClick();return true;}
    }
    private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
    private int parameterWidth(){return Math.max(dp(60),Math.round(dp(60)*Math.min(1.4f,activity.getResources().getConfiguration().fontScale)));}
    private int toolWidth(){return dp(64);}
    private int toolHeight(){return dp(72+Math.max(0,Math.round((activity.getResources().getConfiguration().fontScale-1f)*28)));}
    private LinearLayout column(){LinearLayout l=new LinearLayout(getContext());l.setOrientation(LinearLayout.VERTICAL);return l;}
    private LinearLayout row(){LinearLayout l=new LinearLayout(getContext());l.setGravity(Gravity.CENTER_VERTICAL);l.setBaselineAligned(false);return l;}
    private TextView text(String text,int size,int color){TextView t=new TextView(getContext());t.setText(text);t.setTextSize(size);t.setTextColor(color);t.setIncludeFontPadding(false);t.setGravity(Gravity.CENTER_VERTICAL);t.setSingleLine(true);return t;}
    private Button button(String text,Runnable action){return styleButton(new Button(getContext()),text,action);}
    private Button parameterButton(String text,Runnable action){
        return styleButton(new Button(getContext()){
            private final Paint indicator=new Paint(Paint.ANTI_ALIAS_FLAG);
            @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);if(isSelected()){indicator.setColor(ACCENT);indicator.setStrokeWidth(dp(2));indicator.setStrokeCap(Paint.Cap.ROUND);canvas.drawLine(getWidth()/2f-dp(8),getHeight()-dp(3),getWidth()/2f+dp(8),getHeight()-dp(3),indicator);}}
        },text,action);
    }
    private Button styleButton(Button b,String text,Runnable action){b.setText(text);b.setTextSize(12);b.setTextColor(TEXT);b.setAllCaps(false);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setPadding(dp(4),0,dp(4),0);b.setSingleLine(true);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffe335),null,null));b.setStateListAnimator(null);b.setOnClickListener(v->action.run());return b;}
}
