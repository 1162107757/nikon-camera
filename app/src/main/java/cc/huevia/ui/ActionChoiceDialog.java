package cc.huevia.ui;

import android.app.AlertDialog;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.InsetDrawable;
import android.graphics.drawable.RippleDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import cc.huevia.R;
import java.util.ArrayList;
import java.util.List;

/** Compact action menus. Confirmations, forms and permission choices keep their explicit actions. */
public final class ActionChoiceDialog {
    private final Context context;
    private final UiPalette palette;
    private final String title;
    private final List<Action> actions = new ArrayList<>();
    private String note = "", secondaryLabel = "";
    private Runnable secondary;
    private static final class Action {
        final AppIcon.Kind icon; final String title, subtitle; final Runnable run;
        Action(AppIcon.Kind icon, String title, String subtitle, Runnable run) {
            this.icon = icon; this.title = title; this.subtitle = subtitle; this.run = run;
        }
    }
    public ActionChoiceDialog(Context context, UiPalette palette, String title) {
        this.context = context; this.palette = palette; this.title = title;
    }
    public ActionChoiceDialog add(AppIcon.Kind icon, String title, String subtitle, Runnable action) {
        if (action == null) throw new IllegalArgumentException("Action required");
        actions.add(new Action(icon, title, subtitle == null ? "" : subtitle, action)); return this;
    }
    public ActionChoiceDialog note(String value) { note = value == null ? "" : value; return this; }
    public ActionChoiceDialog secondary(String label, Runnable action) {
        secondaryLabel = label; secondary = action; return this;
    }
    public AlertDialog create() {
        LinearLayout header = new LinearLayout(context); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(20), dp(8), dp(14), dp(2));
        TextView heading = text(title, 16, palette.text, true); heading.setMaxLines(3);
        header.addView(heading, new LinearLayout.LayoutParams(0, -2, 1));
        ImageView close = new ImageView(context); close.setImageDrawable(new AppIcon(AppIcon.Kind.CLOSE, palette.secondary, density()));
        close.setPadding(dp(13), dp(13), dp(13), dp(13)); close.setContentDescription("关闭" + title);
        close.setFocusable(true); close.setBackground(new RippleDrawable(ColorStateList.valueOf(alpha(palette.primary, .12f)),
                new InsetDrawable(shape(palette.container, 16), dp(6)), new InsetDrawable(shape(Color.WHITE, 16), dp(6))));
        header.addView(close, new LinearLayout.LayoutParams(dp(44), dp(44)));
        LinearLayout content = new LinearLayout(context); content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(20), 0, dp(20), dp(18));
        List<View> entries = new ArrayList<>();
        for (Action action : actions) {
            View row = row(action); entries.add(row); LinearLayout.LayoutParams layout = new LinearLayout.LayoutParams(-1, -2);
            layout.topMargin = dp(8); content.addView(row, layout);
        }
        TextView link = null;
        if (!note.isEmpty() || secondary != null) {
            LinearLayout footer = new LinearLayout(context); footer.setGravity(Gravity.CENTER_VERTICAL);
            LinearLayout.LayoutParams footerLayout = new LinearLayout.LayoutParams(-1, -2); footerLayout.topMargin = dp(10);
            content.addView(footer, footerLayout);
            TextView info = text(note, 12, palette.secondary, false); info.setLineSpacing(dp(2), 1);
            footer.addView(info, new LinearLayout.LayoutParams(0, -2, 1));
            if (secondary != null) {
                link = text(secondaryLabel, 12, palette.primary, true); link.setGravity(Gravity.CENTER);
                link.setPadding(dp(10), 0, 0, 0); link.setMinHeight(dp(44)); link.setMinimumWidth(dp(64));
                link.setFocusable(true); footer.addView(link, new LinearLayout.LayoutParams(-2, -2));
            }
        }
        int maxHeight = Math.min(dp(520), (int) (context.getResources().getDisplayMetrics().heightPixels * .62f));
        ScrollView scroll = new ScrollView(context) {
            @Override protected void onMeasure(int width, int height) {
                int limit = View.MeasureSpec.getMode(height) == View.MeasureSpec.UNSPECIFIED ? maxHeight
                        : Math.min(maxHeight, View.MeasureSpec.getSize(height));
                super.onMeasure(width, View.MeasureSpec.makeMeasureSpec(limit, View.MeasureSpec.AT_MOST));
            }
        };
        scroll.setClipToPadding(false); scroll.addView(content);
        AlertDialog dialog = new AppDialog.Builder(context, palette.dark ? R.style.AppThemeDark : R.style.AppThemeLight)
                .setCustomTitle(header).setView(scroll).create();
        dialog.setCanceledOnTouchOutside(true); close.setOnClickListener(view -> dialog.dismiss());
        boolean[] dispatched = {false};
        for (int i = 0; i < actions.size(); i++) {
            Action action = actions.get(i); entries.get(i).setOnClickListener(view -> {
                if (dispatched[0]) return; dispatched[0] = true; dialog.dismiss(); action.run.run();
            });
        }
        if (link != null) link.setOnClickListener(view -> {
            if (dispatched[0]) return; dispatched[0] = true; dialog.dismiss(); secondary.run();
        });
        return dialog;
    }
    public AlertDialog show() { AlertDialog dialog = create(); dialog.show(); return dialog; }

    private View row(Action action) {
        LinearLayout row = new LinearLayout(context); row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(14), dp(12), dp(12), dp(12)); row.setMinimumHeight(dp(action.subtitle.isEmpty() ? 52 : 66));
        row.setBackground(new RippleDrawable(ColorStateList.valueOf(alpha(palette.primary, .1f)), shape(palette.container, 14), shape(Color.WHITE, 14)));
        row.setFocusable(true); row.setClickable(true); row.setTag("compact-action:" + action.title);
        row.setContentDescription(action.title + (action.subtitle.isEmpty() ? "" : "，" + action.subtitle));
        ImageView icon = new ImageView(context); icon.setImageDrawable(new AppIcon(action.icon, palette.text, density()));
        icon.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO); row.addView(icon, new LinearLayout.LayoutParams(dp(24), dp(24)));
        LinearLayout labels = new LinearLayout(context); labels.setOrientation(LinearLayout.VERTICAL);
        TextView label = text(action.title, 14, palette.text, true); labels.addView(label);
        if (!action.subtitle.isEmpty()) {
            TextView subtitle = text(action.subtitle, 12, palette.secondary, false); subtitle.setMaxLines(3);
            LinearLayout.LayoutParams subLayout = new LinearLayout.LayoutParams(-1, -2); subLayout.topMargin = dp(4); labels.addView(subtitle, subLayout);
        }
        LinearLayout.LayoutParams labelLayout = new LinearLayout.LayoutParams(0, -2, 1); labelLayout.leftMargin = dp(12); labelLayout.rightMargin = dp(8); row.addView(labels, labelLayout);
        ImageView chevron = new ImageView(context); chevron.setImageDrawable(new AppIcon(AppIcon.Kind.CHEVRON, palette.secondary, density()));
        chevron.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO); row.addView(chevron, new LinearLayout.LayoutParams(dp(16), dp(16)));
        return row;
    }
    private TextView text(String value, float sp, int color, boolean medium) {
        TextView view = new TextView(context); view.setText(value); view.setTextSize(sp); view.setTextColor(color);
        view.setTypeface(Typeface.create(medium ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL)); view.setIncludeFontPadding(false); return view;
    }
    private GradientDrawable shape(int color, int radius) { GradientDrawable shape = new GradientDrawable(); shape.setColor(color); shape.setCornerRadius(dp(radius)); return shape; }
    private static int alpha(int color, float amount) { return color & 0x00ffffff | Math.round(255 * amount) << 24; }
    private float density() { return context.getResources().getDisplayMetrics().density; }
    private int dp(float value) { return Math.round(value * density()); }
}
