package cc.huevia.ui;

import android.app.*;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import cc.huevia.ncp.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** Tentative repair transaction: select a target, then drag its clean sampling source. */
public final class PhotoPatchDialog extends Dialog {
    public interface Renderer{Bitmap render(PhotoLocalEdits edits,boolean interactive)throws Exception;}
    private static final int TEXT=0xfff4f5f7,MUTED=PhotoPrismaStyle.MUTED,YELLOW=PhotoPrismaStyle.YELLOW;
    private final Activity activity;
    private final Bitmap initial;
    private final Consumer<PhotoLocalEdits> commit;
    private final AdjustmentRegion seed;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<>(1),r->{Thread t=new Thread(r,"photo-patch-preview");t.setDaemon(true);return t;},new ThreadPoolExecutor.DiscardOldestPolicy());
    private final LatestPreviewQueue<PhotoLocalEdits,Bitmap> queue;
    private final ArrayDeque<State> undo=new ArrayDeque<>(),redo=new ArrayDeque<>();
    private PhotoLocalEdits edits;
    private int selected;
    private Bitmap rendered,mask,selectionPhoto;
    private AdjustmentRegion.Brush coverage;
    private PhotoBrushDialog selectionDialog;
    private Button apply,undoButton,redoButton,eyeButton,moreButton,selectionButton,sampleButton,newButton;
    private TextView title,hint,status,visibility,featherValue,blendValue;
    private SeekBar featherSlider,blendSlider;
    private LinearLayout body,panel;
    private FrameLayout stage;
    private ScrollView dock;
    private final PhotoCanvas photo;
    private State gestureStart,sliderStart;
    private boolean disposed,showSelection=true,adjusting,dragging,rendering,updating;

    public PhotoPatchDialog(Activity activity,Bitmap orientedPhoto,PhotoLocalEdits edits,AdjustmentRegion seed,Renderer renderer,Consumer<PhotoLocalEdits> commit){
        super(activity,cc.huevia.R.style.AppThemeDark);
        if(orientedPhoto==null||orientedPhoto.isRecycled()||edits==null||renderer==null||commit==null)throw new IllegalArgumentException("修补参数无效。");
        this.activity=activity;initial=orientedPhoto;this.edits=edits;this.seed=seed;this.commit=commit;selected=edits.patches().size()-1;photo=new PhotoCanvas();
        queue=new LatestPreviewQueue<>(worker,task->main.post(task),renderer::render,new LatestPreviewQueue.Listener<PhotoLocalEdits,Bitmap>(){
            public void frame(PhotoLocalEdits value,Bitmap image,boolean interactive,boolean latest){
                if(disposed){image.recycle();return;}Bitmap old=rendered;rendered=image;if(old!=null&&old!=image)old.recycle();
                if(latest&&!interactive){rendering=false;status.setText("");status.setOnClickListener(null);refresh();}photo.invalidate();
            }
            public void discard(Bitmap image){image.recycle();}
            public void error(Throwable failure){if(disposed)return;rendering=true;status.setText("修补预览失败 · 点击重试");status.setOnClickListener(v->changed(false));refresh();}
        });
    }
    public PhotoLocalEdits settings(){return edits;}
    @Override protected void onCreate(Bundle state){
        super.onCreate(state);requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout root=column();root.setTag("patch-workspace");LinearLayout header=row();header.setPadding(dp(4),0,dp(8),0);
        header.addView(PhotoWorkspaceUi.icon(getContext(),"close","取消本次修补","patch-cancel",this::dismiss),new LinearLayout.LayoutParams(dp(48),dp(52)));
        title=text("修补",16,TEXT);title.setSingleLine(true);title.setEllipsize(android.text.TextUtils.TruncateAt.END);title.setGravity(Gravity.CENTER);header.addView(title,new LinearLayout.LayoutParams(0,dp(52),1));
        apply=button("应用",()->{if(!disposed&&apply.isEnabled()){commit.accept(edits);dismiss();}});apply.setTag("patch-apply");PhotoPrismaStyle.primary(apply);header.addView(apply,new LinearLayout.LayoutParams(dp(76),dp(52)));root.addView(header);
        body=column();body.setTag("patch-body");root.addView(body,new LinearLayout.LayoutParams(-1,0,1));stage=new FrameLayout(getContext());stage.setTag("patch-stage");stage.addView(photo,new FrameLayout.LayoutParams(-1,-1));body.addView(stage,new LinearLayout.LayoutParams(-1,0,1));
        hint=text("先圈选要修补的区域",12,TEXT);hint.setTag("patch-hint");hint.setGravity(Gravity.CENTER);hint.setMaxLines(2);hint.setEllipsize(android.text.TextUtils.TruncateAt.END);hint.setPadding(dp(10),dp(6),dp(10),dp(6));hint.setBackground(PhotoPrismaStyle.shape(0xb3191e17,dp(8)));
        FrameLayout.LayoutParams hp=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);hp.setMargins(dp(8),dp(8),dp(8),dp(8));stage.addView(hint,hp);
        panel=column();panel.setPadding(dp(12),0,dp(12),dp(8));panel.setTag("patch-panel");LinearLayout history=row();
        undoButton=PhotoWorkspaceUi.icon(getContext(),"undo","撤销修补操作","patch-undo",this::undo);redoButton=PhotoWorkspaceUi.icon(getContext(),"redo","重做修补操作","patch-redo",this::redo);
        eyeButton=PhotoWorkspaceUi.icon(getContext(),"eye","隐藏选区","patch-overlay",()->{showSelection=!showSelection;refresh();});
        for(Button b:new Button[]{undoButton,redoButton,eyeButton})history.addView(b,new LinearLayout.LayoutParams(dp(48),dp(48)));
        visibility=text("隐藏选区",12,TEXT);visibility.setSingleLine(true);visibility.setGravity(Gravity.CENTER);visibility.setOnClickListener(v->eyeButton.performClick());history.addView(visibility,new LinearLayout.LayoutParams(0,dp(48),1));
        moreButton=PhotoWorkspaceUi.icon(getContext(),"more","更多修补操作","patch-more",this::more);history.addView(moreButton,new LinearLayout.LayoutParams(dp(48),dp(48)));panel.addView(history);
        LinearLayout tools=row();selectionButton=PhotoWorkspaceUi.tool(getContext(),"选区","patch-selection","brush",()->select(false));sampleButton=PhotoWorkspaceUi.tool(getContext(),"取样","patch-sample","clone",()->{hint.setText("拖动选区到干净位置 · 双指缩放和移动");photo.announceForAccessibility("在照片上拖动取样区");});newButton=PhotoWorkspaceUi.tool(getContext(),"新增","patch-new","add",()->select(true));
        for(Button b:new Button[]{selectionButton,sampleButton,newButton})tools.addView(b,new LinearLayout.LayoutParams(0,dp(80),1));panel.addView(tools);
        featherSlider=slider("羽化","patch-feather",true);blendSlider=slider("融合","patch-blend",false);
        status=text("",12,MUTED);status.setTag("patch-status");status.setGravity(Gravity.CENTER);status.setMinHeight(dp(24));panel.addView(status,new LinearLayout.LayoutParams(-1,-2));
        dock=new ScrollView(getContext());dock.setTag("patch-controls-scroll");dock.setFillViewport(false);dock.setVerticalScrollBarEnabled(false);dock.addView(panel);body.addView(dock,new LinearLayout.LayoutParams(-1,-2));
        body.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->arrange());stage.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->hint.setMaxWidth(Math.max(dp(48),stage.getWidth()-dp(16))));
        root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){Insets safe=insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());root.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else root.setPadding(insets.getStableInsetLeft(),insets.getStableInsetTop(),insets.getStableInsetRight(),insets.getStableInsetBottom());body.post(this::arrange);return insets;});
        PhotoPrismaStyle.workspace(root,initial);setContentView(root);if(getWindow()!=null){getWindow().setBackgroundDrawableResource(android.R.color.transparent);getWindow().setLayout(-1,-1);}root.requestApplyInsets();rebuildMask();refresh();
        if(seed!=null&&seed.hasSelection()&&edits.patches().size()<PhotoLocalEdits.MAX_PATCHES)acceptSelection(seed,true);
    }
    @Override public void show(){super.show();if(getWindow()!=null)getWindow().setLayout(-1,-1);}
    private void arrange(){
        if(disposed||body==null||body.getHeight()<2)return;int w=body.getWidth(),h=body.getHeight();boolean side=w>h&&w>=dp(480);int orientation=side?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL;
        if(body.getOrientation()!=orientation)body.setOrientation(orientation);
        int sw=side?0:-1,sh=side?-1:0;LinearLayout.LayoutParams sp=(LinearLayout.LayoutParams)stage.getLayoutParams();if(sp.width!=sw||sp.height!=sh||sp.weight!=1)stage.setLayoutParams(new LinearLayout.LayoutParams(sw,sh,1));
        int dw=side?Math.min(dp(320),Math.round(w*.44f)):-1,dh=side?-1:Math.min(dp(256+48*(Math.max(1,activity.getResources().getConfiguration().fontScale)-1)),h/2);
        LinearLayout.LayoutParams cp=(LinearLayout.LayoutParams)dock.getLayoutParams();if(cp.width!=dw||cp.height!=dh)dock.setLayoutParams(new LinearLayout.LayoutParams(dw,dh));photo.invalidate();
    }
    private PhotoPatch patch(){return selected>=0&&selected<edits.patches().size()?edits.patches().get(selected):null;}
    private State snapshot(){return new State(edits,selected);}
    private void restore(State s){edits=s.edits;selected=s.selected;rebuildMask();refresh();changed(false);}
    private void remember(State before){if(before==null||before.edits.equals(edits))return;undo.push(before);while(undo.size()>40)undo.removeLast();redo.clear();}
    private void undo(){cancelGesture();if(undo.isEmpty())return;redo.push(snapshot());restore(undo.pop());}
    private void redo(){cancelGesture();if(redo.isEmpty())return;undo.push(snapshot());restore(redo.pop());}
    private void changed(boolean interactive){if(disposed||status==null)return;rendering=true;status.setText("修补预览中…");status.setOnClickListener(null);refresh();queue.offer(edits,interactive||dragging||adjusting);}
    private void select(boolean add){
        if(disposed||selectionDialog!=null||dragging||adjusting||rendering)return;
        if(add&&edits.patches().size()>=PhotoLocalEdits.MAX_PATCHES){status.setText("修补数量已达上限，可删除不再使用的修补");return;}
        try{selectionPhoto=(rendered==null?initial:rendered).copy(Bitmap.Config.ARGB_8888,false);if(selectionPhoto==null)throw new OutOfMemoryError();}
        catch(OutOfMemoryError error){status.setText("暂时无法打开选区，请稍后重试");return;}
        PhotoPatch current=patch();AdjustmentRegion region=!add&&current!=null?current.selection:AdjustmentRegion.create("修补区域");
        PhotoBrushDialog dialog=new PhotoBrushDialog(activity,selectionPhoto,region,next->{if(!disposed){if(next.hasSelection())acceptSelection(next,add||current==null);else if(!add&&current!=null)removeCurrent();}});selectionDialog=dialog;
        dialog.setOnDismissListener(v->{if(selectionDialog==dialog)selectionDialog=null;if(selectionPhoto!=null){selectionPhoto.recycle();selectionPhoto=null;}if(!disposed)refresh();});dialog.show();refresh();
    }
    private void acceptSelection(AdjustmentRegion selection,boolean add){
        State before=snapshot();try{
            if(add){edits=edits.addPatch(PhotoPatch.create(selection));selected=edits.patches().size()-1;}
            else edits=edits.withPatch(selected,patch().selection(selection));
            PhotoPatch p=patch();edits=edits.withPatch(selected,clamp(p,p.dx,p.dy));showSelection=true;remember(before);rebuildMask();changed(false);
        }catch(IllegalArgumentException limit){edits=before.edits;selected=before.selected;status.setText(limit.getMessage());}
    }
    private PhotoPatch clamp(PhotoPatch p,double dx,double dy){AdjustmentRegion.Brush b=p.selection.compileBrush(initial.getWidth(),initial.getHeight());return p.sample(Math.max(-b.left,Math.min(1-b.right,dx)),Math.max(-b.top,Math.min(1-b.bottom,dy)));}
    private void removeCurrent(){if(patch()==null)return;cancelGesture();State before=snapshot();edits=edits.removePatch(selected);selected=Math.min(selected,edits.patches().size()-1);remember(before);rebuildMask();changed(false);}
    private void more(){
        PopupMenu menu=new PopupMenu(getContext(),moreButton);menu.getMenu().add("适应照片").setOnMenuItemClickListener(i->{photo.resetViewport();return true;});
        menu.getMenu().add("删除当前修补").setEnabled(patch()!=null).setOnMenuItemClickListener(i->{removeCurrent();return true;});
        if(edits.patches().size()>1)for(int n=0;n<edits.patches().size();n++){final int index=n;menu.getMenu().add("修补 "+(n+1)).setCheckable(true).setChecked(n==selected).setOnMenuItemClickListener(i->{cancelGesture();selected=index;rebuildMask();refresh();return true;});}
        menu.show();
    }
    private SeekBar slider(String caption,String tag,boolean feather){
        LinearLayout line=row();line.addView(text(caption,12,MUTED),new LinearLayout.LayoutParams(dp(44),dp(48)));SeekBar s=new SeekBar(getContext());s.setTag(tag);s.setMax(100);s.setContentDescription(caption);PhotoPrismaStyle.slider(activity,s);line.addView(s,new LinearLayout.LayoutParams(0,dp(48),1));TextView value=text("0%",12,MUTED);value.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);line.addView(value,new LinearLayout.LayoutParams(dp(48),dp(48)));if(feather)featherValue=value;else blendValue=value;
        s.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onStartTrackingTouch(SeekBar bar){if(patch()==null)return;sliderStart=snapshot();adjusting=true;refresh();}
            public void onProgressChanged(SeekBar bar,int progress,boolean user){if(!user||updating||patch()==null)return;State before=snapshot();try{edits=edits.withPatch(selected,feather?patch().feather(progress/100.0):patch().blend(progress/100.0));if(sliderStart==null)remember(before);if(feather)rebuildMask();changed(adjusting);}catch(IllegalArgumentException limit){status.setText(limit.getMessage());}}
            public void onStopTrackingTouch(SeekBar bar){adjusting=false;remember(sliderStart);sliderStart=null;changed(false);}
        });panel.addView(line);return s;
    }
    private void rebuildMask(){
        if(mask!=null){mask.recycle();mask=null;}PhotoPatch p=patch();coverage=p==null?null:p.selection.compileBrush(initial.getWidth(),initial.getHeight());
        if(coverage!=null){double scale=Math.min(1,320.0/Math.max(initial.getWidth(),initial.getHeight()));int w=Math.max(2,(int)Math.round(initial.getWidth()*scale)),h=Math.max(2,(int)Math.round(initial.getHeight()*scale));int[] pixels=new int[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++)pixels[y*w+x]=(Math.round((float)coverage.weight((x+.5)/w,(y+.5)/h)*38)<<24)|0x00fff1e4;mask=Bitmap.createBitmap(pixels,w,h,Bitmap.Config.ARGB_8888);}
        photo.invalidate();
    }
    private void refresh(){
        if(apply==null)return;PhotoPatch p=patch();boolean available=p!=null&&p.selection.hasSelection();title.setText(p==null?"修补":"修补 · "+(selected+1)+" / "+edits.patches().size());
        undoButton.setEnabled(!undo.isEmpty()&&!adjusting&&!dragging);redoButton.setEnabled(!redo.isEmpty()&&!adjusting&&!dragging);eyeButton.setEnabled(available);eyeButton.setSelected(showSelection);eyeButton.setContentDescription(showSelection?"隐藏选区，保留修补":"显示选区");eyeButton.setTooltipText(eyeButton.getContentDescription());visibility.setText(showSelection?"隐藏选区":"显示选区");visibility.setEnabled(available);
        selectionButton.setEnabled(!rendering&&!adjusting&&!dragging);newButton.setEnabled(!rendering&&!adjusting&&!dragging&&edits.patches().size()<PhotoLocalEdits.MAX_PATCHES);sampleButton.setEnabled(available);sampleButton.setSelected(available);moreButton.setEnabled(!adjusting&&!dragging);
        updating=true;featherSlider.setEnabled(available);blendSlider.setEnabled(available);if(p!=null){featherSlider.setProgress((int)Math.round(p.feather()*100));blendSlider.setProgress((int)Math.round(p.blend*100));}featherValue.setText(featherSlider.getProgress()+"%");blendValue.setText(blendSlider.getProgress()+"%");updating=false;
        boolean pending=false;for(PhotoPatch repair:edits.patches())if(repair.enabled&&!repair.hasEffect())pending=true;
        apply.setEnabled(!rendering&&!adjusting&&!dragging&&selectionDialog==null&&!pending);apply.setAlpha(apply.isEnabled()?1:.45f);
        hint.setText(!available?"先圈选要修补的区域":coverage.right-coverage.left>.999&&coverage.bottom-coverage.top>.999?"请缩小选区，为干净取样区域留出空间":p.dx==0&&p.dy==0?"拖动选区到干净位置 · 双指缩放和移动":"拖动取样区微调 · 双指缩放和移动");photo.invalidate();
    }
    private void cancelGesture(){
        boolean change=false;if(gestureStart!=null){edits=gestureStart.edits;selected=gestureStart.selected;gestureStart=null;change=true;}if(sliderStart!=null){edits=sliderStart.edits;selected=sliderStart.selected;sliderStart=null;change=true;}dragging=adjusting=false;photo.tracking=false;
        if(!disposed){if(change){rebuildMask();changed(false);}else refresh();}
    }
    @Override public void onWindowFocusChanged(boolean focused){super.onWindowFocusChanged(focused);if(!focused&&photo!=null)cancelGesture();}
    @Override public void dismiss(){if(!disposed){disposed=true;if(selectionDialog!=null)selectionDialog.dismiss();queue.close();worker.shutdownNow();if(rendered!=null){rendered.recycle();rendered=null;}if(mask!=null){mask.recycle();mask=null;}}super.dismiss();}

    private final class PhotoCanvas extends View{
        final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);final RectF frame=new RectF();final ScaleGestureDetector scale;
        float zoom=1,panX,panY,lastX,lastY;double downX,downY,startDX,startDY;boolean tracking,navigating;
        PhotoCanvas(){super(PhotoPatchDialog.this.getContext());setTag("patch-photo");setContentDescription("修补照片，拖动选区选择干净取样位置，双指缩放移动");setFocusable(true);scale=new ScaleGestureDetector(getContext(),new ScaleGestureDetector.SimpleOnScaleGestureListener(){public boolean onScale(ScaleGestureDetector d){zoom=Math.max(1,Math.min(4,zoom*d.getScaleFactor()));bounds();invalidate();return true;}});}
        void resetViewport(){zoom=1;panX=panY=0;bounds();invalidate();}
        void bounds(){float fit=Math.min(getWidth()/(float)initial.getWidth(),getHeight()/(float)initial.getHeight()),w=initial.getWidth()*fit*zoom,h=initial.getHeight()*fit*zoom;panX=Math.max(-Math.max(0,(w-getWidth())/2),Math.min(Math.max(0,(w-getWidth())/2),panX));panY=Math.max(-Math.max(0,(h-getHeight())/2),Math.min(Math.max(0,(h-getHeight())/2),panY));float x=(getWidth()-w)/2+panX,y=(getHeight()-h)/2+panY;frame.set(x,y,x+w,y+h);}
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);if(disposed)return;bounds();Bitmap image=rendered==null?initial:rendered;ink.setAlpha(255);ink.setStyle(Paint.Style.FILL);canvas.drawBitmap(image,null,frame,ink);PhotoPatch p=patch();if(p==null||mask==null||!showSelection||adjusting)return;int save=canvas.save();canvas.clipRect(frame);canvas.drawBitmap(mask,null,frame,ink);
            float dx=(float)(p.dx*frame.width()),dy=(float)(p.dy*frame.height());if(p.dx!=0||p.dy!=0){ink.setAlpha(150);canvas.save();canvas.translate(dx,dy);canvas.drawBitmap(mask,null,frame,ink);canvas.restore();ink.setAlpha(255);}
            RectF target=new RectF((float)(frame.left+coverage.left*frame.width()),(float)(frame.top+coverage.top*frame.height()),(float)(frame.left+coverage.right*frame.width()),(float)(frame.top+coverage.bottom*frame.height()));RectF source=new RectF(target);source.offset(dx,dy);
            ink.setStyle(Paint.Style.STROKE);ink.setStrokeWidth(dp(1));ink.setColor(0xb3fff1e4);canvas.drawRect(target,ink);if(p.dx!=0||p.dy!=0){ink.setColor(YELLOW);ink.setPathEffect(new DashPathEffect(new float[]{dp(4),dp(3)},0));canvas.drawRect(source,ink);ink.setPathEffect(null);canvas.drawLine(target.centerX(),target.centerY(),source.centerX(),source.centerY(),ink);}
            ink.setStyle(Paint.Style.FILL);label(canvas,"修补区",target.left,target.top,TEXT);if(p.dx!=0||p.dy!=0)label(canvas,"取样",source.left,source.top,YELLOW);canvas.restoreToCount(save);
        }
        void label(Canvas c,String label,float x,float y,int colour){ink.setTextSize(sp(11));float width=ink.measureText(label)+dp(12),height=sp(15)+dp(6);x=Math.max(frame.left,Math.min(frame.right-width,x));y=Math.max(frame.top+height,Math.min(frame.bottom,y));ink.setColor(0xcc191e17);c.drawRoundRect(x,y-height,x+width,y,dp(4),dp(4),ink);ink.setColor(colour);c.drawText(label,x+dp(6),y-dp(4),ink);}
        @Override public boolean onTouchEvent(MotionEvent e){if(disposed||adjusting)return false;bounds();int action=e.getActionMasked();scale.onTouchEvent(e);
            if(e.getPointerCount()>1){if(!navigating){cancelGesture();navigating=true;lastX=(e.getX(0)+e.getX(1))/2;lastY=(e.getY(0)+e.getY(1))/2;}float x=(e.getX(0)+e.getX(1))/2,y=(e.getY(0)+e.getY(1))/2;if(action==MotionEvent.ACTION_MOVE){panX+=x-lastX;panY+=y-lastY;bounds();}lastX=x;lastY=y;invalidate();return true;}
            if(navigating){if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL)navigating=false;return true;}
            PhotoPatch p=patch();if(p==null||coverage==null)return false;
            if(action==MotionEvent.ACTION_DOWN){if(!frame.contains(e.getX(),e.getY()))return false;gestureStart=snapshot();tracking=dragging=true;downX=(e.getX()-frame.left)/frame.width();downY=(e.getY()-frame.top)/frame.height();startDX=p.dx;startDY=p.dy;refresh();getParent().requestDisallowInterceptTouchEvent(true);return true;}
            if(!tracking)return true;
            if(action==MotionEvent.ACTION_CANCEL){cancelGesture();getParent().requestDisallowInterceptTouchEvent(false);return true;}
            if(action==MotionEvent.ACTION_MOVE||action==MotionEvent.ACTION_UP){double dx=startDX+(e.getX()-frame.left)/frame.width()-downX,dy=startDY+(e.getY()-frame.top)/frame.height()-downY;PhotoPatch next=clamp(p,dx,dy);if(!next.equals(p)){edits=edits.withPatch(selected,next);changed(action!=MotionEvent.ACTION_UP);}if(action==MotionEvent.ACTION_UP){tracking=dragging=false;remember(gestureStart);gestureStart=null;changed(false);getParent().requestDisallowInterceptTouchEvent(false);performClick();}return true;}return true;
        }
        @Override public boolean performClick(){super.performClick();return true;}
    }
    private static final class State{final PhotoLocalEdits edits;final int selected;State(PhotoLocalEdits e,int s){edits=e;selected=s;}}
    private Button button(String label,Runnable action){Button b=new Button(getContext());b.setText(label);b.setTextSize(12);b.setAllCaps(false);b.setTextColor(TEXT);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setIncludeFontPadding(false);b.setPadding(dp(4),0,dp(4),0);b.setStateListAnimator(null);b.setBackgroundColor(Color.TRANSPARENT);b.setOnClickListener(v->action.run());return b;}
    private TextView text(String label,float size,int color){TextView v=new TextView(getContext());v.setText(label);v.setTextSize(size);v.setTextColor(color);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.HORIZONTAL);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private LinearLayout column(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.VERTICAL);return v;}
    private int dp(float value){return Math.round(value*activity.getResources().getDisplayMetrics().density);}
    private float sp(float value){return value*activity.getResources().getDisplayMetrics().scaledDensity;}
}
