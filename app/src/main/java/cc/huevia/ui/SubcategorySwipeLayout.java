package cc.huevia.ui;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.view.animation.PathInterpolator;
import android.widget.AbsSeekBar;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import java.util.function.BooleanSupplier;
import java.util.function.IntConsumer;
import java.util.function.IntSupplier;
import java.util.function.Supplier;

/** Source tabs stay fixed while their content follows a drag and settles into its new page. */
public final class SubcategorySwipeLayout extends LinearLayout {
    private final IntSupplier selected;
    private final IntConsumer choose;
    private final BooleanSupplier enabled;
    private final int count,slop;
    private final float density;
    private final Paint bitmapPaint=new Paint(Paint.FILTER_BITMAP_FLAG);
    private float downX,downY,dragOffset,dragAlpha=1;
    private int initial;
    private boolean tracking,blocked,captured,snapshotting;
    private View motionAnchor;
    private Bitmap dragFrame;
    private ValueAnimator rebound;
    private Motion motion;
    private static final PathInterpolator EASE=new PathInterpolator(.22f,1f,.36f,1f);

    public SubcategorySwipeLayout(Context context,IntSupplier selected,int count,IntConsumer choose,BooleanSupplier enabled){
        super(context);this.selected=selected;this.count=count;this.choose=choose;this.enabled=enabled;
        density=getResources().getDisplayMetrics().density;slop=ViewConfiguration.get(context).getScaledTouchSlop();setOrientation(VERTICAL);
    }
    public void setMotionAnchor(View view){motionAnchor=view;}
    private int motionTop(){
        if(motionAnchor==null||motionAnchor.getParent()==null)return 0;
        Rect bounds=new Rect(0,0,motionAnchor.getWidth(),motionAnchor.getHeight());
        offsetDescendantRectToMyCoords(motionAnchor,bounds);return Math.max(0,Math.min(getHeight(),bounds.bottom));
    }
    @Override protected void dispatchDraw(Canvas canvas){
        if(snapshotting||motion==null&&dragOffset==0&&dragFrame==null){super.dispatchDraw(canvas);return;}
        int top=motionTop(),save=canvas.save();canvas.clipRect(0,0,getWidth(),top);super.dispatchDraw(canvas);canvas.restoreToCount(save);
        save=canvas.save();canvas.clipRect(0,top,getWidth(),getHeight());
        if(motion!=null){
            float width=getWidth(),out=motion.startOffset*(1-motion.progress)-motion.direction*width*motion.progress;
            drawFrame(canvas,motion.frame,out,top,1);
            canvas.translate(motion.direction*width*(1-motion.progress)+motion.startOffset*(1-motion.progress),0);super.dispatchDraw(canvas);
        }else if(dragFrame!=null){
            super.dispatchDraw(canvas);drawFrame(canvas,dragFrame,dragOffset,top,dragAlpha);
        }else{canvas.translate(dragOffset,0);super.dispatchDraw(canvas);}
        canvas.restoreToCount(save);
    }
    private void drawFrame(Canvas canvas,Bitmap frame,float x,int top,float alpha){
        if(frame==null||frame.isRecycled())return;
        bitmapPaint.setAlpha(Math.round(255*alpha));canvas.drawBitmap(frame,null,new android.graphics.RectF(x,top,x+getWidth(),getHeight()),bitmapPaint);bitmapPaint.setAlpha(255);
    }
    private Bitmap snapshot(boolean atRest){
        int top=motionTop(),width=getWidth(),height=getHeight()-top;if(width<=0||height<=0)return null;
        float scale=Math.min(1f,(float)Math.sqrt(2000000d/((double)width*height)));
        Bitmap frame=null;
        try{
            frame=Bitmap.createBitmap(Math.max(1,(int)(width*scale)),Math.max(1,(int)(height*scale)),Bitmap.Config.ARGB_8888);
            Canvas canvas=new Canvas(frame);canvas.scale(scale,scale);canvas.translate(0,-top);snapshotting=atRest;draw(canvas);return frame;
        }catch(OutOfMemoryError failure){if(frame!=null)frame.recycle();return null;}
        finally{snapshotting=false;}
    }
    /** Both click and swipe handlers keep their existing state mutation and data-loading path. */
    public static void changeSource(View before,int from,int to,Runnable change,Supplier<? extends View> after){
        if(!(before instanceof SubcategorySwipeLayout)||from==to||!ValueAnimator.areAnimatorsEnabled()){if(before instanceof SubcategorySwipeLayout)((SubcategorySwipeLayout)before).clearMotion();change.run();return;}
        SubcategorySwipeLayout old=(SubcategorySwipeLayout)before;
        boolean composite=old.motion!=null||old.dragFrame!=null;float start=composite?0:old.dragOffset;
        Bitmap frame=old.snapshot(!composite);
        old.clearMotion();
        try{change.run();}catch(RuntimeException|Error failure){if(frame!=null)frame.recycle();throw failure;}
        View next=after.get();
        if(frame==null||!(next instanceof SubcategorySwipeLayout)){if(frame!=null)frame.recycle();return;}
        new Motion(frame,Integer.signum(to-from),start,to,after).prepare((SubcategorySwipeLayout)next);
    }
    @Override public boolean onInterceptTouchEvent(MotionEvent event){
        int action=event.getActionMasked();
        if(action==MotionEvent.ACTION_DOWN){begin(event);return movingBody(event);}
        if(action==MotionEvent.ACTION_POINTER_DOWN||event.getPointerCount()!=1){tracking=false;return false;}
        if(action==MotionEvent.ACTION_MOVE&&canCapture(event))capture();
        if(action==MotionEvent.ACTION_CANCEL){tracking=false;captured=false;returnHome();}
        return captured;
    }
    @Override public boolean onTouchEvent(MotionEvent event){
        int action=event.getActionMasked();
        if(action==MotionEvent.ACTION_DOWN){begin(event);return movingBody(event)||tracking&&!blocked;}
        if(action==MotionEvent.ACTION_POINTER_DOWN||event.getPointerCount()!=1){tracking=false;returnHome();return captured;}
        if(action==MotionEvent.ACTION_MOVE){
            if(canCapture(event))capture();
            if(captured&&tracking&&ValueAnimator.areAnimatorsEnabled()){
                float dx=event.getX()-downX;int next=initial+(dx<0?1:-1);
                dragOffset=next>=0&&next<count?Math.copySign(Math.min(Math.abs(dx)*.65f,getWidth()*.35f),dx):0;invalidate();
            }
            return captured||tracking&&!blocked;
        }
        if(action==MotionEvent.ACTION_UP){
            float dx=event.getX()-downX,dy=event.getY()-downY;int next=initial+(dx<0?1:-1);
            float threshold=Math.max(48*density,Math.min(80*density,getWidth()*.12f));
            boolean change=tracking&&!blocked&&enabled.getAsBoolean()&&selected.getAsInt()==initial
                    &&Math.abs(dx)>=threshold&&Math.abs(dx)>Math.abs(dy)*1.4f&&next>=0&&next<count;
            boolean handled=captured||tracking&&!blocked;tracking=false;captured=false;
            if(change){choose.accept(next);if(dragOffset!=0&&motion==null)returnHome();}else returnHome();
            return handled;
        }
        if(action==MotionEvent.ACTION_CANCEL){boolean handled=captured;tracking=false;captured=false;returnHome();return handled;}
        return captured;
    }
    // Canvas movement does not move child hit rectangles. Own body taps until it settles,
    // while leaving the pinned source controls available for rapid reverse clicks.
    private boolean movingBody(MotionEvent event){return (motion!=null||rebound!=null)&&event.getY()>=motionTop();}
    private void capture(){
        if(captured)return;captured=true;stopRebound();
        if(motion!=null){dragFrame=snapshot(false);motion.finish();dragOffset=0;dragAlpha=1;}
        if(getParent()!=null)getParent().requestDisallowInterceptTouchEvent(true);
    }
    private void begin(MotionEvent event){
        downX=event.getX();downY=event.getY();initial=selected.getAsInt();captured=false;
        tracking=enabled.getAsBoolean()&&count>1;blocked=childOwnsHorizontalGesture(this,downX,downY);
    }
    private boolean canCapture(MotionEvent event){
        if(!tracking||blocked||!enabled.getAsBoolean())return false;
        float dx=event.getX()-downX,dy=event.getY()-downY;
        if(Math.abs(dy)>slop*2&&Math.abs(dy)>=Math.abs(dx)){tracking=false;return false;}
        int next=initial+(dx<0?1:-1);
        return next>=0&&next<count&&Math.abs(dx)>slop*2&&Math.abs(dx)>Math.abs(dy)*1.4f;
    }
    private void returnHome(){
        stopRebound();if(dragOffset==0&&dragFrame==null)return;
        if(!ValueAnimator.areAnimatorsEnabled()){clearDrag();return;}
        float start=dragOffset;rebound=ValueAnimator.ofFloat(0,1);rebound.setDuration(170);rebound.setInterpolator(EASE);
        rebound.addUpdateListener(a->{if(!ValueAnimator.areAnimatorsEnabled()){clearDrag();return;}float p=(Float)a.getAnimatedValue();dragOffset=start*(1-p);dragAlpha=1-p;invalidate();});
        rebound.addListener(new AnimatorListenerAdapter(){@Override public void onAnimationEnd(Animator a){if(rebound==a){rebound=null;clearDrag();}}});rebound.start();
    }
    private void stopRebound(){if(rebound!=null){ValueAnimator value=rebound;rebound=null;value.cancel();}}
    private void clearDrag(){dragOffset=0;dragAlpha=1;if(dragFrame!=null){dragFrame.recycle();dragFrame=null;}invalidate();}
    private void clearMotion(){stopRebound();if(motion!=null)motion.finish();clearDrag();}
    private boolean childOwnsHorizontalGesture(View view,float x,float y){
        // Padded vertical lists may report horizontal ranges without owning horizontal drags.
        if(view instanceof AbsSeekBar||view instanceof EditText||view instanceof HorizontalScrollView)return true;
        if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;
            for(int i=group.getChildCount()-1;i>=0;i--){View child=group.getChildAt(i);if(child.getVisibility()!=VISIBLE)continue;
                float childX=x+group.getScrollX()-child.getLeft(),childY=y+group.getScrollY()-child.getTop();
                if(childX>=0&&childX<child.getWidth()&&childY>=0&&childY<child.getHeight())return childOwnsHorizontalGesture(child,childX,childY);
            }
        }
        return false;
    }
    @Override protected void onDetachedFromWindow(){
        tracking=false;captured=false;stopRebound();clearDrag();
        if(motion!=null){Motion value=motion;motion=null;value.bound=null;}super.onDetachedFromWindow();
    }
    private static final class Motion {
        final Bitmap frame;final int direction,selection;final float startOffset;
        final Supplier<? extends View> target;final Handler handler=new Handler(Looper.getMainLooper());
        SubcategorySwipeLayout bound;ValueAnimator animator;float progress;boolean finished;int width,height;
        ViewTreeObserver observer;ViewTreeObserver.OnPreDrawListener listener;
        final Runnable deadline=()->finish();
        Motion(Bitmap frame,int direction,float start,int selection,Supplier<? extends View> target){this.frame=frame;this.direction=direction;startOffset=start;this.selection=selection;this.target=target;}
        void prepare(SubcategorySwipeLayout view){
            bound=view;view.motion=this;observer=view.getViewTreeObserver();
            listener=()->{removeListener();start();return true;};observer.addOnPreDrawListener(listener);handler.postDelayed(deadline,800);view.invalidate();
        }
        void removeListener(){if(observer!=null&&observer.isAlive()&&listener!=null)observer.removeOnPreDrawListener(listener);observer=null;listener=null;}
        boolean bind(){
            View value=target.get();if(!(value instanceof SubcategorySwipeLayout)||!value.isAttachedToWindow())return false;
            SubcategorySwipeLayout next=(SubcategorySwipeLayout)value;
            if(next.selected.getAsInt()!=selection||!next.enabled.getAsBoolean()||next.getWidth()<=0||next.getHeight()<=next.motionTop())return false;
            if(width>0&&(next.getWidth()!=width||next.getHeight()!=height))return false;
            if(bound!=next){if(bound!=null){bound.motion=null;bound.invalidate();}bound=next;next.motion=this;}
            return true;
        }
        void start(){
            handler.removeCallbacks(deadline);
            if(finished||!ValueAnimator.areAnimatorsEnabled()||!bind()){finish();return;}
            width=bound.getWidth();height=bound.getHeight();
            animator=ValueAnimator.ofFloat(0,1);animator.setDuration(240);animator.setInterpolator(EASE);
            animator.addUpdateListener(a->{if(!ValueAnimator.areAnimatorsEnabled()||!bind()){finish();return;}progress=(Float)a.getAnimatedValue();bound.invalidate();});
            animator.addListener(new AnimatorListenerAdapter(){@Override public void onAnimationEnd(Animator a){finish();}});animator.start();
        }
        void finish(){
            if(finished)return;finished=true;handler.removeCallbacks(deadline);removeListener();
            if(animator!=null){ValueAnimator value=animator;animator=null;value.cancel();}
            if(bound!=null){bound.motion=null;bound.invalidate();bound=null;}if(!frame.isRecycled())frame.recycle();
        }
    }
}
