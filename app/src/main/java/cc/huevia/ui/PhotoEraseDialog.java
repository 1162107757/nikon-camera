package cc.huevia.ui;

import android.app.*;
import android.graphics.*;
import android.graphics.drawable.Drawable;
import android.os.*;
import android.view.*;
import android.widget.*;
import cc.huevia.ncp.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;
import java.util.function.Function;

/** Latest-only actual repair while painting; one completed gesture remains one tentative edit. */
public final class PhotoEraseDialog extends Dialog {
    private static final int TEXT=0xfff4f5f7, MUTED=PhotoPrismaStyle.MUTED;
    private final Activity activity;
    private final Bitmap initial;
    private final PhotoPatchDialog.Renderer renderer;
    private final Consumer<PhotoLocalEdits> commit;
    private final AdjustmentRegion seed;
    private final Function<Bitmap,Bitmap> guideFactory=PhotoEraseDialog::copyGuide;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"photo-auto-erase");t.setDaemon(true);return t;});
    private final ArrayDeque<State> undo=new ArrayDeque<>(),redo=new ArrayDeque<>();
    private PhotoLocalEdits edits;
    private int selected;
    private Bitmap rendered,liveFrame;
    private final PhotoCanvas photo;
    private Button apply,undoButton,redoButton,moreButton;
    private TextView status,sizeValue;
    private SeekBar sizeSlider;
    private LinearLayout body,panel;
    private FrameLayout stage;
    private ScrollView dock;
    private ViewGroup sizeGuideHost;
    private final BrushSizeGuide sizeGuide=new BrushSizeGuide();
    private Future<?> job;
    private PhotoPatchDialog manualDialog;
    private volatile long generation;
    private volatile boolean disposed;
    private boolean busy,adjusting,previewRunning,pumpScheduled;
    private long sequence,lastAppliedSequence,lastPreviewStarted;
    private State strokeBefore;
    private Guide strokeGuide;
    private AdjustmentRegion strokeRegion;
    private double strokeRadius;
    private Request pendingRequest;
    private final Runnable previewPump=this::pumpPreview;
    private double radius=.025;

    public PhotoEraseDialog(Activity activity,Bitmap image,PhotoLocalEdits edits,AdjustmentRegion seed,
                            PhotoPatchDialog.Renderer renderer,Consumer<PhotoLocalEdits> commit) {
        super(activity,cc.huevia.R.style.AppThemeDark);
        if(image==null||image.isRecycled()||edits==null||renderer==null||commit==null)throw new IllegalArgumentException("消除参数无效。");
        this.activity=activity;initial=image;this.edits=edits;this.seed=seed;this.renderer=renderer;this.commit=commit;
        selected=edits.patches().size()-1;photo=new PhotoCanvas();
    }
    public PhotoLocalEdits settings(){return edits;}
    @Override protected void onCreate(Bundle state){
        super.onCreate(state);requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout root=column();root.setTag("erase-workspace");LinearLayout header=row();header.setPadding(dp(4),0,dp(8),0);
        header.addView(PhotoWorkspaceUi.icon(getContext(),"close","取消本次修补","erase-cancel",this::dismiss),new LinearLayout.LayoutParams(dp(48),dp(52)));
        TextView title=text("修补",16,TEXT);title.setGravity(Gravity.CENTER);header.addView(title,new LinearLayout.LayoutParams(0,dp(52),1));
        apply=button("完成",()->{if(apply.isEnabled()){commit.accept(edits);dismiss();}});apply.setTag("erase-apply");PhotoPrismaStyle.primary(apply);header.addView(apply,new LinearLayout.LayoutParams(dp(76),dp(52)));root.addView(header);
        body=column();root.addView(body,new LinearLayout.LayoutParams(-1,0,1));stage=new FrameLayout(getContext());stage.setTag("erase-stage");stage.addView(photo,new FrameLayout.LayoutParams(-1,-1));body.addView(stage,new LinearLayout.LayoutParams(-1,0,1));
        panel=column();panel.setPadding(dp(12),0,dp(12),dp(8));panel.setTag("erase-panel");LinearLayout history=row();
        undoButton=PhotoWorkspaceUi.icon(getContext(),"undo","撤销上一笔消除","erase-undo",this::undo);
        redoButton=PhotoWorkspaceUi.icon(getContext(),"redo","重做消除","erase-redo",this::redo);
        for(Button b:new Button[]{undoButton,redoButton})history.addView(b,new LinearLayout.LayoutParams(dp(48),dp(48)));
        View space=new View(getContext());history.addView(space,new LinearLayout.LayoutParams(0,1,1));
        moreButton=PhotoWorkspaceUi.icon(getContext(),"more","更多修补操作","erase-more",this::more);history.addView(moreButton,new LinearLayout.LayoutParams(dp(48),dp(48)));panel.addView(history);
        LinearLayout size=row();size.addView(text("画笔大小",12,MUTED),new LinearLayout.LayoutParams(dp(72),dp(48)));
        sizeSlider=new SeekBar(getContext());sizeSlider.setTag("erase-size");sizeSlider.setMax(99);sizeSlider.setProgress(24);PhotoPrismaStyle.slider(activity,sizeSlider);size.addView(sizeSlider,new LinearLayout.LayoutParams(0,dp(48),1));
        sizeValue=text("25",12,TEXT);sizeValue.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);size.addView(sizeValue,new LinearLayout.LayoutParams(dp(36),dp(48)));panel.addView(size);
        sizeSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onStartTrackingTouch(SeekBar b){adjusting=true;refresh();}
            public void onProgressChanged(SeekBar b,int p,boolean user){radius=(p+1)/1000.0;sizeValue.setText(Integer.toString(p+1));b.setContentDescription("画笔大小，"+(p+1));sizeGuide.invalidateSelf();}
            public void onStopTrackingTouch(SeekBar b){adjusting=false;refresh();}
        });sizeSlider.setContentDescription("画笔大小，25");
        status=text("涂抹即可修补",12,MUTED);status.setTag("erase-status");status.setGravity(Gravity.CENTER);status.setMinHeight(dp(28));status.setPadding(dp(4),dp(4),dp(4),dp(4));panel.addView(status,new LinearLayout.LayoutParams(-1,-2));
        dock=new ScrollView(getContext());dock.setTag("erase-controls-scroll");dock.setVerticalScrollBarEnabled(false);dock.addView(panel);body.addView(dock,new LinearLayout.LayoutParams(-1,-2));
        body.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->arrange());
        root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){Insets safe=insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());root.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else root.setPadding(insets.getStableInsetLeft(),insets.getStableInsetTop(),insets.getStableInsetRight(),insets.getStableInsetBottom());body.post(this::arrange);return insets;});
        sizeGuideHost=root;root.getOverlay().add(sizeGuide);root.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->sizeGuide.setBounds(0,0,r-l,b-t));
        PhotoPrismaStyle.workspace(root,initial);setContentView(root);if(getWindow()!=null){getWindow().setBackgroundDrawableResource(android.R.color.transparent);getWindow().setLayout(-1,-1);}root.requestApplyInsets();
        refresh();
        if(seed!=null&&seed.hasSelection())main.post(()->erase(seed));
    }
    @Override public void show(){super.show();if(getWindow()!=null)getWindow().setLayout(-1,-1);}
    private void arrange(){
        if(disposed||body.getHeight()<2)return;int w=body.getWidth(),h=body.getHeight();boolean side=w>h&&w>=dp(480);
        int orientation=side?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL;if(body.getOrientation()!=orientation)body.setOrientation(orientation);
        LinearLayout.LayoutParams sp=(LinearLayout.LayoutParams)stage.getLayoutParams();int sw=side?0:-1,sh=side?-1:0;
        if(sp.width!=sw||sp.height!=sh||sp.weight!=1)stage.setLayoutParams(new LinearLayout.LayoutParams(sw,sh,1));
        int dw=side?Math.min(dp(320),Math.round(w*.44f)):-1,dh=side?-1:Math.min(dp(140+32*(Math.max(1,activity.getResources().getConfiguration().fontScale)-1)),h/2);
        LinearLayout.LayoutParams cp=(LinearLayout.LayoutParams)dock.getLayoutParams();if(cp.width!=dw||cp.height!=dh)dock.setLayoutParams(new LinearLayout.LayoutParams(dw,dh));photo.invalidate();
    }
    private State snapshot(){return new State(edits,selected);}
    private static Bitmap copyGuide(Bitmap source){
        double scale=Math.min(1,384.0/Math.max(source.getWidth(),source.getHeight()));
        Bitmap scaled=Bitmap.createScaledBitmap(source,Math.max(2,(int)Math.round(source.getWidth()*scale)),Math.max(2,(int)Math.round(source.getHeight()*scale)),true);
        return scaled==source?source.copy(Bitmap.Config.ARGB_8888,false):scaled;
    }
    private void erase(AdjustmentRegion selection){
        if(!beginStroke())return;
        PhotoPatch seeded=PhotoPatch.create(selection);
        AdjustmentRegion soft=seeded.feather(Math.max(.35,seeded.feather())).selection;
        busy=true;photo.pending=true;queue(soft,true);status.setText("正在完成修补…");refresh();
    }
    private boolean beginStroke(){
        if(disposed||busy)return false;
        if(edits.patches().size()>=PhotoLocalEdits.MAX_PATCHES){status.setText("修补已达上限，可撤销或删除后重试");return false;}
        Bitmap guide=null;
        try{
            guide=guideFactory.apply(rendered==null?initial:rendered);if(guide==null)throw new OutOfMemoryError();
            int w=guide.getWidth(),h=guide.getHeight();int[] pixels=new int[w*h];guide.getPixels(pixels,0,w,0,0,w,h);
            generation++;strokeGuide=new Guide(pixels,w,h);strokeBefore=snapshot();strokeRegion=AdjustmentRegion.create("涂抹修补");strokeRadius=radius;
            status.setText("涂抹即可修补");return true;
        }catch(RuntimeException|OutOfMemoryError failure){status.setText("暂时无法修补，请稍后重试");photo.clearStroke();refresh();return false;}
        finally{recycle(guide);}
    }
    private void queuePaint(boolean terminal){
        if(strokeGuide==null||photo.points.isEmpty())return;
        double[] p=new double[photo.points.size()];for(int i=0;i<p.length;i++)p[i]=photo.points.get(i);
        try{queue(strokeRegion.addStroke(PhotoPatchSampler.automaticStroke(p,strokeRadius)),terminal);}
        catch(IllegalArgumentException failure){abortStroke();status.setText("本笔未修补，请缩小范围重试");}
    }
    private void queue(AdjustmentRegion selection,boolean terminal){
        pendingRequest=new Request(generation,++sequence,strokeBefore,strokeGuide,selection,terminal);
        schedulePreview();
    }
    private void schedulePreview(){
        if(disposed||previewRunning||pumpScheduled||pendingRequest==null)return;
        pumpScheduled=true;main.postDelayed(previewPump,pendingRequest.terminal?0:Math.max(0,48-(SystemClock.uptimeMillis()-lastPreviewStarted)));
    }
    private void pumpPreview(){
        pumpScheduled=false;if(disposed||previewRunning||pendingRequest==null)return;
        Request request=pendingRequest;pendingRequest=null;previewRunning=true;lastPreviewStarted=SystemClock.uptimeMillis();
        job=worker.submit(()->{
            Bitmap frame=null;PhotoLocalEdits next=null;Throwable failure=null;
            try{
                PhotoPatch repair=PhotoPatchSampler.choose(request.guide.pixels,request.guide.width,request.guide.height,request.selection,
                        ()->disposed||request.token!=generation||Thread.currentThread().isInterrupted()).contextBlend(true);
                if(disposed||request.token!=generation)throw new java.io.InterruptedIOException("修补已取消");
                next=request.before.edits.addPatch(repair);frame=renderer.render(next,!request.terminal);
                if(frame==null||frame.isRecycled())throw new java.io.IOException("修补预览不可用");
            }catch(Exception|OutOfMemoryError error){failure=error;recycle(frame);frame=null;}
            Bitmap result=frame;PhotoLocalEdits resultEdits=next;Throwable error=failure;
            main.post(()->completePreview(request,resultEdits,result,error));
        });
    }
    private void completePreview(Request request,PhotoLocalEdits next,Bitmap frame,Throwable failure){
        previewRunning=false;
        if(disposed||request.token!=generation){recycle(frame);schedulePreview();return;}
        if(request.sequence<lastAppliedSequence){recycle(frame);schedulePreview();return;}
        if(failure!=null){
            if(request.terminal){abortStroke();status.setText("本笔未修补，请缩小范围重试");}
            else if(photo.tracking)status.setText("继续涂抹，或缩小修补范围");
        }else if(request.terminal){
            lastAppliedSequence=request.sequence;undo.push(request.before);trimUndo();redo.clear();accept(new State(next,next.patches().size()-1),frame);status.setText("可继续涂抹修补");
        }else{lastAppliedSequence=request.sequence;recycle(liveFrame);liveFrame=frame;photo.invalidate();}
        schedulePreview();
    }
    private void discardStroke(){
        pendingRequest=null;main.removeCallbacks(previewPump);pumpScheduled=false;strokeGuide=null;strokeBefore=null;strokeRegion=null;recycle(liveFrame);liveFrame=null;photo.clearStroke();
    }
    private void abortStroke(){generation++;discardStroke();busy=false;refresh();}
    private void accept(State next,Bitmap image){
        edits=next.edits;selected=next.selected;recycle(rendered);rendered=image;discardStroke();busy=false;refresh();
    }
    private void undo(){if(!busy&&!undo.isEmpty())moveHistory(undo,redo);}
    private void redo(){if(!busy&&!redo.isEmpty())moveHistory(redo,undo);}
    private void moveHistory(ArrayDeque<State> from,ArrayDeque<State> to){
        State next=from.peek(),before=snapshot();renderState(next,()->{from.pop();to.push(before);trimUndo();});
    }
    private void renderState(State next,Runnable success){
        if(disposed||busy)return;long token=++generation;discardStroke();busy=true;status.setText("正在更新…");refresh();
        job=worker.submit(()->{Bitmap image=null;try{
            image=renderer.render(next.edits,false);if(image==null||image.isRecycled())throw new java.io.IOException("修补预览不可用");Bitmap frame=image;image=null;
            main.post(()->{if(disposed||token!=generation){recycle(frame);return;}success.run();accept(next,frame);status.setText("涂抹即可修补");});
        }catch(Exception|OutOfMemoryError failure){main.post(()->{if(disposed||token!=generation)return;busy=false;status.setText("更新失败，原有修补已保留，请重试");refresh();});}finally{recycle(image);}});
    }
    private void trimUndo(){while(undo.size()>40)undo.removeLast();}
    private void more(){
        if(busy||photo.tracking)return;PopupMenu menu=new PopupMenu(getContext(),moreButton);
        menu.getMenu().add("适应照片").setOnMenuItemClickListener(i->{photo.resetViewport();return true;});
        menu.getMenu().add("删除上一处修补").setEnabled(!edits.patches().isEmpty()).setOnMenuItemClickListener(i->{State before=snapshot();PhotoLocalEdits next=edits.removePatch(edits.patches().size()-1);renderState(new State(next,next.patches().size()-1),()->{undo.push(before);trimUndo();redo.clear();});return true;});
        menu.getMenu().add("手动取样修补").setOnMenuItemClickListener(i->{manual();return true;});menu.show();
    }
    private void manual(){
        if(busy)return;photo.cancelStroke();final Bitmap image;
        try{image=(rendered==null?initial:rendered).copy(Bitmap.Config.ARGB_8888,false);if(image==null)throw new OutOfMemoryError();}
        catch(OutOfMemoryError failure){status.setText("暂时无法打开手动修补，请稍后重试");return;}
        State before=snapshot();PhotoPatchDialog dialog=new PhotoPatchDialog(activity,image,edits,null,renderer,next->{if(!disposed&&!next.equals(edits))renderState(new State(next,next.patches().size()-1),()->{undo.push(before);trimUndo();redo.clear();});});
        manualDialog=dialog;dialog.setOnDismissListener(v->{image.recycle();if(manualDialog==dialog)manualDialog=null;});dialog.show();
    }
    private void refresh(){
        if(apply==null)return;boolean idle=!busy&&!photo.tracking&&!photo.navigating&&!adjusting;apply.setEnabled(idle);apply.setAlpha(idle?1:.45f);
        undoButton.setEnabled(idle&&!undo.isEmpty());redoButton.setEnabled(idle&&!redo.isEmpty());moreButton.setEnabled(idle);sizeSlider.setEnabled(!busy&&!photo.tracking&&!photo.navigating);
        photo.invalidate();sizeGuide.invalidateSelf();
    }
    @Override public void onWindowFocusChanged(boolean focused){super.onWindowFocusChanged(focused);if(!focused&&photo!=null){photo.cancelStroke();adjusting=false;if(apply!=null)refresh();}}
    @Override public void dismiss(){if(!disposed){disposed=true;generation++;main.removeCallbacks(previewPump);pendingRequest=null;strokeGuide=null;if(sizeGuideHost!=null){sizeGuideHost.getOverlay().remove(sizeGuide);sizeGuideHost=null;}if(manualDialog!=null){manualDialog.dismiss();manualDialog=null;}if(job!=null)job.cancel(true);worker.shutdownNow();recycle(rendered);rendered=null;recycle(liveFrame);liveFrame=null;}super.dismiss();}
    private static void recycle(Bitmap image){if(image!=null&&!image.isRecycled())image.recycle();}
    private static final class State{final PhotoLocalEdits edits;final int selected;State(PhotoLocalEdits e,int s){edits=e;selected=s;}}
    private static final class Guide{final int[] pixels;final int width,height;Guide(int[] p,int w,int h){pixels=p;width=w;height=h;}}
    private static final class Request{final long token,sequence;final State before;final Guide guide;final AdjustmentRegion selection;final boolean terminal;Request(long t,long s,State b,Guide g,AdjustmentRegion r,boolean end){token=t;sequence=s;before=b;guide=g;selection=r;terminal=end;}}

    /** Window-centred size feedback, separate from the photograph and live repair renderer. */
    private final class BrushSizeGuide extends Drawable {
        private final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG);
        private int opacity=255;
        @Override public void draw(Canvas canvas){
            if(!adjusting||disposed||getBounds().isEmpty()||photo.getWidth()==0||photo.getHeight()==0)return;
            photo.bounds();float cx=getBounds().exactCenterX(),cy=getBounds().exactCenterY();
            float r=(float)(radius*Math.min(photo.frame.width(),photo.frame.height()));
            ink.setStyle(Paint.Style.STROKE);ink.setColor(0x99000000);ink.setAlpha(153*opacity/255);ink.setStrokeWidth(dp(3));canvas.drawCircle(cx,cy,r,ink);
            ink.setColor(TEXT);ink.setAlpha(opacity);ink.setStrokeWidth(dp(1.25f));canvas.drawCircle(cx,cy,r,ink);
            String value=Integer.toString(sizeSlider.getProgress()+1);ink.setStyle(Paint.Style.FILL);ink.setTextSize(12*activity.getResources().getDisplayMetrics().scaledDensity);
            Paint.FontMetrics metrics=ink.getFontMetrics();float tw=ink.measureText(value),height=metrics.descent-metrics.ascent+dp(8),top=cy+r+dp(10);
            RectF badge=new RectF(cx-tw/2-dp(10),top,cx+tw/2+dp(10),top+height);
            ink.setColor(0xb3191e17);ink.setAlpha(179*opacity/255);canvas.drawRoundRect(badge,dp(6),dp(6),ink);
            ink.setColor(TEXT);ink.setAlpha(opacity);canvas.drawText(value,cx-tw/2,top+dp(4)-metrics.ascent,ink);
        }
        @Override public void setAlpha(int value){opacity=Math.max(0,Math.min(255,value));invalidateSelf();}
        @Override public void setColorFilter(ColorFilter filter){ink.setColorFilter(filter);invalidateSelf();}
        @Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }

    private final class PhotoCanvas extends View {
        final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);final RectF frame=new RectF();
        final ArrayList<Double> points=new ArrayList<>();final ScaleGestureDetector scale;
        float zoom=1,panX,panY,lastX,lastY;boolean tracking,navigating;boolean pending;
        PhotoCanvas(){super(PhotoEraseDialog.this.getContext());setTag("erase-photo");setContentDescription("涂抹即可看到修补效果；双指缩放移动");setFocusable(true);scale=new ScaleGestureDetector(getContext(),new ScaleGestureDetector.SimpleOnScaleGestureListener(){public boolean onScale(ScaleGestureDetector d){zoom=Math.max(1,Math.min(4,zoom*d.getScaleFactor()));bounds();invalidate();return true;}});}
        void resetViewport(){zoom=1;panX=panY=0;bounds();invalidate();}
        void bounds(){float fit=Math.min(getWidth()/(float)initial.getWidth(),getHeight()/(float)initial.getHeight()),w=initial.getWidth()*fit*zoom,h=initial.getHeight()*fit*zoom;panX=Math.max(-Math.max(0,(w-getWidth())/2),Math.min(Math.max(0,(w-getWidth())/2),panX));panY=Math.max(-Math.max(0,(h-getHeight())/2),Math.min(Math.max(0,(h-getHeight())/2),panY));frame.set((getWidth()-w)/2+panX,(getHeight()-h)/2+panY,(getWidth()+w)/2+panX,(getHeight()+h)/2+panY);}
        void clearStroke(){points.clear();tracking=pending=false;invalidate();}
        void cancelStroke(){if(tracking){abortStroke();getParent().requestDisallowInterceptTouchEvent(false);}}
        void add(float x,float y){
            double nx=Math.max(0,Math.min(1,(x-frame.left)/frame.width())),ny=Math.max(0,Math.min(1,(y-frame.top)/frame.height()));int n=points.size();
            if(n>=2&&Math.hypot((nx-points.get(n-2))*initial.getWidth(),(ny-points.get(n-1))*initial.getHeight())<.001*Math.min(initial.getWidth(),initial.getHeight()))return;
            if(points.size()/2>=PhotoPortrait.MAX_STROKE_POINTS){ArrayList<Double> reduced=new ArrayList<>();for(int i=0;i<points.size();i+=4){reduced.add(points.get(i));reduced.add(points.get(i+1));}reduced.add(points.get(points.size()-2));reduced.add(points.get(points.size()-1));points.clear();points.addAll(reduced);}
            points.add(nx);points.add(ny);
        }
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);if(disposed)return;bounds();ink.setAlpha(255);canvas.drawBitmap(liveFrame!=null?liveFrame:rendered==null?initial:rendered,null,frame,ink);}
        @Override public boolean onTouchEvent(MotionEvent e){
            if(disposed||busy||adjusting)return false;bounds();int action=e.getActionMasked();scale.onTouchEvent(e);
            if(e.getPointerCount()>1){if(!navigating){navigating=true;cancelStroke();lastX=(e.getX(0)+e.getX(1))/2;lastY=(e.getY(0)+e.getY(1))/2;refresh();}float x=(e.getX(0)+e.getX(1))/2,y=(e.getY(0)+e.getY(1))/2;if(action==MotionEvent.ACTION_MOVE){panX+=x-lastX;panY+=y-lastY;bounds();}lastX=x;lastY=y;invalidate();return true;}
            if(navigating){if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL){navigating=false;refresh();}return true;}
            if(action==MotionEvent.ACTION_DOWN){if(!frame.contains(e.getX(),e.getY()))return false;clearStroke();if(!beginStroke())return true;tracking=true;add(e.getX(),e.getY());getParent().requestDisallowInterceptTouchEvent(true);queuePaint(false);refresh();return true;}
            if(!tracking)return true;if(action==MotionEvent.ACTION_CANCEL){cancelStroke();refresh();return true;}
            if(action==MotionEvent.ACTION_MOVE||action==MotionEvent.ACTION_UP){for(int i=0;i<e.getHistorySize();i++)add(e.getHistoricalX(i),e.getHistoricalY(i));add(e.getX(),e.getY());if(action==MotionEvent.ACTION_MOVE)queuePaint(false);}
            if(action==MotionEvent.ACTION_UP){tracking=false;pending=true;busy=true;getParent().requestDisallowInterceptTouchEvent(false);performClick();queuePaint(true);if(busy)status.setText("正在完成这一笔…");refresh();}return true;
        }
        @Override public boolean performClick(){super.performClick();return true;}
    }
    private Button button(String label,Runnable action){Button b=new Button(getContext());b.setText(label);b.setTextSize(12);b.setAllCaps(false);b.setTextColor(TEXT);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setIncludeFontPadding(false);b.setPadding(dp(4),0,dp(4),0);b.setStateListAnimator(null);b.setBackgroundColor(Color.TRANSPARENT);b.setOnClickListener(v->action.run());return b;}
    private TextView text(String label,float size,int color){TextView v=new TextView(getContext());v.setText(label);v.setTextSize(size);v.setTextColor(color);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.HORIZONTAL);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private LinearLayout column(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.VERTICAL);return v;}
    private int dp(float value){return Math.round(value*activity.getResources().getDisplayMetrics().density);}
}
