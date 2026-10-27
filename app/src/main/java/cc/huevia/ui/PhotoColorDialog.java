package cc.huevia.ui;

import android.app.*;
import android.content.res.*;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import cc.huevia.ncp.*;
import java.util.Arrays;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** Tentative colour workspace. Cancel/Back never commits; Apply is one editor undo step. */
public final class PhotoColorDialog extends Dialog {
    public interface Renderer { Bitmap render(PhotoAdjustments settings,boolean interactive)throws Exception; }
    private static final int TEXT=0xfff4f5f7,MUTED=0xffbab1a7,ACCENT=0xfff2b48c,BG=0xff131110;
    private final Activity activity;
    private final Renderer renderer;
    private final Consumer<PhotoAdjustments> commit;
    private final boolean curveMode;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<>(1),r->{Thread t=new Thread(r,"photo-colour-preview");t.setDaemon(true);return t;},new ThreadPoolExecutor.DiscardOldestPolicy());
    private final LatestPreviewQueue<PhotoAdjustments,Bitmap> previewQueue;
    private PhotoAdjustments settings;
    private ImageView photo;
    private Bitmap rendered;
    private TextView status,pointValue;
    private Button apply,remove;
    private CurveCanvas graph;
    private final SeekBar[] sliders=new SeekBar[3];
    private final TextView[] values=new TextView[3];
    private final Button[] bands;
    private int channel,point,revision;
    private boolean updating,disposed,dragging;
    private AlertDialog exactDialog;
    public PhotoColorDialog(Activity activity,Bitmap initial,PhotoAdjustments settings,boolean curveMode,Renderer renderer,Consumer<PhotoAdjustments> commit){
        super(activity,cc.huevia.R.style.AppThemeDark);this.activity=activity;this.settings=settings;this.curveMode=curveMode;this.renderer=renderer;this.commit=commit;this.bands=new Button[curveMode?4:8];
        photo=new ImageView(getContext());photo.setScaleType(ImageView.ScaleType.FIT_CENTER);photo.setImageBitmap(initial);photo.setContentDescription("当前调色预览");
        previewQueue=new LatestPreviewQueue<>(worker,task->main.post(task),renderer::render,new LatestPreviewQueue.Listener<PhotoAdjustments,Bitmap>(){
            public void frame(PhotoAdjustments value,Bitmap image,boolean interactive,boolean latest){if(disposed){image.recycle();return;}Bitmap old=rendered;rendered=image;photo.setImageBitmap(image);if(old!=null&&old!=image)old.recycle();if(latest&&!interactive){status.setText("");status.setOnClickListener(null);apply.setEnabled(true);apply.setAlpha(1f);}}
            public void discard(Bitmap image){image.recycle();}
            public void error(Throwable error){if(disposed)return;status.setText("预览失败，请重试");apply.setEnabled(false);apply.setAlpha(.45f);status.setOnClickListener(v->changed());}
        });
    }
    public PhotoAdjustments settings(){return settings;}
    @Override protected void onCreate(Bundle saved){
        super.onCreate(saved);requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout root=column();root.setBackgroundColor(0xff0e0d0c);root.setTag("photo-colour-workspace");
        LinearLayout top=row();top.addView(button("取消",this::dismiss),new LinearLayout.LayoutParams(dp(68),dp(48)));TextView title=text(curveMode?"曲线":"HSL",16,TEXT);title.setGravity(Gravity.CENTER);top.addView(title,new LinearLayout.LayoutParams(0,dp(48),1));
        apply=button("应用",()->{commit.accept(settings);dismiss();});apply.setTag("colour-apply");apply.setTextColor(ACCENT);top.addView(apply,new LinearLayout.LayoutParams(dp(68),dp(48)));root.addView(top);
        boolean landscape=activity.getResources().getConfiguration().orientation==Configuration.ORIENTATION_LANDSCAPE;
        LinearLayout body=new LinearLayout(getContext());body.setOrientation(landscape?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL);root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
        FrameLayout stage=new FrameLayout(getContext());stage.addView(photo,new FrameLayout.LayoutParams(-1,-1));status=text("",11,MUTED);status.setPadding(dp(12),dp(4),dp(12),dp(4));status.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);status.setMinHeight(dp(48));stage.addView(status,new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM));
        body.addView(stage,landscape?new LinearLayout.LayoutParams(0,-1,1):new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout controls=column();controls.setBackgroundColor(BG);controls.setPadding(dp(12),0,dp(12),dp(6));
        HorizontalScrollView scroll=new HorizontalScrollView(getContext());scroll.setHorizontalScrollBarEnabled(false);LinearLayout choices=row();scroll.addView(choices);LinearLayout.LayoutParams colorRow=new LinearLayout.LayoutParams(-1,dp(curveMode?48:56));colorRow.topMargin=dp(curveMode?0:8);controls.addView(scroll,colorRow);
        String[] names=curveMode?new String[]{"RGB","红","绿","蓝"}:PhotoHsl.NAMES;
        for(int i=0;i<names.length;i++){final int c=i;bands[i]=button(names[i],()->{channel=c;point=0;refresh();});if(!curveMode){android.graphics.drawable.GradientDrawable swatch=new android.graphics.drawable.GradientDrawable();swatch.setShape(android.graphics.drawable.GradientDrawable.OVAL);swatch.setColor(PhotoHsl.COLORS[i]);swatch.setBounds(0,0,dp(9),dp(9));bands[i].setCompoundDrawables(null,swatch,null,null);bands[i].setCompoundDrawablePadding(dp(3));bands[i].setPadding(dp(4),dp(8),dp(4),dp(4));}bands[i].setTag("colour-band-"+i);choices.addView(bands[i],new LinearLayout.LayoutParams(dp(curveMode?64:48),dp(48)));}
        if(curveMode){
            graph=new CurveCanvas();graph.setTag("colour-curve-graph");controls.addView(graph,new LinearLayout.LayoutParams(-1,dp(132)));
            LinearLayout line=row();line.addView(button("上一点",()->{point=Math.max(0,point-1);refresh();}),new LinearLayout.LayoutParams(0,dp(48),1));pointValue=text("",12,ACCENT);pointValue.setGravity(Gravity.CENTER);pointValue.setOnClickListener(v->exactPoint());pointValue.setFocusable(true);line.addView(pointValue,new LinearLayout.LayoutParams(0,dp(48),2));line.addView(button("下一点",()->{point=Math.min(settings.curves.points(channel).length/2-1,point+1);refresh();}),new LinearLayout.LayoutParams(0,dp(48),1));controls.addView(line);
            LinearLayout points=row();points.addView(button("加点",this::addPoint),new LinearLayout.LayoutParams(0,dp(48),1));remove=button("删点",this::removePoint);points.addView(remove,new LinearLayout.LayoutParams(0,dp(48),1));controls.addView(points);
        }else{
            String[] axes={"色相","饱和度","明亮度"};
            for(int axis=0;axis<3;axis++){final int a=axis;LinearLayout line=row();line.addView(text(axes[a],12,TEXT),new LinearLayout.LayoutParams(dp(56),dp(48)));SeekBar slider=new SeekBar(getContext());slider.setTag("hsl-axis-"+a);slider.setMax(200);slider.setKeyProgressIncrement(1);slider.setProgressTintList(ColorStateList.valueOf(ACCENT));slider.setThumbTintList(ColorStateList.valueOf(ACCENT));line.addView(slider,new LinearLayout.LayoutParams(0,dp(48),1));sliders[a]=slider;values[a]=text("",12,ACCENT);values[a].setGravity(Gravity.END|Gravity.CENTER_VERTICAL);values[a].setFocusable(true);values[a].setOnClickListener(v->exactHsl(a));line.addView(values[a],new LinearLayout.LayoutParams(dp(48),dp(48)));controls.addView(line);
                slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar s,int p,boolean user){if(user&&!updating){settings=settings.withHsl(settings.hsl.with(channel,a,p-100));changed();}}public void onStartTrackingTouch(SeekBar s){dragging=true;}public void onStopTrackingTouch(SeekBar s){dragging=false;changed();}});
            }
        }
        LinearLayout resets=row();resets.addView(button(curveMode?"重置通道":"重置此颜色",()->{settings=curveMode?settings.withCurves(settings.curves.reset(channel)):settings.withHsl(settings.hsl.reset(channel));point=0;changed();}),new LinearLayout.LayoutParams(0,dp(48),1));resets.addView(button(curveMode?"重置曲线":"重置 HSL",()->{settings=curveMode?settings.withCurves(PhotoCurves.NONE):settings.withHsl(PhotoHsl.NONE);point=0;changed();}),new LinearLayout.LayoutParams(0,dp(48),1));controls.addView(resets);
        if(landscape){ScrollView pane=new ScrollView(getContext());pane.addView(controls);body.addView(pane,new LinearLayout.LayoutParams(dp(330),-1));}
        else{ScrollView pane=new ScrollView(getContext());pane.addView(controls);body.addView(pane,new LinearLayout.LayoutParams(-1,dp(curveMode?330:264)));}
        root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){Insets safe=insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());root.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else root.setPadding(insets.getStableInsetLeft(),insets.getStableInsetTop(),insets.getStableInsetRight(),insets.getStableInsetBottom());return insets;});
        setContentView(root);if(getWindow()!=null){getWindow().setBackgroundDrawableResource(android.R.color.transparent);getWindow().setLayout(-1,-1);}root.requestApplyInsets();refresh();changed();
    }
    @Override public void show(){super.show();if(getWindow()!=null)getWindow().setLayout(-1,-1);}
    @Override public void dismiss(){dispose();super.dismiss();}
    private void dispose(){if(disposed)return;disposed=true;revision++;previewQueue.close();if(exactDialog!=null)exactDialog.dismiss();worker.shutdownNow();photo.setImageDrawable(null);if(rendered!=null){rendered.recycle();rendered=null;}}
    private void changed(){if(disposed)return;refresh();revision++;status.setText("预览中");apply.setEnabled(false);apply.setAlpha(.45f);previewQueue.offer(settings,dragging);}
    private void refresh(){
        updating=true;
        for(int i=0;i<bands.length;i++){Button b=bands[i];b.setSelected(channel==i);b.setTextColor(channel==i?ACCENT:TEXT);b.setContentDescription((curveMode?new String[]{"RGB 总曲线","红通道","绿通道","蓝通道"}[i]:PhotoHsl.NAMES[i]+"色")+(channel==i?"，已选择":""));android.graphics.drawable.GradientDrawable face=new android.graphics.drawable.GradientDrawable();face.setColor(channel==i?0x26f2b48c:Color.TRANSPARENT);face.setCornerRadius(dp(8));b.setBackground(new android.graphics.drawable.InsetDrawable(face,dp(2),dp(6),dp(2),dp(6)));if(!curveMode)b.setPadding(dp(4),dp(10),dp(4),dp(4));}
        if(curveMode){int[] p=settings.curves.points(channel);point=Math.min(point,p.length/2-1);pointValue.setText(p[point*2]+" → "+p[point*2+1]);pointValue.setContentDescription("控制点输入 "+p[point*2]+"，输出 "+p[point*2+1]+"，点击精确输入");remove.setEnabled(point>0&&point<p.length/2-1);remove.setAlpha(remove.isEnabled()?1:.4f);graph.invalidate();graph.setContentDescription("曲线。点击加点，拖动控制点；也可使用上一点、下一点和精确输入。当前 "+pointValue.getText());}
        else for(int a=0;a<3;a++){int value=settings.hsl.get(channel,a);sliders[a].setProgress(value+100);values[a].setText(value>0?"+"+value:String.valueOf(value));sliders[a].setContentDescription(PhotoHsl.NAMES[channel]+"色"+new String[]{"色相","饱和度","明亮度"}[a]+"，"+value+"，范围负100至100");values[a].setContentDescription(sliders[a].getContentDescription()+"，点击输入数值");}
        updating=false;
    }
    private void addPoint(){int[] p=settings.curves.points(channel);if(p.length>=PhotoCurves.MAX_POINTS*2)return;int slot=Math.min(point,p.length/2-2);if(p[(slot+1)*2]-p[slot*2]<2)return;int x=(p[slot*2]+p[(slot+1)*2])/2;insert(x,(int)Math.round(settings.curves.map(channel,x/255.0)*255));}
    private void insert(int x,int y){int[] old=settings.curves.points(channel);if(old.length>=PhotoCurves.MAX_POINTS*2||x<=0||x>=255)return;int i=0;while(i<old.length&&old[i]<x)i+=2;if(i<old.length&&old[i]==x){point=i/2;refresh();return;}int[] next=new int[old.length+2];System.arraycopy(old,0,next,0,i);next[i]=x;next[i+1]=y;System.arraycopy(old,i,next,i+2,old.length-i);point=i/2;settings=settings.withCurves(settings.curves.withPoints(channel,next));changed();}
    private void removePoint(){int[] old=settings.curves.points(channel);if(point<=0||point>=old.length/2-1)return;int[] next=new int[old.length-2];System.arraycopy(old,0,next,0,point*2);System.arraycopy(old,point*2+2,next,point*2,old.length-point*2-2);point--;settings=settings.withCurves(settings.curves.withPoints(channel,next));changed();}
    private void movePoint(int x,int y){int[] p=settings.curves.points(channel);if(point==0)x=0;else if(point==p.length/2-1)x=255;else x=Math.max(p[point*2-2]+1,Math.min(p[point*2+2]-1,x));p[point*2]=x;p[point*2+1]=Math.max(0,Math.min(255,y));PhotoCurves next=settings.curves.withPoints(channel,p);if(!next.equals(settings.curves)){settings=settings.withCurves(next);changed();}}
    private void exactPoint(){int[] p=settings.curves.points(channel);LinearLayout fields=column();fields.setPadding(dp(20),0,dp(20),0);EditText x=input(p[point*2]),y=input(p[point*2+1]);x.setContentDescription("输入，0至255");y.setContentDescription("输出，0至255");x.setEnabled(point>0&&point<p.length/2-1);fields.addView(text("输入",12,MUTED));fields.addView(x);fields.addView(text("输出",12,MUTED));fields.addView(y);AlertDialog d=new PhotoEditorTypography.Builder(getContext()).setTitle("控制点").setView(fields).setNegativeButton("取消",null).setPositiveButton("应用",null).create();d.setOnShowListener(v->d.getButton(-1).setOnClickListener(w->{try{int a=Integer.parseInt(x.getText().toString().trim()),b=Integer.parseInt(y.getText().toString().trim());if(a<0||a>255||b<0||b>255||point>0&&a<=p[point*2-2]||point<p.length/2-1&&a>=p[point*2+2])throw new IllegalArgumentException();movePoint(a,b);d.dismiss();}catch(IllegalArgumentException e){y.setError("范围0–255，输入点不能交叉");}}));exactDialog=d;d.setOnDismissListener(v->{if(exactDialog==d)exactDialog=null;});d.show();PhotoEditorTypography.apply(d);}
    private void exactHsl(int axis){EditText input=input(settings.hsl.get(channel,axis));LinearLayout form=column();form.setPadding(dp(20),0,dp(20),0);form.addView(input);AlertDialog d=new PhotoEditorTypography.Builder(getContext()).setTitle(PhotoHsl.NAMES[channel]+"色 · "+new String[]{"色相","饱和度","明亮度"}[axis]).setView(form).setNegativeButton("取消",null).setPositiveButton("应用",null).create();d.setOnShowListener(v->d.getButton(-1).setOnClickListener(w->{try{int value=Integer.parseInt(input.getText().toString().trim());settings=settings.withHsl(settings.hsl.with(channel,axis,value));changed();d.dismiss();}catch(IllegalArgumentException e){input.setError("请输入−100至100的整数");}}));exactDialog=d;d.setOnDismissListener(v->{if(exactDialog==d)exactDialog=null;});d.show();PhotoEditorTypography.apply(d);}
    private EditText input(int value){EditText input=new EditText(getContext());input.setInputType(android.text.InputType.TYPE_CLASS_NUMBER|android.text.InputType.TYPE_NUMBER_FLAG_SIGNED);input.setSingleLine(true);input.setText(String.valueOf(value));input.selectAll();return input;}
    private final class CurveCanvas extends View {
        private final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG);private final RectF frame=new RectF();
        CurveCanvas(){super(PhotoColorDialog.this.getContext());setFocusable(true);}
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);frame.set(dp(12),dp(10),getWidth()-dp(12),getHeight()-dp(10));ink.setStrokeWidth(dp(1));ink.setColor(0x24ffffff);for(int i=0;i<=4;i++){float t=i/4f;canvas.drawLine(frame.left+frame.width()*t,frame.top,frame.left+frame.width()*t,frame.bottom,ink);canvas.drawLine(frame.left,frame.top+frame.height()*t,frame.right,frame.top+frame.height()*t,ink);}ink.setColor(0x45ffffff);canvas.drawLine(frame.left,frame.bottom,frame.right,frame.top,ink);Path path=new Path();for(int x=0;x<256;x++){float a=frame.left+frame.width()*x/255f,b=frame.bottom-frame.height()*(float)settings.curves.map(channel,x/255.0);if(x==0)path.moveTo(a,b);else path.lineTo(a,b);}ink.setColor(new int[]{ACCENT,0xffee8e86,0xff8bca95,0xff97b7ef}[channel]);ink.setStyle(Paint.Style.STROKE);ink.setStrokeWidth(dp(2));canvas.drawPath(path,ink);ink.setStyle(Paint.Style.FILL);int[] p=settings.curves.points(channel);for(int i=0;i<p.length;i+=2){ink.setColor(i/2==point?Color.WHITE:ACCENT);canvas.drawCircle(frame.left+frame.width()*p[i]/255f,frame.bottom-frame.height()*p[i+1]/255f,dp(i/2==point?5:4),ink);}}
        @Override public boolean onTouchEvent(MotionEvent e){if(frame.width()<=0)return false;int action=e.getActionMasked(),x=Math.max(0,Math.min(255,Math.round((e.getX()-frame.left)/frame.width()*255))),y=Math.max(0,Math.min(255,Math.round((frame.bottom-e.getY())/frame.height()*255)));if(action==MotionEvent.ACTION_DOWN){dragging=true;int[] p=settings.curves.points(channel);double best=dp(26);int nearest=-1;for(int i=0;i<p.length;i+=2){double distance=Math.hypot(e.getX()-(frame.left+frame.width()*p[i]/255f),e.getY()-(frame.bottom-frame.height()*p[i+1]/255f));if(distance<best){best=distance;nearest=i/2;}}if(nearest<0&&p.length>=PhotoCurves.MAX_POINTS*2){dragging=false;return false;}if(nearest<0)insert(x,y);else{point=nearest;refresh();}getParent().requestDisallowInterceptTouchEvent(true);return true;}if(action==MotionEvent.ACTION_MOVE){movePoint(x,y);return true;}if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL){dragging=false;changed();getParent().requestDisallowInterceptTouchEvent(false);performClick();return true;}return true;}
        @Override public boolean performClick(){super.performClick();return true;}
    }
    private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
    private LinearLayout column(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.VERTICAL);return v;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(getContext());v.setGravity(Gravity.CENTER_VERTICAL);v.setBaselineAligned(false);return v;}
    private TextView text(String s,int size,int color){TextView v=new TextView(getContext());v.setText(s);v.setTextSize(size);v.setTextColor(color);v.setGravity(Gravity.CENTER_VERTICAL);v.setIncludeFontPadding(false);return v;}
    private Button button(String s,Runnable run){Button b=new Button(getContext());b.setText(s);b.setTextSize(12);b.setAllCaps(false);b.setTextColor(TEXT);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setPadding(dp(4),0,dp(4),0);b.setBackground(new android.graphics.drawable.RippleDrawable(ColorStateList.valueOf(0x33f2b48c),null,null));b.setOnClickListener(v->run.run());return b;}
}
