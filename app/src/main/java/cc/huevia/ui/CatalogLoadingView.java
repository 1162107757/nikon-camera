package cc.huevia.ui;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Shader;
import android.view.View;
import android.view.animation.LinearInterpolator;

/** Photo-card placeholders. Animation is decorative, never a fabricated download percentage. */
public final class CatalogLoadingView extends View {
    private final UiPalette colors;
    private final Paint base = new Paint(Paint.ANTI_ALIAS_FLAG), shine = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF rect = new RectF();
    private ValueAnimator animator;
    private float phase = .35f;
    public CatalogLoadingView(Context context, UiPalette colors) {
        super(context); this.colors = colors;
        setContentDescription("正在加载在线预设"); setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);
        setTag("catalog-loading-animation");
    }
    @Override protected void onMeasure(int width, int height) {
        int w = MeasureSpec.getSize(width), columns = w >= dp(540) ? 3 : 2;
        float card = (w - dp(12) * (columns - 1)) / (float) columns;
        setMeasuredDimension(w, resolveSize(Math.round((card * .68f + dp(46)) * 2 + dp(12)), height));
    }
    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        int columns = getWidth() >= dp(540) ? 3 : 2;
        float gap = dp(12), card = (getWidth() - gap * (columns - 1)) / columns, image = card * .68f;
        float band = getWidth() * .7f, x = -band + phase * (getWidth() + band * 2);
        shine.setShader(new LinearGradient(x, 0, x + band, dp(100),
                new int[]{0x00ffffff, colors.card, 0x00ffffff}, new float[]{0, .5f, 1}, Shader.TileMode.CLAMP));
        for (int row = 0; row < 2; row++) for (int col = 0; col < columns; col++) {
            float left = col * (card + gap), top = row * (image + dp(46) + gap);
            tile(canvas, left, top, card, image, dp(13));
            tile(canvas, left, top + image + dp(12), card * .72f, dp(8), dp(4));
            tile(canvas, left, top + image + dp(28), card * .43f, dp(6), dp(3));
        }
    }
    private void tile(Canvas canvas, float x, float y, float w, float h, float radius) {
        rect.set(x, y, x + w, y + h); base.setColor(colors.container);
        canvas.drawRoundRect(rect, radius, radius, base); canvas.drawRoundRect(rect, radius, radius, shine);
    }
    private void updateAnimation() {
        boolean run = isAttachedToWindow() && isShown() && getWindowVisibility() == VISIBLE && ValueAnimator.areAnimatorsEnabled();
        if (!run) { if (animator != null) animator.cancel(); return; }
        if (animator == null) {
            animator = ValueAnimator.ofFloat(0, 1); animator.setDuration(1500); animator.setRepeatCount(ValueAnimator.INFINITE);
            animator.setInterpolator(new LinearInterpolator());
            animator.addUpdateListener(value -> { phase = (Float) value.getAnimatedValue(); invalidate(); });
        }
        if (!animator.isStarted()) animator.start();
    }
    @Override protected void onAttachedToWindow() { super.onAttachedToWindow(); updateAnimation(); }
    @Override protected void onDetachedFromWindow() { if (animator != null) animator.cancel(); super.onDetachedFromWindow(); }
    @Override protected void onVisibilityChanged(View changed, int visibility) { super.onVisibilityChanged(changed, visibility); updateAnimation(); }
    @Override protected void onWindowVisibilityChanged(int visibility) { super.onWindowVisibilityChanged(visibility); updateAnimation(); }
    private int dp(float value) { return Math.round(value * getResources().getDisplayMetrics().density); }
}
