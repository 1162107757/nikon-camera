package cc.huevia.ui;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;

/** Fixed source choices. Frame and selection share one inset geometry, including their end radii. */
final class PhotoPresetSourceTabs extends LinearLayout {
    final Button mine, online;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF trackBounds = new RectF(), selectionBounds = new RectF();
    private float outerRadius, innerRadius;
    private boolean onlineSelected;

    PhotoPresetSourceTabs(Context context, Runnable chooseMine, Runnable chooseOnline) {
        super(context);
        setOrientation(HORIZONTAL);
        setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        setGravity(Gravity.CENTER_VERTICAL);
        setWillNotDraw(false);
        setPadding(dp(3), 0, dp(3), 0);
        setMinimumHeight(dp(48));
        setTag("editor-source-tabs");
        mine = choice("我的", "editor-source-mine", chooseMine);
        online = choice("在线", "editor-source-online", chooseOnline);
        addView(mine, new LayoutParams(0, LayoutParams.MATCH_PARENT, 1));
        addView(online, new LayoutParams(0, LayoutParams.MATCH_PARENT, 1));
        setOnline(true);
    }

    void setOnline(boolean value) {
        onlineSelected = value;
        style(mine, !value);
        style(online, value);
        invalidate();
    }

    @Override protected void onMeasure(int widthSpec, int heightSpec) {
        float scale = getResources().getConfiguration().fontScale;
        int width = dp(104 * Math.max(1f, scale / 1.3f));
        width = resolveSize(width, widthSpec);
        super.onMeasure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), heightSpec);
    }

    @Override protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        super.onLayout(changed, left, top, right, bottom);
        geometry();
    }

    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        geometry();
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(0x18ffffff);
        canvas.drawRoundRect(trackBounds, outerRadius, outerRadius, paint);
        paint.setColor(0xfff4f5f7);
        canvas.drawRoundRect(selectionBounds, innerRadius, innerRadius, paint);
        Button pressed = mine.isPressed() ? mine : online.isPressed() ? online : null;
        if (pressed != null) {
            RectF feedback = new RectF(pressed.getLeft(), selectionBounds.top, pressed.getRight(), selectionBounds.bottom);
            paint.setColor(pressed.isSelected() ? 0x22000000 : 0x28ffffff);
            canvas.drawRoundRect(feedback, innerRadius, innerRadius, paint);
        }
        float stroke = getResources().getDisplayMetrics().density;
        RectF edge = new RectF(trackBounds);
        edge.inset(stroke / 2f, stroke / 2f);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(stroke);
        paint.setColor(0x66ffffff);
        canvas.drawRoundRect(edge, Math.max(0, outerRadius - stroke / 2f), Math.max(0, outerRadius - stroke / 2f), paint);
        Button focused = mine.isFocused() ? mine : online.isFocused() ? online : null;
        if (focused != null) {
            RectF focus = new RectF(focused.getLeft(), selectionBounds.top, focused.getRight(), selectionBounds.bottom);
            focus.inset(stroke / 2f, stroke / 2f);
            paint.setColor(0xffffe335);
            canvas.drawRoundRect(focus, Math.max(0, innerRadius - stroke / 2f), Math.max(0, innerRadius - stroke / 2f), paint);
        }
        paint.setStyle(Paint.Style.FILL);
    }

    private void geometry() {
        Paint.FontMetrics metrics = mine.getPaint().getFontMetrics();
        float paintedHeight = Math.max(dp(32), metrics.bottom - metrics.top + dp(10));
        paintedHeight = Math.min(Math.max(0, getHeight() - dp(2)), paintedHeight);
        float top = (getHeight() - paintedHeight) / 2f;
        trackBounds.set(0, top, getWidth(), top + paintedHeight);
        Button chosen = onlineSelected ? online : mine;
        selectionBounds.set(chosen.getLeft(), top + dp(3), chosen.getRight(), top + paintedHeight - dp(3));
        outerRadius = trackBounds.height() / 2f;
        innerRadius = selectionBounds.height() / 2f;
    }

    private Button choice(String label, String tag, Runnable action) {
        Button button = new Button(getContext()) {
            @Override protected void drawableStateChanged() {
                super.drawableStateChanged();
                PhotoPresetSourceTabs.this.invalidate();
            }
        };
        button.setText(label);
        button.setAllCaps(false);
        button.setTextSize(12);
        button.setSingleLine(true);
        button.setIncludeFontPadding(false);
        button.setGravity(Gravity.CENTER);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setMinHeight(0);
        button.setMinimumHeight(0);
        button.setPadding(dp(2), 0, dp(2), 0);
        button.setStateListAnimator(null);
        button.setElevation(0);
        button.setBackground(new ColorDrawable(Color.TRANSPARENT));
        button.setBackgroundTintList(null);
        button.setForeground(null);
        button.setDefaultFocusHighlightEnabled(false);
        button.setTag(tag);
        button.setOnFocusChangeListener((view, focused) -> invalidate());
        button.setOnClickListener(view -> action.run());
        return button;
    }

    private void style(Button button, boolean selected) {
        button.setSelected(selected);
        button.setTextColor(selected ? 0xff191e17 : 0xffc8cdca);
        button.setTypeface(Typeface.create(selected ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
        button.setContentDescription((button == mine ? "我的滤镜" : "在线滤镜") + (selected ? "，已选择" : ""));
    }

    private int dp(float value) { return Math.round(value * getResources().getDisplayMetrics().density); }
}
