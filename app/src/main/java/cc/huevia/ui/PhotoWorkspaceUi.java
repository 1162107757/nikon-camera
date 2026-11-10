package cc.huevia.ui;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.InsetDrawable;
import android.graphics.drawable.LayerDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.StateListDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.widget.Button;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.lang.ref.WeakReference;
import java.util.WeakHashMap;

/** Quiet, shared chrome for the photo-first portrait and local workspaces. */
final class PhotoWorkspaceUi {
    static final int TEXT = 0xfff4f5f7;
    static final int MUTED = PhotoPrismaStyle.MUTED;
    static final int ACCENT = PhotoPrismaStyle.YELLOW;
    private static final WeakHashMap<HorizontalScrollView, RevealRequest> REVEALS = new WeakHashMap<>();

    private PhotoWorkspaceUi() { }

    /** Keep the complete native thumb inside the view at both ends, including its pressed state. */
    static void fitSliderThumb(android.widget.SeekBar slider) {
        Drawable thumb = slider.getThumb();
        int width = thumb == null ? 0 : Math.max(thumb.getIntrinsicWidth(), thumb.getMinimumWidth());
        int inset = Math.max(dp(slider.getContext(), 12),
                Math.max(slider.getThumbOffset(), (width + 1) / 2)) + dp(slider.getContext(), 2);
        slider.setPadding(Math.max(slider.getPaddingLeft(), inset), slider.getPaddingTop(),
                Math.max(slider.getPaddingRight(), inset), slider.getPaddingBottom());
    }

    static int entryWidth(Context context) {
        return dp(context, 56 * Math.max(1, context.getResources().getConfiguration().fontScale));
    }

    static int entryHeight(Context context) {
        return dp(context, 48 + 20 * Math.max(1, context.getResources().getConfiguration().fontScale));
    }

    /** Larger circular entries belong to portrait workspaces. */
    static LinearLayout toolEntry(Context context, String label, String tag, AppIcon.Kind icon, Runnable action) {
        return iconCaptionEntry(context, label, tag, icon, action, true);
    }

    /** Match the 26dp line icons, spacing and caption baseline of adjustment parameters. */
    static LinearLayout adjustmentEntry(Context context, String label, String tag, AppIcon.Kind icon, Runnable action) {
        return iconCaptionEntry(context, label, tag, icon, action, false);
    }

    private static LinearLayout iconCaptionEntry(Context context, String label, String tag,
                                                AppIcon.Kind icon, Runnable action, boolean circular) {
        LinearLayout entry = new LinearLayout(context);
        entry.setOrientation(LinearLayout.VERTICAL);
        entry.setGravity(Gravity.CENTER_HORIZONTAL);
        entry.setPadding(0, dp(context, circular ? 3 : 6), 0, 0);
        entry.setMinimumHeight(dp(context, 48));
        entry.setFocusable(true);
        entry.setClickable(true);
        entry.setTag(tag);
        entry.setContentDescription(label);
        entry.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335), tabShape(Color.TRANSPARENT, dp(context, 4)), null));
        ImageView image = new ImageView(context);
        image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        image.setImageDrawable(circular ? PhotoPrismaStyle.circle(context,icon,false)
                : new AppIcon(icon, 0x99ffffff, context.getResources().getDisplayMetrics().density));
        int iconSize = dp(context, circular ? 39 : 26);
        entry.addView(image, new LinearLayout.LayoutParams(iconSize, iconSize));
        LinearLayout.LayoutParams captionSize = new LinearLayout.LayoutParams(-1,
                dp(context, 20 * Math.max(1, context.getResources().getConfiguration().fontScale)));
        captionSize.topMargin = dp(context, 4);
        entry.addView(entryCaption(context, label), captionSize);
        entry.setOnClickListener(v -> action.run());
        return entry;
    }

    static TextView entryCaption(Context context, String label) {
        TextView caption = new TextView(context);
        caption.setText(label);
        caption.setTextColor(0x99ffffff);
        caption.setTextSize(10.5f);
        caption.setIncludeFontPadding(false);
        caption.setGravity(Gravity.TOP | Gravity.CENTER_HORIZONTAL);
        caption.setSingleLine(true);
        caption.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        int baseline = dp(context, 14 * Math.max(1, context.getResources().getConfiguration().fontScale));
        if (android.os.Build.VERSION.SDK_INT >= 28) {
            caption.setFallbackLineSpacing(false);
            caption.setFirstBaselineToTopHeight(baseline);
        } else caption.setPadding(0, Math.max(0, baseline + caption.getPaint().getFontMetricsInt().ascent), 0, 0);
        return caption;
    }

    static int tabHeight(Context context) {
        return dp(context, 48 * Math.max(1, context.getResources().getConfiguration().fontScale));
    }

    /** Shared by the editor's primary menu and the portrait submenus. */
    static void styleTab(Button control, boolean active) {
        Context context = control.getContext();
        control.setTextSize(12);
        control.setSingleLine(true);
        control.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        control.setTextColor(active ? ACCENT : 0x99ffffff);
        control.setSelected(active);
        control.setMinWidth(dp(context, 48));
        control.setMinimumWidth(dp(context, 48));
        LayerDrawable indicator = new LayerDrawable(new Drawable[]{tabShape(Color.TRANSPARENT, 0), tabShape(active ? ACCENT : Color.TRANSPARENT, dp(context, 1))});
        indicator.setLayerSize(1, dp(context, 18), dp(context, 2));
        indicator.setLayerGravity(1, Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        indicator.setLayerInset(1, 0, 0, 0, dp(context, 5));
        GradientDrawable focus = tabShape(0x0cffffff, dp(context, 8));
        focus.setStroke(dp(context, 1), ACCENT);
        StateListDrawable states = new StateListDrawable();
        states.addState(new int[]{android.R.attr.state_focused}, new InsetDrawable(focus, 0, dp(context, 5), 0, dp(context, 5)));
        states.addState(new int[]{}, indicator);
        control.setBackgroundTintList(null);
        control.setClipToOutline(false);
        control.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335), states,
                new InsetDrawable(tabShape(Color.WHITE, dp(context, 8)), 0, dp(context, 5), 0, dp(context, 5))));
        control.setPadding(dp(context, 4), 0, dp(context, 4), 0);
    }

    private static GradientDrawable tabShape(int color, float radius) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color);
        shape.setCornerRadius(radius);
        return shape;
    }

    static Button tool(Context context, String label, String tag, String icon, Runnable action) {
        WorkspaceButton button = new WorkspaceButton(context, icon, true);
        button.setText(label);
        button.setContentDescription(label);
        button.setTag(tag);
        button.setOnClickListener(v -> action.run());
        return button;
    }

    static Button icon(Context context, String icon, String description, String tag, Runnable action) {
        WorkspaceButton button = new WorkspaceButton(context, icon, false);
        button.setContentDescription(description);
        button.setTag(tag);
        button.setOnClickListener(v -> action.run());
        return button;
    }

    /** Call only when a choice, its available peers, or the viewport changes. */
    static void revealChoice(HorizontalScrollView rail, View choice) {
        if (rail == null || choice == null) return;
        RevealRequest pending = REVEALS.get(rail);
        if (pending != null) {
            pending.choice = new WeakReference<>(choice);
            return;
        }
        RevealRequest request = new RevealRequest(rail, choice);
        REVEALS.put(rail, request);
        rail.getViewTreeObserver().addOnGlobalLayoutListener(request);
        rail.requestLayout();
    }

    private static final class RevealRequest implements ViewTreeObserver.OnGlobalLayoutListener {
        private final WeakReference<HorizontalScrollView> rail;
        private WeakReference<View> choice;

        RevealRequest(HorizontalScrollView rail, View choice) {
            this.rail = new WeakReference<>(rail);
            this.choice = new WeakReference<>(choice);
        }

        @Override public void onGlobalLayout() {
            HorizontalScrollView scroller = rail.get();
            if (scroller == null) return;
            ViewTreeObserver observer = scroller.getViewTreeObserver();
            if (observer.isAlive()) observer.removeOnGlobalLayoutListener(this);
            REVEALS.remove(scroller);
            View selected = choice.get();
            if (!scroller.isAttachedToWindow() || selected == null || !selected.isShown()
                    || selected.getWidth() == 0 || scroller.getChildCount() == 0
                    || !(scroller.getChildAt(0) instanceof ViewGroup)) return;
            ViewGroup content = (ViewGroup) scroller.getChildAt(0);
            android.view.ViewParent parent = selected.getParent();
            while (parent != null && parent != content) parent = parent.getParent();
            if (parent != content) return;
            // TextView may scroll its single-line text internally, even when its outer button fits.
            Rect rect = new Rect();
            selected.getDrawingRect(rect);
            content.offsetDescendantRectToMyCoords(selected, rect);
            int viewport = scroller.getWidth() - scroller.getPaddingLeft() - scroller.getPaddingRight();
            int start = scroller.getScrollX(), target = start;
            if (rect.left < start) target = rect.left;
            else if (rect.right > start + viewport) target = rect.right - viewport;
            int max = Math.max(0, content.getWidth() - viewport);
            scroller.scrollTo(Math.max(0, Math.min(max, target)), scroller.getScrollY());
        }
    }

    private static int dp(Context context, float value) {
        return Math.round(context.getResources().getDisplayMetrics().density * value);
    }

    private static final class WorkspaceButton extends Button {
        private final LineIcon icon;
        private PhotoPrismaStyle.ToolFace circle;
        private final boolean label;

        WorkspaceButton(Context context, String name, boolean label) {
            super(context);
            this.label = label;
            icon = new LineIcon(name);
            int size = dp(context, 26);
            icon.setBounds(0, 0, size, size);
            setAllCaps(false);
            setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
            setTextSize(10.5f);
            setTextColor(TEXT);
            setGravity(Gravity.CENTER);
            setMinWidth(0);
            setMinimumWidth(0);
            setMinHeight(dp(context, 48));
            setMinimumHeight(dp(context, 48));
            setPadding(dp(context, 4), dp(context, label ? 8 : 0), dp(context, 4), dp(context, label ? 8 : 0));
            setBackgroundColor(Color.TRANSPARENT);setBackgroundTintList(null);setClipToOutline(false);setIncludeFontPadding(false);
            setStateListAnimator(null);
            if (label) {
                circle=new PhotoPrismaStyle.ToolFace(context,icon,false);circle.setBounds(0,0,dp(context,39),dp(context,39));
                setCompoundDrawables(null, circle, null, null);
                setCompoundDrawablePadding(dp(context, 4));
                setPadding(dp(context,4),dp(context,3),dp(context,4),dp(context,2));
            }else setBackground(PhotoPrismaStyle.face(context,0x6e0e1513,24,6));
        }

        @Override protected void drawableStateChanged() {
            super.drawableStateChanged();
            if (icon == null) return;
            int color = isSelected() || isPressed() ? ACCENT : TEXT;
            icon.color = color;
            if(circle!=null){circle.selected(isSelected());circle.setState(getDrawableState());}
            icon.setAlpha(isEnabled() ? (isPressed() ? 190 : 255) : 80);
            setTextColor(isEnabled() ? color : (color & 0x00ffffff) | 0x60000000);
            invalidate();
        }

        @Override protected void onDraw(Canvas canvas) {
            if (label) {
                super.onDraw(canvas);
            } else {
                int size = dp(getContext(), 24);
                int save = canvas.save();
                canvas.translate((getWidth() - size) / 2f, (getHeight() - size) / 2f);
                icon.setBounds(0, 0, size, size);
                icon.draw(canvas);
                canvas.restoreToCount(save);
            }
        }
    }

    /** Authored 24-unit line icons: one stroke, no font glyphs or bitmap assets. */
    private static final class LineIcon extends Drawable {
        private final String name;
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path path = new Path();
        private int color = TEXT;
        private int alpha = 255;

        LineIcon(String name) {
            this.name = name;
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(1.6f);
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setStrokeJoin(Paint.Join.ROUND);
        }

        @Override public void draw(Canvas canvas) {
            int save = canvas.save();
            canvas.translate(getBounds().left, getBounds().top);
            canvas.scale(getBounds().width() / 24f, getBounds().height() / 24f);
            paint.setColor(color);
            paint.setAlpha(alpha);
            path.reset();
            switch (name) {
                case "body":
                    path.moveTo(7,3);path.cubicTo(10,8,9,10,7,13);path.cubicTo(5,16,5,19,6,22);path.moveTo(17,3);path.cubicTo(14,8,15,10,17,13);path.cubicTo(19,16,19,19,18,22);stroke(canvas);line(canvas,2,11,5,11);line(canvas,19,11,22,11);break;
                case "legs":
                    path.moveTo(5,3);path.lineTo(6,21);path.lineTo(10,21);path.lineTo(12,9);path.lineTo(14,21);path.lineTo(18,21);path.lineTo(19,3);stroke(canvas);line(canvas,5,3,19,3);break;
                case "length":
                    line(canvas,6,4,6,20);line(canvas,3,7,6,4);line(canvas,9,7,6,4);line(canvas,3,17,6,20);line(canvas,9,17,6,20);path.moveTo(14,3);path.lineTo(14,12);path.lineTo(12,21);path.lineTo(18,21);path.lineTo(20,12);path.lineTo(20,3);stroke(canvas);break;
                case "back":
                    line(canvas, 19, 12, 5, 12); line(canvas, 5, 12, 12, 5); line(canvas, 5, 12, 12, 19); break;
                case "close":
                    line(canvas, 5, 5, 19, 19); line(canvas, 19, 5, 5, 19); break;
                case "check":
                    path.moveTo(4, 12); path.lineTo(9.5f, 17.5f); path.lineTo(20, 6.5f); stroke(canvas); break;
                case "undo": case "redo": {
                    if (name.equals("redo")) { canvas.translate(24, 0); canvas.scale(-1, 1); }
                    canvas.drawArc(new RectF(3.5f,3.5f,20.5f,20.5f),225,300,false,paint);
                    line(canvas,5.99f,1.89f,5.99f,5.99f);line(canvas,5.99f,5.99f,10.09f,5.99f);break;
                }
                case "fit":
                    line(canvas, 4, 9, 4, 4); line(canvas, 4, 4, 9, 4);
                    line(canvas, 15, 4, 20, 4); line(canvas, 20, 4, 20, 9);
                    line(canvas, 20, 15, 20, 20); line(canvas, 20, 20, 15, 20);
                    line(canvas, 9, 20, 4, 20); line(canvas, 4, 20, 4, 15); break;
                case "range-options":
                    line(canvas,3,6,7,6);line(canvas,11,6,21,6);canvas.drawCircle(9,6,2,paint);
                    line(canvas,3,12,13,12);line(canvas,17,12,21,12);canvas.drawCircle(15,12,2,paint);
                    line(canvas,3,18,8,18);line(canvas,12,18,21,18);canvas.drawCircle(10,18,2,paint);break;
                case "more":
                    canvas.drawCircle(5, 12, .9f, paint); canvas.drawCircle(12, 12, .9f, paint); canvas.drawCircle(19, 12, .9f, paint); break;
                case "add":
                    line(canvas, 5, 12, 19, 12); line(canvas, 12, 5, 12, 19); break;
                case "face":
                    canvas.drawOval(new RectF(5, 2.5f, 19, 21.5f), paint);
                    line(canvas, 8, 10, 9, 10); line(canvas, 15, 10, 16, 10);
                    path.moveTo(9, 16); path.quadTo(12, 18, 15, 16); stroke(canvas); break;
                case "color":
                    path.moveTo(12, 2.5f); path.cubicTo(10, 6, 5, 10.5f, 5, 14.5f);
                    path.cubicTo(5, 23, 19, 23, 19, 14.5f); path.cubicTo(19, 10.5f, 14, 6, 12, 2.5f); stroke(canvas);
                    path.reset(); path.moveTo(8.5f, 14); path.quadTo(8.5f, 17, 11, 18); stroke(canvas); break;
                case "smooth":
                    path.moveTo(4, 17); path.cubicTo(8, 18, 17, 14, 19, 4);
                    path.cubicTo(10, 2, 5, 8, 7, 14); stroke(canvas);
                    line(canvas, 4, 21, 15, 9); line(canvas, 9, 14, 9, 8); line(canvas, 9, 14, 15, 14); break;
                case "light":
                    canvas.drawCircle(12, 12, 4, paint);
                    for (int i = 0; i < 8; i++) {
                        double angle = i * Math.PI / 4;
                        line(canvas, 12 + (float)Math.cos(angle) * 7, 12 + (float)Math.sin(angle) * 7,
                                12 + (float)Math.cos(angle) * 9.5f, 12 + (float)Math.sin(angle) * 9.5f);
                    }
                    break;
                case "brightness":
                    canvas.drawCircle(12, 12, 5, paint);
                    line(canvas, 12, 7, 12, 17);
                    line(canvas, 12, 2, 12, 4); line(canvas, 12, 20, 12, 22);
                    line(canvas, 2, 12, 4, 12); line(canvas, 20, 12, 22, 12);
                    line(canvas, 5, 5, 6.5f, 6.5f); line(canvas, 17.5f, 17.5f, 19, 19);
                    line(canvas, 5, 19, 6.5f, 17.5f); line(canvas, 17.5f, 6.5f, 19, 5); break;
                case "warmth":
                    path.moveTo(9, 14); path.lineTo(9, 5); path.cubicTo(9, 1, 15, 1, 15, 5);
                    path.lineTo(15, 14); path.cubicTo(22, 20, 12, 26, 7.5f, 20);
                    path.quadTo(5.5f, 16.5f, 9, 14); stroke(canvas);
                    line(canvas, 12, 8, 12, 18); line(canvas, 18, 6, 21, 6); line(canvas, 18, 10, 20, 10); break;
                case "redness":
                    canvas.drawOval(new RectF(5, 2.5f, 19, 21.5f), paint);
                    canvas.drawCircle(8, 13.5f, 1.6f, paint); canvas.drawCircle(16, 13.5f, 1.6f, paint);
                    path.moveTo(9, 17); path.quadTo(12, 19, 15, 17); stroke(canvas); break;
                case "texture":
                    for (int y = 6; y <= 18; y += 6) {
                        path.reset(); path.moveTo(3, y); path.cubicTo(7, y - 4, 9, y + 4, 13, y);
                        path.cubicTo(17, y - 4, 19, y + 4, 22, y); stroke(canvas);
                    }
                    break;
                case "shadows":
                    path.moveTo(16, 3); path.cubicTo(3, 1, 1, 18, 11, 21);
                    path.quadTo(18, 23, 21, 16); path.cubicTo(12, 20, 8, 8, 16, 3); stroke(canvas); break;
                case "brush":
                    path.moveTo(8, 14); path.lineTo(17, 3); path.quadTo(19, 1, 21, 3);
                    path.quadTo(22, 4, 20, 6); path.lineTo(11, 17); stroke(canvas);
                    path.reset(); path.moveTo(10.5f, 17); path.cubicTo(12, 22, 5, 22, 3, 21);
                    path.cubicTo(6, 20, 3, 16, 7, 15); stroke(canvas); break;
                case "erase":
                    path.moveTo(3, 14); path.lineTo(13, 3); path.quadTo(14, 2, 15, 3);
                    path.lineTo(21, 9); path.lineTo(11, 20); path.lineTo(8, 20); path.close(); stroke(canvas);
                    line(canvas, 8, 9, 16, 16); line(canvas, 11, 20, 21, 20); break;
                case "heal":
                    canvas.save(); canvas.rotate(-45, 12, 12);
                    canvas.drawRoundRect(new RectF(3, 7, 21, 17), 4, 4, paint);
                    line(canvas, 8, 7, 8, 17); line(canvas, 16, 7, 16, 17);
                    canvas.drawCircle(11, 10, .35f, paint); canvas.drawCircle(13, 14, .35f, paint);
                    canvas.restore(); break;
                case "radial":
                    canvas.drawOval(new RectF(4, 6, 20, 18), paint);
                    line(canvas, 12, 3, 12, 7); line(canvas, 12, 17, 12, 21);
                    line(canvas, 2, 12, 6, 12); line(canvas, 18, 12, 22, 12); break;
                case "selection-circle":
                    canvas.drawCircle(12,12,8,paint);break;
                case "selection-rectangle":
                    canvas.drawRect(4,4,20,20,paint);break;
                case "linear":
                    line(canvas, 4, 4, 20, 4); line(canvas, 4, 20, 20, 20);
                    line(canvas, 12, 7, 12, 17); canvas.drawCircle(12, 12, 2.5f, paint); break;
                case "clone":
                    canvas.drawCircle(8, 8, 4, paint); canvas.drawCircle(16, 16, 4, paint);
                    line(canvas, 9, 14, 14, 9); break;
                case "compare":
                    canvas.drawRoundRect(new RectF(3, 4, 21, 20), 2, 2, paint);
                    line(canvas, 12, 2, 12, 22); line(canvas, 6, 12, 9, 12); line(canvas, 15, 9, 18, 9); line(canvas, 15, 15, 18, 15); break;
                case "teeth":
                    path.moveTo(6,3);path.cubicTo(2,5,4,12,6,18);path.quadTo(8,24,10,16);path.quadTo(12,11,14,16);path.quadTo(16,24,18,18);path.cubicTo(20,12,22,5,18,3);path.quadTo(15,1,12,4);path.quadTo(9,1,6,3);stroke(canvas);line(canvas,10,7,14,7);break;
                case "under-eye":
                    path.moveTo(3,9);path.quadTo(12,0,21,9);path.quadTo(12,18,3,9);stroke(canvas);canvas.drawCircle(12,9,2,paint);canvas.drawArc(new RectF(4,8,20,21),15,150,false,paint);break;
                case "eye-clean":
                    path.moveTo(2,12);path.quadTo(12,-1,22,12);path.quadTo(12,25,2,12);stroke(canvas);canvas.drawCircle(12,12,3,paint);line(canvas,19,2,19,7);line(canvas,16.5f,4.5f,21.5f,4.5f);break;
                case "skin-even":
                    canvas.drawOval(new RectF(5,2,19,22),paint);line(canvas,8,10,16,10);line(canvas,8,14,16,14);line(canvas,10,18,14,18);break;
                case "shine-control":
                    path.moveTo(10,3);path.cubicTo(9,7,4,11,4,15);path.cubicTo(4,23,17,23,17,15);path.cubicTo(17,11,12,7,10,3);stroke(canvas);line(canvas,15,5,22,5);break;
                case "eye":
                    path.moveTo(2, 12); path.quadTo(12, -1, 22, 12); path.quadTo(12, 25, 2, 12); stroke(canvas);
                    canvas.drawCircle(12, 12, 3, paint); break;
                case "reset":
                    AppIcon.drawRefresh(canvas,paint);break;
                case "mask":
                    canvas.drawCircle(12, 12, 8, paint);
                    for (int x = 6; x <= 15; x += 3) line(canvas, x, 7, x, 17);
                    break;
                default:
                    canvas.drawCircle(12, 12, 8, paint);
                    line(canvas, 8, 12, 16, 12);
            }
            canvas.restoreToCount(save);
        }

        private void line(Canvas canvas, float x1, float y1, float x2, float y2) {
            canvas.drawLine(x1, y1, x2, y2, paint);
        }
        private void stroke(Canvas canvas) { canvas.drawPath(path, paint); }
        @Override public void setAlpha(int alpha) { this.alpha = alpha; invalidateSelf(); }
        @Override public void setColorFilter(ColorFilter filter) { paint.setColorFilter(filter); invalidateSelf(); }
        @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
    }
}
