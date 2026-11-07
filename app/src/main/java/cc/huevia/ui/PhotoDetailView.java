package cc.huevia.ui;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.GestureDetector;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import cc.huevia.album.PhotoDetailSource;

/** Physical-pixel canvas. No ImageView/resource density matrix participates in 100% rendering. */
public final class PhotoDetailView extends View implements AutoCloseable {
    public interface Listener {
        void state(boolean loading,String message,double scale,boolean fitting,int mode,boolean failed);
        void invalidated();
    }
    private static final int PAN_LEFT=0x01020001,PAN_RIGHT=0x01020002,PAN_UP=0x01020003,PAN_DOWN=0x01020004;
    private final PhotoDetailSource source;private final Listener listener;
    private final PhotoDetailViewport viewport=new PhotoDetailViewport();
    private final Paint imagePaint=new Paint(),miniPaint=new Paint(Paint.ANTI_ALIAS_FLAG),linePaint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF mini=new RectF(),locator=new RectF();
    private final Path miniClip=new Path();
    private final RectF floatingControls=new RectF();
    private final GestureDetector gestures;private final ScaleGestureDetector scales;
    private PhotoDetailSource.Frame frame;private int mode=PhotoDetailSource.CURRENT;
    private boolean closed,paused,loading,failed,miniDrag;private long revision;
    private boolean requestInFlight,frameQueued,submitScheduled;private long requestSerial;
    private final Runnable submit=this::submitFrame;
    private final Runnable validity=new Runnable(){public void run(){if(closed||paused)return;if(!source.valid()){listener.invalidated();return;}postDelayed(this,750);}};
    public PhotoDetailView(Context context,PhotoDetailSource source,Listener listener){
        super(context);this.source=source;this.listener=listener;setBackgroundColor(0xff0a0908);setFocusable(true);setClickable(true);
        setContentDescription("照片细节。双击切换适应与100%，双指缩放，放大后拖动查看。");
        gestures=new GestureDetector(context,new GestureDetector.SimpleOnGestureListener(){
            @Override public boolean onDown(MotionEvent e){return true;}
            @Override public boolean onDoubleTap(MotionEvent e){
                if(viewport.imageWidth<1)return true;
                if(viewport.fitting)viewport.zoom(1,e.getX(),e.getY());else viewport.fitImage();changed();return true;
            }
            @Override public boolean onScroll(MotionEvent first,MotionEvent now,float dx,float dy){if(!scales.isInProgress()){viewport.move(-dx,-dy);changed();}return true;}
            @Override public boolean onSingleTapConfirmed(MotionEvent e){performClick();return true;}
        });
        scales=new ScaleGestureDetector(context,new ScaleGestureDetector.SimpleOnScaleGestureListener(){
            @Override public boolean onScale(ScaleGestureDetector detector){viewport.zoom(viewport.scale*detector.getScaleFactor(),detector.getFocusX(),detector.getFocusY());changed();return true;}
        });
        linePaint.setColor(0xffffe335);linePaint.setStrokeWidth(dp(1.5f));linePaint.setStyle(Paint.Style.STROKE);
        miniPaint.setFilterBitmap(true);post(validity);
    }
    public int selectedMode(){return mode;}
    public void mode(int next){if(next==PhotoDetailSource.BEFORE&&!source.canCompare()||mode==next)return;mode=next;cancelRequests();failed=false;changed();}
    public void fit(){viewport.fitImage();changed();}
    public void zoom(double scale){viewport.zoom(scale,getWidth()/2.0,getHeight()/2.0);changed();}
    public void retry(){failed=false;changed();}
    public void pause(){if(closed||paused)return;paused=true;revision++;cancelRequests();removeCallbacks(validity);frame=null;source.releaseMemory();invalidate();}
    public void resume(){if(closed||!paused)return;paused=false;post(validity);changed();}
    public double scale(){return viewport.scale;}
    public boolean isFitting(){return viewport.fitting;}
    public int contentWidth(){return viewport.imageWidth;}
    public int contentHeight(){return viewport.imageHeight;}
    public boolean hasFullPixels(){return !loading&&!failed&&frame!=null&&!frame.provisional&&frame.mode==mode;}
    /** The locator is chrome only; its box never changes the physical-pixel viewport. */
    public boolean isLocatorVisible(){return frame!=null&&viewport.scale>viewport.fit()+.0001;}
    public RectF locatorBounds(){return isLocatorVisible()?new RectF(locator):new RectF();}
    public RectF visiblePhotoBounds(){if(viewport.imageWidth<1)return new RectF();return new RectF((float)Math.max(0,viewport.left()),(float)Math.max(0,viewport.top()),(float)Math.min(getWidth(),viewport.left()+viewport.imageWidth*viewport.scale),(float)Math.min(getHeight(),viewport.top()+viewport.imageHeight*viewport.scale));}
    public void setFloatingControls(RectF bounds){if(!floatingControls.equals(bounds)){floatingControls.set(bounds);invalidate();}}
    private void changed(){
        if(closed||paused)return;revision++;loading=true;failed=false;
        frameQueued=true;
        notifyState(frame==null?"载入中…":"细化中…");
        invalidate();scheduleFrame(false);
    }
    private void scheduleFrame(boolean immediate){
        if(closed||paused||requestInFlight||!frameQueued)return;
        if(immediate){removeCallbacks(submit);submitScheduled=false;submitFrame();}
        else if(!submitScheduled){submitScheduled=true;postOnAnimation(submit);}
    }
    private void cancelRequests(){
        requestSerial++;requestInFlight=false;frameQueued=false;submitScheduled=false;
        removeCallbacks(submit);source.cancelFrames();
    }
    private void submitFrame(){
        submitScheduled=false;
        if(closed||paused||requestInFlight||!frameQueued||getWidth()<1||getHeight()<1)return;
        if(!source.valid()){listener.invalidated();return;}
        final long token=revision,request=++requestSerial;final int requestedMode=mode;
        frameQueued=false;requestInFlight=true;
        source.frame(mode,getWidth(),getHeight(),viewport.fitting?0:viewport.scale,viewport.imageWidth<1?.5:viewport.centerX/viewport.imageWidth,viewport.imageHeight<1?.5:viewport.centerY/viewport.imageHeight,new PhotoDetailSource.Callback(){
            private boolean active(){return !closed&&!paused&&request==requestSerial&&requestedMode==mode;}
            public void preview(PhotoDetailSource.Frame result){
                if(!active())return;
                if(frame==null||frame.provisional||frame.mode!=result.mode)frame=result;
                viewport.image(result.width,result.height);loading=true;failed=false;
                notifyState("细化中…");invalidate();
            }
            public void loaded(PhotoDetailSource.Frame result){
                if(!active())return;
                requestInFlight=false;frame=result;viewport.image(result.width,result.height);failed=false;
                // A same-mode intermediate frame improves newly exposed areas while moving.
                // Only the latest viewport may certify its scale and complete pixel coverage.
                loading=token!=revision;frameQueued=loading;
                notifyState(loading?"细化中…":viewport.fitting?"点按100%查看真实像素":Math.abs(viewport.scale-1)<.001?"像素1:1 · 拖动查看细节":viewport.scale>1?"放大查看，不增加细节":"拖动查看细节");invalidate();
                scheduleFrame(false);
            }
            public void failed(String message){
                if(!active())return;requestInFlight=false;
                if(token!=revision){loading=true;failed=false;frameQueued=true;notifyState("细化中…");scheduleFrame(false);}
                else{loading=false;failed=true;notifyState(message);}
                invalidate();
            }
            public void invalidated(){
                if(!active())return;requestInFlight=false;frameQueued=false;listener.invalidated();
            }
        });
    }
    private void notifyState(String message){
        if((loading||failed)&&frame!=null&&frame.mode!=mode)message+=" · 仍显示"+(frame.mode==PhotoDetailSource.BEFORE?"调色前":"当前效果");
        listener.state(loading,message,viewport.scale,viewport.fitting,mode,failed);
    }
    @Override protected void onSizeChanged(int width,int height,int oldWidth,int oldHeight){viewport.canvas(width,height);changed();}
    @Override protected void onDraw(Canvas canvas){
        super.onDraw(canvas);mini.setEmpty();locator.setEmpty();PhotoDetailSource.Frame shown=frame;if(shown==null)return;
        double scale=viewport.scale,left=viewport.left(),top=viewport.top();
        if(Math.abs(scale-1)<.00001||Math.abs(scale-2)<.00001){left=Math.round(left);top=Math.round(top);}
        canvas.save();canvas.translate((float)left,(float)top);canvas.scale((float)scale,(float)scale);
        imagePaint.setFilterBitmap(true);canvas.drawBitmap(shown.overview,null,new RectF(0,0,shown.width,shown.height),imagePaint);
        imagePaint.setFilterBitmap(scale<.99999);
        for(PhotoDetailSource.Tile tile:shown.tiles)canvas.drawBitmap(tile.bitmap,null,new RectF(tile.bounds),imagePaint);
        canvas.restore();
        if(isLocatorVisible()){
            // Fixed compact shell; fit the actual image inside rather than stretching its aspect.
            float width=Math.min(dp(76),getWidth()-dp(24)),height=Math.min(dp(98),getHeight()-dp(88));
            if(width<=dp(8)||height<=dp(8))return;
            locator.set(getWidth()-dp(12)-width,getHeight()-dp(76)-height,getWidth()-dp(12),getHeight()-dp(76));
            if(RectF.intersects(locator,floatingControls))locator.offset(0,floatingControls.top-dp(9)-locator.bottom);
            miniPaint.setStyle(Paint.Style.FILL);miniPaint.setColor(0xc7201e1c);canvas.drawRoundRect(locator,dp(14),dp(14),miniPaint);
            miniPaint.setStyle(Paint.Style.STROKE);miniPaint.setStrokeWidth(Math.max(1,dp(.5f)));miniPaint.setColor(0x45ffffff);canvas.drawRoundRect(locator,dp(14),dp(14),miniPaint);miniPaint.setStyle(Paint.Style.FILL);
            RectF inside=new RectF(locator);inside.inset(dp(4),dp(4));
            float miniScale=Math.min(inside.width()/shown.width,inside.height()/shown.height),w=shown.width*miniScale,h=shown.height*miniScale;
            mini.set(inside.centerX()-w/2,inside.centerY()-h/2,inside.centerX()+w/2,inside.centerY()+h/2);
            int saved=canvas.save();miniClip.reset();miniClip.addRoundRect(inside,dp(10),dp(10),Path.Direction.CW);canvas.clipPath(miniClip);
            miniPaint.setColor(0xff0a0908);canvas.drawRect(inside,miniPaint);canvas.drawBitmap(shown.overview,null,mini,miniPaint);
            float l=(float)Math.max(0,viewport.centerX-getWidth()/(2*scale)),t=(float)Math.max(0,viewport.centerY-getHeight()/(2*scale));
            float r=(float)Math.min(shown.width,viewport.centerX+getWidth()/(2*scale)),b=(float)Math.min(shown.height,viewport.centerY+getHeight()/(2*scale));
            RectF visible=new RectF(mini.left+l*miniScale,mini.top+t*miniScale,mini.left+r*miniScale,mini.top+b*miniScale);
            // Outside dimming makes the viewport readable on both bright and dark photographs.
            miniPaint.setColor(0x57000000);canvas.drawRect(mini.left,mini.top,mini.right,visible.top,miniPaint);canvas.drawRect(mini.left,visible.bottom,mini.right,mini.bottom,miniPaint);
            canvas.drawRect(mini.left,visible.top,visible.left,visible.bottom,miniPaint);canvas.drawRect(visible.right,visible.top,mini.right,visible.bottom,miniPaint);
            canvas.drawRoundRect(visible,dp(4),dp(4),linePaint);canvas.restoreToCount(saved);
        }
    }
    @Override public boolean onTouchEvent(MotionEvent event){
        if(closed||paused)return false;
        if(event.getActionMasked()==MotionEvent.ACTION_DOWN){miniDrag=isLocatorVisible()&&!mini.isEmpty()&&locator.contains(event.getX(),event.getY());}
        if(miniDrag){
            if(event.getActionMasked()!=MotionEvent.ACTION_CANCEL&&event.getPointerCount()==1&&!mini.isEmpty()){viewport.center((event.getX()-mini.left)/mini.width()*viewport.imageWidth,(event.getY()-mini.top)/mini.height()*viewport.imageHeight);changed();}
            if(event.getActionMasked()==MotionEvent.ACTION_UP||event.getActionMasked()==MotionEvent.ACTION_CANCEL){miniDrag=false;scheduleFrame(true);performClick();}return true;
        }
        scales.onTouchEvent(event);gestures.onTouchEvent(event);
        if(event.getActionMasked()==MotionEvent.ACTION_UP||event.getActionMasked()==MotionEvent.ACTION_CANCEL)scheduleFrame(true);
        return true;
    }
    @Override public boolean performClick(){return super.performClick();}
    @Override public boolean onKeyDown(int keyCode,KeyEvent event){
        switch(keyCode){case KeyEvent.KEYCODE_DPAD_LEFT:pan(-1,0);return true;case KeyEvent.KEYCODE_DPAD_RIGHT:pan(1,0);return true;case KeyEvent.KEYCODE_DPAD_UP:pan(0,-1);return true;case KeyEvent.KEYCODE_DPAD_DOWN:pan(0,1);return true;case KeyEvent.KEYCODE_0:case KeyEvent.KEYCODE_MOVE_HOME:fit();return true;case KeyEvent.KEYCODE_1:zoom(1);return true;case KeyEvent.KEYCODE_2:zoom(2);return true;case KeyEvent.KEYCODE_PLUS:case KeyEvent.KEYCODE_EQUALS:zoom(viewport.scale*1.25);return true;case KeyEvent.KEYCODE_MINUS:zoom(viewport.scale/1.25);return true;case KeyEvent.KEYCODE_ENTER:if(viewport.fitting)zoom(1);else fit();return true;default:return super.onKeyDown(keyCode,event);}
    }
    private void pan(int dx,int dy){viewport.move(-dx*getWidth()*.25,-dy*getHeight()*.25);changed();}
    @Override public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info){
        super.onInitializeAccessibilityNodeInfo(info);info.setClassName("android.widget.ImageView");
        info.setContentDescription("照片真实细节，"+Math.round(viewport.scale*100)+"%，"+(mode==PhotoDetailSource.BEFORE?"调色前":"当前效果")+(loading?"，正在载入":failed?"，载入失败":""));
        info.addAction(new AccessibilityNodeInfo.AccessibilityAction(PAN_LEFT,"查看左侧"));info.addAction(new AccessibilityNodeInfo.AccessibilityAction(PAN_RIGHT,"查看右侧"));
        info.addAction(new AccessibilityNodeInfo.AccessibilityAction(PAN_UP,"查看上方"));info.addAction(new AccessibilityNodeInfo.AccessibilityAction(PAN_DOWN,"查看下方"));
    }
    @Override public boolean performAccessibilityAction(int action,android.os.Bundle args){switch(action){case PAN_LEFT:pan(-1,0);return true;case PAN_RIGHT:pan(1,0);return true;case PAN_UP:pan(0,-1);return true;case PAN_DOWN:pan(0,1);return true;default:return super.performAccessibilityAction(action,args);}}
    private float dp(float value){return value*getResources().getDisplayMetrics().density;}
    @Override public void close(){if(closed)return;closed=true;revision++;cancelRequests();removeCallbacks(validity);frame=null;mini.setEmpty();locator.setEmpty();invalidate();}
}
