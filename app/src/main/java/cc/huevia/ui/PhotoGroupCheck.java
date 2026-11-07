package cc.huevia.ui;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.drawable.RippleDrawable;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import cc.huevia.album.PhotoGroupSelection;
/** Shared 22dp date checkbox in a full 48dp target, with an explicit mixed state. */
public final class PhotoGroupCheck extends View {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final int accent, ink, muted;
    private PhotoGroupSelection.State state = PhotoGroupSelection.State.NONE;
    public PhotoGroupCheck(Context context, int accent, int ink, int muted) {
        super(context); this.accent = accent; this.ink = ink; this.muted = muted;
        setTag("photo-date-group-check"); setClickable(true); setFocusable(true);
        setMinimumWidth(dp(48)); setMinimumHeight(dp(48));
        setBackground(new RippleDrawable(ColorStateList.valueOf(0x26f3b493), null, null));
    }
    public PhotoGroupSelection.State selectionState() { return state; }
    public void bind(String date, PhotoGroupSelection.State value, int count) {
        state = value; setSelected(value == PhotoGroupSelection.State.ALL);
        String description = value == PhotoGroupSelection.State.ALL ? "已全选" : value == PhotoGroupSelection.State.PARTIAL ? "已部分选择" : "未选择";
        setContentDescription(date + "，共 " + count + " 张，" + description + (value == PhotoGroupSelection.State.ALL ? "，取消整组选择" : "，选择整组"));
        if (android.os.Build.VERSION.SDK_INT >= 30) setStateDescription(description);
        invalidate();
    }
    @Override public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info) {
        super.onInitializeAccessibilityNodeInfo(info); info.setClassName("android.widget.CheckBox");
        info.setCheckable(true); info.setChecked(state == PhotoGroupSelection.State.ALL);
    }
    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas); float x = getWidth() / 2f, y = getHeight() / 2f, r = dp(10);
        paint.setStyle(Paint.Style.FILL); paint.setColor(state == PhotoGroupSelection.State.NONE ? android.graphics.Color.TRANSPARENT : accent);
        canvas.drawCircle(x, y, r, paint);
        paint.setStyle(Paint.Style.STROKE); paint.setStrokeWidth(dp(1.5f)); paint.setStrokeCap(Paint.Cap.ROUND); paint.setStrokeJoin(Paint.Join.ROUND);
        paint.setColor(state == PhotoGroupSelection.State.NONE ? muted : accent); canvas.drawCircle(x,y,r,paint);
        paint.setColor(ink); paint.setStrokeWidth(dp(1.8f));
        if (state == PhotoGroupSelection.State.PARTIAL) canvas.drawLine(x-dp(4),y,x+dp(4),y,paint);
        else if (state == PhotoGroupSelection.State.ALL) { android.graphics.Path path = new android.graphics.Path(); path.moveTo(x-dp(4.5f),y); path.lineTo(x-dp(1),y+dp(3.5f)); path.lineTo(x+dp(5),y-dp(4)); canvas.drawPath(path,paint); }
    }
    private int dp(float value) { return Math.round(value * getResources().getDisplayMetrics().density); }
}
