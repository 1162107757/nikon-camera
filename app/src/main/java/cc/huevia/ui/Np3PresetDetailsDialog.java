package cc.huevia.ui;

import android.content.Context;
import android.app.AlertDialog;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.InsetDrawable;
import android.graphics.drawable.RippleDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import cc.huevia.ncp.Np3PresetDetails;
import java.util.ArrayList;
import java.util.List;

/** Small, read-only parameter tables using the same palette and dialog finish as the preset library. */
public final class Np3PresetDetailsDialog {
    private Np3PresetDetailsDialog() {}

    public static void show(Context context, UiPalette palette, Np3PresetDetails details) {
        LinearLayout content = new LinearLayout(context); content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(context, 20), dp(context, 4), dp(context, 20), dp(context, 12));
        TextView name = text(context, palette.text, 14, true);
        name.setText(details.registrationName.isEmpty() ? "未命名预设" : details.registrationName);
        name.setMaxLines(2); content.addView(name);
        TextView format = text(context, palette.secondary, 12, false);
        format.setText("NP3 · " + details.version + " · " + details.baseLabel);
        format.setPadding(0, dp(context, 5), 0, dp(context, 10)); content.addView(format);
        TextView status = text(context, palette.secondary, 12, false);
        status.setText(details.previewSupported ? "参数已解析 · 手机近似预览" : "原文件已保留 · 手机预览暂不支持");
        status.setPadding(dp(context, 10), dp(context, 8), dp(context, 10), dp(context, 8));
        GradientDrawable background = new GradientDrawable(); background.setColor(palette.container);
        background.setCornerRadius(dp(context, 12)); status.setBackground(background); content.addView(status);
        if (!details.previewSupported) {
            TextView reason = text(context, palette.secondary, 12, false);
            reason.setText(details.previewReason); reason.setPadding(0, dp(context, 10), 0, 0); content.addView(reason);
        }
        if (!details.groups.isEmpty()) {
            List<String> ids = new ArrayList<>(), labels = new ArrayList<>();
            for (Np3PresetDetails.Group group : details.groups) {
                if (group.id.equals("grading-blend")) continue;
                ids.add(group.id); labels.add(group.id.equals("detail") ? "细节" : group.id.equals("tone") ? "色调"
                        : group.id.equals("blender") ? "混色" : "分级");
            }
            LinearLayout tabs = new LinearLayout(context); tabs.setPadding(dp(context, 3), dp(context, 3), dp(context, 3), dp(context, 3));
            tabs.setBackground(shape(context, palette.container, 14));
            LinearLayout.LayoutParams tabLayout = new LinearLayout.LayoutParams(-1, dp(context, 40));
            tabLayout.topMargin = dp(context, 12); tabLayout.bottomMargin = dp(context, 6); content.addView(tabs, tabLayout);
            LinearLayout values = new LinearLayout(context); values.setOrientation(LinearLayout.VERTICAL); content.addView(values);
            List<TextView> items = new ArrayList<>();
            for (String label : labels) {
                TextView item = text(context, palette.secondary, 12, false); item.setText(label);
                item.setGravity(Gravity.CENTER); item.setSingleLine(true); tabs.addView(item, new LinearLayout.LayoutParams(0, -1, 1)); items.add(item);
            }
            for (int i = 0; i < items.size(); i++) {
                final int selected = i;
                items.get(i).setOnClickListener(view -> select(context, palette, details, ids.get(selected), selected, items, values));
            }
            select(context, palette, details, ids.get(0), 0, items, values);
        }
        if (!details.note.isEmpty()) {
            TextView heading = text(context, palette.secondary, 12, true); heading.setText("备注");
            heading.setPadding(0, dp(context, 18), 0, dp(context, 5)); content.addView(heading);
            TextView note = text(context, palette.secondary, 12, false); note.setText(details.note); content.addView(note);
        }
        if (details.previewSupported) {
            TextView note = text(context, palette.secondary, 11, false);
            note.setText("手机效果为近似模拟，相机导入会另行检查兼容性。");
            note.setPadding(0, dp(context, 16), 0, 0); content.addView(note);
        }
        int maxHeight = Math.min(dp(context, 520), (int) (context.getResources().getDisplayMetrics().heightPixels * .62f));
        ScrollView scroll = new ScrollView(context) {
            @Override protected void onMeasure(int width, int height) {
                super.onMeasure(width, View.MeasureSpec.makeMeasureSpec(Math.min(maxHeight,
                        View.MeasureSpec.getMode(height) == View.MeasureSpec.UNSPECIFIED ? maxHeight
                                : View.MeasureSpec.getSize(height)), View.MeasureSpec.AT_MOST));
            }
        };
        scroll.setClipToPadding(false); scroll.addView(content);
        LinearLayout header = new LinearLayout(context); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(context, 20), dp(context, 8), dp(context, 8), 0);
        TextView title = text(context, palette.text, 16, true); title.setText("NP3 参数");
        header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        TextView close = text(context, palette.secondary, 22, false); close.setText("×");
        close.setGravity(Gravity.CENTER); close.setContentDescription("关闭 NP3 参数");
        close.setFocusable(true);
        InsetDrawable closeFill = new InsetDrawable(shape(context, palette.container, 16), dp(context, 6));
        close.setBackground(new RippleDrawable(ColorStateList.valueOf(palette.primaryContainer), closeFill,
                new InsetDrawable(shape(context, android.graphics.Color.WHITE, 16), dp(context, 6))));
        header.addView(close, new LinearLayout.LayoutParams(dp(context, 44), dp(context, 44)));
        AlertDialog dialog = new AppDialog.Builder(context).setCustomTitle(header).setView(scroll).create();
        dialog.setCanceledOnTouchOutside(true);
        close.setOnClickListener(view -> dialog.dismiss()); dialog.show();
    }

    private static void select(Context context, UiPalette palette, Np3PresetDetails details, String id, int selected,
            List<TextView> items, LinearLayout values) {
        for (int i = 0; i < items.size(); i++) {
            TextView item = items.get(i); boolean active = i == selected;
            item.setSelected(active); item.setTextColor(active ? palette.onPrimaryContainer : palette.secondary);
            item.setBackground(active ? shape(context, palette.primaryContainer, 11) : null);
            item.setTypeface(Typeface.create(active ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
            item.setContentDescription(item.getText() + (active ? "，已选中" : ""));
        }
        values.removeAllViews();
        for (Np3PresetDetails.Group group : details.groups) {
            if (!group.id.equals(id) && !(id.equals("grading") && group.id.equals("grading-blend"))) continue;
            if (!group.columns.isEmpty()) addRow(values, palette, "", group.columns.toArray(new String[0]), true);
            if (group.id.equals("grading-blend")) {
                View line = new View(context); line.setBackgroundColor(palette.container);
                LinearLayout.LayoutParams spacing = new LinearLayout.LayoutParams(-1, dp(context, 1));
                spacing.topMargin = dp(context, 5); spacing.bottomMargin = dp(context, 5); values.addView(line, spacing);
            }
            for (Np3PresetDetails.Row row : group.rows) addRow(values, palette, row.label, row.values.toArray(new String[0]), false);
        }
    }

    private static void addRow(LinearLayout parent, UiPalette palette, String label, String[] values, boolean header) {
        Context context = parent.getContext(); LinearLayout row = new LinearLayout(context);
        row.setGravity(Gravity.CENTER_VERTICAL); row.setPadding(0, dp(context, header ? 4 : 7), 0, dp(context, header ? 4 : 7));
        TextView key = text(context, palette.secondary, header ? 11 : 13, false); key.setText(label);
        key.setMinWidth(0); row.addView(key, new LinearLayout.LayoutParams(0, -2, values.length == 1 ? 1.25f : 1.15f));
        for (String value : values) {
            TextView cell = text(context, header ? palette.secondary : palette.text, header ? 11 : 13, false);
            cell.setText(value); cell.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
            if (!header) cell.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
            row.addView(cell, new LinearLayout.LayoutParams(0, -2, 1));
        }
        parent.addView(row, new LinearLayout.LayoutParams(-1, -2));
    }
    private static TextView text(Context context, int color, int sp, boolean medium) {
        TextView result = new TextView(context); result.setTextSize(sp); result.setTextColor(color);
        result.setTypeface(Typeface.create(medium ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
        result.setIncludeFontPadding(false); result.setLineSpacing(dp(context, 2), 1); return result;
    }
    private static int dp(Context context, float value) { return Math.round(value * context.getResources().getDisplayMetrics().density); }
    private static GradientDrawable shape(Context context, int color, int radius) {
        GradientDrawable result = new GradientDrawable(); result.setColor(color); result.setCornerRadius(dp(context, radius)); return result;
    }
}
