package cc.huevia.ui;

import android.content.Context;
import android.content.res.ColorStateList;
import android.app.AlertDialog;
import android.graphics.Bitmap;
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
import android.graphics.drawable.LayerDrawable;
import android.graphics.drawable.RippleDrawable;
import android.view.Gravity;
import android.view.TouchDelegate;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Button;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;
import cc.huevia.ncp.PhotoHistogram;
import java.util.concurrent.CancellationException;

/** Editor-only diagnostics. The host owns snapshot identity, request ordering and image lifetime.
 * Neither statistics nor warning preferences are edit parameters or export inputs. */
public final class PhotoHistogramPanel extends LinearLayout {
    public interface Listener { void onWarningsChanged(boolean shadows, boolean highlights); }
    private static final int TEXT=0xffffffff, ACCENT=0xfff2b48c, ACCENT_INK=0xff2a1c12;
    private final Listener listener;
    private final ToggleButton luminance, rgb, shadow, highlight;
    private final Chart chart;
    private final TextView footer;
    private PhotoHistogram data;
    private boolean rgbMode, shadowOn, highlightOn, updating;
    private String error="",status="";
    private View photoSource;
    private PhotoGlassDrawable glass;
    private AlertDialog explanation;

    public PhotoHistogramPanel(Context context, Listener listener) {
        super(context); this.listener=listener;
        setOrientation(VERTICAL);
        setChildrenDrawingOrderEnabled(true);
        setPanelBackground(fallbackMaterial());
        LinearLayout header=row();
        luminance=button("亮度",false,()->{rgbMode=false;refresh();});
        rgb=button("RGB",false,()->{rgbMode=true;refresh();});
        header.addView(luminance,new LayoutParams(dp(48),dp(48)));
        header.addView(rgb,new LayoutParams(dp(48),dp(48)));
        header.addView(new View(context),new LayoutParams(0,1,1));
        shadow=button("",true,()->{if(hasData()){shadowOn=!shadowOn;refresh();notifyWarnings();}});
        highlight=button("",true,()->{if(hasData()){highlightOn=!highlightOn;refresh();notifyWarnings();}});
        shadow.setText("暗部");highlight.setText("高光");
        addSwatch(shadow,false);addSwatch(highlight,true);
        header.addView(shadow,new LayoutParams(chipWidth(shadow,"暗部"),dp(48)));
        LayoutParams highlightSize=new LayoutParams(chipWidth(highlight,"高光"),dp(48));highlightSize.setMarginStart(dp(6));header.addView(highlight,highlightSize);
        HorizontalScrollView headerScroll=new HorizontalScrollView(context);headerScroll.setHorizontalScrollBarEnabled(false);
        headerScroll.setFillViewport(true);headerScroll.setContentDescription("直方图工具，窄屏可左右滑动");
        headerScroll.addView(header,new HorizontalScrollView.LayoutParams(-1,dp(48)));
        addView(headerScroll,new LayoutParams(-1,dp(48)));
        chart=new Chart(context);chart.setOnClickListener(v->showExplanation());chart.setTooltipText("直方图与警示说明");
        // The 28dp header faces end at y=38. The remaining touch target is transparent,
        // so the 52dp graph can start at y=40 without adding a tall toolbar to the photo.
        LayoutParams graphSize=new LayoutParams(-1,dp(52));graphSize.topMargin=-dp(8);addView(chart,graphSize);
        LinearLayout foot=row();
        TextView zero=footerLabel(context,"0"),end=footerLabel(context,"255");
        footer=footerLabel(context,"8 位 sRGB");footer.setGravity(Gravity.CENTER);
        foot.addView(zero,new LayoutParams(dp(22),-1));foot.addView(footer,new LayoutParams(0,-1,1));
        end.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);foot.addView(end,new LayoutParams(dp(22),-1));
        Paint.FontMetricsInt footerMetrics=footer.getPaint().getFontMetricsInt();
        addView(foot,new LayoutParams(-1,Math.max(dp(12),footerMetrics.descent-footerMetrics.ascent)));
        refresh();
    }

    // Header's transparent final 8dp overlaps only the graph. Draw and dispatch it last,
    // preserving all four 48dp button hit areas while keeping the prototype's compact height.
    @Override protected int getChildDrawingOrder(int count,int index){return index==count-1?0:index+1;}
    @Override protected void onLayout(boolean changed,int left,int top,int right,int bottom){
        super.onLayout(changed,left,top,right,bottom);
        if(chart!=null)setTouchDelegate(new TouchDelegate(new Rect(chart.getLeft(),dp(48),chart.getRight(),getHeight()),chart));
    }

    /** The photo is sampled locally beneath this floating overlay; never sample an ancestor. */
    public void setPhotoSource(View source) {
        if(photoSource==source&&glass!=null){glass.refresh();return;}
        closeGlass();photoSource=source;createGlass();
    }
    /** Call after a preview or viewport update; the bounded backdrop is refreshed on the next draw. */
    public void refreshGlass() { if(glass!=null)glass.refresh(); }
    private void createGlass() {
        if(photoSource==null){setPanelBackground(fallbackMaterial());return;}
        glass=new PhotoGlassDrawable(photoSource,this,getResources().getDisplayMetrics().density,18);setPanelBackground(glass);
    }
    private void setPanelBackground(Drawable background){setBackground(background);setPadding(dp(10),0,dp(10),0);}
    private void closeGlass() { if(glass!=null){glass.close();glass=null;} }
    @Override protected void onAttachedToWindow(){super.onAttachedToWindow();if(glass==null)createGlass();}
    @Override protected void onDetachedFromWindow(){if(explanation!=null){explanation.dismiss();explanation=null;}closeGlass();super.onDetachedFromWindow();}

    public void setData(PhotoHistogram value) {
        data=value!=null&&value.hasData()?value:null;updating=false;error="";refresh();
    }
    /** Keep the last valid plot while explicitly labelling it as the previous preview. */
    public void setUpdating() { updating=true;error="";refresh(); }
    public void setError(String message) { updating=false;error=message==null||message.trim().isEmpty()?"预览统计暂不可用，请调整后重试。":message;refresh(); }
    /** Call on photograph/account rebind or a new editor session; no callback or draft mutation. */
    public void reset() { data=null;rgbMode=false;shadowOn=false;highlightOn=false;updating=false;error="";if(explanation!=null){explanation.dismiss();explanation=null;}refresh(); }
    /** Silent host synchronisation. */
    public void setWarnings(boolean shadows,boolean highlights) { shadowOn=shadows;highlightOn=highlights;refresh(); }
    public boolean isShadowWarning() { return shadowOn; }
    public boolean isHighlightWarning() { return highlightOn; }
    private void showExplanation() {
        if(explanation!=null&&explanation.isShowing())return;
        String measured=hasData()?"当前统计：暗部 "+data.shadowPercent()+"，高光 "+data.highlightPercent()+"。\n\n":"";
        String message=(error.isEmpty()?"":error+"\n\n")+measured+"基于当前 sRGB 预览，统计整幅构图内容，不含外加边框。\n\n高光：任一 RGB 通道为 255。暗部：三通道均为 0。RGB 三通道共用纵轴。\n\n暖色右斜纹表示高光，蓝色左斜纹表示暗部，仅辅助判断，不代表原片细节一定不可恢复；并非 RAW 测量。警示不会写入导出照片。";
        explanation=new PhotoEditorTypography.Builder(getContext()).setTitle("直方图与警示").setMessage(message).setPositiveButton("知道了",null).create();
        explanation.setOnDismissListener(dialog->explanation=null);explanation.show();PhotoEditorTypography.apply(explanation);
    }
    private boolean hasData() { return data!=null&&data.hasData(); }
    private void notifyWarnings() { if(listener!=null)listener.onWarningsChanged(shadowOn,highlightOn); }

    private void refresh() {
        boolean valid=hasData(),old=updating||!error.isEmpty();
        select(luminance,!rgbMode);select(rgb,rgbMode);
        status=updating?(valid?"更新中 · 上次预览":"统计中"):
                !error.isEmpty()?(valid?"失败 · 上次预览":"统计不可用"):(valid?"8 位 sRGB":"暂无预览");
        footer.setText(status);
        shadow.setEnabled(valid);highlight.setEnabled(valid);
        shadow.setAlpha(valid?1:.55f);highlight.setAlpha(valid?1:.55f);
        String sp=valid?data.shadowPercent():"—",hp=valid?data.highlightPercent():"—";
        select(shadow,shadowOn);select(highlight,highlightOn);
        shadow.setContentDescription("暗部警示，"+(shadowOn?"已开启":"已关闭")+"，"+(old&&valid?"上次预览 ":"")+sp+"，蓝色左斜纹");
        highlight.setContentDescription("高光警示，"+(highlightOn?"已开启":"已关闭")+"，"+(old&&valid?"上次预览 ":"")+hp+"，暖色右斜纹，任一通道触顶");
        String summary=valid?(rgbMode?"RGB 三通道，共享纵轴":"显示亮度，0 至 255")+"，有效预览像素 "+data.pixelCount()+"，暗部 "+sp+"，高光 "+hp:"暂无有效预览统计";
        chart.setContentDescription(status+"，"+summary+(old&&valid?"，上一份有效预览":"")+(error.isEmpty()?"":"，"+error)+"，轻点查看直方图与警示说明");chart.invalidate();
    }

    /** Use only unframed, unmasked sRGB working content, on a host worker thread. */
    public static PhotoHistogram measure(Bitmap content) {
        requireBitmap(content);
        PhotoHistogram.Builder builder=new PhotoHistogram.Builder();
        int width=content.getWidth();int[] row=new int[width];
        for(int y=0;y<content.getHeight();y++) {
            if(Thread.currentThread().isInterrupted())throw new CancellationException();
            content.getPixels(row,0,width,0,y,width,1);builder.addArgb(row,0,width);
        }
        return builder.build();
    }

    /** Returns a distinct ARGB_8888 copy even when disabled. Apply an external frame only afterwards.
     * The source, histogram data and export pixels must never be replaced by this diagnostic copy. */
    public static Bitmap warningCopy(Bitmap content,boolean shadows,boolean highlights) {
        requireBitmap(content);
        Bitmap copy=content.copy(Bitmap.Config.ARGB_8888,true);
        if(copy==null)throw new IllegalStateException("预览警示暂无法载入。");
        if(!shadows&&!highlights)return copy;
        try {
            int width=content.getWidth();int[] row=new int[width];
            int stripe=Math.max(3,Math.min(10,Math.min(width,content.getHeight())/70));
            for(int y=0;y<content.getHeight();y++) {
                if(Thread.currentThread().isInterrupted())throw new CancellationException();
                content.getPixels(row,0,width,0,y,width,1);
                for(int x=0;x<width;x++) {
                    int argb=row[x];boolean high=highlights&&PhotoHistogram.isHighlight(argb);
                    boolean low=shadows&&PhotoHistogram.isShadow(argb);
                    if(!high&&!low)continue;
                    // Opposing stripe directions remain distinguishable without colour vision.
                    boolean line=Math.floorMod(high?x-y:x+y,stripe*2)<stripe;
                    int tint=high?0xfff3a676:0xff80b9f2,alpha=line?144:46;
                    row[x]=blend(argb,tint,alpha);
                }
                copy.setPixels(row,0,width,0,y,width,1);
            }
            return copy;
        }catch(RuntimeException|Error failure){copy.recycle();throw failure;}
    }
    private static void requireBitmap(Bitmap bitmap) {
        if(bitmap==null||bitmap.isRecycled()||bitmap.getWidth()<1||bitmap.getHeight()<1)
            throw new IllegalArgumentException("预览内容不可用。");
    }
    private static int blend(int source,int tint,int alpha) {
        int inverse=255-alpha;
        int r=(((source>>>16)&255)*inverse+((tint>>>16)&255)*alpha+127)/255;
        int g=(((source>>>8)&255)*inverse+((tint>>>8)&255)*alpha+127)/255;
        int b=((source&255)*inverse+(tint&255)*alpha+127)/255;
        return (source&0xff000000)|(r<<16)|(g<<8)|b;
    }

    private final class Chart extends View {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);private final Path path=new Path(),area=new Path();
        Chart(Context context){super(context);setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);setAccessibilityLiveRegion(ACCESSIBILITY_LIVE_REGION_POLITE);}
        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float left=0,right=getWidth(),top=dp(1),bottom=getHeight()-dp(1);
            if(right<=left||bottom<=top)return;
            paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(Math.max(1,dp(.5f)));paint.setColor(0x24ffffff);
            canvas.drawLine(left,bottom,right,bottom,paint);
            if(!hasData()) {
                paint.setStyle(Paint.Style.FILL);paint.setTextSize(12*getResources().getDisplayMetrics().scaledDensity);paint.setColor(TEXT);paint.setTextAlign(Paint.Align.CENTER);
                canvas.drawText(updating?"统计中":"暂无统计",(left+right)/2,(top+bottom)/2-(paint.ascent()+paint.descent())/2,paint);
                paint.setTextAlign(Paint.Align.LEFT);return;
            }
            if(rgbMode) {
                long maximum=data.sharedRgbMaximum();
                drawChannel(canvas,PhotoHistogram.Channel.RED,0xffff6a5e,maximum,left,right,top,bottom,true);
                drawChannel(canvas,PhotoHistogram.Channel.GREEN,0xff6fe38c,maximum,left,right,top,bottom,true);
                drawChannel(canvas,PhotoHistogram.Channel.BLUE,0xff6ea0ff,maximum,left,right,top,bottom,true);
            } else {
                drawChannel(canvas,PhotoHistogram.Channel.LUMINANCE,0xd9ffffff,data.max(PhotoHistogram.Channel.LUMINANCE),left,right,top,bottom,true);
                paint.setStyle(Paint.Style.STROKE);paint.setColor(0x24ffffff);paint.setStrokeWidth(Math.max(1,dp(.5f)));
                for(int i=1;i<4;i++){float x=left+(right-left)*i/4;canvas.drawLine(x,top,x,bottom,paint);}
            }
            if(data.shadowCount()>0)endpoint(canvas,left,top,0xff93b6e4);
            if(data.highlightCount()>0)endpoint(canvas,right,top,ACCENT);
        }
        private void drawChannel(Canvas canvas,PhotoHistogram.Channel channel,int color,long max,float left,float right,float top,float bottom,boolean fill) {
            if(max<=0)return;
            path.reset();
            for(int bin=0;bin<256;bin++) {
                float x=left+(right-left)*bin/255f;
                // Fixed linear mapping, preserving all endpoint peaks and channel relative height.
                float y=bottom-(float)((bottom-top)*data.count(channel,bin)/(double)max);
                if(bin==0)path.moveTo(x,y);else path.lineTo(x,y);
            }
            if(fill){area.set(path);area.lineTo(right,bottom);area.lineTo(left,bottom);area.close();paint.setStyle(Paint.Style.FILL);paint.setColor((color&0xffffff)|(rgbMode?0x47000000:0x4d000000));canvas.drawPath(area,paint);}
            paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(dp(1));paint.setColor(color);canvas.drawPath(path,paint);
        }
        private void endpoint(Canvas canvas,float x,float top,int color){path.reset();path.moveTo(x,top+dp(6));path.lineTo(x-dp(3),top);path.lineTo(x+dp(3),top);path.close();paint.setColor(color);paint.setStyle(Paint.Style.FILL);canvas.drawPath(path,paint);}
    }
    private final class ToggleButton extends Button {
        private final boolean chip;
        private WarningSwatch swatch;
        ToggleButton(Context context,boolean chip){super(context);this.chip=chip;}
        @Override protected void onDraw(Canvas canvas){
            if(!chip||swatch==null){super.onDraw(canvas);return;}
            // View supplies a scrolled content canvas. TextView can scroll its centred,
            // single-line layout horizontally; keep this custom group in viewport coordinates,
            // matching View.drawBackground's scroll compensation for the fixed chip face.
            int saved=canvas.save();canvas.translate(getScrollX(),getScrollY());
            // Draw the swatch and label as one centred group, independent of TextView's layout.
            Paint textPaint=getPaint();textPaint.setColor(getCurrentTextColor());
            String label=getText().toString();float icon=dp(8),gap=dp(4);
            float group=icon+gap+textPaint.measureText(label),left=(getWidth()-group)/2f;
            float middle=getHeight()/2f;
            swatch.setBounds(Math.round(left),Math.round(middle-icon/2),Math.round(left+icon),Math.round(middle+icon/2));
            swatch.draw(canvas);
            Paint.FontMetrics metrics=textPaint.getFontMetrics();
            canvas.drawText(label,left+icon+gap,middle-(metrics.ascent+metrics.descent)/2f,textPaint);
            canvas.restoreToCount(saved);
        }
        @Override public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info){super.onInitializeAccessibilityNodeInfo(info);info.setCheckable(true);info.setChecked(isSelected());}
    }
    private LinearLayout row(){LinearLayout row=new LinearLayout(getContext());row.setGravity(Gravity.CENTER_VERTICAL);row.setBaselineAligned(false);return row;}
    private ToggleButton button(String name,boolean chip,Runnable action){ToggleButton button=new ToggleButton(getContext(),chip);button.setText(name);button.setAllCaps(false);button.setTextSize(chip?11:12);button.setTypeface(Typeface.create("sans-serif",Typeface.NORMAL));button.setIncludeFontPadding(false);button.setSingleLine(true);button.setGravity(Gravity.CENTER);button.setMinWidth(0);button.setMinimumWidth(0);button.setMinHeight(0);button.setMinimumHeight(0);button.setPadding(chip?dp(8):0,0,chip?dp(8):0,0);button.setStateListAnimator(null);button.setBackgroundTintList(null);button.setOnClickListener(v->action.run());return button;}
    private TextView footerLabel(Context context,String text){TextView label=new TextView(context);label.setText(text);label.setTextSize(9.5f);label.setTextColor(0x6bffffff);label.setIncludeFontPadding(false);label.setSingleLine(true);label.setGravity(Gravity.CENTER_VERTICAL);return label;}
    private void addSwatch(ToggleButton button,boolean high){button.swatch=new WarningSwatch(high);}
    private int chipWidth(ToggleButton button,String name){Paint measure=new Paint(button.getPaint());measure.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));float width=Math.max(button.getPaint().measureText(name),measure.measureText(name));return Math.max(dp(48),(int)Math.ceil(width)+dp(28));}
    private void select(ToggleButton button,boolean selected){
        button.setSelected(selected);button.setTextColor(button.chip?(selected?ACCENT_INK:0xccffffff):(selected?TEXT:0x99ffffff));
        button.setTypeface(Typeface.create(selected?"sans-serif-medium":"sans-serif",Typeface.NORMAL));
        Drawable content,mask;
        if(button.chip){
            content=new ChipFace(selected?ACCENT:0x12ffffff,selected?ACCENT:0x38ffffff);
            mask=new ChipFace(Color.WHITE,Color.TRANSPARENT);
        }else{
            // A real background layer is independent of TextView's text canvas and clipping.
            LayerDrawable mode=new LayerDrawable(new Drawable[]{shape(Color.TRANSPARENT,9),shape(selected?ACCENT:Color.TRANSPARENT,1)});
            mode.setLayerSize(1,Math.max(dp(14),(int)Math.ceil(button.getPaint().measureText(button.getText().toString()))),dp(2));
            mode.setLayerGravity(1,Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);
            mode.setLayerInset(1,0,0,0,dp(12));
            content=mode;mask=new ChipFace(Color.WHITE,Color.TRANSPARENT);
        }
        button.setBackground(new RippleDrawable(ColorStateList.valueOf(0x28f3b493),content,mask));button.setBackgroundTintList(null);
        // Background replacement can supply drawable padding. Restore the intended content
        // padding last; the 28dp visual face remains centred in its 48dp touch target.
        button.setPadding(button.chip?dp(8):0,0,button.chip?dp(8):0,0);button.setGravity(Gravity.CENTER);button.setClipToOutline(false);button.invalidate();
    }
    /** Fixed visual geometry is independent of font size and the larger touch target. */
    private final class ChipFace extends Drawable {
        private final int fill,stroke;private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF face=new RectF();private int alpha=255;
        ChipFace(int fill,int stroke){this.fill=fill;this.stroke=stroke;}
        @Override public void draw(Canvas canvas){
            Rect bounds=getBounds();float half=Math.min(dp(28),bounds.height())/2f;
            face.set(bounds.left,bounds.exactCenterY()-half,bounds.right,bounds.exactCenterY()+half);
            paint.setStyle(Paint.Style.FILL);paint.setColor(fill);paint.setAlpha(Color.alpha(fill)*alpha/255);canvas.drawRoundRect(face,dp(8),dp(8),paint);
            if(Color.alpha(stroke)>0){float width=Math.max(1,dp(1));face.inset(width/2,width/2);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(width);paint.setColor(stroke);paint.setAlpha(Color.alpha(stroke)*alpha/255);canvas.drawRoundRect(face,Math.max(0,dp(8)-width/2),Math.max(0,dp(8)-width/2),paint);}
        }
        @Override public void setAlpha(int alpha){this.alpha=alpha;invalidateSelf();}
        @Override public void setColorFilter(ColorFilter filter){paint.setColorFilter(filter);invalidateSelf();}
        @Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    /** Two small, opposing stripe samples preserve the warning meaning without relying on hue. */
    private final class WarningSwatch extends Drawable {
        private final boolean high;private int alpha=255;private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);private final Path clip=new Path();
        WarningSwatch(boolean high){this.high=high;}
        @Override public void draw(Canvas canvas){RectF r=new RectF(getBounds());if(r.isEmpty())return;int save=canvas.save();clip.reset();clip.addRoundRect(r,dp(3),dp(3),Path.Direction.CW);canvas.clipPath(clip);paint.setStyle(Paint.Style.FILL);paint.setColor(high?0xff5a3a14:0xff17233a);paint.setAlpha(alpha);canvas.drawRect(r,paint);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(dp(2));paint.setColor(high?0xffff9838:0xff6aa0ff);paint.setAlpha(alpha);float extent=r.width()+r.height();for(float x=-extent;x<extent*2;x+=dp(4)){if(high)canvas.drawLine(r.left+x,r.bottom,r.left+x+r.height(),r.top,paint);else canvas.drawLine(r.left+x,r.top,r.left+x+r.height(),r.bottom,paint);}canvas.restoreToCount(save);}
        @Override public void setAlpha(int alpha){this.alpha=alpha;invalidateSelf();}
        @Override public void setColorFilter(ColorFilter filter){paint.setColorFilter(filter);invalidateSelf();}
        @Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    private GradientDrawable fallbackMaterial(){GradientDrawable material=shape(0xc71a1613,18);material.setStroke(Math.max(1,dp(.5f)),0x29ffffff);return material;}
    private GradientDrawable shape(int color,int radius){GradientDrawable shape=new GradientDrawable();shape.setColor(color);shape.setCornerRadius(dp(radius));return shape;}
    private int dp(float value){return Math.round(value*getResources().getDisplayMetrics().density);}
}
