package cc.huevia.ui;

import android.app.Activity;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.style.ImageSpan;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import cc.huevia.R;
import cc.huevia.album.PhotoSort;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Consumer;

/** THESIS: Order the album by meaningful dates. OWN-WORLD: inherited paper/charcoal B sheet.
 * STORY: inspect order, change a draft, apply once. FIRST VIEWPORT: two pairs of choices, fixed actions.
 * FORM: approved album-time-sort-v2-arrows.png; no new visual tokens.
 * FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance. */
public final class AlbumSortSheet extends Dialog {
    private final Activity activity;private final UiPalette palette;private final boolean phone;
    private final Consumer<PhotoSort> apply;private PhotoSort draft;
    private LinearLayout content,frame;private LimitedScroll scroll;private TextView note;
    private final List<TextView> choices=new ArrayList<>();
    private final GradientDrawable material=new GradientDrawable();private java.util.function.Consumer<Boolean> blurListener;private WindowManager manager;
    public AlbumSortSheet(Activity activity,UiPalette palette,boolean phone,PhotoSort applied,Consumer<PhotoSort> apply){
        super(activity,palette.dark?R.style.PresetFilterDialogDark:R.style.PresetFilterDialogLight);
        this.activity=activity;this.palette=palette;this.phone=phone;this.draft=applied;this.apply=apply;requestWindowFeature(Window.FEATURE_NO_TITLE);setCanceledOnTouchOutside(true);build();
    }
    private void build(){
        frame=new LinearLayout(getContext());frame.setOrientation(LinearLayout.VERTICAL);frame.setPadding(dp(18),dp(10),dp(18),dp(12));frame.setTag("album-sort-sheet");
        if(Build.VERSION.SDK_INT>=28)frame.setAccessibilityPaneTitle("时间排序");
        View handle=new View(activity);handle.setBackground(shape(palette.outline,2));LinearLayout.LayoutParams grip=new LinearLayout.LayoutParams(dp(30),dp(3));grip.gravity=Gravity.CENTER_HORIZONTAL;grip.bottomMargin=dp(4);frame.addView(handle,grip);handle.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        LinearLayout header=new LinearLayout(activity);header.setGravity(Gravity.CENTER_VERTICAL);header.addView(text("时间排序",16,true),new LinearLayout.LayoutParams(0,-2,1));
        ImageView close=new ImageView(activity);close.setImageDrawable(new AppIcon(AppIcon.Kind.CLOSE,palette.text,density()));close.setPadding(dp(14),dp(14),dp(14),dp(14));close.setContentDescription("关闭排序，放弃未应用修改");close.setTag("album-sort-close");close.setFocusable(true);close.setBackground(ripple(Color.TRANSPARENT,24));close.setOnClickListener(v->dismiss());header.addView(close,new LinearLayout.LayoutParams(dp(48),dp(48)));frame.addView(header);
        content=new LinearLayout(activity);content.setOrientation(LinearLayout.VERTICAL);scroll=new LimitedScroll();scroll.setTag("album-sort-options");scroll.setClipToPadding(false);scroll.addView(content);frame.addView(scroll,new LinearLayout.LayoutParams(-1,-2));
        group("排序依据",new String[]{"拍摄时间","添加时间"},new String[]{"taken","added"},0);
        group("排列顺序",new String[]{"新到旧","旧到新"},new String[]{"newest","oldest"},2);
        note=text("旧照片没有入库记录时，添加时间使用现存文件时间。",12,false);note.setTextColor(palette.secondary);note.setPadding(0,dp(4),0,dp(6));content.addView(note);
        LinearLayout footer=new LinearLayout(activity);footer.setGravity(Gravity.CENTER_VERTICAL);TextView reset=text("重置",14,false);reset.setTag("album-sort-reset");reset.setGravity(Gravity.CENTER);reset.setMinHeight(dp(48));reset.setPadding(dp(6),0,dp(6),0);reset.setTextColor(palette.secondary);reset.setFocusable(true);reset.setBackground(ripple(Color.TRANSPARENT,12));reset.setOnClickListener(v->{draft=PhotoSort.DEFAULT;refreshChoices();});footer.addView(reset,new LinearLayout.LayoutParams(dp(64),-2));
        footer.addView(new View(activity),new LinearLayout.LayoutParams(0,1,1));TextView done=text("应用",14,true);done.setTag("album-sort-apply");done.setGravity(Gravity.CENTER);done.setPadding(dp(20),dp(10),dp(20),dp(10));done.setMinHeight(dp(48));done.setTextColor(palette.onAction);done.setFocusable(true);done.setBackground(ripple(palette.action,24));done.setOnClickListener(v->{PhotoSort selected=draft;dismiss();apply.accept(selected);});footer.addView(done,new LinearLayout.LayoutParams(dp(108),-2));frame.addView(footer);setContentView(frame);refreshChoices();
    }
    private void group(String title,String[] names,String[] tags,int start){
        TextView label=text(title,12,false);label.setTextColor(palette.secondary);label.setPadding(0,dp(start==0?0:10),0,dp(4));content.addView(label);
        ChipFlow row=new ChipFlow(2);for(int i=0;i<2;i++){final int item=start+i;TextView chip=text(names[i],14,false);chip.setTag("album-sort-"+tags[i]);chip.setMinHeight(dp(48));chip.setGravity(Gravity.CENTER);chip.setPadding(dp(10),dp(6),dp(10),dp(6));chip.setFocusable(true);chip.setOnClickListener(v->{draft=item<2?draft.withBasis(item==1):draft.withDirection(item==3);refreshChoices();});chip.setAccessibilityDelegate(new View.AccessibilityDelegate(){@Override public void onInitializeAccessibilityNodeInfo(View view,android.view.accessibility.AccessibilityNodeInfo info){super.onInitializeAccessibilityNodeInfo(view,info);info.setClassName("android.widget.Button");}});choices.add(chip);row.addView(chip);}content.addView(row,new LinearLayout.LayoutParams(-1,-2));
    }
    private void refreshChoices(){
        for(String tag:new String[]{"album-sort-close","album-sort-reset","album-sort-apply"}){View action=frame.findViewWithTag(tag);action.setAccessibilityDelegate(new View.AccessibilityDelegate(){@Override public void onInitializeAccessibilityNodeInfo(View view,android.view.accessibility.AccessibilityNodeInfo info){super.onInitializeAccessibilityNodeInfo(view,info);info.setClassName("android.widget.Button");}});}
        String[] labels={"拍摄时间","添加时间","新到旧","旧到新"};
        for(int i=0;i<choices.size();i++){
            TextView chip=choices.get(i);boolean selected=i<2?(draft.added?i==1:i==0):(draft.oldest?i==3:i==2);chip.setSelected(selected);chip.setTextColor(selected?palette.onAction:palette.text);
            chip.setBackground(new android.graphics.drawable.InsetDrawable(ripple(selected?palette.action:alpha(palette.card,.65f),24),0,dp(6),0,dp(6)));chip.setPadding(dp(10),dp(6),dp(10),dp(6));
            if(selected){AppIcon check=new AppIcon(AppIcon.Kind.CHECK,palette.onAction,density());check.setBounds(0,0,dp(16),dp(16));SpannableString label=new SpannableString(labels[i]+"  \uFFFC");label.setSpan(new ImageSpan(check,ImageSpan.ALIGN_CENTER),label.length()-1,label.length(),Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);chip.setText(label);}else chip.setText(labels[i]);
            chip.setContentDescription(labels[i]+(selected?"，已选中":"")+(i==0?"；缺少拍摄时间时使用添加时间":""));
        }
        note.setVisibility(!phone&&draft.added?View.VISIBLE:View.GONE);if(isShowing())frame.post(this::layoutForWindow);
    }
    @Override public void show() {
        super.show(); Window window = getWindow(); if (window == null) return;
        window.setBackgroundDrawable(material); material.setCornerRadius(dp(28));
        // Android forces light status icons for dimming floating windows that do not
        // intersect the status bar. Keep the page's own bar appearance and glass depth.
        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND); window.setDimAmount(0f);
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING);
        window.setGravity(Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        window.setNavigationBarColor(palette.surface);
        if (Build.VERSION.SDK_INT >= 29) window.setNavigationBarContrastEnforced(false);
        if (Build.VERSION.SDK_INT >= 30) window.setDecorFitsSystemWindows(true);
        window.getDecorView().setSystemUiVisibility(palette.dark ? 0 : View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR | View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
        updateSystemBars();
        layoutForWindow();
        updateMaterial(false);
        if (Build.VERSION.SDK_INT >= 31) {
            manager = activity.getSystemService(WindowManager.class);
            blurListener = enabled -> updateMaterial(enabled);
            manager.addCrossWindowBlurEnabledListener(activity.getMainExecutor(), blurListener);
            updateMaterial(manager.isCrossWindowBlurEnabled());
        }
    }

    /** Called when the host handles configuration changes without recreating its Activity. */
    public void layoutForWindow() {
        Window window = getWindow(); if (window == null) return;
        android.util.DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
        int width = metrics.widthPixels, height = metrics.heightPixels, top = dp(24), bottom = dp(24);
        if (Build.VERSION.SDK_INT >= 30) {
            android.view.WindowMetrics bounds = activity.getWindowManager().getCurrentWindowMetrics();
            Insets safe = bounds.getWindowInsets().getInsetsIgnoringVisibility(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            width = bounds.getBounds().width() - safe.left - safe.right;
            height = bounds.getBounds().height(); top = safe.top; bottom = safe.bottom;
        }
        int available = height - top - bottom - dp(24);
        // Header/footer wrap with sp text, leaving every remaining pixel to scrollable options.
        frame.measure(View.MeasureSpec.makeMeasureSpec(Math.min(dp(520), width - dp(20)), View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
        int fixed = frame.getMeasuredHeight() - scroll.getMeasuredHeight();
        scroll.limit = Math.max(dp(48), available - fixed); scroll.requestLayout();
        window.setLayout(Math.min(dp(520), width - dp(20)), ViewGroup.LayoutParams.WRAP_CONTENT);
        WindowManager.LayoutParams params = window.getAttributes(); params.y = dp(10); window.setAttributes(params);
    }

    private void updateMaterial(boolean blurred) {
        material.setColor(alpha(palette.surface, blurred ? .83f : .995f));
        material.setStroke(dp(1), alpha(palette.dark ? Color.WHITE : palette.card, palette.dark ? .16f : .90f));
        if (Build.VERSION.SDK_INT >= 31 && getWindow() != null) getWindow().setBackgroundBlurRadius(blurred ? dp(28) : 0);
        frame.setTag(cc.huevia.R.id.preset_filter_material, blurred ? "blur" : "translucent-fallback");
    }
    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) updateSystemBars();
    }
    private void updateSystemBars() {
        if (Build.VERSION.SDK_INT >= 30 && getWindow() != null) {
            android.view.WindowInsetsController controller = getWindow().getInsetsController();
            if (controller != null) {
                int mask = android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                        | android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                controller.setSystemBarsAppearance(palette.dark ? 0 : mask, mask);
            }
        }
    }
    @Override public void dismiss() {
        if (Build.VERSION.SDK_INT >= 31 && manager != null && blurListener != null) {
            manager.removeCrossWindowBlurEnabledListener(blurListener); blurListener = null;
        }
        super.dismiss();
    }
    private final class LimitedScroll extends ScrollView {
        int limit = Integer.MAX_VALUE;
        LimitedScroll() { super(activity); }
        @Override protected void onMeasure(int width, int height) {
            super.onMeasure(width, MeasureSpec.makeMeasureSpec(limit == Integer.MAX_VALUE ? 100000 : limit, MeasureSpec.AT_MOST));
        }
    }
    private final class ChipFlow extends ViewGroup {
        final int maxColumns; int columns, cell, gap = dp(8);
        ChipFlow(int maxColumns) { super(activity); this.maxColumns = maxColumns; }
        @Override protected void onMeasure(int widthSpec, int heightSpec) {
            int width = MeasureSpec.getSize(widthSpec);
            float font = getResources().getConfiguration().fontScale;
            columns = Math.max(1, Math.min(maxColumns, (width + gap) / (dp(124 * Math.max(1f, font)) + gap)));
            cell = (width - gap * (columns - 1)) / columns;
            int height = 0;
            for (int first = 0; first < getChildCount(); first += columns) {
                int row = dp(48);
                for (int i = first; i < Math.min(first + columns, getChildCount()); i++) {
                    View child = getChildAt(i); child.measure(MeasureSpec.makeMeasureSpec(cell, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED));
                    row = Math.max(row, child.getMeasuredHeight());
                }
                height += row + (first == 0 ? 0 : gap);
            }
            setMeasuredDimension(width, height);
        }
        @Override protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
            int y = 0;
            for (int first = 0; first < getChildCount(); first += columns) {
                int row = dp(48);
                for (int i = first; i < Math.min(first + columns, getChildCount()); i++) row = Math.max(row, getChildAt(i).getMeasuredHeight());
                for (int i = first; i < Math.min(first + columns, getChildCount()); i++) {
                    int x = (i - first) * (cell + gap); getChildAt(i).layout(x, y, x + cell, y + row);
                }
                y += row + gap;
            }
        }
    }
    private TextView text(String value, float size, boolean bold) {
        TextView text = new TextView(getContext()); text.setText(value); text.setTextSize(size); text.setTextColor(palette.text);
        text.setTypeface(Typeface.create("sans-serif", bold ? Typeface.BOLD : Typeface.NORMAL)); return text;
    }
    private GradientDrawable shape(int color, int radius) { GradientDrawable shape = new GradientDrawable(); shape.setColor(color); shape.setCornerRadius(dp(radius)); return shape; }
    private RippleDrawable ripple(int color, int radius) { return new RippleDrawable(ColorStateList.valueOf(alpha(palette.text, .10f)), shape(color, radius), shape(Color.WHITE, radius)); }
    private static int alpha(int color, float value) { return (color & 0xffffff) | (Math.round(value * 255) << 24); }
    private float density() { return activity.getResources().getDisplayMetrics().density; }
    private int dp(float value) { return Math.round(value * density()); }
}
