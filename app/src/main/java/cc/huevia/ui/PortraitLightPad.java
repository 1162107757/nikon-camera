package cc.huevia.ui;
import android.content.Context;
import android.graphics.*;
import android.view.*;

/** A source-position control. The photo receives only the saved lighting adjustment. */
public final class PortraitLightPad extends View {
    public interface Listener{void start();void change(int x,int y);void end(boolean cancel);}
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);private final Listener listener;private int x,y;private boolean dragging;
    public PortraitLightPad(Context context,Listener listener){super(context);this.listener=listener;setTag("portrait-light-pad");setFocusable(true);setContentDescription("拖动光点调整补光方向，也可使用左右和上下精确调节");}
    public void position(int x,int y){this.x=x;this.y=y;invalidate();}
    @Override protected void onDraw(Canvas c){super.onDraw(c);float radius=Math.max(1,Math.min(getWidth(),getHeight())*.42f),cx=getWidth()/2f,cy=getHeight()/2f,distance=(float)Math.max(1,Math.hypot(x,y)/100.0),px=cx+x/distance/100f*radius,py=cy+y/distance/100f*radius;paint.setShader(new RadialGradient(px,py,radius*1.8f,new int[]{0xffb6a28e,0xff51483f,0xff24211e},null,Shader.TileMode.CLAMP));c.drawCircle(cx,cy,radius,paint);paint.setShader(null);paint.setColor(0xff6e5c4f);paint.setStrokeWidth(getResources().getDisplayMetrics().density);paint.setStyle(Paint.Style.STROKE);c.drawCircle(cx,cy,radius,paint);c.drawLine(cx-radius,cy,cx+radius,cy,paint);c.drawLine(cx,cy-radius,cx,cy+radius,paint);paint.setStyle(Paint.Style.FILL);paint.setColor(dragging?0x44ffe335:0x22ffe335);c.drawCircle(px,py,17*getResources().getDisplayMetrics().density,paint);paint.setColor(PhotoPrismaStyle.YELLOW);c.drawCircle(px,py,6*getResources().getDisplayMetrics().density,paint);}
    @Override public boolean onTouchEvent(MotionEvent event){if(!isEnabled())return false;int action=event.getActionMasked();if(action==MotionEvent.ACTION_DOWN){dragging=true;getParent().requestDisallowInterceptTouchEvent(true);listener.start();}if(event.getPointerCount()>1||action==MotionEvent.ACTION_CANCEL){if(dragging)listener.end(true);dragging=false;getParent().requestDisallowInterceptTouchEvent(false);invalidate();return true;}if(dragging&&(action==MotionEvent.ACTION_MOVE||action==MotionEvent.ACTION_DOWN)){float radius=Math.max(1,Math.min(getWidth(),getHeight())*.42f);x=Math.round(Math.max(-100,Math.min(100,(event.getX()-getWidth()/2f)/radius*100)));y=Math.round(Math.max(-100,Math.min(100,(event.getY()-getHeight()/2f)/radius*100)));double magnitude=Math.hypot(x,y);if(magnitude>100){x=(int)Math.round(x*100/magnitude);y=(int)Math.round(y*100/magnitude);}listener.change(x,y);invalidate();}if(action==MotionEvent.ACTION_UP&&dragging){dragging=false;listener.end(false);getParent().requestDisallowInterceptTouchEvent(false);performClick();invalidate();}return true;}
    @Override public boolean performClick(){return super.performClick();}
}
