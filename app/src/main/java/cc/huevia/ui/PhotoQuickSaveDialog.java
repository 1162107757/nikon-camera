package cc.huevia.ui;

import android.app.*;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.*;
import android.os.Build;
import android.view.*;
import android.widget.*;
import cc.huevia.album.*;
import java.util.*;

/** The common save path; advanced export remains available without changing its guarded pipeline. */
public final class PhotoQuickSaveDialog extends Dialog {
    private final int PANEL,FIELD,TEXT,MUTED,ACCENT,ACTION,ON_ACTION,OUTLINE;
    private final Activity activity;
    private final List<PhotoExportDialog.Item> items;
    private final PhotoExportDialog.Listener listener;
    private final Runnable advanced;
    private SeekBar quality;
    private TextView qualityDetail;
    private final List<Button> qualityLabels=new ArrayList<>();
    private PhotoExportQuality selectedQuality=PhotoExportQuality.ORIGINAL;
    private LinearLayout outer,summary;
    private Button save,advancedButton;
    private String versionSummary="";
    private boolean submitted;
    public static PhotoQuickSaveDialog show(Activity activity,List<PhotoExportDialog.Item> items,PhotoExportDialog.Listener listener,Runnable advanced){
        if(activity.isFinishing()||activity.isDestroyed())return null;
        PhotoQuickSaveDialog d=new PhotoQuickSaveDialog(activity,items,listener,advanced);d.show();return d;
    }
    private PhotoQuickSaveDialog(Activity a,List<PhotoExportDialog.Item> values,PhotoExportDialog.Listener listener,Runnable advanced){
        super(new ContextThemeWrapper(a,new UiPalette(a).dark?cc.huevia.R.style.AppThemeDark:cc.huevia.R.style.AppThemeLight));activity=a;items=new ArrayList<>(values);this.listener=listener;this.advanced=advanced;
        UiPalette palette=new UiPalette(a);PANEL=palette.card;FIELD=palette.container;TEXT=palette.text;MUTED=palette.secondary;ACCENT=palette.primary;ACTION=palette.primaryContainer;ON_ACTION=palette.onPrimaryContainer;OUTLINE=palette.outline;
        requestWindowFeature(Window.FEATURE_NO_TITLE);setContentView(content());Window w=getWindow();
        if(w!=null){w.setBackgroundDrawableResource(android.R.color.transparent);w.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);WindowManager.LayoutParams p=w.getAttributes();p.dimAmount=.48f;w.setAttributes(p);w.setGravity(Gravity.BOTTOM);w.setNavigationBarColor(PANEL);}
    }
    @Override public void show(){super.show();Window w=getWindow();if(w!=null)w.setLayout(sheetWidth(),-2);}
    private int sheetWidth(){return Math.min(dp(560),activity.getResources().getDisplayMetrics().widthPixels);}
    private View content(){
        final boolean compact=getContext().getResources().getConfiguration().screenHeightDp<500;
        outer=column();outer.setTag("quick-save-sheet");GradientDrawable surface=shape(PANEL,24);outer.setBackground(surface);outer.setPadding(dp(22),dp(compact?8:12),dp(22),dp(compact?10:18));
        View handle=new View(getContext());handle.setBackground(shape(OUTLINE,2));LinearLayout.LayoutParams hp=new LinearLayout.LayoutParams(dp(30),dp(3));hp.gravity=Gravity.CENTER_HORIZONTAL;hp.bottomMargin=dp(compact?6:14);outer.addView(handle,hp);
        LinearLayout heading=row();TextView title=text("导出照片",17,TEXT);title.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));heading.addView(title,new LinearLayout.LayoutParams(0,dp(48),1));Button close=button("",this::dismiss);close.setContentDescription("取消导出，返回照片");close.setCompoundDrawablesRelativeWithIntrinsicBounds(new AppIcon(AppIcon.Kind.CLOSE,MUTED,density()),null,null,null);close.setPadding(dp(12),0,dp(12),0);heading.addView(close,new LinearLayout.LayoutParams(dp(48),dp(48)));outer.addView(heading);
        summary=row();summary.setPadding(0,dp(compact?0:8),0,dp(compact?6:12));outer.addView(summary);refreshSummary();
        outer.addView(qualityControl(),new LinearLayout.LayoutParams(-1,-2));
        if(advanced!=null){Button more=button("更多设置",()->{if(submitted||!validSelection())return;dismiss();advanced.run();});advancedButton=more;more.setTag("quick-save-advanced");more.setTextColor(MUTED);more.setGravity(Gravity.START|Gravity.CENTER_VERTICAL);if(compact){more.setTextSize(12);more.setPadding(dp(4),0,dp(4),0);heading.addView(more,heading.getChildCount()-1,new LinearLayout.LayoutParams(dp(88),dp(48)));}else{more.setPadding(dp(14),0,dp(14),0);more.setCompoundDrawablesRelativeWithIntrinsicBounds(null,null,new AppIcon(AppIcon.Kind.CHEVRON,MUTED,density()),null);more.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22f3b493),shape(FIELD,12),null));outer.addView(more,new LinearLayout.LayoutParams(-1,dp(48)));}}
        save=button("导出到手机相册",()->{if(submitted||!validSelection())return;submitted=true;PhotoExportSpec spec=selectedQuality.spec();dismiss();listener.chosen(spec,PhotoSaveTarget.PHONE_ALBUM,true);});save.setTag("quick-save-confirm");save.setTextColor(ON_ACTION);save.setTextSize(14);save.setTypeface(null,Typeface.BOLD);save.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22262016),shape(ACTION,14),null));save.setCompoundDrawablesRelativeWithIntrinsicBounds(new AppIcon(AppIcon.Kind.DOWNLOAD,ON_ACTION,density()),null,null,null);save.setCompoundDrawablePadding(dp(7));save.setEnabled(validSelection());LinearLayout.LayoutParams sp=new LinearLayout.LayoutParams(-1,dp(52));sp.topMargin=dp(9);outer.addView(save,sp);
        ScrollView scroll=new ScrollView(getContext());scroll.setFillViewport(false);scroll.setClipToPadding(false);scroll.addView(outer);int available=activity.getResources().getDisplayMetrics().heightPixels-dp(48);scroll.setOnApplyWindowInsetsListener((v,insets)->{int bottom=Build.VERSION.SDK_INT>=30?insets.getInsets(WindowInsets.Type.systemBars()).bottom:insets.getSystemWindowInsetBottom();v.setPadding(0,0,0,bottom);return insets;});scroll.setOnHierarchyChangeListener(null);outer.post(()->{if(getWindow()!=null&&outer.getHeight()>available)getWindow().setLayout(sheetWidth(),available);});return scroll;
    }
    private View qualityControl(){
        LinearLayout control=column();control.setTag("quick-save-quality-control");
        LinearLayout heading=row();TextView title=text("画质",13,TEXT);title.setTag("quick-save-quality-label");title.setSingleLine(true);heading.addView(title,new LinearLayout.LayoutParams(dp(48),dp(32)));
        qualityDetail=text("",11,MUTED);qualityDetail.setTag("quick-save-quality-detail");qualityDetail.setSingleLine(true);qualityDetail.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);heading.addView(qualityDetail,new LinearLayout.LayoutParams(0,dp(32),1));control.addView(heading);
        quality=new SeekBar(getContext()){@Override protected void onSizeChanged(int w,int h,int oldw,int oldh){int inset=Math.round(w/8f);if(inset>0&&getPaddingLeft()!=inset)setPadding(inset,0,inset,0);super.onSizeChanged(w,h,oldw,oldh);}};quality.setTag("quick-save-quality");quality.setMax(PhotoExportQuality.values().length-1);quality.setKeyProgressIncrement(1);quality.setSplitTrack(false);quality.setPadding(dp(12),0,dp(12),0);
        GradientDrawable track=shape(OUTLINE,2);GradientDrawable fill=shape(ACCENT,2);ClipDrawable clipped=new ClipDrawable(fill,Gravity.START,ClipDrawable.HORIZONTAL);LayerDrawable layers=new LayerDrawable(new android.graphics.drawable.Drawable[]{track,clipped});layers.setId(0,android.R.id.background);layers.setId(1,android.R.id.progress);for(int i=0;i<2;i++){layers.setLayerHeight(i,dp(3));layers.setLayerGravity(i,Gravity.CENTER_VERTICAL|Gravity.FILL_HORIZONTAL);}quality.setProgressDrawable(layers);
        GradientDrawable thumb=shape(ACCENT,8);thumb.setSize(dp(16),dp(16));quality.setThumb(thumb);quality.setThumbOffset(dp(8));GradientDrawable tick=shape(MUTED,2);tick.setSize(dp(4),dp(4));quality.setTickMark(tick);quality.setTickMarkTintList(ColorStateList.valueOf(MUTED));quality.setProgress(selectedQuality.ordinal());control.addView(quality,new LinearLayout.LayoutParams(-1,dp(48)));
        LinearLayout labels=row();
        for(PhotoExportQuality level:PhotoExportQuality.values()){Button choice=button(level.label,()->quality.setProgress(level.ordinal()));choice.setTag("quick-save-quality-level-"+level.ordinal());choice.setSingleLine(true);choice.setTextSize(12);choice.setPadding(dp(2),0,dp(2),0);choice.setContentDescription(level.label+"，"+level.detail());qualityLabels.add(choice);labels.addView(choice,new LinearLayout.LayoutParams(0,dp(48),1));}control.addView(labels);
        quality.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar bar,int progress,boolean fromUser){selectedQuality=PhotoExportQuality.values()[progress];refreshQuality();refreshSummary();}public void onStartTrackingTouch(SeekBar bar){}public void onStopTrackingTouch(SeekBar bar){}});
        refreshQuality();return control;
    }
    private void refreshQuality(){
        qualityDetail.setText(selectedQuality.detail());quality.setContentDescription("画质，"+selectedQuality.label+"，"+selectedQuality.detail());if(Build.VERSION.SDK_INT>=30)quality.setStateDescription(selectedQuality.label);
        for(int i=0;i<qualityLabels.size();i++){Button label=qualityLabels.get(i);boolean active=i==selectedQuality.ordinal();label.setSelected(active);label.setTextColor(active?ACCENT:MUTED);label.setTypeface(Typeface.create(active?"sans-serif-medium":"sans-serif",Typeface.NORMAL));}
    }
    public void setVersionContent(View content) { outer.addView(content,3,new LinearLayout.LayoutParams(-1,-2)); }
    public void setVersionItems(List<PhotoExportDialog.Item> values,String label) {
        if(submitted)return;items.clear();items.addAll(values);versionSummary=label;refreshSummary();save.setEnabled(validSelection());
        save.setAlpha(save.isEnabled()?1f:.45f);
        if(advancedButton!=null)advancedButton.setEnabled(validSelection());
    }
    private boolean validSelection(){return !items.isEmpty()&&items.size()<=PhotoPresetBatch.MAX_BATCH&&items.stream().allMatch(PhotoExportDialog.Item::dimensionsAvailable);}
    private void refreshSummary(){
        if(summary==null)return;summary.removeAllViews();PhotoExportDialog.Item first=items.isEmpty()?null:items.get(0);
        if(first!=null&&first.thumbnail!=null&&!first.thumbnail.isRecycled()){ImageView image=new ImageView(getContext());image.setImageBitmap(first.thumbnail);image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);image.setBackground(shape(PANEL,8));image.setClipToOutline(true);LinearLayout.LayoutParams ip=new LinearLayout.LayoutParams(dp(48),dp(48));ip.rightMargin=dp(12);summary.addView(image,ip);}
        LinearLayout copy=column();String name=versionSummary.isEmpty()?(items.size()==1?"当前编辑效果":items.size()+" 张照片 · 各自的编辑效果"):versionSummary;
        TextView title=text(name,14,TEXT);title.setTag("quick-save-version-summary");title.setSingleLine(true);title.setEllipsize(android.text.TextUtils.TruncateAt.END);title.setContentDescription(name);copy.addView(title);
        String dimensions="保留原图，生成新照片";if(first!=null&&items.size()==1&&first.dimensionsAvailable()){PhotoExportSpec.Resolved resolved=selectedQuality.spec().resolve(first.fullWidth,first.fullHeight);dimensions=resolved.width+" × "+resolved.height+" px";}
        TextView hint=text(dimensions,12,MUTED);hint.setTag("quick-save-output-size");hint.setSingleLine(true);hint.setPadding(0,dp(4),0,0);copy.addView(hint);summary.addView(copy,new LinearLayout.LayoutParams(0,-2,1));
    }
    private LinearLayout column(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.VERTICAL);return v;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(getContext());v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private TextView text(String label,int size,int color){TextView v=new TextView(getContext());v.setText(label);v.setTextSize(size);v.setTextColor(color);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private Button button(String label,Runnable action){Button b=new Button(getContext());b.setText(label);b.setTextSize(13);b.setAllCaps(false);b.setMinWidth(0);b.setMinimumWidth(0);b.setPadding(dp(12),0,dp(12),0);b.setTextColor(TEXT);b.setStateListAnimator(null);b.setElevation(0);b.setTranslationZ(0);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22f3b493),shape(android.graphics.Color.TRANSPARENT,10),null));b.setOnClickListener(v->action.run());return b;}
    private GradientDrawable shape(int color,int radius){GradientDrawable v=new GradientDrawable();v.setColor(color);v.setCornerRadius(dp(radius));return v;}
    private float density(){return activity.getResources().getDisplayMetrics().density;}
    private int dp(float value){return Math.round(value*density());}
}
