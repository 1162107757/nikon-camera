package cc.huevia.ui;

import android.app.*;
import android.content.*;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.InsetDrawable;
import android.graphics.drawable.LayerDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.StateListDrawable;
import android.media.ExifInterface;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import cc.huevia.album.*;
import cc.huevia.library.*;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

/**
 * THESIS: The photograph owns the editor; the accepted Prisma prototype is the visual authority.
 * OWN-WORLD: Photo-derived blur, charcoal circles, white filmstrip labels and slider knobs,
 * yellow #FFE335 actions, native platform type and real system safe areas.
 * STORY: Choose a real preset, tune, compare with an aligned original, compose, export a new copy.
 * FIRST VIEWPORT: Close/filename/yellow export, a contained photo with top-right split comparison,
 * history, five circular tools, and their workspace. Follow-up correction: 14dp filmstrip gaps.
 * FORM: User-approved 2026-11-07 prototype and subsequent spacing correction.
 * FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review,
 * the verdict, DESIGN.md, and every shipping raster carrying its provenance.
 */
public final class PhotoFilterEditor implements AutoCloseable {
    public interface Host {
        void changed();
        void export(java.util.List<PhotoPresetBatch.Edit> edits);
        void raw();
        boolean canExportRaw();
        void download();
        void addFilters();
        void error(String message);
        default void saveOriginal(DownloadedPhoto photo){}
        default void applyRecipeToSelection(PhotoRecipeStore.Recipe recipe){}
        default void copyAdjustments(PhotoAdjustments settings,DownloadedPhoto source){}
        default void undoAdjustmentCopy(){}
        default void workspaceMode(boolean crop){}
    }
    private static final int BG=0xff292724, FIELD=0xff33302c, TEXT=0xfff4f5f7, MUTED=0xffbab1a7, BLUE=PhotoPrismaStyle.YELLOW;
    private final Activity activity; private final PhotoPresetBatch batch; private final Host host;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService io=Executors.newSingleThreadExecutor(r->thread(r,"photo-edit-io"));
    private final ExecutorService catalogIo=Executors.newSingleThreadExecutor(r->thread(r,"photo-edit-catalog"));
    private final ThreadPoolExecutor previews=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<>(1),r->thread(r,"photo-edit-preview"),new ThreadPoolExecutor.DiscardOldestPolicy());
    private final LatestPreviewQueue<PreviewRequest,PreviewFrame> previewQueue;
    private final ThreadPoolExecutor thumbnails=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<>(16),r->thread(r,"photo-edit-thumbnails"),new ThreadPoolExecutor.AbortPolicy());
    private final java.util.List<Entry> entries=new ArrayList<>(); private final java.util.List<Runnable> visibleRequests=new ArrayList<>();
    private final java.util.List<Entry> onlineEntries=new ArrayList<>();
    private final ArrayDeque<Entry> renderedEntries=new ArrayDeque<>();
    private volatile int generation, previewRequest; private volatile boolean closed;
    private DownloadedPhoto bound, originalPhoto; private String owner="", sourceSha="", selected="", selectedName="原图", category="", query="";
    private byte[] selectedBytes=new byte[0]; private PresetPreviewProfile selectedProfile;
    private int strength=100; private boolean ready, hasDraft, exported, updating, parkedDraft;
    private PhotoAdjustments adjustments=PhotoAdjustments.NONE;
    private PhotoGeometry geometry=PhotoGeometry.NONE;
    private PhotoLocalEdits localEdits=PhotoLocalEdits.NONE;
    private String selectedRegionId="";
    private boolean brushLoading;
    private Button brushScopeButton;
    private Button regionMaskHoldButton;
    private Bitmap regionMaskPreview;
    private int displayedSourceWidth,displayedSourceHeight;
    private PhotoGeometry displayedGeometry=PhotoGeometry.NONE;
    private PhotoBorder displayedBorder=PhotoBorder.NONE;
    private PhotoBodyShape displayedBodyShape=PhotoBodyShape.NONE;
    private boolean regionMaskHeld,regionMaskPreparing;
    private String regionMaskRegionId="";
    private volatile long regionMaskRequest;
    private final Runnable endRegionMaskClick=()->stopRegionMaskPeek();
    private final ArrayList<Dialog> linkedPaintDialogs=new ArrayList<>();
    private boolean closingPaintDialogs;
    private LinearLayout localControl,portraitControl,paletteControl,cleanupControl;
    private boolean localLoading,portraitLoading;
    private long portraitRequest;
    private PhotoBorder border=PhotoBorder.NONE;private PhotoCaptureInfo captureInfo=PhotoCaptureInfo.EMPTY;
    private PhotoBorderPanel borderControls;private View borderPanel;private boolean borderMode;
    private boolean recipeMode,compositionMode,compositionLoading;
    private double inlineRatio=0;
    private final java.util.List<Button> inlineRatios=new ArrayList<>();
    private static final double[] INLINE_RATIOS={0,1,2.0/3,1.5,9.0/16};
    private LinearLayout compositionPanel;private TextView compositionSummary,adjustmentCaption;
    private FrameLayout toolPanels;private Button compositionReset;
    private final java.util.List<View> compositionTools=new ArrayList<>();
    private boolean savedVersionOnly,unrecoverableSaved,histogramOpen,detailLoading;
    private PhotoHistogramPanel histogramPanel;
    private PhotoDetailDialog detailDialog;
    private PhotoExportDialog exportDialog;
    private PhotoVersionExport versionExport;
    private PhotoCompactDock compactDock;
    private QuickState quickState;
    private PhotoCleanup.Analysis quickAnalysis;
    private boolean quickBusy;
    private volatile long quickRequest;
    private int portraitSection;
    private Bitmap diagnosticPreview;
    private String displayedSha="";
    private long recipeRequest;
    private final java.util.List<PhotoRecipeStore.Recipe> recipes=new ArrayList<>();
    private LinearLayout recipePanel,recipeRows;private TextView recipeStatus;private Button saveRecipeButton;
    private PhotoAdjustments.Parameter parameter=PhotoAdjustments.Parameter.EXPOSURE;
    private boolean adjustmentMode;
    private volatile int thumbRevision;
    private Bitmap plainThumb;
    private final ArrayDeque<EditState> undo=new ArrayDeque<>(),redo=new ArrayDeque<>();
    private EditState dragStart;
    private SeekBar trackingSlider;
    private boolean interactivePreview;
    private LinearLayout filterPanel,adjustmentPanel;
    private Button gridButton,filterModeButton,adjustmentModeButton,undoButton,redoButton;
    private HorizontalScrollView categoryScroll;
    private TextView categoryStatus;
    private TextView adjustmentValue;
    private SeekBar adjustmentSlider;
    private String preparationError="";
    private final Map<PhotoAdjustments.Parameter,LinearLayout> parameterControls=new LinkedHashMap<>();
    private final Map<Boolean,LinearLayout> advancedControls=new LinkedHashMap<>();
    private int pickerFirst, pickerTop;
    private Bitmap original, current, thumb, glass,fastOriginal,comparisonPreview;
    private Bitmap referenceCache,referenceCacheSource;private String referenceCacheKey=""; private PresetLibrary library;
    private LinearLayout dock, strip, categories; private TextView title, value, note; private SeekBar slider;
    private HorizontalScrollView filterScroll; private Dialog popup; private GridView grid; private BaseAdapter gridAdapter;
    private Runnable delayedSave; private boolean savePending; private Entry pendingChoice;
    private boolean pendingChoiceFromPicker;
    private Runnable pendingRetry;private int pendingRetryCount;private long pendingChoiceSerial;
    private final Map<String, FilterCard> stripCards = new LinkedHashMap<>();
    private final Map<String, Button> categoryButtons = new LinkedHashMap<>();
    private View addFiltersAction;
    private boolean onlineSource=true,catalogLoading;private String catalogMessage="正在加载在线滤镜…",catalogDiagnostic="";
    private EditorPresetCatalog onlineCatalog;private Button onlineButton,mineButton;private TextView sourceStatus;
    private final java.util.List<OnlinePreset> catalogMetadata=new ArrayList<>();private long catalogLoadedAt;private String cachedCatalogMessage="",cachedCatalogDiagnostic="";
    private LinearLayout pickerCategories;private TextView pickerStatus,pickerTitle,pickerCount;
    private static final Map<String,Boolean> KNOWN=Collections.synchronizedMap(new LinkedHashMap<String,Boolean>(64,.75f,true){protected boolean removeEldestEntry(Map.Entry<String,Boolean> entry){return size()>512;}});
    private static final class Entry {
        final PresetRecord preset;final OnlinePreset online;final String id,name,category;
        Bitmap image;byte[] bytes;PresetPreviewProfile profile;String error="";boolean loading,retryable;int renderedRevision=-1;
        Entry(PresetRecord p){preset=p;online=null;id=p.id;name=p.displayName;category=p.category;}
        Entry(OnlinePreset p){preset=null;online=p;id=p.sha256;name=p.name;category=p.category;}
    }
    public PhotoFilterEditor(Activity activity, PhotoPresetBatch batch, Host host){
        this.activity=activity;this.batch=batch;this.host=host;
        previewQueue=new LatestPreviewQueue<>(previews,task->main.post(task),this::renderPreview,new LatestPreviewQueue.Listener<PreviewRequest,PreviewFrame>(){
            public void frame(PreviewRequest request,PreviewFrame result,boolean interactive,boolean latest){
                if(!valid(request.token,request.scope)){discard(result);return;}
                stopRegionMaskPeek();current=result.image;comparisonPreview=result.reference;diagnosticPreview=result.diagnostic;displayedSourceWidth=request.base.getWidth();displayedSourceHeight=request.base.getHeight();displayedGeometry=GeometryPreviewProfile.geometry(request.profile);displayedBorder=request.frame;displayedBodyShape=request.bodyShape;updateRegionMaskHoldButton();
                if(request.statistics&&histogramPanel!=null&&histogramOpen)histogramPanel.setData(result.histogram);
                host.changed();
            }
            public void discard(PreviewFrame result){result.recycle();}
            public void error(Throwable error){if(closed||!ready)return;if(histogramPanel!=null&&histogramOpen)histogramPanel.setError(message(error));host.error(message(error));}
        });
    }
    private static Thread thread(Runnable r,String name){Thread t=new Thread(r,name);t.setDaemon(true);return t;}
    public static String accountOwner(Context context){
        cc.huevia.account.AccountRepository repository=cc.huevia.account.AndroidAccounts.get(context);
        cc.huevia.account.AccountRepository.Session session=repository.cachedSession(); return session==null||repository.isLogoutPending()?"":session.user.id;
    }
    public static void invalidateDraftCache(){KNOWN.clear();}
    public Bitmap preview(){return ready?(regionMaskPreview==null?normalPreview():regionMaskPreview):null;} public Bitmap original(){return ready&&!unrecoverableSaved?(comparisonPreview==null?original:comparisonPreview):null;}
    public Bitmap backdrop(){return ready?glass:null;}
    private Bitmap normalPreview(){return diagnosticPreview==null?current:diagnosticPreview;}
    /** A momentary display-only mask; the original preview, draft and exported pixels are untouched. */
    public Button createRegionMaskHoldButton(){
        stopRegionMaskPeek();
        final Button button=PhotoWorkspaceUi.icon(activity,"mask","按住显示当前涂抹选区，松开隐藏","editor-region-mask-hold",()->{});
        regionMaskHoldButton=button;button.setMinWidth(dp(48));button.setMinimumWidth(dp(48));button.setMinHeight(dp(48));button.setMinimumHeight(dp(48));button.setPadding(0,0,0,0);
        GradientDrawable face=shape(0xb80c0b0a,24);face.setStroke(dp(1),0x38ffffff);button.setBackgroundTintList(null);button.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335),face,null));
        button.setOnTouchListener((v,event)->{int action=event.getActionMasked();if(action==MotionEvent.ACTION_DOWN){if(button.isEnabled())beginRegionMaskPeek();return true;}if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL||action==MotionEvent.ACTION_OUTSIDE||event.getPointerCount()>1||action==MotionEvent.ACTION_MOVE&&(event.getX()<0||event.getY()<0||event.getX()>v.getWidth()||event.getY()>v.getHeight())){stopRegionMaskPeek();return true;}return true;});
        button.setOnClickListener(v->{beginRegionMaskPeek();main.removeCallbacks(endRegionMaskClick);if(regionMaskHeld)main.postDelayed(endRegionMaskClick,650);});
        button.setOnFocusChangeListener((v,focused)->{if(!focused&&regionMaskHoldButton==button)stopRegionMaskPeek();});
        final ViewTreeObserver.OnWindowFocusChangeListener focus=focused->{if(!focused&&regionMaskHoldButton==button)stopRegionMaskPeek();};
        button.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener(){public void onViewAttachedToWindow(View v){v.getViewTreeObserver().addOnWindowFocusChangeListener(focus);}public void onViewDetachedFromWindow(View v){if(v.getViewTreeObserver().isAlive())v.getViewTreeObserver().removeOnWindowFocusChangeListener(focus);if(regionMaskHoldButton==button)stopRegionMaskPeek();}});
        updateRegionMaskHoldButton();return button;
    }
    private boolean canPeekRegionMask(){AdjustmentRegion region=activeRegion();Bitmap base=normalPreview();return ready&&!closed&&!unrecoverableSaved&&region!=null&&!region.strokes.isEmpty()&&base!=null&&!base.isRecycled()&&Math.max(base.getWidth(),base.getHeight())<=2048&&displayedSourceWidth>0&&displayedSourceHeight>0&&displayedGeometry.equals(geometry)&&displayedBorder.equals(border)&&displayedBodyShape.equals(localEdits.portrait.bodyShape)&&original!=null&&!original.isRecycled();}
    private void updateRegionMaskHoldButton(){if(regionMaskHoldButton==null)return;boolean available=canPeekRegionMask();if(regionMaskHeld&&(!available||!selectedRegionId.equals(regionMaskRegionId)))stopRegionMaskPeek();regionMaskHoldButton.setVisibility(available?View.VISIBLE:View.GONE);regionMaskHoldButton.setEnabled(available);}
    private void beginRegionMaskPeek(){stopRegionMaskPeek();if(!canPeekRegionMask())return;regionMaskHeld=true;regionMaskRegionId=selectedRegionId;if(regionMaskHoldButton!=null){regionMaskHoldButton.setSelected(true);regionMaskHoldButton.setPressed(true);}prepareRegionMaskPeek();}
    private void stopRegionMaskPeek(){main.removeCallbacks(endRegionMaskClick);regionMaskRequest++;regionMaskHeld=false;regionMaskRegionId="";boolean shown=regionMaskPreview!=null;regionMaskPreview=null;if(regionMaskHoldButton!=null){regionMaskHoldButton.setSelected(false);regionMaskHoldButton.setPressed(false);}if(shown)host.changed();}
    /** At most one owned preview copy/job. A newer hold is admitted only after an old job returns. */
    private void prepareRegionMaskPeek(){
        if(regionMaskPreparing||!regionMaskHeld||!canPeekRegionMask())return;
        final long request=regionMaskRequest;final int token=generation;final String account=owner;final AdjustmentRegion region=activeRegion();final PhotoGeometry composition=displayedGeometry;final PhotoBorder frame=displayedBorder;final PhotoBodyShape bodyShape=displayedBodyShape;final Bitmap source=normalPreview();final int sourceWidth=displayedSourceWidth,sourceHeight=displayedSourceHeight;
        final Bitmap copy;try{copy=source.copy(Bitmap.Config.ARGB_8888,true);if(copy==null)throw new IllegalStateException("selection preview copy");}catch(RuntimeException|OutOfMemoryError unavailable){stopRegionMaskPeek();return;}
        regionMaskPreparing=true;
        try{io.execute(()->{boolean complete=false;Bitmap mask=null;try{mask=regionMaskBitmap(region,composition,frame,sourceWidth,sourceHeight,copy.getWidth(),copy.getHeight(),bodyShape,()->closed||request!=regionMaskRequest||Thread.currentThread().isInterrupted());if(closed||request!=regionMaskRequest)throw new CancellationException();drawRegionMaskOverlay(copy,mask,composition,frame,sourceWidth,sourceHeight);complete=true;}catch(Exception|OutOfMemoryError ignored){}finally{if(mask!=null&&!mask.isRecycled())mask.recycle();}
            final boolean built=complete;main.post(()->{regionMaskPreparing=false;boolean same=regionMaskHeld&&request==regionMaskRequest&&canPeekRegionMask()&&valid(token,account)&&source==normalPreview()&&sourceWidth==displayedSourceWidth&&sourceHeight==displayedSourceHeight&&composition.equals(displayedGeometry)&&frame.equals(displayedBorder)&&bodyShape.equals(displayedBodyShape)&&region==activeRegion()&&composition.equals(geometry)&&frame.equals(border)&&region.id.equals(selectedRegionId);if(built&&same){regionMaskPreview=copy;host.changed();}else{copy.recycle();if(request==regionMaskRequest)stopRegionMaskPeek();else if(regionMaskHeld)prepareRegionMaskPeek();}});
        });}catch(RejectedExecutionException unavailable){regionMaskPreparing=false;copy.recycle();stopRegionMaskPeek();}
    }
    private static void drawRegionMaskOverlay(Bitmap copy,Bitmap mask,PhotoGeometry composition,PhotoBorder frame,int sourceWidth,int sourceHeight){
        PhotoGeometry.Plan plan=composition.plan(sourceWidth,sourceHeight,1);int[] framed=frame.dimensions(plan.width,plan.height);RectF photo=regionMaskPhotoRect(plan,frame,framed);float radius=regionMaskCorner(plan,frame);Canvas canvas=new Canvas(copy);int save=canvas.save();canvas.scale(copy.getWidth()/(float)framed[0],copy.getHeight()/(float)framed[1]);Path clip=new Path();clip.addRoundRect(photo,radius,radius,Path.Direction.CW);canvas.clipPath(clip);canvas.drawBitmap(mask,null,new RectF(0,0,framed[0],framed[1]),new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG));canvas.restoreToCount(save);
    }
    private static RectF regionMaskPhotoRect(PhotoGeometry.Plan plan,PhotoBorder frame,int[] framed){float margin=frame.margin/100f,left=frame.isNone()||frame.template==3?0:frame.template==1?(framed[0]-plan.width)/2f:framed[0]-plan.width-plan.width*.08f*margin,top=frame.isNone()||frame.template==3?0:plan.width*(frame.template==1?.06f:.07f)*margin;return new RectF(left,top,left+plan.width,top+plan.height);}
    private static float regionMaskCorner(PhotoGeometry.Plan plan,PhotoBorder frame){return frame.isNone()||frame.template==3?0:plan.width*.025f*frame.corner/100f;}
    /** Geometry and border placement mirror the existing composed-photo pipeline, at a 320px mask bound. */
    private static Bitmap regionMaskBitmap(AdjustmentRegion region,PhotoGeometry composition,PhotoBorder frame,int sourceWidth,int sourceHeight,int outputWidth,int outputHeight,java.util.function.BooleanSupplier cancel){return regionMaskBitmap(region,composition,frame,sourceWidth,sourceHeight,outputWidth,outputHeight,PhotoBodyShape.NONE,cancel);}
    private static Bitmap regionMaskBitmap(AdjustmentRegion region,PhotoGeometry composition,PhotoBorder frame,int sourceWidth,int sourceHeight,int outputWidth,int outputHeight,PhotoBodyShape bodyShape,java.util.function.BooleanSupplier cancel){
        PhotoGeometry.Plan plan=composition.plan(sourceWidth,sourceHeight,1);int[] framed=frame.dimensions(plan.width,plan.height);double scale=Math.min(1,320.0/Math.max(outputWidth,outputHeight));int w=Math.max(1,(int)Math.round(outputWidth*scale)),h=Math.max(1,(int)Math.round(outputHeight*scale));int[] pixels=new int[w*h];
        RectF photo=regionMaskPhotoRect(plan,frame,framed);double left=photo.left,top=photo.top,radius=regionMaskCorner(plan,frame);
        radius=Math.min(radius,Math.min(plan.width,plan.height)/2.0);AdjustmentRegion.Brush brush=region.compileBrush(sourceWidth,sourceHeight);
        for(int y=0;y<h;y++){if(cancel.getAsBoolean())throw new CancellationException();for(int x=0;x<w;x++){double px=(x+.5)*framed[0]/w-left,py=(y+.5)*framed[1]/h-top;if(px<0||py<0||px>=plan.width||py>=plan.height)continue;if(radius>0){double dx=px-Math.max(radius,Math.min(plan.width-radius,px)),dy=py-Math.max(radius,Math.min(plan.height-radius,py));if(dx*dx+dy*dy>radius*radius)continue;}double[] source=plan.inverse(px,py);if(source[0]<0||source[1]<0||source[0]>=sourceWidth||source[1]>=sourceHeight)continue;PhotoBodyWarp.source(bodyShape,source[0]/sourceWidth,source[1]/sourceHeight,source);int alpha=(int)Math.round(104*brush.weight(source[0],source[1]));pixels[y*w+x]=(alpha<<24)|0x00fff1e4;}}
        return Bitmap.createBitmap(pixels,w,h,Bitmap.Config.ARGB_8888);
    }
    public boolean isReady(){return ready;}public boolean isQuickProcessing(){return quickBusy;} public String label(){return hasDraft?contextLabel()+(adjustments.isNeutral()?"":" · 调节 "+adjustments.count()+" 项")+(localEdits.portrait.isNeutral()?"":" · 人像")+(border.isNone()?"":" · "+PhotoBorder.TEMPLATES[border.template])+(exported?"":" · 未导出"):parkedDraft?"已保存版本 · 未导出草稿已保留":"当前已保存版本";}
    public String contextLabel(){if(unrecoverableSaved&&ready)return "已保存版本";return !ready?preparationError.isEmpty()?"正在准备照片…":"准备失败 · 点按重试":!hasDraft&&bound!=null&&originalPhoto!=null&&!bound.file().equals(originalPhoto.file())?"已保存版本":(selected.isEmpty()?"无滤镜":selectedName+" · "+strength+"%");}
    public void retryPreparation(){if(!ready&&!preparationError.isEmpty()){DownloadedPhoto photo=bound;bound=null;bind(photo);}}
    public boolean dirty(){return ready&&hasDraft&&!exported;}
    public boolean matches(PhotoPresetBatch.Edit edit){return ready&&(edit.draft==null?bound.file().equals(edit.source.localPhoto()==null?null:edit.source.localPhoto().file()):hasDraft&&sourceSha.equals(edit.draft.sourceSha)&&selected.equals(edit.draft.presetSha)&&strength==edit.draft.strength&&adjustments.equals(edit.draft.adjustments)&&geometry.equals(edit.draft.geometry)&&border.equals(edit.draft.border)&&localEdits.equals(edit.draft.localEdits));}
    /** Ordinary entry resumes the photo's pending work; explicit version selection stays pixel-exact. */
    public void bind(DownloadedPhoto photo){bind(photo,false);}
    public void bindSavedVersion(DownloadedPhoto photo){unbind();bind(photo,true);}
    private void bind(DownloadedPhoto photo,boolean savedOnly){
        String nextOwner=accountOwner(activity);
        if(bound!=null&&photo!=null&&bound.file().equals(photo.file())&&owner.equals(nextOwner))return;
        unbind(); bound=photo; owner=nextOwner;savedVersionOnly=savedOnly;
        if(photo==null){refresh();return;} final int token=generation; final String scope=owner;
        io.execute(()->{
            try{
                if(!valid(token,scope))return;
                PhotoSavedVersion version=PhotoSavedVersion.resolve(batch,photo);DownloadedPhoto root=version.photo; String sha=PhotoEditStore.hashFile(root.file());
                PhotoEditStore.Draft stored=version.unrecoverable?null:new PhotoEditStore(activity.getFilesDir(),scope).read(sha);
                PhotoEditStore.Draft draft=!savedOnly&&stored!=null&&!stored.exported?stored:stored!=null&&stored.exported&&PhotoPresetBatch.matchesSavedDraft(photo,stored)?stored:null;
                Bitmap base=decode(root.file(),1280), fast=interactiveSource(base), shown=(draft==null||draft.exported)&&!root.file().equals(photo.file())?decode(photo.file(),1280):base;
                PresetPreviewProfile profile=draft==null||draft.presetSha.isEmpty()?null:PresetPreviewProfiles.fromPreset(draft.presetBytes());
                PhotoCaptureInfo capture=PhotoCaptureInfo.read(root.file());
                if(draft!=null&&!draft.exported&&draft.hasEffect())shown=renderFramed(base,draft.profile(),capture,activity);
                int maskSourceWidth=base.getWidth(),maskSourceHeight=base.getHeight();
                if(draft!=null&&draft.exported&&!root.file().equals(photo.file())){
                    // Saved pixels were composed at full resolution before being decoded for display.
                    maskSourceWidth=maskSourceHeight=0;
                    try{PhotoPresetRenderer.Dimensions full=PhotoPresetRenderer.dimensions(root.file(),null);maskSourceWidth=full.contentWidth;maskSourceHeight=full.contentHeight;}catch(IOException|RuntimeException unavailable){}
                }
                final int shownSourceWidth=maskSourceWidth,shownSourceHeight=maskSourceHeight;
                PresetLibrary local=new PresetLibrary(activity.getFilesDir()); PersonalPresetSync personal=new PersonalPresetSync(activity.getFilesDir(),local);
                java.util.List<PresetRecord> visible=new ArrayList<>();for(PresetRecord p:local.list())if(personal.visible(scope,p.id))visible.add(p);
                final String shownSha=root.file().equals(photo.file())?sha:PhotoEditStore.hashFile(photo.file());Bitmap result=shown;
                Bitmap atmosphere=EditorGlassDrawable.sample(shown),reference=composeReference(base,draft==null?PhotoGeometry.NONE:draft.geometry,draft==null?PhotoBorder.NONE:draft.border,capture,activity);
                main.post(()->{
                    if(!valid(token,scope))return;
                    unrecoverableSaved=version.unrecoverable;savedVersionOnly=savedOnly||version.unrecoverable;captureInfo=capture;originalPhoto=root;sourceSha=sha;displayedSha=shownSha;original=base;fastOriginal=fast;current=result;comparisonPreview=reference;displayedSourceWidth=shownSourceWidth;displayedSourceHeight=shownSourceHeight;displayedGeometry=draft==null?PhotoGeometry.NONE:draft.geometry;displayedBorder=draft==null?PhotoBorder.NONE:draft.border;displayedBodyShape=draft==null?PhotoBodyShape.NONE:draft.localEdits.portrait.bodyShape;glass=atmosphere;inlineRatio=draft==null||draft.geometry.isNeutral()?0:-1;plainThumb=Bitmap.createScaledBitmap(base,256,Math.max(1,base.getHeight()*256/base.getWidth()),true);thumb=plainThumb;
                    library=local;ready=true;preparationError="";hasDraft=draft!=null;exported=draft!=null&&draft.exported;parkedDraft=savedOnly&&stored!=null&&!stored.exported;
                    selected=draft==null?"":draft.presetSha;selectedName=draft==null?"原图":draft.name;selectedBytes=draft==null?new byte[0]:draft.presetBytes();strength=draft==null?100:draft.strength;selectedProfile=profile;
                    adjustments=draft==null?PhotoAdjustments.NONE:draft.adjustments;geometry=draft==null?PhotoGeometry.NONE:draft.geometry;border=draft==null?PhotoBorder.NONE:draft.border;localEdits=draft==null?PhotoLocalEdits.NONE:draft.localEdits;selectedRegionId="";undo.clear();redo.clear();loadRecipes();
                    entries.clear();for(PresetRecord p:visible)entries.add(new Entry(p));KNOWN.put(scope+":"+sha,stored!=null&&!stored.exported);
                    refreshManualThumbnails();if(onlineCatalog!=null&&SystemClock.elapsedRealtime()-catalogLoadedAt<300000){for(OnlinePreset p:catalogMetadata)onlineEntries.add(new Entry(p));catalogMessage=cachedCatalogMessage;catalogDiagnostic=cachedCatalogDiagnostic;refresh();host.changed();}else{refresh();host.changed();loadOnlineCatalog();}
                });
            }catch(Exception|OutOfMemoryError failure){main.post(()->{if(valid(token,scope)){preparationError=message(failure);refresh();host.changed();host.error(message(failure));}});}
        });
    }
    public void unbind(){
        if(versionExport!=null){versionExport.close();versionExport=null;}
        stopRegionMaskPeek();
        closeDetails();detailLoading=false;histogramOpen=false;diagnosticPreview=null;displayedSha="";if(histogramPanel!=null){histogramPanel.reset();histogramPanel.setVisibility(View.GONE);}savedVersionOnly=false;unrecoverableSaved=false;
        flushSave();generation++;previewRequest++;previewQueue.reset();interactivePreview=false;trackingSlider=null;cancelPendingRetry();thumbnails.getQueue().clear();dismissPopup();
        if(borderControls!=null)borderControls.invalidate();captureInfo=PhotoCaptureInfo.EMPTY;border=PhotoBorder.NONE;
        bound=null;ready=false;original=null;fastOriginal=null;current=null;comparisonPreview=null;displayedSourceWidth=displayedSourceHeight=0;displayedGeometry=PhotoGeometry.NONE;displayedBorder=PhotoBorder.NONE;displayedBodyShape=PhotoBodyShape.NONE;thumb=null;glass=null;originalPhoto=null;sourceSha="";entries.clear();onlineEntries.clear();catalogLoading=false;catalogMessage="正在加载在线滤镜…";catalogDiagnostic="";renderedEntries.clear();pendingChoice=null;parkedDraft=false;pickerFirst=pickerTop=0;selected="";selectedProfile=null;selectedBytes=new byte[0];hasDraft=false;visibleRequests.clear();stripCards.clear();categoryButtons.clear();if(strip!=null)strip.removeAllViews();if(categories!=null)categories.removeAllViews();if(filterScroll!=null)filterScroll.scrollTo(0,0);
        adjustments=PhotoAdjustments.NONE;geometry=PhotoGeometry.NONE;localEdits=PhotoLocalEdits.NONE;selectedRegionId="";brushLoading=false;compositionLoading=localLoading=portraitLoading=false;recipes.clear();thumbRevision++;plainThumb=null;undo.clear();redo.clear();dragStart=null;preparationError="";quickRequest++;quickBusy=false;quickState=null;quickAnalysis=null;
    }
    private boolean valid(int token,String scope){return !closed&&token==generation&&scope.equals(owner)&&scope.equals(accountOwner(activity));}
    public View createDock(){
        if(borderControls!=null)borderControls.close();
        stripCards.clear();categoryButtons.clear();visibleRequests.clear();addFiltersAction=null;
        dock=column();dock.setTag("editor-tool-dock");dock.setBackgroundColor(Color.TRANSPARENT);dock.setElevation(0);
        FrameLayout modes=new FrameLayout(activity);toolPanels=modes;modes.setTag("editor-tool-panels");dock.addView(modes,new LinearLayout.LayoutParams(-1,PhotoPrismaStyle.compact(activity)?dp(160):fp(184)));
        filterPanel=column();filterPanel.setTag("editor-filter-panel");modes.addView(filterPanel,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout heading=row();heading.setPadding(dp(20),0,dp(20),0);title=text("滤镜",14,TEXT);categories=row();sourceStatus=text("",11,MUTED);note=text("",11,MUTED);
        gridButton=iconButton(AppIcon.Kind.GRID,"查看全部滤镜",this::showAll);
        // Center the icon in the whole target, independently of TextView's empty text/compound metrics.
        gridButton.setCompoundDrawablesRelative(null,null,null,null);gridButton.setCompoundDrawablePadding(0);
        AppIcon gridIcon=new AppIcon(AppIcon.Kind.GRID,TEXT,activity.getResources().getDisplayMetrics().density);
        LayerDrawable gridFace=new LayerDrawable(new Drawable[]{sourceFace(outline(0x0fffffff,10,0x33ffffff),36,6),gridIcon});gridFace.setLayerSize(1,dp(19),dp(19));gridFace.setLayerGravity(1,Gravity.CENTER);
        gridButton.setBackground(gridFace);gridButton.setPadding(0,0,0,0);heading.addView(gridButton,new LinearLayout.LayoutParams(dp(48),-1));gridButton.setVisibility(View.GONE);heading.setOnLongClickListener(v->{showAll();return true;});
        LinearLayout sources=sourceToggle();onlineButton=button("在线",false,()->setOnlineSource(true));mineButton=button("我的",false,()->setOnlineSource(false));
        onlineButton.setTag("editor-source-online");mineButton.setTag("editor-source-mine");sources.addView(onlineButton,new LinearLayout.LayoutParams(dp(46),-1));sources.addView(mineButton,new LinearLayout.LayoutParams(dp(46),-1));heading.addView(sources,new LinearLayout.LayoutParams(-2,-1));sources.setVisibility(View.GONE);
        categoryStatus=text("",10,MUTED);categoryStatus.setGravity(Gravity.CENTER);categoryStatus.setMaxWidth(dp(42));categoryStatus.setSingleLine(true);categoryStatus.setPadding(dp(4),0,dp(4),0);categoryStatus.setOnClickListener(v->{if(!ready)retryPreparation();else if(onlineSource&&!catalogLoading)loadOnlineCatalog();});heading.addView(categoryStatus,new LinearLayout.LayoutParams(-2,-1));
        categoryScroll=new HorizontalScrollView(activity);categoryScroll.setHorizontalScrollBarEnabled(false);categoryScroll.setOverScrollMode(View.OVER_SCROLL_NEVER);categoryScroll.addView(categories);heading.addView(categoryScroll,new LinearLayout.LayoutParams(0,-1,1));filterPanel.addView(heading,new LinearLayout.LayoutParams(-1,dp(48)));
        onlineButton.setOnLongClickListener(v->{if(!catalogLoading)loadOnlineCatalog();return true;});
        filterScroll=new HorizontalScrollView(activity);filterScroll.setHorizontalScrollBarEnabled(false);filterScroll.setOverScrollMode(View.OVER_SCROLL_NEVER);strip=row();strip.setGravity(Gravity.CENTER_VERTICAL);strip.setPadding(dp(18),dp(2),dp(18),dp(3));filterScroll.addView(strip);filterPanel.addView(filterScroll,new LinearLayout.LayoutParams(-1,0,1));
        filterScroll.getViewTreeObserver().addOnScrollChangedListener(this::requestVisible);
        LinearLayout intensity=row();intensity.setPadding(dp(16),0,dp(16),0);TextView label=text("强度",11,MUTED);intensity.addView(label,new LinearLayout.LayoutParams(dp(38),-1));
        slider=new SeekBar(activity);slider.setMax(100);slider.setProgressTintList(ColorStateList.valueOf(BLUE));slider.setThumbTintList(ColorStateList.valueOf(BLUE));PhotoPrismaStyle.slider(activity,slider);slider.setContentDescription("滤镜强度，0 到 100 百分比");intensity.addView(slider,new LinearLayout.LayoutParams(0,-1,1));
        value=text("100",11,TEXT);value.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);value.setFocusable(true);value.setOnClickListener(v->showStrengthValue());intensity.addView(value,new LinearLayout.LayoutParams(dp(46),-1));filterPanel.addView(intensity,new LinearLayout.LayoutParams(-1,PhotoPrismaStyle.compact(activity)?dp(48):Math.max(dp(48),fp(46))));
        slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar s,int p,boolean user){if(user&&!updating&&ready&&!selected.isEmpty()){if(dragStart==null)dragStart=snapshot();strength=p;exported=false;hasDraft=true;value.setText(String.valueOf(p));schedulePreview();scheduleSave();if(trackingSlider!=s)finishDrag(false);}}public void onStartTrackingTouch(SeekBar s){stopRegionMaskPeek();if(ready){dragStart=snapshot();trackingSlider=s;interactivePreview=true;}}public void onStopTrackingTouch(SeekBar s){trackingSlider=null;finishDrag(false);}});

        adjustmentPanel=column();adjustmentPanel.setTag("editor-adjustment-panel");modes.addView(adjustmentPanel,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout controls=row();controls.setTag("editor-inline-adjustment");controls.setPadding(dp(10),0,dp(10),0);undoButton=iconButton(AppIcon.Kind.UNDO,"撤销",()->restoreHistory(false));redoButton=iconButton(AppIcon.Kind.REDO,"重做",()->restoreHistory(true));controls.addView(undoButton,new LinearLayout.LayoutParams(dp(48),-1));controls.addView(redoButton,new LinearLayout.LayoutParams(dp(48),-1));undoButton.setVisibility(View.GONE);redoButton.setVisibility(View.GONE);adjustmentCaption=text("亮度",12,MUTED);adjustmentCaption.setGravity(Gravity.START|Gravity.CENTER_VERTICAL);adjustmentCaption.setSingleLine(true);adjustmentCaption.setOnClickListener(v->showParameterHelp());adjustmentCaption.setContentDescription("参数说明");adjustmentCaption.setEllipsize(TextUtils.TruncateAt.END);controls.addView(adjustmentCaption,new LinearLayout.LayoutParams(Math.min(fp(64),dp(84)),dp(48)));
        adjustmentValue=text("0",12,BLUE);adjustmentValue.setGravity(Gravity.CENTER);adjustmentValue.setSingleLine(true);adjustmentValue.setEllipsize(TextUtils.TruncateAt.END);adjustmentValue.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));adjustmentValue.setFocusable(true);adjustmentValue.setOnClickListener(v->showExactValue());controls.addView(adjustmentValue,new LinearLayout.LayoutParams(Math.min(fp(60),dp(72)),dp(48)));adjustmentPanel.addView(controls,new LinearLayout.LayoutParams(-1,dp(PhotoPrismaStyle.compact(activity)?26:30)));
        adjustmentCaption.setTag("editor-adjustment-caption");brushScopeButton=iconButton(AppIcon.Kind.BRUSH,"作用范围：全图",this::showRegionScope);brushScopeButton.setTag("editor-brush-scope");
        controls.addView(brushScopeButton,controls.getChildCount()-1,new LinearLayout.LayoutParams(dp(48),-1));
        adjustmentValue.setOnLongClickListener(v->{showParameterHelp();return true;});adjustmentValue.setTooltipText("点击输入数值，长按查看参数说明");
        adjustmentSlider=new SeekBar(activity){private final Paint tick=new Paint(Paint.ANTI_ALIAS_FLAG);@Override protected void onDraw(Canvas canvas){tick.setColor(0x4dffffff);tick.setStrokeWidth(dp(1));float x=getPaddingLeft()+(getWidth()-getPaddingLeft()-getPaddingRight())*(-parameter.min)/(float)(parameter.max-parameter.min);canvas.drawLine(x,getHeight()/2f-dp(5),x,getHeight()/2f+dp(5),tick);super.onDraw(canvas);}};adjustmentSlider.setProgressTintList(ColorStateList.valueOf(BLUE));adjustmentSlider.setThumbTintList(ColorStateList.valueOf(BLUE));PhotoPrismaStyle.slider(activity,adjustmentSlider);controls.removeView(brushScopeButton);controls.addView(adjustmentSlider,controls.indexOfChild(adjustmentValue),new LinearLayout.LayoutParams(0,dp(48),1));controls.addView(brushScopeButton,new LinearLayout.LayoutParams(dp(48),dp(48)));
        adjustmentSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar s,int p,boolean user){if(user&&!updating&&ready&&!unrecoverableSaved){if(dragStart==null)dragStart=snapshot();if(!setEditingAdjustments(editingAdjustments().with(parameter,p+parameter.min)))return;hasDraft=true;exported=false;updateDraggingReadout();scheduleSave();schedulePreview();if(trackingSlider!=s)finishDrag(true);}}public void onStartTrackingTouch(SeekBar s){stopRegionMaskPeek();if(ready){dragStart=snapshot();trackingSlider=s;interactivePreview=true;}}public void onStopTrackingTouch(SeekBar s){trackingSlider=null;finishDrag(true);}});

        // The approved prototype separates caption/value from the full-width slider.
        controls.removeView(adjustmentSlider);controls.removeView(brushScopeButton);
        controls.setPadding(dp(21),0,dp(21),0);adjustmentCaption.setTextColor(TEXT);adjustmentValue.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);
        adjustmentCaption.setLayoutParams(new LinearLayout.LayoutParams(0,-1,1));adjustmentValue.setLayoutParams(new LinearLayout.LayoutParams(fp(64),-1));
        LinearLayout sliderLine=row();sliderLine.setPadding(dp(8),0,dp(8),0);sliderLine.addView(adjustmentSlider,new LinearLayout.LayoutParams(-1,dp(48)));adjustmentPanel.addView(sliderLine);
        HorizontalScrollView parameters=new HorizontalScrollView(activity);parameters.setTag("editor-adjustment-tools");parameters.setContentDescription("调节工具，左右滑动选择；曲线、HSL、调色盘、去灰和局部可直接打开");parameters.setHorizontalScrollBarEnabled(false);parameters.setOverScrollMode(View.OVER_SCROLL_NEVER);LinearLayout options=row();options.setGravity(Gravity.CENTER_VERTICAL);options.setPadding(dp(8),0,dp(8),0);parameters.addView(options);parameterControls.clear();
        paletteControl=PhotoWorkspaceUi.toolEntry(activity,"调色盘","editor-palette",AppIcon.Kind.PALETTE,this::showPalette);paletteControl.setContentDescription("调色盘，拖动白点调整颜色与影调");options.addView(paletteControl,new LinearLayout.LayoutParams(PhotoWorkspaceUi.entryWidth(activity),-1));
        cleanupControl=PhotoWorkspaceUi.toolEntry(activity,"去灰","editor-cleanup",AppIcon.Kind.CLEANUP,this::showCleanup);cleanupControl.setContentDescription("去灰，自动分析灰雾与噪点");options.addView(cleanupControl,new LinearLayout.LayoutParams(PhotoWorkspaceUi.entryWidth(activity),-1));
        portraitControl=PhotoWorkspaceUi.toolEntry(activity,"人像","editor-portrait",AppIcon.Kind.PERSON,this::showPortrait);portraitControl.setContentDescription("人像精修，肤色、面部修饰、瘦身、瘦腿与腿部拉长");options.addView(portraitControl,new LinearLayout.LayoutParams(PhotoWorkspaceUi.entryWidth(activity),-1));
        localControl=PhotoWorkspaceUi.toolEntry(activity,"局部","editor-local",AppIcon.Kind.ADJUST,this::showRegionScope);localControl.setContentDescription("局部调节，涂抹范围与区域管理");options.addView(localControl,new LinearLayout.LayoutParams(PhotoWorkspaceUi.entryWidth(activity),-1));
        advancedControls.clear();for(boolean curve:new boolean[]{true,false}){
            LinearLayout advanced=column();advanced.setGravity(Gravity.CENTER_HORIZONTAL);advanced.setPadding(0,dp(6),0,0);advanced.setFocusable(true);advanced.setClickable(true);advanced.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335),shape(Color.TRANSPARENT,4),null));advanced.setTag(curve?"editor-curves":"editor-hsl");
            ImageView image=new ImageView(activity);image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);image.setImageDrawable(new AppIcon(curve?AppIcon.Kind.CURVE:AppIcon.Kind.SATURATION,0x99ffffff,activity.getResources().getDisplayMetrics().density));advanced.addView(image,new LinearLayout.LayoutParams(dp(26),dp(26)));
            TextView caption=parameterCaption(curve?"曲线":"HSL");LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(-1,fp(20));cp.topMargin=dp(4);advanced.addView(caption,cp);
            advanced.setOnClickListener(v->showColor(curve));advanced.setContentDescription(curve?"编辑 RGB 与单色通道曲线":"编辑分色 HSL");options.addView(advanced,new LinearLayout.LayoutParams(fp(56),-1));advancedControls.put(curve,advanced);
        }
        for(PhotoAdjustments.Parameter p:PhotoAdjustments.Parameter.values()){
            LinearLayout option=column();option.setGravity(Gravity.CENTER_HORIZONTAL);option.setPadding(0,dp(6),0,0);option.setFocusable(true);option.setClickable(true);option.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335),shape(Color.TRANSPARENT,4),null));
            ImageView image=new ImageView(activity);image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);option.addView(image,new LinearLayout.LayoutParams(dp(26),dp(26)));TextView caption=parameterCaption(p.label);LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(-1,fp(20));cp.topMargin=dp(4);option.addView(caption,cp);
            option.setTag("editor-parameter-"+p.name());option.setOnClickListener(v->{finishDrag(true);parameter=p;updateAdjustmentControls();PhotoWorkspaceUi.revealChoice(parameters,option);});option.setOnLongClickListener(v->{resetParameter(p);return true;});options.addView(option,new LinearLayout.LayoutParams(fp(Math.max(56,p.label.length()>4?72:56)),-1));parameterControls.put(p,option);
        }
        // Keep everyday controls first; specialised tools are peers on this same rail, never a submenu.
        options.removeAllViews();
        PhotoAdjustments.Parameter[] everyday={PhotoAdjustments.Parameter.EXPOSURE,PhotoAdjustments.Parameter.CONTRAST,PhotoAdjustments.Parameter.SATURATION,PhotoAdjustments.Parameter.TEMPERATURE};
        for(PhotoAdjustments.Parameter p:everyday){LinearLayout item=parameterControls.get(p);options.addView(item,item.getLayoutParams());}
        for(boolean curve:new boolean[]{true,false}){LinearLayout item=advancedControls.get(curve);options.addView(item,item.getLayoutParams());}
        for(View item:new View[]{paletteControl,cleanupControl,localControl})options.addView(item,item.getLayoutParams());
        for(PhotoAdjustments.Parameter p:PhotoAdjustments.Parameter.values()){boolean included=false;for(PhotoAdjustments.Parameter common:everyday)if(p==common)included=true;if(!included){LinearLayout item=parameterControls.get(p);options.addView(item,item.getLayoutParams());}}
        adjustmentPanel.addView(new View(activity),new LinearLayout.LayoutParams(1,0,1));
        adjustmentPanel.addView(parameters,new LinearLayout.LayoutParams(-1,PhotoPrismaStyle.compact(activity)?dp(66):PhotoWorkspaceUi.entryHeight(activity)+dp(4)));
        parameters.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{int width=Math.max(dp(48),(parameters.getWidth()-options.getPaddingLeft()-options.getPaddingRight())/4);for(int i=0;i<options.getChildCount();i++){View child=options.getChildAt(i);if(child.getLayoutParams().width!=width){child.getLayoutParams().width=width;child.requestLayout();}}});
        TextView parameterHint=text("长按参数图标，恢复此项",10,0xb8ffffff);parameterHint.setPadding(dp(21),0,dp(21),0);adjustmentPanel.addView(parameterHint,new LinearLayout.LayoutParams(-1,PhotoPrismaStyle.compact(activity)?dp(20):fp(22)));
        compositionPanel=column();compositionPanel.setTag("editor-composition-panel");compositionPanel.setPadding(dp(14),0,dp(14),0);modes.addView(compositionPanel,new FrameLayout.LayoutParams(-1,-1));
        compositionTools.clear();inlineRatios.clear();LinearLayout ratios=row();String[] ratioNames={"原比例","1:1","2:3","3:2","9:16"};
        for(int i=0;i<INLINE_RATIOS.length;i++){final double ratio=INLINE_RATIOS[i];Button item=button(ratioNames[i],false,()->chooseInlineRatio(ratio));item.setTag("editor-crop-ratio-"+i);item.setContentDescription("裁切比例，"+ratioNames[i]);item.setTextSize(10.5f);item.setGravity(Gravity.CENTER);item.setPadding(0,dp(7),0,0);item.setCompoundDrawablePadding(dp(5));ratios.addView(item,new LinearLayout.LayoutParams(0,PhotoPrismaStyle.compact(activity)?dp(64):fp(76),1));inlineRatios.add(item);compositionTools.add(item);}compositionPanel.addView(ratios);
        LinearLayout transforms=row();transforms.setGravity(Gravity.CENTER);compositionPanel.addView(transforms,new LinearLayout.LayoutParams(-1,dp(48)));
        Button rotate=inlineCompositionAction("旋转 90°",AppIcon.Kind.ROTATE,"editor-composition-rotate",this::rotateInline);
        Button flip=inlineCompositionAction("水平翻转",AppIcon.Kind.FLIP_HORIZONTAL,"editor-composition-flip",()->changeComposition(geometry.flipHorizontal()));
        compositionReset=inlineCompositionAction("重置",AppIcon.Kind.REFRESH,"editor-composition-reset",this::resetComposition);
        transforms.addView(rotate,new LinearLayout.LayoutParams(0,-1,1));transforms.addView(flip,new LinearLayout.LayoutParams(0,-1,1));transforms.addView(compositionReset,new LinearLayout.LayoutParams(0,-1,1));
        compositionSummary=text("切换比例，预览居中裁切效果",10,0xbdffffff);compositionSummary.setTag("editor-composition-summary");compositionSummary.setGravity(Gravity.CENTER);compositionSummary.setSingleLine(true);compositionSummary.setEllipsize(TextUtils.TruncateAt.END);compositionSummary.setContentDescription("切换比例预览居中裁切，点击打开精细裁切、拉直与透视");compositionSummary.setOnClickListener(v->showComposition());compositionPanel.addView(compositionSummary,new LinearLayout.LayoutParams(-1,PhotoPrismaStyle.compact(activity)?dp(40):fp(40)));
        recipePanel=column();recipePanel.setTag("editor-recipe-panel");recipePanel.setPadding(dp(16),0,dp(16),0);modes.addView(recipePanel,new FrameLayout.LayoutParams(-1,-1));LinearLayout recipeHeader=row();TextView recipeTitle=text("配方",12,TEXT);recipeTitle.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));recipeHeader.addView(recipeTitle,new LinearLayout.LayoutParams(0,-1,1));recipePanel.addView(recipeHeader,new LinearLayout.LayoutParams(-1,fp(36)));
        saveRecipeButton=button("保存当前",false,this::saveRecipeDialog);saveRecipeButton.setTextSize(12);AppIcon plus=new AppIcon(AppIcon.Kind.PLUS,BLUE,activity.getResources().getDisplayMetrics().density);plus.setBounds(0,0,dp(15),dp(15));saveRecipeButton.setCompoundDrawables(null,null,null,null);GradientDrawable dashed=shape(Color.TRANSPARENT,10);dashed.setStroke(dp(1),0x42ffffff,dp(4),dp(3));saveRecipeButton.setBackground(new InsetDrawable(dashed,0,dp(5),0,dp(5)));recipePanel.addView(saveRecipeButton,new LinearLayout.LayoutParams(-1,Math.max(dp(48),fp(38))));
        ScrollView recipeScroll=new ScrollView(activity);recipeRows=column();recipeScroll.addView(recipeRows);recipePanel.addView(recipeScroll,new LinearLayout.LayoutParams(-1,0,1));recipeStatus=text("",10,0x70ffffff);recipeStatus.setGravity(Gravity.CENTER);recipeStatus.setSingleLine(true);recipeStatus.setEllipsize(TextUtils.TruncateAt.END);recipeStatus.setTooltipText("保存滤镜与调节，仅存本机当前账号");recipeStatus.setVisibility(View.GONE);recipePanel.addView(recipeStatus,new LinearLayout.LayoutParams(-1,fp(20)));updateRecipeRows();
        borderControls=new PhotoBorderPanel(activity,new PhotoBorderPanel.Host(){
            public PhotoBorder border(){return border;}public PhotoCaptureInfo capture(){return captureInfo;}public boolean ready(){return ready;}public String identity(){return owner+":"+generation+":"+sourceSha;}
            public Bitmap thumbnail(){return plainThumb;}public PresetPreviewProfile colour(){return GeometryPreviewProfile.of(LocalEditsPreviewProfile.of(AdjustedPreviewProfile.of(selectedProfile==null?null:StrengthPreviewProfile.of(selectedProfile,strength),adjustments),localEdits),geometry);}
            public void change(PhotoBorder value){if(!readableSettings()||border.equals(value))return;finishDrag(true);EditState before=snapshot();border=value;remember(before);edited();}
            public void startDrag(){if(!readableSettings())return;finishDrag(true);dragStart=snapshot();interactivePreview=true;}
            public void dragChange(PhotoBorder value){if(!ready||unrecoverableSaved||border.equals(value))return;border=value;hasDraft=true;exported=false;schedulePreview();scheduleSave();}
            public void endDrag(){finishDrag(true);if(borderControls!=null)borderControls.refresh();}
            public void undo(){restoreHistory(false);}public void redo(){restoreHistory(true);}public boolean canUndo(){return !undo.isEmpty();}public boolean canRedo(){return !redo.isEmpty();}public void error(String message){host.error(message);}
        });borderPanel=borderControls.create();modes.addView(borderPanel,new FrameLayout.LayoutParams(-1,-1));

        LinearLayout nav=row();nav.setTag("editor-tool-tabs");nav.setGravity(Gravity.CENTER);nav.setBackgroundColor(0xff0e0d0c);filterModeButton=button("滤镜",false,()->setAdjustmentMode(false));adjustmentModeButton=button("调节",false,()->setAdjustmentMode(true));
        nav.addView(filterModeButton,new LinearLayout.LayoutParams(0,-1,1));nav.addView(adjustmentModeButton,new LinearLayout.LayoutParams(0,-1,1));
        Button compose=button("构图",false,()->{finishDrag(true);compositionMode=true;borderMode=false;recipeMode=false;updateModes();});compose.setTag("composition-mode");nav.addView(compose,new LinearLayout.LayoutParams(0,-1,1));
        Button borderButton=button("边框",false,()->{finishDrag(true);compositionMode=false;borderMode=true;recipeMode=false;updateModes();});borderButton.setTag("border-mode");nav.addView(borderButton,new LinearLayout.LayoutParams(0,-1,1));
        Button recipeButton=button("配方",false,()->{finishDrag(true);compositionMode=false;recipeMode=true;borderMode=false;updateModes();loadRecipes();});recipeButton.setTag("recipe-mode");nav.addView(recipeButton,new LinearLayout.LayoutParams(0,-1,1));dock.addView(nav,new LinearLayout.LayoutParams(-1,PhotoWorkspaceUi.tabHeight(activity)));
        nav.setVisibility(View.GONE);
        compactDock=new PhotoCompactDock(activity,dock,new PhotoCompactDock.Host(){
            public boolean ready(){return PhotoFilterEditor.this.ready&&!unrecoverableSaved;}
            public boolean canUndo(){return !undo.isEmpty();}public boolean canRedo(){return !redo.isEmpty();}public void history(boolean forward){restoreHistory(forward);}
            public Bitmap thumbnail(){return plainThumb;}public int quickStyle(){QuickState q=matchingQuick();return q!=null?q.style:adjustments.isNeutral()&&localEdits.isNeutral()&&selected.isEmpty()&&geometry.isNeutral()&&border.isNone()?0:-1;}
            public int quickAmount(){QuickState q=matchingQuick();return q==null?0:q.amount;}public boolean quickBusy(){return quickBusy;}public String quickMessage(){return quickStyle()<0?"已有调整 · 可继续微调":"";}
            public void quick(int style){chooseQuick(style);}public void quickAmount(int amount){dragQuick(amount);}
            public void beginDrag(){finishDrag(true);dragStart=snapshot();interactivePreview=true;}
            public void endDrag(){finishDrag(true);}
            public void legacy(int mode){if(mode==PhotoCompactDock.ADVANCED){showAll();return;}compositionMode=mode==PhotoCompactDock.CROP;recipeMode=mode==PhotoCompactDock.RECIPE;borderMode=mode==PhotoCompactDock.BORDER;adjustmentMode=mode==PhotoCompactDock.ADJUST;updateModes();if(recipeMode)loadRecipes();}
            public String effectLabel(){return !ready?(preparationError.isEmpty()?"正在准备照片":"准备失败，点击文件名重试"):selected.isEmpty()?(adjustments.isNeutral()&&localEdits.isNeutral()?"原图":"原图 · 已调整"):selectedName+" · "+strength+"%";}
            public void reset(){PhotoFilterEditor.this.reset(true);}
            public void openComposition(){PhotoFilterEditor.this.showComposition();}
            public void portrait(int section){if(section==3)showCompactBody();else{portraitSection=section;showPortrait();}}
        });
        refresh();return compactDock;
    }
    private int fp(float n){return dp(n*Math.max(1,activity.getResources().getConfiguration().fontScale));}
    public FrameLayout comparisonMount(){return compactDock==null?null:compactDock.comparisonMount();}
    private QuickState matchingQuick(){if(quickState!=null&&quickState.applied.equals(adjustments)&&quickState.appliedPortrait.equals(localEdits.portrait))return quickState;int style=PhotoQuickPreset.detect(adjustments,localEdits.portrait);if(style<0){quickState=null;return null;}quickState=new QuickState(style,PhotoQuickPreset.amount(adjustments,localEdits.portrait,style),adjustments,localEdits.portrait,adjustments.cleanup.analysis);return quickState;}
    private void chooseQuick(int style){
        if(!readableSettings())return;finishDrag(true);quickRequest++;quickBusy=false;
        if(style==PhotoQuickPreset.ORIGINAL){quickState=null;reset(true);if(compactDock!=null)compactDock.refresh();return;}
        QuickState previous=matchingQuick();final PhotoAdjustments base=previous==null?adjustments:previous.base;
        final PhotoPortrait portrait=previous==null?localEdits.portrait:previous.portrait;
        final int amount=style==PhotoQuickPreset.CLEAR?48:style==PhotoQuickPreset.PORTRAIT?45:55;
        final EditState starting=snapshot();final int token=generation;final String scope=owner,sha=sourceSha;final long request=quickRequest;
        if(originalPhoto==null)return;final File file=originalPhoto.file();quickBusy=true;if(compactDock!=null)compactDock.refresh();host.changed();
        io.execute(()->{Bitmap analysisBitmap=null;try{
            java.util.function.BooleanSupplier cancelled=()->!valid(token,scope)||request!=quickRequest;
            PhotoCleanup.Analysis cleanup=quickAnalysis!=null?quickAnalysis:PhotoCleanupAnalyzer.analyze(file,sha,null,cancelled);
            PhotoPortrait prepared=portrait;
            if(style==PhotoQuickPreset.PORTRAIT){analysisBitmap=decode(file,1600);PhotoPersonAnalysis.Result found=PhotoPersonAnalysis.analyze(activity.getApplicationContext(),analysisBitmap,cancelled);prepared=PhotoPortraitBatch.merge(portrait,null,found,true).withRetouch(portrait.retouch);}
            if(cancelled.getAsBoolean())return;if(!sha.equals(PhotoEditStore.hashFile(file)))throw new IOException("照片内容已变化，请重新打开。");final PhotoPortrait readyPortrait=prepared;
            main.post(()->{if(!valid(token,scope)||request!=quickRequest)return;quickBusy=false;
                if(!starting.same(snapshot())){if(compactDock!=null)compactDock.refresh();host.changed();return;}
                quickAnalysis=cleanup;EditState before=snapshot();QuickState next=new QuickState(style,amount,base,readyPortrait,cleanup);quickState=next;adjustments=next.applied;localEdits=localEdits.withPortrait(next.appliedPortrait);remember(before);edited();refreshManualThumbnails();
            });
        }catch(Exception|LinkageError|OutOfMemoryError failure){main.post(()->{if(valid(token,scope)&&request==quickRequest){quickBusy=false;if(compactDock!=null)compactDock.refresh();host.changed();host.error("快速优化未完成："+message(failure));}});}finally{if(analysisBitmap!=null)analysisBitmap.recycle();}});
    }
    private void dragQuick(int amount){
        QuickState previous=matchingQuick();if(previous==null||quickBusy||!ready)return;boolean single=dragStart==null;if(single)dragStart=snapshot();
        QuickState next=new QuickState(previous.style,amount,previous.base,previous.portrait,previous.analysis);quickState=next;adjustments=next.applied;localEdits=localEdits.withPortrait(next.appliedPortrait);hasDraft=true;exported=false;parkedDraft=false;schedulePreview();scheduleSave();if(single)finishDrag(true);
    }
    private void showCompactBody(){
        if(!readableSettings()||portraitLoading)return;finishDrag(true);dismissPopup();portraitLoading=true;
        final int token=generation;final String scope=owner;final EditState starting=snapshot();final Bitmap base=original,fast=fastOriginal==null?base:fastOriginal;final PhotoCaptureInfo capture=captureInfo;
        final PresetPreviewProfile global=AdjustedPreviewProfile.of(starting.profile==null?null:StrengthPreviewProfile.of(starting.profile,starting.strength),starting.manual);
        io.execute(()->{try{Bitmap entering=render(base,LocalEditsPreviewProfile.of(global,starting.localEdits));main.post(()->{
            if(!valid(token,scope)){entering.recycle();return;}portraitLoading=false;if(!starting.same(snapshot())){entering.recycle();return;}
            PhotoBodyDialog dialog=new PhotoBodyDialog(activity,entering,starting.localEdits.portrait.bodyShape,(next,interactive)->{
                if(!valid(token,scope)||!starting.same(snapshot()))throw new IOException("照片已变化，请重新打开塑形。");
                PhotoLocalEdits edits=starting.localEdits.withPortrait(starting.localEdits.portrait.withBodyShape(next));
                return render(interactive?fast:base,LocalEditsPreviewProfile.of(global,edits));
            },next->{if(valid(token,scope)&&starting.same(snapshot())&&!next.equals(localEdits.portrait.bodyShape)){EditState before=snapshot();localEdits=localEdits.withPortrait(localEdits.portrait.withBodyShape(next));remember(before);edited();refreshManualThumbnails();}});
            dialog.setAnalysisSource(base);popup=dialog;dialog.setOnDismissListener(v->{if(popup==dialog)popup=null;entering.recycle();});dialog.show();PhotoEditorTypography.apply(dialog);
        });}catch(Exception|OutOfMemoryError failure){main.post(()->{if(valid(token,scope)){portraitLoading=false;host.error(message(failure));}});}});
    }
    private GradientDrawable outline(int color,int radius,int stroke){GradientDrawable d=shape(color,radius);d.setStroke(Math.max(1,dp(1)),stroke);return d;}
    private void showStrengthValue(){
        if(!ready||selected.isEmpty()||unrecoverableSaved)return;final int token=generation;final String scope=owner,id=selected;finishDrag(true);
        EditText input=new EditText(new ContextThemeWrapper(activity,cc.huevia.R.style.AppThemeDark));input.setTextSize(13);input.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);input.setText(String.valueOf(strength));input.selectAll();LinearLayout form=column();form.setPadding(dp(20),0,dp(20),0);form.addView(input,new LinearLayout.LayoutParams(-1,dp(48)));
        AlertDialog d=new PhotoEditorTypography.Builder(new ContextThemeWrapper(activity,cc.huevia.R.style.AppThemeDark)).setTitle("滤镜强度（0–100）").setView(form).setNegativeButton("取消",null).setPositiveButton("应用",null).create();popup=d;d.setOnShowListener(v->d.getButton(-1).setOnClickListener(w->{int n;try{n=Integer.parseInt(input.getText().toString().trim());}catch(Exception e){input.setError("请输入 0–100 的整数");return;}if(n<0||n>100){input.setError("请输入 0–100 的整数");return;}if(valid(token,scope)&&id.equals(selected)&&n!=strength){EditState before=snapshot();strength=n;remember(before);edited();}d.dismiss();}));d.setOnDismissListener(v->{if(popup==d)popup=null;});d.show();PhotoEditorTypography.apply(d);
    }
    private void refresh(){
        if(dock==null)return;updating=true;slider.setProgress(selected.isEmpty()?0:strength);slider.setEnabled(ready&&!selected.isEmpty());value.setText(String.valueOf(selected.isEmpty()?0:strength));value.setTextColor(selected.isEmpty()?0x99ffffff:TEXT);value.setEnabled(ready&&!selected.isEmpty());updating=false;
        note.setText(!ready?(bound==null?"下载完整原图后即可使用滤镜 · 点按下载":"正在准备当前照片的滤镜…"):label()+(parkedDraft?" · 点按恢复编辑":" · 手机近似效果"));note.setTooltipText(note.getText());note.setOnClickListener(parkedDraft?v->{DownloadedPhoto photo=bound;unbind();bind(photo,false);}:!ready&&bound==null?v->host.download():null);
        title.setText("滤镜");styleSource(onlineButton,onlineSource);styleSource(mineButton,!onlineSource);
        updateCatalogStatus(sourceStatus);
        buildCategories();buildStrip();updateAdjustmentControls();updateModes();
        String status=!ready?(preparationError.isEmpty()?"准备中":"准备失败 · 重试"):onlineSource&&!catalogMessage.isEmpty()?(catalogLoading?"加载中":catalogMessage.startsWith("离线")?"离线缓存":catalogMessage.contains("失败")?"加载失败":"") :"";
        categoryStatus.setText(status.equals("离线缓存")?"缓存":status.contains("失败")?"重试":status.contains("准备")?"准备":status.isEmpty()?"":"加载");categoryStatus.setVisibility(status.isEmpty()||activity.getResources().getConfiguration().orientation==android.content.res.Configuration.ORIENTATION_LANDSCAPE?View.GONE:View.VISIBLE);categoryStatus.setContentDescription(status+"。"+sourceStatus.getText());categoryStatus.setTooltipText(sourceStatus.getTooltipText());onlineButton.setContentDescription("在线滤镜，"+sourceStatus.getText());onlineButton.setTooltipText(sourceStatus.getTooltipText());categoryScroll.setContentDescription("左右滑动选择滤镜分类，"+(category.isEmpty()?"全部":category)+"。"+sourceStatus.getText());categoryScroll.setTooltipText(sourceStatus.getTooltipText());if(compactDock!=null)compactDock.refresh();
    }
    private Button iconButton(AppIcon.Kind kind,String label,Runnable action){Button b=button("",false,action);b.setCompoundDrawablesRelativeWithIntrinsicBounds(icon(kind),null,null,null);b.setPadding(dp(12),0,dp(12),0);b.setContentDescription(label);b.setTooltipText(label);return b;}
    private void setAdjustmentMode(boolean value){finishDrag(true);compositionMode=false;recipeMode=false;borderMode=false;adjustmentMode=value;updateModes();}
    private void updateModes(){
        if(filterPanel==null)return;host.workspaceMode(compositionMode);boolean plain=!compositionMode&&!borderMode&&!recipeMode;
        int panelHeight=compactDock!=null?compactDock.panelHeightPx():PhotoPrismaStyle.compact(activity)?dp(160):fp(184);if(toolPanels.getLayoutParams().height!=panelHeight){toolPanels.getLayoutParams().height=panelHeight;toolPanels.requestLayout();}
        filterPanel.setVisibility(plain&&!adjustmentMode?View.VISIBLE:View.INVISIBLE);adjustmentPanel.setVisibility(plain&&adjustmentMode?View.VISIBLE:View.INVISIBLE);compositionPanel.setVisibility(compositionMode?View.VISIBLE:View.INVISIBLE);recipePanel.setVisibility(!compositionMode&&!borderMode&&recipeMode?View.VISIBLE:View.INVISIBLE);if(borderPanel!=null)borderPanel.setVisibility(!compositionMode&&borderMode?View.VISIBLE:View.INVISIBLE);
        styleCategory(filterModeButton,plain&&!adjustmentMode);styleCategory(adjustmentModeButton,plain&&adjustmentMode);
        Button recipe=dock.findViewWithTag("recipe-mode"),frame=dock.findViewWithTag("border-mode"),compose=dock.findViewWithTag("composition-mode");if(recipe!=null)styleCategory(recipe,recipeMode&&!compositionMode&&!borderMode);if(frame!=null)styleCategory(frame,borderMode&&!compositionMode);if(compose!=null)styleCategory(compose,compositionMode);
        if(original!=null&&!original.isRecycled()){PhotoGeometry.Plan plan=geometry.plan(original.getWidth(),original.getHeight(),1),full=geometry.fullFrame().plan(original.getWidth(),original.getHeight(),1);double actual=plan.width/(double)plan.height,frameRatio=full.width/(double)full.height;if(inlineRatio<0||Math.abs(actual-(inlineRatio==0?frameRatio:inlineRatio))>.01){inlineRatio=-1;for(double ratio:INLINE_RATIOS)if(Math.abs(actual-(ratio==0?frameRatio:ratio))<.01){inlineRatio=ratio;break;}}}
        compositionSummary.setTooltipText(geometry.label()+"，点击精细构图");for(int i=0;i<inlineRatios.size();i++){Button item=inlineRatios.get(i);boolean selected=inlineRatio==INLINE_RATIOS[i];item.setSelected(selected);item.setTextColor(selected?BLUE:0xc9ffffff);Drawable ratioIcon=PhotoPrismaStyle.ratio(activity,INLINE_RATIOS[i],selected);ratioIcon.setBounds(0,0,dp(30),dp(30));item.setCompoundDrawables(null,ratioIcon,null,null);item.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335),null,shape(Color.WHITE,4)));}
        boolean compositionReady=ready&&!unrecoverableSaved;for(View tool:compositionTools){tool.setEnabled(compositionReady);tool.setAlpha(compositionReady?1:.35f);}compositionReset.setEnabled(compositionReady&&!geometry.isNeutral());compositionReset.setAlpha(compositionReset.isEnabled()?1:.3f);if(borderControls!=null)borderControls.refresh();
    }
    private View compositionTool(AppIcon.Kind kind,String label,String tag,int tool){
        LinearLayout item=column();item.setGravity(Gravity.CENTER);item.setTag(tag);item.setFocusable(true);item.setClickable(true);item.setMinimumHeight(dp(48));item.setPadding(dp(4),0,dp(4),dp(6));item.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335),shape(Color.TRANSPARENT,10),null));
        ImageView image=new ImageView(activity);image.setImageDrawable(new AppIcon(kind,TEXT,activity.getResources().getDisplayMetrics().density));image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);item.addView(image,new LinearLayout.LayoutParams(dp(24),dp(24)));
        TextView caption=text(label,11,TEXT);caption.setGravity(Gravity.CENTER);caption.setSingleLine(true);caption.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(-1,fp(20));cp.topMargin=dp(4);item.addView(caption,cp);
        String description=tool==PhotoCropDialog.TOOL_ROTATE?"向右旋转90度，预览后应用":tool==PhotoCropDialog.TOOL_STRAIGHTEN?"拉直照片":tool==PhotoCropDialog.TOOL_PERSPECTIVE?"校正水平或垂直透视":"裁剪照片";item.setContentDescription(description);item.setTooltipText(description);item.setOnClickListener(v->showComposition(tool));compositionTools.add(item);return item;
    }
    private Button inlineCompositionAction(String label,AppIcon.Kind kind,String tag,Runnable action){
        Button button=button(label,false,action);button.setTag(tag);button.setTextColor(TEXT);button.setTextSize(10.5f);button.setPadding(dp(3),0,dp(3),0);button.setSingleLine(true);button.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335),null,shape(Color.WHITE,6)));
        Drawable icon=new AppIcon(kind,TEXT,activity.getResources().getDisplayMetrics().density);icon.setBounds(0,0,dp(17),dp(17));button.setCompoundDrawables(icon,null,null,null);button.setCompoundDrawablePadding(dp(4));compositionTools.add(button);return button;
    }
    private void chooseInlineRatio(double ratio){
        if(!readableSettings()||original==null)return;inlineRatio=ratio;
        PhotoGeometry.Plan frame=geometry.fullFrame().plan(original.getWidth(),original.getHeight(),1);
        double normalized=ratio==0?1:ratio*frame.frameHeight/frame.frameWidth,w=Math.min(1,normalized),h=w/normalized;
        changeComposition(geometry.crop((1-w)/2,(1-h)/2,(1+w)/2,(1+h)/2));
        updateModes();
    }
    private void changeComposition(PhotoGeometry next){if(!readableSettings()||geometry.equals(next))return;finishDrag(true);EditState before=snapshot();geometry=next;remember(before);edited();refreshManualThumbnails();}
    private void rotateInline(){
        PhotoGeometry next=geometry.rotate();
        if(inlineRatio>0&&original!=null){PhotoGeometry.Plan frame=next.fullFrame().plan(original.getWidth(),original.getHeight(),1);double normalized=inlineRatio*frame.frameHeight/frame.frameWidth,w=Math.min(1,normalized),h=w/normalized;next=next.crop((1-w)/2,(1-h)/2,(1+w)/2,(1+h)/2);}
        changeComposition(next);
    }
    private void resetComposition(){if(!readableSettings()||geometry.isNeutral())return;finishDrag(true);EditState before=snapshot();geometry=PhotoGeometry.NONE;inlineRatio=0;remember(before);edited();refreshManualThumbnails();}
    private void selectCategory(String name){
        if(!ready||category.equals(name)||!categoryNames().contains(name))return;
        cancelPendingRetry();pendingChoice=null;category=name;buildCategories();buildStrip();refreshPickerMetadata();
        if(gridAdapter!=null)gridAdapter.notifyDataSetChanged();resetPickerPosition();
        final HorizontalScrollView target=filterScroll;final int token=generation;
        if(target!=null)target.post(()->{if(generation==token&&filterScroll==target)target.scrollTo(0,0);});
        final Button selectedCategory=categoryButtons.get(name);
        if(selectedCategory!=null)selectedCategory.post(()->{if(generation==token&&categoryButtons.get(name)==selectedCategory)selectedCategory.requestRectangleOnScreen(new android.graphics.Rect(0,0,selectedCategory.getWidth(),selectedCategory.getHeight()),true);});
    }
    private void updateAdjustmentControls(){
        updateRegionMaskHoldButton();if(adjustmentSlider==null)return;normalizeRegionScope();PhotoAdjustments target=editingAdjustments();updating=true;adjustmentSlider.setMax(parameter.max-parameter.min);adjustmentSlider.setKeyProgressIncrement(1);adjustmentSlider.setProgress(target.get(parameter)-parameter.min);adjustmentSlider.setEnabled(ready&&!unrecoverableSaved);adjustmentSlider.setContentDescription(parameter.label+"，"+parameter.format(target.get(parameter))+"，"+scopeLabel()+"，范围 "+parameter.format(parameter.min)+" 至 "+parameter.format(parameter.max));adjustmentValue.setText(parameter.format(target.get(parameter)));adjustmentValue.setContentDescription(parameter.label+"，"+adjustmentValue.getText()+"，点击输入数值");adjustmentValue.setEnabled(ready&&!unrecoverableSaved);updating=false;
        if(adjustmentCaption!=null){adjustmentCaption.setText(parameter.label+(selectedRegionId.isEmpty()?"":" · "+scopeLabel()));adjustmentCaption.setContentDescription(parameter.label+"，"+scopeLabel()+"，点击查看说明");adjustmentCaption.setTooltipText(adjustmentCaption.getText());}
        if(brushScopeButton!=null){brushScopeButton.setEnabled(ready&&!unrecoverableSaved&&!brushLoading);brushScopeButton.setSelected(!selectedRegionId.isEmpty());brushScopeButton.setCompoundDrawablesRelativeWithIntrinsicBounds(new AppIcon(AppIcon.Kind.BRUSH,selectedRegionId.isEmpty()?TEXT:BLUE,activity.getResources().getDisplayMetrics().density),null,null,null);brushScopeButton.setContentDescription("作用范围："+scopeLabel()+"，选择或涂抹局部区域");brushScopeButton.setTooltipText("作用范围："+scopeLabel());}
        undoButton.setEnabled(ready&&!undo.isEmpty());redoButton.setEnabled(ready&&!redo.isEmpty());undoButton.setAlpha(undoButton.isEnabled()?1:.35f);redoButton.setAlpha(redoButton.isEnabled()?1:.35f);
        for(Map.Entry<Boolean,LinearLayout> item:advancedControls.entrySet()){LinearLayout option=item.getValue();option.setEnabled(ready&&!unrecoverableSaved);option.setSelected(false);option.setAlpha(option.isEnabled()?1:.35f);}
        if(paletteControl!=null){paletteControl.setEnabled(ready&&!unrecoverableSaved);paletteControl.setAlpha(paletteControl.isEnabled()?1:.35f);boolean active=!target.palette.isNeutral();((ImageView)paletteControl.getChildAt(0)).setImageDrawable(new AppIcon(AppIcon.Kind.PALETTE,active?BLUE:0x99ffffff,activity.getResources().getDisplayMetrics().density));((TextView)paletteControl.getChildAt(1)).setTextColor(active?BLUE:0x99ffffff);paletteControl.setContentDescription("调色盘，"+scopeLabel()+"，颜色 "+target.palette.color+"，影调 "+target.palette.tone+"，强度 "+target.palette.amount+"%"+(active?"，已调整":""));}
        if(cleanupControl!=null){cleanupControl.setEnabled(ready&&!unrecoverableSaved);cleanupControl.setAlpha(cleanupControl.isEnabled()?1:.35f);boolean active=!target.cleanup.isNeutral();((ImageView)cleanupControl.getChildAt(0)).setImageDrawable(new AppIcon(AppIcon.Kind.CLEANUP,active?BLUE:0x99ffffff,activity.getResources().getDisplayMetrics().density));((TextView)cleanupControl.getChildAt(1)).setTextColor(active?BLUE:0x99ffffff);cleanupControl.setContentDescription("去灰，"+scopeLabel()+"，强度 "+target.cleanup.amount+"%"+(active?"，已调整":""));}
        if(portraitControl!=null){portraitControl.setEnabled(ready&&!unrecoverableSaved&&!portraitLoading);portraitControl.setAlpha(portraitControl.isEnabled()?1:.35f);boolean active=!localEdits.portrait.isNeutral();((ImageView)portraitControl.getChildAt(0)).setImageDrawable(new AppIcon(AppIcon.Kind.PERSON,active?BLUE:0x99ffffff,activity.getResources().getDisplayMetrics().density));((TextView)portraitControl.getChildAt(1)).setTextColor(active?BLUE:0x99ffffff);portraitControl.setContentDescription("人像精修，肤色、柔肤、面部光影与祛痘"+(active?"，已调整":""));}
        for(Map.Entry<PhotoAdjustments.Parameter,LinearLayout> item:parameterControls.entrySet()){PhotoAdjustments.Parameter p=item.getKey();LinearLayout option=item.getValue();boolean active=p==parameter;((ImageView)option.getChildAt(0)).setImageDrawable(new AppIcon(parameterIcon(p),active?BLUE:0x99ffffff,activity.getResources().getDisplayMetrics().density));TextView label=(TextView)option.getChildAt(1);label.setText(p.label);label.setTextColor(active?BLUE:0x99ffffff);GradientDrawable dot=shape(target.get(p)==0?Color.TRANSPARENT:BLUE,3);LayerDrawable mark=new LayerDrawable(new Drawable[]{shape(Color.TRANSPARENT,0),dot});mark.setLayerSize(1,dp(5),dp(5));mark.setLayerGravity(1,Gravity.TOP|Gravity.RIGHT);mark.setLayerInset(1,0,dp(3),dp(10),0);option.setForeground(mark);option.setSelected(active);option.setEnabled(ready);option.setContentDescription(p.label+"，"+p.format(target.get(p))+"，"+scopeLabel()+(active?"，当前参数":"")+"，长按重置");}
    }
    private TextView parameterCaption(String label){return PhotoWorkspaceUi.entryCaption(activity,label);}
    private void updateDraggingReadout(){PhotoAdjustments target=editingAdjustments();adjustmentValue.setText(parameter.format(target.get(parameter)));adjustmentValue.setContentDescription(parameter.label+"，"+adjustmentValue.getText()+"，点击输入数值");adjustmentSlider.setContentDescription(parameter.label+"，"+parameter.format(target.get(parameter))+"，"+scopeLabel());}
    private AppIcon.Kind parameterIcon(PhotoAdjustments.Parameter p){switch(p){case LUMA_DENOISE:case COLOR_DENOISE:return AppIcon.Kind.CLARITY;case GRAIN:return AppIcon.Kind.VIBRANCE;case VIGNETTE:return AppIcon.Kind.BRIGHTNESS;default:return AppIcon.Kind.valueOf(p.name());}}
    private static final class QuickState{
        final int style,amount;final PhotoAdjustments base,applied;final PhotoPortrait portrait,appliedPortrait;final PhotoCleanup.Analysis analysis;
        QuickState(int style,int amount,PhotoAdjustments base,PhotoPortrait portrait,PhotoCleanup.Analysis analysis){this.style=style;this.amount=amount;this.base=base;this.portrait=portrait;this.analysis=analysis;applied=PhotoQuickPreset.adjustments(base,style,amount,analysis);appliedPortrait=PhotoQuickPreset.portrait(portrait,style,amount);}
    }
    private static final class EditState{
        final String id,name;final byte[] bytes;final PresetPreviewProfile profile;final int strength;final PhotoAdjustments manual;final PhotoGeometry geometry;final PhotoBorder border;final PhotoLocalEdits localEdits;
        final QuickState quick;
        EditState(String id,String name,byte[] bytes,PresetPreviewProfile profile,int strength,PhotoAdjustments manual,PhotoGeometry geometry,PhotoBorder border,PhotoLocalEdits localEdits,QuickState quick){this.border=border;this.id=id;this.name=name;this.bytes=bytes;this.profile=profile;this.strength=strength;this.manual=manual;this.geometry=geometry;this.localEdits=localEdits;this.quick=quick;}
        boolean same(EditState other){return id.equals(other.id)&&strength==other.strength&&manual.equals(other.manual)&&geometry.equals(other.geometry)&&border.equals(other.border)&&localEdits.equals(other.localEdits);}
    }
    private EditState snapshot(){return new EditState(selected,selectedName,selectedBytes,selectedProfile,strength,adjustments,geometry,border,localEdits,matchingQuick());}
    private int regionIndex(String id){return regionIndex(localEdits,id);}
    private static int regionIndex(PhotoLocalEdits edits,String id){if(id==null||id.isEmpty())return -1;for(int i=0;i<edits.regions().size();i++)if(edits.regions().get(i).id.equals(id))return i;return -1;}
    private AdjustmentRegion activeRegion(){int index=regionIndex(selectedRegionId);return index<0?null:localEdits.regions().get(index);}
    private void normalizeRegionScope(){if(regionIndex(selectedRegionId)<0)selectedRegionId="";}
    private String scopeLabel(){AdjustmentRegion region=activeRegion();return region==null?"全图":region.name;}
    private PhotoAdjustments editingAdjustments(){AdjustmentRegion region=activeRegion();return region==null?adjustments:region.adjustments;}
    private boolean setEditingAdjustments(PhotoAdjustments next){
        if(next.equals(editingAdjustments()))return false;
        try{int index=regionIndex(selectedRegionId);if(index<0)adjustments=next;else localEdits=localEdits.withRegion(index,localEdits.regions().get(index).withAdjustments(next));return true;}
        catch(IllegalArgumentException limit){host.error(message(limit));updateAdjustmentControls();return false;}
    }
    private String nextRegionName(){for(int number=1;number<=17;number++){String name="区域 "+number;boolean used=false;for(AdjustmentRegion region:localEdits.regions())if(region.name.equals(name)){used=true;break;}if(!used)return name;}return "新区域";}
    private void showRegionScope(){
        if(!readableSettings()||brushLoading)return;finishDrag(true);if(!adjustmentMode||compositionMode||recipeMode||borderMode)setAdjustmentMode(true);normalizeRegionScope();PopupMenu menu=new PopupMenu(activity,brushScopeButton);
        menu.getMenu().add(0,0,0,"全图").setCheckable(true).setChecked(selectedRegionId.isEmpty());
        for(int i=0;i<localEdits.regions().size();i++){AdjustmentRegion region=localEdits.regions().get(i);menu.getMenu().add(0,100+i,i+1,region.name).setCheckable(true).setChecked(region.id.equals(selectedRegionId));}
        menu.getMenu().add(0,1,1000,"新增涂抹区域").setEnabled(localEdits.regions().size()<16);
        menu.getMenu().add(0,2,1001,"编辑当前选区").setEnabled(activeRegion()!=null);
        menu.getMenu().add(0,5,1001,"查看选区").setEnabled(activeRegion()!=null);
        menu.getMenu().add(0,3,1002,"删除当前区域").setEnabled(activeRegion()!=null);
        menu.getMenu().add(0,4,1003,"渐变与取样修复");
        menu.setOnMenuItemClickListener(item->{int id=item.getItemId();if(id==0){selectedRegionId="";updateAdjustmentControls();return true;}if(id>=100){int index=id-100;if(index<localEdits.regions().size()){selectedRegionId=localEdits.regions().get(index).id;updateAdjustmentControls();}return true;}if(id==1){showBrushSelection(null,null);return true;}if(id==2||id==5){showBrushSelection(activeRegion(),null);return true;}if(id==3){int index=regionIndex(selectedRegionId);if(index>=0){EditState before=snapshot();localEdits=localEdits.removeRegion(index);selectedRegionId="";remember(before);edited();refreshManualThumbnails();}return true;}if(id==4){showLocal();return true;}return false;});
        if(brushScopeButton.isShown()&&brushScopeButton.getWidth()>0)menu.show();else{final int token=generation;final long request=portraitRequest;final String account=owner;final Button anchor=brushScopeButton;final android.view.ViewTreeObserver observer=anchor.getViewTreeObserver();observer.addOnGlobalLayoutListener(new android.view.ViewTreeObserver.OnGlobalLayoutListener(){public void onGlobalLayout(){if(observer.isAlive())observer.removeOnGlobalLayoutListener(this);if(valid(token,account)&&request==portraitRequest&&anchor==brushScopeButton&&popup==null&&linkedPaintDialogs.isEmpty()&&anchor.isShown()&&anchor.getWidth()>0)menu.show();}});}
    }
    private void showBrushSelection(AdjustmentRegion existing,Runnable afterCommit){
        if(!readableSettings()||brushLoading)return;finishDrag(true);dismissPopup();brushLoading=true;updateAdjustmentControls();
        final int token=generation;final long request=portraitRequest;final String account=owner;final EditState starting=snapshot();final Bitmap base=original;
        final AdjustmentRegion region=existing==null?AdjustmentRegion.create(nextRegionName()):existing;
        final PresetPreviewProfile global=AdjustedPreviewProfile.of(starting.profile==null?null:StrengthPreviewProfile.of(starting.profile,starting.strength),starting.manual);
        io.execute(()->{try{Bitmap image=render(base,LocalEditsPreviewProfile.of(global,withoutBody(starting.localEdits)));main.post(()->{
            if(!valid(token,account)||request!=portraitRequest){image.recycle();return;}brushLoading=false;updateAdjustmentControls();if(!starting.same(snapshot())){image.recycle();return;}
            final boolean[] committed={false};PhotoBrushDialog dialog=new PhotoBrushDialog(activity,image,region,next->{
                if(!valid(token,account)||request!=portraitRequest||!starting.same(snapshot()))return;
                try{int index=regionIndex(next.id);PhotoLocalEdits changed=index<0?localEdits.addRegion(next):localEdits.withRegion(index,next);if(changed.equals(localEdits)){selectedRegionId=next.id;committed[0]=true;updateAdjustmentControls();return;}EditState before=snapshot();localEdits=changed;selectedRegionId=next.id;remember(before);committed[0]=true;edited();refreshManualThumbnails();}
                catch(IllegalArgumentException limit){host.error(message(limit));}
            });dialog.setSourcePositioning(!starting.localEdits.portrait.bodyShape.isNeutral());popup=dialog;dialog.setOnDismissListener(v->{if(popup==dialog)popup=null;image.recycle();if(committed[0]&&afterCommit!=null&&valid(token,account)&&request==portraitRequest)main.post(afterCommit);});dialog.show();
        });}catch(Exception|OutOfMemoryError failure){main.post(()->{if(valid(token,account)&&request==portraitRequest){brushLoading=false;updateAdjustmentControls();host.error(message(failure));}});}});
    }
    private void remember(EditState before){if(before==null||before.same(snapshot()))return;undo.addLast(before);while(undo.size()>32)undo.removeFirst();redo.clear();}
    private void finishDrag(boolean refreshThumbs){stopRegionMaskPeek();boolean refine=interactivePreview;interactivePreview=false;trackingSlider=null;if(dragStart!=null){boolean manualChanged=!dragStart.manual.equals(adjustments)||!dragStart.localEdits.equals(localEdits);remember(dragStart);dragStart=null;if(manualChanged&&refreshThumbs)refreshManualThumbnails();}flushSave();updateAdjustmentControls();if(compactDock!=null)compactDock.refresh();if(refine&&ready&&!closed)schedulePreview();}
    private void restoreHistory(boolean forward){if(!ready)return;finishDrag(true);quickRequest++;quickBusy=false;ArrayDeque<EditState> from=forward?redo:undo,to=forward?undo:redo;if(from.isEmpty())return;to.addLast(snapshot());EditState target=from.removeLast();boolean changed=!adjustments.equals(target.manual)||!geometry.equals(target.geometry)||!localEdits.equals(target.localEdits);selected=target.id;selectedName=target.name;selectedBytes=target.bytes;selectedProfile=target.profile;strength=target.strength;adjustments=target.manual;geometry=target.geometry;border=target.border;localEdits=target.localEdits;quickState=target.quick;edited();if(changed)refreshManualThumbnails();}
    private void edited(){stopRegionMaskPeek();normalizeRegionScope();closeDetails();hasDraft=true;exported=false;parkedDraft=false;refresh();refreshGridThumbnails();scheduleSave();schedulePreview();}
    private void resetParameter(PhotoAdjustments.Parameter p){if(!ready||unrecoverableSaved||editingAdjustments().get(p)==0)return;EditState before=snapshot();if(!setEditingAdjustments(editingAdjustments().with(p,0)))return;remember(before);edited();refreshManualThumbnails();}
    private void reset(boolean all){if(!ready||unrecoverableSaved||!all&&editingAdjustments().isNeutral()&&!editingAdjustments().palette.hasStoredState()&&!editingAdjustments().cleanup.hasStoredState())return;EditState before=snapshot();if(all){adjustments=PhotoAdjustments.NONE;localEdits=PhotoLocalEdits.NONE;selectedRegionId="";border=PhotoBorder.NONE;geometry=PhotoGeometry.NONE;cancelPendingRetry();pendingChoice=null;selected="";selectedName="无滤镜";selectedBytes=new byte[0];selectedProfile=null;strength=0;}else if(!setEditingAdjustments(PhotoAdjustments.NONE))return;remember(before);edited();refreshManualThumbnails();}
    public void addMenuItems(Menu menu){
        if(!ready)return;
        PhotoActionsMenu.item(activity,menu,0,15101,4,"全部滤镜","在线与我的滤镜",AppIcon.Kind.GRID,this::showAll);
        PhotoActionsMenu.item(activity,menu,0,15102,5,"快速优化","自然、通透与人像",AppIcon.Kind.CLEANUP,()->{if(compactDock!=null)compactDock.choose(PhotoCompactDock.OPTIMIZE);});
        PhotoActionsMenu.item(activity,menu,0,15103,6,"照片配方","保存与应用本机配方",AppIcon.Kind.RECIPE,()->{if(compactDock!=null)compactDock.choose(PhotoCompactDock.RECIPE);});
        PhotoActionsMenu.item(activity,menu,0,15104,7,"精细构图","裁切、拉直与透视",AppIcon.Kind.CROP,this::showComposition);
        PhotoActionsMenu.item(activity,menu,0,PhotoActionsMenu.DETAIL,3,"查看细节","",AppIcon.Kind.DETAIL,this::showDetails);
        PhotoActionsMenu.item(activity,menu,1,PhotoActionsMenu.COPY,10,"复制调色","用到其他照片",AppIcon.Kind.RECIPE,()->{if(readableSettings()){finishDrag(true);final PhotoAdjustments frozen=adjustments;final DownloadedPhoto source=originalPhoto;afterPendingSaves(()->host.copyAdjustments(frozen,source));}}).setEnabled(!unrecoverableSaved);
        PhotoActionsMenu.item(activity,menu,1,PhotoActionsMenu.UNDO_COPY,11,"撤销复制","撤回上一次批量调色",AppIcon.Kind.UNDO,()->host.undoAdjustmentCopy());
        PhotoActionsMenu.item(activity,menu,2,PhotoActionsMenu.RESET_COLOUR,20,"重置调色",selectedRegionId.isEmpty()?"保留滤镜与人像效果":"仅清除"+scopeLabel()+"的调色",AppIcon.Kind.ADJUST,()->reset(false)).setEnabled(!unrecoverableSaved);
        PhotoActionsMenu.item(activity,menu,2,PhotoActionsMenu.RESTORE_ORIGINAL,21,"还原原图","清除全部编辑，可撤销",AppIcon.Kind.REFRESH,()->reset(true)).setEnabled(!unrecoverableSaved);
        if(parkedDraft)PhotoActionsMenu.item(activity,menu,1,PhotoActionsMenu.RESTORE_DRAFT,12,"继续编辑","恢复这张照片的草稿",AppIcon.Kind.RECEIPTS,()->{DownloadedPhoto photo=bound;unbind();bind(photo,false);});
    }
    private boolean readableSettings(){if(!ready)return false;if(unrecoverableSaved||!hasDraft&&bound!=null&&originalPhoto!=null&&!bound.file().equals(originalPhoto.file())){host.error("此保存版本的编辑参数暂不可恢复。仍可查看完整文件像素或调整导出尺寸；编辑请先选择原图。");return false;}return true;}
    public void showCleanup(){
        if(!readableSettings())return;finishDrag(true);dismissPopup();
        if(originalPhoto==null||!originalPhoto.file().isFile()){host.error("无法读取原图，请重新选择照片。");return;}
        final int token=generation;final String scope=owner,regionId=selectedRegionId,originalSha=sourceSha;final EditState starting=snapshot();final Bitmap base=original,fast=fastOriginal==null?base:fastOriginal;final PhotoCaptureInfo capture=captureInfo;final File source=originalPhoto.file();final int index=regionIndex(starting.localEdits,regionId);final AdjustmentRegion analysisRegion=index<0?null:starting.localEdits.regions().get(index);
        PhotoCleanupDialog dialog=new PhotoCleanupDialog(activity,current,editingAdjustments(),scopeLabel(),cancelled->PhotoCleanupAnalyzer.analyze(source,originalSha,analysisRegion,()->cancelled.getAsBoolean()||closed||generation!=token), (manual,interactive)->{
            PhotoAdjustments full=index<0?manual:starting.manual;PhotoLocalEdits locals=index<0?starting.localEdits:starting.localEdits.withRegion(index,starting.localEdits.regions().get(index).withAdjustments(manual));
            PresetPreviewProfile profile=BorderPreviewProfile.of(GeometryPreviewProfile.of(LocalEditsPreviewProfile.of(AdjustedPreviewProfile.of(starting.profile==null?null:StrengthPreviewProfile.of(starting.profile,starting.strength),full),locals),starting.geometry),starting.border);
            return renderFramed(interactive?fast:base,profile,capture,activity);
        },next->{if(!valid(token,scope)||!regionId.equals(selectedRegionId)||!starting.same(snapshot()))return;EditState before=snapshot();if(!setEditingAdjustments(next))return;remember(before);edited();refreshManualThumbnails();});
        popup=dialog;dialog.setOnDismissListener(v->{if(popup==dialog)popup=null;});dialog.show();PhotoEditorTypography.apply(dialog);
    }
    public void showPalette(){
        if(!readableSettings())return;finishDrag(true);dismissPopup();
        final int token=generation;final String scope=owner,regionId=selectedRegionId;final EditState starting=snapshot();final Bitmap base=original,fast=fastOriginal==null?base:fastOriginal;final PhotoCaptureInfo capture=captureInfo;
        PhotoPaletteDialog dialog=new PhotoPaletteDialog(activity,current,editingAdjustments(),scopeLabel(),(manual,interactive)->{
            int index=regionIndex(starting.localEdits,regionId);PhotoAdjustments full=index<0?manual:starting.manual;PhotoLocalEdits locals=index<0?starting.localEdits:starting.localEdits.withRegion(index,starting.localEdits.regions().get(index).withAdjustments(manual));
            PresetPreviewProfile profile=BorderPreviewProfile.of(GeometryPreviewProfile.of(LocalEditsPreviewProfile.of(AdjustedPreviewProfile.of(starting.profile==null?null:StrengthPreviewProfile.of(starting.profile,starting.strength),full),locals),starting.geometry),starting.border);
            return renderFramed(interactive?fast:base,profile,capture,activity);
        },next->{if(!valid(token,scope)||!regionId.equals(selectedRegionId)||!starting.same(snapshot()))return;EditState before=snapshot();if(!setEditingAdjustments(next))return;remember(before);edited();refreshManualThumbnails();});
        popup=dialog;dialog.setOnDismissListener(v->{if(popup==dialog)popup=null;});dialog.show();PhotoEditorTypography.apply(dialog);
    }
    public void showColor(boolean curves){
        if(!readableSettings())return;finishDrag(true);dismissPopup();
        final int token=generation;final String scope=owner,regionId=selectedRegionId;final EditState starting=snapshot();final Bitmap base=original,fast=fastOriginal==null?base:fastOriginal;final PhotoCaptureInfo capture=captureInfo;
        PhotoColorDialog dialog=new PhotoColorDialog(activity,current,editingAdjustments(),curves,(manual,interactive)->{
            int index=regionIndex(starting.localEdits,regionId);PhotoAdjustments full=index<0?manual:starting.manual;PhotoLocalEdits locals=index<0?starting.localEdits:starting.localEdits.withRegion(index,starting.localEdits.regions().get(index).withAdjustments(manual));
            PresetPreviewProfile profile=BorderPreviewProfile.of(GeometryPreviewProfile.of(LocalEditsPreviewProfile.of(AdjustedPreviewProfile.of(starting.profile==null?null:StrengthPreviewProfile.of(starting.profile,starting.strength),full),locals),starting.geometry),starting.border);
            return renderFramed(interactive?fast:base,profile,capture,activity);
        },next->{if(!valid(token,scope)||!regionId.equals(selectedRegionId)||!starting.same(snapshot()))return;EditState before=snapshot();if(!setEditingAdjustments(next))return;remember(before);edited();refreshManualThumbnails();});
        popup=dialog;dialog.setOnDismissListener(v->{if(popup==dialog)popup=null;});dialog.show();PhotoEditorTypography.apply(dialog);
    }
    /** A copied target must discard stale editor memory and reload its account-scoped draft. */
    public void reloadDraft(){if(bound==null)return;DownloadedPhoto photo=bound;unbind();bind(photo,false);}
    public void showPortrait(){
        if(!readableSettings()||portraitLoading)return;
        finishDrag(true);dismissPopup();normalizeRegionScope();portraitLoading=true;updateAdjustmentControls();
        final int token=generation;final long request=++portraitRequest;final String scope=owner,regionId=selectedRegionId;final EditState starting=snapshot();final Bitmap base=original,fast=fastOriginal==null?base:fastOriginal;
        final PresetPreviewProfile global=AdjustedPreviewProfile.of(starting.profile==null?null:StrengthPreviewProfile.of(starting.profile,starting.strength),starting.manual);
        io.execute(()->{try{
            int regionIndex=regionIndex(starting.localEdits,regionId);PhotoLocalEdits analysisEdits=starting.localEdits;if(regionIndex<0)analysisEdits=analysisEdits.withPortrait(PhotoPortrait.NONE);else{AdjustmentRegion selected=analysisEdits.regions().get(regionIndex);analysisEdits=analysisEdits.withRegion(regionIndex,selected.withPortrait(PhotoPortrait.NONE).withSkinSettings(PhotoPortrait.Settings.NONE));}
            Bitmap image=render(base,LocalEditsPreviewProfile.of(global,withoutBody(analysisEdits)));
            main.post(()->{
                if(!valid(token,scope)||request!=portraitRequest){image.recycle();return;}portraitLoading=false;updateAdjustmentControls();
                if(!starting.same(snapshot())||!regionId.equals(selectedRegionId)){image.recycle();return;}
                int index=regionIndex(starting.localEdits,regionId);
                if(index>=0){
                    AdjustmentRegion seed=starting.localEdits.regions().get(index);
                    PhotoPortraitDialog regional=new PhotoPortraitDialog(activity,image,seed,(next,interactive)->{
                        if(!valid(token,scope)||request!=portraitRequest)throw new IOException("照片已切换，请重新打开局部人像。");
                        return render(interactive?fast:base,LocalEditsPreviewProfile.of(global,withoutBody(starting.localEdits.withRegion(index,next))));
                    },next->{if(!valid(token,scope)||request!=portraitRequest||!starting.same(snapshot()))return;try{PhotoLocalEdits result=localEdits.withRegion(index,next);EditState before=snapshot();localEdits=result;selectedRegionId=next.id;remember(before);edited();refreshManualThumbnails();}catch(IllegalArgumentException limit){host.error(message(limit));}});
                    regional.setSourcePositioning(!starting.localEdits.portrait.bodyShape.isNeutral());popup=regional;regional.setOnDismissListener(v->{if(popup==regional)popup=null;portraitRequest++;image.recycle();});regional.show();return;
                }
                PhotoPortraitDialog dialog=new PhotoPortraitDialog(activity,image,starting.localEdits.portrait,(next,interactive)->{
                    if(!valid(token,scope)||request!=portraitRequest)throw new IOException("照片已切换，请重新打开人像精修。");
                    return render(interactive?fast:base,LocalEditsPreviewProfile.of(global,starting.localEdits.withPortrait(next)));
                },next->{
                    if(!valid(token,scope)||request!=portraitRequest||!starting.same(snapshot())||localEdits.portrait.equals(next))return;
                    EditState before=snapshot();localEdits=localEdits.withPortrait(next);remember(before);edited();refreshManualThumbnails();
                });
                dialog.setPaintRequest(()->showPortraitPaint(dialog,image,starting,global,token,scope,request));
                popup=dialog;dialog.setOnDismissListener(v->{linkedPaintDialogs.remove(dialog);if(popup==dialog)popup=null;brushLoading=false;portraitRequest++;image.recycle();});dialog.show();dialog.openSection(portraitSection);portraitSection=0;PhotoEditorTypography.apply(dialog);
            });
        }catch(Exception|OutOfMemoryError failure){main.post(()->{if(valid(token,scope)&&request==portraitRequest){portraitLoading=false;updateAdjustmentControls();host.error(message(failure));}});}});
    }
    /** Keep the original portrait transaction behind the brush and regional child until Apply. */
    private void showPortraitPaint(PhotoPortraitDialog parent,Bitmap image,EditState starting,PresetPreviewProfile global,int token,String account,long request){
        if(!valid(token,account)||request!=portraitRequest||!starting.same(snapshot())||closingPaintDialogs||brushLoading)return;
        if(starting.localEdits.regions().size()>=16){host.error("局部区域已达上限，请先删除一处。");return;}
        brushLoading=true;final PhotoPortrait staged=parent.settings();final Bitmap base=original;
        io.execute(()->{try{Bitmap brushImage=render(base,LocalEditsPreviewProfile.of(global,withoutBody(starting.localEdits.withPortrait(staged))));main.post(()->{
            if(!valid(token,account)||request!=portraitRequest||!parent.isShowing()){brushImage.recycle();return;}
            brushLoading=false;if(!starting.same(snapshot())||!staged.equals(parent.settings())){brushImage.recycle();return;}
            openPortraitBrush(parent,brushImage,staged,starting,global,token,account,request);
        });}catch(Exception|OutOfMemoryError failure){main.post(()->{if(valid(token,account)&&request==portraitRequest){brushLoading=false;host.error(message(failure));}});}});
    }
    private void openPortraitBrush(PhotoPortraitDialog parent,Bitmap image,PhotoPortrait staged,EditState starting,PresetPreviewProfile global,int token,String account,long request){
        if(!linkedPaintDialogs.contains(parent))linkedPaintDialogs.add(parent);
        final AdjustmentRegion seed=AdjustmentRegion.create(nextRegionName());final AdjustmentRegion[] painted={null};
        PhotoBrushDialog brush=new PhotoBrushDialog(activity,image,seed,next->{if(valid(token,account)&&request==portraitRequest&&starting.same(snapshot()))painted[0]=next;});
        brush.setSourcePositioning(!staged.bodyShape.isNeutral());linkedPaintDialogs.add(brush);popup=brush;brush.setOnDismissListener(v->{
            linkedPaintDialogs.remove(brush);if(popup==brush)popup=null;
            if(closingPaintDialogs||!valid(token,account)||request!=portraitRequest||!parent.isShowing()){image.recycle();return;}
            if(painted[0]==null){popup=parent;image.recycle();return;}
            try{
                PhotoLocalEdits stagedEdits=starting.localEdits.withPortrait(staged).addRegion(painted[0]);int index=stagedEdits.regions().size()-1;final boolean[] applied={false};final Bitmap base=original,fast=fastOriginal==null?base:fastOriginal;
                PhotoPortraitDialog regional=new PhotoPortraitDialog(activity,image,painted[0],(next,interactive)->{
                    if(!valid(token,account)||request!=portraitRequest)throw new IOException("照片已切换，请重新打开人像。");
                    return render(interactive?fast:base,LocalEditsPreviewProfile.of(global,withoutBody(stagedEdits.withRegion(index,next))));
                },next->{if(!valid(token,account)||request!=portraitRequest||!starting.same(snapshot()))return;try{PhotoLocalEdits result=stagedEdits.withRegion(index,next);EditState before=snapshot();localEdits=result;selectedRegionId=next.id;remember(before);applied[0]=true;edited();refreshManualThumbnails();}catch(IllegalArgumentException limit){host.error(message(limit));}});
                regional.setSourcePositioning(!staged.bodyShape.isNeutral());linkedPaintDialogs.add(regional);popup=regional;regional.setOnDismissListener(w->{linkedPaintDialogs.remove(regional);if(popup==regional)popup=null;image.recycle();if(closingPaintDialogs)return;if(applied[0])parent.dismiss();else if(valid(token,account)&&request==portraitRequest&&parent.isShowing())popup=parent;});regional.show();
            }catch(IllegalArgumentException limit){image.recycle();popup=parent;host.error(message(limit));}
        });brush.show();
    }
    private static PhotoLocalEdits withoutBody(PhotoLocalEdits edits){return edits.portrait.bodyShape.isNeutral()?edits:edits.withPortrait(edits.portrait.withBodyShape(PhotoBodyShape.NONE));}
    private void showLocal(){
        if(!readableSettings()||localLoading)return;
        finishDrag(true);dismissPopup();localLoading=true;
        final int token=generation;final String scope=owner;final EditState starting=snapshot();final Bitmap base=original,fast=fastOriginal==null?base:fastOriginal;
        final PresetPreviewProfile global=AdjustedPreviewProfile.of(starting.profile==null?null:StrengthPreviewProfile.of(starting.profile,starting.strength),starting.manual);
        io.execute(()->{try{
            Bitmap image=render(base,LocalEditsPreviewProfile.of(global,withoutBody(starting.localEdits)));
            main.post(()->{
                if(!valid(token,scope)){image.recycle();return;}localLoading=false;
                if(!starting.same(snapshot())){image.recycle();return;}
                PhotoLocalEditDialog dialog=new PhotoLocalEditDialog(activity,image,starting.localEdits,(next,interactive)->render(interactive?fast:base,LocalEditsPreviewProfile.of(global,withoutBody(next))),next->{
                    if(!valid(token,scope)||!starting.same(snapshot())||localEdits.equals(next))return;
                    EditState before=snapshot();localEdits=next;remember(before);edited();refreshManualThumbnails();
                });
                popup=dialog;dialog.setOnDismissListener(v->{if(popup==dialog)popup=null;image.recycle();});dialog.show();PhotoEditorTypography.apply(dialog);
            });
        }catch(Exception|OutOfMemoryError failure){main.post(()->{if(valid(token,scope)){localLoading=false;host.error(message(failure));}});}});
    }
    public void showComposition(){showComposition(PhotoCropDialog.TOOL_CROP);}
    private void showComposition(int tool){
        if(!readableSettings()||compositionLoading)return;finishDrag(true);compositionLoading=true;
        final int token=generation;final String scope=owner;final EditState starting=snapshot();final Bitmap base=original;
        io.execute(()->{try{PresetPreviewProfile colour=LocalEditsPreviewProfile.of(AdjustedPreviewProfile.of(starting.profile==null?null:StrengthPreviewProfile.of(starting.profile,starting.strength),starting.manual),starting.localEdits);Bitmap image=render(base,colour);main.post(()->{if(!valid(token,scope)){image.recycle();return;}compositionLoading=false;if(!starting.same(snapshot())){image.recycle();host.error("照片设置已变化，请重新打开构图。");return;}dismissPopup();PhotoCropDialog dialog=new PhotoCropDialog(activity,image,geometry,tool,next->{if(!valid(token,scope)||!ready||next.equals(geometry))return;EditState before=snapshot();geometry=next;remember(before);edited();refreshManualThumbnails();});popup=dialog;dialog.setOnDismissListener(v->{if(popup==dialog)popup=null;image.recycle();});dialog.show();PhotoEditorTypography.apply(dialog);});}catch(Exception|OutOfMemoryError failure){main.post(()->{if(valid(token,scope)){compositionLoading=false;host.error(message(failure));}});}});
    }
    private void loadRecipes(){
        final int token=generation;final String scope=owner;
        io.execute(()->{try{java.util.List<PhotoRecipeStore.Recipe> values=new PhotoRecipeStore(activity.getFilesDir(),scope).list();main.post(()->{if(!valid(token,scope))return;recipes.clear();recipes.addAll(values);updateRecipeRows();});}catch(IOException failure){main.post(()->{if(valid(token,scope)&&recipeStatus!=null){recipeStatus.setText("读取失败 · 重试");recipeStatus.setVisibility(View.VISIBLE);}});}});
    }
    private void updateRecipeRows(){
        if(recipeRows==null)return;recipeRows.removeAllViews();if(recipeStatus!=null){recipeStatus.setText("");recipeStatus.setVisibility(View.GONE);recipeStatus.setOnClickListener(v->loadRecipes());}
        if(recipes.isEmpty()){TextView empty=text("暂无配方",12,MUTED);empty.setGravity(Gravity.CENTER);recipeRows.addView(empty,new LinearLayout.LayoutParams(-1,dp(48)));return;}
        for(PhotoRecipeStore.Recipe recipe:recipes){LinearLayout line=row();Button apply=button(recipe.name,false,()->applyRecipe(recipe));apply.setGravity(Gravity.CENTER_VERTICAL|Gravity.START);apply.setSingleLine(true);apply.setTooltipText(recipe.summary());apply.setEllipsize(TextUtils.TruncateAt.END);apply.setTextSize(12);apply.setContentDescription("套用配方，"+recipe.name+"，"+recipe.summary()+"，保留本张构图");line.addView(apply,new LinearLayout.LayoutParams(0,dp(48),1));Button more=iconButton(AppIcon.Kind.MORE,"管理配方 "+recipe.name,()->{});more.setOnClickListener(v->{PopupMenu menu=new PopupMenu(new ContextThemeWrapper(activity,cc.huevia.R.style.AppThemeDark),more);menu.getMenu().add("重命名").setOnMenuItemClickListener(item->{recipeNameDialog(recipe);return true;});menu.getMenu().add("删除配方").setOnMenuItemClickListener(item->{new PhotoEditorTypography.Builder(new ContextThemeWrapper(activity,cc.huevia.R.style.AppThemeDark)).setTitle("删除配方？").setMessage(recipe.name).setNegativeButton("取消",null).setPositiveButton("删除",(d,w)->{final int token=generation;final String scope=owner;io.execute(()->{try{new PhotoRecipeStore(activity.getFilesDir(),scope).delete(recipe.id);main.post(()->{if(valid(token,scope))loadRecipes();});}catch(IOException failure){main.post(()->{if(valid(token,scope))host.error(message(failure));});}});}).show();return true;});menu.show();});line.addView(more,new LinearLayout.LayoutParams(dp(48),dp(48)));recipeRows.addView(line);}
    }
    private void saveRecipeDialog(){if(!readableSettings())return;finishDrag(true);recipeNameDialog(null);}
    private void recipeNameDialog(PhotoRecipeStore.Recipe renaming){
        if(!ready)return;dismissPopup();final int token=generation;final String scope=owner;final PhotoEditStore.Draft settings;
        try{settings=new PhotoEditStore.Draft(sourceSha,selectedBytes,selectedName,strength,adjustments,false);}catch(IOException failure){host.error(message(failure));return;}
        Context themed=new ContextThemeWrapper(activity,cc.huevia.R.style.AppThemeDark);EditText input=new EditText(themed);input.setSingleLine(true);input.setTextSize(13);input.setHint("名称（1–40字）");input.setText(renaming==null?"":renaming.name);input.selectAll();LinearLayout form=column();form.setPadding(dp(20),0,dp(20),0);form.addView(input);TextView validation=text("",12,0xffffb4ab);validation.setVisibility(View.GONE);form.addView(validation);
        AlertDialog dialog=new PhotoEditorTypography.Builder(themed).setTitle(renaming==null?"保存配方":"重命名").setMessage(renaming==null?"仅保存滤镜与调节，不含构图。":null).setView(form).setNegativeButton("取消",null).setPositiveButton("保存",null).create();popup=dialog;dialog.setOnDismissListener(v->{if(popup==dialog)popup=null;});dialog.setOnShowListener(v->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(w->{String name=input.getText().toString();dialog.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(false);io.execute(()->{try{PhotoRecipeStore store=new PhotoRecipeStore(activity.getFilesDir(),scope);if(renaming==null)store.create(name,settings);else store.rename(renaming.id,name);main.post(()->{if(valid(token,scope)){dialog.dismiss();compositionMode=false;recipeMode=true;borderMode=false;updateModes();loadRecipes();}});}catch(IOException failure){main.post(()->{if(valid(token,scope)&&dialog.isShowing()){dialog.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(true);input.setError(message(failure));}});}});}));dialog.show();PhotoEditorTypography.apply(dialog);
    }
    private void applyRecipe(PhotoRecipeStore.Recipe recipe){
        if(!readableSettings())return;finishDrag(true);final int token=generation;final long request=++recipeRequest;final String scope=owner;final String sha=sourceSha;final PhotoGeometry composition=geometry;final EditState starting=snapshot();
        io.execute(()->{try{PhotoEditStore.Draft settings=recipe.apply(sha,composition);PresetPreviewProfile parsed=settings.presetSha.isEmpty()?null:PresetPreviewProfiles.fromPreset(settings.presetBytes());main.post(()->{if(request!=recipeRequest||!valid(token,scope)||!starting.same(snapshot()))return;EditState before=snapshot();cancelPendingRetry();pendingChoice=null;selected=settings.presetSha;selectedName=settings.name;selectedBytes=settings.presetBytes();selectedProfile=parsed;strength=settings.strength;adjustments=settings.adjustments;if(before.same(snapshot()))return;remember(before);edited();refreshManualThumbnails();});}catch(IOException failure){main.post(()->{if(request==recipeRequest&&valid(token,scope)&&starting.same(snapshot()))host.error(message(failure));});}});
    }
    private void showParameterHelp(){
        if(!ready)return;dismissPopup();PhotoAdjustments.Parameter p=parameter;
        AlertDialog dialog=new PhotoEditorTypography.Builder(new ContextThemeWrapper(activity,cc.huevia.R.style.AppThemeDark)).setTitle(p.label).setMessage(p.help()+"\n\n范围："+p.format(p.min)+" 至 "+p.format(p.max)+"；0 为不额外调节。\n点击滑杆旁的数值可精确输入。").setPositiveButton("知道了",null).create();popup=dialog;dialog.setOnDismissListener(v->{if(popup==dialog)popup=null;});dialog.show();PhotoEditorTypography.apply(dialog);
    }
    private void showExactValue(){
        if(!ready)return;finishDrag(true);dismissPopup();final int token=generation;final String scope=owner,regionId=selectedRegionId;final PhotoAdjustments.Parameter p=parameter;final PhotoAdjustments values=editingAdjustments();
        Context themed=new ContextThemeWrapper(activity,cc.huevia.R.style.AppThemeDark);
        EditText input=new EditText(themed);input.setTextSize(13);input.setTextColor(TEXT);input.setInputType(android.text.InputType.TYPE_CLASS_NUMBER|android.text.InputType.TYPE_NUMBER_FLAG_SIGNED|(p==PhotoAdjustments.Parameter.EXPOSURE?android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL:0));input.setText(p==PhotoAdjustments.Parameter.EXPOSURE?String.format(Locale.ROOT,"%.1f",values.get(p)/10.0):String.valueOf(values.get(p)));input.selectAll();LinearLayout form=column();form.setPadding(dp(20),0,dp(20),0);form.addView(input,new LinearLayout.LayoutParams(-1,dp(48)));
        AlertDialog dialog=new PhotoEditorTypography.Builder(themed).setTitle(p.label).setMessage("范围 "+p.format(p.min)+" 至 "+p.format(p.max)).setView(form).setNegativeButton("取消",null).setPositiveButton("确定",null).create();popup=dialog;
        dialog.setOnDismissListener(v->{if(popup==dialog)popup=null;});
        dialog.setOnShowListener(v->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(w->{if(!valid(token,scope)||!ready||!regionId.equals(selectedRegionId)){dialog.dismiss();return;}try{double raw=Double.parseDouble(input.getText().toString().trim())*(p==PhotoAdjustments.Parameter.EXPOSURE?10:1);if(!Double.isFinite(raw)||Math.abs(raw-Math.rint(raw))>.00001||raw<p.min||raw>p.max)throw new IllegalArgumentException();PhotoAdjustments next=editingAdjustments().with(p,(int)Math.rint(raw));EditState before=snapshot();if(setEditingAdjustments(next)){remember(before);edited();refreshManualThumbnails();}dialog.dismiss();}catch(IllegalArgumentException invalid){input.setError("请输入范围内的"+(p==PhotoAdjustments.Parameter.EXPOSURE?"数值，步长 0.1 EV":"整数"));}}));dialog.show();PhotoEditorTypography.apply(dialog);
    }
    private void refreshManualThumbnails(){
        if(!ready||plainThumb==null)return;final int token=generation,revision=++thumbRevision;final String scope=owner;final PhotoAdjustments manual=adjustments;final PhotoGeometry composition=geometry;final PhotoLocalEdits local=localEdits;final Bitmap base=plainThumb;
        for(Entry entry:entries)entry.image=null;for(Entry entry:onlineEntries)entry.image=null;
        io.execute(()->{try{Bitmap result=manual.isNeutral()&&composition.isNeutral()&&local.isNeutral()?base:render(base,GeometryPreviewProfile.of(LocalEditsPreviewProfile.of(AdjustedPreviewProfile.of(null,manual),local),composition));main.post(()->{if(!valid(token,scope)||revision!=thumbRevision)return;thumb=result;for(FilterCard card:stripCards.values())card.update();refreshGridThumbnails();requestVisible();});}catch(Exception|OutOfMemoryError failure){main.post(()->{if(valid(token,scope)&&revision==thumbRevision)host.error(message(failure));});}});
    }
    private java.util.List<Entry> activeEntries(){return onlineSource?onlineEntries:entries;}
    private void updateCatalogStatus(TextView status){
        String label=onlineSource?(catalogMessage.isEmpty()?"在线滤镜 · "+onlineEntries.size()+" 款":catalogMessage):"我的滤镜 · "+entries.size()+" 款";
        status.setText(label);status.setTooltipText(onlineSource&&!catalogDiagnostic.isEmpty()?label+"\n"+catalogDiagnostic:label);
    }
    private void setOnlineSource(boolean online){if(onlineSource==online)return;cancelPendingRetry();onlineSource=online;category="";query="";pendingChoice=null;pickerFirst=pickerTop=0;refresh();if(filterScroll!=null){final HorizontalScrollView target=filterScroll;final int token=generation;target.post(()->{if(!closed&&generation==token&&filterScroll==target&&onlineSource==online)target.scrollTo(0,0);});}}
    private void loadOnlineCatalog(){
        if(!ready||closed||catalogLoading)return;catalogLoading=true;catalogMessage="正在加载在线滤镜…";catalogDiagnostic="";refresh();refreshPickerMetadata();
        final int token=generation;final String scope=owner;final PresetLibrary local=library;
        catalogIo.execute(()->{if(!valid(token,scope))return;try{EditorPresetCatalog catalog=new EditorPresetCatalog(activity.getFilesDir(),local);OnlinePresetRepository.CatalogResult result=catalog.load();main.post(()->{
            if(!valid(token,scope))return;onlineCatalog=catalog;catalogLoading=false;Map<String,Entry> previous=new LinkedHashMap<>();for(Entry e:onlineEntries)previous.put(e.id,e);LinkedHashMap<String,Entry> distinct=new LinkedHashMap<>();for(OnlinePreset preset:result.presets){Entry entry=previous.get(preset.sha256);if(entry==null||!entry.category.equals(preset.category)||!entry.name.equals(preset.name))entry=new Entry(preset);distinct.putIfAbsent(entry.id,entry);}onlineEntries.clear();onlineEntries.addAll(distinct.values());
            if(pendingChoice!=null&&pendingChoice.online!=null&&!onlineEntries.contains(pendingChoice))pendingChoice=null;
            catalogMessage="ok".equals(result.status)?(onlineEntries.isEmpty()?"在线暂无滤镜 · 轻点刷新":""):"cached".equals(result.status)?"离线缓存 · "+onlineEntries.size()+" 款 · 轻点刷新":"在线滤镜加载失败 · 轻点重试";
            catalogDiagnostic="ok".equals(result.status)?"":result.message;catalogMetadata.clear();catalogMetadata.addAll(result.presets);catalogLoadedAt=SystemClock.elapsedRealtime();cachedCatalogMessage=catalogMessage;cachedCatalogDiagnostic=catalogDiagnostic;refresh();refreshPickerMetadata();if(gridAdapter!=null)gridAdapter.notifyDataSetChanged();
        });}catch(Exception failure){main.post(()->{if(valid(token,scope)){catalogLoading=false;catalogMessage="在线滤镜加载失败 · 轻点重试";catalogDiagnostic=message(failure);refresh();refreshPickerMetadata();}});}});
    }
    private void buildCategories(){
        if(categories==null)return;LinkedHashSet<String> names=categoryNames();
        if(!names.contains(category))category="";
        if(!new ArrayList<>(categoryButtons.keySet()).equals(new ArrayList<>(names))){categories.removeAllViews();categoryButtons.clear();for(String name:names){Button b=button(name.isEmpty()?"全部":name,false,()->selectCategory(name));b.setTag(name);categoryButtons.put(name,b);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-2,dp(48));p.rightMargin=dp(6);categories.addView(b,p);}}
        for(Map.Entry<String,Button> item:categoryButtons.entrySet())styleCategory(item.getValue(),item.getKey().equals(category));
    }
    private LinkedHashSet<String> categoryNames(){LinkedHashSet<String> present=new LinkedHashSet<>(),names=new LinkedHashSet<>();names.add("");for(Entry e:activeEntries())present.add(PresetCategories.label(e.category));for(String c:PresetCategories.SUGGESTED)if(present.remove(c))names.add(c);boolean uncategorized=present.remove(PresetCategories.UNCATEGORIZED);names.addAll(present);if(uncategorized)names.add(PresetCategories.UNCATEGORIZED);return names;}
    private boolean included(Entry e){return(category.isEmpty()||category.equals(PresetCategories.label(e.category)))&&(query.isEmpty()||(e.name+" "+PresetCategories.label(e.category)).toLowerCase(Locale.ROOT).contains(query.toLowerCase(Locale.ROOT)));}
    private void buildStrip(){
        if(strip==null)return;visibleRequests.clear();
        java.util.List<Entry> shown=new ArrayList<>();Entry chosen=null;
        for(Entry entry:activeEntries()){if(entry.id.equals(selected))chosen=entry;if(included(entry)&&shown.size()<24)shown.add(entry);}
        if(chosen!=null&&included(chosen)&&!shown.contains(chosen)){if(shown.size()==24)shown.remove(23);shown.add(chosen);}
        java.util.List<Entry> desired=new ArrayList<>();desired.add(null);desired.addAll(shown);
        LinkedHashSet<String> keys=new LinkedHashSet<>();for(Entry entry:desired)keys.add(entry==null?"":entry.id);
        boolean structureChanged=!new ArrayList<>(stripCards.keySet()).equals(new ArrayList<>(keys));
        if(!structureChanged)for(Entry entry:desired){FilterCard existing=stripCards.get(entry==null?"":entry.id);if(existing==null||existing.entry!=entry){structureChanged=true;break;}}
        int scrollX=filterScroll.getScrollX();
        if(structureChanged){Map<String,FilterCard> old=new LinkedHashMap<>(stripCards);stripCards.clear();for(int i=0;i<desired.size();i++){Entry entry=desired.get(i);String id=entry==null?"":entry.id;FilterCard view=old.remove(id);if(view!=null&&view.entry!=entry){strip.removeView(view);view=null;}if(view==null)view=new FilterCard(entry,false);stripCards.put(id,view);if(view.getParent()!=strip)strip.addView(view,i,stripSize());else if(strip.indexOfChild(view)!=i){strip.removeView(view);strip.addView(view,i,stripSize());}}for(FilterCard stale:old.values())strip.removeView(stale);}
        for(FilterCard view:stripCards.values()){view.setLayoutParams(stripSize());view.update();visibleRequests.add(view::requestIfVisible);}
        if(ready&&!onlineSource&&entries.isEmpty()){if(addFiltersAction==null)addFiltersAction=button("去添加滤镜",false,host::addFilters);if(addFiltersAction.getParent()!=strip)strip.addView(addFiltersAction,new LinearLayout.LayoutParams(-2,dp(96)));}else if(addFiltersAction!=null&&addFiltersAction.getParent()==strip)strip.removeView(addFiltersAction);
        final HorizontalScrollView target=filterScroll;final int token=generation;final boolean restore=structureChanged,online=onlineSource;final String scope=owner;
        target.post(()->{if(!valid(token,scope)||filterScroll!=target||onlineSource!=online)return;if(restore)target.scrollTo(scrollX,0);requestVisible();});
    }
    private LinearLayout.LayoutParams stripSize(){LinearLayout.LayoutParams size=new LinearLayout.LayoutParams(PhotoPrismaStyle.compact(activity)?dp(66):fp(66),PhotoPrismaStyle.compact(activity)?dp(59):fp(83));size.rightMargin=dp(14);size.setMarginEnd(dp(14));return size;}
    private View card(Entry entry,boolean large){
        return new FilterCard(entry,large);
    }
    /** A card's identity and bounds survive selection and asynchronous thumbnail completion. */
    private final class FilterCard extends LinearLayout {
        final Entry entry;final boolean large;final ImageView image,check;final TextView name;final FrameLayout photo;final ProgressBar busy;
        final GradientDrawable border;Bitmap shownBitmap;String shownLabel="";
        FilterCard(Entry entry,boolean large){
            super(activity);this.entry=entry;this.large=large;setOrientation(VERTICAL);setPadding(0,0,large?dp(8):0,0);setTag(entry==null?"":entry.id);if(!large){setBackground(shape(Color.WHITE,7));setClipToOutline(true);}
            photo=new FrameLayout(activity);border=shape(large?FIELD:Color.TRANSPARENT,large?12:7);photo.setBackground(large?border:shape(0xff131b1b,0));photo.setClipToOutline(large);photo.setPadding(large?dp(2):0,large?dp(2):0,large?dp(2):0,large?dp(2):0);if(!large)setForeground(border);
            image=new ImageView(activity);image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setBackground(shape(FIELD,large?9:0));image.setClipToOutline(large);photo.addView(image,new FrameLayout.LayoutParams(-1,-1));
            check=new ImageView(activity);check.setImageDrawable(icon(AppIcon.Kind.CHECK));check.setBackground(large?shape(0xff342f19,12):null);check.setPadding(large?dp(3):0,large?dp(3):0,large?dp(3):0,large?dp(3):0);FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(dp(large?22:27),dp(large?22:27),large?Gravity.BOTTOM|Gravity.END:Gravity.CENTER);if(large)cp.setMargins(0,0,dp(4),dp(4));photo.addView(check,cp);
            busy=new ProgressBar(activity);busy.setIndeterminateTintList(ColorStateList.valueOf(BLUE));busy.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);photo.addView(busy,new FrameLayout.LayoutParams(dp(24),dp(24),Gravity.CENTER));
            addView(photo,new LinearLayout.LayoutParams(-1,large?dp(86):PhotoPrismaStyle.compact(activity)?dp(39):fp(62)));name=text("",large?12:11,TEXT);if(!large)name.setTextSize(10.5f);name.setSingleLine(true);name.setEllipsize(TextUtils.TruncateAt.END);name.setGravity(Gravity.CENTER);addView(name,new LinearLayout.LayoutParams(-1,large?dp(26):PhotoPrismaStyle.compact(activity)?dp(20):fp(21)));
            setFocusable(true);setClickable(true);setOnClickListener(v->{if(!ready)return;cancelPendingRetry();pendingChoice=null;if(entry!=null&&!entry.error.isEmpty()){if(entry.retryable){entry.error="";entry.retryable=false;}else{refreshPendingState();host.error(entry.error);return;}}if(entry!=null&&entry.profile==null){pendingChoice=entry;pendingChoiceFromPicker=large;refreshPendingState();request(entry);return;}refreshPendingState();choose(entry,large);dismissPopup();});
            update();post(this::requestIfVisible);
        }
        void requestIfVisible(){if(entry!=null&&entry.image==null&&entry.error.isEmpty()&&isShown()&&getGlobalVisibleRect(new Rect()))request(entry);}
        void update(){
            String id=entry==null?"":entry.id;boolean chosen=id.equals(selected)&&(hasDraft||ready&&bound!=null&&originalPhoto!=null&&bound.file().equals(originalPhoto.file()));
            Bitmap bitmap=entry==null?thumb:entry.image;if(bitmap!=shownBitmap){shownBitmap=bitmap;image.setImageBitmap(bitmap);}
            boolean unsupported=entry!=null&&!entry.error.isEmpty();String label=unsupported?(entry.retryable?"轻点重试":"暂不支持"):entry==null?"原图":entry.name;
            if(!shownLabel.equals(label)){shownLabel=label;name.setText(label);}image.setAlpha(unsupported?.3f:chosen&&!large?.8f:1f);
            border.setColor(large?(chosen?PhotoPrismaStyle.SELECTION_FILL:FIELD):Color.TRANSPARENT);border.setStroke(dp(1),chosen?PhotoPrismaStyle.SELECTION_FRAME:Color.TRANSPARENT);check.setVisibility(chosen?View.VISIBLE:View.GONE);name.setTextColor(large?(chosen?PhotoPrismaStyle.SELECTION_LABEL:TEXT):0xff1f2b29);name.setTypeface(Typeface.create(large&&chosen?"sans-serif-medium":"sans-serif",Typeface.NORMAL));setSelected(chosen);
            busy.setVisibility(entry!=null&&pendingChoice==entry&&entry.profile==null?View.VISIBLE:View.GONE);
            setContentDescription((entry==null?"无滤镜，保留基础调节":entry.name)+(unsupported?(entry.retryable?"，预览加载失败，点按重试：":"，暂不支持：")+entry.error:chosen?"，已选择":pendingChoice==entry&&entry!=null?"，正在准备预览":""));setTooltipText(getContentDescription());
        }
    }
    private void refreshPendingState(){for(FilterCard card:stripCards.values())card.update();refreshGridThumbnails();}
    private void requestVisible(){
        // A tap takes priority over speculative thumbnails. A full queue must not strand
        // an expanded-grid choice that has no counterpart in the collapsed strip.
        if(pendingChoice!=null)request(pendingChoice);
        for(Runnable r:new ArrayList<>(visibleRequests))r.run();
        if(grid!=null)for(int i=0;i<grid.getChildCount();i++){View child=grid.getChildAt(i);if(child instanceof FilterCard)((FilterCard)child).requestIfVisible();}
    }
    private void refreshGridThumbnails(){
        if(grid==null)return;
        for(int i=0;i<grid.getChildCount();i++){
            View child=grid.getChildAt(i);if(child instanceof FilterCard)((FilterCard)child).update();
        }
    }
    private void request(Entry entry){
        if(!ready||entry.loading||entry.image!=null||!entry.error.isEmpty())return;entry.loading=true;
        final int token=generation,revision=thumbRevision;final String scope=owner;final Bitmap base=plainThumb;final PhotoAdjustments manual=adjustments;final PhotoGeometry composition=geometry;final PhotoLocalEdits localSettings=localEdits;final PresetLibrary local=library;final EditorPresetCatalog catalog=onlineCatalog;final byte[] cachedBytes=entry.bytes;final PresetPreviewProfile cachedProfile=entry.profile;
        try{thumbnails.execute(()->{if(!valid(token,scope))return;Bitmap image=null;String error="";byte[] bytes=null;PresetPreviewProfile profile=null;
            boolean retryable=true;try{if(cachedBytes!=null&&cachedProfile!=null){bytes=cachedBytes;profile=cachedProfile;}else{if(entry.online!=null){if(catalog==null)throw new IOException("在线滤镜目录尚未就绪，请稍后重试。");bytes=catalog.read(entry.online);}else bytes=local.readPreset(entry.id);retryable=false;profile=PresetPreviewProfiles.fromPreset(bytes);}retryable=true;image=render(base,GeometryPreviewProfile.of(LocalEditsPreviewProfile.of(AdjustedPreviewProfile.of(profile,manual),localSettings),composition));retryable=false;}catch(Exception|OutOfMemoryError e){error=message(e);}
            final Bitmap result=image;final String reason=error;final byte[] data=bytes;final PresetPreviewProfile parsed=profile;final boolean canRetry=retryable;
            main.post(()->{entry.loading=false;if(!valid(token,scope)||!(entries.contains(entry)||onlineEntries.contains(entry)))return;entry.bytes=data;entry.profile=parsed;if(revision!=thumbRevision){requestVisible();return;}entry.image=result;entry.renderedRevision=revision;entry.error=reason;entry.retryable=canRetry;renderedEntries.remove(entry);renderedEntries.addLast(entry);while(renderedEntries.size()>48){Entry old=renderedEntries.removeFirst();old.image=null;old.bytes=null;old.profile=null;}if(pendingChoice==entry){boolean fromPicker=pendingChoiceFromPicker;pendingChoice=null;if(parsed!=null&&reason.isEmpty()){choose(entry,fromPicker);dismissPopup();}else host.error(reason);}FilterCard card=stripCards.get(entry.id);if(card!=null&&card.entry==entry)card.update();refreshGridThumbnails();requestVisible();});
        });}catch(RejectedExecutionException full){entry.loading=false;if(pendingChoice==entry)schedulePendingRetry(entry);}
    }
    private void cancelPendingRetry(){if(pendingRetry!=null)main.removeCallbacks(pendingRetry);pendingRetry=null;pendingRetryCount=0;pendingChoiceSerial++;}
    /** Four admission retries, then worker completions retry the active tap first. No idle polling. */
    private void schedulePendingRetry(Entry entry){
        if(closed||pendingRetry!=null||pendingRetryCount>=4||thumbnails.isShutdown())return;
        final int token=generation,attempt=++pendingRetryCount;final String scope=owner;final boolean online=onlineSource;final long choice=pendingChoiceSerial;
        pendingRetry=()->{pendingRetry=null;if(!valid(token,scope)||onlineSource!=online||choice!=pendingChoiceSerial||pendingChoice!=entry||!activeEntries().contains(entry))return;request(entry);};
        main.postDelayed(pendingRetry,80L<<(attempt-1));
    }
    private void choose(Entry entry){
        choose(entry,false);
    }
    private void choose(Entry entry,boolean fromPicker){
        if(!readableSettings())return;finishDrag(true);EditState before=snapshot();
        cancelPendingRetry();pendingChoice=null;
        selected=entry==null?"":entry.id;selectedName=entry==null?"无滤镜":entry.name;selectedBytes=entry==null?new byte[0]:entry.bytes.clone();selectedProfile=entry==null?null:entry.profile;
        strength=entry==null?0:100;remember(before);edited();
        if(fromPicker&&filterScroll!=null){final String id=selected,scope=owner;final int token=generation;final boolean online=onlineSource;final HorizontalScrollView target=filterScroll;target.post(()->{FilterCard card=stripCards.get(id);if(!valid(token,scope)||filterScroll!=target||onlineSource!=online||card==null||!selected.equals(id))return;int left=target.getScrollX(),right=left+target.getWidth();if(card.getLeft()<left)target.scrollTo(Math.max(0,card.getLeft()-dp(8)),0);else if(card.getRight()>right)target.scrollTo(Math.max(0,card.getRight()-target.getWidth()+dp(8)),0);});}
    }
    private void schedulePreview(){
        stopRegionMaskPeek();if(!ready||closed)return;previewRequest++;
        boolean statistics=histogramOpen&&recoverableDetail(),shadows=statistics&&histogramPanel!=null&&histogramPanel.isShadowWarning(),highlights=statistics&&histogramPanel!=null&&histogramPanel.isHighlightWarning();
        if(statistics&&histogramPanel!=null)histogramPanel.setUpdating();
        previewQueue.offer(new PreviewRequest(generation,owner,interactivePreview&&fastOriginal!=null?fastOriginal:original,currentProfile(),border,captureInfo,statistics,shadows,highlights,localEdits.portrait.bodyShape),interactivePreview);
    }
    private static final class PreviewRequest{
        final PhotoBodyShape bodyShape;
        final int token;final String scope;final Bitmap base;final PresetPreviewProfile profile;final PhotoBorder frame;final PhotoCaptureInfo capture;final boolean statistics,shadows,highlights;
        PreviewRequest(int token,String scope,Bitmap base,PresetPreviewProfile profile,PhotoBorder frame,PhotoCaptureInfo capture,boolean statistics,boolean shadows,boolean highlights,PhotoBodyShape bodyShape){this.bodyShape=bodyShape;this.token=token;this.scope=scope;this.base=base;this.profile=profile;this.frame=frame;this.capture=capture;this.statistics=statistics;this.shadows=shadows;this.highlights=highlights;}
    }
    private static final class PreviewFrame{
        final Bitmap image,diagnostic,reference;final PhotoHistogram histogram;
        PreviewFrame(Bitmap image,Bitmap diagnostic,PhotoHistogram histogram,Bitmap reference){this.image=image;this.diagnostic=diagnostic;this.histogram=histogram;this.reference=reference;}
        void recycle(){image.recycle();if(diagnostic!=null&&diagnostic!=image)diagnostic.recycle();}
    }
    private PreviewFrame renderPreview(PreviewRequest request,boolean interactive)throws IOException{
        Bitmap content=render(request.base,request.profile),result=null,diagnostic=null;boolean success=false;
        try{PhotoHistogram histogram=request.statistics?PhotoHistogramPanel.measure(content):null;result=request.frame.isNone()?content:new PhotoBorderRenderer(activity.getAssets()).apply(content,request.frame,request.capture);
            if(request.shadows||request.highlights){Bitmap warned=PhotoHistogramPanel.warningCopy(content,request.shadows,request.highlights);if(request.frame.isNone())diagnostic=warned;else try{diagnostic=new PhotoBorderRenderer(activity.getAssets()).apply(warned,request.frame,request.capture);}finally{warned.recycle();}}
            String referenceKey=GeometryPreviewProfile.geometry(request.profile).identity()+":"+request.frame.identity();
            if(referenceCacheSource!=request.base||!referenceCacheKey.equals(referenceKey)||referenceCache==null||referenceCache.isRecycled()){
                referenceCache=composeReference(request.base,GeometryPreviewProfile.geometry(request.profile),request.frame,request.capture,activity);referenceCacheSource=request.base;referenceCacheKey=referenceKey;
            }
            success=true;return new PreviewFrame(result,diagnostic,histogram,referenceCache);
        }finally{if(!success){if(result!=null&&result!=content)result.recycle();if(diagnostic!=null&&diagnostic!=content&&diagnostic!=result)diagnostic.recycle();content.recycle();}else if(result!=content)content.recycle();}
    }
    static Bitmap interactiveSource(Bitmap source){int edge=Math.max(source.getWidth(),source.getHeight());return edge<=480?source:Bitmap.createScaledBitmap(source,Math.max(1,Math.round(source.getWidth()*480f/edge)),Math.max(1,Math.round(source.getHeight()*480f/edge)),true);}
    private static Bitmap composeReference(Bitmap base,PhotoGeometry geometry,PhotoBorder border,PhotoCaptureInfo capture,Context context)throws IOException{
        Bitmap composed=geometry.isNeutral()?base:PhotoComposition.apply(base,geometry,1);if(border.isNone())return composed;
        try{return new PhotoBorderRenderer(context.getAssets()).apply(composed,border,capture);}finally{if(composed!=base)composed.recycle();}
    }
    private void scheduleSave(){savePending=true;if(delayedSave!=null)main.removeCallbacks(delayedSave);delayedSave=this::flushSave;main.postDelayed(delayedSave,200);}
    private void flushSave(){
        if(delayedSave!=null){main.removeCallbacks(delayedSave);delayedSave=null;}if(!savePending||!ready||!hasDraft||closed)return;savePending=false;
        final String sha=sourceSha,name=selectedName,scope=owner;final byte[] bytes=selectedBytes.clone();final int amount=strength;final boolean saved=exported;
        final PhotoAdjustments manual=adjustments;final PhotoGeometry composition=geometry;final PhotoBorder frame=border;final PhotoLocalEdits local=localEdits;
        io.execute(()->{try{PhotoEditStore.Draft draft=new PhotoEditStore.Draft(sha,bytes,name,amount,manual,composition,frame,local,saved);new PhotoEditStore(activity.getFilesDir(),scope).save(draft);KNOWN.put(scope+":"+sha,!draft.exported);}catch(IOException e){main.post(()->{if(!closed)host.error(message(e));});}});
    }
    public void flushDraft(){finishDrag(true);flushSave();}
    public void refreshExportStatus(){
        if(!ready)return;flushSave();final int token=generation;final String scope=owner,sha=sourceSha,id=selected;final int amount=strength;final PhotoAdjustments manual=adjustments;final PhotoGeometry composition=geometry;final PhotoBorder frame=border;final PhotoLocalEdits local=localEdits;
        io.execute(()->{try{PhotoEditStore.Draft d=new PhotoEditStore(activity.getFilesDir(),scope).read(sha);main.post(()->{if(!valid(token,scope)||!id.equals(selected)||amount!=strength||!manual.equals(adjustments)||!composition.equals(geometry)||!frame.equals(border)||!local.equals(localEdits))return;exported=d!=null&&d.exported&&d.presetSha.equals(id)&&d.strength==amount&&d.adjustments.equals(manual)&&d.geometry.equals(composition)&&d.border.equals(frame)&&d.localEdits.equals(local);KNOWN.put(scope+":"+sha,d!=null&&!d.exported);refresh();host.changed();});}catch(IOException e){main.post(()->{if(valid(token,scope))host.error(message(e));});}});
    }
    private void resetPickerPosition(){pickerFirst=pickerTop=0;if(grid!=null)grid.setSelection(0);}
    /** Serial barrier also covers a draft just flushed while leaving the detail page. */
    public void afterPendingSaves(Runnable done){flushSave();io.execute(()->main.post(()->{if(!closed)done.run();}));}
    public void freeze(Consumer<PhotoPresetBatch.Edit> done){
        if(!ready){host.download();return;}flushSave();final DownloadedPhoto photo=originalPhoto,displayed=bound;final int token=generation;final String scope=owner,sha=sourceSha,displayHash=displayedSha;
        final PhotoEditStore.Draft frozen;
        try{frozen=hasDraft&&!exported?new PhotoEditStore.Draft(sha,selectedBytes,selectedName,strength,adjustments,geometry,border,localEdits,false):null;}catch(IOException error){host.error(message(error));return;}
        io.execute(()->{try{if(frozen!=null)new PhotoEditStore(activity.getFilesDir(),scope).save(frozen);PhotoPresetBatch.Edit edit=frozen==null?PhotoPresetBatch.Edit.saved(PhotoPresetBatch.Source.local(displayed),PhotoExportSpec.full(),displayHash):PhotoPresetBatch.Edit.draft(PhotoPresetBatch.Source.local(photo),frozen,scope);main.post(()->{if(valid(token,scope))done.accept(edit.withAccount(scope));});}catch(Exception e){main.post(()->{if(valid(token,scope))host.error(message(e));});}});
    }
    private PresetPreviewProfile currentProfile(){
        return BorderPreviewProfile.of(GeometryPreviewProfile.of(LocalEditsPreviewProfile.of(AdjustedPreviewProfile.of(selectedProfile==null?null:StrengthPreviewProfile.of(selectedProfile,strength),adjustments),localEdits),geometry),border);
    }
    private boolean recoverableDetail(){return !unrecoverableSaved&&(hasDraft||!savedVersionOnly&&bound!=null&&originalPhoto!=null&&bound.file().equals(originalPhoto.file()));}
    private void closeDetails(){if(detailDialog!=null){detailDialog.close();detailDialog=null;}detailLoading=false;}
    public View createHistogramOverlay(){
        if(histogramPanel==null)histogramPanel=new PhotoHistogramPanel(activity,(shadows,highlights)->{if(ready&&histogramOpen)schedulePreview();});
        if(histogramPanel.getParent() instanceof ViewGroup)((ViewGroup)histogramPanel.getParent()).removeView(histogramPanel);
        histogramPanel.setVisibility(histogramOpen?View.VISIBLE:View.GONE);return histogramPanel;
    }
    public boolean isHistogramVisible(){return histogramOpen;}
    public void toggleHistogram(){
        if(!ready){retryPreparation();return;}if(histogramPanel==null)createHistogramOverlay();histogramOpen=!histogramOpen;
        histogramPanel.setVisibility(histogramOpen?View.VISIBLE:View.GONE);
        if(!histogramOpen){previewRequest++;previewQueue.reset();diagnosticPreview=null;host.changed();if(recoverableDetail())schedulePreview();return;}host.changed();
        if(!recoverableDetail()){histogramPanel.reset();histogramPanel.setError("此保存版本无法恢复不含边框的统计，请选择原图或恢复草稿。");return;}
        schedulePreview();
    }
    public void showDetails(){
        if(!ready){host.download();return;}if(detailLoading)return;finishDrag(true);closeDetails();detailLoading=true;
        final int token=generation;final String scope=owner,rootSha=sourceSha,shownSha=displayedSha;final EditState starting=snapshot();final boolean compare=recoverableDetail();
        final DownloadedPhoto source=compare?originalPhoto:bound;final PresetPreviewProfile profile=compare?currentProfile():null;
        if(source==null){detailLoading=false;host.error("完整照片尚未就绪。");return;}
        try{
            String sha=compare?rootSha:shownSha;
            String identity=scope+":"+sha+":"+token+":"+(compare?new PhotoEditStore.Draft(rootSha,starting.bytes,starting.name,starting.strength,starting.manual,starting.geometry,starting.border,starting.localEdits,false).identity():"saved-file");
            boolean unchanged=compare&&(starting.bytes.length==0||starting.strength==0)&&starting.manual.isNeutral()&&starting.geometry.isNeutral()&&starting.localEdits.isNeutral();
            detailLoading=false;
            // Source verifies the frozen hash off the UI thread before displaying any pixels.
            detailDialog=PhotoDetailDialog.show(activity,new PhotoDetailSource.Request(activity,source.file(),sha,identity,profile,compare,unchanged,()->valid(token,scope)&&ready&&starting.same(snapshot())),bound==null?source.filename():bound.filename());
        }catch(Exception|OutOfMemoryError error){detailLoading=false;host.error(message(error));}
    }
    public void showExport(){
        if(quickBusy){host.error("正在优化照片，请稍后保存。");return;}
        if(!ready){host.download();return;}finishDrag(true);dismissPopup();final int token=generation;final String scope=owner;
        final EditState starting=snapshot();final Bitmap thumbnail=current;final DownloadedPhoto displayed=bound,originalSource=originalPhoto;final String originalSha=sourceSha;
        final boolean allowOriginal=!unrecoverableSaved&&originalSource!=null&&!originalSource.filename().contains("_PNG白底");
        freeze(frozen->io.execute(()->{try{
            PhotoVersionExport.Data data=PhotoVersionExport.prepare(activity,Collections.singletonList(displayed),frozen,thumbnail,scope,()->!valid(token,scope));
            main.post(()->{if(!valid(token,scope)||!starting.same(snapshot()))return;
                if(versionExport!=null)versionExport.close();
                versionExport=new PhotoVersionExport(activity,data,()->valid(token,scope)&&starting.same(snapshot()),
                    edits->{popup=null;host.export(edits);},
                    dialog->{popup=dialog;if(dialog!=null)dialog.setOnDismissListener(d->{if(popup==dialog)popup=null;});},
                    dialog->{exportDialog=dialog;popup=dialog;},
                    allowOriginal?()->confirmOriginalExport(originalSource,originalSha,token,scope):null,
                    host.canExportRaw()?()->{if(valid(token,scope))host.raw();}:null);
                versionExport.show();
            });
        }catch(Exception|OutOfMemoryError error){main.post(()->{if(valid(token,scope))host.error(message(error));});}}));
    }
    private void confirmOriginalExport(DownloadedPhoto photo,String expectedSha,int token,String scope){
        if(!valid(token,scope))return;
        new PhotoEditorTypography.Builder(activity).setTitle("保存 JPEG 原始文件？").setMessage("不会应用当前滤镜、调节、构图与边框，也不使用上方尺寸和质量设置。完整保留原文件内容及其已有信息（可能包含定位）。").setNegativeButton("取消",null).setPositiveButton("保存原始文件",(d,w)->{
            io.execute(()->{try{if(!expectedSha.equals(PhotoEditStore.hashFile(photo.file())))throw new IOException("原图内容已变化，请重新打开照片。");main.post(()->{if(valid(token,scope))host.saveOriginal(photo);});}catch(Exception error){main.post(()->{if(valid(token,scope))host.error(message(error));});}});
        }).show();
    }
    public void showAll(){
        if(!ready)return;
        dismissPopup();query="";
        boolean compact=activity.getResources().getConfiguration().orientation==android.content.res.Configuration.ORIENTATION_LANDSCAPE;
        LinearLayout content=sheet("滤镜");pickerTitle=(TextView)((LinearLayout)content.getChildAt(1)).getChildAt(0);
        LinearLayout header=(LinearLayout)content.getChildAt(1);pickerCount=text("",11,MUTED);pickerCount.setGravity(Gravity.CENTER);pickerCount.setSingleLine(true);header.addView(pickerCount,header.getChildCount()-1,new LinearLayout.LayoutParams(dp(42),dp(48)));
        LinearLayout sources=sourceToggle();
        for(boolean online:new boolean[]{true,false}){
            Button choice=button(online?"在线":"我的",false,()->{if(onlineSource==online)return;dismissPopup();setOnlineSource(online);showAll();});choice.setSingleLine(true);
            styleSource(choice,onlineSource==online);
            sources.addView(choice,compact?new LinearLayout.LayoutParams(dp(54),dp(48)):new LinearLayout.LayoutParams(0,dp(48),1));
        }
        if(compact){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-2,dp(48));p.rightMargin=dp(12);header.addView(sources,header.getChildCount()-1,p);}else{LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(48));p.bottomMargin=dp(8);content.addView(sources,p);}
        EditText search=new EditText(activity);search.setTextColor(TEXT);search.setHintTextColor(MUTED);search.setTextSize(13);search.setSingleLine(true);search.setHint("搜索名称或分类");search.setBackground(shape(FIELD,14));search.setPadding(dp(14),0,dp(14),0);
        HorizontalScrollView cats=new HorizontalScrollView(activity);pickerCategories=row();cats.setHorizontalScrollBarEnabled(false);cats.setOverScrollMode(View.OVER_SCROLL_NEVER);cats.addView(pickerCategories);
        if(compact){LinearLayout filters=row();int searchWidth=Math.min(260,Math.max(176,activity.getResources().getConfiguration().screenWidthDp*32/100));filters.addView(search,new LinearLayout.LayoutParams(dp(searchWidth),dp(48)));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,dp(48),1);p.leftMargin=dp(12);filters.addView(cats,p);content.addView(filters,new LinearLayout.LayoutParams(-1,dp(48)));}else{content.addView(search,new LinearLayout.LayoutParams(-1,dp(48)));content.addView(cats,new LinearLayout.LayoutParams(-1,dp(48)));}
        pickerStatus=text("",11,MUTED);pickerStatus.setOnClickListener(v->{if(!catalogLoading)loadOnlineCatalog();});if(compact){pickerStatus.setSingleLine(true);pickerStatus.setEllipsize(TextUtils.TruncateAt.END);content.addView(pickerStatus,new LinearLayout.LayoutParams(-1,dp(24)));}else{pickerStatus.setSingleLine(true);pickerStatus.setEllipsize(TextUtils.TruncateAt.END);pickerStatus.setPadding(0,dp(6),0,dp(6));content.addView(pickerStatus);}refreshPickerMetadata();
        FrameLayout results=new FrameLayout(activity);content.addView(results,new LinearLayout.LayoutParams(-1,0,1));
        grid=new GridView(activity);grid.setNumColumns(3);grid.setHorizontalSpacing(dp(8));grid.setVerticalSpacing(dp(10));grid.setClipToPadding(false);grid.setPadding(0,dp(8),0,dp(12));grid.setSelector(new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
        gridAdapter=new BaseAdapter(){
            private final java.util.List<Entry> values=new ArrayList<>();{filter();}
            private void filter(){values.clear();if(query.isEmpty())values.add(null);for(Entry e:activeEntries())if(included(e))values.add(e);}
            public void notifyDataSetChanged(){filter();super.notifyDataSetChanged();}
            public int getCount(){return values.size();}public Object getItem(int i){return values.get(i);}
            public boolean hasStableIds(){return true;}public long getItemId(int i){Entry entry=values.get(i);return entry==null?0:Long.parseUnsignedLong(entry.id.substring(0,16),16);}
            public View getView(int i,View old,ViewGroup parent){Entry entry=(Entry)getItem(i);if(old instanceof FilterCard&&((FilterCard)old).entry==entry){((FilterCard)old).update();old.post(((FilterCard)old)::requestIfVisible);return old;}return card(entry,true);}
        };
        grid.setAdapter(gridAdapter);results.addView(grid,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout empty=column();empty.setGravity(Gravity.CENTER);TextView noResults=text("无匹配滤镜",12,MUTED);noResults.setGravity(Gravity.CENTER);empty.addView(noResults);empty.addView(button("清空搜索",false,()->search.setText("")));results.addView(empty,new FrameLayout.LayoutParams(-1,-1));grid.setEmptyView(empty);
        search.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int a,int c,int d){}public void onTextChanged(CharSequence s,int a,int b,int c){query=s.toString().trim();refreshPickerMetadata();gridAdapter.notifyDataSetChanged();resetPickerPosition();}public void afterTextChanged(Editable e){}});
        int screenHeight=activity.getResources().getDisplayMetrics().heightPixels;
        int pickerHeight=compact?Math.min(screenHeight,Math.max((int)(screenHeight*.90),dp(322))):(int)(screenHeight*.72);
        showSheet(content,pickerHeight);
        final GridView restoring=grid;final int first=pickerFirst,top=pickerTop;restoring.post(()->{if(grid==restoring){restoring.setSelection(first);restoring.post(()->{if(grid==restoring)restoring.smoothScrollToPositionFromTop(first,top,0);});}});
    }
    private void refreshPickerMetadata(){
        if(pickerCategories==null)return;
        LinkedHashSet<String> all=categoryNames();java.util.List<String> present=new ArrayList<>();for(int i=0;i<pickerCategories.getChildCount();i++)present.add((String)pickerCategories.getChildAt(i).getTag());
        if(!present.equals(new ArrayList<>(all))){pickerCategories.removeAllViews();for(String c:all){Button button=button(c.isEmpty()?"全部":c,false,()->selectCategory(c));button.setTag(c);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-2,dp(48));p.rightMargin=dp(6);pickerCategories.addView(button,p);}}
        for(int i=0;i<pickerCategories.getChildCount();i++){Button button=(Button)pickerCategories.getChildAt(i);styleCategory(button,category.equals(button.getTag()));}
        if(pickerStatus!=null){updateCatalogStatus(pickerStatus);boolean issue=onlineSource&&(catalogLoading||!catalogMessage.isEmpty());pickerStatus.setVisibility(issue?View.VISIBLE:View.GONE);if(issue)pickerStatus.setText(catalogLoading?"加载中":catalogMessage.contains("缓存")?"离线缓存 · 刷新":catalogMessage.contains("失败")?"加载失败 · 重试":"暂无在线滤镜");}
        if(pickerTitle!=null){int count=0;for(Entry e:activeEntries())if(included(e))count++;pickerTitle.setText("滤镜");if(pickerCount!=null)pickerCount.setText(count+"款");}
    }
    private LinearLayout sheet(String label){LinearLayout content=column();content.setPadding(dp(20),dp(8),dp(20),dp(24));content.setBackground(material());content.setClipToOutline(true);View handle=new View(activity);handle.setBackground(shape(0xff657080,2));LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(dp(32),dp(3));p.gravity=Gravity.CENTER_HORIZONTAL;p.bottomMargin=dp(8);content.addView(handle,p);LinearLayout row=row();final float[] y={0};row.setOnTouchListener((v,e)->{if(e.getActionMasked()==MotionEvent.ACTION_DOWN)y[0]=e.getY();if(e.getActionMasked()==MotionEvent.ACTION_UP&&e.getY()-y[0]>dp(24)){dismissPopup();return true;}return true;});TextView title=text(label,14,TEXT);title.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));title.setSingleLine(true);title.setEllipsize(TextUtils.TruncateAt.END);row.addView(title,new LinearLayout.LayoutParams(0,dp(48),1));Button close=button("",false,this::dismissPopup);close.setCompoundDrawablesRelativeWithIntrinsicBounds(icon(AppIcon.Kind.CLOSE),null,null,null);close.setContentDescription("关闭面板");row.addView(close,new LinearLayout.LayoutParams(dp(48),dp(48)));content.addView(row);return content;}
    private void showSheet(LinearLayout content,int height){Dialog dialog=new Dialog(activity);popup=dialog;dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);if(height==-2){ScrollView scroll=new ScrollView(activity);scroll.addView(content);dialog.setContentView(scroll);content.measure(View.MeasureSpec.makeMeasureSpec(activity.getResources().getDisplayMetrics().widthPixels,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));height=Math.min(content.getMeasuredHeight(),(int)(activity.getResources().getDisplayMetrics().heightPixels*.90));}else dialog.setContentView(content);Window window=dialog.getWindow();if(window!=null){window.setBackgroundDrawableResource(android.R.color.transparent);window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);window.setGravity(Gravity.BOTTOM);window.setLayout(-1,height);window.setDimAmount(.35f);if(android.os.Build.VERSION.SDK_INT>=31)window.setBackgroundBlurRadius(dp(24));}dialog.setOnDismissListener(v->{if(popup!=dialog)return;popup=null;clearPickerState();});dialog.show();PhotoEditorTypography.apply(dialog);if(window!=null)window.setLayout(-1,height);}
    /** Release picker views before a replacement sheet can own the shared fields. */
    private void clearPickerState(){if(grid!=null&&query.isEmpty()){pickerFirst=grid.getFirstVisiblePosition();View first=grid.getChildAt(0);pickerTop=first==null?0:first.getTop();}grid=null;gridAdapter=null;pickerCategories=null;pickerStatus=null;pickerTitle=null;pickerCount=null;query="";}
    public boolean dismissPopup(){stopRegionMaskPeek();portraitRequest++;portraitLoading=false;brushLoading=false;if(detailDialog!=null){boolean showing=detailDialog.isShowing();closeDetails();if(showing)return true;}if(borderControls!=null&&borderControls.dismiss())return true;if(popup==null&&linkedPaintDialogs.isEmpty())return false;Dialog old=popup;if(old!=null)clearPickerState();popup=null;closingPaintDialogs=true;try{ArrayList<Dialog> linked=new ArrayList<>(linkedPaintDialogs);linkedPaintDialogs.clear();for(Dialog dialog:linked)dialog.dismiss();if(old!=null&&!linked.contains(old))old.dismiss();}finally{closingPaintDialogs=false;}return true;}
    private void info(LinearLayout parent,String label,String value){LinearLayout row=row();row.addView(text(label,14,TEXT),new LinearLayout.LayoutParams(0,dp(46),1));row.addView(text(value,14,MUTED));parent.addView(row);}
    private LinearLayout column(){LinearLayout v=new LinearLayout(activity);v.setOrientation(LinearLayout.VERTICAL);return v;}private LinearLayout row(){LinearLayout v=new LinearLayout(activity);v.setOrientation(LinearLayout.HORIZONTAL);v.setGravity(Gravity.CENTER_VERTICAL);return v;}
    private TextView text(String s,int size,int color){TextView v=new TextView(activity);v.setText(s);v.setTextColor(color);v.setTextSize(size);v.setGravity(Gravity.CENTER_VERTICAL);v.setIncludeFontPadding(false);return v;}
    private Button button(String s,boolean primary,Runnable action){Button b=new Button(activity);b.setText(s);b.setTextSize(12);b.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));b.setIncludeFontPadding(false);b.setAllCaps(false);b.setTextColor(primary?0xff352016:BLUE);b.setStateListAnimator(null);b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setMinimumHeight(dp(48));b.setPadding(dp(12),0,dp(12),0);b.setBackground(shape(primary?BLUE:Color.TRANSPARENT,24));b.setBackgroundTintList(null);b.setPadding(dp(12),0,dp(12),0);b.setOnClickListener(v->action.run());return b;}
    private void compactAction(Button button,boolean primary){Drawable face=outline(primary?BLUE:Color.TRANSPARENT,17,primary?BLUE:0x38ffffff);button.setBackground(sourceFace(face,34,0));button.setBackgroundTintList(null);button.setTextSize(12);button.setTextColor(primary?0xff352016:TEXT);button.setPadding(dp(12),0,dp(12),0);button.setSingleLine(true);}
    private Drawable sourceFace(Drawable face,int height,int horizontalInset){LayerDrawable layer=new LayerDrawable(new Drawable[]{face});layer.setLayerHeight(0,dp(height));layer.setLayerGravity(0,Gravity.CENTER_VERTICAL|Gravity.FILL_HORIZONTAL);layer.setLayerInset(0,dp(horizontalInset),0,dp(horizontalInset),0);return layer;}
    private LinearLayout sourceToggle(){LinearLayout group=row();group.setBackground(sourceFace(shape(0x12ffffff,10),34,0));group.setPadding(dp(3),0,dp(3),0);return group;}
    private void styleSource(Button control,boolean active){
        control.setTextSize(11.5f);control.setSingleLine(true);control.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));control.setTextColor(active?0xff2a1c12:0xadffffff);control.setSelected(active);
        StateListDrawable states=new StateListDrawable();GradientDrawable focus=shape(active?BLUE:0x14ffffff,7);focus.setStroke(dp(1),BLUE);states.addState(new int[]{android.R.attr.state_focused},sourceFace(focus,28,0));states.addState(new int[]{android.R.attr.state_pressed},sourceFace(shape(0x3dffffff,7),28,0));states.addState(new int[]{},sourceFace(shape(active?BLUE:Color.TRANSPARENT,7),28,0));control.setBackground(states);control.setPadding(dp(8),0,dp(8),0);
    }
    private void styleCategory(Button control,boolean active){
        boolean main=control==filterModeButton||control==adjustmentModeButton||control.getTag()!=null&&control.getTag().toString().endsWith("-mode");if(main){PhotoWorkspaceUi.styleTab(control,active);return;}control.setTextSize(11.5f);control.setSingleLine(true);control.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));control.setTextColor(active?TEXT:0x99ffffff);control.setSelected(active);control.setMinWidth(dp(48));control.setMinimumWidth(dp(48));
        LayerDrawable indicator=new LayerDrawable(new Drawable[]{shape(Color.TRANSPARENT,0),shape(active?BLUE:Color.TRANSPARENT,1)});indicator.setLayerSize(1,dp(18),dp(2));indicator.setLayerGravity(1,Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);indicator.setLayerInset(1,0,0,0,dp(5));
        GradientDrawable focus=shape(0x0cffffff,8);focus.setStroke(dp(1),BLUE);StateListDrawable states=new StateListDrawable();states.addState(new int[]{android.R.attr.state_focused},new InsetDrawable(focus,0,dp(5),0,dp(5)));states.addState(new int[]{},indicator);control.setBackgroundTintList(null);control.setClipToOutline(false);control.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335),states,new InsetDrawable(shape(Color.WHITE,8),0,dp(5),0,dp(5))));control.setPadding(dp(main?4:7),0,dp(main?4:7),0);
    }
    private EditorGlassDrawable material(){return new EditorGlassDrawable(glass,activity.getResources().getDisplayMetrics().density,26);}
    private AppIcon icon(AppIcon.Kind kind){return new AppIcon(kind,TEXT,activity.getResources().getDisplayMetrics().density);}private GradientDrawable shape(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}private int dp(float n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
    private static String message(Throwable e){return e.getMessage()==null?"暂时无法处理，请重试。":e.getMessage();}
    static Bitmap renderColour(Bitmap base,PresetPreviewProfile profile){return render(base,profile);}
    private static Bitmap renderFramed(Bitmap base,PresetPreviewProfile profile,PhotoCaptureInfo capture,Context context)throws IOException{Bitmap colour=render(base,profile);PhotoBorder frame=BorderPreviewProfile.border(profile);if(frame.isNone())return colour;try{return new PhotoBorderRenderer(context.getAssets()).apply(colour,frame,capture);}finally{colour.recycle();}}
    private static Bitmap render(Bitmap base,PresetPreviewProfile profile){int w=base.getWidth(),h=base.getHeight();int[] pixels=new int[w*h];base.getPixels(pixels,0,w,0,0,w,h);int[] result=profile.render(pixels,w,h);Bitmap colour=Bitmap.createBitmap(result,w,h,Bitmap.Config.ARGB_8888);PhotoGeometry composition=GeometryPreviewProfile.geometry(profile);if(composition.isNeutral())return colour;try{return PhotoComposition.apply(colour,composition,1);}finally{colour.recycle();}}
    public static Bitmap decode(File file,int edge)throws IOException{
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),bounds);if(bounds.outWidth<1||bounds.outHeight<1)throw new IOException("原图无法读取。");BitmapFactory.Options options=new BitmapFactory.Options();options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);options.inScaled=false;options.inSampleSize=1;while(Math.max(bounds.outWidth,bounds.outHeight)/options.inSampleSize>edge*2)options.inSampleSize*=2;Bitmap bitmap=BitmapFactory.decodeFile(file.getPath(),options);if(bitmap==null)throw new IOException("原图无法解码。");
        try{
            int orientation=new ExifInterface(file.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);Matrix matrix=new Matrix();switch(orientation){case 2:matrix.setScale(-1,1);break;case 3:matrix.setRotate(180);break;case 4:matrix.setScale(1,-1);break;case 5:matrix.setRotate(90);matrix.postScale(-1,1);break;case 6:matrix.setRotate(90);break;case 7:matrix.setRotate(270);matrix.postScale(-1,1);break;case 8:matrix.setRotate(270);break;}
            if(!matrix.isIdentity()){
                Bitmap oriented=Bitmap.createBitmap(bitmap,0,0,bitmap.getWidth(),bitmap.getHeight(),matrix,true);
                if(oriented!=bitmap){bitmap.recycle();bitmap=oriented;}
            }
            float scale=Math.min(1,edge/(float)Math.max(bitmap.getWidth(),bitmap.getHeight()));
            Bitmap result=scale<1?Bitmap.createScaledBitmap(bitmap,Math.max(1,Math.round(bitmap.getWidth()*scale)),Math.max(1,Math.round(bitmap.getHeight()*scale)),true):bitmap;
            if(result!=bitmap)bitmap.recycle();
            bitmap=null;return result;
        }finally{if(bitmap!=null&&!bitmap.isRecycled())bitmap.recycle();}
    }
    /** Runs on the album thumbnail worker. A missing draft never changes a saved version's pixels. */
    public static Bitmap draftThumbnail(Context context,DownloadedPhoto original,String sha,int edge)throws IOException{
        String owner=accountOwner(context);PhotoEditStore.Draft d=new PhotoEditStore(context.getFilesDir(),owner).read(sha);if(d==null){KNOWN.remove(owner+":"+sha);return null;}KNOWN.put(owner+":"+sha,!d.exported);if(d.exported)return null;Bitmap base=decode(original.file(),edge);if(!d.hasEffect())return base;try{return renderFramed(base,d.profile(),PhotoCaptureInfo.read(original.file()),context);}finally{base.recycle();}
    }
    public static String draftBadge(Context context,String sha){return Boolean.TRUE.equals(KNOWN.get(accountOwner(context)+":"+sha))?"未导出":"";}
    @Override public void close(){stopRegionMaskPeek();closeDetails();if(borderControls!=null)borderControls.close();flushSave();closed=true;previewQueue.close();generation++;cancelPendingRetry();dismissPopup();io.shutdown();catalogIo.shutdownNow();previews.shutdownNow();thumbnails.shutdownNow();main.removeCallbacksAndMessages(null);}
}
