package cc.huevia.ui;

import android.app.*;
import android.content.res.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import cc.huevia.ncp.*;
import java.util.ArrayDeque;
import java.util.concurrent.*;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;

/** Source-based cleanup analysis stays tentative until the complete workspace is applied. */
public final class PhotoCleanupDialog extends Dialog {
    public interface Analyzer { PhotoCleanup.Analysis analyze(BooleanSupplier cancelled)throws Exception; }
    public interface Renderer { Bitmap render(PhotoAdjustments settings,boolean interactive)throws Exception; }
    private static final int TEXT=0xfff4f5f7,MUTED=PhotoPrismaStyle.MUTED,ACCENT=PhotoPrismaStyle.YELLOW,BG=Color.TRANSPARENT;
    private final Activity activity;
    private final Bitmap initial;
    private final String scopeLabel;
    private final Analyzer analyzer;
    private final Consumer<PhotoAdjustments> commit;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ThreadPoolExecutor analysisWorker=worker("photo-cleanup-analysis"),previewWorker=worker("photo-cleanup-preview");
    private final LatestPreviewQueue<PhotoAdjustments,Bitmap> previewQueue;
    private final ArrayDeque<PhotoCleanup> history=new ArrayDeque<>(),redo=new ArrayDeque<>();
    private final SeekBar[] sliders=new SeekBar[3];
    private final TextView[] values=new TextView[3];
    private PhotoAdjustments settings;
    private PhotoCleanup gestureOrigin;
    private PhotoImageView photo;
    private Bitmap rendered;
    private TextView status;
    private Button apply,undoButton,redoButton,compareButton,advancedToggle,analyzeButton;
    private LinearLayout advancedPanel;
    private ScrollView controlsPane;
    private AlertDialog exactDialog;
    private boolean updating,dragging,comparing,analysisRunning,analysisError,previewError,previewReady=true,expanded,landscape;
    private volatile boolean disposed;
    private volatile int analysisRequest;
    private final Runnable compareEnd=()->setComparing(false);

    public PhotoCleanupDialog(Activity activity,Bitmap initial,PhotoAdjustments settings,String scopeLabel,Analyzer analyzer,Renderer renderer,Consumer<PhotoAdjustments> commit){
        super(activity,cc.huevia.R.style.AppThemeDark);this.activity=activity;this.initial=initial;this.settings=settings;this.scopeLabel=scopeLabel;this.analyzer=analyzer;this.commit=commit;
        previewQueue=new LatestPreviewQueue<>(previewWorker,task->main.post(task),renderer::render,new LatestPreviewQueue.Listener<PhotoAdjustments,Bitmap>(){
            public void frame(PhotoAdjustments value,Bitmap image,boolean interactive,boolean latest){if(disposed){image.recycle();return;}rendered=image;if(!comparing)photo.setPhotoPreservingTransform(image);if(latest&&!interactive){previewReady=true;previewError=false;availability();}}
            public void discard(Bitmap image){image.recycle();}
            public void error(Throwable error){if(disposed)return;previewReady=false;previewError=true;availability();}
        });
    }
    private final PhotoSelectionOverlay selectionOverlay=new PhotoSelectionOverlay();
    public void setSelectionMask(Bitmap owned){selectionOverlay.setMask(owned);}
    private Runnable paintRequest;
    private String paintScope="全图";
    public void setPaintRequest(String scope,Runnable request){paintScope=scope==null?"全图":scope;paintRequest=request;}
    public PhotoAdjustments settings(){return settings;}
    private static ThreadPoolExecutor worker(String name){return new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<>(1),r->{Thread t=new Thread(r,name);t.setDaemon(true);return t;},new ThreadPoolExecutor.DiscardOldestPolicy());}

    @Override protected void onCreate(Bundle saved){
        super.onCreate(saved);requestWindowFeature(Window.FEATURE_NO_TITLE);LinearLayout root=column();root.setTag("cleanup-workspace");root.setBackgroundColor(0xff0e0d0c);
        LinearLayout top=row();Button cancel=button("取消",this::dismiss);cancel.setTag("cleanup-cancel");top.addView(cancel,new LinearLayout.LayoutParams(dp(64),dp(48)));if(paintRequest!=null){Button brush=PhotoWorkspaceUi.icon(getContext(),"brush","涂抹范围，当前"+paintScope,"cleanup-brush",()->{if(!disposed&&!dragging&&!analysisRunning)paintRequest.run();});top.addView(brush,new LinearLayout.LayoutParams(dp(48),dp(48)));}TextView title=text("去灰 · "+scopeLabel,16,TEXT);title.setSingleLine(true);title.setEllipsize(TextUtils.TruncateAt.END);title.setGravity(Gravity.CENTER);title.setContentDescription("去灰，作用范围："+scopeLabel);top.addView(title,new LinearLayout.LayoutParams(0,dp(48),1));apply=button("应用",()->{if(disposed||dragging||analysisRunning||!previewReady)return;commit.accept(settings);dismiss();});apply.setTag("cleanup-apply");apply.setTextColor(ACCENT);top.addView(apply,new LinearLayout.LayoutParams(dp(64),dp(48)));root.addView(top);
        landscape=activity.getResources().getConfiguration().orientation==Configuration.ORIENTATION_LANDSCAPE;LinearLayout body=new LinearLayout(getContext());body.setOrientation(landscape?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL);root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
        FrameLayout stage=new FrameLayout(getContext());stage.setTag("cleanup-stage");photo=new PhotoImageView(getContext());photo.setTag("cleanup-photo");photo.setPhoto(initial);photo.setContentDescription("去灰实时预览，可双指缩放");stage.addView(photo,new FrameLayout.LayoutParams(-1,-1));selectionOverlay.attach(stage,photo,"cleanup-selection-visibility");
        status=text("",12,MUTED);status.setTag("cleanup-status");status.setGravity(Gravity.CENTER);status.setMinHeight(dp(48));status.setFocusable(true);FrameLayout.LayoutParams statusPos=new FrameLayout.LayoutParams(-1,dp(48),Gravity.BOTTOM);statusPos.setMargins(dp(64),0,dp(64),0);stage.addView(status,statusPos);
        Button fit=iconButton(AppIcon.Kind.EXPAND,"适应屏幕",photo::resetZoom);fit.setTag("cleanup-fit");FrameLayout.LayoutParams fitPos=new FrameLayout.LayoutParams(dp(48),dp(48),Gravity.START|Gravity.BOTTOM);fitPos.setMargins(dp(8),0,0,dp(8));stage.addView(fit,fitPos);
        compareButton=iconButton(AppIcon.Kind.COMPARE,"按住对比本次调整前的效果",()->{setComparing(true);main.postDelayed(compareEnd,650);});compareButton.setTag("cleanup-compare");compareButton.setOnTouchListener((v,event)->{int a=event.getActionMasked();if(a==MotionEvent.ACTION_DOWN){setComparing(true);return true;}if(a==MotionEvent.ACTION_MOVE){if(event.getX()<0||event.getY()<0||event.getX()>=v.getWidth()||event.getY()>=v.getHeight())setComparing(false);return true;}if(a==MotionEvent.ACTION_UP||a==MotionEvent.ACTION_CANCEL||a==MotionEvent.ACTION_POINTER_DOWN||a==MotionEvent.ACTION_OUTSIDE){setComparing(false);return true;}return true;});compareButton.setOnKeyListener((v,key,event)->{if(key!=KeyEvent.KEYCODE_ENTER&&key!=KeyEvent.KEYCODE_DPAD_CENTER&&key!=KeyEvent.KEYCODE_SPACE)return false;setComparing(event.getAction()==KeyEvent.ACTION_DOWN);return true;});compareButton.setOnFocusChangeListener((v,focused)->{if(!focused)setComparing(false);});FrameLayout.LayoutParams comparePos=new FrameLayout.LayoutParams(dp(48),dp(48),Gravity.END|Gravity.BOTTOM);comparePos.setMargins(0,0,dp(8),dp(8));stage.addView(compareButton,comparePos);
        body.addView(stage,landscape?new LinearLayout.LayoutParams(0,-1,1):new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout controls=column();controls.setBackgroundColor(BG);controls.setPadding(dp(12),dp(4),dp(12),dp(8));addSlider(controls,0,"强度","cleanup-strength");
        LinearLayout tools=row();undoButton=iconButton(AppIcon.Kind.UNDO,"撤销去灰调整",()->history(false));undoButton.setTag("cleanup-undo");tools.addView(undoButton,new LinearLayout.LayoutParams(dp(48),dp(48)));redoButton=iconButton(AppIcon.Kind.REDO,"重做去灰调整",()->history(true));redoButton.setTag("cleanup-redo");tools.addView(redoButton,new LinearLayout.LayoutParams(dp(48),dp(48)));TextView hint=text("按住画面右下角对比",11,MUTED);hint.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);hint.setGravity(Gravity.CENTER);tools.addView(hint,new LinearLayout.LayoutParams(0,dp(48),1));Button reset=iconButton(AppIcon.Kind.REFRESH,"重置去灰",()->edit(PhotoCleanup.NONE));reset.setTag("cleanup-reset");tools.addView(reset,new LinearLayout.LayoutParams(dp(48),dp(48)));controls.addView(tools);
        advancedToggle=button("高级",()->{if(dragging)endGesture(true);expanded=!expanded;advancedPanel.setVisibility(expanded?View.VISIBLE:View.GONE);advancedToggle.setText(expanded?"收起高级":"高级");advancedToggle.setContentDescription(expanded?"收起高级去灰设置":"展开高级去灰设置");resizeControls();});advancedToggle.setTag("cleanup-advanced");controls.addView(advancedToggle,new LinearLayout.LayoutParams(-1,dp(48)));
        advancedPanel=column();advancedPanel.setTag("cleanup-advanced-panel");advancedPanel.setVisibility(View.GONE);addSlider(advancedPanel,1,"去灰雾","cleanup-haze");addSlider(advancedPanel,2,"降噪","cleanup-noise");analyzeButton=button("重新分析",this::startAnalysis);analyzeButton.setTag("cleanup-analyze");analyzeButton.setTextColor(ACCENT);advancedPanel.addView(analyzeButton,new LinearLayout.LayoutParams(-1,dp(48)));controls.addView(advancedPanel);
        controlsPane=new ScrollView(getContext());controlsPane.setFillViewport(false);controlsPane.setOverScrollMode(View.OVER_SCROLL_IF_CONTENT_SCROLLS);controlsPane.addView(controls);body.addView(controlsPane,landscape?new LinearLayout.LayoutParams(dp(320),-1):new LinearLayout.LayoutParams(-1,dp(156)));
        root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){Insets safe=insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());root.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else root.setPadding(insets.getStableInsetLeft(),insets.getStableInsetTop(),insets.getStableInsetRight(),insets.getStableInsetBottom());return insets;});
        PhotoPrismaStyle.workspace(root,initial);setContentView(root);if(getWindow()!=null){getWindow().setBackgroundDrawableResource(android.R.color.transparent);getWindow().setLayout(-1,-1);}root.requestApplyInsets();refresh();if(settings.cleanup.analysis==null)startAnalysis();else changed();
    }
    private void addSlider(LinearLayout parent,int axis,String label,String tag){
        LinearLayout line=row();line.addView(text(label,12,TEXT),new LinearLayout.LayoutParams(dp(axis==0?42:56),dp(48)));
        SeekBar slider=new SeekBar(getContext()){
            private boolean interrupted;
            @Override public boolean onTouchEvent(MotionEvent event){int a=event.getActionMasked();if(a==MotionEvent.ACTION_DOWN)interrupted=false;if(a==MotionEvent.ACTION_CANCEL||a==MotionEvent.ACTION_POINTER_DOWN){endGesture(true);MotionEvent cancel=MotionEvent.obtain(event);cancel.setAction(MotionEvent.ACTION_CANCEL);super.onTouchEvent(cancel);cancel.recycle();interrupted=true;}if(interrupted){if(a==MotionEvent.ACTION_UP||a==MotionEvent.ACTION_CANCEL)setPressed(false);return true;}return super.onTouchEvent(event);}
        };slider.setTag(tag);slider.setMax(100);slider.setKeyProgressIncrement(1);slider.setProgressTintList(ColorStateList.valueOf(ACCENT));slider.setThumbTintList(ColorStateList.valueOf(ACCENT));sliders[axis]=slider;line.addView(slider,new LinearLayout.LayoutParams(0,dp(48),1));TextView value=text("",12,ACCENT);values[axis]=value;value.setTag("cleanup-value-"+axis);value.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);value.setFocusable(true);value.setClickable(true);value.setOnClickListener(v->exact(axis));line.addView(value,new LinearLayout.LayoutParams(dp(48),dp(48)));parent.addView(line);
        slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar s,int p,boolean user){if(user&&!updating&&!analysisRunning&&settings.cleanup.analysis!=null){PhotoCleanup next=withAxis(settings.cleanup,axis,p);if(gestureOrigin==null)edit(next);else{settings=settings.withCleanup(next);changed();}}}public void onStartTrackingTouch(SeekBar s){beginGesture();}public void onStopTrackingTouch(SeekBar s){endGesture(false);}});
    }
    private void resizeControls(){if(controlsPane==null||landscape)return;LinearLayout.LayoutParams p=(LinearLayout.LayoutParams)controlsPane.getLayoutParams();p.height=expanded?Math.min(dp(312),Math.round(activity.getResources().getDisplayMetrics().heightPixels*.48f)):dp(156);controlsPane.setLayoutParams(p);}
    @Override public void show(){super.show();if(getWindow()!=null)getWindow().setLayout(-1,-1);}
    @Override public void dismiss(){dispose();super.dismiss();}
    @Override public void onWindowFocusChanged(boolean focused){super.onWindowFocusChanged(focused);if(!focused){setComparing(false);if(dragging){for(SeekBar slider:sliders)if(slider!=null){MotionEvent cancel=MotionEvent.obtain(SystemClock.uptimeMillis(),SystemClock.uptimeMillis(),MotionEvent.ACTION_CANCEL,0,0,0);slider.dispatchTouchEvent(cancel);cancel.recycle();}endGesture(true);}}}
    private void dispose(){if(disposed)return;disposed=true;selectionOverlay.close();analysisRequest++;main.removeCallbacks(compareEnd);previewQueue.close();analysisWorker.shutdownNow();previewWorker.shutdownNow();if(exactDialog!=null)exactDialog.dismiss();if(photo!=null)photo.setPhoto(null);rendered=null;gestureOrigin=null;}
    private void setComparing(boolean held){main.removeCallbacks(compareEnd);if(disposed||photo==null)return;comparing=held;selectionOverlay.setComparing(held);if(compareButton!=null)compareButton.setPressed(held);photo.setPhotoPreservingTransform(held?initial:rendered==null?initial:rendered);}
    private void startAnalysis(){
        if(disposed||analysisRunning)return;if(dragging)endGesture(true);setComparing(false);final int request=++analysisRequest;analysisRunning=true;analysisError=false;availability();
        analysisWorker.execute(()->{try{PhotoCleanup.Analysis result=analyzer.analyze(()->disposed||request!=analysisRequest||Thread.currentThread().isInterrupted());if(result==null)throw new IllegalStateException("无法分析画面");main.post(()->{if(disposed||request!=analysisRequest)return;analysisRunning=false;analysisError=false;edit(new PhotoCleanup(100,100,100,result));});}catch(Exception|OutOfMemoryError failure){main.post(()->{if(disposed||request!=analysisRequest)return;analysisRunning=false;analysisError=true;availability();});}});
    }
    private void cancelAnalysis(){analysisRequest++;analysisRunning=false;analysisError=false;}
    private void beginGesture(){if(disposed||analysisRunning||settings.cleanup.analysis==null)return;setComparing(false);if(gestureOrigin!=null)endGesture(true);gestureOrigin=settings.cleanup;dragging=true;selectionOverlay.setInteracting(true);}
    private void endGesture(boolean cancelled){if(gestureOrigin==null)return;PhotoCleanup before=gestureOrigin;gestureOrigin=null;dragging=false;selectionOverlay.setInteracting(false);if(cancelled)settings=settings.withCleanup(before);else if(!before.equals(settings.cleanup))remember(before);changed();}
    private void edit(PhotoCleanup next){if(disposed)return;if(gestureOrigin!=null)endGesture(true);cancelAnalysis();setComparing(false);if(next.equals(settings.cleanup)){refresh();return;}remember(settings.cleanup);settings=settings.withCleanup(next);changed();}
    private void remember(PhotoCleanup before){history.addLast(before);while(history.size()>64)history.removeFirst();redo.clear();}
    private void history(boolean forward){if(disposed)return;if(gestureOrigin!=null)endGesture(true);cancelAnalysis();ArrayDeque<PhotoCleanup> from=forward?redo:history,to=forward?history:redo;if(from.isEmpty()){refresh();return;}setComparing(false);to.addLast(settings.cleanup);settings=settings.withCleanup(from.removeLast());changed();}
    private void changed(){if(disposed)return;previewReady=false;previewError=false;refresh();previewQueue.offer(settings,dragging);}
    private void refresh(){if(sliders[0]==null)return;updating=true;for(int i=0;i<3;i++){int value=axis(settings.cleanup,i);sliders[i].setProgress(value);sliders[i].setContentDescription(new String[]{"去灰强度","去灰雾","降噪"}[i]+" "+value+"，范围0至100");values[i].setText(value+"%");values[i].setContentDescription(sliders[i].getContentDescription()+"，点击输入数值");}updating=false;availability();}
    private void availability(){
        if(status==null)return;boolean adjustable=!disposed&&!analysisRunning&&settings.cleanup.analysis!=null;for(int i=0;i<3;i++)if(sliders[i]!=null){sliders[i].setEnabled(adjustable);values[i].setEnabled(adjustable);values[i].setAlpha(adjustable?1:.4f);}undoButton.setEnabled(!history.isEmpty());redoButton.setEnabled(!redo.isEmpty());undoButton.setAlpha(undoButton.isEnabled()?1:.35f);redoButton.setAlpha(redoButton.isEnabled()?1:.35f);analyzeButton.setEnabled(!analysisRunning);apply.setEnabled(!disposed&&!analysisRunning&&!dragging&&previewReady);apply.setAlpha(apply.isEnabled()?1:.45f);
        status.setOnClickListener(null);if(analysisRunning)status.setText("正在分析画面…");else if(analysisError){status.setText("分析失败，点击重试");status.setOnClickListener(v->startAnalysis());}else if(previewError){status.setText("预览失败，点击重试");status.setOnClickListener(v->changed());}else if(!previewReady)status.setText(dragging?"":"预览中");else if(settings.cleanup.analysis==null){status.setText("未应用去灰，点击自动分析");status.setOnClickListener(v->startAnalysis());}else if(settings.cleanup.analysis.hazeConfidence==0&&settings.cleanup.analysis.noiseConfidence==0)status.setText("未发现明显灰雾或噪点");else status.setText("");status.setFocusable(status.hasOnClickListeners());status.setClickable(status.hasOnClickListeners());
    }
    private static int axis(PhotoCleanup p,int axis){return axis==0?p.amount:axis==1?p.haze:p.noise;}
    private static PhotoCleanup withAxis(PhotoCleanup p,int axis,int value){return axis==0?p.withAmount(value):axis==1?p.withHaze(value):p.withNoise(value);}
    private void exact(int axis){
        if(disposed||analysisRunning||settings.cleanup.analysis==null)return;if(dragging)endGesture(true);EditText input=new EditText(getContext());input.setTag("cleanup-exact-input");input.setInputType(InputType.TYPE_CLASS_NUMBER);input.setSingleLine(true);input.setText(String.valueOf(axis(settings.cleanup,axis)));input.selectAll();input.setContentDescription(new String[]{"去灰强度","去灰雾","降噪"}[axis]+"，范围0至100");LinearLayout form=column();form.setPadding(dp(20),0,dp(20),0);form.addView(input);AlertDialog d=new PhotoEditorTypography.Builder(getContext()).setTitle(new String[]{"去灰强度","去灰雾","降噪"}[axis]).setView(form).setNegativeButton("取消",null).setPositiveButton("应用",null).create();exactDialog=d;d.setOnDismissListener(v->{if(exactDialog==d)exactDialog=null;});d.setOnShowListener(v->d.getButton(-1).setOnClickListener(w->{try{int value=Integer.parseInt(input.getText().toString().trim());if(value<0||value>100)throw new IllegalArgumentException();edit(withAxis(settings.cleanup,axis,value));d.dismiss();}catch(IllegalArgumentException error){input.setError("请输入0至100的整数");}}));d.show();PhotoEditorTypography.apply(d);
    }
    private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
    private LinearLayout column(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.VERTICAL);return v;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(getContext());v.setGravity(Gravity.CENTER_VERTICAL);v.setBaselineAligned(false);return v;}
    private TextView text(String s,int size,int color){TextView v=new TextView(getContext());v.setText(s);v.setTextSize(size);v.setTextColor(color);v.setGravity(Gravity.CENTER_VERTICAL);v.setIncludeFontPadding(false);return v;}
    private Button button(String s,Runnable run){Button b=new Button(getContext());b.setText(s);b.setTextSize(12);b.setAllCaps(false);b.setTextColor(TEXT);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setPadding(dp(4),0,dp(4),0);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffe335),null,null));b.setOnClickListener(v->run.run());return b;}
    private Button iconButton(AppIcon.Kind kind,String label,Runnable run){Button b=button("",run);b.setContentDescription(label);b.setTooltipText(label);Drawable icon=new AppIcon(kind,TEXT,activity.getResources().getDisplayMetrics().density);LayerDrawable face=new LayerDrawable(new Drawable[]{icon});face.setLayerSize(0,dp(24),dp(24));face.setLayerGravity(0,Gravity.CENTER);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffe335),face,null));return b;}
}
