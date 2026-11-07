package cc.huevia.ui;

import android.app.*;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.*;
import android.os.*;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import cc.huevia.ncp.PhotoBodyShape;
import java.util.ArrayDeque;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** Body geometry is staged as one child transaction inside the portrait workspace. */
public final class PhotoBodyDialog extends Dialog {
    public interface Renderer { Bitmap render(PhotoBodyShape shape,boolean interactive)throws Exception; }
    private static final int TEXT=0xfff4f5f7,MUTED=PhotoPrismaStyle.MUTED,ACCENT=PhotoPrismaStyle.YELLOW;
    private static final String[] NAMES={"瘦身","瘦腿","腿部拉长"};
    private final Activity activity;
    private final Bitmap initial;
    private final Consumer<PhotoBodyShape> commit;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"portrait-body-preview");t.setDaemon(true);return t;});
    private final LatestPreviewQueue<PhotoBodyShape,Bitmap> queue;
    private final ArrayDeque<PhotoBodyShape> undo=new ArrayDeque<>(),redo=new ArrayDeque<>();
    private final Button[] tools=new Button[3];
    private final SeekBar[] boxSliders=new SeekBar[4];
    private final TextView[] boxValues=new TextView[4];
    private PhotoBodyShape shape,gestureStart;
    private PhotoBodyShape completed;
    private Bitmap rendered;
    private BodyCanvas photo;
    private TextView label,value,hint,status;
    private Button apply,undoButton,redoButton,guidesButton,singleButton,rangeButton,resetCurrentButton;
    private SeekBar strength;
    private LinearLayout body,rangePanel;
    private ScrollView controls;
    private FrameLayout stage;
    private AlertDialog exactDialog;
    private int tool;
    private boolean locating;
    private Bitmap analysisSource;
    private Button locateButton,protectionButton;
    private final java.util.concurrent.ExecutorService analysisWorker=java.util.concurrent.Executors.newSingleThreadExecutor();
    private boolean updating,dragging,guides=true,comparing,expanded,error;
    private volatile boolean disposed;
    private final Runnable compareEnd=()->setCompare(false);

    /** initial is borrowed and already contains the entering portrait state. */
    public PhotoBodyDialog(Activity activity,Bitmap initial,PhotoBodyShape shape,Renderer renderer,Consumer<PhotoBodyShape> commit){
        super(activity,cc.huevia.R.style.AppThemeDark);
        if(initial==null||initial.isRecycled()||shape==null||renderer==null||commit==null)throw new IllegalArgumentException("塑形预览参数无效。");
        this.activity=activity;this.initial=initial;this.analysisSource=initial;this.shape=shape;this.commit=commit;
        queue=new LatestPreviewQueue<>(worker,r->main.post(r),renderer::render,new LatestPreviewQueue.Listener<PhotoBodyShape,Bitmap>(){
            public void frame(PhotoBodyShape state,Bitmap image,boolean interactive,boolean latest){if(disposed){image.recycle();return;}rendered=image;photo.invalidate();if(latest&&!interactive&&state.equals(PhotoBodyDialog.this.shape)){completed=state;error=false;availability();}}
            public void discard(Bitmap image){image.recycle();}
            public void error(Throwable failure){if(disposed)return;completed=null;error=true;availability();}
        });
    }
    public PhotoBodyShape settings(){return shape;}

    @Override protected void onCreate(Bundle saved){
        super.onCreate(saved);requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout root=column();root.setTag("body-workspace");root.setBackgroundColor(0xff0c0b0a);
        LinearLayout top=row();Button back=PhotoWorkspaceUi.icon(getContext(),"back","取消塑形并返回人像","body-cancel",this::dismiss);top.addView(back,new LinearLayout.LayoutParams(dp(56),dp(52)));
        TextView title=text("塑形",16,TEXT);title.setGravity(Gravity.CENTER);top.addView(title,new LinearLayout.LayoutParams(0,dp(52),1));
        apply=button("应用",()->{if(!disposed&&!dragging&&!locating&&completed!=null&&completed.equals(shape)){commit.accept(shape);dismiss();}});apply.setTag("body-apply");apply.setTextColor(0xff211812);GradientDrawable face=new GradientDrawable();face.setColor(ACCENT);face.setCornerRadius(dp(10));apply.setBackground(new InsetDrawable(face,dp(4),dp(8),dp(4),dp(8)));top.addView(apply,new LinearLayout.LayoutParams(dp(72),dp(52)));root.addView(top);
        body=column();body.setTag("body-content");root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
        stage=new FrameLayout(getContext());stage.setTag("body-stage");photo=new BodyCanvas();stage.addView(photo,new FrameLayout.LayoutParams(-1,-1));
        hint=text("",12,MUTED);hint.setTag("body-hint");hint.setGravity(Gravity.CENTER);hint.setMaxLines(2);hint.setBackgroundColor(0x7017221e);stage.addView(hint,new FrameLayout.LayoutParams(-1,dp(48),Gravity.TOP));
        LinearLayout quick=row();quick.setPadding(dp(8),0,dp(8),0);quick.setBackgroundColor(Color.TRANSPARENT);
        undoButton=action(quick,"undo","撤销塑形","body-undo",()->history(false));redoButton=action(quick,"redo","重做塑形","body-redo",()->history(true));
        quick.addView(new View(getContext()),new LinearLayout.LayoutParams(0,1,1));guidesButton=action(quick,"eye","显示或隐藏塑形范围","body-guides",()->{guides=!guides;refresh();});
        action(quick,"fit","适应照片","body-fit",photo::resetViewport);
        Button compare=action(quick,"compare","按住对比进入塑形前的照片","body-compare",()->{setCompare(true);main.postDelayed(compareEnd,650);});
        compare.setOnTouchListener((v,e)->{int a=e.getActionMasked();if(a==MotionEvent.ACTION_DOWN){setCompare(true);return true;}if(a==MotionEvent.ACTION_MOVE){if(e.getX()<0||e.getY()<0||e.getX()>=v.getWidth()||e.getY()>=v.getHeight())setCompare(false);return true;}if(a==MotionEvent.ACTION_UP||a==MotionEvent.ACTION_CANCEL||a==MotionEvent.ACTION_POINTER_DOWN)setCompare(false);return true;});
        compare.setOnKeyListener((v,k,e)->{if(k!=KeyEvent.KEYCODE_ENTER&&k!=KeyEvent.KEYCODE_DPAD_CENTER&&k!=KeyEvent.KEYCODE_SPACE)return false;setCompare(e.getAction()==KeyEvent.ACTION_DOWN);return true;});compare.setOnFocusChangeListener((v,f)->{if(!f)setCompare(false);});
        stage.addView(quick,new FrameLayout.LayoutParams(-1,dp(48),Gravity.BOTTOM));
        status=text("",12,MUTED);status.setTag("body-status");status.setGravity(Gravity.CENTER);status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);status.setBackgroundColor(0x7017221e);FrameLayout.LayoutParams sp=new FrameLayout.LayoutParams(-1,dp(48),Gravity.BOTTOM);sp.bottomMargin=dp(48);stage.addView(status,sp);body.addView(stage,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout panel=column();panel.setPadding(dp(12),dp(4),dp(12),dp(8));panel.setBackgroundColor(Color.TRANSPARENT);
        LinearLayout adjustment=row();label=text("瘦身",12,TEXT);adjustment.addView(label,new LinearLayout.LayoutParams(dp(72),dp(48)));strength=slider("body-strength");adjustment.addView(strength,new LinearLayout.LayoutParams(0,dp(48),1));value=text("0",12,ACCENT);value.setGravity(Gravity.CENTER);value.setTag("body-value");value.setFocusable(true);value.setClickable(true);value.setOnClickListener(v->exact());adjustment.addView(value,new LinearLayout.LayoutParams(dp(48),dp(48)));panel.addView(adjustment);
        strength.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar b,int p,boolean user){if(user&&!updating){PhotoBodyShape next=shape.withArea(tool,shape.area(tool).withAmount(p));edit(next);}}public void onStartTrackingTouch(SeekBar b){beginGesture();}public void onStopTrackingTouch(SeekBar b){endGesture(false);}});
        singleButton=button("双腿",()->edit(shape.withSingleLeg(!shape.singleLeg)));singleButton.setTag("body-leg-mode");singleButton.setTextSize(11);singleButton.setTextColor(MUTED);adjustment.addView(singleButton,1,new LinearLayout.LayoutParams(dp(56),dp(48)));
        LinearLayout rail=row();rail.setTag("body-primary-tools");String[] icons={"body","legs","length"},captions={"瘦身","瘦腿","拉长"};int toolHeight=dp(72*Math.max(1,activity.getResources().getConfiguration().fontScale));
        for(int i=0;i<3;i++){final int next=i;tools[i]=PhotoWorkspaceUi.tool(getContext(),captions[i],"body-tool-"+i,icons[i],()->choose(next));tools[i].setContentDescription(NAMES[i]);rail.addView(tools[i],new LinearLayout.LayoutParams(0,toolHeight,1));}
        rangeButton=PhotoWorkspaceUi.tool(getContext(),"范围","body-range-options","range-options",()->{endGesture(false);expanded=!expanded;rangePanel.setVisibility(expanded?View.VISIBLE:View.GONE);refresh();resize();});rail.addView(rangeButton,new LinearLayout.LayoutParams(0,toolHeight,1));
        resetCurrentButton=PhotoWorkspaceUi.tool(getContext(),"重置","body-reset","reset",()->edit((tool==PhotoBodyShape.LEGS?shape.withSingleLeg(false):shape).withArea(tool,PhotoBodyShape.NONE.area(tool))));rail.addView(resetCurrentButton,new LinearLayout.LayoutParams(0,toolHeight,1));panel.addView(rail);
        LinearLayout automation=row();locateButton=button("自动定位",()->analyzeBody(true));locateButton.setTag("body-auto-locate");locateButton.setTextSize(11);locateButton.setTextColor(MUTED);automation.addView(locateButton,new LinearLayout.LayoutParams(0,dp(48),1));protectionButton=button("背景保护",this::toggleProtection);protectionButton.setTag("body-background-protection");protectionButton.setTextSize(11);protectionButton.setTextColor(new ColorStateList(new int[][]{new int[]{android.R.attr.state_selected},new int[]{}},new int[]{ACCENT,MUTED}));automation.addView(protectionButton,new LinearLayout.LayoutParams(0,dp(48),1));panel.addView(automation);
        rangePanel=column();rangePanel.setTag("body-range-panel");String[] labels={"左边","上边","宽度","高度"};for(int i=0;i<4;i++){final int axis=i;LinearLayout line=row();line.addView(text(labels[i],12,TEXT),new LinearLayout.LayoutParams(dp(48),dp(48)));SeekBar b=slider("body-box-"+i);b.setMax(1000);boxSliders[i]=b;line.addView(b,new LinearLayout.LayoutParams(0,dp(48),1));TextView number=text("",11,MUTED);number.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);boxValues[i]=number;line.addView(number,new LinearLayout.LayoutParams(dp(40),dp(48)));rangePanel.addView(line);b.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar bar,int p,boolean user){if(user&&!updating)boxAxis(axis,p/1000.0);}public void onStartTrackingTouch(SeekBar b){beginGesture();}public void onStopTrackingTouch(SeekBar b){endGesture(false);}});}rangePanel.setVisibility(View.GONE);panel.addView(rangePanel);
        controls=new ScrollView(getContext());controls.setFillViewport(false);controls.setVerticalScrollBarEnabled(false);controls.addView(panel);body.addView(controls,new LinearLayout.LayoutParams(-1,dp(180)));body.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->resize());
        root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){Insets safe=insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());root.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else root.setPadding(insets.getStableInsetLeft(),insets.getStableInsetTop(),insets.getStableInsetRight(),insets.getStableInsetBottom());body.post(this::resize);return insets;});
        PhotoPrismaStyle.workspace(root,initial);setContentView(root);if(getWindow()!=null){getWindow().setBackgroundDrawableResource(android.R.color.transparent);getWindow().setLayout(-1,-1);}root.requestApplyInsets();refresh();changed();
    }
    private void resize(){if(disposed||body==null||body.getWidth()<1||body.getHeight()<2)return;boolean side=body.getWidth()>body.getHeight()&&body.getWidth()>=dp(480);int orientation=side?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL;if(body.getOrientation()!=orientation)body.setOrientation(orientation);LinearLayout.LayoutParams p=(LinearLayout.LayoutParams)stage.getLayoutParams();int sw=side?0:-1,sh=side?-1:0;if(p.width!=sw||p.height!=sh||p.weight!=1)stage.setLayoutParams(new LinearLayout.LayoutParams(sw,sh,1));int cw=side?Math.min(dp(320),Math.round(body.getWidth()*.44f)):-1,ch=side?-1:Math.min(body.getHeight()/2,dp((expanded?372:180)+72*(Math.max(1,activity.getResources().getConfiguration().fontScale)-1)));LinearLayout.LayoutParams c=(LinearLayout.LayoutParams)controls.getLayoutParams();if(c.width!=cw||c.height!=ch)controls.setLayoutParams(new LinearLayout.LayoutParams(cw,ch));}
    public void setAnalysisSource(Bitmap source){if(source!=null&&!source.isRecycled())analysisSource=source;}
    private void toggleProtection(){if(shape.backgroundMask==null){analyzeBody(false);return;}edit(shape.withBackgroundProtection(shape.backgroundMask,shape.backgroundProtection==0?100:0));}
    private void analyzeBody(boolean locate){
        if(disposed||locating)return;endGesture(true);locating=true;refresh();availability();status.setText(locate?"正在识别人物轮廓…":"正在分析背景直线…");
        final PhotoBodyShape before=shape;analysisWorker.execute(()->{cc.huevia.album.PhotoBodyAnalysis.Result result=null;String failure=null;try{result=cc.huevia.album.PhotoBodyAnalysis.analyze(activity.getApplicationContext(),analysisSource,()->disposed||Thread.currentThread().isInterrupted());}catch(Exception|LinkageError|OutOfMemoryError e){failure="识别未完成，可以重试或手动调整范围。";}final cc.huevia.album.PhotoBodyAnalysis.Result found=result;final String message=failure;main.post(()->{
            if(disposed)return;locating=false;refresh();availability();if(!shape.equals(before)){status.setText("设置已变化，请重新识别。");return;}if(found==null){status.setText(message);return;}
            java.util.function.Consumer<cc.huevia.album.PhotoBodyAnalysis.Person> use=person->{PhotoBodyShape next=person==null?shape:cc.huevia.album.PhotoBodyAnalysis.locate(shape,person);edit(next.withBackgroundProtection(found.protection,100));status.setText(locate?(person.legsVisible?"已按人物轮廓定位 · 请检查腰腿位置":"已定位上身 · 未确认腿部，请手动定位"):"背景直线保护已开启");};
            if(!locate){use.accept(null);return;}if(found.people.isEmpty()){status.setText("未识别到完整人物轮廓，请手动调整。");return;}if(found.people.size()==1){use.accept(found.people.get(0));return;}String[] names=new String[found.people.size()];for(int i=0;i<names.length;i++)names[i]="人物 "+(i+1)+" · 画面"+Math.round((found.people.get(i).left+found.people.get(i).right)*50)+"% 处";exactDialog=new AppDialog.Builder(activity).setTitle("选择要塑形的人物").setItems(names,(d,i)->use.accept(found.people.get(i))).setNegativeButton("取消",null).create();exactDialog.show();
        });});
    }
    private SeekBar slider(String tag){SeekBar b=new SeekBar(getContext()){private boolean interrupted;@Override public boolean onTouchEvent(MotionEvent e){int a=e.getActionMasked();if(a==MotionEvent.ACTION_DOWN)interrupted=false;if(a==MotionEvent.ACTION_CANCEL||a==MotionEvent.ACTION_POINTER_DOWN){endGesture(true);MotionEvent cancel=MotionEvent.obtain(e);cancel.setAction(MotionEvent.ACTION_CANCEL);super.onTouchEvent(cancel);cancel.recycle();interrupted=true;}if(interrupted){if(a==MotionEvent.ACTION_UP||a==MotionEvent.ACTION_CANCEL)setPressed(false);return true;}return super.onTouchEvent(e);}};b.setTag(tag);b.setMax(100);b.setKeyProgressIncrement(1);b.setProgressTintList(ColorStateList.valueOf(ACCENT));b.setThumbTintList(ColorStateList.valueOf(ACCENT));PhotoPrismaStyle.slider(getContext(),b);return b;}
    private void beginGesture(){if(disposed)return;setCompare(false);if(gestureStart!=null)endGesture(true);gestureStart=shape;dragging=true;photo.invalidate();availability();}
    private void endGesture(boolean cancel){if(gestureStart==null)return;PhotoBodyShape before=gestureStart;gestureStart=null;dragging=false;if(cancel)shape=before;else remember(before);changed();}
    private void remember(PhotoBodyShape before){if(before.equals(shape))return;undo.addLast(before);while(undo.size()>48)undo.removeFirst();redo.clear();}
    private void edit(PhotoBodyShape next){if(disposed||next.equals(shape))return;PhotoBodyShape before=shape;shape=next;if(gestureStart==null)remember(before);changed();}
    private void changed(){if(disposed)return;completed=null;error=false;refresh();queue.offer(shape,dragging);}
    private void choose(int next){endGesture(false);tool=next;guides=true;photo.stopGesture();refresh();}
    private void history(boolean forward){endGesture(true);ArrayDeque<PhotoBodyShape> from=forward?redo:undo,to=forward?undo:redo;if(from.isEmpty())return;to.addLast(shape);shape=from.removeLast();changed();}
    private void boxAxis(int axis,double n){PhotoBodyShape.Area a=shape.area(tool);double l=a.left,t=a.top,w=a.right-a.left,h=a.bottom-a.top;switch(axis){case 0:l=Math.min(n,1-w);break;case 1:t=Math.min(n,(tool==2?.97:1)-h);break;case 2:w=Math.max(Math.min(.08,1-l),Math.min(n,1-l));break;case 3:h=Math.max(Math.min(.10,(tool==2?.97:1)-t),Math.min(n,(tool==2?.97:1)-t));break;default:return;}edit(shape.withArea(tool,new PhotoBodyShape.Area(l,t,l+w,t+h,a.amount)));}
    private void refresh(){if(strength==null)return;locateButton.setEnabled(!locating);protectionButton.setEnabled(!locating);protectionButton.setSelected(shape.backgroundProtection>0);protectionButton.setText(shape.backgroundProtection>0?"背景保护 · 开":"背景保护");updating=true;PhotoBodyShape.Area a=shape.area(tool);label.setText(NAMES[tool]);strength.setProgress(a.amount);strength.setContentDescription(NAMES[tool]+"强度 "+a.amount+"，范围0至100");value.setText(Integer.toString(a.amount));value.setContentDescription(strength.getContentDescription()+"，点按输入数值");for(int i=0;i<3;i++)tools[i].setSelected(tool==i);guidesButton.setSelected(guides);guidesButton.setContentDescription(guides?"隐藏塑形范围":"显示塑形范围");singleButton.setVisibility(tool==1?View.VISIBLE:View.GONE);singleButton.setText(shape.singleLeg?"单腿":"双腿");singleButton.setContentDescription(shape.singleLeg?"当前单腿，点按切换为双腿":"当前双腿，点按切换为单腿");rangeButton.setText("范围");rangeButton.setSelected(expanded);rangeButton.setContentDescription(expanded?"收起塑形范围参数":"展开塑形范围参数");resetCurrentButton.setContentDescription("重置当前"+NAMES[tool]+"，保留其他塑形项");resetCurrentButton.setTooltipText("重置当前"+NAMES[tool]);double[] axes={a.left,a.top,a.right-a.left,a.bottom-a.top};String[] names={"塑形范围左边","塑形范围上边","塑形范围宽度","塑形范围高度"};for(int i=0;i<4;i++){boxSliders[i].setProgress((int)Math.round(axes[i]*1000));boxValues[i].setText(Math.round(axes[i]*100)+"%");boxSliders[i].setContentDescription(names[i]+" "+boxValues[i].getText());}
        hint.setText(tool==2?"上边对齐大腿根，底边对齐脚底 · 脚下需留白":tool==1?(shape.singleLeg?"将范围框贴合一条腿 · 双指缩放查看":"将范围框贴合双腿 · 中线放在两腿之间"):"将范围框放在肩部以下 · 拖动边角调整");photo.setContentDescription("塑形照片，"+NAMES[tool]+"强度"+a.amount+"。可拖动范围框；也可展开范围，使用四个滑块调整。双指缩放查看。");updating=false;photo.invalidate();availability();}
    private void availability(){if(apply==null)return;boolean ready=!disposed&&!dragging&&!locating&&completed!=null&&completed.equals(shape);apply.setEnabled(ready);apply.setAlpha(ready?1:.45f);undoButton.setEnabled(!undo.isEmpty()&&!dragging);redoButton.setEnabled(!redo.isEmpty()&&!dragging);undoButton.setAlpha(undoButton.isEnabled()?1:.35f);redoButton.setAlpha(redoButton.isEnabled()?1:.35f);status.setText(error?"预览失败，点击重试":completed==null&&!dragging?"预览中…":"");status.setVisibility(status.getText().length()>0?View.VISIBLE:View.GONE);status.setOnClickListener(error?v->changed():null);status.setFocusable(error);}
    private void setCompare(boolean value){main.removeCallbacks(compareEnd);comparing=value;if(photo!=null)photo.invalidate();}
    private void exact(){if(disposed)return;endGesture(false);EditText input=new EditText(getContext());input.setInputType(InputType.TYPE_CLASS_NUMBER);input.setSingleLine(true);input.setText(Integer.toString(shape.area(tool).amount));input.selectAll();input.setContentDescription(NAMES[tool]+"强度，0至100");LinearLayout panel=column();panel.setPadding(dp(24),dp(8),dp(24),0);panel.addView(input);exactDialog=new AppDialog.Builder(getContext()).setTitle(NAMES[tool]+" · 0—100").setView(panel).setNegativeButton("取消",null).setPositiveButton("确定",null).create();exactDialog.setOnShowListener(d->exactDialog.getButton(-1).setOnClickListener(v->{try{int n=Integer.parseInt(input.getText().toString());if(n<0||n>100)throw new NumberFormatException();edit(shape.withArea(tool,shape.area(tool).withAmount(n)));exactDialog.dismiss();}catch(NumberFormatException bad){input.setError("请输入0至100的整数");}}));exactDialog.show();}
    @Override public void show(){super.show();if(getWindow()!=null)getWindow().setLayout(-1,-1);}
    @Override public void onWindowFocusChanged(boolean focused){super.onWindowFocusChanged(focused);if(!focused){setCompare(false);if(photo!=null)photo.stopGesture();endGesture(true);}}
    @Override public void dismiss(){if(!disposed){disposed=true;main.removeCallbacks(compareEnd);queue.close();analysisWorker.shutdownNow();worker.shutdownNow();if(exactDialog!=null)exactDialog.dismiss();if(photo!=null)photo.invalidate();rendered=null;gestureStart=null;}super.dismiss();}

    private final class BodyCanvas extends View {
        private final RectF frame=new RectF(),box=new RectF();
        private final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
        private final ScaleGestureDetector scale;
        private float zoom=1,panX,panY,lastX,lastY;
        private int handle=-1;
        private boolean navigating;
        private double downX,downY;
        private PhotoBodyShape.Area startArea;
        BodyCanvas(){super(PhotoBodyDialog.this.getContext());setTag("body-photo");setFocusable(true);setClickable(true);scale=new ScaleGestureDetector(getContext(),new ScaleGestureDetector.SimpleOnScaleGestureListener(){public boolean onScale(ScaleGestureDetector d){float next=Math.max(1,Math.min(8,zoom*d.getScaleFactor())),r=next/zoom,fx=d.getFocusX()-getWidth()/2f,fy=d.getFocusY()-getHeight()/2f;panX=fx-(fx-panX)*r;panY=fy-(fy-panY)*r;zoom=next;bounds();invalidate();return true;}});}
        void resetViewport(){stopGesture();endGesture(true);zoom=1;panX=panY=0;invalidate();}
        void stopGesture(){handle=-1;navigating=false;startArea=null;invalidate();}
        @Override protected void onSizeChanged(int w,int h,int ow,int oh){super.onSizeChanged(w,h,ow,oh);stopGesture();endGesture(true);bounds();}
        private void bounds(){float availableHeight=Math.max(1,getHeight()-dp(96));float fit=Math.min(getWidth()/(float)initial.getWidth(),availableHeight/initial.getHeight()),w=initial.getWidth()*fit*zoom,h=initial.getHeight()*fit*zoom;float mx=Math.max(0,(w-getWidth())/2),my=Math.max(0,(h-availableHeight)/2);panX=Math.max(-mx,Math.min(mx,panX));panY=Math.max(-my,Math.min(my,panY));frame.set((getWidth()-w)/2+panX,(getHeight()-h)/2+panY,(getWidth()+w)/2+panX,(getHeight()+h)/2+panY);PhotoBodyShape.Area a=shape.area(tool);box.set((float)(frame.left+a.left*frame.width()),(float)(frame.top+a.top*frame.height()),(float)(frame.left+a.right*frame.width()),(float)(frame.top+a.bottom*frame.height()));}
        @Override protected void onDraw(Canvas c){super.onDraw(c);if(disposed)return;bounds();int viewport=c.save();c.clipRect(0,dp(48),getWidth(),Math.max(dp(48),getHeight()-dp(48)));Bitmap image=comparing||rendered==null?initial:rendered;ink.setAlpha(255);ink.setStyle(Paint.Style.FILL);c.drawBitmap(image,null,frame,ink);if(!guides||comparing||dragging&&handle<0||frame.isEmpty()){c.restoreToCount(viewport);return;}int save=c.save();c.clipRect(frame);ink.setColor(0xaafff1e4);ink.setStyle(Paint.Style.STROKE);ink.setStrokeWidth(dp(1));ink.setPathEffect(new DashPathEffect(new float[]{dp(5),dp(5)},0));c.drawRoundRect(box,dp(3),dp(3),ink);if(tool==1&&!shape.singleLeg)c.drawLine(box.centerX(),box.top,box.centerX(),box.bottom,ink);ink.setPathEffect(null);ink.setColor(ACCENT);ink.setStrokeWidth(dp(2));float arm=dp(12);for(int i=0;i<4;i++){float x=i%2==0?box.left:box.right,y=i<2?box.top:box.bottom;c.drawLine(x,y,x+(i%2==0?arm:-arm),y,ink);c.drawLine(x,y,x,y+(i<2?arm:-arm),ink);}c.drawLine(box.centerX()-dp(10),box.top,box.centerX()+dp(10),box.top,ink);c.drawLine(box.centerX()-dp(10),box.bottom,box.centerX()+dp(10),box.bottom,ink);ink.setStyle(Paint.Style.FILL);c.restoreToCount(save);c.restoreToCount(viewport);}
        private int hit(float x,float y){float[] xs={box.left,box.right,box.left,box.right,box.centerX(),box.centerX(),box.left,box.right};float[] ys={box.top,box.top,box.bottom,box.bottom,box.top,box.bottom,box.centerY(),box.centerY()};int best=-1;double distance=dp(24);for(int i=0;i<xs.length;i++){double d=Math.hypot(x-xs[i],y-ys[i]);if(d<distance){best=i;distance=d;}}return best>=0?best:box.contains(x,y)?8:-1;}
        @Override public boolean onTouchEvent(MotionEvent e){if(disposed||comparing)return false;bounds();int action=e.getActionMasked();scale.onTouchEvent(e);
            if(action==MotionEvent.ACTION_DOWN){lastX=e.getX();lastY=e.getY();downX=nx(lastX);downY=ny(lastY);handle=guides?hit(lastX,lastY):-1;navigating=false;if(handle>=0){beginGesture();startArea=shape.area(tool);}return true;}
            if(e.getPointerCount()>1){if(handle>=0){endGesture(true);handle=-1;startArea=null;}float x=0,y=0;for(int i=0;i<e.getPointerCount();i++){x+=e.getX(i);y+=e.getY(i);}x/=e.getPointerCount();y/=e.getPointerCount();if(navigating&&action==MotionEvent.ACTION_MOVE){panX+=x-lastX;panY+=y-lastY;bounds();}lastX=x;lastY=y;navigating=true;invalidate();return true;}
            if(navigating){if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL)stopGesture();return true;}
            if(action==MotionEvent.ACTION_MOVE&&handle>=0&&startArea!=null){move(nx(e.getX())-downX,ny(e.getY())-downY);return true;}
            if(action==MotionEvent.ACTION_MOVE&&zoom>1){panX+=e.getX()-lastX;panY+=e.getY()-lastY;lastX=e.getX();lastY=e.getY();invalidate();return true;}
            if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL){if(handle>=0)endGesture(action==MotionEvent.ACTION_CANCEL);stopGesture();if(action==MotionEvent.ACTION_UP)performClick();return true;}return true;}
        private void move(double dx,double dy){PhotoBodyShape.Area a=startArea;double l=a.left,r=a.right,t=a.top,b=a.bottom,maxB=tool==2?.97:1;if(handle==8){dx=Math.max(-l,Math.min(1-r,dx));dy=Math.max(-t,Math.min(maxB-b,dy));l+=dx;r+=dx;t+=dy;b+=dy;}else{if(handle==0||handle==2||handle==6)l=Math.max(0,Math.min(r-.08,l+dx));if(handle==1||handle==3||handle==7)r=Math.max(l+.08,Math.min(1,r+dx));if(handle==0||handle==1||handle==4)t=Math.max(0,Math.min(b-.10,t+dy));if(handle==2||handle==3||handle==5)b=Math.max(t+.10,Math.min(maxB,b+dy));}edit(shape.withArea(tool,new PhotoBodyShape.Area(l,t,r,b,a.amount)));}
        private double nx(float x){return Math.max(0,Math.min(1,(x-frame.left)/Math.max(1,frame.width())));}
        private double ny(float y){return Math.max(0,Math.min(1,(y-frame.top)/Math.max(1,frame.height())));}
        @Override public boolean performClick(){return super.performClick();}
    }
    private Button action(LinearLayout parent,String icon,String description,String tag,Runnable run){Button b=PhotoWorkspaceUi.icon(getContext(),icon,description,tag,run);parent.addView(b,new LinearLayout.LayoutParams(dp(48),dp(48)));return b;}
    private Button button(String label,Runnable task){Button b=new Button(getContext());b.setText(label);b.setTextColor(TEXT);b.setTextSize(12);b.setAllCaps(false);b.setMinimumWidth(0);b.setMinWidth(0);b.setMinimumHeight(dp(48));b.setMinHeight(dp(48));b.setPadding(dp(4),0,dp(4),0);b.setIncludeFontPadding(false);b.setBackgroundColor(Color.TRANSPARENT);b.setStateListAnimator(null);b.setOnClickListener(v->task.run());return b;}
    private TextView text(String s,int size,int color){TextView v=new TextView(getContext());v.setText(s);v.setTextSize(size);v.setTextColor(color);v.setIncludeFontPadding(false);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private LinearLayout row(){LinearLayout l=new LinearLayout(getContext());l.setOrientation(LinearLayout.HORIZONTAL);l.setGravity(Gravity.CENTER_VERTICAL);return l;}
    private LinearLayout column(){LinearLayout l=new LinearLayout(getContext());l.setOrientation(LinearLayout.VERTICAL);return l;}
    private int dp(float value){return Math.round(value*getContext().getResources().getDisplayMetrics().density);}
}
