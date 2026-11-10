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
import cc.huevia.library.PresetCategories;
import cc.huevia.library.PresetHomeFilter;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Consumer;

/** B: floating glass sheet, independent draft, fixed actions and a bounded scroll region. */
public final class PresetFilterSheet extends Dialog {
    private final Activity activity;
    private final UiPalette palette;
    private final boolean local;
    private final Consumer<PresetHomeFilter> apply;
    private final List<String> categories = new ArrayList<>();
    private PresetHomeFilter draft;
    private LinearLayout content, frame;
    private LimitedScroll scroll;
    private final GradientDrawable material = new GradientDrawable();
    private java.util.function.Consumer<Boolean> blurListener;
    private WindowManager manager;

    public PresetFilterSheet(Activity activity, UiPalette palette, boolean local,
                             PresetHomeFilter applied, Collection<String> available, Consumer<PresetHomeFilter> apply) {
        super(activity, palette.dark ? R.style.PresetFilterDialogDark : R.style.PresetFilterDialogLight);
        this.activity = activity; this.palette = palette; this.local = local; this.apply = apply; draft = applied;
        Set<String> values = new LinkedHashSet<>(available);
        categories.add(PresetCategories.ALL);
        for (String category : PresetCategories.SUGGESTED) if (values.remove(category)) categories.add(category);
        values.remove(PresetCategories.ALL); boolean uncategorized = values.remove(""); categories.addAll(values);
        if (uncategorized) categories.add("");
        if (!categories.contains(applied.category)) categories.add(applied.category);
        requestWindowFeature(Window.FEATURE_NO_TITLE); setCanceledOnTouchOutside(true);
        build();
    }

    private void build() {
        frame = new LinearLayout(getContext()); frame.setOrientation(LinearLayout.VERTICAL);
        frame.setTag("preset-filter-sheet"); frame.setPadding(dp(18), dp(10), dp(18), dp(12));
        if (Build.VERSION.SDK_INT >= 28) frame.setAccessibilityPaneTitle("预设筛选");
        View handle = new View(getContext()); handle.setBackground(shape(palette.outline, 2));
        LinearLayout.LayoutParams grip = new LinearLayout.LayoutParams(dp(30), dp(3)); grip.gravity = Gravity.CENTER_HORIZONTAL;
        grip.bottomMargin = dp(4); frame.addView(handle, grip); handle.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        LinearLayout header = new LinearLayout(getContext()); header.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = text("筛选", 18, true); header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        ImageView close = new ImageView(getContext()); close.setImageDrawable(new AppIcon(AppIcon.Kind.CLOSE, palette.text, density()));
        close.setPadding(dp(14), dp(14), dp(14), dp(14)); close.setContentDescription("关闭筛选，放弃未应用修改");
        close.setTag("preset-filter-close"); close.setFocusable(true); close.setBackground(ripple(Color.TRANSPARENT, 24));
        close.setOnClickListener(v -> dismiss()); header.addView(close, new LinearLayout.LayoutParams(dp(48), dp(48)));
        frame.addView(header, new LinearLayout.LayoutParams(-1, -2));
        content = new LinearLayout(getContext()); content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0, 0, 0, dp(8));
        scroll = new LimitedScroll(); scroll.setFillViewport(false); scroll.setClipToPadding(false);
        scroll.setTag("preset-filter-options"); scroll.addView(content, new ScrollView.LayoutParams(-1, -2));
        frame.addView(scroll, new LinearLayout.LayoutParams(-1, -2));
        LinearLayout actions = new LinearLayout(getContext()); actions.setGravity(Gravity.CENTER_VERTICAL);
        actions.setPadding(0, dp(8), 0, 0);
        TextView reset = text("重置", 14, false); reset.setGravity(Gravity.CENTER); reset.setMinHeight(dp(48));
        reset.setPadding(dp(12), 0, dp(12), 0); reset.setTextColor(palette.secondary); reset.setTag("preset-filter-reset");
        reset.setBackground(ripple(Color.TRANSPARENT, 24)); reset.setFocusable(true);
        reset.setOnClickListener(v -> { draft = PresetHomeFilter.empty(); rebuildChoices(); });
        actions.addView(reset, new LinearLayout.LayoutParams(-2, -2));
        actions.addView(new View(getContext()), new LinearLayout.LayoutParams(0, 1, 1));
        TextView commit = text("应用", 14, true); commit.setMinHeight(dp(48)); commit.setGravity(Gravity.CENTER);
        commit.setTextColor(palette.onAction); commit.setPadding(dp(28), dp(8), dp(28), dp(8));
        commit.setBackground(ripple(palette.action, 24)); commit.setTag("preset-filter-apply"); commit.setFocusable(true);
        commit.setOnClickListener(v -> { PresetHomeFilter result = draft; dismiss(); apply.accept(result); });
        actions.addView(commit, new LinearLayout.LayoutParams(-2, -2));
        frame.addView(actions, new LinearLayout.LayoutParams(-1, -2));
        setContentView(frame); rebuildChoices();
    }

    private void rebuildChoices() {
        int y = scroll.getScrollY(); content.removeAllViews();
        group("风格", categories, draft.category, 4, value -> draft = draft.withCategory(value), true);
        if (!local) group("下载状态", java.util.Arrays.asList("all", "missing", "saved"), draft.download, 3,
                value -> draft = draft.withDownload(value), false);
        group("预设类型", java.util.Arrays.asList("", "NCP", "NP3"), draft.type, 3,
                value -> draft = draft.withType(value), false);
        scroll.post(() -> scroll.scrollTo(0, y));
    }

    private void group(String name, List<String> values, String selected, int columns, Consumer<String> select, boolean style) {
        TextView title = text(name, 12, false); title.setTextColor(palette.secondary);
        title.setPadding(0, dp(12), 0, dp(8)); content.addView(title, new LinearLayout.LayoutParams(-1, -2));
        ChipFlow flow = new ChipFlow(columns); content.addView(flow, new LinearLayout.LayoutParams(-1, -2));
        for (String value : values) {
            String label = style ? (PresetCategories.ALL.equals(value) ? value : PresetCategories.label(value))
                    : "missing".equals(value) ? "未下载" : "saved".equals(value) ? "已下载" : "all".equals(value) || value.isEmpty() ? "全部" : value;
            boolean active = value.equals(selected);
            TextView chip = text(label, 12, active); chip.setGravity(Gravity.CENTER); chip.setMinHeight(dp(48));
            chip.setMaxLines(2); chip.setEllipsize(android.text.TextUtils.TruncateAt.END);
            chip.setPadding(dp(8), dp(8), dp(8), dp(8)); chip.setIncludeFontPadding(false);
            chip.setTextColor(active ? palette.onPrimaryContainer : palette.text);
            chip.setBackground(ripple(active ? palette.primaryContainer : alpha(palette.card, .70f), 24));
            if (active) {
                AppIcon check = new AppIcon(AppIcon.Kind.CHECK, palette.onPrimaryContainer, density());
                check.setBounds(0, 0, dp(12), dp(12)); chip.setCompoundDrawablesRelative(null, null, check, null);
                chip.setCompoundDrawablePadding(dp(3));
            }
            chip.setSelected(active); chip.setFocusable(true); chip.setContentDescription(name + "：" + label);
            chip.setTag("preset-filter:" + name + ":" + value);
            chip.setOnClickListener(v -> { select.accept(value); rebuildChoices(); }); flow.addView(chip);
        }
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
            columns = Math.max(1, Math.min(maxColumns, (width + gap) / (dp(64 * Math.max(1f, font)) + gap)));
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
