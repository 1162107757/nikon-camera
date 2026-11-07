package cc.huevia.ui;
import android.content.Context;
import android.graphics.*;
import android.graphics.drawable.Drawable;
import android.widget.CheckBox;

/** Branded circular mark retaining CompoundButton's checked, keyboard and accessibility behavior. */
final class PhotoChoiceCheck extends CheckBox {
    private final UiPalette colors;
    PhotoChoiceCheck(Context context){super(context);colors=new UiPalette(context);setButtonTintList(null);setButtonDrawable(new Mark());setPadding(dp(12),0,dp(12),0);setMinHeight(dp(48));}
    private int dp(float value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private final class Mark extends Drawable {
        private final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG);private boolean checked,enabled=true;
        @Override public boolean isStateful(){return true;}
        @Override protected boolean onStateChange(int[] states){checked=false;enabled=false;for(int state:states){if(state==android.R.attr.state_checked)checked=true;if(state==android.R.attr.state_enabled)enabled=true;}invalidateSelf();return true;}
        @Override public void draw(Canvas canvas){int saved=canvas.save();canvas.translate(getBounds().left,getBounds().top);canvas.scale(getBounds().width()/22f,getBounds().height()/22f);ink.setColor(checked?colors.primaryContainer:colors.secondary);ink.setAlpha(enabled?255:110);ink.setStyle(checked?Paint.Style.FILL:Paint.Style.STROKE);ink.setStrokeWidth(1.5f);canvas.drawCircle(11,11,9.5f,ink);if(checked){ink.setStyle(Paint.Style.STROKE);ink.setStrokeWidth(1.8f);ink.setColor(colors.onPrimaryContainer);ink.setAlpha(enabled?255:110);ink.setStrokeCap(Paint.Cap.ROUND);ink.setStrokeJoin(Paint.Join.ROUND);Path path=new Path();path.moveTo(6.5f,11);path.lineTo(9.5f,14);path.lineTo(15.8f,7.5f);canvas.drawPath(path,ink);}canvas.restoreToCount(saved);}
        @Override public int getIntrinsicWidth(){return dp(22);}@Override public int getIntrinsicHeight(){return dp(22);}
        @Override public void setAlpha(int alpha){ink.setAlpha(alpha);invalidateSelf();}@Override public void setColorFilter(ColorFilter filter){ink.setColorFilter(filter);invalidateSelf();}@Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
}
