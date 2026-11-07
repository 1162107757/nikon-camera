package cc.huevia.ui;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Insets;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.InsetDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;
import cc.huevia.ncp.AdjustmentRegion;
import cc.huevia.ncp.PhotoPortrait;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Locale;
import java.util.function.Consumer;

/** A transactional, shared selection editor. Only vector strokes are changed. */
public final class PhotoBrushDialog extends Dialog {
    private static final int TEXT=0xfff4f5f7,MUTED=PhotoPrismaStyle.MUTED,ACCENT=PhotoPrismaStyle.YELLOW,PANEL=Color.TRANSPARENT;
    private static final int SOFT_MASK_ALPHA=38,FLASH_MASK_ALPHA=104;
    private static final long FLASH_ON_MS=220,FLASH_GAP_MS=140;
    private final Activity activity;
    private final Bitmap initial;
    private final Consumer<AdjustmentRegion> commit;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ArrayDeque<AdjustmentRegion> undo=new ArrayDeque<>(),redo=new ArrayDeque<>();
    private final PhotoCanvas photo;
    private final Bitmap mask;
    private final int maskWidth,maskHeight;
    private final float[] coverage,strokeCoverage;
    private final int[] maskPixels;
    private AdjustmentRegion region;
    private final AdjustmentRegion originalRegion;
    private Button apply,addButton,eraseButton,undoButton,redoButton,holdMaskButton;
    private TextView status;
    private LinearLayout body,panel;
    private FrameLayout stage;
    private double radius=.04,feather=.65;
    private boolean erase,disposed,sourcePositioning;
    public void setSourcePositioning(boolean value){sourcePositioning=value;}
    private int flashStep=-1;
    private final Runnable flashTick=this::advanceFlash;
    private boolean singleCompletionFlash,previewSingleHighlight;
    private int previewFlashStep=-1;
    private final Runnable previewFlashTick=this::advancePreviewFlash;
    private boolean holdingMask;
    private int maskPointer=-1;
    private final Runnable maskPeekEnd=()->setMaskHeld(false);

    /** The bitmap is borrowed until dismissal; result preserves all non-brush parameters. */
    public PhotoBrushDialog(Activity activity,Bitmap orientedPhoto,AdjustmentRegion initialRegion,Consumer<AdjustmentRegion> commit){
        super(activity,cc.huevia.R.style.AppThemeDark);
        if(orientedPhoto==null||orientedPhoto.isRecycled()||initialRegion==null||commit==null)throw new IllegalArgumentException("涂抹参数无效。");
        this.activity=activity;initial=orientedPhoto;region=initialRegion;originalRegion=initialRegion;this.commit=commit;
        double scale=Math.min(1,320.0/Math.max(initial.getWidth(),initial.getHeight()));
        maskWidth=Math.max(2,(int)Math.round(initial.getWidth()*scale));maskHeight=Math.max(2,(int)Math.round(initial.getHeight()*scale));
        mask=Bitmap.createBitmap(maskWidth,maskHeight,Bitmap.Config.ARGB_8888);coverage=new float[maskWidth*maskHeight];strokeCoverage=new float[coverage.length];maskPixels=new int[coverage.length];photo=new PhotoCanvas();
        rebuildMask();
    }
    public AdjustmentRegion settings(){return region;}
    @Override protected void onCreate(Bundle state){
        super.onCreate(state);requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout root=column();root.setTag("brush-workspace");root.setBackgroundColor(0xff0c0b0a);
        LinearLayout top=row();top.setPadding(dp(4),0,dp(8),0);
        top.addView(PhotoWorkspaceUi.icon(getContext(),"close","取消涂抹选区","brush-cancel",this::dismiss),new LinearLayout.LayoutParams(dp(48),dp(52)));
        TextView title=text("涂抹 · "+region.name,16,TEXT);title.setSingleLine(true);title.setEllipsize(android.text.TextUtils.TruncateAt.END);title.setGravity(Gravity.CENTER);top.addView(title,new LinearLayout.LayoutParams(0,dp(52),1));
        apply=button("完成选区",this::complete);apply.setTag("brush-apply");apply.setTextColor(0xff211812);GradientDrawable face=new GradientDrawable();face.setColor(ACCENT);face.setCornerRadius(dp(10));apply.setBackground(new InsetDrawable(face,dp(4),dp(8),dp(4),dp(8)));top.addView(apply,new LinearLayout.LayoutParams(dp(96),dp(52)));root.addView(top);
        body=column();body.setTag("brush-body");root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
        stage=new FrameLayout(getContext());stage.setTag("brush-stage");stage.addView(photo,new FrameLayout.LayoutParams(-1,-1));body.addView(stage,new LinearLayout.LayoutParams(-1,0,1));
        status=text(sourcePositioning?"按塑形前画面定位 · 完成后恢复塑形":"单指涂抹 · 双指缩放和移动",12,MUTED);status.setTag("brush-status");status.setGravity(Gravity.CENTER);status.setPadding(dp(8),dp(4),dp(8),dp(4));status.setBackgroundColor(0x7017221e);status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);stage.addView(status,new FrameLayout.LayoutParams(-1,dp(40),Gravity.BOTTOM));
        holdMaskButton=PhotoWorkspaceUi.icon(getContext(),"mask","按住查看选区，松开隐藏","brush-hold-mask",this::peekMask);
        GradientDrawable holdFace=new GradientDrawable();holdFace.setColor(0xc721201d);holdFace.setCornerRadius(dp(24));holdFace.setStroke(dp(1),0x45ffffff);holdMaskButton.setBackground(holdFace);
        holdMaskButton.setOnTouchListener((view,event)->holdMaskTouch(event));
        holdMaskButton.setOnFocusChangeListener((view,focused)->{if(!focused)setMaskHeld(false);});
        holdMaskButton.setOnKeyListener((view,key,event)->{if(key!=KeyEvent.KEYCODE_ENTER&&key!=KeyEvent.KEYCODE_DPAD_CENTER&&key!=KeyEvent.KEYCODE_SPACE)return false;if(event.getAction()==KeyEvent.ACTION_DOWN)setMaskHeld(true);else if(event.getAction()==KeyEvent.ACTION_UP)setMaskHeld(false);return true;});
        FrameLayout.LayoutParams holdParams=new FrameLayout.LayoutParams(dp(48),dp(48),Gravity.END|Gravity.BOTTOM);holdParams.rightMargin=dp(12);holdParams.bottomMargin=dp(52);stage.addView(holdMaskButton,holdParams);
        panel=column();panel.setTag("brush-controls");panel.setPadding(dp(12),dp(4),dp(12),dp(8));panel.setBackgroundColor(PANEL);
        LinearLayout tools=row();tools.setGravity(Gravity.CENTER);
        addButton=PhotoWorkspaceUi.icon(getContext(),"brush","涂抹补选","brush-add",()->setErase(false));eraseButton=PhotoWorkspaceUi.icon(getContext(),"erase","擦除选区","brush-erase",()->setErase(true));
        undoButton=PhotoWorkspaceUi.icon(getContext(),"undo","撤销笔触","brush-undo",this::undo);redoButton=PhotoWorkspaceUi.icon(getContext(),"redo","重做笔触","brush-redo",this::redo);
        Button fit=PhotoWorkspaceUi.icon(getContext(),"fit","适应照片","brush-fit",photo::resetViewport);Button clear=button("清空",this::clear);clear.setTag("brush-clear");
        for(Button b:new Button[]{addButton,eraseButton,undoButton,redoButton,fit,clear})tools.addView(b,new LinearLayout.LayoutParams(dp(48),dp(48)));HorizontalScrollView toolScroll=new HorizontalScrollView(getContext());toolScroll.setHorizontalScrollBarEnabled(false);toolScroll.setFillViewport(true);toolScroll.addView(tools);panel.addView(toolScroll,new LinearLayout.LayoutParams(-1,dp(48)));
        addSlider(panel,"大小","brush-size",119,39,p->{radius=(p+1)/1000.0;return String.format(Locale.ROOT,"%.1f%%",radius*100);});
        addSlider(panel,"羽化","brush-feather",100,65,p->{feather=p/100.0;return p+"%";});
        ScrollView scroll=new ScrollView(getContext());scroll.setTag("brush-dock");scroll.setVerticalScrollBarEnabled(false);scroll.addView(panel);body.addView(scroll,new LinearLayout.LayoutParams(-1,dp(156)));
        body.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->arrange(scroll));
        root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){Insets safe=insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());root.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else root.setPadding(insets.getStableInsetLeft(),insets.getStableInsetTop(),insets.getStableInsetRight(),insets.getStableInsetBottom());body.post(()->arrange(scroll));return insets;});
        PhotoPrismaStyle.workspace(root,initial);setContentView(root);if(getWindow()!=null){getWindow().setBackgroundDrawableResource(android.R.color.transparent);getWindow().setLayout(-1,-1);}root.requestApplyInsets();refresh();
    }
    @Override public void show(){super.show();if(getWindow()!=null)getWindow().setLayout(-1,-1);photo.post(this::flashSelection);}
    private void arrange(ScrollView scroll){if(disposed||body.getWidth()<1||body.getHeight()<2)return;int w=body.getWidth(),h=body.getHeight();boolean side=w>h&&w>=dp(480);body.setOrientation(side?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL);stage.setLayoutParams(side?new LinearLayout.LayoutParams(0,-1,1):new LinearLayout.LayoutParams(-1,0,1));scroll.setLayoutParams(side?new LinearLayout.LayoutParams(Math.min(dp(320),Math.round(w*.44f)),-1):new LinearLayout.LayoutParams(-1,Math.min(dp(156),h/2)));photo.invalidate();}
    private interface SliderValue {String change(int value);}
    private void addSlider(LinearLayout parent,String label,String tag,int max,int initialValue,SliderValue changed){LinearLayout row=row();row.addView(text(label,12,TEXT),new LinearLayout.LayoutParams(dp(44),dp(48)));SeekBar slider=new SeekBar(getContext());slider.setTag(tag);slider.setMax(max);slider.setProgress(initialValue);slider.setProgressTintList(ColorStateList.valueOf(ACCENT));slider.setThumbTintList(ColorStateList.valueOf(ACCENT));row.addView(slider,new LinearLayout.LayoutParams(0,dp(48),1));TextView value=text(changed.change(initialValue),12,ACCENT);value.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);row.addView(value,new LinearLayout.LayoutParams(dp(52),dp(48)));slider.setContentDescription(label+"，"+value.getText());slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar b,int p,boolean user){value.setText(changed.change(p));b.setContentDescription(label+"，"+value.getText());}public void onStartTrackingTouch(SeekBar b){photo.cancelStroke();}public void onStopTrackingTouch(SeekBar b){}});parent.addView(row);}
    private void setErase(boolean value){if(flashStep>=0)return;photo.cancelStroke();erase=value;refresh();}
    private void remember(AdjustmentRegion before){if(before.equals(region))return;undo.addLast(before);while(undo.size()>32)undo.removeFirst();redo.clear();}
    private void undo(){if(flashStep>=0||undo.isEmpty())return;photo.cancelStroke();redo.addLast(region);region=undo.removeLast();rebuildMask();refresh();flashSelection();}
    private void redo(){if(flashStep>=0||redo.isEmpty())return;photo.cancelStroke();undo.addLast(region);region=redo.removeLast();rebuildMask();refresh();flashSelection();}
    private void clear(){if(flashStep>=0)return;photo.cancelStroke();AdjustmentRegion old=region;region=region.withStrokes(java.util.Collections.emptyList());remember(old);rebuildMask();refresh();}
    private boolean hasCoverage(){for(float value:coverage)if(value>0)return true;return false;}
    private boolean canComplete(){return hasCoverage()||!originalRegion.strokes.isEmpty()&&!region.equals(originalRegion);}
    private void refresh(){if(apply==null)return;addButton.setSelected(!erase);eraseButton.setSelected(erase);undoButton.setEnabled(!undo.isEmpty()&&flashStep<0);redoButton.setEnabled(!redo.isEmpty()&&flashStep<0);undoButton.setAlpha(undoButton.isEnabled()?1:.35f);redoButton.setAlpha(redoButton.isEnabled()?1:.35f);apply.setEnabled(flashStep<0&&!photo.tracking&&canComplete());apply.setAlpha(apply.isEnabled()?1:.45f);boolean canInspect=flashStep<0&&hasCoverage();holdMaskButton.setEnabled(canInspect);holdMaskButton.setAlpha(canInspect?1:.35f);if(!canInspect)setMaskHeld(false);photo.invalidate();}
    /** The acknowledgement never blocks drawing and ends on a clean photograph. */
    private void flashSelection(){stopPreviewFlash();if(disposed||!isShowing()||flashStep>=0||photo.tracking||holdingMask||!hasCoverage())return;previewSingleHighlight=!ValueAnimator.areAnimatorsEnabled();previewFlashStep=0;photo.invalidate();main.postDelayed(previewFlashTick,FLASH_ON_MS);}
    private void advancePreviewFlash(){if(disposed||previewFlashStep<0)return;if(flashStep>=0||photo.tracking){stopPreviewFlash();return;}previewFlashStep++;if(previewSingleHighlight||previewFlashStep>=3){stopPreviewFlash();return;}photo.invalidate();main.postDelayed(previewFlashTick,previewFlashStep==1?FLASH_GAP_MS:FLASH_ON_MS);}
    private void stopPreviewFlash(){main.removeCallbacks(previewFlashTick);previewFlashStep=-1;previewSingleHighlight=false;if(photo!=null&&!disposed)photo.invalidate();}
    private void complete(){if(disposed||flashStep>=0||photo.tracking||!canComplete())return;setMaskHeld(false);stopPreviewFlash();singleCompletionFlash=!ValueAnimator.areAnimatorsEnabled();flashStep=0;status.setText(hasCoverage()?"选区已完成":"选区已清空");refresh();main.postDelayed(flashTick,FLASH_ON_MS);}
    private void advanceFlash(){if(disposed)return;flashStep++;if(singleCompletionFlash||flashStep>=3){AdjustmentRegion result=region;commit.accept(result);dismiss();return;}photo.invalidate();main.postDelayed(flashTick,flashStep==1?FLASH_GAP_MS:FLASH_ON_MS);}
    @Override public void onBackPressed(){if(flashStep>=0){main.removeCallbacks(flashTick);flashStep=-1;status.setText(sourcePositioning?"按塑形前画面定位 · 完成后恢复塑形":"单指涂抹 · 双指缩放和移动");refresh();return;}super.onBackPressed();}
    private void setMaskHeld(boolean value){main.removeCallbacks(maskPeekEnd);stopPreviewFlash();holdingMask=value&&!disposed&&flashStep<0&&hasCoverage();if(!holdingMask)maskPointer=-1;if(holdMaskButton!=null){holdMaskButton.setSelected(holdingMask);holdMaskButton.setPressed(holdingMask);}if(!disposed)photo.invalidate();}
    private void peekMask(){setMaskHeld(true);if(holdingMask)main.postDelayed(maskPeekEnd,650);}
    private boolean holdMaskTouch(MotionEvent event){int action=event.getActionMasked();if(action==MotionEvent.ACTION_DOWN){if(!holdMaskButton.isEnabled()||event.getPointerCount()!=1)return false;maskPointer=event.getPointerId(0);setMaskHeld(true);holdMaskButton.getParent().requestDisallowInterceptTouchEvent(true);return true;}if(action==MotionEvent.ACTION_MOVE){int index=event.findPointerIndex(maskPointer);if(event.getPointerCount()!=1||index<0||event.getX(index)<0||event.getX(index)>holdMaskButton.getWidth()||event.getY(index)<0||event.getY(index)>holdMaskButton.getHeight())setMaskHeld(false);return true;}if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL||action==MotionEvent.ACTION_OUTSIDE||action==MotionEvent.ACTION_POINTER_DOWN||action==MotionEvent.ACTION_POINTER_UP){setMaskHeld(false);holdMaskButton.getParent().requestDisallowInterceptTouchEvent(false);return true;}return true;}
    @Override public void onWindowFocusChanged(boolean hasFocus){super.onWindowFocusChanged(hasFocus);if(!hasFocus){setMaskHeld(false);photo.cancelStroke();}}
    @Override public void dismiss(){if(!disposed){setMaskHeld(false);disposed=true;main.removeCallbacks(flashTick);stopPreviewFlash();photo.cancelStroke();mask.recycle();}super.dismiss();}
    private void rebuildMask(){AdjustmentRegion.Brush brush=region.compileBrush(initial.getWidth(),initial.getHeight());for(int y=0;y<maskHeight;y++)for(int x=0;x<maskWidth;x++){int i=y*maskWidth+x;coverage[i]=(float)brush.weight((x+.5)/maskWidth,(y+.5)/maskHeight);maskPixels[i]=(Math.round(coverage[i]*SOFT_MASK_ALPHA)<<24)|0x00fff1e4;}Arrays.fill(strokeCoverage,0);mask.setPixels(maskPixels,0,maskWidth,0,0,maskWidth,maskHeight);if(photo!=null)photo.invalidate();}
    /** Keep the already-computed live stroke; release never reevaluates older vector paths. */
    private void commitLiveCoverage(){for(int i=0;i<coverage.length;i++){float weight=strokeCoverage[i];if(weight>0)coverage[i]=erase?coverage[i]*(1-weight):coverage[i]+(1-coverage[i])*weight;}restoreMask();}
    private void restoreMask(){Arrays.fill(strokeCoverage,0);for(int i=0;i<coverage.length;i++)maskPixels[i]=(Math.round(coverage[i]*SOFT_MASK_ALPHA)<<24)|0x00fff1e4;mask.setPixels(maskPixels,0,maskWidth,0,0,maskWidth,maskHeight);if(photo!=null)photo.invalidate();}
    private void liveSegment(double ax,double ay,double bx,double by){
        double w=initial.getWidth(),h=initial.getHeight(),r=radius*Math.min(w,h),vx=(bx-ax)*w,vy=(by-ay)*h,len=vx*vx+vy*vy;
        int left=Math.max(0,(int)Math.floor((Math.min(ax,bx)-r/w)*maskWidth)),right=Math.min(maskWidth-1,(int)Math.ceil((Math.max(ax,bx)+r/w)*maskWidth));int top=Math.max(0,(int)Math.floor((Math.min(ay,by)-r/h)*maskHeight)),bottom=Math.min(maskHeight-1,(int)Math.ceil((Math.max(ay,by)+r/h)*maskHeight));
        for(int y=top;y<=bottom;y++)for(int x=left;x<=right;x++){double px=(x+.5)/maskWidth*w-ax*w,py=(y+.5)/maskHeight*h-ay*h,t=len==0?0:Math.max(0,Math.min(1,(px*vx+py*vy)/len));double d=Math.hypot(px-t*vx,py-t*vy)/r,weight;if(d>=1)weight=0;else if(feather<=0||d<=1-feather)weight=1;else{double f=(d-1+feather)/feather;weight=1-f*f*(3-2*f);}int i=y*maskWidth+x;if(weight<=strokeCoverage[i])continue;strokeCoverage[i]=(float)weight;double value=erase?coverage[i]*(1-weight):coverage[i]+(1-coverage[i])*weight;maskPixels[i]=((int)Math.round(value*SOFT_MASK_ALPHA)<<24)|0x00fff1e4;}
        mask.setPixels(maskPixels,0,maskWidth,0,0,maskWidth,maskHeight);photo.invalidate();
    }
    private final class PhotoCanvas extends View {
        final RectF frame=new RectF();private final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);private final Paint flashInk=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);private final ArrayList<Double> path=new ArrayList<>();
        private final ScaleGestureDetector scale;private float zoom=1,panX,panY,lastX,lastY;private boolean tracking,navigating;
        PhotoCanvas(){super(PhotoBrushDialog.this.getContext());flashInk.setColorFilter(new ColorMatrixColorFilter(new float[]{1,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,(float)FLASH_MASK_ALPHA/SOFT_MASK_ALPHA,0}));setTag("brush-canvas");setFocusable(true);setClickable(true);setContentDescription("涂抹选区照片，单指涂抹或擦除，双指缩放和移动");scale=new ScaleGestureDetector(getContext(),new ScaleGestureDetector.SimpleOnScaleGestureListener(){public boolean onScale(ScaleGestureDetector d){float next=Math.max(1,Math.min(8,zoom*d.getScaleFactor())),ratio=next/zoom,fx=d.getFocusX()-getWidth()/2f,fy=d.getFocusY()-getHeight()/2f;panX=fx-(fx-panX)*ratio;panY=fy-(fy-panY)*ratio;zoom=next;bounds();invalidate();return true;}});scale.setQuickScaleEnabled(false);scale.setStylusScaleEnabled(false);}
        @Override protected void onSizeChanged(int w,int h,int ow,int oh){super.onSizeChanged(w,h,ow,oh);if(w<1||h<1)return;if(ow>0&&oh>0&&!frame.isEmpty()){double cx=(ow/2.0-frame.left)/frame.width(),cy=(oh/2.0-frame.top)/frame.height();float fit=Math.min(w/(float)initial.getWidth(),h/(float)initial.getHeight());panX=(float)((.5-cx)*initial.getWidth()*fit*zoom);panY=(float)((.5-cy)*initial.getHeight()*fit*zoom);}cancelStroke();navigating=false;bounds();}
        void resetViewport(){cancelStroke();zoom=1;panX=panY=0;bounds();invalidate();}
        private void bounds(){float fit=Math.min(getWidth()/(float)initial.getWidth(),getHeight()/(float)initial.getHeight()),w=initial.getWidth()*fit*zoom,h=initial.getHeight()*fit*zoom,mx=Math.max(0,(w-getWidth())/2),my=Math.max(0,(h-getHeight())/2);panX=Math.max(-mx,Math.min(mx,panX));panY=Math.max(-my,Math.min(my,panY));frame.set((getWidth()-w)/2+panX,(getHeight()-h)/2+panY,(getWidth()+w)/2+panX,(getHeight()+h)/2+panY);}
        private void cancelStroke(){setMaskHeld(false);boolean pending=tracking||!path.isEmpty();tracking=false;path.clear();if(pending&&!disposed)restoreMask();if(!disposed)refresh();}
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);if(disposed)return;bounds();ink.setAlpha(255);canvas.drawBitmap(initial,null,frame,ink);boolean completing=flashStep==0||flashStep==2;if(completing||flashStep<0&&(tracking||holdingMask||previewFlashStep>=0)){canvas.save();canvas.clipRect(frame);canvas.drawBitmap(mask,null,frame,(completing||tracking||holdingMask||previewFlashStep==0||previewFlashStep==2)?flashInk:ink);canvas.restore();}}
        @Override public boolean onTouchEvent(MotionEvent event){if(disposed||flashStep>=0)return false;bounds();int action=event.getActionMasked();scale.onTouchEvent(event);
            if(action==MotionEvent.ACTION_DOWN){cancelStroke();navigating=false;tracking=frame.contains(event.getX(),event.getY());lastX=event.getX();lastY=event.getY();if(tracking){double x=nx(event.getX()),y=ny(event.getY());path.add(x);path.add(y);liveSegment(x,y,x,y);}refresh();return true;}
            if(event.getPointerCount()>1){if(!navigating){cancelStroke();navigating=true;float x=0,y=0;for(int i=0;i<event.getPointerCount();i++){x+=event.getX(i);y+=event.getY(i);}lastX=x/event.getPointerCount();lastY=y/event.getPointerCount();}float x=0,y=0;for(int i=0;i<event.getPointerCount();i++){x+=event.getX(i);y+=event.getY(i);}x/=event.getPointerCount();y/=event.getPointerCount();if(action==MotionEvent.ACTION_MOVE){panX+=x-lastX;panY+=y-lastY;bounds();}lastX=x;lastY=y;invalidate();return true;}
            if(navigating){if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL)navigating=false;return true;}
            if(!tracking)return true;double x=nx(event.getX()),y=ny(event.getY());
            if(action==MotionEvent.ACTION_MOVE||action==MotionEvent.ACTION_UP){int n=path.size();double ax=path.get(n-2),ay=path.get(n-1);if(Math.hypot((x-ax)*initial.getWidth(),(y-ay)*initial.getHeight())>.001*Math.min(initial.getWidth(),initial.getHeight())&&path.size()<PhotoPortrait.MAX_STROKE_POINTS*2){path.add(x);path.add(y);liveSegment(ax,ay,x,y);}}
            if(action==MotionEvent.ACTION_UP){tracking=false;boolean accepted=false;try{double[] points=new double[path.size()];for(int i=0;i<points.length;i++)points[i]=path.get(i);AdjustmentRegion before=region;region=region.addStroke(new PhotoPortrait.Stroke(points,radius,feather,erase));remember(before);accepted=true;status.setText(erase?"已擦除 · 可继续涂抹或完成选区":"已选中 · 可继续涂抹或完成选区");}catch(IllegalArgumentException limit){status.setText("笔触数量已达上限，请撤销或清空后重试。");}path.clear();if(accepted)commitLiveCoverage();else restoreMask();refresh();if(accepted)flashSelection();performClick();return true;}
            if(action==MotionEvent.ACTION_CANCEL){cancelStroke();}return true;
        }
        private double nx(float x){return Math.max(0,Math.min(1,(x-frame.left)/frame.width()));}
        private double ny(float y){return Math.max(0,Math.min(1,(y-frame.top)/frame.height()));}
        @Override public boolean performClick(){return super.performClick();}
    }
    private Button button(String label,Runnable task){Button b=new Button(getContext());b.setText(label);b.setAllCaps(false);b.setTextSize(12);b.setTextColor(TEXT);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setPadding(dp(4),0,dp(4),0);b.setIncludeFontPadding(false);b.setGravity(Gravity.CENTER);b.setStateListAnimator(null);b.setBackgroundColor(Color.TRANSPARENT);b.setOnClickListener(v->task.run());return b;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.HORIZONTAL);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private LinearLayout column(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.VERTICAL);return v;}
    private TextView text(String value,float size,int color){TextView v=new TextView(getContext());v.setText(value);v.setTextSize(size);v.setTextColor(color);v.setIncludeFontPadding(false);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private int dp(float n){return Math.round(n*getContext().getResources().getDisplayMetrics().density);}
}
