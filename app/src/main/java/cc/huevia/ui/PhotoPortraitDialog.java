package cc.huevia.ui;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.InsetDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.PopupMenu;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;
import cc.huevia.album.PhotoPortraitDetection;
import cc.huevia.album.PhotoFaceLandmarks;
import cc.huevia.album.PhotoFaceSkinMask;
import cc.huevia.album.PhotoFaceBodySkin;
import cc.huevia.album.PhotoExposedSkin;
import cc.huevia.ncp.PhotoPortrait;
import cc.huevia.ncp.AdjustmentRegion;
import cc.huevia.ncp.PortraitPreviewFilter;
import cc.huevia.ncp.SkinTone;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

/** Tentative, photo-local portrait editing. Only Apply commits to the parent editor. */
public final class PhotoPortraitDialog extends Dialog {
    /** Return a fresh owned EXIF-oriented, pre-composition image. */
    public interface Renderer { Bitmap render(PhotoPortrait portrait, boolean interactive) throws Exception; }
    public interface RegionRenderer { Bitmap render(AdjustmentRegion region, boolean interactive) throws Exception; }
    private static final int TEXT=0xfff4f5f7,MUTED=PhotoPrismaStyle.MUTED,ACCENT=PhotoPrismaStyle.YELLOW,PANEL=Color.TRANSPARENT;
    private static final String[] PARAMETER_NAMES={"面部提亮","面部冷暖","面部红润","面部柔肤","面部纹理保留","面部光照","眼下阴影"};
    private static final String[] PARAMETER_LABELS={"提亮","冷暖","红润","柔肤","纹理","光照","眼下阴影"};
    private final Activity activity;
    private final Bitmap initial,analysis;
    private final Consumer<PhotoPortrait> commit;
    private final Consumer<AdjustmentRegion> regionCommit;
    private final boolean regionMode;
    private AdjustmentRegion region;
    private Runnable paintRequest;
    private PhotoBrushDialog brushDialog;
    private PhotoBodyDialog bodyDialog;
    private Renderer portraitRenderer;
    private boolean sourcePositioning;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"portrait-preview");t.setDaemon(true);return t;});
    private final ExecutorService auxiliary=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"portrait-selection");t.setDaemon(true);return t;});
    private final LatestPreviewQueue<Snapshot,Bitmap> queue;
    private final LatestPreviewQueue<PhotoPortrait.Face,Bitmap> maskQueue;
    private final ArrayDeque<Snapshot> undo=new ArrayDeque<>(),redo=new ArrayDeque<>();
    private final PhotoCanvas photo;
    private final SkinToneSwatches toneSwatches;
    private PhotoPortrait portrait;
    private Snapshot gestureStart,completedPreview;
    private PhotoPortrait.Face overlayFace;
    private Bitmap rendered,overlay;
    private TextView status,hint,sizeValue,workspaceTitle;
    private View sizeRow;
    private Button apply,selection,overlayButton,undoButton,redoButton,auto,maskCategory;
    private Button toneFace,toneBody,toneManage,toneMore,cancelButton,backButton,brushButton,skinToneTool,skinSmoothingTool;
    private final Button[] skinEffects=new Button[5];
    private HorizontalScrollView skinRail;
    private LinearLayout groupEntries;
    private boolean choosingGroup=true,directSection;
    private LinearLayout toneControls,toneCards;
    private LinearLayout faceBar;
    private LinearLayout tonePreviewActions;
    private HorizontalScrollView toneRail;
    private SkinTonePicker tonePicker;
    private String toneCardsKey;
    private boolean photoSampling;
    private boolean tonePreviewing;
    private Snapshot tonePreviewStart;
    private int sampleSeed;
    private volatile long toneTask;
    private boolean tonePerFace,globalSkinBusy,globalSkinAttempted,globalSkinFailed,globalSkinEmpty;
    private volatile long globalSkinTask;
    private PhotoPortrait.BodySkinMask preparedGlobalSkinMask;
    private final Button[] tools=new Button[4],effects=new Button[7];
    private final TextView[] labels=new TextView[1],values=new TextView[1];
    private final SeekBar[] sliders=new SeekBar[1];
    private final View[] rows=new View[1];
    /** mode: 0 = one direct effect, 1 = healing, 2 = selection correction, 3 = skin tone. */
    private cc.huevia.ncp.PortraitRetouch.Parameter activeRetouch;
    private final java.util.EnumMap<cc.huevia.ncp.PortraitRetouch.Parameter,Button> retouchTools=new java.util.EnumMap<>(cc.huevia.ncp.PortraitRetouch.Parameter.class);
    private final java.util.EnumMap<cc.huevia.ncp.PortraitRetouch.Parameter,Button> lightAxisTools=new java.util.EnumMap<>(cc.huevia.ncp.PortraitRetouch.Parameter.class);
    private PortraitLightPad lightPad;
    private View lightAxes;
    private int selected=-1,tool,mode=3,activeParameter,lastFaceMode,activeSkinParameter;
    private double radius=.022;
    private boolean adding,showOverlay=true,compare,updating,dragging,analysisBusy;
    private boolean overlayHiddenByUser,selectionEntryDragging;
    private PhotoPortrait.BodySkinMask overlayGlobalMask;
    private boolean selectionFlashPending;
    /** Legacy queue cancellation state, retained for in-flight mask callbacks; no timer animates selection. */
    private int selectionFlashStep=-1;
    private final Runnable selectionFlashTick=this::advanceSelectionFlash;
    private LinearLayout selectionTools,workspaceBody;
    private FrameLayout workspaceStage;
    private ScrollView dock;
    private LinearLayout dockPanel;
    private HorizontalScrollView primaryRail;
    private volatile boolean disposed;
    private volatile long revision;
    private String notice;
    private AlertDialog decision;

    private static final class Snapshot {
        final PhotoPortrait portrait;final AdjustmentRegion region;final boolean beforeBody;
        Snapshot(PhotoPortrait portrait,AdjustmentRegion region){this(portrait,region,false);}
        Snapshot(PhotoPortrait portrait,AdjustmentRegion region,boolean beforeBody){this.portrait=portrait;this.region=region;this.beforeBody=beforeBody;}
        @Override public boolean equals(Object other){if(!(other instanceof Snapshot))return false;Snapshot value=(Snapshot)other;return portrait.equals(value.portrait)&&java.util.Objects.equals(region,value.region);}
        @Override public int hashCode(){return java.util.Objects.hash(portrait,region);}
    }

    /** The initial bitmap is borrowed until dismissal and is never recycled here. */
    public PhotoPortraitDialog(Activity activity,Bitmap orientedBeforePortrait,PhotoPortrait initialSettings,
            Renderer renderer,Consumer<PhotoPortrait> commit) {
        this(activity,orientedBeforePortrait,initialSettings,renderer,commit,null,null,null);
    }
    public PhotoPortraitDialog(Activity activity,Bitmap orientedBeforeRegion,AdjustmentRegion initialRegion,
            RegionRenderer renderer,Consumer<AdjustmentRegion> commit){
        this(activity,orientedBeforeRegion,initialRegion==null?null:initialRegion.portrait,null,null,initialRegion,renderer,commit);
    }
    private PhotoPortraitDialog(Activity activity,Bitmap orientedBeforePortrait,PhotoPortrait initialSettings,
            Renderer renderer,Consumer<PhotoPortrait> commit,AdjustmentRegion initialRegion,RegionRenderer regionRenderer,Consumer<AdjustmentRegion> regionCommit){
        super(activity,cc.huevia.R.style.AppThemeDark);
        if(orientedBeforePortrait==null||orientedBeforePortrait.isRecycled()||initialSettings==null||(initialRegion==null?(renderer==null||commit==null):(regionRenderer==null||regionCommit==null)))
            throw new IllegalArgumentException("人像编辑参数无效。");
        this.activity=activity;this.initial=orientedBeforePortrait;this.portrait=initialSettings;this.commit=commit;this.regionCommit=regionCommit;regionMode=initialRegion!=null;region=initialRegion;
        portraitRenderer=renderer;
        toneSwatches=new SkinToneSwatches(activity);
        preparedGlobalSkinMask=regionMode?region.effectiveSkinMask():portrait.globalSkinMask;globalSkinAttempted=preparedGlobalSkinMask!=null;globalSkinEmpty=emptySkinMask(preparedGlobalSkinMask);
        if(preparedGlobalSkinMask!=null)portrait=portrait.withGlobalSkinMask(preparedGlobalSkinMask);
        double ratio=Math.min(1,960.0/Math.max(initial.getWidth(),initial.getHeight()));
        Bitmap small=Bitmap.createScaledBitmap(initial,Math.max(2,(int)Math.round(initial.getWidth()*ratio)),Math.max(2,(int)Math.round(initial.getHeight()*ratio)),true);
        analysis=small==initial?initial.copy(Bitmap.Config.ARGB_8888,false):small;
        if(analysis==null)throw new IllegalArgumentException("人像预览准备失败。");
        if(!portrait.faces().isEmpty())selected=0;
        for(int i=0;i<portrait.faces().size();i++)if(!portrait.faces().get(i).tone.isNeutral()){tonePerFace=true;selected=i;break;}
        photo=new PhotoCanvas();
        queue=new LatestPreviewQueue<>(worker,r->main.post(r),(value,interactive)->regionMode?regionRenderer.render(value.region,interactive):renderer.render(value.beforeBody?value.portrait.withBodyShape(cc.huevia.ncp.PhotoBodyShape.NONE):value.portrait,interactive),new LatestPreviewQueue.Listener<Snapshot,Bitmap>(){
            public void frame(Snapshot value,Bitmap image,boolean interactive,boolean latest){
                if(disposed||value.beforeBody!=beforeBody()){image.recycle();return;}Bitmap old=rendered;rendered=image;photo.invalidate();if(old!=null&&old!=image)old.recycle();
                if(latest&&!interactive&&value.equals(snapshot())){completedPreview=value;showPreviewStatus();refreshApplyAvailability();}
            }
            public void discard(Bitmap image){image.recycle();}
            public void error(Throwable error){if(disposed)return;completedPreview=null;status.setText("预览失败 · 点按重试");status.setOnClickListener(v->changed(false));refreshApplyAvailability();}
        });
        maskQueue=new LatestPreviewQueue<>(auxiliary,r->main.post(r),(face,interactive)->maskBitmap(face),new LatestPreviewQueue.Listener<PhotoPortrait.Face,Bitmap>(){
            public void frame(PhotoPortrait.Face face,Bitmap image,boolean interactive,boolean latest){if(disposed||!latest||!face.equals(overlayFace)||!(showOverlay||selectionFlashPending||selectionFlashStep>=0)){image.recycle();return;}Bitmap old=overlay;overlay=image;if(old!=null&&old!=image)old.recycle();if(selectionFlashPending)startSelectionFlash();photo.invalidate();}
            public void discard(Bitmap image){image.recycle();}
            public void error(Throwable error){if(!disposed){clearSelectionFlash();overlayFace=null;Bitmap old=overlay;overlay=null;if(old!=null)old.recycle();photo.invalidate();}}
        });
    }
    public PhotoPortrait settings(){return portrait;}
    /** Enter a common tool directly from the main editor, retaining this dialog's Apply/Cancel transaction. */
    public void openSection(int section){if(disposed)return;directSection=section==1||section==2;if(directSection){backButton.setContentDescription("返回编辑照片");backButton.setOnClickListener(v->onBackPressed());}if(section==1)chooseTone();else if(section==2){chooseFaceGroup();if(portrait.faces().isEmpty())askDetect();}}
    public void setSourcePositioning(boolean value){sourcePositioning=value;if(status!=null)changed(false);}
    private boolean beforeBody(){return sourcePositioning||!choosingGroup&&!portrait.bodyShape.isNeutral();}
    public AdjustmentRegion regionSettings(){return regionMode?snapshot().region:null;}
    public void setPaintRequest(Runnable request){paintRequest=request;if(brushButton!=null)refresh();}

    @Override protected void onCreate(Bundle state){
        super.onCreate(state);requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout root=column();root.setBackgroundColor(0xff0c0b0a);root.setTag("photo-portrait-workspace");
        // The photograph leads. Controls reveal one task at a time in the bottom dock.
        LinearLayout top=row();top.setPadding(dp(4),0,dp(8),0);
        FrameLayout navigation=new FrameLayout(getContext());
        cancelButton=PhotoWorkspaceUi.icon(getContext(),"close","取消人像精修","portrait-cancel",this::dismiss);navigation.addView(cancelButton,new FrameLayout.LayoutParams(-1,-1));
        backButton=PhotoWorkspaceUi.icon(getContext(),"back","返回人像工具","portrait-back",this::showGroupEntries);navigation.addView(backButton,new FrameLayout.LayoutParams(-1,-1));
        top.addView(navigation,new LinearLayout.LayoutParams(dp(48),dp(52)));
        TextView title=text("人像",16,TEXT);workspaceTitle=title;title.setTag("portrait-title");title.setSingleLine(true);title.setEllipsize(android.text.TextUtils.TruncateAt.END);title.setGravity(Gravity.CENTER);top.addView(title,new LinearLayout.LayoutParams(0,dp(52),1));
        apply=button("应用",()->{if(!disposed&&apply.isEnabled()){if(regionMode)regionCommit.accept(snapshot().region);else commit.accept(portrait);dismiss();}});
        apply.setTag("portrait-apply");apply.setTextColor(0xff211812);
        GradientDrawable applyFace=new GradientDrawable();applyFace.setColor(ACCENT);applyFace.setCornerRadius(dp(10));
        apply.setBackground(new InsetDrawable(applyFace,dp(4),dp(8),dp(4),dp(8)));
        top.addView(apply,new LinearLayout.LayoutParams(dp(72),dp(52)));root.addView(top);
        boolean landscape=activity.getResources().getConfiguration().orientation==Configuration.ORIENTATION_LANDSCAPE;
        LinearLayout body=new LinearLayout(getContext());workspaceBody=body;body.setTag("portrait-body");body.setOrientation(landscape?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL);root.addView(body,new LinearLayout.LayoutParams(-1,0,1));
        FrameLayout stage=new FrameLayout(getContext());workspaceStage=stage;stage.setTag("portrait-stage");stage.addView(photo,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout faces=row();faceBar=faces;faces.setPadding(dp(8),0,dp(4),0);faces.setBackgroundColor(0x7017221e);
        selection=button("选择人脸",this::chooseFace);selection.setTag("portrait-selection");selection.setMaxLines(1);
        selection.setEllipsize(android.text.TextUtils.TruncateAt.END);faces.addView(selection,new LinearLayout.LayoutParams(0,dp(48),1));
        auto=button("自动选脸",this::askDetect);auto.setTag("portrait-auto");auto.setTextColor(ACCENT);
        faces.addView(auto,new LinearLayout.LayoutParams(dp(96),dp(48)));
        Button add=PhotoWorkspaceUi.icon(getContext(),"add","手动添加人脸","portrait-add-face",()->{cancelTonePreview();photoSampling=false;clearSelectionFlash();mode=2;adding=true;tool=0;showOverlay=!overlayHiddenByUser;refresh();revealActiveChoice();});
        faces.addView(add,new LinearLayout.LayoutParams(dp(48),dp(48)));
        Button more=PhotoWorkspaceUi.icon(getContext(),"more","更多人像操作","portrait-more",()->showMore());
        faces.addView(more,new LinearLayout.LayoutParams(dp(48),dp(48)));
        stage.addView(faces,new FrameLayout.LayoutParams(-1,dp(48),Gravity.TOP));

        LinearLayout quick=row();quick.setPadding(dp(8),0,dp(8),0);quick.setBackgroundColor(Color.TRANSPARENT);
        undoButton=stageAction(quick,"undo","撤销","portrait-undo",this::undo);
        redoButton=stageAction(quick,"redo","重做","portrait-redo",this::redo);
        quick.addView(new View(getContext()),new LinearLayout.LayoutParams(0,1,1));
        brushButton=stageAction(quick,"brush","涂抹范围","portrait-brush",this::editBrush);
        overlayButton=stageAction(quick,"eye","显示或隐藏选区","portrait-overlay",()->{clearSelectionFlash();overlayHiddenByUser=!overlayHiddenByUser;showOverlay=!overlayHiddenByUser;refresh();});
        stageAction(quick,"fit","适应照片","portrait-fit",photo::resetViewport);
        Button compareButton=stageAction(quick,"compare","按住查看处理前；辅助功能点击切换","portrait-compare",()->setCompare(!compare));
        compareButton.setOnTouchListener((v,e)->{switch(e.getActionMasked()){case MotionEvent.ACTION_DOWN:setCompare(true);return true;case MotionEvent.ACTION_UP:case MotionEvent.ACTION_CANCEL:case MotionEvent.ACTION_POINTER_DOWN:setCompare(false);return true;case MotionEvent.ACTION_MOVE:if(e.getX()<0||e.getX()>v.getWidth()||e.getY()<0||e.getY()>v.getHeight())setCompare(false);return true;}return true;});
        stage.addView(quick,new FrameLayout.LayoutParams(-1,dp(48),Gravity.BOTTOM));
        status=text("",12,MUTED);status.setTag("portrait-status");status.setMaxLines(2);status.setPadding(dp(12),dp(4),dp(12),dp(4));status.setGravity(Gravity.CENTER);status.setBackgroundColor(0x7017221e);status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);status.setVisibility(View.GONE);
        status.addTextChangedListener(new android.text.TextWatcher(){public void beforeTextChanged(CharSequence s,int start,int count,int after){}public void onTextChanged(CharSequence s,int start,int before,int count){status.setVisibility(s.length()==0?View.GONE:View.VISIBLE);}public void afterTextChanged(android.text.Editable s){}});
        FrameLayout.LayoutParams statusParams=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);statusParams.bottomMargin=dp(48);stage.addView(status,statusParams);
        body.addView(stage,landscape?new LinearLayout.LayoutParams(0,-1,1):new LinearLayout.LayoutParams(-1,0,1));

        LinearLayout controls=column();controls.setBackgroundColor(PANEL);controls.setPadding(dp(12),dp(4),dp(12),dp(8));
        selectionTools=row();selectionTools.setTag("portrait-selection-modes");
        String[] names={"选脸","补选","擦除"};
        for(int i=0;i<3;i++){final int next=i;tools[i]=button(names[i],()->{clearSelectionFlash();mode=2;tool=next;adding=false;showOverlay=!overlayHiddenByUser;refresh();if(next==0)flashSelectedFace();revealActiveChoice();});tools[i].setTag("portrait-tool-"+i);selectionTools.addView(tools[i],new LinearLayout.LayoutParams(0,dp(48),1));}
        controls.addView(selectionTools);
        hint=text("",12,MUTED);hint.setTag("portrait-hint");hint.setPadding(dp(4),0,dp(4),0);hint.setGravity(Gravity.CENTER);hint.setMaxLines(2);
        controls.addView(hint,new LinearLayout.LayoutParams(-1,dp(48)));

        LinearLayout regions=row();sizeRow=regions;TextView sizeLabel=text("大小",12,TEXT);regions.addView(sizeLabel,new LinearLayout.LayoutParams(dp(44),dp(48)));
        SeekBar size=new SeekBar(getContext());size.setTag("portrait-size");size.setMax(118);size.setProgress(20);tint(size);size.setContentDescription("画笔和祛痘范围");regions.addView(size,new LinearLayout.LayoutParams(0,dp(48),1));
        sizeValue=text("2.2%",12,ACCENT);sizeValue.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);regions.addView(sizeValue,new LinearLayout.LayoutParams(dp(44),dp(48)));
        size.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar b,int p,boolean user){if(user)stopSelectionFlash();radius=(p+2)/1000.0;sizeValue.setText(String.format(Locale.ROOT,"%.1f%%",radius*100));size.setContentDescription(String.format(Locale.ROOT,"画笔和祛痘范围 %.1f%%",radius*100));}public void onStartTrackingTouch(SeekBar b){dragging=true;photo.invalidate();}public void onStopTrackingTouch(SeekBar b){dragging=false;photo.invalidate();}});controls.addView(regions);
        toneControls=column();toneControls.setTag("portrait-tone-controls");LinearLayout scope=row();
        toneFace=button("仅脸部",()->chooseToneScope(false));toneFace.setTag("portrait-tone-scope-face");scope.addView(toneFace,new LinearLayout.LayoutParams(0,dp(48),1));
        toneBody=button("全身皮肤",()->chooseToneScope(true));toneBody.setTag("portrait-tone-scope-body");scope.addView(toneBody,new LinearLayout.LayoutParams(0,dp(48),1));
        toneManage=button("管理色卡",this::manageToneCards);toneManage.setTag("portrait-tone-manage");scope.addView(toneManage,new LinearLayout.LayoutParams(dp(80),dp(48)));toneControls.addView(scope);
        toneMore=PhotoWorkspaceUi.icon(getContext(),"more","更多肤色选项","portrait-tone-more",this::showMore);scope.addView(toneMore,new LinearLayout.LayoutParams(dp(48),dp(48)));
        toneRail=new HorizontalScrollView(getContext());toneRail.setTag("portrait-tone-swatches");toneRail.setHorizontalScrollBarEnabled(false);toneRail.setOverScrollMode(View.OVER_SCROLL_NEVER);toneCards=row();toneRail.addView(toneCards);toneControls.addView(toneRail,new LinearLayout.LayoutParams(-1,dp(88)));
        tonePreviewActions=row();tonePreviewActions.setTag("portrait-tone-preview-actions");
        Button continueTone=button("继续选色",()->openTonePicker(editedTone().presetId==SkinTone.ORIGINAL?SkinTone.byId(1).colorRGB:editedTone().colorRGB));continueTone.setTag("portrait-tone-preview-edit");tonePreviewActions.addView(continueTone,new LinearLayout.LayoutParams(0,dp(48),1));
        Button cancelTone=button("取消",this::cancelTonePreview);cancelTone.setTag("portrait-tone-preview-cancel");tonePreviewActions.addView(cancelTone,new LinearLayout.LayoutParams(0,dp(48),1));
        Button useTone=button("使用此色",this::confirmTonePreview);useTone.setTag("portrait-tone-preview-use");useTone.setTextColor(ACCENT);tonePreviewActions.addView(useTone,new LinearLayout.LayoutParams(0,dp(48),1));toneControls.addView(tonePreviewActions);controls.addView(toneControls);
        for(int i=0;i<sliders.length;i++){final int axis=i;LinearLayout line=row();labels[i]=text("",12,TEXT);line.addView(labels[i],new LinearLayout.LayoutParams(dp(80),dp(48)));sliders[i]=new SeekBar(getContext());sliders[i].setTag("portrait-axis-"+i);tint(sliders[i]);line.addView(sliders[i],new LinearLayout.LayoutParams(0,dp(48),1));values[i]=text("",12,ACCENT);values[i].setGravity(Gravity.END|Gravity.CENTER_VERTICAL);line.addView(values[i],new LinearLayout.LayoutParams(dp(44),dp(48)));rows[i]=line;controls.addView(line);
            sliders[i].setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar b,int p,boolean user){if(user&&!updating)adjust(axis,p);}public void onStartTrackingTouch(SeekBar b){showOverlay=!overlayHiddenByUser;stopSelectionFlash();select(overlayButton,showOverlay);gestureStart=snapshot();dragging=true;}public void onStopTrackingTouch(SeekBar b){dragging=false;if(!tonePreviewing)remember(gestureStart);gestureStart=null;changed(false);}});
        }

        lightPad=new PortraitLightPad(getContext(),new PortraitLightPad.Listener(){public void start(){gestureStart=snapshot();dragging=true;showOverlay=!overlayHiddenByUser;clearSelectionFlash();}public void change(int x,int y){setLightPosition(x,y);}public void end(boolean cancel){dragging=false;if(cancel&&gestureStart!=null)restore(gestureStart);else remember(gestureStart);gestureStart=null;changed(false);}});controls.addView(lightPad,new LinearLayout.LayoutParams(-1,dp(112)));
        LinearLayout axes=row();lightAxes=axes;for(cc.huevia.ncp.PortraitRetouch.Parameter axis:new cc.huevia.ncp.PortraitRetouch.Parameter[]{cc.huevia.ncp.PortraitRetouch.Parameter.LIGHT_X,cc.huevia.ncp.PortraitRetouch.Parameter.LIGHT_Y}){Button exact=button(axis.label,()->chooseRetouch(axis,false));exact.setTag("portrait-retouch-"+axis.name().toLowerCase(java.util.Locale.US));lightAxisTools.put(axis,exact);axes.addView(exact,new LinearLayout.LayoutParams(0,dp(48),1));}controls.addView(axes);
        skinRail=new HorizontalScrollView(getContext());skinRail.setTag("portrait-skin-tools");skinRail.setHorizontalScrollBarEnabled(false);skinRail.setOverScrollMode(View.OVER_SCROLL_NEVER);LinearLayout skinTools=row();
        Button naturalTool=PhotoWorkspaceUi.tool(getContext(),"自然精修","portrait-retouch-natural","face",this::naturalRetouch);retouchTools.put(cc.huevia.ncp.PortraitRetouch.Parameter.NATURAL,naturalTool);skinTools.addView(naturalTool,new LinearLayout.LayoutParams(toolWidth(),toolHeight()));
        skinToneTool=PhotoWorkspaceUi.tool(getContext(),"肤色","portrait-skin-tone","color",this::chooseTone);skinTools.addView(skinToneTool,new LinearLayout.LayoutParams(toolWidth(),toolHeight()));
        skinSmoothingTool=PhotoWorkspaceUi.tool(getContext(),"磨皮","portrait-skin-smoothing","smooth",this::chooseSkinSmoothing);skinSmoothingTool.setContentDescription("磨皮，自动淡化露出皮肤的细小瑕疵并保留纹理");skinTools.addView(skinSmoothingTool,new LinearLayout.LayoutParams(toolWidth(),toolHeight()));
        String[] skinIcons={"brightness","warmth","redness","smooth","texture"};
        for(int i=0;i<skinEffects.length;i++){final int parameter=i;skinEffects[i]=PhotoWorkspaceUi.tool(getContext(),(i==3?"磨皮":PARAMETER_LABELS[i]),"portrait-skin-effect-"+i,skinIcons[i],()->chooseSkinEffect(parameter));skinEffects[i].setContentDescription("涂抹皮肤"+PARAMETER_LABELS[i]);skinTools.addView(skinEffects[i],new LinearLayout.LayoutParams(toolWidth(),toolHeight()));}
        for(cc.huevia.ncp.PortraitRetouch.Parameter p:new cc.huevia.ncp.PortraitRetouch.Parameter[]{cc.huevia.ncp.PortraitRetouch.Parameter.TEXTURE,cc.huevia.ncp.PortraitRetouch.Parameter.EVENNESS,cc.huevia.ncp.PortraitRetouch.Parameter.SHINE}){Button b=PhotoWorkspaceUi.tool(getContext(),p.label,"portrait-retouch-"+p.name().toLowerCase(java.util.Locale.US),p==cc.huevia.ncp.PortraitRetouch.Parameter.TEXTURE?"texture":p==cc.huevia.ncp.PortraitRetouch.Parameter.EVENNESS?"skin-even":"shine-control",()->chooseRetouch(p,true));retouchTools.put(p,b);skinTools.addView(b,new LinearLayout.LayoutParams(toolWidth(),toolHeight()));}
        Button autoHeal=PhotoWorkspaceUi.tool(getContext(),"自动祛痘","portrait-auto-blemishes","heal",this::autoBlemishes);skinTools.addView(autoHeal,new LinearLayout.LayoutParams(toolWidth(),toolHeight()));
        skinRail.addView(skinTools);controls.addView(skinRail,new LinearLayout.LayoutParams(-1,toolHeight()));

        HorizontalScrollView rail=new HorizontalScrollView(getContext());primaryRail=rail;rail.setHorizontalScrollBarEnabled(false);rail.setOverScrollMode(View.OVER_SCROLL_NEVER);rail.setFillViewport(true);
        LinearLayout categories=row();categories.setGravity(Gravity.CENTER);categories.setTag("portrait-primary-tools");
        String[] effectIcons={"brightness","warmth","redness","smooth","texture","light","shadows"};
        for(int i=0;i<effects.length;i++){final int next=i;effects[i]=PhotoWorkspaceUi.tool(getContext(),PARAMETER_LABELS[i],"portrait-effect-"+i,effectIcons[i],()->chooseEffect(next));effects[i].setContentDescription(PARAMETER_NAMES[i]);categories.addView(effects[i],new LinearLayout.LayoutParams(toolWidth(),toolHeight()));}
        for(cc.huevia.ncp.PortraitRetouch.Parameter p:new cc.huevia.ncp.PortraitRetouch.Parameter[]{cc.huevia.ncp.PortraitRetouch.Parameter.EYE_DETAIL,cc.huevia.ncp.PortraitRetouch.Parameter.EYE_WHITE,cc.huevia.ncp.PortraitRetouch.Parameter.TEETH,cc.huevia.ncp.PortraitRetouch.Parameter.UNDER_EYE,cc.huevia.ncp.PortraitRetouch.Parameter.FILL}){Button b=PhotoWorkspaceUi.tool(getContext(),p.label,"portrait-retouch-"+p.name().toLowerCase(java.util.Locale.US),p==cc.huevia.ncp.PortraitRetouch.Parameter.FILL?"light":p==cc.huevia.ncp.PortraitRetouch.Parameter.TEETH?"teeth":p==cc.huevia.ncp.PortraitRetouch.Parameter.UNDER_EYE?"under-eye":p==cc.huevia.ncp.PortraitRetouch.Parameter.EYE_WHITE?"eye-clean":"eye",()->chooseRetouch(p,false));retouchTools.put(p,b);categories.addView(b,new LinearLayout.LayoutParams(toolWidth(),toolHeight()));}
        tools[3]=PhotoWorkspaceUi.tool(getContext(),"祛痘","portrait-tool-3","heal",()->chooseMode(1));categories.addView(tools[3],new LinearLayout.LayoutParams(toolWidth(),toolHeight()));
        maskCategory=PhotoWorkspaceUi.tool(getContext(),"选区","portrait-selection-tools","face",()->chooseMode(2));categories.addView(maskCategory,new LinearLayout.LayoutParams(toolWidth(),toolHeight()));
        rail.addView(categories);controls.addView(rail,new LinearLayout.LayoutParams(-1,toolHeight()));
        rail.addOnLayoutChangeListener((v,l,t,r,b,oldL,oldT,oldR,oldB)->{if(r-l!=oldR-oldL)revealActiveChoice();});
        ScrollView scroll=new ScrollView(getContext());dock=scroll;scroll.setFillViewport(false);scroll.setVerticalScrollBarEnabled(false);scroll.setTag("portrait-dock");scroll.addView(controls);
        LinearLayout panel=column();dockPanel=panel;panel.setTag("portrait-dock-panel");panel.setBackgroundColor(PANEL);panel.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout entries=row();groupEntries=entries;entries.setTag("portrait-entry-tools");entries.setPadding(dp(8),0,dp(8),0);
        LinearLayout skinEntry=PhotoWorkspaceUi.toolEntry(getContext(),"皮肤","portrait-entry-skin",AppIcon.Kind.TINT,this::chooseTone);skinEntry.setContentDescription("皮肤，自动识别全部露出皮肤并调整肤色");entries.addView(skinEntry,new LinearLayout.LayoutParams(PhotoWorkspaceUi.entryWidth(getContext()),-1));
        LinearLayout faceEntry=PhotoWorkspaceUi.toolEntry(getContext(),"面部","portrait-entry-face",AppIcon.Kind.PERSON,this::chooseFaceGroup);faceEntry.setContentDescription("面部，选择人脸进行面部修饰");entries.addView(faceEntry,new LinearLayout.LayoutParams(PhotoWorkspaceUi.entryWidth(getContext()),-1));
        if(!regionMode){LinearLayout bodyEntry=PhotoWorkspaceUi.toolEntry(getContext(),"塑形","portrait-entry-body",AppIcon.Kind.BODY,this::chooseBody);bodyEntry.setContentDescription("塑形，瘦身、瘦腿和腿部拉长");entries.addView(bodyEntry,new LinearLayout.LayoutParams(PhotoWorkspaceUi.entryWidth(getContext()),-1));}
        LinearLayout natural=PhotoWorkspaceUi.toolEntry(getContext(),"自然精修","portrait-entry-natural",AppIcon.Kind.PERSON,this::naturalRetouch);entries.addView(natural,new LinearLayout.LayoutParams(PhotoWorkspaceUi.entryWidth(getContext()),-1));
        HorizontalScrollView entryScroll=new HorizontalScrollView(getContext());entryScroll.setHorizontalScrollBarEnabled(false);entryScroll.addView(entries);panel.addView(entryScroll,new LinearLayout.LayoutParams(-1,PhotoWorkspaceUi.entryHeight(getContext())));
        body.addView(panel,landscape?new LinearLayout.LayoutParams(dp(320),-1):new LinearLayout.LayoutParams(-1,dockHeight()));
        body.addOnLayoutChangeListener((v,l,t,r,b,oldL,oldT,oldR,oldB)->layoutWorkspace(body,stage,panel));
        root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){Insets safe=insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());root.setPadding(safe.left,safe.top,safe.right,safe.bottom);}else root.setPadding(insets.getStableInsetLeft(),insets.getStableInsetTop(),insets.getStableInsetRight(),insets.getStableInsetBottom());body.post(()->layoutWorkspace(body,stage,panel));return insets;});
        PhotoPrismaStyle.workspace(root,initial);setContentView(root);if(getWindow()!=null){getWindow().setBackgroundDrawableResource(android.R.color.transparent);getWindow().setLayout(-1,-1);}root.requestApplyInsets();refresh();changed(false);
    }
    /** Adapt the existing views when the hosting Activity handles rotation without recreation. */
    private void layoutWorkspace(LinearLayout body,FrameLayout stage,LinearLayout controls){
        if(disposed)return;int width=body.getWidth(),height=body.getHeight();if(width<1||height<2)return;
        boolean side=width>height&&width>=dp(480);int orientation=side?LinearLayout.HORIZONTAL:LinearLayout.VERTICAL;
        boolean structureChanged=body.getOrientation()!=orientation;
        if(structureChanged)body.setOrientation(orientation);
        LinearLayout.LayoutParams stageParams=(LinearLayout.LayoutParams)stage.getLayoutParams();
        int stageWidth=side?0:-1,stageHeight=side?-1:0;
        if(stageParams.width!=stageWidth||stageParams.height!=stageHeight||stageParams.weight!=1){stage.setLayoutParams(new LinearLayout.LayoutParams(stageWidth,stageHeight,1));}
        int controlsWidth=side?Math.min(dp(320),Math.max(1,Math.round(width*.44f))):-1;
        int controlsHeight=side?-1:Math.max(1,Math.min(dockHeight(),height/2));
        LinearLayout.LayoutParams controlsParams=(LinearLayout.LayoutParams)controls.getLayoutParams();
        boolean controlsChanged=controlsParams.width!=controlsWidth||controlsParams.height!=controlsHeight||controlsParams.weight!=0;
        if(controlsChanged)controls.setLayoutParams(new LinearLayout.LayoutParams(controlsWidth,controlsHeight));
        photo.invalidate();if(structureChanged||controlsChanged)revealActiveChoice();
    }
    private int toolWidth(){return dp(activity.getResources().getConfiguration().fontScale>=1.2f?80:72);}
    private int toolHeight(){return dp(activity.getResources().getConfiguration().fontScale>=1.2f?84:72);}
    private boolean lightingControl(){return activeRetouch==cc.huevia.ncp.PortraitRetouch.Parameter.FILL||activeRetouch==cc.huevia.ncp.PortraitRetouch.Parameter.LIGHT_X||activeRetouch==cc.huevia.ncp.PortraitRetouch.Parameter.LIGHT_Y;}
    private boolean hasSliderSelection(){
        if(choosingGroup)return false;
        Button selectedTool;
        if(activeRetouch!=null)selectedTool=lightAxisTools.containsKey(activeRetouch)?lightAxisTools.get(activeRetouch):retouchTools.get(activeRetouch);
        else if(mode==0)selectedTool=activeParameter>=0&&activeParameter<effects.length?effects[activeParameter]:null;
        else if(mode==3)selectedTool=editedTone().presetId!=SkinTone.ORIGINAL&&!photoSampling?skinToneTool:null;
        else if(mode==4)selectedTool=regionMode&&activeSkinParameter>=0&&activeSkinParameter<skinEffects.length?skinEffects[activeSkinParameter]:null;
        else selectedTool=mode==5?skinSmoothingTool:null;
        return selectedTool!=null&&selectedTool.isSelected();
    }
    private int dockHeight(){
        if(choosingGroup)return PhotoWorkspaceUi.entryHeight(getContext());boolean large=activity.getResources().getConfiguration().fontScale>=1.2f;int height;
        if(mode>=3)height=mode>=4?(large?144:132):(photoSampling||tonePreviewing?116:196)+(large?84:72);
        else height=(large?144:132)+(mode==2?48:0);
        if((mode==0||mode>=3)&&!hasSliderSelection())height-=48;
        if(lightingControl())height+=160;return dp(height);
    }

    private void chooseEffect(int parameter){activeRetouch=null;
        cancelTonePreview();photoSampling=false;clearSelectionFlash();activeParameter=parameter;mode=0;adding=false;showOverlay=!overlayHiddenByUser;tool=0;refresh();revealActiveChoice();
    }
    private void chooseMode(int next){activeRetouch=null;
        cancelTonePreview();photoSampling=false;clearSelectionFlash();mode=next;adding=false;showOverlay=!overlayHiddenByUser;tool=next==1?3:0;refresh();if(next==2)flashSelectedFace();revealActiveChoice();
    }
    private void chooseFaceGroup(){
        if(!choosingGroup&&mode<3)return;
        cancelTonePreview();choosingGroup=false;photoSampling=false;clearSelectionFlash();activeRetouch=null;mode=lastFaceMode;adding=false;showOverlay=!overlayHiddenByUser;tool=mode==1?3:0;
        if(!portrait.bodyShape.isNeutral()){rendered=null;changed(false);}else{refresh();refreshApplyAvailability();showPreviewStatus();}dock.scrollTo(0,0);revealActiveChoice();
    }
    private void chooseBody(){
        if(disposed||regionMode||bodyDialog!=null||analysisBusy||globalSkinBusy)return;
        if(completedPreview==null||!completedPreview.equals(snapshot())||rendered==null){status.setText("预览中，请稍后打开塑形");return;}
        clearSelectionFlash();final PhotoPortrait frozen=portrait;final long token=revision;
        final Bitmap entering=rendered.copy(Bitmap.Config.ARGB_8888,false);if(entering==null){status.setText("塑形照片准备失败，请重试");return;}
        bodyDialog=new PhotoBodyDialog(activity,entering,frozen.bodyShape,(next,interactive)->{if(disposed||revision!=token)throw new java.io.IOException("人像设置已变化，请重新打开塑形。");return portraitRenderer.render(frozen.withBodyShape(next),interactive);},next->{if(!disposed&&revision==token)replace(portrait.withBodyShape(next),true);});
        bodyDialog.setAnalysisSource(analysis);bodyDialog.setOnDismissListener(d->{bodyDialog=null;entering.recycle();});bodyDialog.show();PhotoEditorTypography.apply(bodyDialog);
    }
    private void showGroupEntries(){
        if(choosingGroup)return;
        if(mode<3)lastFaceMode=mode;
        cancelTonePreview();boolean finishDrag=dragging||gestureStart!=null;
        if(finishDrag){dragging=false;remember(gestureStart);gestureStart=null;}
        photoSampling=false;clearSelectionFlash();adding=false;showOverlay=!overlayHiddenByUser;tool=0;photo.cancelEditingGesture();choosingGroup=true;
        if(finishDrag||!portrait.bodyShape.isNeutral()){rendered=null;changed(false);}else{refresh();refreshApplyAvailability();showPreviewStatus();}
    }
    private void revealActiveChoice(){
        if(primaryRail==null||disposed||choosingGroup)return;
        if(lightAxisTools.containsKey(activeRetouch)){PhotoWorkspaceUi.revealChoice(primaryRail,retouchTools.get(cc.huevia.ncp.PortraitRetouch.Parameter.FILL));return;}
        if(activeRetouch!=null&&retouchTools.get(activeRetouch)!=null){PhotoWorkspaceUi.revealChoice(mode>=3?skinRail:primaryRail,retouchTools.get(activeRetouch));return;}
        if(mode>=3){PhotoWorkspaceUi.revealChoice(skinRail,mode==5?skinSmoothingTool:mode==3?skinToneTool:skinEffects[activeSkinParameter]);return;}
        View choice=mode==0?effects[activeParameter]:mode==1?tools[3]:maskCategory;
        if(choice!=null)PhotoWorkspaceUi.revealChoice(primaryRail,choice);
    }
    private void showMore(){
        cancelTonePreview();photoSampling=false;
        View anchor=mode==3&&!tonePerFace?toneMore:getWindow().getDecorView().findViewWithTag("portrait-more");PopupMenu menu=new PopupMenu(getContext(),anchor);
        PhotoPortrait.Face current=face();
        menu.getMenu().add(0,7,0,"逐处撤销祛痘").setEnabled(!portrait.heals().isEmpty());
        if(mode==3){menu.getMenu().add(0,6,0,"管理个人色卡").setEnabled(!toneSwatches.load().isEmpty());menu.getMenu().add(0,5,0,tonePerFace?"全图肤色调节":"逐人肤色调节（高级）");}
        menu.getMenu().add(0,1,0,current!=null&&!current.enabled?"启用此人脸":"停用此人脸").setEnabled(current!=null);
        menu.getMenu().add(0,2,1,"删除此人脸").setEnabled(current!=null);
        menu.getMenu().add(0,3,2,"撤回上一处祛痘").setEnabled(!portrait.heals().isEmpty());
        menu.getMenu().add(0,4,3,"重置人像精修");
        menu.setOnMenuItemClickListener(item->{switch(item.getItemId()){case 7:showHealingHistory();break;case 1:toggleFace();break;case 2:deleteFace();break;case 3:deleteHeal();break;case 4:confirm("重置人像精修？","清除本次照片的肤色、磨皮、面部调整、塑形、选区修正和祛痘。仍可撤销。","重置",()->{selected=-1;replace(PhotoPortrait.NONE,true);});break;case 5:switchToneEditing();break;case 6:manageToneCards();break;default:return false;}return true;});
        menu.show();
    }
    @Override public void show(){super.show();if(getWindow()!=null)getWindow().setLayout(-1,-1);}
    @Override public void onWindowFocusChanged(boolean focus){super.onWindowFocusChanged(focus);if(!focus){compare=false;if(dragging){dragging=false;if(gestureStart!=null){Snapshot before=gestureStart;gestureStart=null;restore(before);}}photo.invalidate();}}
    @Override public void dismiss(){
        if(!disposed){disposed=true;photoSampling=false;toneTask++;globalSkinTask++;if(bodyDialog!=null){bodyDialog.dismiss();bodyDialog=null;}if(brushDialog!=null){brushDialog.dismiss();brushDialog=null;}if(tonePicker!=null){tonePicker.dismiss();tonePicker=null;}clearSelectionFlash();revision++;completedPreview=null;refreshApplyAvailability();if(decision!=null){decision.dismiss();decision=null;}queue.close();maskQueue.close();worker.shutdownNow();auxiliary.execute(()->analysis.recycle());auxiliary.shutdown();photo.invalidate();if(rendered!=null){rendered.recycle();rendered=null;}if(overlay!=null){overlay.recycle();overlay=null;}}
        super.dismiss();
    }
    private PhotoPortrait.Face face(){return selected>=0&&selected<portrait.faces().size()?portrait.faces().get(selected):null;}
    private Snapshot snapshot(){if(regionMode){if(!region.portrait.equals(portrait))region=region.withPortrait(portrait);if(preparedGlobalSkinMask!=null&&region.skinMask!=preparedGlobalSkinMask)region=region.withSkinMask(preparedGlobalSkinMask);}return new Snapshot(portrait,region);}
    private Snapshot withPreparedSkin(Snapshot value){PhotoPortrait p=withPreparedSkin(value.portrait);AdjustmentRegion r=value.region==null?null:value.region.withPortrait(p);if(r!=null&&preparedGlobalSkinMask!=null)r=r.withSkinMask(preparedGlobalSkinMask);return new Snapshot(p,r);}
    private void restore(Snapshot value){Snapshot prepared=withPreparedSkin(value);portrait=prepared.portrait;region=prepared.region;}
    private void remember(Snapshot old){if(old==null)return;old=withPreparedSkin(old);if(old.equals(snapshot()))return;undo.addLast(old);while(undo.size()>32)undo.removeFirst();redo.clear();}
    private void replace(PhotoPortrait next,boolean history){Snapshot old=snapshot();portrait=withPreparedSkin(next);revision++;if(history)remember(old);if(selected>=portrait.faces().size())selected=portrait.faces().isEmpty()?-1:portrait.faces().size()-1;changed(false);}
    private void replaceRegion(AdjustmentRegion next,boolean history){Snapshot old=snapshot();region=next;portrait=withPreparedSkin(next.portrait);if(preparedGlobalSkinMask!=null)region=region.withSkinMask(preparedGlobalSkinMask);revision++;if(history)remember(old);normalize();changed(false);}
    /** Idle is not success: only the latest completed final frame certifies these settings. */
    private void refreshApplyAvailability(){if(apply==null)return;boolean ready=(portrait.skinSmoothing==0&&!portrait.retouch.hasSkinEffect()&&portrait.globalTone.isNeutral()&&(!regionMode||region.skinSettings.isNeutral()))||portrait.globalSkinMask!=null;boolean available=!disposed&&!analysisBusy&&!globalSkinBusy&&ready&&!photoSampling&&!tonePreviewing&&completedPreview!=null&&completedPreview.beforeBody==beforeBody()&&completedPreview.equals(snapshot());apply.setEnabled(available);apply.setAlpha(available?1:.45f);}
    private void changed(boolean interactive){if(disposed||status==null)return;clearSelectionFlash();completedPreview=null;notice=null;refresh();status.setText(globalSkinBusy?"正在识别露出皮肤…":"预览中…");status.setOnClickListener(null);refreshApplyAvailability();Snapshot value=snapshot();queue.offer(new Snapshot(value.portrait,value.region,beforeBody()),interactive||dragging);}
    private void undo(){if(tonePreviewStart!=null){cancelTonePreview();return;}if(undo.isEmpty())return;redo.addLast(snapshot());restore(undo.removeLast());revision++;normalize();changed(false);}
    private void redo(){if(tonePreviewStart!=null){cancelTonePreview();return;}if(redo.isEmpty())return;undo.addLast(snapshot());restore(redo.removeLast());revision++;normalize();changed(false);}
    private void normalize(){portrait=withPreparedSkin(portrait);if(selected>=portrait.faces().size())selected=portrait.faces().size()-1;if(selected<0&&!portrait.faces().isEmpty())selected=0;}
    private void chooseFace(){stopSelectionFlash();PopupMenu menu=new PopupMenu(getContext(),selection);for(int i=0;i<portrait.faces().size();i++){PhotoPortrait.Face f=portrait.faces().get(i);menu.getMenu().add(0,i,i,"人脸 "+(i+1)+(f.enabled?"":" · 停用")).setCheckable(true).setChecked(i==selected);}if(portrait.faces().isEmpty())menu.getMenu().add("先自动选脸或手动添加").setEnabled(false);else menu.getMenu().setGroupCheckable(0,true,true);menu.setOnMenuItemClickListener(item->{selectFace(item.getItemId());return true;});menu.show();}
    private void selectFace(int index){if(index<0||index>=portrait.faces().size())return;cancelTonePreview();photoSampling=false;toneTask++;selected=index;adding=false;tool=mode==1?3:0;showOverlay=!overlayHiddenByUser;refresh();flashSelectedFace();}
    private void deleteFace(){if(face()==null)return;replace(portrait.removeFace(selected),true);}
    private void deleteHeal(){if(!portrait.heals().isEmpty())replace(portrait.removeHeal(portrait.heals().size()-1),true);}
    private void toggleFace(){PhotoPortrait.Face value=face();if(value!=null)replace(portrait.withFace(selected,value.withEnabled(!value.enabled)),true);}
    private void adjust(int axis,int progress){if(analysisBusy||!hasSliderSelection())return;PhotoPortrait.Face value=face();if(mode==3?!canEditTone():mode==4?!regionMode:mode==5?globalSkinBusy||portrait.globalSkinMask==null:value==null)return;showOverlay=!overlayHiddenByUser;Snapshot old=snapshot();if(activeRetouch!=null){int amount=progress+activeRetouch.min;cc.huevia.ncp.PortraitRetouch next=retouchSettings().with(activeRetouch,amount);portrait=mode>=3?portrait.withRetouch(next):portrait.withFace(selected,value.withRetouch(next));}else if(mode==5){portrait=portrait.withSkinSmoothing(progress);}else if(mode==3){PhotoPortrait.Tone tone=editedTone();portrait=withEditedTone(new PhotoPortrait.Tone(tone.presetId,tone.colorRGB,progress/100.0,tone.body));}else{int p=mode==4?activeSkinParameter:parameter(axis);int[] v=settings(mode==4?region.skinSettings:value.settings);v[p]=progress-(p==0||p==1||p==2||p==5?100:0);PhotoPortrait.Settings next=new PhotoPortrait.Settings(v[0],v[1],v[2],v[3],v[4],v[5],v[6]);if(mode==4)region=region.withSkinSettings(next);else portrait=portrait.withFace(selected,value.withSettings(next));}revision++;if(!dragging&&!tonePreviewing)remember(old);changed(dragging);}
    private static int[] settings(PhotoPortrait.Settings v){return new int[]{v.brightness,v.warmth,v.redness,v.smoothing,v.texture,v.light,v.shadows};}
    private int parameter(int axis){return activeParameter;}
    private void refresh(){
        if(selection==null)return;updating=true;PhotoPortrait.Face value=face();selection.setText(value==null?"选择人脸":"人脸 "+(selected+1)+(value.enabled?" / "+portrait.faces().size():" · 停用"));select(selection,value!=null);selection.setContentDescription(value==null?"选择人脸，点按切换人物":"已选中"+selection.getText()+"，点按切换人物");
        boolean adjustment=mode==0,selectionMode=mode==2;
        groupEntries.setVisibility(choosingGroup?View.VISIBLE:View.GONE);((View)groupEntries.getParent()).setVisibility(choosingGroup?View.VISIBLE:View.GONE);dock.setVisibility(choosingGroup?View.GONE:View.VISIBLE);
        cancelButton.setVisibility(choosingGroup?View.VISIBLE:View.GONE);backButton.setVisibility(choosingGroup?View.GONE:View.VISIBLE);workspaceTitle.setText((choosingGroup?"人像":mode>=3?"皮肤":"面部")+(!choosingGroup&&beforeBody()?" · 塑形前定位":"")+(regionMode?" · "+region.name:""));
        primaryRail.setVisibility(choosingGroup||mode>=3?View.GONE:View.VISIBLE);
        skinRail.setVisibility(!choosingGroup&&mode>=3?View.VISIBLE:View.GONE);select(skinToneTool,mode==3);skinSmoothingTool.setVisibility(regionMode?View.GONE:View.VISIBLE);select(skinSmoothingTool,mode==5&&activeRetouch==null);for(int i=0;i<skinEffects.length;i++){skinEffects[i].setVisibility(regionMode?View.VISIBLE:View.GONE);select(skinEffects[i],mode==4&&activeSkinParameter==i);}
        faceBar.setVisibility(choosingGroup||mode>=4||mode==3&&!tonePerFace?View.GONE:View.VISIBLE);
        boolean selectionAvailable=face()!=null||preparedGlobalSkinMask!=null||regionMode&&region.hasSelection();
        overlayButton.setVisibility(choosingGroup&&!selectionAvailable?View.GONE:View.VISIBLE);overlayButton.setEnabled(selectionAvailable);
        overlayButton.setContentDescription(showOverlay?"隐藏选区，保留调整":"显示选区");overlayButton.setTooltipText(overlayButton.getContentDescription());
        brushButton.setVisibility(!choosingGroup&&(regionMode||paintRequest!=null)?View.VISIBLE:View.GONE);brushButton.setEnabled(!analysisBusy&&!globalSkinBusy&&!photoSampling&&!tonePreviewing);brushButton.setContentDescription(regionMode?"编辑"+region.name+"涂抹范围":"涂抹局部调节范围");
        for(int i=0;i<3;i++){select(tools[i],selectionMode&&tool==i);tools[i].setEnabled(i==0||value!=null);}
        for(int i=0;i<effects.length;i++)select(effects[i],adjustment&&activeRetouch==null&&activeParameter==i);
        select(tools[3],mode==1);select(maskCategory,selectionMode);
        for(java.util.Map.Entry<cc.huevia.ncp.PortraitRetouch.Parameter,Button> entry:retouchTools.entrySet()){select(entry.getValue(),!choosingGroup&&(entry.getKey()==activeRetouch||entry.getKey()==cc.huevia.ncp.PortraitRetouch.Parameter.FILL&&lightingControl()));if(entry.getKey()==cc.huevia.ncp.PortraitRetouch.Parameter.TEXTURE)entry.getValue().setVisibility(regionMode?View.GONE:View.VISIBLE);}
        for(java.util.Map.Entry<cc.huevia.ncp.PortraitRetouch.Parameter,Button> entry:lightAxisTools.entrySet())select(entry.getValue(),!choosingGroup&&entry.getKey()==activeRetouch);
        toneControls.setVisibility(!choosingGroup&&mode==3?View.VISIBLE:View.GONE);toneControls.getChildAt(0).setVisibility(tonePreviewing||photoSampling?View.GONE:View.VISIBLE);
        PhotoPortrait.Tone tone=editedTone();
        toneFace.setText(tonePerFace?"仅脸部":"全部露出皮肤");toneFace.setTag(tonePerFace?"portrait-tone-scope-face":"portrait-tone-global-scope");
        toneManage.setVisibility(tonePerFace?View.VISIBLE:View.GONE);toneMore.setVisibility(tonePerFace?View.GONE:View.VISIBLE);
        toneBody.setText(tonePerFace?"全身皮肤":globalSkinBusy?"识别中…":"重新识别");toneBody.setTag(tonePerFace?"portrait-tone-scope-body":"portrait-tone-rescan");
        select(toneFace,!tonePerFace||!tone.body);select(toneBody,tonePerFace&&tone.body);
        toneFace.setEnabled(tonePerFace&&value!=null&&value.enabled&&!analysisBusy&&!photoSampling&&!tonePreviewing);
        toneBody.setEnabled((tonePerFace?value!=null&&value.enabled&&!analysisBusy:!globalSkinBusy)&&!photoSampling&&!tonePreviewing);
        toneFace.setAlpha(!tonePerFace||toneFace.isEnabled()?1:.4f);toneBody.setAlpha(toneBody.isEnabled()?1:.4f);toneRail.setVisibility(tonePreviewing||photoSampling?View.GONE:View.VISIBLE);tonePreviewActions.setVisibility(tonePreviewing&&!photoSampling?View.VISIBLE:View.GONE);refreshToneCards();
        selectionTools.setVisibility(selectionMode?View.VISIBLE:View.GONE);
        sizeRow.setVisibility(mode==1||(selectionMode&&tool!=0)?View.VISIBLE:View.GONE);
        auto.setEnabled(!analysisBusy);auto.setAlpha(analysisBusy?.45f:1);
        undoButton.setEnabled(!undo.isEmpty()&&!tonePreviewing);undoButton.setAlpha(undoButton.isEnabled()?1:.35f);
        redoButton.setEnabled(!redo.isEmpty()&&!tonePreviewing);redoButton.setAlpha(redoButton.isEnabled()?1:.35f);select(overlayButton,showOverlay);
        String instruction=adding?"在照片上拖出人脸范围，松手确认":tool==1?"在皮肤上涂抹补选 · 双指缩放和移动":tool==2?"涂抹擦除选区 · 双指缩放和移动":tool==3?"点按瑕疵自动融合 · 双指缩放查看细节":value==null?"先自动选脸，或点 + 手动添加":"点按人脸切换人物 · 双指缩放和移动";
        if(mode==3&&!tonePerFace)instruction="自动调整整张照片露出的皮肤 · 双指缩放查看细节";
        if(mode==5)instruction="自动淡化全部露出皮肤的细小瑕疵，保留纹理 · 双指缩放查看";
        if(photoSampling)instruction="点按照片取色 · 点此取消取色";
        if(mode==4)instruction="仅调整涂抹范围内自动识别的皮肤 · 双指缩放查看细节";
        hint.setText(instruction);hint.setVisibility(!choosingGroup&&((selectionMode&&tool==0)||photoSampling||(mode==3&&tonePerFace&&value==null))?View.VISIBLE:View.GONE);hint.setOnClickListener(photoSampling?v1->cancelPhotoSampling():null);hint.setClickable(photoSampling);photo.setContentDescription(choosingGroup?"人像精修照片。选择皮肤、面部或塑形工具，双指缩放查看细节。":"人像精修照片。"+(mode>=3&&(mode>=4||!tonePerFace)?regionMode?region.name+"涂抹皮肤调节。":"全图肤色调节。":value==null?"未选择人脸。":"已选中人脸 "+(selected+1)+(value.enabled?"。":"，已停用。"))+instruction);
        int[] v=settings(mode==4&&regionMode?region.skinSettings:value==null?PhotoPortrait.Settings.NONE:value.settings);
        for(int i=0;i<sliders.length;i++){
            rows[i].setVisibility(hasSliderSelection()?View.VISIBLE:View.GONE);
            if(activeRetouch!=null){labels[i].setText(activeRetouch.label);sliders[i].setMax(activeRetouch.max-activeRetouch.min);sliders[i].setProgress(retouchSettings().get(activeRetouch)-activeRetouch.min);sliders[i].setEnabled(mode>=3?!analysisBusy&&!globalSkinBusy&&portrait.globalSkinMask!=null:value!=null&&value.enabled&&!analysisBusy&&(activeRetouch==cc.huevia.ncp.PortraitRetouch.Parameter.FILL||activeRetouch==cc.huevia.ncp.PortraitRetouch.Parameter.LIGHT_X||activeRetouch==cc.huevia.ncp.PortraitRetouch.Parameter.LIGHT_Y||value.landmarks!=null));values[i].setText(Integer.toString(retouchSettings().get(activeRetouch)));sliders[i].setContentDescription(activeRetouch.label+"，"+values[i].getText());continue;}
            if(mode==5){labels[i].setText("磨皮");sliders[i].setMax(100);sliders[i].setProgress(portrait.skinSmoothing);sliders[i].setEnabled(!globalSkinBusy&&portrait.globalSkinMask!=null);values[i].setText(Integer.toString(portrait.skinSmoothing));sliders[i].setContentDescription("皮肤磨皮强度，"+portrait.skinSmoothing);continue;}
            if(mode==3){labels[i].setText("强度");sliders[i].setMax(100);sliders[i].setProgress((int)Math.round(tone.amount*100));sliders[i].setEnabled(canEditTone()&&tone.presetId!=SkinTone.ORIGINAL&&!photoSampling);values[i].setText(Integer.toString(sliders[i].getProgress()));sliders[i].setContentDescription("肤色强度，"+values[i].getText());continue;}
            int p=mode==4?activeSkinParameter:parameter(i),offset=p==0||p==1||p==2||p==5?100:0;
            labels[i].setText(PARAMETER_LABELS[p]);
            sliders[i].setMax(offset==100?200:100);sliders[i].setProgress(v[p]+offset);sliders[i].setEnabled(mode==4?regionMode:value!=null&&value.enabled);
            values[i].setText(offset==100?String.format(Locale.ROOT,"%+d",v[p]):Integer.toString(v[p]));sliders[i].setContentDescription((mode==4?"涂抹皮肤"+PARAMETER_LABELS[p]:PARAMETER_NAMES[p])+"，"+values[i].getText());
        }
        boolean lighting=lightingControl();lightPad.setVisibility(!choosingGroup&&lighting?View.VISIBLE:View.GONE);lightAxes.setVisibility(!choosingGroup&&lighting?View.VISIBLE:View.GONE);lightPad.setEnabled(value!=null&&value.enabled&&!analysisBusy);lightPad.position(retouchSettings().get(cc.huevia.ncp.PortraitRetouch.Parameter.LIGHT_X),retouchSettings().get(cc.huevia.ncp.PortraitRetouch.Parameter.LIGHT_Y));

        updating=false;requestMask();photo.invalidate();
        if(workspaceBody!=null&&workspaceStage!=null&&dockPanel!=null)layoutWorkspace(workspaceBody,workspaceStage,dockPanel);
    }
    private void chooseTone(){activeRetouch=null;if(!choosingGroup&&mode==3)return;if(mode<3)lastFaceMode=mode;cancelTonePreview();choosingGroup=false;photoSampling=false;clearSelectionFlash();mode=3;tool=0;adding=false;showOverlay=!overlayHiddenByUser;if(!portrait.bodyShape.isNeutral()){rendered=null;changed(false);}else{refresh();refreshApplyAvailability();showPreviewStatus();}dock.scrollTo(0,0);revealActiveChoice();if(!tonePerFace)ensureGlobalSkin(false);}
    private cc.huevia.ncp.PortraitRetouch retouchSettings(){return mode>=3?portrait.retouch:face()==null?cc.huevia.ncp.PortraitRetouch.NONE:face().retouch;}
    private void chooseRetouch(cc.huevia.ncp.PortraitRetouch.Parameter parameter,boolean skin){cancelTonePreview();photoSampling=false;clearSelectionFlash();activeRetouch=parameter;mode=skin?5:0;choosingGroup=false;adding=false;showOverlay=!overlayHiddenByUser;tool=0;refresh();revealActiveChoice();if(skin){ensureGlobalSkin(false);if(parameter==cc.huevia.ncp.PortraitRetouch.Parameter.EVENNESS&&portrait.faces().isEmpty())prepareRetouchFaces();}else if(face()==null||face().landmarks==null)prepareRetouchFaces();}
    private void prepareRetouchFaces(){
        if(disposed||analysisBusy)return;analysisBusy=true;final long token=revision;final List<PhotoPortrait.Face> existing=portrait.faces();refresh();refreshApplyAvailability();status.setText("正在定位面部细节…");
        auxiliary.execute(()->{List<PhotoPortrait.Face> found=null;try{found=existing.isEmpty()?cc.huevia.album.PhotoPersonAnalysis.analyze(activity.getApplicationContext(),analysis,()->disposed||token!=revision).faces:PhotoFaceSkinMask.refine(activity.getApplicationContext(),analysis,PhotoFaceLandmarks.refine(activity.getApplicationContext(),analysis,existing,()->disposed||token!=revision),()->disposed||token!=revision);}catch(Exception|LinkageError|OutOfMemoryError ignored){}final List<PhotoPortrait.Face> result=found;main.post(()->{if(disposed)return;analysisBusy=false;if(token!=revision){changed(false);return;}if(result==null||result.isEmpty()){status.setText("未定位到清晰五官，可自动选脸或手动调整脸部范围。");refresh();refreshApplyAvailability();return;}if(selected<0)selected=0;replace(portrait.withFaces(result),false);});});
    }
    private void setLightPosition(int x,int y){PhotoPortrait.Face f=face();if(f==null)return;portrait=portrait.withFace(selected,f.withRetouch(f.retouch.with(cc.huevia.ncp.PortraitRetouch.Parameter.LIGHT_X,x).with(cc.huevia.ncp.PortraitRetouch.Parameter.LIGHT_Y,y)));revision++;changed(true);}
    private void naturalRetouch(){
        final int naturalAmount=portrait.retouch.get(cc.huevia.ncp.PortraitRetouch.Parameter.NATURAL)>0?portrait.retouch.get(cc.huevia.ncp.PortraitRetouch.Parameter.NATURAL):50;
        if(disposed||analysisBusy||globalSkinBusy)return;cancelTonePreview();activeRetouch=cc.huevia.ncp.PortraitRetouch.Parameter.NATURAL;choosingGroup=false;mode=5;analysisBusy=true;final long token=revision;refresh();refreshApplyAvailability();status.setText("正在准备自然精修…");
        auxiliary.execute(()->{cc.huevia.album.PhotoPersonAnalysis.Result result=null;try{result=cc.huevia.album.PhotoPersonAnalysis.analyze(activity.getApplicationContext(),analysis,()->disposed||token!=revision);}catch(Exception|LinkageError|OutOfMemoryError ignored){}final cc.huevia.album.PhotoPersonAnalysis.Result found=result;main.post(()->{if(disposed)return;analysisBusy=false;if(token!=revision){changed(false);return;}if(found==null){status.setText("识别未完成，请重试。");refreshApplyAvailability();return;}preparedGlobalSkinMask=found.skin;globalSkinAttempted=true;globalSkinEmpty=emptySkinMask(found.skin);PhotoPortrait next=portrait.withGlobalSkinMask(found.skin);if(next.faces().isEmpty())next=next.withFaces(found.faces);selected=next.faces().isEmpty()?-1:0;replace(next.withRetouch(next.retouch.with(cc.huevia.ncp.PortraitRetouch.Parameter.NATURAL,naturalAmount)),true);});});
    }
    private void autoBlemishes(){
        if(disposed||analysisBusy||globalSkinBusy)return;if(portrait.globalSkinMask==null){ensureGlobalSkin(false);return;}if(portrait.heals().size()>=PhotoPortrait.MAX_HEALS){status.setText("祛痘记录已满，请先移除一处。");return;}analysisBusy=true;final long token=revision;final PhotoPortrait frozen=portrait;refreshApplyAvailability();status.setText("正在寻找细小红色瑕疵…");
        auxiliary.execute(()->{List<PhotoPortrait.Heal> result=null;try{result=cc.huevia.album.PhotoAutoBlemishes.detect(analysis,frozen.globalSkinMask,frozen.heals(),()->disposed||token!=revision);}catch(Exception|OutOfMemoryError ignored){}final List<PhotoPortrait.Heal> found=result;main.post(()->{if(disposed)return;analysisBusy=false;if(token!=revision){changed(false);return;}if(found==null||found.isEmpty()){status.setText(found==null?"分析未完成，请重试。":"未发现适合自动处理的小红色瑕疵，可用面部里的点按祛痘。");refreshApplyAvailability();return;}reviewBlemishes(found,token);});});
    }
    private void reviewBlemishes(List<PhotoPortrait.Heal> found,long token){if(disposed||token!=revision||found==null||found.isEmpty())return;String[] names=new String[found.size()];boolean[] chosen=new boolean[names.length];java.util.Arrays.fill(chosen,true);for(int i=0;i<names.length;i++)names[i]="第 "+(i+1)+" 处 · "+Math.round(found.get(i).tx*100)+"%, "+Math.round(found.get(i).ty*100)+"%";decision=new AppDialog.Builder(getContext()).setTitle("修复疑似小瑕疵").setMultiChoiceItems(names,chosen,(d,i,checked)->chosen[i]=checked).setNegativeButton("取消",(d,w)->refreshApplyAvailability()).setPositiveButton("修复所选",(d,w)->{if(disposed||token!=revision)return;PhotoPortrait next=portrait;for(int i=0;i<chosen.length;i++)if(chosen[i])next=next.addHeal(found.get(i));replace(next,true);}).setOnCancelListener(d->refreshApplyAvailability()).create();decision.show();refreshApplyAvailability();}
    private void showHealingHistory(){String[] names=new String[portrait.heals().size()];for(int i=0;i<names.length;i++)names[i]="撤销第 "+(i+1)+" 处 · "+Math.round(portrait.heals().get(i).tx*100)+"%, "+Math.round(portrait.heals().get(i).ty*100)+"%";decision=new AppDialog.Builder(getContext()).setTitle("选择要撤销的祛痘记录").setItems(names,(d,i)->{if(!disposed&&i<portrait.heals().size())replace(portrait.removeHeal(i),true);}).setNegativeButton("关闭",null).create();decision.show();}
    private void chooseSkinSmoothing(){activeRetouch=null;if(regionMode){chooseSkinEffect(3);return;}cancelTonePreview();photoSampling=false;clearSelectionFlash();mode=5;choosingGroup=false;adding=false;showOverlay=!overlayHiddenByUser;tool=0;refresh();refreshApplyAvailability();showPreviewStatus();revealActiveChoice();ensureGlobalSkin(false);}
    private void chooseSkinEffect(int parameter){activeRetouch=null;if(!regionMode)return;cancelTonePreview();photoSampling=false;clearSelectionFlash();mode=4;activeSkinParameter=parameter;adding=false;showOverlay=!overlayHiddenByUser;tool=0;refresh();refreshApplyAvailability();showPreviewStatus();revealActiveChoice();ensureGlobalSkin(false);}
    private void editBrush(){
        if(disposed||analysisBusy||globalSkinBusy)return;cancelTonePreview();photoSampling=false;clearSelectionFlash();photo.cancelEditingGesture();showOverlay=!overlayHiddenByUser;
        if(dragging||gestureStart!=null){dragging=false;remember(gestureStart);gestureStart=null;changed(false);}
        if(!regionMode){if(paintRequest!=null)paintRequest.run();return;}
        Bitmap brushPhoto=(rendered==null?initial:rendered).copy(Bitmap.Config.ARGB_8888,false);if(brushPhoto==null){status.setText("选区照片准备失败，请重试。");return;}
        brushDialog=new PhotoBrushDialog(activity,brushPhoto,snapshot().region,next->{if(!disposed)replaceRegion(next,true);});brushDialog.setSourcePositioning(beforeBody());brushDialog.setOnDismissListener(d->{if(!brushPhoto.isRecycled())brushPhoto.recycle();brushDialog=null;});brushDialog.show();
    }
    private PhotoPortrait.Tone editedTone(){PhotoPortrait.Face value=face();return tonePerFace?(value==null?PhotoPortrait.Tone.NONE:value.tone):portrait.globalTone;}
    private boolean canEditTone(){PhotoPortrait.Face value=face();return !disposed&&(!tonePerFace||(value!=null&&value.enabled&&!analysisBusy));}
    private PhotoPortrait withEditedTone(PhotoPortrait.Tone tone){return tonePerFace?portrait.withFace(selected,face().withTone(tone)):portrait.withGlobalTone(tone);}
    private PhotoPortrait withPreparedSkin(PhotoPortrait value){return preparedGlobalSkinMask!=null&&value.globalSkinMask!=preparedGlobalSkinMask?value.withGlobalSkinMask(preparedGlobalSkinMask):value;}
    private static boolean emptySkinMask(PhotoPortrait.BodySkinMask mask){if(mask==null)return false;for(byte value:mask.copyCoverage())if((value&255)>0)return false;return true;}
    private void showPreviewStatus(){
        if(status==null)return;status.setOnClickListener(null);
        if(globalSkinBusy){status.setText("正在识别露出皮肤…");return;}
        if((mode>=3&&(mode>=4||!tonePerFace))||portrait.skinSmoothing>0||!portrait.globalTone.isNeutral()||regionMode&&!region.skinSettings.isNeutral()){
            if(globalSkinFailed){status.setText("皮肤识别未完成 · 点按重试");status.setOnClickListener(v->ensureGlobalSkin(true));return;}
            if(globalSkinEmpty){status.setText("未发现露出的皮肤，已保留原有画面。");return;}
        }
        if(mode==5&&notice==null){status.setText("自动识别皮肤 · 点按重新识别");status.setOnClickListener(v->ensureGlobalSkin(true));}else status.setText(notice==null?"":notice);
    }
    private void ensureGlobalSkin(boolean force){
        if(disposed||globalSkinBusy)return;
        if(!force&&(portrait.globalSkinMask!=null||globalSkinAttempted)){showPreviewStatus();return;}
        final long task=++globalSkinTask;final List<PhotoPortrait.Face> knownFaces=portrait.faces();
        globalSkinAttempted=true;globalSkinBusy=true;globalSkinFailed=false;clearSelectionFlash();refresh();refreshApplyAvailability();showPreviewStatus();
        auxiliary.execute(()->{PhotoPortrait.BodySkinMask mask=null;try{mask=PhotoExposedSkin.detect(getContext().getApplicationContext(),analysis,knownFaces,()->disposed||task!=globalSkinTask);}catch(Exception|LinkageError|OutOfMemoryError failure){}
            final PhotoPortrait.BodySkinMask result=mask;main.post(()->{if(disposed||task!=globalSkinTask)return;globalSkinBusy=false;
                if(result==null){globalSkinFailed=true;refresh();refreshApplyAvailability();showPreviewStatus();return;}
                overlayHiddenByUser=false;showOverlay=true;preparedGlobalSkinMask=result;globalSkinEmpty=emptySkinMask(result);globalSkinFailed=false;
                // Preparing an automatic mask is a cache update, not a user edit. Keep queued face detection valid.
                portrait=portrait.withGlobalSkinMask(result);changed(false);showPreviewStatus();
            });});
    }
    private void switchToneEditing(){
        cancelTonePreview();photoSampling=false;PhotoPortrait.Tone prior=editedTone();PhotoPortrait.Face current=face();tonePerFace=!tonePerFace;clearSelectionFlash();
        if(tonePerFace&&current!=null&&!portrait.globalTone.isNeutral()){
            PhotoPortrait next=portrait.withGlobalTone(PhotoPortrait.Tone.NONE).withFace(selected,current.withTone(new PhotoPortrait.Tone(prior.presetId,prior.colorRGB,prior.amount,false)));replace(next,true);
        }else if(!tonePerFace&&!prior.isNeutral())replace(portrait.withGlobalTone(new PhotoPortrait.Tone(prior.presetId,prior.colorRGB,prior.amount,false)),true);
        else refresh();
        if(!tonePerFace)ensureGlobalSkin(false);else if(face()==null){status.setText("逐人调节可先识别人脸；全图肤色无需选脸。");}
    }
    private double toneAmount(){PhotoPortrait.Tone tone=editedTone();return tone.presetId==SkinTone.ORIGINAL?.6:tone.amount;}
    private void chooseTonePreset(int id){
        if(!canEditTone()||photoSampling)return;
        clearSelectionFlash();replace(withEditedTone(SkinTone.preset(id,id==0?0:toneAmount(),editedTone().body)),true);
    }
    private void chooseToneColor(int rgb){
        if(!canEditTone()||photoSampling)return;
        clearSelectionFlash();replace(withEditedTone(SkinTone.custom(rgb,toneAmount(),editedTone().body)),true);
    }
    private void refreshToneCards(){
        if(toneCards==null)return;PhotoPortrait.Tone tone=editedTone();
        boolean enabled=canEditTone()&&!photoSampling&&!tonePreviewing;
        List<SkinToneSwatches.Entry> saved=toneSwatches.load();StringBuilder key=new StringBuilder().append(enabled).append(':').append(tone.presetId).append(':').append(tone.colorRGB);
        toneManage.setEnabled(!saved.isEmpty()&&!photoSampling&&!tonePreviewing);toneManage.setAlpha(toneManage.isEnabled()?1:.4f);
        for(SkinToneSwatches.Entry entry:saved)key.append(':').append(entry.id).append(':').append(entry.name).append(':').append(entry.colorRGB);
        if(key.toString().equals(toneCardsKey))return;toneCardsKey=key.toString();int scroll=toneRail.getScrollX();toneCards.removeAllViews();
        for(SkinTone.Entry entry:SkinTone.presets())addToneCard(entry.label,entry.colorRGB,entry.id==0,tone.presetId==entry.id,enabled,"portrait-tone-preset-"+entry.id,()->chooseTonePreset(entry.id),null);
        boolean personal=false;for(SkinToneSwatches.Entry entry:saved)if(tone.presetId==SkinTone.CUSTOM&&tone.colorRGB==entry.colorRGB){personal=true;break;}
        int custom=tone.presetId==SkinTone.CUSTOM?tone.colorRGB:SkinTone.byId(1).colorRGB;
        addToneCard("自定义",custom,false,tone.presetId==SkinTone.CUSTOM&&!personal,enabled,"portrait-tone-custom",()->openTonePicker(custom),null);
        for(SkinToneSwatches.Entry entry:saved)addToneCard(entry.name,entry.colorRGB,false,tone.presetId==SkinTone.CUSTOM&&tone.colorRGB==entry.colorRGB,enabled,"portrait-tone-saved-"+entry.id,()->chooseToneColor(entry.colorRGB),()->deleteToneCard(entry));
        toneRail.post(()->{if(!disposed)toneRail.scrollTo(scroll,0);});
    }
    private void addToneCard(String name,int rgb,boolean original,boolean chosen,boolean enabled,String tag,Runnable action,Runnable remove){
        LinearLayout card=column();card.setGravity(Gravity.CENTER);card.setPadding(dp(4),dp(4),dp(4),dp(4));card.setTag(tag);card.setSelected(chosen);card.setEnabled(enabled);card.setAlpha(enabled?1:.4f);card.setClickable(true);card.setFocusable(true);
        GradientDrawable background=new GradientDrawable();background.setColor(chosen?PhotoPrismaStyle.SELECTION_FILL:Color.TRANSPARENT);background.setCornerRadius(dp(12));if(chosen)background.setStroke(dp(1),PhotoPrismaStyle.SELECTION_FRAME);card.setBackground(background);
        card.setContentDescription(name+"肤色"+(chosen?"，已选中":"")+(remove!=null?"，长按删除个人色卡":""));
        card.addView(new ToneSwatch(rgb,original,chosen),new LinearLayout.LayoutParams(dp(40),dp(40)));TextView label=text(name,11,chosen?PhotoPrismaStyle.SELECTION_LABEL:TEXT);label.setGravity(Gravity.CENTER);label.setMaxLines(2);card.addView(label,new LinearLayout.LayoutParams(-1,dp(36)));
        card.setOnClickListener(v->{if(enabled)action.run();});if(remove!=null)card.setOnLongClickListener(v->{remove.run();return true;});
        toneCards.addView(card,new LinearLayout.LayoutParams(dp(activity.getResources().getConfiguration().fontScale>=1.2f?104:84),dp(84)));
    }
    private void openTonePicker(int rgb){
        if(!canEditTone())return;
        stopSelectionFlash();showOverlay=!overlayHiddenByUser;photoSampling=false;final int target=selected;final boolean perFace=tonePerFace;
        if(tonePreviewStart==null)tonePreviewStart=snapshot();
        if(tonePicker!=null)tonePicker.dismiss();
        tonePicker=new SkinTonePicker(activity,rgb,toneSwatches,new SkinTonePicker.Listener(){
            public void interaction(boolean active){if(!disposed){selectionEntryDragging=active;photo.invalidate();}}
            public void use(int color){if(disposed||perFace!=tonePerFace||(perFace&&target!=selected)||!canEditTone())return;tonePreviewing=true;portrait=withEditedTone(SkinTone.custom(color,toneAmount(),editedTone().body));revision++;changed(false);}
            public void sample(int color){if(disposed||perFace!=tonePerFace||(perFace&&target!=selected))return;sampleSeed=color;photoSampling=true;stopSelectionFlash();showOverlay=!overlayHiddenByUser;refresh();refreshApplyAvailability();status.setText("点按照片取色");}
            public void saved(){if(!disposed){toneCardsKey=null;refreshToneCards();}}
            public void cancel(){if(!disposed)cancelTonePreview();}
        });tonePicker.show();photo.invalidate();
    }
    private void confirmTonePreview(){if(!tonePreviewing||tonePreviewStart==null)return;Snapshot before=tonePreviewStart;tonePreviewing=false;tonePreviewStart=null;dragging=false;gestureStart=null;remember(before);changed(false);}
    private void cancelTonePreview(){if(tonePreviewStart==null)return;Snapshot before=withPreparedSkin(tonePreviewStart);tonePreviewStart=null;tonePreviewing=false;photoSampling=false;dragging=false;gestureStart=null;if(!snapshot().equals(before)){restore(before);revision++;changed(false);}else{refresh();refreshApplyAvailability();photo.invalidate();}}
    private void cancelPhotoSampling(){if(!photoSampling)return;photoSampling=false;refresh();refreshApplyAvailability();openTonePicker(sampleSeed);}
    @Override public void onBackPressed(){if(photoSampling){cancelPhotoSampling();return;}if(tonePreviewStart!=null){cancelTonePreview();return;}if(!choosingGroup&&!directSection){showGroupEntries();return;}super.onBackPressed();}
    private void manageToneCards(){
        List<SkinToneSwatches.Entry> saved=toneSwatches.load();if(saved.isEmpty()){status.setText("在自定义肤色中保存个人色卡。");return;}
        String[] names=new String[saved.size()];for(int i=0;i<saved.size();i++)names[i]="删除 · "+saved.get(i).name;
        if(decision!=null)decision.dismiss();decision=new AppDialog.Builder(getContext()).setTitle("管理个人色卡").setItems(names,(d,index)->deleteToneCard(saved.get(index))).setNegativeButton("关闭",null).create();decision.show();
    }
    private void deleteToneCard(SkinToneSwatches.Entry entry){
        confirm("删除「"+entry.name+"」？","照片中已经使用的颜色会保留。","删除",()->{try{toneSwatches.remove(entry.id);toneCardsKey=null;refreshToneCards();status.setText("已删除个人色卡");}catch(Exception failure){status.setText("色卡未能删除，请重试。");}});
    }
    private void chooseToneScope(boolean body){
        if(!tonePerFace){if(body)ensureGlobalSkin(true);return;}
        PhotoPortrait.Face value=face();if(value==null||!value.enabled||analysisBusy||photoSampling)return;
        PhotoPortrait.Tone tone=value.tone;
        if(!body||value.bodySkinMask!=null){clearSelectionFlash();replace(portrait.withFace(selected,value.withTone(new PhotoPortrait.Tone(tone.presetId,tone.colorRGB,tone.amount,body))),true);return;}
        final int target=selected;final long token=revision,task=++toneTask;final PhotoPortrait frozen=portrait;
        analysisBusy=true;clearSelectionFlash();refresh();refreshApplyAvailability();status.setText("正在准备全身皮肤…");status.setOnClickListener(null);
        auxiliary.execute(()->{List<PhotoPortrait.Face> found=null;try{found=PhotoFaceBodySkin.refine(getContext().getApplicationContext(),analysis,frozen.faces(),()->disposed||revision!=token||toneTask!=task);}catch(Exception|LinkageError|OutOfMemoryError failure){}
            final List<PhotoPortrait.Face> result=found;main.post(()->{if(disposed)return;analysisBusy=false;
                if(revision!=token||toneTask!=task||selected!=target){refresh();refreshApplyAvailability();return;}
                if(result==null||result.size()!=frozen.faces().size()||result.get(target).bodySkinMask==null){refresh();refreshApplyAvailability();notice="全身皮肤选区未完成，点按重试。";status.setText(notice);status.setOnClickListener(v->chooseToneScope(true));return;}
                PhotoPortrait next=frozen.withFaces(result);PhotoPortrait.Face refined=next.faces().get(target);PhotoPortrait.Tone original=refined.tone;
                replace(next.withFace(target,refined.withTone(new PhotoPortrait.Tone(original.presetId,original.colorRGB,original.amount,true))),true);
            });});
    }
    private final class ToneSwatch extends View {
        private final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG);private final int rgb;private final boolean original,chosen;
        ToneSwatch(int rgb,boolean original,boolean chosen){super(PhotoPortraitDialog.this.getContext());this.rgb=rgb;this.original=original;this.chosen=chosen;setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);}
        @Override protected void onDraw(Canvas canvas){float pad=dp(2);RectF box=new RectF(pad,pad,getWidth()-pad,getHeight()-pad);ink.setStyle(Paint.Style.FILL);ink.setColor(original?0xffb9a99a:0xff000000|rgb);canvas.drawRoundRect(box,dp(10),dp(10),ink);if(original){canvas.save();canvas.clipRect(box.centerX(),box.top,box.right,box.bottom);ink.setColor(0xffe4d9ce);canvas.drawRoundRect(box,dp(10),dp(10),ink);canvas.restore();}if(chosen){ink.setStyle(Paint.Style.STROKE);ink.setStrokeWidth(dp(2));ink.setStrokeCap(Paint.Cap.ROUND);ink.setStrokeJoin(Paint.Join.ROUND);Path check=new Path();check.moveTo(getWidth()*.28f,getHeight()*.51f);check.lineTo(getWidth()*.44f,getHeight()*.67f);check.lineTo(getWidth()*.74f,getHeight()*.34f);ink.setColor(original||(.2126*((rgb>>16)&255)+.7152*((rgb>>8)&255)+.0722*(rgb&255))>150?0xff30241c:Color.WHITE);canvas.drawPath(check,ink);}}
    }
    private void askDetect(){if(analysisBusy)return;cancelTonePreview();photoSampling=false;if(!portrait.faces().isEmpty())confirm("重新识别人脸？","会替换已有的人脸选区和对应调节，保留祛痘。可撤销。","重新识别",this::detect);else detect();}
    private void confirm(String title,String message,String action,Runnable run){if(decision!=null)decision.dismiss();decision=new AppDialog.Builder(getContext()).setTitle(title).setMessage(message).setNegativeButton("取消",null).setPositiveButton(action,(d,w)->{if(!disposed)run.run();}).create();decision.show();}
    private void detect(){
        if(disposed||analysisBusy)return;analysisBusy=true;final long token=revision;status.setText("正在选脸…");refreshApplyAvailability();auto.setEnabled(false);
        auxiliary.execute(()->{List<PhotoPortrait.Face> found=null;String error=null;try{found=PhotoFaceSkinMask.refine(getContext().getApplicationContext(),analysis,PhotoFaceLandmarks.refine(getContext().getApplicationContext(),analysis,PhotoPortraitDetection.detect(analysis,()->disposed||token!=revision),()->disposed||token!=revision),()->disposed||token!=revision);}catch(Exception|LinkageError|OutOfMemoryError failure){error="自动选脸未完成，请重试或手动添加。";}final List<PhotoPortrait.Face> result=found;final String message=error;main.post(()->{
            if(disposed)return;analysisBusy=false;auto.setEnabled(true);if(token!=revision){changed(false);return;}
            if(message!=null||result==null||result.isEmpty()){notice=message==null?"未识别到清晰正脸，请手动添加。":message;status.setText(notice);refreshApplyAvailability();return;}
            selected=0;tool=mode==1?3:0;adding=false;showOverlay=!overlayHiddenByUser;replace(portrait.withFaces(result),true);flashSelectedFace();
        });});
    }
    private void heal(double x,double y){
        if(disposed||analysisBusy)return;analysisBusy=true;final long token=revision;final double brush=radius;status.setText("寻找附近纹理…");refreshApplyAvailability();
        auxiliary.execute(()->{PhotoPortrait.Heal patch=null;String error=null;try{patch=PhotoPortraitDetection.heal(analysis,x,y,brush);}catch(Exception|OutOfMemoryError failure){error="修复未完成，请缩小画笔后重试。";}final PhotoPortrait.Heal result=patch;final String message=error;main.post(()->{
            if(disposed)return;analysisBusy=false;if(token!=revision){changed(false);return;}if(result==null){notice=message;status.setText(message);refreshApplyAvailability();return;}
            try{replace(portrait.addHeal(result),true);}catch(IllegalArgumentException limit){status.setText("祛痘数量已达上限，请先撤回一处。");refreshApplyAvailability();}
        });});
    }
    private void requestMask(){
        boolean global=mode==4||mode==5||mode==3&&!tonePerFace;
        PhotoPortrait.BodySkinMask body=global?preparedGlobalSkinMask:null;
        if(showOverlay&&body!=null){
            if(overlayGlobalMask==body&&overlay!=null&&!overlay.isRecycled())return;
            overlayFace=null;maskQueue.reset();overlayGlobalMask=body;
            if(overlay!=null){overlay.recycle();overlay=null;}
            byte[] coverage=body.copyCoverage();int[] pixels=new int[coverage.length];
            AdjustmentRegion.Brush brush=regionMode?region.compileBrush(analysis.getWidth(),analysis.getHeight()):null;int side=PhotoPortrait.BodySkinMask.SIZE;
            for(int i=0;i<pixels.length;i++){double selected=brush==null?1:brush.weight((i%side+.5)/side,(i/side+.5)/side);pixels[i]=((int)Math.round((coverage[i]&255)*38.0/255*selected)<<24)|0x00fff1e4;}
            overlay=Bitmap.createBitmap(pixels,PhotoPortrait.BodySkinMask.SIZE,PhotoPortrait.BodySkinMask.SIZE,Bitmap.Config.ARGB_8888);return;
        }
        overlayGlobalMask=null;
        PhotoPortrait.Face value=showOverlay&&!global?face():null;
        if(value==null){overlayFace=null;maskQueue.reset();if(overlay!=null){overlay.recycle();overlay=null;}return;}
        value=value.withSettings(PhotoPortrait.Settings.NONE);
        if(value.equals(overlayFace))return;overlayFace=value;if(overlay!=null){overlay.recycle();overlay=null;}maskQueue.offer(value,false);
    }
    private void clearSelectionFlash(){main.removeCallbacks(selectionFlashTick);selectionFlashPending=false;selectionFlashStep=-1;}
    private void stopSelectionFlash(){clearSelectionFlash();requestMask();photo.invalidate();}
    private void flashSelectedFace(){
        clearSelectionFlash();if(disposed)return;overlayHiddenByUser=false;showOverlay=true;requestMask();photo.invalidate();
    }
    private void startSelectionFlash(){clearSelectionFlash();requestMask();photo.invalidate();}
    private void advanceSelectionFlash(){clearSelectionFlash();}
    private void setCompare(boolean value){compare=value;if(value)stopSelectionFlash();photo.invalidate();}
    private Bitmap maskBitmap(PhotoPortrait.Face value)throws Exception{
        int width=240,height=Math.max(1,(int)Math.round(analysis.getHeight()*240.0/analysis.getWidth()));if(height>320){width=Math.max(1,(int)Math.round(width*320.0/height));height=320;}
        Bitmap image=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888);boolean completed=false;try{PortraitPreviewFilter.Mask mask=PortraitPreviewFilter.mask(value,analysis.getWidth(),analysis.getHeight());AdjustmentRegion.Brush brush=regionMode?region.compileBrush(analysis.getWidth(),analysis.getHeight()):null;int[] row=new int[width];for(int y=0;y<height;y++){if(disposed||Thread.currentThread().isInterrupted())throw new java.io.IOException("选区已关闭。");double ny=(y+.5)/height;for(int x=0;x<width;x++){double nx=(x+.5)/width;int source=analysis.getPixel(Math.min(analysis.getWidth()-1,(int)(nx*analysis.getWidth())),Math.min(analysis.getHeight()-1,(int)(ny*analysis.getHeight())));int alpha=(int)Math.round(mask.weight(source,nx,ny)*38*(brush==null?1:brush.weight(nx,ny)));row[x]=(alpha<<24)|0x00fff1e4;}image.setPixels(row,0,width,0,y,width,1);}completed=true;return image;}finally{if(!completed)image.recycle();}}

    private final class PhotoCanvas extends View {
        final RectF frame=new RectF();private final Paint ink=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);private final ArrayList<Double> path=new ArrayList<>();
        private final ScaleGestureDetector scale;private float zoom=1,panX,panY,lastX,lastY;private double downX,downY;private boolean tracking,navigating;
        PhotoCanvas(){super(PhotoPortraitDialog.this.getContext());setTag("portrait-canvas");setFocusable(true);setClickable(true);scale=new ScaleGestureDetector(getContext(),new ScaleGestureDetector.SimpleOnScaleGestureListener(){public boolean onScale(ScaleGestureDetector d){float next=Math.max(1,Math.min(8,zoom*d.getScaleFactor())),ratio=next/zoom,fx=d.getFocusX()-getWidth()/2f,fy=d.getFocusY()-getHeight()/2f;panX=fx-(fx-panX)*ratio;panY=fy-(fy-panY)*ratio;zoom=next;bounds();invalidate();return true;}});}
        private void cancelEditingGesture(){tracking=false;navigating=false;path.clear();invalidate();}
        @Override protected void onSizeChanged(int width,int height,int oldWidth,int oldHeight){
            super.onSizeChanged(width,height,oldWidth,oldHeight);
            if(width<1||height<1)return;
            if(oldWidth>0&&oldHeight>0&&!frame.isEmpty()){
                double centerX=(oldWidth/2.0-frame.left)/frame.width(),centerY=(oldHeight/2.0-frame.top)/frame.height();
                float fit=Math.min(width/(float)initial.getWidth(),height/(float)initial.getHeight());
                panX=(float)((.5-centerX)*initial.getWidth()*fit*zoom);panY=(float)((.5-centerY)*initial.getHeight()*fit*zoom);
            }
            // A rotation cancels an unfinished gesture, while preserving the frozen edit and zoom.
            tracking=false;navigating=false;path.clear();bounds();
        }
        void resetViewport(){stopSelectionFlash();zoom=1;panX=panY=0;bounds();invalidate();}
        private void bounds(){float fit=Math.min(getWidth()/(float)initial.getWidth(),getHeight()/(float)initial.getHeight()),w=initial.getWidth()*fit*zoom,h=initial.getHeight()*fit*zoom;float mx=Math.max(0,(w-getWidth())/2),my=Math.max(0,(h-getHeight())/2);panX=Math.max(-mx,Math.min(mx,panX));panY=Math.max(-my,Math.min(my,panY));frame.set((getWidth()-w)/2+panX,(getHeight()-h)/2+panY,(getWidth()+w)/2+panX,(getHeight()+h)/2+panY);}
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);if(disposed)return;bounds();Bitmap image=compare||rendered==null?initial:rendered;ink.setAlpha(255);ink.setStyle(Paint.Style.FILL);canvas.drawBitmap(image,null,frame,ink);if(compare||frame.isEmpty())return;canvas.save();canvas.clipRect(frame);if(showOverlay&&!dragging&&!selectionEntryDragging&&!photoSampling&&overlay!=null&&!overlay.isRecycled())canvas.drawBitmap(overlay,null,frame,ink);
            // Selection stays visible until hidden by the user; adjustment gestures temporarily suppress it.
            if(showOverlay&&!dragging&&!selectionEntryDragging&&!photoSampling&&!choosingGroup&&tool==3){ink.setColor(ACCENT);ink.setStyle(Paint.Style.STROKE);ink.setStrokeWidth(dp(1));for(PhotoPortrait.Heal h:portrait.heals())canvas.drawCircle((float)(frame.left+h.tx*frame.width()),(float)(frame.top+h.ty*frame.height()),(float)(h.radius*Math.min(frame.width(),frame.height())),ink);}
            if(tracking&&!navigating&&!path.isEmpty()){ink.setColor(tool==2?0xaaff9b8f:0x66fff1e4);ink.setStyle(Paint.Style.STROKE);ink.setStrokeCap(Paint.Cap.ROUND);ink.setStrokeJoin(Paint.Join.ROUND);ink.setStrokeWidth((float)(2*radius*Math.min(frame.width(),frame.height())));Path stroke=new Path();for(int i=0;i<path.size();i+=2){float x=(float)(frame.left+path.get(i)*frame.width()),y=(float)(frame.top+path.get(i+1)*frame.height());if(i==0)stroke.moveTo(x,y);else stroke.lineTo(x,y);}canvas.drawPath(stroke,ink);}
            ink.setStyle(Paint.Style.FILL);canvas.restore();
        }
        @Override public boolean onTouchEvent(MotionEvent event){
            if(disposed)return false;bounds();int action=event.getActionMasked();
            if(photoSampling){
                if(action==MotionEvent.ACTION_DOWN){stopSelectionFlash();tracking=frame.contains(event.getX(),event.getY());lastX=event.getX();lastY=event.getY();path.clear();return true;}
                if(event.getPointerCount()>1||action==MotionEvent.ACTION_CANCEL){tracking=false;return true;}
                if(action==MotionEvent.ACTION_UP){boolean pick=tracking&&frame.contains(event.getX(),event.getY())&&Math.hypot(event.getX()-lastX,event.getY()-lastY)<dp(24);tracking=false;if(pick){int px=Math.max(0,Math.min(analysis.getWidth()-1,(int)(nx(event.getX())*analysis.getWidth()))),py=Math.max(0,Math.min(analysis.getHeight()-1,(int)(ny(event.getY())*analysis.getHeight())));int color=analysis.getPixel(px,py)&0xffffff;photoSampling=false;refresh();refreshApplyAvailability();openTonePicker(color);performClick();}return true;}return true;
            }
            scale.onTouchEvent(event);
            if(action==MotionEvent.ACTION_DOWN){stopSelectionFlash();tracking=frame.contains(event.getX(),event.getY());navigating=false;path.clear();downX=nx(event.getX());downY=ny(event.getY());lastX=event.getX();lastY=event.getY();if(tracking&&(tool==1||tool==2)){path.add(downX);path.add(downY);}return true;}
            if(event.getPointerCount()>1){navigating=true;tracking=false;path.clear();float x=0,y=0;for(int i=0;i<event.getPointerCount();i++){x+=event.getX(i);y+=event.getY(i);}x/=event.getPointerCount();y/=event.getPointerCount();if(action==MotionEvent.ACTION_MOVE){panX+=x-lastX;panY+=y-lastY;bounds();}lastX=x;lastY=y;invalidate();return true;}
            if(navigating){if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL){navigating=false;tracking=false;}return true;}
            if(!tracking)return true;double x=nx(event.getX()),y=ny(event.getY());
            if(action==MotionEvent.ACTION_MOVE){if((tool==1||tool==2)&&path.size()<1024){int n=path.size();if(n<2||Math.hypot(x-path.get(n-2),y-path.get(n-1))>.001){path.add(x);path.add(y);}}invalidate();return true;}
            if(action==MotionEvent.ACTION_UP){tracking=false;try{
                if(choosingGroup||mode>=4||mode==3&&!tonePerFace){/* Entry navigation and global colour editing have no face-selection gesture. */}
                else if(adding&&tool==0){double cx=(downX+x)/2,cy=(downY+y)/2,rx=Math.abs(x-downX)/2,ry=Math.abs(y-downY)/2;if(rx<.008||ry<.008){cx=x;cy=y;rx=.12;ry=.17;}PhotoPortrait.Face f=PhotoPortraitDetection.manualFace(analysis,cx,cy,rx,ry);selected=portrait.faces().size();adding=false;replace(portrait.addFace(f),true);flashSelectedFace();}
                else if(tool==0){double best=Double.POSITIVE_INFINITY;int found=-1;for(int i=0;i<portrait.faces().size();i++){PhotoPortrait.Face f=portrait.faces().get(i);double dx=(x-f.cx)*analysis.getWidth(),dy=(y-f.cy)*analysis.getHeight(),a=Math.toRadians(f.roll),lx=dx*Math.cos(a)+dy*Math.sin(a),ly=-dx*Math.sin(a)+dy*Math.cos(a),distance=Math.hypot(lx/(f.rx*analysis.getWidth()),ly/(f.ry*analysis.getHeight()));if(PortraitPreviewFilter.faceContains(f,x,y,analysis.getWidth(),analysis.getHeight())&&distance<best){best=distance;found=i;}}if(found>=0)selectFace(found);}
                else if((tool==1||tool==2)&&face()!=null){double[] points=new double[path.size()];for(int i=0;i<points.length;i++)points[i]=path.get(i);PhotoPortrait.Face f=face().addStroke(new PhotoPortrait.Stroke(points,radius,.65,tool==2));replace(portrait.withFace(selected,f),true);}
                else if(tool==3&&Math.hypot((x-downX)*frame.width(),(y-downY)*frame.height())<dp(20))heal(x,y);
            }catch(IllegalArgumentException limit){status.setText("选区或修复数量已达上限，请先撤销或删除。");}path.clear();invalidate();performClick();return true;}
            if(action==MotionEvent.ACTION_CANCEL){tracking=false;path.clear();invalidate();}return true;
        }
        private double nx(float x){return Math.max(0,Math.min(1,(x-frame.left)/frame.width()));}
        private double ny(float y){return Math.max(0,Math.min(1,(y-frame.top)/frame.height()));}
        @Override public boolean performClick(){return super.performClick();}
    }
    private Button stageAction(LinearLayout parent,String icon,String description,String tag,Runnable task){Button b=PhotoWorkspaceUi.icon(getContext(),icon,description,tag,task);parent.addView(b,new LinearLayout.LayoutParams(dp(48),dp(48)));return b;}
    private Button button(String label,Runnable task){Button b=new Button(getContext());b.setText(label);b.setAllCaps(false);b.setTextSize(12);b.setTextColor(TEXT);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setMinWidth(0);b.setMinimumWidth(0);b.setIncludeFontPadding(false);b.setPadding(dp(4),0,dp(4),0);b.setGravity(Gravity.CENTER);b.setStateListAnimator(null);b.setBackgroundColor(Color.TRANSPARENT);b.setOnClickListener(v->task.run());return b;}
    private void select(Button button,boolean chosen){button.setSelected(chosen);button.setTextColor(chosen?ACCENT:TEXT);}
    private void tint(SeekBar slider){PhotoPrismaStyle.slider(getContext(),slider);}
    private LinearLayout row(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.HORIZONTAL);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private LinearLayout column(){LinearLayout v=new LinearLayout(getContext());v.setOrientation(LinearLayout.VERTICAL);return v;}
    private TextView text(String value,float size,int color){TextView v=new TextView(getContext());v.setText(value);v.setTextSize(size);v.setTextColor(color);v.setGravity(Gravity.CENTER_VERTICAL);v.setIncludeFontPadding(false);return v;}
    private int dp(float n){return Math.round(n*getContext().getResources().getDisplayMetrics().density);}
}
