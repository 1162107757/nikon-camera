package cc.huevia.ui;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.*;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.SeekBar;

/** Materials from the user-approved Prisma editor prototype; confined to photo editing. */
final class PhotoPrismaStyle {
    static final int YELLOW=0xffffe335,WHITE=0xfff4f5f7,MUTED=0xffc8cdca,INK=0xff191e17;
    /** Quiet card selection: the checkmark carries certainty; the frame stays secondary. */
    static final int SELECTION_FRAME=0xffbbb9a1,SELECTION_LABEL=0xffffffff,SELECTION_FILL=0x18121c17;
    private PhotoPrismaStyle(){}
    static boolean compact(Context context){android.content.res.Configuration c=context.getResources().getConfiguration();return c.screenWidthDp<600&&c.screenHeightDp<720;}
    static int dp(Context context,float value){return Math.round(value*context.getResources().getDisplayMetrics().density);}
    static GradientDrawable shape(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(radius);return d;}
    static Drawable circle(Context context,AppIcon.Kind kind,boolean selected){return new Circle(context,kind,selected);}
    static Drawable ratio(Context context,double ratio,boolean selected){return new Ratio(context,ratio,selected);}
    static Drawable face(Context context,int color,int radius,int inset){
        StateListDrawable states=new StateListDrawable();
        states.addState(new int[]{android.R.attr.state_pressed},new Disk(0xc9233028,dp(context,inset),false));
        states.addState(new int[]{android.R.attr.state_focused},new Disk(0xc93a4231,dp(context,inset),true));
        states.addState(new int[]{},new Disk(color,dp(context,inset),false));
        return states;
    }
    private static final class Disk extends Drawable {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);private final int color,inset;private final boolean focused;
        Disk(int color,int inset,boolean focused){this.color=color;this.inset=inset;this.focused=focused;}
        @Override public void draw(Canvas c){Rect b=getBounds();float radius=Math.max(0,Math.min(b.width(),b.height())/2f-inset);paint.setStyle(Paint.Style.FILL);paint.setColor(color);c.drawCircle(b.exactCenterX(),b.exactCenterY(),radius,paint);if(focused){paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(Math.max(1,inset/6f));paint.setColor(YELLOW);c.drawCircle(b.exactCenterX(),b.exactCenterY(),Math.max(0,radius-paint.getStrokeWidth()),paint);}}
        @Override public void setAlpha(int alpha){}@Override public void setColorFilter(ColorFilter filter){}@Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    /** The glyph and every control state share the target's exact center, including odd pixel sizes. */
    static Drawable iconFace(Context context,AppIcon.Kind kind,int color){
        AppIcon icon=new AppIcon(kind,WHITE,context.getResources().getDisplayMetrics().density);
        LayerDrawable layers=new LayerDrawable(new Drawable[]{face(context,color,24,6),icon});
        layers.setPaddingMode(LayerDrawable.PADDING_MODE_STACK);
        layers.setLayerSize(1,dp(context,19),dp(context,19));layers.setLayerGravity(1,Gravity.CENTER);return layers;
    }
    static void primary(Button button){
        Context c=button.getContext();button.setBackground(new InsetDrawable(shape(YELLOW,dp(c,24)),dp(c,4),dp(c,5),dp(c,4),dp(c,5)));
        button.setBackgroundTintList(null);button.setTextColor(INK);button.setTextSize(13);button.setGravity(Gravity.CENTER);button.setStateListAnimator(null);button.setIncludeFontPadding(false);
    }
    private static final java.util.concurrent.ExecutorService ATMOSPHERES=java.util.concurrent.Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"editor-atmosphere");t.setDaemon(true);return t;});
    /** Full-screen editing tools use the same bounded photo atmosphere as their parent workspace. */
    static void workspace(View root,Bitmap source){
        Backdrop backdrop=new Backdrop();root.setBackground(backdrop);decorate(root);
        java.util.concurrent.Future<?> task=ATMOSPHERES.submit(()->{
            Bitmap sample=null;try{if(source!=null&&!source.isRecycled())sample=EditorGlassDrawable.sample(source);}catch(RuntimeException|OutOfMemoryError ignored){}
            final Bitmap image=sample;root.post(()->{if(root.getBackground()==backdrop&&root.isAttachedToWindow())backdrop.setSample(image);else if(image!=null&&!image.isRecycled())image.recycle();});
        });
        root.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener(){public void onViewAttachedToWindow(View v){}public void onViewDetachedFromWindow(View v){task.cancel(false);Bitmap image=backdrop.sample;backdrop.setSample(null);if(image!=null&&!image.isRecycled())image.recycle();root.removeOnAttachStateChangeListener(this);}});
    }
    private static void decorate(View view){
        if(view instanceof SeekBar)slider(view.getContext(),(SeekBar)view);
        if(view instanceof Button&&String.valueOf(view.getTag()).endsWith("-apply"))primary((Button)view);
        if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;for(int i=0;i<group.getChildCount();i++)decorate(group.getChildAt(i));}
    }
    static void slider(Context context,SeekBar slider){
        GradientDrawable track=shape(0x66ffffff,dp(context,1)),fill=shape(YELLOW,dp(context,1));
        LayerDrawable drawable=new LayerDrawable(new Drawable[]{track,new ClipDrawable(fill,Gravity.LEFT,ClipDrawable.HORIZONTAL)});
        drawable.setId(0,android.R.id.background);drawable.setId(1,android.R.id.progress);
        for(int i=0;i<2;i++){drawable.setLayerHeight(i,dp(context,2));drawable.setLayerGravity(i,Gravity.CENTER_VERTICAL);}
        slider.setProgressDrawable(drawable);slider.setProgressTintList(null);slider.setProgressBackgroundTintList(null);
        GradientDrawable knob=shape(Color.WHITE,dp(context,8));knob.setSize(dp(context,14),dp(context,14));slider.setThumb(knob);slider.setThumbTintList(null);
        slider.setSplitTrack(false);slider.setThumbOffset(dp(context,7));PhotoWorkspaceUi.fitSliderThumb(slider);
    }
    static final class ToolFace extends Drawable {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Drawable icon;private final int size;private boolean selected,pressed,focused;
        ToolFace(Context context,Drawable icon,boolean selected){this.selected=selected;size=dp(context,39);this.icon=icon;}
        @Override public void draw(Canvas canvas){Rect b=getBounds();float r=Math.min(b.width(),b.height())/2f;paint.setStyle(Paint.Style.FILL);paint.setColor(pressed?0xe62e3827:selected?0xe6111713:0x9c101412);canvas.drawCircle(b.exactCenterX(),b.exactCenterY(),r,paint);int side=Math.round(r*42/39f);int save=canvas.save();canvas.translate(b.exactCenterX()-side/2f,b.exactCenterY()-side/2f);icon.setBounds(0,0,side,side);icon.draw(canvas);canvas.restoreToCount(save);if(focused){paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(Math.max(1,size/39f));paint.setColor(YELLOW);canvas.drawCircle(b.exactCenterX(),b.exactCenterY(),r-paint.getStrokeWidth(),paint);}}
        void selected(boolean value){selected=value;invalidateSelf();}
        @Override public boolean isStateful(){return true;}
        @Override protected boolean onStateChange(int[] states){pressed=focused=false;for(int state:states){if(state==android.R.attr.state_pressed)pressed=true;if(state==android.R.attr.state_focused)focused=true;}invalidateSelf();return true;}
        @Override public int getIntrinsicWidth(){return size;}@Override public int getIntrinsicHeight(){return size;}
        @Override public void setAlpha(int alpha){}@Override public void setColorFilter(ColorFilter filter){}@Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    static final class Circle extends Drawable {
        private final ToolFace face;
        Circle(Context context,AppIcon.Kind kind,boolean selected){face=new ToolFace(context,new AppIcon(kind,selected?YELLOW:Color.WHITE,context.getResources().getDisplayMetrics().density),selected);}
        @Override public void draw(Canvas canvas){face.setBounds(getBounds());face.draw(canvas);}
        @Override public boolean isStateful(){return true;}@Override protected boolean onStateChange(int[] states){face.setState(states);invalidateSelf();return true;}
        @Override public int getIntrinsicWidth(){return face.getIntrinsicWidth();}@Override public int getIntrinsicHeight(){return face.getIntrinsicHeight();}
        @Override public void setAlpha(int alpha){}@Override public void setColorFilter(ColorFilter filter){}@Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    static final class Ratio extends Drawable {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);private final int size;private final double ratio;
        Ratio(Context context,double ratio,boolean selected){size=dp(context,30);this.ratio=ratio==0?.8:ratio;paint.setColor(selected?YELLOW:0xc9ffffff);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(dp(context,1));}
        @Override public void draw(Canvas canvas){Rect b=getBounds();float h=b.height()*.82f,w=(float)(h*ratio);if(w>b.width()*.9f){w=b.width()*.9f;h=(float)(w/ratio);}canvas.drawRoundRect(new RectF(b.exactCenterX()-w/2,b.exactCenterY()-h/2,b.exactCenterX()+w/2,b.exactCenterY()+h/2),2,2,paint);}
        @Override public int getIntrinsicWidth(){return size;}@Override public int getIntrinsicHeight(){return size;}@Override public void setAlpha(int alpha){}@Override public void setColorFilter(ColorFilter filter){}@Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    /** Borrows the editor's bounded, worker-produced blurred photo sample; never decodes on draw. */
    static final class Backdrop extends Drawable {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
        private final RectF image=new RectF();private Bitmap sample;
        void setSample(Bitmap bitmap){if(sample!=bitmap){sample=bitmap;invalidateSelf();}}
        @Override public void draw(Canvas canvas){
            Rect b=getBounds();canvas.save();canvas.clipRect(b);canvas.drawColor(0xff242b27);
            if(sample!=null&&!sample.isRecycled()){
                float scale=Math.max(b.width()/(float)sample.getWidth(),b.height()/(float)sample.getHeight());float w=sample.getWidth()*scale,h=sample.getHeight()*scale;
                image.set(b.exactCenterX()-w/2,b.exactCenterY()-h/2,b.exactCenterX()+w/2,b.exactCenterY()+h/2);paint.setColor(Color.WHITE);paint.setShader(null);canvas.drawBitmap(sample,null,image,paint);
            }
            paint.setShader(new LinearGradient(0,b.top,0,b.bottom,new int[]{0x8917221e,0x2b15211d,0x9e131b1b},new float[]{0,.48f,1},Shader.TileMode.CLAMP));canvas.drawRect(b,paint);paint.setShader(null);canvas.restore();
        }
        @Override public void setAlpha(int alpha){}@Override public void setColorFilter(ColorFilter filter){}@Override public int getOpacity(){return PixelFormat.OPAQUE;}
    }
}
