package cc.huevia.ui;

import android.app.Activity;
import android.app.Application;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.InsetDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.os.Bundle;
import android.view.GestureDetector;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import cc.huevia.album.PhotoExportPreview;
import cc.huevia.album.PhotoExportSpec;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.Locale;

/** Actual JPEG pixels with an identical-canvas, lossless pre-encoder comparison. */
public final class PhotoExportPreviewDialog extends Dialog implements AutoCloseable {
    private static final int BG=0xff0a0908,TEXT=0xfff6f1eb,ACCENT=0xfff2b48c;
    private final Activity activity;
    private final PhotoExportPreview.Request request;
    private final PhotoExportSpec spec;
    private final String displayName;
    private PhotoExportPreview source;
    private CanvasView canvas;
    private TextView metric,status;
    private Button jpeg,before,fit,one,two,retry;
    private LinearLayout feedback,comparison,zoom;
    private FrameLayout stage;
    private PhotoExportPreview.Info info;
    private final ArrayList<PhotoGlassDrawable> glasses=new ArrayList<>();
    private final IdentityHashMap<Button,Boolean> selections=new IdentityHashMap<>();
    private boolean released,registered,paused;
    private final Application.ActivityLifecycleCallbacks lifecycle=new Application.ActivityLifecycleCallbacks(){
        public void onActivityCreated(Activity a,Bundle b){}public void onActivityStarted(Activity a){if(a==activity&&!released){paused=false;if(canvas!=null)canvas.resume();}}
        public void onActivityResumed(Activity a){}public void onActivityPaused(Activity a){}
        public void onActivityStopped(Activity a){if(a==activity&&!released){paused=true;if(canvas!=null)canvas.pause();}}
        public void onActivitySaveInstanceState(Activity a,Bundle b){}public void onActivityDestroyed(Activity a){if(a==activity)close();}
    };
    public static PhotoExportPreviewDialog show(Activity activity,PhotoExportPreview.Request request,PhotoExportSpec spec,String displayName){
        if(activity.isFinishing()||activity.isDestroyed())return null;
        PhotoExportPreviewDialog dialog=new PhotoExportPreviewDialog(activity,request,spec,displayName);dialog.show();PhotoEditorTypography.apply(dialog);return dialog;
    }
    public PhotoExportPreviewDialog(Activity activity,PhotoExportPreview.Request request,PhotoExportSpec spec,String displayName){
        super(activity,android.R.style.Theme_Material_NoActionBar);if(request==null||spec==null)throw new IllegalArgumentException("request/spec");this.activity=activity;this.request=request;this.spec=spec;this.displayName=displayName==null?request.source.getName():displayName;
        setOnDismissListener(ignored->release());
    }
    @Override protected void onCreate(Bundle saved){
        super.onCreate(saved);configureWindow();FrameLayout page=new FrameLayout(activity);page.setBackgroundColor(BG);page.setTag("export-preview-page");
        page.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){android.graphics.Insets safe=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());v.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
        stage=new FrameLayout(activity);page.addView(stage,new FrameLayout.LayoutParams(-1,-1));canvas=new CanvasView();canvas.setTag("export-preview-canvas");stage.addView(canvas,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout header=row();header.setPadding(dp(8),0,dp(8),0);header.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0x99000000,0x00000000}));
        Button back=button("",()->dismiss());back.setTag("export-preview-back");back.setContentDescription("返回导出设置");AppIcon icon=new AppIcon(AppIcon.Kind.BACK,TEXT,density());icon.setBounds(0,0,dp(22),dp(22));back.setCompoundDrawables(icon,null,null,null);back.setPadding(dp(12),0,dp(12),0);header.addView(back,new LinearLayout.LayoutParams(dp(48),dp(48)));
        LinearLayout titles=column();titles.setGravity(Gravity.CENTER);TextView title=text("成品预览",13,TEXT);title.setGravity(Gravity.CENTER);title.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));titles.addView(title);TextView name=text(displayName,11,0xddffffff);name.setSingleLine(true);name.setEllipsize(android.text.TextUtils.TruncateAt.MIDDLE);name.setGravity(Gravity.CENTER);titles.addView(name,new LinearLayout.LayoutParams(-1,dp(20)));header.addView(titles,new LinearLayout.LayoutParams(0,dp(48),1));
        Button done=button("完成",this::dismiss);done.setTextColor(ACCENT);done.setTag("export-preview-done");header.addView(done,new LinearLayout.LayoutParams(dp(52),dp(48)));stage.addView(header,new FrameLayout.LayoutParams(-1,dp(52),Gravity.TOP));
        comparison=row();comparison.setTag("export-preview-compare");jpeg=segment("JPEG",()->canvas.mode(PhotoExportPreview.JPEG));jpeg.setTag("export-preview-jpeg");before=segment("编码前",()->canvas.mode(PhotoExportPreview.BEFORE_ENCODING));before.setTag("export-preview-before");comparison.addView(jpeg,new LinearLayout.LayoutParams(0,dp(48),1));comparison.addView(before,new LinearLayout.LayoutParams(0,dp(48),1));glass(comparison,24);FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(dp(220),dp(48),Gravity.TOP|Gravity.CENTER_HORIZONTAL);cp.topMargin=dp(58);stage.addView(comparison,cp);
        metric=text("",11,TEXT);metric.setTag("export-preview-metric");metric.setSingleLine(true);metric.setGravity(Gravity.CENTER);metric.setPadding(dp(10),0,dp(10),0);glass(metric,12);metric.setVisibility(View.GONE);FrameLayout.LayoutParams mp=new FrameLayout.LayoutParams(-2,dp(30),Gravity.TOP|Gravity.END);mp.topMargin=dp(116);mp.rightMargin=dp(12);stage.addView(metric,mp);
        feedback=column();feedback.setGravity(Gravity.CENTER);feedback.setPadding(dp(12),dp(6),dp(12),dp(6));glass(feedback,14);status=text("生成中…",12,TEXT);status.setTag("export-preview-status");status.setGravity(Gravity.CENTER);status.setMaxLines(2);status.setMaxWidth(dp(280));feedback.addView(status);retry=button("重试",this::load);retry.setTag("export-preview-retry");retry.setVisibility(View.GONE);feedback.addView(retry,new LinearLayout.LayoutParams(-1,dp(40)));FrameLayout.LayoutParams fp=new FrameLayout.LayoutParams(-2,-2,Gravity.CENTER);fp.leftMargin=dp(20);fp.rightMargin=dp(20);stage.addView(feedback,fp);
        zoom=row();zoom.setTag("export-preview-zoom");fit=segment("适应",()->canvas.fit());one=segment("100%",()->canvas.zoom(1));two=segment("200%",()->canvas.zoom(2));fit.setTag("export-preview-fit");one.setTag("export-preview-100");two.setTag("export-preview-200");for(Button b:new Button[]{fit,one,two})zoom.addView(b,new LinearLayout.LayoutParams(0,dp(48),1));glass(zoom,24);FrameLayout.LayoutParams zp=new FrameLayout.LayoutParams(dp(222),dp(48),Gravity.BOTTOM|Gravity.START);zp.leftMargin=dp(12);zp.bottomMargin=dp(12);stage.addView(zoom,zp);
        stage.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{canvas.controlsBottom=zoom.getHeight()+dp(24);refreshGlass();});setContentView(page);activity.getApplication().registerActivityLifecycleCallbacks(lifecycle);registered=true;load();
    }
    private void load(){
        if(released)return;if(canvas!=null)canvas.dropSource();if(source!=null)source.close();source=new PhotoExportPreview(request);canvas.source=source;info=null;metric.setVisibility(View.GONE);feedback.setVisibility(View.VISIBLE);retry.setVisibility(View.GONE);status.setText("生成中…");controls(false);final PhotoExportPreview active=source;
        source.start(spec,new PhotoExportPreview.Listener(){
            public void progress(double value){if(!released&&source==active)status.setText("生成中 "+Math.min(99,Math.max(0,(int)Math.round(value*100)))+"%");}
            public void ready(PhotoExportPreview.Info ready){if(released||source!=active)return;info=ready;metric.setText(String.format(Locale.ROOT,"%d×%d · JPEG %d · %s",ready.width,ready.height,ready.quality,bytes(ready.jpegBytes)));metric.setContentDescription("实际导出尺寸 "+ready.width+"乘"+ready.height+"像素，JPEG 质量"+ready.quality+"，实际文件大小"+ready.jpegBytes+"字节");metric.setVisibility(View.VISIBLE);controls(true);canvas.ready(ready);if(paused)canvas.pause();refreshGlass();}
            public void failed(String message){if(released||source!=active)return;status.setText(message);retry.setVisibility(View.VISIBLE);feedback.setVisibility(View.VISIBLE);controls(false);refreshGlass();}
            public void invalidated(){invalid();}
        });
    }
    private void controls(boolean ready){for(Button b:new Button[]{jpeg,before,fit,one,two}){b.setEnabled(ready);b.setAlpha(ready?1:.45f);}refreshSelection();}
    private void refreshSelection(){if(canvas==null)return;select(jpeg,canvas.mode==PhotoExportPreview.JPEG);select(before,canvas.mode==PhotoExportPreview.BEFORE_ENCODING);select(fit,canvas.viewport.fitting);select(one,!canvas.viewport.fitting&&Math.abs(canvas.viewport.scale-1)<.005);select(two,!canvas.viewport.fitting&&Math.abs(canvas.viewport.scale-2)<.005);}
    private void invalid(){if(released)return;Toast.makeText(activity,"照片或编辑状态已变化，请重新打开成品预览。",Toast.LENGTH_SHORT).show();dismiss();}
    private void configureWindow(){Window w=getWindow();if(w==null)return;w.setBackgroundDrawable(new ColorDrawable(BG));w.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);w.setStatusBarColor(BG);w.setNavigationBarColor(BG);if(Build.VERSION.SDK_INT>=29){w.setStatusBarContrastEnforced(false);w.setNavigationBarContrastEnforced(false);}if(Build.VERSION.SDK_INT>=30){w.setDecorFitsSystemWindows(false);WindowInsetsController controls=w.getInsetsController();if(controls!=null)controls.setSystemBarsAppearance(0,WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);}else w.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);}
    @Override public void show(){super.show();Window window=getWindow();if(window!=null)window.setLayout(-1,-1);}
    @Override public void close(){dismiss();release();}
    private void release(){if(released)return;released=true;if(registered){activity.getApplication().unregisterActivityLifecycleCallbacks(lifecycle);registered=false;}if(canvas!=null)canvas.close();if(source!=null){source.close();source=null;}for(PhotoGlassDrawable glass:glasses)glass.close();glasses.clear();}
    private void glass(View owner,float radius){PhotoGlassDrawable background=new PhotoGlassDrawable(canvas,owner,density(),radius);owner.setBackground(background);glasses.add(background);}
    private void refreshGlass(){for(PhotoGlassDrawable glass:glasses)glass.refresh();}
    private void select(Button button,boolean selected){if(button==null)return;Boolean previous=selections.get(button);if(previous!=null&&previous==selected)return;selections.put(button,selected);button.setSelected(selected);button.setTextColor(selected?0xff2a1c12:TEXT);GradientDrawable fill=new GradientDrawable();fill.setColor(selected?ACCENT:Color.TRANSPARENT);fill.setCornerRadius(dp(20));button.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffffff),new InsetDrawable(fill,dp(4),dp(4),dp(4),dp(4)),null));}
    private Button segment(String label,Runnable action){Button b=button(label,action);b.setContentDescription(label);return b;}
    private Button button(String label,Runnable action){Button b=new Button(activity);b.setText(label);b.setAllCaps(false);b.setTextSize(12);b.setTextColor(TEXT);b.setIncludeFontPadding(false);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(0);b.setMinimumHeight(0);b.setPadding(dp(8),0,dp(8),0);b.setStateListAnimator(null);b.setBackgroundColor(Color.TRANSPARENT);b.setOnClickListener(v->action.run());return b;}
    private TextView text(String value,float size,int color){TextView t=new TextView(activity);t.setText(value);t.setTextSize(size);t.setTextColor(color);t.setIncludeFontPadding(false);return t;}
    private LinearLayout row(){LinearLayout row=new LinearLayout(activity);row.setGravity(Gravity.CENTER_VERTICAL);return row;}
    private LinearLayout column(){LinearLayout column=new LinearLayout(activity);column.setOrientation(LinearLayout.VERTICAL);return column;}
    private static String bytes(long value){return value>=1024*1024?String.format(Locale.ROOT,"%.2f MB",value/(1024.0*1024)):String.format(Locale.ROOT,"%.0f KB",value/1024.0);}
    private static void textIfChanged(TextView view,String value){if(!value.contentEquals(view.getText()))view.setText(value);}
    private float density(){return activity.getResources().getDisplayMetrics().density;}
    private int dp(float value){return Math.round(value*density());}

    private final class CanvasView extends View implements AutoCloseable {
        final PhotoDetailViewport viewport=new PhotoDetailViewport();
        final Paint imagePaint=new Paint(),linePaint=new Paint(Paint.ANTI_ALIAS_FLAG),miniPaint=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
        final RectF mini=new RectF(),locator=new RectF();final Path clip=new Path();
        final GestureDetector gestures;final ScaleGestureDetector scales;
        PhotoExportPreview source;PhotoExportPreview.Frame frame;
        int mode=PhotoExportPreview.JPEG,controlsBottom;
        long revision,requestSerial;
        boolean closed,paused,inFlight,queued,scheduled,miniDrag;
        final Runnable submit=this::submit;
        final Runnable validity=new Runnable(){public void run(){if(closed||paused)return;if(source!=null&&!source.valid()){invalid();return;}postDelayed(this,750);}};
        CanvasView(){super(activity);setBackgroundColor(BG);setClickable(true);setFocusable(true);setContentDescription("实际 JPEG 成品。双击切换适应与100%，双指缩放，拖动查看。");linePaint.setColor(ACCENT);linePaint.setStrokeWidth(dp(1.5f));linePaint.setStyle(Paint.Style.STROKE);gestures=new GestureDetector(activity,new GestureDetector.SimpleOnGestureListener(){public boolean onDown(MotionEvent e){return true;}public boolean onDoubleTap(MotionEvent e){if(viewport.imageWidth>0){if(viewport.fitting)viewport.zoom(1,e.getX(),e.getY());else viewport.fitImage();changed();}return true;}public boolean onScroll(MotionEvent first,MotionEvent now,float dx,float dy){if(!scales.isInProgress()){viewport.move(-dx,-dy);changed();}return true;}public boolean onSingleTapConfirmed(MotionEvent e){performClick();return true;}});scales=new ScaleGestureDetector(activity,new ScaleGestureDetector.SimpleOnScaleGestureListener(){public boolean onScale(ScaleGestureDetector d){viewport.zoom(viewport.scale*d.getScaleFactor(),d.getFocusX(),d.getFocusY());changed();return true;}});post(validity);}
        void ready(PhotoExportPreview.Info info){viewport.image(info.width,info.height);viewport.fitImage();changed();}
        void mode(int next){if(mode==next||info==null)return;mode=next;requestSerial++;inFlight=false;frame=null;if(source!=null)source.cancelFrames();changed();}
        void fit(){if(info==null)return;viewport.fitImage();changed();}
        void zoom(double value){if(info==null)return;viewport.zoom(value,getWidth()/2.0,getHeight()/2.0);changed();}
        void changed(){if(closed||paused||source==null||info==null)return;revision++;queued=true;textIfChanged(status,"读取中…");feedback.setVisibility(frame==null?View.VISIBLE:View.GONE);retry.setVisibility(View.GONE);refreshSelection();invalidate();refreshGlass();if(!inFlight&&!scheduled){scheduled=true;postOnAnimation(submit);}}
        void submit(){scheduled=false;if(closed||paused||source==null||info==null||inFlight||!queued||getWidth()<1||getHeight()<1)return;if(!source.valid()){invalid();return;}queued=false;inFlight=true;long token=revision,request=++requestSerial;int requestedMode=mode;PhotoExportPreview active=source;source.frame(mode,getWidth(),getHeight(),viewport.fitting?0:viewport.scale,viewport.centerX/viewport.imageWidth,viewport.centerY/viewport.imageHeight,new PhotoExportPreview.FrameCallback(){boolean active(){return !closed&&!paused&&request==requestSerial&&active==source&&requestedMode==mode;}public void loaded(PhotoExportPreview.Frame result){if(!active())return;inFlight=false;frame=result;feedback.setVisibility(View.GONE);invalidate();refreshGlass();queued=token!=revision;if(queued&&!scheduled){scheduled=true;postOnAnimation(submit);}}public void failed(String message){if(!active())return;inFlight=false;status.setText(message);retry.setVisibility(View.VISIBLE);feedback.setVisibility(View.VISIBLE);refreshGlass();}public void invalidated(){if(active())invalid();}});}
        void dropSource(){requestSerial++;removeCallbacks(submit);scheduled=false;inFlight=false;queued=false;frame=null;source=null;viewport.image(0,0);invalidate();}
        void pause(){if(closed||paused)return;paused=true;requestSerial++;removeCallbacks(submit);removeCallbacks(validity);scheduled=false;inFlight=false;queued=false;frame=null;if(source!=null)source.releaseMemory();invalidate();}
        void resume(){if(closed||!paused)return;paused=false;post(validity);changed();}
        @Override protected void onSizeChanged(int w,int h,int ow,int oh){viewport.canvas(w,h);changed();}
        @Override protected void onDraw(Canvas output){super.onDraw(output);PhotoExportPreview.Frame shown=frame;if(shown==null||shown.mode!=mode)return;float left=(float)viewport.left(),top=(float)viewport.top();RectF bounds=new RectF(left,top,left+shown.width*(float)viewport.scale,top+shown.height*(float)viewport.scale);imagePaint.setFilterBitmap(true);output.drawBitmap(shown.overview,null,bounds,imagePaint);imagePaint.setFilterBitmap(viewport.scale<1);for(PhotoExportPreview.Tile tile:shown.tiles){RectF destination=new RectF(left+tile.bounds.left*(float)viewport.scale,top+tile.bounds.top*(float)viewport.scale,left+tile.bounds.right*(float)viewport.scale,top+tile.bounds.bottom*(float)viewport.scale);output.drawBitmap(tile.bitmap,null,destination,imagePaint);}drawLocator(output,shown);}
        private void drawLocator(Canvas output,PhotoExportPreview.Frame shown){mini.setEmpty();locator.setEmpty();if(viewport.scale<=viewport.fit()+.0001)return;float width=dp(82),height=width*shown.height/shown.width;if(height>dp(108)){height=dp(108);width=height*shown.width/shown.height;}float right=getWidth()-dp(12),bottom=getHeight()-dp(12);if(getWidth()<dp(360))bottom-=controlsBottom;mini.set(right-width,bottom-height,right,bottom);clip.reset();clip.addRoundRect(mini,dp(10),dp(10),Path.Direction.CW);int save=output.save();output.clipPath(clip);output.drawColor(0xc0000000);output.drawBitmap(shown.overview,null,mini,miniPaint);output.restoreToCount(save);linePaint.setColor(0x88ffffff);output.drawRoundRect(mini,dp(10),dp(10),linePaint);double left=Math.max(0,viewport.centerX-viewport.canvasWidth/(2*viewport.scale)),top=Math.max(0,viewport.centerY-viewport.canvasHeight/(2*viewport.scale)),rightEdge=Math.min(shown.width,viewport.centerX+viewport.canvasWidth/(2*viewport.scale)),bottomEdge=Math.min(shown.height,viewport.centerY+viewport.canvasHeight/(2*viewport.scale));locator.set((float)(mini.left+left/shown.width*mini.width()),(float)(mini.top+top/shown.height*mini.height()),(float)(mini.left+rightEdge/shown.width*mini.width()),(float)(mini.top+bottomEdge/shown.height*mini.height()));linePaint.setColor(ACCENT);output.drawRoundRect(locator,dp(4),dp(4),linePaint);}
        private void locate(float x,float y){if(mini.isEmpty())return;viewport.center((x-mini.left)/mini.width()*viewport.imageWidth,(y-mini.top)/mini.height()*viewport.imageHeight);changed();}
        @Override public boolean onTouchEvent(MotionEvent event){if(info==null)return true;if(event.getActionMasked()==MotionEvent.ACTION_DOWN){miniDrag=mini.contains(event.getX(),event.getY());if(miniDrag){locate(event.getX(),event.getY());return true;}}if(miniDrag){if(event.getActionMasked()==MotionEvent.ACTION_MOVE)locate(event.getX(),event.getY());if(event.getActionMasked()==MotionEvent.ACTION_UP||event.getActionMasked()==MotionEvent.ACTION_CANCEL){miniDrag=false;performClick();}return true;}scales.onTouchEvent(event);gestures.onTouchEvent(event);if(event.getActionMasked()==MotionEvent.ACTION_UP||event.getActionMasked()==MotionEvent.ACTION_CANCEL){if(queued&&!inFlight){removeCallbacks(submit);scheduled=false;submit();}}return true;}
        @Override public boolean performClick(){super.performClick();return true;}
        @Override public void close(){if(closed)return;closed=true;requestSerial++;removeCallbacks(submit);removeCallbacks(validity);frame=null;source=null;}
    }
}
