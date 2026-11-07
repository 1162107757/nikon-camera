package cc.huevia.ui;

import android.app.*;
import android.animation.ValueAnimator;
import android.content.res.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.os.*;
import android.text.*;
import android.view.*;
import android.view.accessibility.*;
import android.view.animation.PathInterpolator;
import android.widget.*;
import cc.huevia.ncp.*;
import java.util.ArrayDeque;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** A tentative two-axis look: preview locally, commit one editor undo step on Apply. */
public final class PhotoPaletteDialog extends Dialog {
    public interface Renderer { Bitmap render(PhotoAdjustments settings,boolean interactive)throws Exception; }
    private static final int TEXT=0xfff4f5f7,MUTED=PhotoPrismaStyle.MUTED,ACCENT=PhotoPrismaStyle.YELLOW,BG=Color.TRANSPARENT;
    private static final PathInterpolator EASE_OUT=new PathInterpolator(.16f,1f,.3f,1f);
    private final Activity activity;
    private final Bitmap initial;
    private final String scopeLabel;
    private final Consumer<PhotoAdjustments> commit;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<>(1),r->{Thread t=new Thread(r,"photo-palette-preview");t.setDaemon(true);return t;},new ThreadPoolExecutor.DiscardOldestPolicy());
    private final LatestPreviewQueue<PhotoAdjustments,Bitmap> previewQueue;
    private final ArrayDeque<PhotoColorPalette> history=new ArrayDeque<>(),redo=new ArrayDeque<>();
    private final SeekBar[] sliders=new SeekBar[3];
    private final TextView[] values=new TextView[3];
    private PhotoAdjustments settings;
    private PhotoColorPalette gestureOrigin;
    private PhotoImageView photo;
    private Bitmap rendered;
    private TextView status;
    private Button apply,undoButton,redoButton,compareButton;
    private PalettePad pad;
    private View controlsPanel;
    private boolean entranceLandscape;
    private AlertDialog exactDialog;
    private boolean updating,disposed,dragging,comparing;
    private final Runnable compareEnd=()->setComparing(false);

    public PhotoPaletteDialog(Activity activity,Bitmap initial,PhotoAdjustments settings,String scopeLabel,Renderer renderer,Consumer<PhotoAdjustments> commit){
        super(activity,cc.huevia.R.style.AppThemeDark);
        this.activity=activity;this.initial=initial;this.settings=settings;this.scopeLabel=scopeLabel;this.commit=commit;
        previewQueue=new LatestPreviewQueue<>(worker,task->main.post(task),renderer::render,new LatestPreviewQueue.Listener<PhotoAdjustments,Bitmap>(){
            public void frame(PhotoAdjustments value,Bitmap image,boolean interactive,boolean latest){
                if(disposed){image.recycle();return;}
                // A displayed frame can still belong to a hardware display list: release its
                // Java reference, rather than recycling it while that list may still draw.
                rendered=image;if(!comparing)photo.setPhotoPreservingTransform(image);
                if(latest&&!interactive){status.setText("");status.setOnClickListener(null);apply.setEnabled(true);apply.setAlpha(1f);}
            }
            public void discard(Bitmap image){image.recycle();}
            public void error(Throwable error){if(disposed)return;status.setText("预览失败，点击重试");apply.setEnabled(false);apply.setAlpha(.45f);status.setOnClickListener(v->changed());}
        });
    }
    public PhotoAdjustments settings(){return settings;}

    @Override protected void onCreate(Bundle saved){
        super.onCreate(saved);requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout root=column();root.setTag("photo-palette-workspace");root.setBackgroundColor(0xff0e0d0c);
        LinearLayout top=row();Button cancel=button("取消",this::dismiss);cancel.setTag("palette-cancel");top.addView(cancel,new LinearLayout.LayoutParams(dp(64),dp(48)));
        TextView title=text("调色盘 · "+scopeLabel,16,TEXT);title.setSingleLine(true);title.setEllipsize(TextUtils.TruncateAt.END);title.setGravity(Gravity.CENTER);title.setContentDescription("调色盘，作用范围："+scopeLabel);top.addView(title,new LinearLayout.LayoutParams(0,dp(48),1));
        apply=button("应用",()->{if(dragging||disposed)return;commit.accept(settings);dismiss();});apply.setTag("palette-apply");apply.setTextColor(ACCENT);top.addView(apply,new LinearLayout.LayoutParams(dp(64),dp(48)));root.addView(top);
        boolean landscape=activity.getResources().getConfiguration().orientation==Configuration.ORIENTATION_LANDSCAPE;
        LinearLayout body=new LinearLayout(getContext());body.setOrientation(landscape?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL);root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
        FrameLayout stage=new FrameLayout(getContext());stage.setTag("palette-stage");photo=new PhotoImageView(getContext());photo.setTag("palette-photo");photo.setPhoto(initial);photo.setContentDescription("调色盘实时预览，可双指缩放");stage.addView(photo,new FrameLayout.LayoutParams(-1,-1));
        status=text("",11,MUTED);status.setGravity(Gravity.CENTER);status.setMinHeight(dp(48));FrameLayout.LayoutParams statusPos=new FrameLayout.LayoutParams(-1,dp(48),Gravity.BOTTOM);statusPos.setMargins(dp(64),0,dp(64),0);stage.addView(status,statusPos);
        Button fit=iconButton(AppIcon.Kind.EXPAND,"适应屏幕",photo::resetZoom);fit.setTag("palette-fit");FrameLayout.LayoutParams fitPos=new FrameLayout.LayoutParams(dp(48),dp(48),Gravity.BOTTOM|Gravity.START);fitPos.setMargins(dp(8),0,0,dp(8));stage.addView(fit,fitPos);
        compareButton=iconButton(AppIcon.Kind.COMPARE,"按住对比进入调色盘前的效果",()->{setComparing(true);main.postDelayed(compareEnd,650);});compareButton.setTag("palette-compare");compareButton.setOnTouchListener((v,event)->{
            int a=event.getActionMasked();if(a==MotionEvent.ACTION_DOWN){setComparing(true);return true;}
            if(a==MotionEvent.ACTION_MOVE){if(event.getX()<0||event.getY()<0||event.getX()>=v.getWidth()||event.getY()>=v.getHeight())setComparing(false);return true;}
            if(a==MotionEvent.ACTION_UP||a==MotionEvent.ACTION_CANCEL||a==MotionEvent.ACTION_OUTSIDE||a==MotionEvent.ACTION_POINTER_DOWN){setComparing(false);return true;}return true;
        });
        compareButton.setOnKeyListener((v,key,event)->{if(key!=KeyEvent.KEYCODE_ENTER&&key!=KeyEvent.KEYCODE_DPAD_CENTER&&key!=KeyEvent.KEYCODE_SPACE)return false;setComparing(event.getAction()==KeyEvent.ACTION_DOWN);return true;});compareButton.setOnFocusChangeListener((v,focused)->{if(!focused)setComparing(false);});
        FrameLayout.LayoutParams comparePos=new FrameLayout.LayoutParams(dp(48),dp(48),Gravity.BOTTOM|Gravity.END);comparePos.setMargins(0,0,dp(8),dp(8));stage.addView(compareButton,comparePos);
        body.addView(stage,landscape?new LinearLayout.LayoutParams(0,-1,1):new LinearLayout.LayoutParams(-1,0,1));

        LinearLayout controls=column();controlsPanel=controls;entranceLandscape=landscape;controls.setBackgroundColor(BG);controls.setPadding(dp(12),dp(4),dp(12),dp(4));
        LinearLayout readouts=row();TextView scope=text(scopeLabel,12,TEXT);scope.setTag("palette-scope");scope.setSingleLine(true);scope.setEllipsize(TextUtils.TruncateAt.END);scope.setContentDescription("作用范围："+scopeLabel);readouts.addView(scope,new LinearLayout.LayoutParams(dp(56),dp(48)));for(int a=0;a<2;a++){final int axis=a;values[a]=text("",12,TEXT);values[a].setTag("palette-value-"+a);values[a].setGravity(Gravity.CENTER);values[a].setFocusable(true);values[a].setClickable(true);values[a].setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffe335),null,null));values[a].setOnClickListener(v->exact(axis));readouts.addView(values[a],new LinearLayout.LayoutParams(0,dp(48),1));}Button reset=iconButton(AppIcon.Kind.REFRESH,"重置调色盘，颜色与影调归零，强度100",()->edit(PhotoColorPalette.NONE));reset.setTag("palette-reset");readouts.addView(reset,new LinearLayout.LayoutParams(dp(48),dp(48)));controls.addView(readouts);
        int screenHeight=activity.getResources().getDisplayMetrics().heightPixels;int panelHeight=Math.min(dp(456),Math.round(screenHeight*.54f));int padHeight=landscape?dp(288):Math.max(dp(172),panelHeight-dp(152));pad=new PalettePad();pad.setTag("palette-pad");controls.addView(pad,new LinearLayout.LayoutParams(-1,padHeight));
        LinearLayout strength=row();strength.addView(text("强度",12,TEXT),new LinearLayout.LayoutParams(dp(42),dp(48)));
        SeekBar slider=new SeekBar(getContext()){
            private boolean interrupted;
            @Override public boolean onTouchEvent(MotionEvent event){int a=event.getActionMasked();if(a==MotionEvent.ACTION_DOWN)interrupted=false;if(a==MotionEvent.ACTION_CANCEL||a==MotionEvent.ACTION_POINTER_DOWN){endGesture(true);MotionEvent cancel=MotionEvent.obtain(event);cancel.setAction(MotionEvent.ACTION_CANCEL);super.onTouchEvent(cancel);cancel.recycle();interrupted=true;}if(interrupted){if(a==MotionEvent.ACTION_UP||a==MotionEvent.ACTION_CANCEL)setPressed(false);return true;}return super.onTouchEvent(event);}
        };slider.setTag("palette-strength");slider.setMax(100);slider.setKeyProgressIncrement(1);slider.setProgressTintList(ColorStateList.valueOf(ACCENT));slider.setThumbTintList(ColorStateList.valueOf(ACCENT));sliders[2]=slider;strength.addView(slider,new LinearLayout.LayoutParams(0,dp(48),1));
        values[2]=text("",12,ACCENT);values[2].setTag("palette-value-2");values[2].setGravity(Gravity.END|Gravity.CENTER_VERTICAL);values[2].setFocusable(true);values[2].setClickable(true);values[2].setOnClickListener(v->exact(2));strength.addView(values[2],new LinearLayout.LayoutParams(dp(48),dp(48)));controls.addView(strength);
        slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar s,int value,boolean user){if(user&&!updating){PhotoColorPalette next=settings.palette.withAmount(value);if(gestureOrigin==null)edit(next);else changeGesture(next);}}
            public void onStartTrackingTouch(SeekBar s){beginGesture();}
            public void onStopTrackingTouch(SeekBar s){endGesture(false);}
        });
        LinearLayout actions=row();undoButton=iconButton(AppIcon.Kind.UNDO,"撤销调色盘调整",()->history(false));undoButton.setTag("palette-undo");actions.addView(undoButton,new LinearLayout.LayoutParams(dp(48),dp(48)));redoButton=iconButton(AppIcon.Kind.REDO,"重做调色盘调整",()->history(true));redoButton.setTag("palette-redo");actions.addView(redoButton,new LinearLayout.LayoutParams(dp(48),dp(48)));
        TextView hint=text("拖动调色 · 按住对比",11,MUTED);hint.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);hint.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);actions.addView(hint,new LinearLayout.LayoutParams(0,dp(48),1));controls.addView(actions);
        ScrollView pane=new ScrollView(getContext());pane.setFillViewport(false);pane.setOverScrollMode(View.OVER_SCROLL_IF_CONTENT_SCROLLS);pane.addView(controls);body.addView(pane,landscape?new LinearLayout.LayoutParams(dp(320),-1):new LinearLayout.LayoutParams(-1,panelHeight));
        root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){Insets safe=insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());root.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else root.setPadding(insets.getStableInsetLeft(),insets.getStableInsetTop(),insets.getStableInsetRight(),insets.getStableInsetBottom());return insets;});
        PhotoPrismaStyle.workspace(root,initial);setContentView(root);if(getWindow()!=null){getWindow().setBackgroundDrawableResource(android.R.color.transparent);getWindow().setLayout(-1,-1);}root.requestApplyInsets();refresh();changed();
    }
    @Override public void show(){super.show();if(getWindow()!=null)getWindow().setLayout(-1,-1);revealControls();}
    @Override public void onWindowFocusChanged(boolean focused){super.onWindowFocusChanged(focused);if(!focused){setComparing(false);finishControlsMotion();if(pad!=null)pad.cancelTouch();if(dragging&&sliders[2]!=null){MotionEvent cancel=MotionEvent.obtain(SystemClock.uptimeMillis(),SystemClock.uptimeMillis(),MotionEvent.ACTION_CANCEL,0,0,0);sliders[2].dispatchTouchEvent(cancel);cancel.recycle();}if(dragging)endGesture(true);}}
    @Override public void dismiss(){dispose();super.dismiss();}
    private void dispose(){if(disposed)return;disposed=true;main.removeCallbacks(compareEnd);finishControlsMotion();if(pad!=null)pad.stopMotion();previewQueue.close();if(exactDialog!=null)exactDialog.dismiss();worker.shutdownNow();if(photo!=null)photo.setPhoto(null);rendered=null;gestureOrigin=null;}
    private void setComparing(boolean held){main.removeCallbacks(compareEnd);if(disposed||photo==null)return;comparing=held;if(compareButton!=null)compareButton.setPressed(held);photo.setPhotoPreservingTransform(held?initial:rendered==null?initial:rendered);}
    private void beginGesture(){beginGesture(true);}
    private void beginGesture(boolean snap){if(disposed)return;setComparing(false);if(gestureOrigin!=null)endGesture(true);gestureOrigin=settings.palette;dragging=true;if(pad!=null){if(snap)pad.snapMarker();else pad.pauseMarker();}}
    private void changeGesture(PhotoColorPalette next){if(disposed||next.equals(settings.palette))return;settings=settings.withPalette(next);changed();}
    private void endGesture(boolean cancelled){if(gestureOrigin==null)return;PhotoColorPalette before=gestureOrigin;gestureOrigin=null;dragging=false;if(cancelled)settings=settings.withPalette(before);else if(!before.equals(settings.palette))remember(before);changed();if(pad!=null){pad.releasePoint(cancelled);if(cancelled)pad.snapMarker();}}
    private void edit(PhotoColorPalette next){if(disposed)return;if(gestureOrigin!=null)endGesture(true);setComparing(false);if(next.equals(settings.palette))return;remember(settings.palette);settings=settings.withPalette(next);changed();}
    private void remember(PhotoColorPalette before){history.addLast(before);while(history.size()>64)history.removeFirst();redo.clear();}
    private void history(boolean forward){if(gestureOrigin!=null)endGesture(true);ArrayDeque<PhotoColorPalette> from=forward?redo:history,to=forward?history:redo;if(from.isEmpty())return;setComparing(false);to.addLast(settings.palette);settings=settings.withPalette(from.removeLast());changed();}
    private void changed(){if(disposed)return;refresh();status.setText(dragging?"":"预览中");apply.setEnabled(false);apply.setAlpha(.45f);previewQueue.offer(settings,dragging);}
    private void refresh(){
        if(pad==null)return;updating=true;PhotoColorPalette p=settings.palette;values[0].setText("颜色  "+signed(p.color));values[1].setText("影调  "+signed(p.tone));values[2].setText(p.amount+"%");
        values[0].setContentDescription("颜色 "+p.color+"，负值清淡，正值鲜艳，点击输入数值");values[1].setContentDescription("影调 "+p.tone+"，负值低对比，正值高对比，点击输入数值");values[2].setContentDescription("强度 "+p.amount+"%，点击输入数值");sliders[2].setProgress(p.amount);sliders[2].setContentDescription("调色盘强度 "+p.amount+"%，范围0至100");
        undoButton.setEnabled(!history.isEmpty());redoButton.setEnabled(!redo.isEmpty());undoButton.setAlpha(undoButton.isEnabled()?1:.35f);redoButton.setAlpha(redoButton.isEnabled()?1:.35f);pad.setContentDescription("调色盘，颜色 "+p.color+"，影调 "+p.tone+"。左右改变颜色浓淡，上下改变影调对比。也可点击上方数值精确输入。");pad.updateMarker(dragging&&pad.directDrag);pad.invalidate();updating=false;
    }
    private void exact(int axis){
        if(disposed)return;if(gestureOrigin!=null)endGesture(true);setComparing(false);final int minimum=axis==2?0:-100,maximum=100;int current=axis==0?settings.palette.color:axis==1?settings.palette.tone:settings.palette.amount;
        LinearLayout form=column();form.setPadding(dp(20),0,dp(20),0);EditText input=new EditText(getContext());input.setTag("palette-exact-input");input.setInputType(InputType.TYPE_CLASS_NUMBER|(axis==2?0:InputType.TYPE_NUMBER_FLAG_SIGNED));input.setSingleLine(true);input.setText(String.valueOf(current));input.selectAll();input.setContentDescription(new String[]{"颜色","影调","强度"}[axis]+"，范围"+minimum+"至100");form.addView(input);
        SeekBar precision=new SeekBar(getContext());precision.setTag("palette-exact-slider");precision.setMax(maximum-minimum);precision.setKeyProgressIncrement(1);precision.setProgress(current-minimum);precision.setProgressTintList(ColorStateList.valueOf(ACCENT));precision.setThumbTintList(ColorStateList.valueOf(ACCENT));precision.setContentDescription(input.getContentDescription());form.addView(precision,new LinearLayout.LayoutParams(-1,dp(48)));
        precision.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar s,int p,boolean user){if(user){input.setText(String.valueOf(p+minimum));input.setSelection(input.length());}}public void onStartTrackingTouch(SeekBar s){}public void onStopTrackingTouch(SeekBar s){}});
        input.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int start,int count,int after){}public void onTextChanged(CharSequence s,int start,int before,int count){try{int value=Integer.parseInt(s.toString().trim());if(value>=minimum&&value<=maximum)precision.setProgress(value-minimum);}catch(NumberFormatException ignored){}}public void afterTextChanged(Editable e){}});
        AlertDialog dialog=new PhotoEditorTypography.Builder(getContext()).setTitle(new String[]{"颜色 · 清淡至鲜艳","影调 · 低对比至高对比","调色盘强度"}[axis]).setView(form).setNegativeButton("取消",null).setPositiveButton("应用",null).create();exactDialog=dialog;dialog.setOnDismissListener(v->{if(exactDialog==dialog)exactDialog=null;});dialog.setOnShowListener(v->dialog.getButton(-1).setOnClickListener(w->{try{int value=Integer.parseInt(input.getText().toString().trim());if(value<minimum||value>maximum)throw new IllegalArgumentException();PhotoColorPalette p=settings.palette;edit(axis==0?p.withColor(value):axis==1?p.withTone(value):p.withAmount(value));dialog.dismiss();}catch(IllegalArgumentException error){input.setError("请输入"+minimum+"至100的整数");}}));dialog.show();PhotoEditorTypography.apply(dialog);
    }
    private static boolean motionEnabled(){return ValueAnimator.areAnimatorsEnabled();}
    private void revealControls(){
        if(controlsPanel==null||disposed)return;finishControlsMotion();if(!motionEnabled())return;
        controlsPanel.setAlpha(.55f);controlsPanel.setTranslationX(entranceLandscape?dp(18):0);controlsPanel.setTranslationY(entranceLandscape?0:dp(18));
        controlsPanel.animate().alpha(1f).translationX(0).translationY(0).setDuration(180).setInterpolator(EASE_OUT).start();
    }
    private void finishControlsMotion(){if(controlsPanel==null)return;controlsPanel.animate().cancel();controlsPanel.setAlpha(1f);controlsPanel.setTranslationX(0);controlsPanel.setTranslationY(0);}
    private final class PalettePad extends View {
        private static final int COLOR_UP=0x7f0f7301,COLOR_DOWN=0x7f0f7302,TONE_UP=0x7f0f7303,TONE_DOWN=0x7f0f7304;
        private final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
        private final RectF frame=new RectF();
        private final Bitmap field=Bitmap.createBitmap(96,96,Bitmap.Config.ARGB_8888);
        private final Paint light=new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Shader glow=new RadialGradient(0,0,dp(28),new int[]{0x68ffc59b,0x30ffc59b,0x00ffc59b},new float[]{0f,.35f,1f},Shader.TileMode.CLAMP);
        private final Shader shadow=new RadialGradient(0,0,dp(13),new int[]{0x600b0805,0x200b0805,0x000b0805},new float[]{0f,.45f,1f},Shader.TileMode.CLAMP);
        private boolean tracking,directDrag;
        private float touchStartX,touchStartY;
        private ValueAnimator markerAnimator,pressAnimator;
        private float markerColor,markerTone,pressProgress;
        private int markerTargetColor,markerTargetTone;
        PalettePad(){super(PhotoPaletteDialog.this.getContext());setFocusable(true);setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);markerColor=markerTargetColor=settings.palette.color;markerTone=markerTargetTone=settings.palette.tone;for(int y=0;y<96;y++)for(int x=0;x<96;x++){float u=x/95f,v=y/95f,t=v<.48f?v/.48f:(v-.48f)/.52f;t=t*t*(3-2*t);int left=v<.48f?mix(0xff343437,0xff777979,t):mix(0xff777979,0xffb7b1a7,t);int right=v<.48f?mix(0xff81503d,0xffdc8c87,t):mix(0xffdc8c87,0xffcbb595,t);field.setPixel(x,y,mix(left,right,u*u*(3-2*u)));}}
        private void pauseMarker(){if(markerAnimator!=null){markerAnimator.cancel();markerAnimator=null;}markerTargetColor=markerTargetTone=Integer.MIN_VALUE;}
        private void snapMarker(){if(markerAnimator!=null){markerAnimator.cancel();markerAnimator=null;}markerColor=markerTargetColor=settings.palette.color;markerTone=markerTargetTone=settings.palette.tone;invalidate();}
        private void updateMarker(boolean direct){
            if(direct||!motionEnabled()||!isAttachedToWindow()){snapMarker();return;}
            final int targetColor=settings.palette.color,targetTone=settings.palette.tone;if(targetColor==markerTargetColor&&targetTone==markerTargetTone)return;
            if(markerAnimator!=null)markerAnimator.cancel();markerTargetColor=targetColor;markerTargetTone=targetTone;
            final float fromColor=markerColor,fromTone=markerTone;markerAnimator=ValueAnimator.ofFloat(0f,1f);markerAnimator.setDuration(160);markerAnimator.setInterpolator(EASE_OUT);
            markerAnimator.addUpdateListener(animation->{if(disposed)return;float t=(float)animation.getAnimatedValue();markerColor=fromColor+(targetColor-fromColor)*t;markerTone=fromTone+(targetTone-fromTone)*t;invalidate();});markerAnimator.start();
        }
        private void pressPoint(){animatePress(1f,false);}
        private void releasePoint(boolean immediate){animatePress(0f,immediate);}
        private void animatePress(float target,boolean immediate){
            if(pressAnimator!=null){pressAnimator.cancel();pressAnimator=null;}if(immediate||!motionEnabled()||disposed){pressProgress=target;invalidate();return;}
            if(pressProgress==target)return;pressAnimator=ValueAnimator.ofFloat(pressProgress,target);pressAnimator.setDuration(target>0?100:150);pressAnimator.setInterpolator(EASE_OUT);pressAnimator.addUpdateListener(animation->{if(disposed)return;pressProgress=(float)animation.getAnimatedValue();invalidate();});pressAnimator.start();
        }
        private void stopMotion(){if(markerAnimator!=null){markerAnimator.cancel();markerAnimator=null;}if(pressAnimator!=null){pressAnimator.cancel();pressAnimator=null;}markerColor=markerTargetColor=settings.palette.color;markerTone=markerTargetTone=settings.palette.tone;pressProgress=0;invalidate();}
        @Override protected void onSizeChanged(int w,int h,int oldw,int oldh){float height=Math.max(1,h-dp(48)),width=Math.min(Math.max(1,w-dp(56)),height*1.15f);frame.set((w-width)/2,dp(24),(w+width)/2,h-dp(24));}
        @Override protected void onDraw(Canvas canvas){
            super.onDraw(canvas);if(frame.width()<=0||frame.height()<=0)return;int save=canvas.save();Path clip=new Path();clip.addRoundRect(frame,dp(12),dp(12),Path.Direction.CW);canvas.clipPath(clip);ink.setColor(Color.WHITE);ink.setStyle(Paint.Style.FILL);canvas.drawBitmap(field,null,frame,ink);canvas.restoreToCount(save);
            ink.setStyle(Paint.Style.STROKE);ink.setColor(0x28ffffff);ink.setStrokeWidth(dp(1));canvas.drawRoundRect(frame,dp(12),dp(12),ink);ink.setColor(0x36ffffff);canvas.drawLine(frame.centerX(),frame.top+dp(8),frame.centerX(),frame.bottom-dp(8),ink);canvas.drawLine(frame.left+dp(8),frame.centerY(),frame.right-dp(8),frame.centerY(),ink);
            float x=frame.left+frame.width()*(markerColor+100)/200f,y=frame.bottom-frame.height()*(markerTone+100)/200f;
            if(pressProgress>0){int optical=canvas.save();canvas.clipPath(clip);canvas.translate(x,y);light.setAlpha(Math.round(pressProgress*255));light.setShader(glow);canvas.drawCircle(0,0,dp(28),light);canvas.translate(dp(2),dp(3));light.setShader(shadow);canvas.drawCircle(0,0,dp(13),light);light.setShader(null);canvas.restoreToCount(optical);}
            float ring=dp(9);ink.setStyle(Paint.Style.STROKE);ink.setColor(0x66000000);ink.setStrokeWidth(dp(3));canvas.drawCircle(x,y,ring,ink);ink.setColor(Color.WHITE);ink.setStrokeWidth(dp(1));canvas.drawCircle(x,y,ring,ink);ink.setStyle(Paint.Style.FILL);ink.setColor(Color.WHITE);canvas.drawCircle(x,y,dp(5),ink);
            if(pressProgress>0){int optical=canvas.save();canvas.clipPath(clip);canvas.drawCircle(x,y,dp(5)+activity.getResources().getDisplayMetrics().density*.75f*pressProgress,ink);ink.setStyle(Paint.Style.STROKE);ink.setStrokeWidth(dp(2));ink.setColor(Color.argb(Math.round(210*pressProgress),255,246,225));canvas.drawArc(new RectF(x-ring,y-ring,x+ring,y+ring),190,95,false,ink);ink.setStyle(Paint.Style.FILL);canvas.restoreToCount(optical);}
            ink.setColor(MUTED);ink.setTextSize(11*activity.getResources().getDisplayMetrics().scaledDensity);ink.setTextAlign(Paint.Align.CENTER);canvas.drawText("层次",frame.centerX(),frame.top-dp(8),ink);canvas.drawText("柔和",frame.centerX(),frame.bottom+dp(18),ink);canvas.drawText("淡",frame.left-dp(16),frame.centerY()-(ink.ascent()+ink.descent())/2,ink);canvas.drawText("鲜",frame.right+dp(16),frame.centerY()-(ink.ascent()+ink.descent())/2,ink);
        }
        private void move(float x,float y){if(frame.width()<=0||frame.height()<=0)return;int color=Math.max(-100,Math.min(100,Math.round((x-frame.left)*200/frame.width()-100)));int tone=Math.max(-100,Math.min(100,Math.round((frame.bottom-y)*200/frame.height()-100)));changeGesture(new PhotoColorPalette(color,tone,settings.palette.amount));}
        @Override public boolean onTouchEvent(MotionEvent event){
            if(disposed||frame.width()<=0||frame.height()<=0)return false;int action=event.getActionMasked();
            if(action==MotionEvent.ACTION_DOWN){if(!frame.contains(event.getX(),event.getY()))return false;tracking=true;directDrag=false;touchStartX=event.getX();touchStartY=event.getY();beginGesture(false);pressPoint();getParent().requestDisallowInterceptTouchEvent(true);move(event.getX(),event.getY());updateMarker(false);return true;}
            if(!tracking)return false;
            if(action==MotionEvent.ACTION_MOVE){if(!directDrag&&Math.hypot(event.getX()-touchStartX,event.getY()-touchStartY)>=ViewConfiguration.get(getContext()).getScaledTouchSlop()){directDrag=true;snapMarker();}move(event.getX(),event.getY());return true;}
            if(action==MotionEvent.ACTION_UP){move(event.getX(),event.getY());tracking=false;endGesture(false);getParent().requestDisallowInterceptTouchEvent(false);performClick();return true;}
            if(action==MotionEvent.ACTION_CANCEL||action==MotionEvent.ACTION_POINTER_DOWN){tracking=false;endGesture(true);getParent().requestDisallowInterceptTouchEvent(false);return true;}return true;
        }
        @Override public boolean performClick(){super.performClick();return true;}
        private void cancelTouch(){releasePoint(true);if(!tracking)return;tracking=false;endGesture(true);getParent().requestDisallowInterceptTouchEvent(false);}
        @Override protected void onFocusChanged(boolean gain,int direction,Rect previous){super.onFocusChanged(gain,direction,previous);if(!gain)cancelTouch();}
        @Override protected void onDetachedFromWindow(){stopMotion();super.onDetachedFromWindow();}
        @Override public boolean onKeyDown(int key,KeyEvent event){PhotoColorPalette p=settings.palette;int step=event.isShiftPressed()?5:1;switch(key){case KeyEvent.KEYCODE_DPAD_LEFT:edit(p.withColor(Math.max(-100,p.color-step)));return true;case KeyEvent.KEYCODE_DPAD_RIGHT:edit(p.withColor(Math.min(100,p.color+step)));return true;case KeyEvent.KEYCODE_DPAD_DOWN:edit(p.withTone(Math.max(-100,p.tone-step)));return true;case KeyEvent.KEYCODE_DPAD_UP:edit(p.withTone(Math.min(100,p.tone+step)));return true;case KeyEvent.KEYCODE_ENTER:case KeyEvent.KEYCODE_DPAD_CENTER:exact(0);return true;default:return super.onKeyDown(key,event);}}
        @Override public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info){super.onInitializeAccessibilityNodeInfo(info);info.addAction(new AccessibilityNodeInfo.AccessibilityAction(COLOR_UP,"颜色更鲜艳"));info.addAction(new AccessibilityNodeInfo.AccessibilityAction(COLOR_DOWN,"颜色更清淡"));info.addAction(new AccessibilityNodeInfo.AccessibilityAction(TONE_UP,"提高影调对比"));info.addAction(new AccessibilityNodeInfo.AccessibilityAction(TONE_DOWN,"降低影调对比"));info.setClickable(false);}
        @Override public boolean performAccessibilityAction(int action,Bundle args){PhotoColorPalette p=settings.palette;if(action==COLOR_UP)edit(p.withColor(Math.min(100,p.color+5)));else if(action==COLOR_DOWN)edit(p.withColor(Math.max(-100,p.color-5)));else if(action==TONE_UP)edit(p.withTone(Math.min(100,p.tone+5)));else if(action==TONE_DOWN)edit(p.withTone(Math.max(-100,p.tone-5)));else return super.performAccessibilityAction(action,args);sendAccessibilityEvent(AccessibilityEvent.TYPE_VIEW_SELECTED);return true;}
    }
    private static int mix(int a,int b,float t){int r=Math.round(Color.red(a)+(Color.red(b)-Color.red(a))*t),g=Math.round(Color.green(a)+(Color.green(b)-Color.green(a))*t),bl=Math.round(Color.blue(a)+(Color.blue(b)-Color.blue(a))*t);return Color.rgb(r,g,bl);}
    private static String signed(int n){return n>0?"+"+n:String.valueOf(n);}
    private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
    private LinearLayout column(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.VERTICAL);return v;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(getContext());v.setGravity(Gravity.CENTER_VERTICAL);v.setBaselineAligned(false);return v;}
    private TextView text(String s,int size,int color){TextView v=new TextView(getContext());v.setText(s);v.setTextSize(size);v.setTextColor(color);v.setGravity(Gravity.CENTER_VERTICAL);v.setIncludeFontPadding(false);return v;}
    private Button button(String s,Runnable run){Button b=new Button(getContext());b.setText(s);b.setTextSize(12);b.setAllCaps(false);b.setTextColor(TEXT);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setPadding(dp(4),0,dp(4),0);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffe335),null,null));b.setOnClickListener(v->run.run());return b;}
    private Button iconButton(AppIcon.Kind kind,String label,Runnable run){Button b=button("",run);b.setContentDescription(label);b.setTooltipText(label);Drawable icon=new AppIcon(kind,TEXT,activity.getResources().getDisplayMetrics().density);LayerDrawable face=new LayerDrawable(new Drawable[]{icon});face.setLayerSize(0,dp(24),dp(24));face.setLayerGravity(0,Gravity.CENTER);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffe335),face,null));return b;}
}
