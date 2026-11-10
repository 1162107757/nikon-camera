package cc.huevia.ui;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.text.method.TextKeyListener;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;
import cc.huevia.album.PhotoExportSpec;
import cc.huevia.album.PhotoExportPreview;
import cc.huevia.album.PhotoSaveTarget;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Full-screen export settings. Receives dimensions already resolved on a worker; never opens files.
 * Accepted settings feed the existing receipt-checked export/save flow without duplicating it. */
public final class PhotoExportDialog extends Dialog {
    public interface Listener { void chosen(PhotoExportSpec spec,PhotoSaveTarget target,boolean newCopy); }
    public static final class Item {
        public final String filename, description;
        /** Natural dimensions of the final full composition, including its external frame. */
        public final int fullWidth, fullHeight;
        /** Optional caller-owned preview, used only as a visual summary and never as export data. */
        public final Bitmap thumbnail;
        public Item(String filename,int fullWidth,int fullHeight) { this(filename,fullWidth,fullHeight,null); }
        public Item(String filename,int fullWidth,int fullHeight,Bitmap thumbnail) { this(filename,fullWidth,fullHeight,thumbnail,"当前效果 · 原图保持不变"); }
        public Item(String filename,int fullWidth,int fullHeight,Bitmap thumbnail,String description) {
            this.filename=filename==null||filename.trim().isEmpty()?"照片":filename;
            this.fullWidth=fullWidth;this.fullHeight=fullHeight;this.thumbnail=thumbnail;
            this.description=description==null?"":description;
        }
        public boolean dimensionsAvailable() { return fullWidth>0&&fullHeight>0&&fullWidth<=65535&&fullHeight<=65535; }
    }
    private final int BG,FIELD,TEXT,MUTED,ACCENT,ERROR,SELECTED,ACTION,ON_ACTION,OUTLINE;
    private final Activity activity;
    private final List<Item> items;
    private final Listener listener;
    private final Runnable original,raw;
    private LinearLayout custom,dimensionsList;
    private TextView dimensionsTitle,dimensions,hint,qualityFixed,validation;
    private EditText edgeInput,qualityInput;
    private SeekBar edgeSlider,qualitySlider;
    private Button next;
    private final PhotoSaveTarget destination=PhotoSaveTarget.PHONE_ALBUM;
    private final ChoiceButton[] modes=new ChoiceButton[3];
    private PhotoExportSpec.Mode mode=PhotoExportSpec.Mode.FULL;
    private boolean synchronising,customEntered,submitted;
    private final int customMaximum;
    private Button actualPreview;
    private List<PhotoExportPreview.Request> previewRequests=Collections.emptyList();
    private PhotoExportPreviewDialog previewDialog;
    private AlertDialog previewPicker;
    private String previewSpecKey="";

    public static PhotoExportDialog show(Activity activity,List<Item> items,Listener listener,Runnable original,Runnable raw) {
        if(activity.isFinishing()||activity.isDestroyed())return null;
        PhotoExportDialog dialog=new PhotoExportDialog(activity,items,listener,original,raw);dialog.show();return dialog;
    }
    private PhotoExportDialog(Activity activity,List<Item> input,Listener listener,Runnable original,Runnable raw) {
        super(activity,new UiPalette(activity).dark?cc.huevia.R.style.AppThemeDark:cc.huevia.R.style.AppThemeLight);
        UiPalette palette=new UiPalette(activity);BG=palette.surface;FIELD=palette.container;TEXT=palette.text;MUTED=palette.secondary;ACCENT=palette.primary;ERROR=palette.error;SELECTED=palette.card;ACTION=palette.primaryContainer;ON_ACTION=palette.onPrimaryContainer;OUTLINE=palette.outline;
        this.activity=activity;this.listener=listener;this.original=original;this.raw=raw;
        List<Item> copy=new ArrayList<>();if(input!=null)for(Item item:input)if(item!=null)copy.add(item);
        this.items=Collections.unmodifiableList(copy);
        int max=0;for(Item item:items)if(item.dimensionsAvailable())max=Math.max(max,Math.max(item.fullWidth,item.fullHeight));
        customMaximum=Math.min(PhotoExportSpec.MAX_CUSTOM_EDGE,max);
        requestWindowFeature(Window.FEATURE_NO_TITLE);setContentView(buildContent());
        Window window=getWindow();
        if(window!=null){window.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(BG));window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);window.setStatusBarColor(BG);window.setNavigationBarColor(BG);int light=palette.dark?0:View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION|light);if(Build.VERSION.SDK_INT>=29){window.setStatusBarContrastEnforced(false);window.setNavigationBarContrastEnforced(false);}if(Build.VERSION.SDK_INT>=30){window.setDecorFitsSystemWindows(false);if(window.getInsetsController()!=null)window.getInsetsController().setSystemBarsAppearance(palette.dark?0:android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);}}
    }
    @Override public void show(){super.show();Window window=getWindow();if(window!=null)window.setLayout(-1,-1);}
    @Override public void dismiss(){closePreview();if(previewPicker!=null){previewPicker.dismiss();previewPicker=null;}super.dismiss();}

    /** The caller freezes original bytes, all editing state and account validity before attachment. */
    public void setPreviewRequest(PhotoExportPreview.Request request){setPreviewRequests(request==null?Collections.emptyList():Collections.singletonList(request));}
    public void setPreviewRequests(List<PhotoExportPreview.Request> requests){
        closePreview();List<PhotoExportPreview.Request> copy=new ArrayList<>();if(requests!=null)for(PhotoExportPreview.Request request:requests){if(request==null)throw new IllegalArgumentException("成品预览快照缺失。");copy.add(request);}
        if(!copy.isEmpty()&&copy.size()!=items.size())throw new IllegalArgumentException("成品预览须逐张对应已选照片。");previewRequests=Collections.unmodifiableList(copy);refreshPreviewAction();
    }

    public void setVersionAction(Runnable action) {
        LinearLayout content=getWindow().getDecorView().findViewWithTag("export-scroll-content");
        if(content!=null){Button change=button("更改导出版本",()->{dismiss();action.run();});change.setTag("export-change-versions");change.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);content.addView(change,1,new LinearLayout.LayoutParams(-1,dp(48)));}
    }

    private View buildContent() {
        LinearLayout root=column();root.setBackgroundColor(BG);
        // Handle dialog insets itself, so fixed actions stay clear of gesture navigation and cutouts.
        root.setOnApplyWindowInsetsListener((v,insets)->{
            if(Build.VERSION.SDK_INT>=30){android.graphics.Insets safe=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());v.setPadding(safe.left,safe.top,safe.right,safe.bottom);}
            else v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());
            return insets;
        });
        LinearLayout header=row();header.setPadding(dp(12),0,dp(12),0);
        Button back=button("",this::dismiss);back.setContentDescription("返回编辑，取消导出设置");back.setCompoundDrawablesRelativeWithIntrinsicBounds(new AppIcon(AppIcon.Kind.BACK,TEXT,density()),null,null,null);back.setPadding(dp(12),0,dp(12),0);
        header.addView(back,new LinearLayout.LayoutParams(dp(48),dp(56)));
        TextView title=text("导出照片",18,TEXT);title.setTypeface(null,Typeface.BOLD);title.setGravity(Gravity.CENTER);header.addView(title,new LinearLayout.LayoutParams(0,dp(56),1));
        Button close=button("",this::dismiss);close.setContentDescription("取消导出");close.setCompoundDrawablesRelativeWithIntrinsicBounds(new AppIcon(AppIcon.Kind.CLOSE,MUTED,density()),null,null,null);close.setPadding(dp(12),0,dp(12),0);header.addView(close,new LinearLayout.LayoutParams(dp(48),dp(56)));root.addView(header);

        ScrollView scroll=new ScrollView(getContext());scroll.setFillViewport(true);scroll.setClipToPadding(false);
        LinearLayout content=new BoundedColumn();content.setTag("export-scroll-content");content.setPadding(dp(20),dp(12),dp(20),dp(24));
        ScrollView.LayoutParams contentParams=new ScrollView.LayoutParams(-1,-2);contentParams.gravity=Gravity.CENTER_HORIZONTAL;scroll.addView(content,contentParams);
        root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        summary(content);
        LinearLayout tabs=row();tabs.setPadding(dp(4),dp(4),dp(4),dp(4));tabs.setBackground(shape(FIELD,20));
        String[] names={"完整尺寸","分享","自定义"};for(int i=0;i<3;i++){final PhotoExportSpec.Mode choice=PhotoExportSpec.Mode.values()[i];ChoiceButton control=new ChoiceButton(getContext());styleButton(control,names[i],()->choose(choice));control.setTag("export-mode-"+i);modes[i]=control;tabs.addView(control,new LinearLayout.LayoutParams(0,dp(48),1));}
        margin(content,tabs,20,0);
        LinearLayout settings=group();settings.setTag("export-image-settings");margin(content,settings,16,0);
        custom=column();custom.setPadding(0,dp(20),0,0);
        custom.addView(text("最终成品长边",13,MUTED));
        edgeInput=input("长边像素，640–"+customMaximum+" px","export-custom-edge");edgeInput.setContentDescription("最终含框成品长边，像素");edgeInput.setHint("640–"+customMaximum+" px");
        margin(custom,edgeInput,8,0);
        edgeSlider=slider(Math.max(0,customMaximum-PhotoExportSpec.MIN_CUSTOM_EDGE));edgeSlider.setContentDescription("最终成品长边滑块，像素");custom.addView(edgeSlider,new LinearLayout.LayoutParams(-1,dp(48)));
        custom.addView(text("640–"+Math.max(640,customMaximum)+" px · 保持比例，不放大",12,MUTED));
        margin(settings,custom,0,0);

        dimensionsTitle=text("最终导出尺寸 · 包含边框",12,MUTED);margin(settings,dimensionsTitle,10,0);
        dimensions=text("",20,TEXT);dimensions.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));dimensions.setTag("export-dimensions");dimensions.setMaxLines(2);margin(settings,dimensions,8,0);
        hint=text("",12,MUTED);margin(settings,hint,6,0);
        dimensionsList=column();margin(settings,dimensionsList,8,0);
        divider(settings,14);
        valueRow(settings,"格式","JPEG · sRGB");
        qualityFixed=valueRow(settings,"JPEG 质量","95");
        LinearLayout qualityCustom=column();qualityCustom.setTag("export-quality-custom");
        qualityInput=input("JPEG 质量，70–100","export-custom-quality");qualityInput.setContentDescription("JPEG 质量，70 至 100");qualityInput.setHint("70–100");
        LinearLayout qr=row();TextView qualityLabel=text("JPEG 质量",13,MUTED);qualityLabel.setGravity(Gravity.CENTER_VERTICAL);qr.addView(qualityLabel,new LinearLayout.LayoutParams(0,dp(48),1));qualityInput.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);qr.addView(qualityInput,new LinearLayout.LayoutParams(dp(96),-2));qualityCustom.addView(qr);
        qualitySlider=slider(30);qualitySlider.setContentDescription("JPEG 质量滑块，70 至 100");qualityCustom.addView(qualitySlider,new LinearLayout.LayoutParams(-1,dp(48)));
        settings.addView(qualityCustom);
        margin(content,text("保留拍摄信息 · 不含定位",12,MUTED),12,0);
        actualPreview=button("查看成品预览",this::openPreview);actualPreview.setTag("export-actual-preview");actualPreview.setTextSize(13);actualPreview.setPadding(dp(14),dp(6),dp(14),dp(6));actualPreview.setBackground(new RippleDrawable(ColorStateList.valueOf(0x28f3b493),shape(SELECTED,14),null));actualPreview.setGravity(Gravity.START|Gravity.CENTER_VERTICAL);actualPreview.setCompoundDrawablesRelativeWithIntrinsicBounds(null,null,new AppIcon(AppIcon.Kind.CHEVRON,MUTED,density()),null);actualPreview.setVisibility(View.GONE);margin(content,actualPreview,16,0);
        if(original!=null||raw!=null){
            LinearLayout originalActions=column();originalActions.setTag("export-original-actions");
            LinearLayout label=row();TextView originalTitle=text("原始文件",13,TEXT);originalTitle.setGravity(Gravity.CENTER_VERTICAL);label.addView(originalTitle,new LinearLayout.LayoutParams(0,dp(32),1));
            TextView originalHint=text("不应用编辑",12,MUTED);originalHint.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);label.addView(originalHint,new LinearLayout.LayoutParams(-2,dp(32)));originalActions.addView(label);
            LinearLayout formats=row();
            if(original!=null)formats.addView(originalButton("JPEG",this::original),new LinearLayout.LayoutParams(0,dp(48),1));
            if(raw!=null){LinearLayout.LayoutParams rp=new LinearLayout.LayoutParams(0,dp(48),1);if(original!=null)rp.leftMargin=dp(8);formats.addView(originalButton("NEF",this::raw),rp);}
            originalActions.addView(formats,new LinearLayout.LayoutParams(-1,-2));margin(content,originalActions,20,0);
        }
        validation=text("",13,ERROR);validation.setTag("export-validation");validation.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);margin(content,validation,16,0);
        LinearLayout footer=new BoundedColumn();footer.setTag("export-fixed-footer");footer.setPadding(dp(20),dp(12),dp(20),dp(12));footer.setBackgroundColor(BG);
        next=button(exportActionLabel(),()->submit());next.setTag("export-confirm");next.setTextColor(ON_ACTION);next.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));next.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22262016),shape(ACTION,16),null));footer.addView(next,new LinearLayout.LayoutParams(-1,dp(52)));
        LinearLayout.LayoutParams footerParams=new LinearLayout.LayoutParams(-1,-2);footerParams.gravity=Gravity.CENTER_HORIZONTAL;root.addView(footer,footerParams);

        TextWatcher watcher=new TextWatcher(){public void beforeTextChanged(CharSequence s,int st,int count,int after){}public void onTextChanged(CharSequence s,int st,int before,int count){if(!synchronising)refresh();}public void afterTextChanged(Editable e){}};
        edgeInput.addTextChangedListener(watcher);qualityInput.addTextChangedListener(watcher);
        edgeSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar bar,int value,boolean user){if(user)edgeInput.setText(String.valueOf(value+640));}public void onStartTrackingTouch(SeekBar b){}public void onStopTrackingTouch(SeekBar b){}});
        qualitySlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar bar,int value,boolean user){if(user)qualityInput.setText(String.valueOf(value+70));}public void onStartTrackingTouch(SeekBar b){}public void onStopTrackingTouch(SeekBar b){}});
        qualityCustom.setVisibility(View.GONE);custom.setVisibility(View.GONE);refresh();return root;
    }

    private void summary(LinearLayout content) {
        LinearLayout row=row();Bitmap thumb=items.isEmpty()?null:items.get(0).thumbnail;
        if(thumb!=null&&!thumb.isRecycled()){ImageView image=new ImageView(getContext());image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setImageBitmap(thumb);image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);image.setBackground(shape(FIELD,12));image.setClipToOutline(true);row.addView(image,new LinearLayout.LayoutParams(dp(72),dp(72)));}
        LinearLayout copy=column();copy.setPadding(thumb!=null?dp(12):0,0,0,0);
        TextView filename=text(items.size()==1?items.get(0).filename:"已选择 "+items.size()+" 张照片",14,TEXT);filename.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));filename.setSingleLine(true);filename.setEllipsize(android.text.TextUtils.TruncateAt.END);filename.setContentDescription(filename.getText());copy.addView(filename);
        TextView description=text(items.size()==1?items.get(0).description:"按各自版本导出，保留原图",12,MUTED);description.setMaxLines(2);description.setEllipsize(android.text.TextUtils.TruncateAt.END);margin(copy,description,6,0);
        row.addView(copy,new LinearLayout.LayoutParams(0,-2,1));content.addView(row);
    }
    private void choose(PhotoExportSpec.Mode selected) {
        if(selected==PhotoExportSpec.Mode.CUSTOM&&!customAvailable())return;
        mode=selected;
        if(mode==PhotoExportSpec.Mode.CUSTOM&&!customEntered){customEntered=true;synchronising=true;edgeInput.setText(String.valueOf(Math.min(4096,customMaximum)));qualityInput.setText("90");synchronising=false;}
        refresh();
    }
    private boolean customAvailable(){return customMaximum>=PhotoExportSpec.MIN_CUSTOM_EDGE&&!items.isEmpty()&&dimensionsAvailable();}
    private boolean dimensionsAvailable(){if(items.isEmpty())return false;for(Item item:items)if(!item.dimensionsAvailable())return false;return true;}
    private PhotoExportSpec selected() {
        if(mode==PhotoExportSpec.Mode.FULL)return PhotoExportSpec.full();
        if(mode==PhotoExportSpec.Mode.SHARE)return PhotoExportSpec.share();
        int edge=parse(edgeInput.getText().toString(),"长边"),quality=parse(qualityInput.getText().toString(),"JPEG 质量");
        if(edge<640||edge>customMaximum)throw new IllegalArgumentException("最终成品长边须为 640–"+customMaximum+" px，不能放大照片。");
        if(quality<70||quality>100)throw new IllegalArgumentException("JPEG 质量须为 70–100。");
        return PhotoExportSpec.custom(edge,quality);
    }
    private static int parse(String value,String label) {
        String trimmed=value.trim();if(trimmed.isEmpty())throw new IllegalArgumentException("请输入"+label+"。");
        if(!trimmed.matches("[0-9]+"))throw new IllegalArgumentException(label+"须为整数，不含小数、符号或其他字符。");
        try{return Integer.parseInt(trimmed);}catch(NumberFormatException invalid){throw new IllegalArgumentException(label+"数值过大，请检查输入。");}
    }
    private void refresh() {
        for(int i=0;i<modes.length;i++){ChoiceButton button=modes[i];boolean active=i==mode.ordinal();button.setSelected(active);button.setTextColor(active?TEXT:MUTED);button.setTypeface(Typeface.create(active?"sans-serif-medium":"sans-serif",Typeface.NORMAL));button.setBackground(shape(active?SELECTED:Color.TRANSPARENT,16));button.setContentDescription(button.getText()+(active?"，已选择":""));}
        modes[2].setEnabled(customAvailable());modes[2].setAlpha(customAvailable()?1:.45f);modes[2].setContentDescription("自定义"+(customAvailable()?(mode==PhotoExportSpec.Mode.CUSTOM?"，已选择":""):"，不可用，完整成品长边不足 640 px 或尺寸尚不可用"));
        boolean isCustom=mode==PhotoExportSpec.Mode.CUSTOM;custom.setVisibility(isCustom?View.VISIBLE:View.GONE);
        View qc=qualityInput.getParent() instanceof View?(View)qualityInput.getParent():null;
        if(qc!=null&&qc.getParent() instanceof View)((View)qc.getParent()).setVisibility(isCustom?View.VISIBLE:View.GONE);
        ((View)qualityFixed.getParent()).setVisibility(isCustom?View.GONE:View.VISIBLE);
        qualityFixed.setText(mode==PhotoExportSpec.Mode.FULL?"95":"90");
        PhotoExportSpec spec=null;String problem="";
        if(!dimensionsAvailable())problem=items.isEmpty()?"没有可导出的照片。":"完整成品尺寸暂不可用，请返回后重试。";
        else try{spec=selected();}catch(IllegalArgumentException invalid){problem=invalid.getMessage();}
        validation.setText(problem);validation.setVisibility(problem.isEmpty()?View.GONE:View.VISIBLE);next.setEnabled(problem.isEmpty()&&!submitted);next.setAlpha(next.isEnabled()?1:.45f);
        dimensionsList.removeAllViews();
        if(spec==null){closePreview();refreshPreviewAction();dimensions.setText("—");hint.setText(problem.isEmpty()?"请检查导出设置":problem);return;}
        String key=spec.mode+":"+spec.longEdge+":"+spec.quality;if(!key.equals(previewSpecKey)){closePreview();previewSpecKey=key;}refreshPreviewAction();
        if(isCustom){synchronising=true;edgeSlider.setProgress(spec.longEdge-640);qualitySlider.setProgress(spec.quality-70);synchronising=false;}
        dimensions.setVisibility(items.size()==1?View.VISIBLE:View.GONE);
        if(items.size()==1){Item item=items.get(0);int[] size=resolvedSize(item,spec);dimensions.setText(size[0]+" × "+size[1]+" px");dimensionsTitle.setText("成品尺寸 · 含边框");}
        else {dimensionsTitle.setText("各照片尺寸 · 含边框");for(Item item:items){int[] size=resolvedSize(item,spec);LinearLayout line=row();line.setMinimumHeight(dp(36));TextView name=text(item.filename,12,MUTED);name.setSingleLine(true);name.setEllipsize(android.text.TextUtils.TruncateAt.END);name.setTooltipText(item.filename);LinearLayout.LayoutParams label=new LinearLayout.LayoutParams(0,-2,1);label.rightMargin=dp(12);line.addView(name,label);TextView sizeLabel=text(size[0]+" × "+size[1]+" px",12,TEXT);sizeLabel.setSingleLine(true);line.addView(sizeLabel);line.setContentDescription(item.filename+"，"+size[0]+" × "+size[1]+" 像素，JPEG质量 "+spec.quality);dimensionsList.addView(line,new LinearLayout.LayoutParams(-1,-2));}}
        hint.setText(spec.mode==PhotoExportSpec.Mode.FULL?"保留当前构图与边框的完整尺寸":("保持比例 · 不放大"+(items.size()>1?" · 每张长边 ≤ "+spec.longEdge+" px":"")));
        hint.setVisibility(items.size()==1||spec.mode!=PhotoExportSpec.Mode.FULL?View.VISIBLE:View.GONE);
        if(!customAvailable()&&dimensionsAvailable())hint.append("\n此图长边不足 640 px，可选完整尺寸或分享。");
    }
    /** Mirror the final-canvas downscale rule for summaries; no decoding or pixel allocation. */
    private static int[] resolvedSize(Item item,PhotoExportSpec spec) {
        int edge=Math.max(item.fullWidth,item.fullHeight),target=spec.mode==PhotoExportSpec.Mode.FULL?edge:Math.min(edge,spec.longEdge);
        int width=item.fullWidth>=item.fullHeight?target:Math.max(1,(int)Math.round(item.fullWidth*(double)target/edge));
        int height=item.fullHeight>=item.fullWidth?target:Math.max(1,(int)Math.round(item.fullHeight*(double)target/edge));return new int[]{width,height};
    }
    private void refreshPreviewAction(){if(actualPreview==null)return;actualPreview.setVisibility(previewRequests.isEmpty()?View.GONE:View.VISIBLE);boolean enabled=!previewRequests.isEmpty()&&!submitted&&dimensionsAvailable();try{selected();}catch(IllegalArgumentException invalid){enabled=false;}actualPreview.setEnabled(enabled);actualPreview.setAlpha(enabled?1:.45f);actualPreview.setText(items.size()>1?"逐张查看成品预览":"查看成品预览");}
    private void openPreview(){
        if(!isShowing()||submitted||previewRequests.isEmpty())return;final PhotoExportSpec spec;try{spec=selected();}catch(IllegalArgumentException invalid){refresh();return;}
        if(previewRequests.size()==1){openPreview(0,spec);return;}
        String[] names=new String[items.size()];for(int i=0;i<names.length;i++)names[i]=items.get(i).filename;
        ActionChoiceDialog choices=new ActionChoiceDialog(getContext(),UiPalette.forTheme(getContext()),"预览照片");
        for(int i=0;i<names.length;i++){final int index=i;choices.add(AppIcon.Kind.ALBUM,names[i],"",()->openPreview(index,spec));}
        previewPicker=choices.create();AlertDialog shown=previewPicker;shown.setOnDismissListener(ignored->{if(previewPicker==shown)previewPicker=null;});shown.show();
    }
    private void openPreview(int index,PhotoExportSpec spec){if(!isShowing()||submitted||index<0||index>=previewRequests.size())return;closePreview();previewDialog=PhotoExportPreviewDialog.show(activity,previewRequests.get(index),spec,items.get(index).filename);}
    private void closePreview(){if(previewDialog!=null){PhotoExportPreviewDialog old=previewDialog;previewDialog=null;old.close();}}
    private String exportActionLabel(){return items.size()>1?"导出 "+items.size()+" 张到相册":"导出到手机相册";}
    private void submit(){if(submitted)return;PhotoExportSpec spec;try{if(!dimensionsAvailable())return;spec=selected();}catch(IllegalArgumentException invalid){refresh();return;}submitted=true;dismiss();if(listener!=null)listener.chosen(spec,destination,true);}
    private void original(){if(submitted)return;submitted=true;dismiss();if(original!=null)original.run();}
    private void raw(){if(submitted)return;submitted=true;dismiss();if(raw!=null)raw.run();}
    private final class ChoiceButton extends Button {
        ChoiceButton(Context context){super(context);}
        @Override public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info){super.onInitializeAccessibilityNodeInfo(info);info.setCheckable(true);info.setChecked(isSelected());}
    }
    private EditText input(String description,String tag){EditText input=new EditText(getContext());input.setTag(tag);input.setTextSize(14);input.setTextColor(TEXT);input.setHintTextColor(MUTED);input.setPadding(dp(12),dp(10),dp(12),dp(10));input.setSingleLine(true);input.setMinHeight(dp(48));input.setBackground(shape(FIELD,12));input.setContentDescription(description);input.setSelectAllOnFocus(true);
        // Keep pasted invalid text visible for validation; the default numeric KeyListener silently
        // removes characters (turning e.g. "2048px" into a different, apparently valid value).
        input.setKeyListener(TextKeyListener.getInstance());input.setRawInputType(InputType.TYPE_CLASS_NUMBER);return input;}
    private SeekBar slider(int max){SeekBar bar=new SeekBar(getContext());bar.setMax(max);bar.setProgressTintList(ColorStateList.valueOf(ACCENT));bar.setProgressBackgroundTintList(ColorStateList.valueOf(OUTLINE));bar.setThumbTintList(ColorStateList.valueOf(ACCENT));return bar;}
    private LinearLayout column(){LinearLayout view=new LinearLayout(getContext());view.setOrientation(LinearLayout.VERTICAL);return view;}
    private LinearLayout group(){LinearLayout view=column();view.setPadding(dp(14),dp(6),dp(14),dp(6));view.setBackground(shape(SELECTED,16));return view;}
    /** Keep settings and their fixed action on the same readable rail on larger windows. */
    private final class BoundedColumn extends LinearLayout {
        BoundedColumn(){super(PhotoExportDialog.this.getContext());setOrientation(VERTICAL);}
        @Override protected void onMeasure(int widthSpec,int heightSpec){int width=Math.min(MeasureSpec.getSize(widthSpec),dp(680));super.onMeasure(MeasureSpec.makeMeasureSpec(width,MeasureSpec.EXACTLY),heightSpec);}
    }
    private LinearLayout row(){LinearLayout view=new LinearLayout(getContext());view.setGravity(Gravity.CENTER_VERTICAL);return view;}
    private TextView text(String copy,int size,int color){TextView text=new TextView(getContext());text.setText(copy);text.setTextColor(color);text.setTextSize(size);text.setIncludeFontPadding(false);return text;}
    private TextView valueRow(LinearLayout content,String label,String value){LinearLayout row=row();TextView caption=text(label,13,MUTED);caption.setSingleLine(true);row.addView(caption,new LinearLayout.LayoutParams(0,dp(44),1));caption.setGravity(Gravity.CENTER_VERTICAL);TextView actual=text(value,13,TEXT);actual.setSingleLine(true);actual.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);row.addView(actual,new LinearLayout.LayoutParams(-2,dp(44)));content.addView(row);return actual;}
    private void divider(LinearLayout content,int top){View line=new View(getContext());line.setBackgroundColor(OUTLINE);margin(content,line,top,0);line.getLayoutParams().height=dp(1);}
    private void margin(LinearLayout content,View view,int top,int bottom){LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(-1,-2);params.topMargin=dp(top);params.bottomMargin=dp(bottom);content.addView(view,params);}
    private Button button(String name,Runnable action){Button button=new Button(getContext());styleButton(button,name,action);return button;}
    private Button originalButton(String format,Runnable action){Button button=button(format,action);button.setTag("export-original-"+format.toLowerCase(java.util.Locale.ROOT));button.setTextSize(13);button.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));button.setContentDescription("保存 "+format+" 原始文件，不应用编辑");button.setGravity(Gravity.START|Gravity.CENTER_VERTICAL);button.setPadding(dp(14),0,dp(14),0);AppIcon icon=new AppIcon(AppIcon.Kind.DOWNLOAD,MUTED,density());icon.setBounds(0,0,dp(18),dp(18));button.setCompoundDrawablesRelative(null,null,icon,null);button.setCompoundDrawablePadding(dp(8));button.setBackground(new RippleDrawable(ColorStateList.valueOf(0x28f3b493),shape(FIELD,12),null));return button;}
    private void styleButton(Button button,String name,Runnable action){button.setText(name);button.setAllCaps(false);button.setTextSize(14);button.setTextColor(TEXT);button.setMinWidth(0);button.setMinimumWidth(0);button.setMinHeight(dp(48));button.setMinimumHeight(dp(48));button.setPadding(dp(8),dp(6),dp(8),dp(6));button.setStateListAnimator(null);button.setElevation(0);button.setTranslationZ(0);button.setBackground(new RippleDrawable(ColorStateList.valueOf(0x28f3b493),shape(Color.TRANSPARENT,12),null));button.setOnClickListener(v->action.run());}
    private GradientDrawable shape(int color,int radius){GradientDrawable shape=new GradientDrawable();shape.setColor(color);shape.setCornerRadius(dp(radius));return shape;}
    private float density(){return getContext().getResources().getDisplayMetrics().density;}
    private int dp(float value){return Math.round(value*density());}
}
