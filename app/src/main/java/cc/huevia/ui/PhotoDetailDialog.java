package cc.huevia.ui;

import android.app.Activity;
import android.app.Application;
import android.app.Dialog;
import android.app.AlertDialog;
import android.view.ContextThemeWrapper;
import android.graphics.Color;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.InsetDrawable;
import android.content.res.ColorStateList;
import android.os.Bundle;
import android.os.Build;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;
import cc.huevia.album.PhotoDetailSource;
import java.util.Locale;
import java.util.ArrayList;

/** Frozen, full-screen detail surface; closing it never mutates drafts, history or exports. */
public final class PhotoDetailDialog extends Dialog implements AutoCloseable {
    private static final int BG=0xff0a0908,TEXT=0xfff6f1eb,ACCENT=0xffffe335;
    private final Activity activity;private final PhotoDetailSource source;private final boolean canCompare;
    private final String displayName;
    private PhotoDetailView detail;private TextView status,metric,filename,savedReason;private Button current,before,fit,one,two,retry;
    private FrameLayout stage,metricAction;private LinearLayout palette,feedback,comparison;private final ArrayList<PhotoGlassDrawable> glasses=new ArrayList<>();
    private boolean hasFailure,hasLoading;private AlertDialog information;
    private int metricWidth=-1,metricHeight=-1,metricPercent=Integer.MIN_VALUE;
    private boolean released,lifecycleRegistered;
    private final Application.ActivityLifecycleCallbacks lifecycle=new Application.ActivityLifecycleCallbacks(){
        public void onActivityCreated(Activity a,Bundle state){}public void onActivityStarted(Activity a){if(a==activity&&detail!=null&&!released)detail.resume();}
        public void onActivityResumed(Activity a){}public void onActivityPaused(Activity a){}
        public void onActivityStopped(Activity a){if(a==activity&&detail!=null&&!released)detail.pause();}
        public void onActivitySaveInstanceState(Activity a,Bundle state){}
        public void onActivityDestroyed(Activity a){if(a==activity)close();}
    };
    public static PhotoDetailDialog show(Activity activity,PhotoDetailSource.Request request){return show(activity,request,request.file.getName());}
    public static PhotoDetailDialog show(Activity activity,PhotoDetailSource.Request request,String displayName){
        PhotoDetailDialog dialog=new PhotoDetailDialog(activity,request,displayName);dialog.show();PhotoEditorTypography.apply(dialog);return dialog;
    }
    public PhotoDetailDialog(Activity activity,PhotoDetailSource.Request request){this(activity,request,request.file.getName());}
    public PhotoDetailDialog(Activity activity,PhotoDetailSource.Request request,String displayName){
        super(activity,android.R.style.Theme_Material_NoActionBar);this.activity=activity;source=new PhotoDetailSource(request);canCompare=request.canCompare;
        this.displayName=displayName==null||displayName.trim().isEmpty()?request.file.getName():displayName.trim();
        setOnDismissListener(dialog->release());setCancelable(true);
    }
    @Override protected void onCreate(Bundle saved){
        super.onCreate(saved);configureWindow();
        FrameLayout page=new FrameLayout(activity);page.setBackgroundColor(BG);page.setTag("detail-page");
        // Exactly one inset owner; the canvas dimensions remain physical pixels.
        page.setOnApplyWindowInsetsListener((view,insets)->{
            if(Build.VERSION.SDK_INT>=30){android.graphics.Insets safe=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());view.setPadding(safe.left,safe.top,safe.right,safe.bottom);}
            else view.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());
            return insets;
        });
        stage=new FrameLayout(activity);stage.setTag("detail-photo-stage");page.addView(stage,new FrameLayout.LayoutParams(-1,-1));
        detail=new PhotoDetailView(activity,source,new PhotoDetailView.Listener(){
            public void state(boolean loading,String message,double scale,boolean fitting,int mode,boolean failed){
                if(released||status==null)return;boolean layoutChanged=hasFailure!=failed;hasFailure=failed;hasLoading=loading;
                textIfChanged(status,message);int statusColor=failed?0xffffb4a7:TEXT;if(status.getCurrentTextColor()!=statusColor)status.setTextColor(statusColor);
                visibleIfChanged(retry,failed);visibleIfChanged(feedback,loading||failed);
                boolean dimensionsReady=detail.contentWidth()>0;
                visibleIfChanged(metricAction,dimensionsReady);
                int width=detail.contentWidth(),height=detail.contentHeight(),percent=detail.hasFullPixels()?(int)Math.round(scale*100):-1;
                if(metricWidth!=width||metricHeight!=height||metricPercent!=percent){
                    metricWidth=width;metricHeight=height;metricPercent=percent;layoutChanged=true;
                    textIfChanged(metric,dimensionsReady?(percent>=0?String.format(Locale.ROOT,"%d×%d px · %d%%",width,height,percent):String.format(Locale.ROOT,"%d×%d px",width,height)):"");
                    metricAction.setContentDescription(dimensionsReady?metric.getText()+"，点按查看细节说明":"照片尺寸尚未载入");
                }
                select(current,mode==PhotoDetailSource.CURRENT);select(before,mode==PhotoDetailSource.BEFORE);
                select(fit,fitting);select(one,!fitting&&Math.abs(scale-1)<.005);select(two,!fitting&&Math.abs(scale-2)<.005);
                enabledIfChanged(fit,dimensionsReady);enabledIfChanged(one,dimensionsReady);enabledIfChanged(two,dimensionsReady);
                if(layoutChanged)positionControls();refreshGlass();
            }
            public void invalidated(){if(!released){AppNotice.show(activity,"照片或编辑状态已变化，请重新打开细节。",false);dismiss();}}
        });
        stage.addView(detail,new FrameLayout.LayoutParams(-1,-1));

        LinearLayout header=row();header.setTag("detail-header");
        header.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0x76000000,Color.TRANSPARENT}));
        header.setPadding(dp(8),0,dp(8),0);
        Button back=button("",13);back.setTag("detail-back");back.setContentDescription("返回照片编辑");
        AppIcon backIcon=new AppIcon(AppIcon.Kind.BACK,TEXT,density());backIcon.setBounds(0,0,dp(22),dp(22));back.setCompoundDrawables(backIcon,null,null,null);back.setPadding(dp(13),0,dp(13),0);back.setOnClickListener(v->dismiss());
        header.addView(back,new LinearLayout.LayoutParams(dp(48),dp(48)));
        LinearLayout titles=column();titles.setGravity(Gravity.CENTER);titles.setTag("detail-title-group");
        TextView title=text(canCompare?"细节预览":"已保存版本",13,Color.WHITE);title.setTag("detail-title");title.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));title.setSingleLine(true);title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        filename=text(displayName,11,0xccffffff);filename.setTag("detail-filename");filename.setSingleLine(true);filename.setEllipsize(android.text.TextUtils.TruncateAt.END);filename.setContentDescription(displayName);
        titles.addView(title,new LinearLayout.LayoutParams(-1,-2));titles.addView(filename,new LinearLayout.LayoutParams(-1,-2));header.addView(titles,new LinearLayout.LayoutParams(0,-2,1));
        Button done=button("完成",13);done.setTag("detail-done");done.setTextColor(ACCENT);done.setContentDescription("完成查看并返回照片编辑");done.setOnClickListener(v->dismiss());header.addView(done,new LinearLayout.LayoutParams(dp(64),dp(48)));
        stage.addView(header,new FrameLayout.LayoutParams(-1,dp(52),Gravity.TOP));

        // 48dp hit row; the shell is inset 4dp vertically to its 40dp visual face.
        comparison=row();comparison.setTag("detail-compare-palette");comparison.setPadding(dp(4),0,dp(4),0);glass(comparison,20,4);
        current=button("当前",12);current.setContentDescription("查看当前效果");before=button("调色前",12);current.setTag("detail-current");before.setTag("detail-before");
        comparison.addView(current,new LinearLayout.LayoutParams(0,controlHeight(),1));comparison.addView(before,new LinearLayout.LayoutParams(0,controlHeight(),1));
        FrameLayout.LayoutParams compareParams=new FrameLayout.LayoutParams(dp(184),controlHeight(),Gravity.TOP|Gravity.CENTER_HORIZONTAL);compareParams.topMargin=dp(54);stage.addView(comparison,compareParams);

        metric=text("",11,0xe0ffffff);metric.setTag("detail-pixel-metric");metric.setSingleLine(true);metric.setEllipsize(android.text.TextUtils.TruncateAt.END);metric.setPadding(dp(10),0,dp(10),0);glass(metric,9,0);metric.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        metricAction=new FrameLayout(activity);metricAction.setTag("detail-pixel-metric-action");metricAction.setFocusable(true);metricAction.setVisibility(View.GONE);metricAction.setContentDescription("照片尺寸与缩放，点按查看细节说明");metricAction.setOnClickListener(v->showInformation());metricAction.addView(metric,new FrameLayout.LayoutParams(-2,dp(26),Gravity.TOP|Gravity.RIGHT));
        FrameLayout.LayoutParams metricParams=new FrameLayout.LayoutParams(-2,dp(48),Gravity.TOP|Gravity.RIGHT);metricParams.setMargins(dp(12),dp(106),dp(12),0);stage.addView(metricAction,metricParams);
        metric.addOnLayoutChangeListener((v,l,t,r,b,oldL,oldT,oldR,oldB)->{if(r-l!=oldR-oldL||b-t!=oldB-oldT){positionControls();refreshGlass();}});

        savedReason=text("调色前不可用",11,Color.WHITE);savedReason.setShadowLayer(dp(2),0,dp(1),Color.BLACK);savedReason.setTag("detail-saved-reason");savedReason.setContentDescription("此版本暂无法恢复调色前内容，当前显示完整已保存文件，包括已烘焙边框。点按尺寸标签可查看说明。");savedReason.setVisibility(canCompare?View.GONE:View.VISIBLE);savedReason.setSingleLine(true);savedReason.setId(View.generateViewId());
        FrameLayout.LayoutParams reasonParams=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);reasonParams.setMargins(dp(12),dp(139),dp(12),0);stage.addView(savedReason,reasonParams);

        feedback=row();feedback.setTag("detail-feedback");feedback.setPadding(dp(10),dp(5),dp(10),dp(5));glass(feedback,16,0);
        status=text("载入中…",11,0xe0ffffff);status.setMaxLines(3);status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);feedback.addView(status,new LinearLayout.LayoutParams(-2,-2));
        retry=button("重试",12);retry.setTag("detail-retry");retry.setTextColor(ACCENT);retry.setVisibility(View.GONE);retry.setOnClickListener(v->detail.retry());feedback.addView(retry,new LinearLayout.LayoutParams(dp(56),dp(48)));
        feedback.setMinimumHeight(dp(28));FrameLayout.LayoutParams feedbackParams=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);feedbackParams.setMargins(dp(20),dp(canCompare?150:176),dp(20),0);stage.addView(feedback,feedbackParams);

        // One 48dp shell/hit area, with each 40dp selected face inset exactly 4dp.
        palette=column();palette.setTag("detail-zoom-palette");palette.setPadding(dp(4),0,dp(4),0);glass(palette,18,0);
        LinearLayout zoom=row();fit=button("适应",12);one=button("100%",12);two=button("200%",12);fit.setTag("detail-fit");one.setTag("detail-100");two.setTag("detail-200");
        zoom.addView(fit,new LinearLayout.LayoutParams(0,controlHeight(),1));zoom.addView(one,new LinearLayout.LayoutParams(0,controlHeight(),1));zoom.addView(two,new LinearLayout.LayoutParams(0,controlHeight(),1));palette.addView(zoom,new LinearLayout.LayoutParams(-1,controlHeight()));
        FrameLayout.LayoutParams paletteParams=new FrameLayout.LayoutParams(dp(216),controlHeight(),Gravity.LEFT|Gravity.BOTTOM);paletteParams.setMargins(dp(12),0,dp(12),dp(12));stage.addView(palette,paletteParams);

        stage.addOnLayoutChangeListener((v,l,t,r,b,oldL,oldT,oldR,oldB)->{positionControls();refreshGlass();});setContentView(page);page.requestApplyInsets();
        current.setOnClickListener(v->detail.mode(PhotoDetailSource.CURRENT));before.setOnClickListener(v->detail.mode(PhotoDetailSource.BEFORE));
        if(!canCompare){before.setEnabled(false);before.setAlpha(.45f);before.setContentDescription("调色前不可用：此版本暂无法恢复调色前内容");}
        fit.setOnClickListener(v->detail.fit());one.setOnClickListener(v->detail.zoom(1));two.setOnClickListener(v->detail.zoom(2));
        fit.setEnabled(false);one.setEnabled(false);two.setEnabled(false);select(current,true);select(fit,true);
        activity.getApplication().registerActivityLifecycleCallbacks(lifecycle);lifecycleRegistered=true;
    }
    @Override protected void onStart(){super.onStart();configureWindow();Window window=getWindow();if(window!=null){window.setLayout(-1,-1);window.getDecorView().requestApplyInsets();}}
    private void configureWindow(){
        Window window=getWindow();if(window==null)return;
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS|WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION);
        window.setBackgroundDrawable(new ColorDrawable(BG));window.getDecorView().setBackgroundColor(BG);
        window.setStatusBarColor(BG);window.setNavigationBarColor(BG);window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING);
        if(Build.VERSION.SDK_INT>=29){window.setStatusBarContrastEnforced(false);window.setNavigationBarContrastEnforced(false);}
        if(Build.VERSION.SDK_INT>=30){window.setDecorFitsSystemWindows(false);WindowInsetsController controls=window.getInsetsController();if(controls!=null)controls.setSystemBarsAppearance(0,WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);}
        else window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
    }
    private void select(Button button,boolean selected){if(button==null||button.getBackground() instanceof InsetDrawable&&button.isSelected()==selected)return;boolean comparing=button==current||button==before;int gap=dp(4),inset=comparing?gap*2:gap;float radius=dp(comparing?20:18)-gap;button.setSelected(selected);button.setTextColor(selected?0xff2a1c12:0xbdffffff);button.setBackground(new InsetDrawable(ripplePixels(selected?ACCENT:Color.TRANSPARENT,radius),0,inset,0,inset));button.setPadding(dp(4),0,dp(4),0);}
    private static void textIfChanged(TextView view,String text){if(!android.text.TextUtils.equals(view.getText(),text))view.setText(text);}
    private static void visibleIfChanged(View view,boolean visible){int visibility=visible?View.VISIBLE:View.GONE;if(view.getVisibility()!=visibility)view.setVisibility(visibility);}
    private static void enabledIfChanged(View view,boolean enabled){if(view.isEnabled()!=enabled)view.setEnabled(enabled);}
    private Button button(String label,float size){Button b=new Button(activity);b.setAllCaps(false);b.setText(label);b.setTextSize(size);b.setTextColor(TEXT);b.setGravity(Gravity.CENTER);b.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));b.setIncludeFontPadding(false);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setMinWidth(0);b.setMinimumWidth(0);b.setStateListAnimator(null);b.setBackground(ripple(Color.TRANSPARENT));b.setPadding(dp(4),0,dp(4),0);return b;}
    private TextView text(String value,float size,int color){TextView t=new TextView(activity);t.setText(value);t.setTextSize(size);t.setTextColor(color);t.setGravity(Gravity.CENTER);t.setIncludeFontPadding(false);return t;}
    private LinearLayout column(){LinearLayout l=new LinearLayout(activity);l.setOrientation(LinearLayout.VERTICAL);return l;}
    private LinearLayout row(){LinearLayout l=new LinearLayout(activity);l.setOrientation(LinearLayout.HORIZONTAL);l.setGravity(Gravity.CENTER_VERTICAL);l.setBaselineAligned(false);return l;}
    private GradientDrawable shape(int color,float radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(radius);return d;}
    private RippleDrawable ripple(int color){return ripple(color,12);}
    private RippleDrawable ripple(int color,float radius){return ripplePixels(color,dp(radius));}
    private RippleDrawable ripplePixels(int color,float radius){return new RippleDrawable(ColorStateList.valueOf(0x25ffffff),shape(color,radius),shape(Color.WHITE,radius));}
    private void glass(View owner,float radius,int verticalInset){int left=owner.getPaddingLeft(),top=owner.getPaddingTop(),right=owner.getPaddingRight(),bottom=owner.getPaddingBottom();PhotoGlassDrawable glass=new PhotoGlassDrawable(detail,owner,density(),radius);owner.setBackground(verticalInset==0?glass:new InsetDrawable(glass,0,dp(verticalInset),0,dp(verticalInset)));owner.setPadding(left,top,right,bottom);glasses.add(glass);}
    private void refreshGlass(){for(PhotoGlassDrawable glass:glasses)glass.refresh();}
    private void positionControls(){
        if(detail==null||palette==null||stage.getWidth()<1)return;
        FrameLayout.LayoutParams params=(FrameLayout.LayoutParams)palette.getLayoutParams();int width=Math.min(dp(activity.getResources().getConfiguration().fontScale>=1.2f?232:216),stage.getWidth()-dp(24));
        if(params.width!=width){params.width=width;palette.setLayoutParams(params);}
        int metricWidth=Math.max(1,stage.getWidth()-dp(24));if(metric.getMaxWidth()!=metricWidth)metric.setMaxWidth(metricWidth);
        int statusWidth=Math.max(dp(48),stage.getWidth()-dp(40)-feedback.getPaddingLeft()-feedback.getPaddingRight()-(hasFailure?dp(56):0));
        if(status.getMaxWidth()!=statusWidth)status.setMaxWidth(statusWidth);
        detail.setFloatingControls(new RectF(dp(12),stage.getHeight()-dp(12)-controlHeight(),dp(12)+width,stage.getHeight()-dp(12)));
        // The 26dp glass tag lives in a real 48dp action above the touchable photo.
    }
    private void showInformation(){
        if(information!=null)information.dismiss();String explanation=canCompare?"当前效果与调色前保持同一构图和查看位置，不含外加边框。\n\n100%：1个图像像素对应1个屏幕物理像素。200%只放大查看，不增加细节。双击照片可切换适应与100%，双指缩放，拖动照片或定位图移动。\n\n细节预览不代表导出压缩效果。":"此版本暂无法恢复调色前内容。查看完整已保存JPEG的文件像素，包括其中已烘焙的边框。\n\n100%：1个图像像素对应1个屏幕物理像素。200%只放大查看，不增加细节。";
        information=new PhotoEditorTypography.Builder(new ContextThemeWrapper(activity,cc.huevia.R.style.AppThemeDark)).setTitle("细节查看说明").setMessage(explanation).setPositiveButton("知道了",null).create();information.show();PhotoEditorTypography.apply(information);
    }
    private float density(){return activity.getResources().getDisplayMetrics().density;}
    // Derive sizes from one rounded gap: fractional densities cannot make one edge 1px tighter.
    private int controlHeight(){return Math.max(dp(48),dp(40)+2*dp(4));}
    private int dp(float value){return Math.round(value*density());}
    private void release(){if(released)return;released=true;if(lifecycleRegistered)activity.getApplication().unregisterActivityLifecycleCallbacks(lifecycle);if(information!=null)information.dismiss();if(detail!=null)detail.close();for(PhotoGlassDrawable glass:glasses)glass.close();glasses.clear();source.close();}
    @Override public void dismiss(){super.dismiss();release();}
    @Override public void close(){dismiss();}
}
