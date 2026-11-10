package cc.huevia.ui;

import android.app.Activity;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.os.Build;
import android.os.Bundle;
import android.view.*;
import android.widget.*;
import cc.huevia.ncp.AdjustmentRegion;
import cc.huevia.ncp.PhotoPortrait;
import cc.huevia.ncp.SelectionShape;
import java.util.*;
import java.util.function.Consumer;

/**
 * THESIS: one photo-first selection workspace shared by regional adjustments.
 * OWN-WORLD: existing Prisma atmosphere, quiet circular tools, yellow primary action.
 * STORY: paint or drag a circle/ellipse or rectangle, refine, then return to adjustment.
 * FIRST VIEWPORT: cancel/name/done above the photo; history, tools and feather below.
 * FORM: user-approved selection-workspace prototype, within the established editor.
 * FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review,
 * the verdict, DESIGN.md, and every shipping raster carrying its provenance.
 */
public final class PhotoBrushDialog extends Dialog {
    private static final int TEXT=0xfff4f5f7,MUTED=PhotoPrismaStyle.MUTED,ACCENT=PhotoPrismaStyle.YELLOW,MASK_ALPHA=38;
    private final Activity activity;
    private final Bitmap initial,mask;
    private final int maskWidth,maskHeight;
    private final float[] coverage,strokeCoverage;
    private final int[] maskPixels;
    private final Consumer<AdjustmentRegion> commit;
    private final AdjustmentRegion originalRegion;
    private AdjustmentRegion region;
    private final ArrayDeque<AdjustmentRegion> undo=new ArrayDeque<>(),redo=new ArrayDeque<>();
    private final PhotoCanvas photo;
    private Button apply,undoButton,redoButton,holdMaskButton,invertButton,moreButton;
    private SeekBar featherControl;
    private final Button[] toolButtons=new Button[3],modeButtons=new Button[3];
    private TextView status,selectionLabel;
    private LinearLayout body,panel,sizeRow;
    private FrameLayout stage;
    private ScrollView dock;
    private int tool,operation;
    private double radius=.04,feather=.2;
    private boolean disposed,sourcePositioning,showSelection=true,adjusting,replaceArmed;
    private AdjustmentRegion sliderStart;

    public PhotoBrushDialog(Activity activity,Bitmap orientedPhoto,AdjustmentRegion initialRegion,Consumer<AdjustmentRegion> commit){
        super(activity,cc.huevia.R.style.AppThemeDark);
        if(orientedPhoto==null||orientedPhoto.isRecycled()||initialRegion==null||commit==null)throw new IllegalArgumentException("选区参数无效。");
        this.activity=activity;initial=orientedPhoto;region=originalRegion=initialRegion;this.commit=commit;
        operation=initialRegion.hasSelection()?1:0;replaceArmed=operation==0;
        double scale=Math.min(1,320.0/Math.max(initial.getWidth(),initial.getHeight()));
        maskWidth=Math.max(2,(int)Math.round(initial.getWidth()*scale));maskHeight=Math.max(2,(int)Math.round(initial.getHeight()*scale));
        mask=Bitmap.createBitmap(maskWidth,maskHeight,Bitmap.Config.ARGB_8888);coverage=new float[maskWidth*maskHeight];strokeCoverage=new float[coverage.length];maskPixels=new int[coverage.length];photo=new PhotoCanvas();rebuildMask();
    }
    public void setSourcePositioning(boolean value){sourcePositioning=value;}
    public AdjustmentRegion settings(){return region;}
    @Override protected void onCreate(Bundle state){
        super.onCreate(state);requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout root=column();root.setTag("brush-workspace");LinearLayout top=row();top.setPadding(dp(4),0,dp(8),0);
        top.addView(PhotoWorkspaceUi.icon(getContext(),"close","取消本次选区编辑","brush-cancel",this::dismiss),new LinearLayout.LayoutParams(dp(48),dp(52)));
        TextView title=text("编辑选区 · "+region.name,16,TEXT);title.setSingleLine(true);title.setEllipsize(android.text.TextUtils.TruncateAt.END);title.setGravity(Gravity.CENTER);top.addView(title,new LinearLayout.LayoutParams(0,dp(52),1));
        apply=button("完成",this::complete);apply.setTag("brush-apply");PhotoPrismaStyle.primary(apply);top.addView(apply,new LinearLayout.LayoutParams(dp(76),dp(52)));root.addView(top);
        body=column();body.setTag("brush-body");root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
        stage=new FrameLayout(getContext());stage.setTag("brush-stage");stage.addView(photo,new FrameLayout.LayoutParams(-1,-1));body.addView(stage,new LinearLayout.LayoutParams(-1,0,1));
        status=text(sourcePositioning?"按原图定位选区 · 调整后保留照片构图":"单指涂抹 · 双指缩放和移动",12,MUTED);status.setGravity(Gravity.CENTER);status.setTag("brush-status");status.setPadding(dp(10),dp(6),dp(10),dp(6));status.setTextColor(TEXT);status.setMaxLines(2);status.setEllipsize(android.text.TextUtils.TruncateAt.END);status.setBackground(PhotoPrismaStyle.shape(0xb3191e17,dp(8)));FrameLayout.LayoutParams hint=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);hint.setMargins(dp(8),dp(8),dp(8),dp(8));stage.addView(status,hint);stage.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{int maximum=Math.max(dp(48),stage.getWidth()-dp(16));if(status.getMaxWidth()!=maximum)status.setMaxWidth(maximum);});
        panel=column();panel.setPadding(dp(12),0,dp(12),dp(8));panel.setTag("brush-panel");
        LinearLayout history=row();undoButton=PhotoWorkspaceUi.icon(getContext(),"undo","撤销选区操作","brush-undo",this::undo);redoButton=PhotoWorkspaceUi.icon(getContext(),"redo","重做选区操作","brush-redo",this::redo);
        history.addView(undoButton,new LinearLayout.LayoutParams(dp(48),dp(48)));history.addView(redoButton,new LinearLayout.LayoutParams(dp(48),dp(48)));history.addView(new View(getContext()),new LinearLayout.LayoutParams(0,1,1));
        holdMaskButton=PhotoWorkspaceUi.icon(getContext(),"eye","隐藏选区，保留调整","brush-hold-mask",()->{showSelection=!showSelection;refresh();});history.addView(holdMaskButton,new LinearLayout.LayoutParams(dp(48),dp(48)));selectionLabel=text("隐藏选区",12,TEXT);selectionLabel.setGravity(Gravity.CENTER);selectionLabel.setSingleLine(true);selectionLabel.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);selectionLabel.setOnClickListener(v->holdMaskButton.performClick());history.addView(selectionLabel,new LinearLayout.LayoutParams(dp(64*Math.max(1,activity.getResources().getConfiguration().fontScale)),dp(48)));
        moreButton=PhotoWorkspaceUi.icon(getContext(),"more","更多选区操作","selection-more",this::showMore);history.addView(moreButton,new LinearLayout.LayoutParams(dp(48),dp(48)));panel.addView(history);
        LinearLayout tools=row();String[] names={"画笔","圆形","矩形"},icons={"brush","selection-circle","selection-rectangle"},tags={"brush-add","selection-circle","selection-rectangle"};
        for(int i=0;i<3;i++){final int next=i;toolButtons[i]=PhotoWorkspaceUi.tool(getContext(),names[i],tags[i],icons[i],()->chooseTool(next));tools.addView(toolButtons[i],new LinearLayout.LayoutParams(0,dp(72*Math.max(1,activity.getResources().getConfiguration().fontScale)),1));}panel.addView(tools);
        LinearLayout modes=row();String[] labels={"替换","添加","减去"};for(int i=0;i<3;i++){final int next=i;modeButtons[i]=button(labels[i],()->{photo.cancelStroke();operation=next;replaceArmed=next==0;refresh();});modeButtons[i].setTag(i==2?"brush-erase":i==0?"selection-replace":"selection-add");modes.addView(modeButtons[i],new LinearLayout.LayoutParams(0,dp(48),1));}
        modes.addView(new View(getContext()),new LinearLayout.LayoutParams(dp(12),1));invertButton=button("反选",()->{photo.cancelStroke();if(!region.hasSelection())return;AdjustmentRegion before=region;region=region.withInverted(!region.inverted);remember(before);showSelection=true;rebuildMask();refresh();});invertButton.setTag("selection-invert");modes.addView(invertButton,new LinearLayout.LayoutParams(dp(60),dp(48)));panel.addView(modes);
        addSlider(panel,"羽化","brush-feather",100,20,true);sizeRow=column();addSlider(sizeRow,"大小","brush-size",119,39,false);panel.addView(sizeRow);
        dock=new ScrollView(getContext());dock.setTag("brush-dock");dock.setVerticalScrollBarEnabled(false);dock.addView(panel);body.addView(dock,new LinearLayout.LayoutParams(-1,dp(264)));body.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->arrange());
        root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){Insets safe=insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());root.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else root.setPadding(insets.getStableInsetLeft(),insets.getStableInsetTop(),insets.getStableInsetRight(),insets.getStableInsetBottom());body.post(this::arrange);return insets;});
        PhotoPrismaStyle.workspace(root,initial);setContentView(root);if(getWindow()!=null){getWindow().setBackgroundDrawableResource(android.R.color.transparent);getWindow().setLayout(-1,-1);}root.requestApplyInsets();refresh();
    }
    @Override public void show(){super.show();if(getWindow()!=null)getWindow().setLayout(-1,-1);}
    private void arrange(){
        if(disposed||body==null||body.getHeight()<2)return;int w=body.getWidth(),h=body.getHeight();boolean side=w>h&&w>=dp(480);int orientation=side?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL;if(body.getOrientation()!=orientation)body.setOrientation(orientation);
        int sw=side?0:-1,sh=side?-1:0;LinearLayout.LayoutParams stageSize=(LinearLayout.LayoutParams)stage.getLayoutParams();if(stageSize.width!=sw||stageSize.height!=sh||stageSize.weight!=1)stage.setLayoutParams(new LinearLayout.LayoutParams(sw,sh,1));
        int dw=side?Math.min(dp(320),Math.round(w*.44f)):-1,dh=side?-1:Math.min(dp((tool==0?264:216)+48*(Math.max(1,activity.getResources().getConfiguration().fontScale)-1)),h/2);LinearLayout.LayoutParams dockSize=(LinearLayout.LayoutParams)dock.getLayoutParams();if(dockSize.width!=dw||dockSize.height!=dh)dock.setLayoutParams(new LinearLayout.LayoutParams(dw,dh));photo.invalidate();
    }
    private void chooseTool(int value){photo.cancelStroke();tool=value;showSelection=true;refresh();arrange();status.setText(tool==0?"单指涂抹 · 双指缩放和移动":"拖动创建 · 拖动选区移动 · 拉角点调整大小");}
    private void showMore(){PopupMenu menu=new PopupMenu(getContext(),moreButton);menu.getMenu().add("适应照片").setOnMenuItemClickListener(item->{photo.resetViewport();return true;});menu.getMenu().add("清空当前选区").setOnMenuItemClickListener(item->{clear();return true;});menu.show();}
    private void addSlider(LinearLayout parent,String label,String tag,int max,int initialValue,boolean featherSlider){
        LinearLayout line=row();line.addView(text(label,12,MUTED),new LinearLayout.LayoutParams(dp(44),dp(48)));SeekBar slider=new SeekBar(getContext());slider.setTag(tag);if(featherSlider)featherControl=slider;slider.setMax(max);slider.setProgress(initialValue);PhotoPrismaStyle.slider(activity,slider);line.addView(slider,new LinearLayout.LayoutParams(0,dp(48),1));TextView value=text(featherSlider?initialValue+"%":"4.0%",12,MUTED);value.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);line.addView(value,new LinearLayout.LayoutParams(dp(48),dp(48)));slider.setContentDescription(label);
        slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar b,int p,boolean user){if(featherSlider){feather=p/100.0;value.setText(p+"%");if(user&&tool>0){SelectionShape selected=photo.selectedShape();if(selected!=null){ArrayList<SelectionShape> shapes=new ArrayList<>(region.shapes);int i=shapes.indexOf(selected);shapes.set(i,selected.feather(feather));region=region.withShapes(shapes);rebuildMask();}}}else{radius=(p+1)/1000.0;value.setText(String.format(Locale.ROOT,"%.1f%%",radius*100));}b.setContentDescription(label+"，"+value.getText());}
            public void onStartTrackingTouch(SeekBar b){photo.cancelStroke();sliderStart=region;adjusting=true;photo.invalidate();}
            public void onStopTrackingTouch(SeekBar b){adjusting=false;if(sliderStart!=null){remember(sliderStart);sliderStart=null;}refresh();}
        });parent.addView(line,new LinearLayout.LayoutParams(-1,dp(48)));
    }
    private void remember(AdjustmentRegion before){if(before==null||before.equals(region))return;undo.addLast(before);while(undo.size()>32)undo.removeFirst();redo.clear();}
    private void undo(){if(undo.isEmpty())return;photo.cancelStroke();redo.addLast(region);region=undo.removeLast();showSelection=true;rebuildMask();refresh();}
    private void redo(){if(redo.isEmpty())return;photo.cancelStroke();undo.addLast(region);region=redo.removeLast();showSelection=true;rebuildMask();refresh();}
    private void clear(){photo.cancelStroke();AdjustmentRegion before=region;region=region.clearSelection();remember(before);rebuildMask();refresh();}
    private boolean hasCoverage(){for(float value:coverage)if(value>0)return true;return false;}
    private boolean canComplete(){return hasCoverage()||originalRegion.hasSelection()&&!region.equals(originalRegion);}
    private void complete(){if(disposed||photo.tracking||adjusting||!canComplete())return;commit.accept(region);dismiss();}
    private void refresh(){if(apply==null)return;if(tool>0&&!adjusting&&featherControl!=null){SelectionShape selected=photo.selectedShape();if(selected!=null){feather=selected.feather;featherControl.setProgress((int)Math.round(feather*100));}}for(int i=0;i<3;i++){toolButtons[i].setSelected(tool==i);modeButtons[i].setSelected(operation==i);modeButtons[i].setTextColor(operation==i?TEXT:MUTED);modeButtons[i].setBackground(PhotoPrismaStyle.shape(operation==i?0x18d9dcc5:Color.TRANSPARENT,dp(8)));}sizeRow.setVisibility(tool==0?View.VISIBLE:View.GONE);undoButton.setEnabled(!undo.isEmpty());redoButton.setEnabled(!redo.isEmpty());apply.setEnabled(!photo.tracking&&!adjusting&&canComplete());holdMaskButton.setSelected(showSelection);holdMaskButton.setContentDescription(showSelection?"隐藏选区，保留调整":"显示选区");holdMaskButton.setTooltipText(holdMaskButton.getContentDescription());selectionLabel.setText(showSelection?"隐藏选区":"显示选区");invertButton.setSelected(region.inverted);invertButton.setTextColor(region.inverted?ACCENT:TEXT);invertButton.setEnabled(region.hasSelection());photo.invalidate();}
    @Override public void onWindowFocusChanged(boolean focused){super.onWindowFocusChanged(focused);if(!focused&&photo!=null){photo.cancelStroke();if(sliderStart!=null){region=sliderStart;sliderStart=null;rebuildMask();}adjusting=false;refresh();}}
    @Override public void dismiss(){if(!disposed){photo.cancelStroke();disposed=true;mask.recycle();}super.dismiss();}
    private void rebuildMask(){AdjustmentRegion.Brush brush=region.compileBrush(initial.getWidth(),initial.getHeight());for(int y=0;y<maskHeight;y++)for(int x=0;x<maskWidth;x++){int i=y*maskWidth+x;coverage[i]=(float)brush.weight((x+.5)/maskWidth,(y+.5)/maskHeight);}restoreMask();}
    private void restoreMask(){Arrays.fill(strokeCoverage,0);for(int i=0;i<coverage.length;i++)maskPixels[i]=(Math.round(coverage[i]*MASK_ALPHA)<<24)|0x00fff1e4;mask.setPixels(maskPixels,0,maskWidth,0,0,maskWidth,maskHeight);if(photo!=null&&!disposed)photo.invalidate();}
    private double combined(double selected,double weight,boolean erase){double raw=region.inverted?1-selected:selected;raw=erase?raw*(1-weight):raw+(1-raw)*weight;return region.inverted?1-raw:raw;}
    private void liveSegment(double ax,double ay,double bx,double by){double w=initial.getWidth(),h=initial.getHeight(),r=radius*Math.min(w,h),vx=(bx-ax)*w,vy=(by-ay)*h,len=vx*vx+vy*vy;int l=Math.max(0,(int)Math.floor((Math.min(ax,bx)-r/w)*maskWidth)),rr=Math.min(maskWidth-1,(int)Math.ceil((Math.max(ax,bx)+r/w)*maskWidth)),t=Math.max(0,(int)Math.floor((Math.min(ay,by)-r/h)*maskHeight)),b=Math.min(maskHeight-1,(int)Math.ceil((Math.max(ay,by)+r/h)*maskHeight));
        for(int y=t;y<=b;y++)for(int x=l;x<=rr;x++){double px=(x+.5)/maskWidth*w-ax*w,py=(y+.5)/maskHeight*h-ay*h,p=len==0?0:Math.max(0,Math.min(1,(px*vx+py*vy)/len)),d=Math.hypot(px-p*vx,py-p*vy)/r,weight=falloff(d,feather);int i=y*maskWidth+x;if(weight<=strokeCoverage[i])continue;strokeCoverage[i]=(float)weight;maskPixels[i]=((int)Math.round(combined(coverage[i],weight,(operation==2)^region.inverted)*MASK_ALPHA)<<24)|0x00fff1e4;}
        mask.setPixels(maskPixels,0,maskWidth,0,0,maskWidth,maskHeight);photo.invalidate();
    }
    private static double falloff(double distance,double feather){if(distance>=1)return 0;if(feather<=0||distance<=1-feather)return 1;double t=(distance-1+feather)/feather;return 1-t*t*(3-2*t);}
    private final class PhotoCanvas extends View {
        final RectF frame=new RectF();private final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);private final ArrayList<Double> path=new ArrayList<>();
        private final ScaleGestureDetector scale;private float zoom=1,panX,panY,lastX,lastY;private boolean tracking,navigating,gestureReplaceArmed;
        private AdjustmentRegion gestureRegion;private double downX,downY;private int shapeIndex=-1,handle=-1,activeShape=-1;private SelectionShape shapeStart;
        PhotoCanvas(){super(PhotoBrushDialog.this.getContext());setTag("brush-canvas");setFocusable(true);setClickable(true);setContentDescription("选区照片，单指绘制或调整选区，双指缩放和移动");scale=new ScaleGestureDetector(getContext(),new ScaleGestureDetector.SimpleOnScaleGestureListener(){public boolean onScale(ScaleGestureDetector d){float next=Math.max(1,Math.min(8,zoom*d.getScaleFactor())),ratio=next/zoom,fx=d.getFocusX()-getWidth()/2f,fy=d.getFocusY()-getHeight()/2f;panX=fx-(fx-panX)*ratio;panY=fy-(fy-panY)*ratio;zoom=next;bounds();invalidate();return true;}});scale.setQuickScaleEnabled(false);scale.setStylusScaleEnabled(false);}
        @Override protected void onSizeChanged(int w,int h,int ow,int oh){super.onSizeChanged(w,h,ow,oh);if(ow>0&&oh>0&&!frame.isEmpty()){double cx=(ow/2.0-frame.left)/frame.width(),cy=(oh/2.0-frame.top)/frame.height();float fit=Math.min(w/(float)initial.getWidth(),h/(float)initial.getHeight());panX=(float)((.5-cx)*initial.getWidth()*fit*zoom);panY=(float)((.5-cy)*initial.getHeight()*fit*zoom);}cancelStroke();navigating=false;bounds();}
        void resetViewport(){cancelStroke();zoom=1;panX=panY=0;bounds();invalidate();}
        private void bounds(){float fit=Math.min(getWidth()/(float)initial.getWidth(),getHeight()/(float)initial.getHeight()),w=initial.getWidth()*fit*zoom,h=initial.getHeight()*fit*zoom,mx=Math.max(0,(w-getWidth())/2),my=Math.max(0,(h-getHeight())/2);panX=Math.max(-mx,Math.min(mx,panX));panY=Math.max(-my,Math.min(my,panY));frame.set((getWidth()-w)/2+panX,(getHeight()-h)/2+panY,(getWidth()+w)/2+panX,(getHeight()+h)/2+panY);}
        private void cancelStroke(){boolean pending=tracking;tracking=false;path.clear();if(pending&&gestureRegion!=null){region=gestureRegion;gestureRegion=null;replaceArmed=gestureReplaceArmed;if(!disposed)rebuildMask();}shapeIndex=handle=-1;shapeStart=null;if(!disposed)refresh();}
        @Override protected void onDraw(Canvas c){super.onDraw(c);if(disposed)return;bounds();ink.setAlpha(255);ink.setStyle(Paint.Style.FILL);c.drawBitmap(initial,null,frame,ink);if(!showSelection||adjusting)return;int save=c.save();c.clipRect(frame);c.drawBitmap(mask,null,frame,ink);SelectionShape selected=selectedShape();if(tool>0&&selected!=null){SelectionShape s=selected;RectF box=new RectF((float)(frame.left+s.left*frame.width()),(float)(frame.top+s.top*frame.height()),(float)(frame.left+s.right*frame.width()),(float)(frame.top+s.bottom*frame.height()));ink.setColor(0xffdddcc8);ink.setStyle(Paint.Style.STROKE);ink.setStrokeWidth(dp(1));if(s.kind==SelectionShape.Kind.ELLIPSE)c.drawOval(box,ink);else c.drawRect(box,ink);ink.setStyle(Paint.Style.FILL);ink.setColor(TEXT);for(int i=0;i<4;i++)c.drawCircle(i%2==0?box.left:box.right,i<2?box.top:box.bottom,dp(3),ink);}c.restoreToCount(save);}
        private SelectionShape selectedShape(){if(activeShape>=0&&activeShape<region.shapes.size()){SelectionShape s=region.shapes.get(activeShape);if((tool==1)==(s.kind==SelectionShape.Kind.ELLIPSE))return s;}for(int i=region.shapes.size()-1;i>=0;i--){SelectionShape s=region.shapes.get(i);if((tool==1)==(s.kind==SelectionShape.Kind.ELLIPSE)){activeShape=i;return s;}}return null;}
        private int hit(SelectionShape s,float x,float y){float l=(float)(frame.left+s.left*frame.width()),r=(float)(frame.left+s.right*frame.width()),t=(float)(frame.top+s.top*frame.height()),b=(float)(frame.top+s.bottom*frame.height());for(int i=0;i<4;i++)if(Math.hypot(x-(i%2==0?l:r),y-(i<2?t:b))<=dp(24))return i;return x>=l&&x<=r&&y>=t&&y<=b?4:-1;}
        private void updateShape(double x,double y){double l,r,t,b;if(handle==4){double dx=Math.max(-shapeStart.left,Math.min(1-shapeStart.right,x-downX)),dy=Math.max(-shapeStart.top,Math.min(1-shapeStart.bottom,y-downY));l=shapeStart.left+dx;r=shapeStart.right+dx;t=shapeStart.top+dy;b=shapeStart.bottom+dy;}else{double ax=handle<0?downX:handle%2==0?shapeStart.right:shapeStart.left,ay=handle<0?downY:handle<2?shapeStart.bottom:shapeStart.top;l=Math.min(ax,x);r=Math.max(ax,x);t=Math.min(ay,y);b=Math.max(ay,y);}if(r-l<.0001||b-t<.0001)return;try{SelectionShape s=new SelectionShape(tool==1?SelectionShape.Kind.ELLIPSE:SelectionShape.Kind.RECTANGLE,l,t,r,b,shapeStart==null?feather:shapeStart.feather,(operation==2)^region.inverted,region.strokes.size());ArrayList<SelectionShape> shapes=new ArrayList<>(region.shapes);if(shapeIndex<0){shapes.add(s);shapeIndex=shapes.size()-1;activeShape=shapeIndex;}else{SelectionShape prior=shapes.get(shapeIndex);shapes.set(shapeIndex,new SelectionShape(prior.kind,l,t,r,b,prior.feather,prior.subtract,prior.strokeIndex));}region=region.withShapes(shapes);rebuildMask();}catch(IllegalArgumentException limit){status.setText("选区元素已达上限，请撤销或清空后重试。");}}
        @Override public boolean onTouchEvent(MotionEvent e){if(disposed||adjusting)return false;bounds();int action=e.getActionMasked();scale.onTouchEvent(e);
            if(e.getPointerCount()>1){if(!navigating){cancelStroke();navigating=true;lastX=e.getX();lastY=e.getY();}float x=0,y=0;for(int i=0;i<e.getPointerCount();i++){x+=e.getX(i);y+=e.getY(i);}x/=e.getPointerCount();y/=e.getPointerCount();if(action==MotionEvent.ACTION_MOVE){panX+=x-lastX;panY+=y-lastY;bounds();}lastX=x;lastY=y;invalidate();return true;}
            if(navigating){if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL)navigating=false;return true;}
            if(action==MotionEvent.ACTION_DOWN){cancelStroke();tracking=frame.contains(e.getX(),e.getY());if(!tracking)return true;gestureRegion=region;gestureReplaceArmed=replaceArmed;downX=nx(e.getX());downY=ny(e.getY());showSelection=true;
                if(tool>0&&operation==0){for(int i=region.shapes.size()-1;i>=0;i--){SelectionShape candidate=region.shapes.get(i);if((tool==1)==(candidate.kind==SelectionShape.Kind.ELLIPSE)){handle=hit(candidate,e.getX(),e.getY());if(handle>=0){shapeIndex=activeShape=i;shapeStart=candidate;refresh();return true;}}}}
                if(operation==0&&(tool>0||replaceArmed)){region=region.clearSelection();replaceArmed=false;rebuildMask();}
                if(tool==0){path.add(downX);path.add(downY);liveSegment(downX,downY,downX,downY);}refresh();return true;}
            if(!tracking)return true;double x=nx(e.getX()),y=ny(e.getY());
            if(action==MotionEvent.ACTION_MOVE||action==MotionEvent.ACTION_UP){if(tool>0)updateShape(x,y);else{int n=path.size();double ax=path.get(n-2),ay=path.get(n-1);if(Math.hypot((x-ax)*initial.getWidth(),(y-ay)*initial.getHeight())>.001*Math.min(initial.getWidth(),initial.getHeight())&&path.size()<PhotoPortrait.MAX_STROKE_POINTS*2){path.add(x);path.add(y);liveSegment(ax,ay,x,y);}}}
            if(action==MotionEvent.ACTION_UP){tracking=false;try{if(tool>0&&shapeIndex<0){region=gestureRegion;rebuildMask();}if(tool==0){double[] points=new double[path.size()];for(int i=0;i<points.length;i++)points[i]=path.get(i);region=region.addStroke(new PhotoPortrait.Stroke(points,radius,feather,(operation==2)^region.inverted));for(int i=0;i<coverage.length;i++)coverage[i]=(float)combined(coverage[i],strokeCoverage[i],(operation==2)^region.inverted);restoreMask();}remember(gestureRegion);}catch(IllegalArgumentException limit){region=gestureRegion;rebuildMask();status.setText("选区元素已达上限，请撤销或清空后重试。");}gestureRegion=null;path.clear();shapeIndex=handle=-1;shapeStart=null;refresh();performClick();return true;}
            if(action==MotionEvent.ACTION_CANCEL)cancelStroke();return true;
        }
        private double nx(float x){return Math.max(0,Math.min(1,(x-frame.left)/frame.width()));}
        private double ny(float y){return Math.max(0,Math.min(1,(y-frame.top)/frame.height()));}
        @Override public boolean performClick(){return super.performClick();}
    }
    private Button button(String label,Runnable task){Button b=new Button(getContext());b.setText(label);b.setAllCaps(false);b.setTextSize(12);b.setTextColor(TEXT);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setPadding(dp(4),0,dp(4),0);b.setIncludeFontPadding(false);b.setGravity(Gravity.CENTER);b.setStateListAnimator(null);b.setBackgroundColor(Color.TRANSPARENT);b.setOnClickListener(v->task.run());return b;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.HORIZONTAL);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private LinearLayout column(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.VERTICAL);return v;}
    private TextView text(String value,float size,int color){TextView v=new TextView(getContext());v.setText(value);v.setTextSize(size);v.setTextColor(color);v.setIncludeFontPadding(false);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private int dp(float value){return Math.round(value*getContext().getResources().getDisplayMetrics().density);}
}
