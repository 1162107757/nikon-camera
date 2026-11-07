package cc.huevia.album;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.BitmapRegionDecoder;
import android.graphics.ColorSpace;
import android.graphics.Rect;
import android.media.ExifInterface;
import android.os.Handler;
import android.os.Looper;
import android.os.FileObserver;
import cc.huevia.ncp.PresetPreviewProfile;
import cc.huevia.ncp.GeometryPreviewProfile;
import cc.huevia.ncp.PhotoGeometry;
import cc.huevia.ui.PhotoDetailViewport;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.Set;
import java.util.HashSet;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;

/** One frozen page: verified original regions or lossless rendered surfaces, bounded overview/tile RAM. */
public final class PhotoDetailSource implements AutoCloseable {
    public static final int CURRENT=0, BEFORE=1;
    private static final int TILE=512, CACHE_BYTES=12*1024*1024;
    private static final Set<String> LIVE_DIRECTORIES=Collections.synchronizedSet(new HashSet<>());
    public static final class Request {
        public final Context context; public final File file; public final String sha,identity;
        public final PresetPreviewProfile profile; public final boolean canCompare,currentUnchanged;
        public final BooleanSupplier stillValid;
        public Request(Context context,File verifiedFile,String sha,String identity,PresetPreviewProfile profile,boolean canCompare,BooleanSupplier stillValid){
            this(context,verifiedFile,sha,identity,profile,canCompare,false,stillValid);
        }
        /** currentUnchanged is supplied only by an editor snapshot with neutral colour and geometry. */
        public Request(Context context,File verifiedFile,String sha,String identity,PresetPreviewProfile profile,boolean canCompare,boolean currentUnchanged,BooleanSupplier stillValid){
            if(context==null||verifiedFile==null||sha==null||!sha.matches("[a-fA-F0-9]{64}")||identity==null||identity.isEmpty()||stillValid==null||canCompare&&profile==null)throw new IllegalArgumentException("细节快照无效。");
            this.context=context.getApplicationContext();this.file=verifiedFile.getAbsoluteFile();this.sha=sha;this.identity=identity;
            this.profile=profile;this.canCompare=canCompare;this.currentUnchanged=currentUnchanged;this.stillValid=stillValid;
        }
    }
    public static final class Tile {
        public final Rect bounds;public final Bitmap bitmap;
        Tile(Rect bounds,Bitmap bitmap){this.bounds=bounds;this.bitmap=bitmap;}
    }
    public static final class Frame {
        public final int mode,width,height,sample;public final Bitmap overview;public final List<Tile> tiles;public final boolean provisional;
        Frame(int mode,int width,int height,int sample,Bitmap overview,List<Tile> tiles){this(mode,width,height,sample,overview,tiles,false);}
        Frame(int mode,int width,int height,int sample,Bitmap overview,List<Tile> tiles,boolean provisional){this.mode=mode;this.width=width;this.height=height;this.sample=sample;this.overview=overview;this.tiles=Collections.unmodifiableList(tiles);this.provisional=provisional;}
    }
    public interface Callback {
        /** Fit-only interim pixels. This is never a completed 100% or 200% frame. */
        default void preview(Frame frame) {}
        void loaded(Frame frame);
        void failed(String message);
        void invalidated();
    }
    private static final PresetPreviewProfile UNCHANGED=new PresetPreviewProfile(){
        public String registrationName(){return "已保存版本";}public String modelVersion(){return "saved-file-pixels-v1";}
        public double mapTone(double v){return v;}public int applyArgb(int v){return v;}
    };
    private static final class Surface {final File file;final BitmapRegionDecoder decoder;final PhotoDetailRaster raster;final Bitmap overview;final int width,height;final boolean temporary;
        Surface(File file,BitmapRegionDecoder decoder,Bitmap overview,boolean temporary){this.file=file;this.decoder=decoder;this.raster=null;this.overview=overview;this.width=decoder.getWidth();this.height=decoder.getHeight();this.temporary=temporary;}
        Surface(File file,PhotoDetailRaster raster,Bitmap overview){this.file=file;this.decoder=null;this.raster=raster;this.overview=overview;this.width=raster.width();this.height=raster.height();this.temporary=true;}
        void close(){if(decoder!=null)decoder.recycle();if(raster!=null)try{raster.close();}catch(IOException ignored){}if(temporary)file.delete();}}
    private static final class Pending {final long token;final int mode;final Callback callback;Pending(long token,int mode,Callback callback){this.token=token;this.mode=mode;this.callback=callback;}}
    private final Request request;private final File directory;private final Handler main=new Handler(Looper.getMainLooper());
    private final long sourceLength,sourceModified;private final FileObserver observer;
    private final ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<>(1),r->{Thread t=new Thread(r,"photo-real-detail");t.setDaemon(true);return t;},new ThreadPoolExecutor.DiscardOldestPolicy());
    private final Surface[] surfaces=new Surface[2];
    private volatile Frame currentPreview,beforePreview;private volatile Pending pending;
    private final LinkedHashMap<String,Bitmap> cache=new LinkedHashMap<>(32,.75f,true);
    private int cacheBytes;private boolean pruned,verified;private BitmapFactory.Options sourceBounds;private int orientation;private volatile long serial;private volatile boolean closed,sourceChanged,releasePending;
    @SuppressWarnings("deprecation") public PhotoDetailSource(Request request){
        this.request=request;directory=new File(request.context.getCacheDir(),"photo-detail-"+UUID.randomUUID());
        LIVE_DIRECTORIES.add(directory.getName());
        sourceLength=request.file.length();sourceModified=request.file.lastModified();
        observer=new FileObserver(request.file.getParent(),FileObserver.CLOSE_WRITE|FileObserver.DELETE|FileObserver.MOVED_FROM|FileObserver.MODIFY|FileObserver.ATTRIB|FileObserver.DELETE_SELF|FileObserver.MOVE_SELF){public void onEvent(int event,String path){if(path==null||request.file.getName().equals(path))sourceChanged=true;}};
        observer.startWatching();
    }
    public boolean canCompare(){return request.canCompare;}
    public boolean valid(){return !closed&&!sourceChanged&&request.file.length()==sourceLength&&request.file.lastModified()==sourceModified&&request.stillValid.getAsBoolean();}
    public void cancelFrames(){serial++;pending=null;worker.getQueue().clear();}
    /** Called after the view drops its frame when the Activity enters the background. */
    public void releaseMemory(){if(closed)return;cancelFrames();releasePending=true;worker.execute(this::drainRelease);}
    private void drainRelease(){if(releasePending){releasePending=false;release();}}
    public void frame(int mode,int canvasWidth,int canvasHeight,double scale,double nx,double ny,Callback callback){
        if(closed)return;
        final long token=++serial;
        pending=new Pending(token,mode,callback);publishPreview(mode);
        worker.execute(()->{
            try{
                drainRelease();
                check();if(mode==BEFORE&&!request.canCompare)throw new IOException("此版本暂无法恢复调色前内容。");
                preparePreview(mode);publishPreview(mode);
                Surface surface=prepare(mode);if(token!=serial)return;
                PhotoDetailViewport viewport=new PhotoDetailViewport();viewport.canvas(canvasWidth,canvasHeight);viewport.image(surface.width,surface.height);
                if(scale>0){viewport.fitting=false;viewport.scale=scale;viewport.center(nx*surface.width,ny*surface.height);}
                else viewport.fitImage();
                int sample=viewport.sample(),step=TILE*sample;
                int left=Math.max(0,(int)Math.floor(viewport.centerX-canvasWidth/(2*viewport.scale))),top=Math.max(0,(int)Math.floor(viewport.centerY-canvasHeight/(2*viewport.scale)));
                int right=Math.min(surface.width,(int)Math.ceil(viewport.centerX+canvasWidth/(2*viewport.scale))),bottom=Math.min(surface.height,(int)Math.ceil(viewport.centerY+canvasHeight/(2*viewport.scale)));
                List<Tile> tiles=new ArrayList<>();long framePixels=0;
                for(int y=top/step*step;y<bottom;y+=step)for(int x=left/step*step;x<right;x+=step){
                    check();if(token!=serial)return;
                    Rect region=new Rect(x,y,Math.min(x+step,surface.width),Math.min(y+step,surface.height));
                    String key=request.identity+":"+mode+":"+sample+":"+x+":"+y;
                    Bitmap bitmap=cache.get(key);
                    if(bitmap==null){bitmap=decodeTile(surface,region,sample);put(key,bitmap);}
                    framePixels+=(long)bitmap.getWidth()*bitmap.getHeight();
                    if(framePixels>8_388_608L)throw new IOException("此视口所需内存过多，请返回后重试。");
                    tiles.add(new Tile(region,bitmap));
                }
                Frame frame=new Frame(mode,surface.width,surface.height,sample,surface.overview,tiles);
                main.post(()->{if(closed||token!=serial)return;if(!valid()){callback.invalidated();return;}callback.loaded(frame);});
            }catch(Exception|OutOfMemoryError failure){
                String message=failure instanceof OutOfMemoryError?"细节暂时无法载入，返回后可重试。":failure.getMessage();
                main.post(()->{if(closed||token!=serial)return;if(!valid()){callback.invalidated();return;}callback.failed(message==null?"无法载入细节，请重试。":message);});
            }
        });
    }
    private Frame previewFor(int mode){return mode==CURRENT?currentPreview:beforePreview;}
    private void publishPreview(int mode){
        Frame frame=previewFor(mode);Pending latest=pending;if(frame==null||latest==null||latest.mode!=mode)return;
        main.post(()->{if(closed||latest.token!=serial)return;if(!valid()){latest.callback.invalidated();return;}latest.callback.preview(frame);});
    }
    /** Hash once per frozen page; file observer/stat/account checks remain active throughout preparation. */
    private void verifySource()throws IOException{
        check();if(verified)return;
        if(!request.file.isFile()||!request.sha.equalsIgnoreCase(PhotoEditStore.hashFile(request.file)))throw new IOException("照片文件已变化，请返回后重新打开。");
        PhotoPreviewCache.validateJpeg(request.file,sourceLength);check();
        sourceBounds=new BitmapFactory.Options();sourceBounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(request.file.getPath(),sourceBounds);
        if(sourceBounds.outWidth<1||sourceBounds.outHeight<1||!"image/jpeg".equals(sourceBounds.outMimeType))throw new IOException("仅支持已校验的完整 JPEG 文件。");
        orientation=new ExifInterface(request.file.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);if(orientation<1||orientation>8)orientation=1;
        check();verified=true;
    }
    private PhotoGeometry geometry(){return request.canCompare?GeometryPreviewProfile.geometry(request.profile):PhotoGeometry.NONE;}
    private void preparePreview(int mode)throws IOException{
        if(previewFor(mode)!=null)return;verifySource();Bitmap bitmap=null;
        try{
            int sample=1;while(Math.max(sourceBounds.outWidth,sourceBounds.outHeight)/(double)sample>1024)sample*=2;
            BitmapFactory.Options options=options(sample);options.inMutable=true;bitmap=BitmapFactory.decodeFile(request.file.getPath(),options);
            if(bitmap==null)throw new IOException("照片预览读取失败。");bitmap.setDensity(Bitmap.DENSITY_NONE);
            if(mode==CURRENT&&request.canCompare&&!request.currentUnchanged){Bitmap working=bitmap;PhotoPresetRenderer.applyRows(new PhotoPresetRenderer.Pixels(){
                public int width(){return working.getWidth();}public int height(){return working.getHeight();}
                public int exifOrientation(){return orientation;}
                public void read(int[] pixels,int row,int rows){working.getPixels(pixels,0,width(),0,row,width(),rows);}
                public void write(int[] pixels,int row,int rows){working.setPixels(pixels,0,width(),0,row,width(),rows);}
            },request.profile,()->!preparationValid(mode),null);}
            checkPreparation(mode);Bitmap composed=PhotoComposition.apply(bitmap,geometry(),orientation);if(composed!=bitmap)bitmap.recycle();bitmap=composed;bitmap.setDensity(Bitmap.DENSITY_NONE);
            PhotoGeometry.Plan full=geometry().plan(sourceBounds.outWidth,sourceBounds.outHeight,orientation);checkPreparation(mode);
            Frame preview=new Frame(mode,full.width,full.height,sample,bitmap,Collections.emptyList(),true);
            if(mode==CURRENT)currentPreview=preview;else beforePreview=preview;bitmap=null;
        }finally{if(bitmap!=null)bitmap.recycle();}
    }
    private Surface prepare(int mode)throws IOException{
        Surface existing=surfaces[mode];if(existing!=null)return existing;
        verifySource();checkPreparation(mode);if(!pruned){pruned=true;pruneOrphans();}
        // Saved JPEGs and neutral 'before' content already contain the exact pixels we need.
        // Region decoding them directly avoids a full-size decode + PNG encode + reread.
        if(orientation==1&&geometry().isNeutral()&&(!request.canCompare||mode==BEFORE||request.currentUnchanged)){
            BitmapRegionDecoder decoder=BitmapRegionDecoder.newInstance(request.file.getPath(),false);
            if(decoder==null)throw new IOException("无法读取完整细节。");
            try{checkPreparation(mode);Surface created=new Surface(request.file,decoder,previewFor(mode).overview,false);surfaces[mode]=created;return created;}
            catch(IOException|RuntimeException|OutOfMemoryError failure){decoder.recycle();throw failure;}
        }
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("细节暂存目录不可用，请检查存储空间。");
        File target=new File(directory,mode==CURRENT?"current.argb":"before.argb");
        PhotoDetailRaster raster=null;
        try{
            PhotoGeometry.Plan plan=geometry().plan(sourceBounds.outWidth,sourceBounds.outHeight,orientation);
            long workingDisk=(long)plan.width*plan.height*4+8L*1024*1024;
            if(directory.getUsableSpace()<workingDisk)throw new IOException("存储空间不足，无法准备完整细节。原图已保留。");
            PhotoPresetRenderer.forContext(request.context).renderDetailRaster(request.file,target,request.canCompare?request.profile:UNCHANGED,mode==BEFORE||!request.canCompare||request.currentUnchanged,()->!preparationValid(mode),null);
            checkPreparation(mode);if(!request.sha.equalsIgnoreCase(PhotoEditStore.hashFile(request.file)))throw new IOException("照片文件已变化，请返回后重新打开。");
            raster=new PhotoDetailRaster(target);
            Surface other=surfaces[1-mode];if(other!=null&&(raster.width()!=other.width||raster.height()!=other.height))throw new IOException("前后构图尺寸不一致，未显示错误对比。");
            // The provisional overview has the same frozen colour/geometry; only unsampled
            // region tiles certify final detail. Reuse it without another full-image decode.
            Surface created=new Surface(target,raster,previewFor(mode).overview);surfaces[mode]=created;return created;
        }catch(IOException|RuntimeException|OutOfMemoryError failure){if(raster!=null)try{raster.close();}catch(IOException ignored){}target.delete();throw failure;}
    }
    private Bitmap decodeTile(Surface surface,Rect region,int sample)throws IOException{
        if(surface.raster!=null)return surface.raster.decodeRegion(region,sample);
        // JPEG chroma interpolation needs neighbours across tile edges. Decode a
        // sample-aligned halo, then crop without resampling so 1:1 pixels agree
        // with a whole-file decode rather than treating each tile as an image edge.
        // The codec rounds down sampled odd edges. Keep its actual decoded extent;
        // a tail thinner than one sample is decoded at 1:1 so it cannot vanish.
        if(region.width()<sample||region.height()<sample)sample=1;
        int halo=32*sample;
        Rect expanded=new Rect(Math.max(0,region.left-halo),Math.max(0,region.top-halo),Math.min(surface.width,region.right+halo),Math.min(surface.height,region.bottom+halo));
        Bitmap decoded=surface.decoder.decodeRegion(expanded,options(sample));if(decoded==null)throw new IOException("细节区域解码失败。");
        try{
            int x=(region.left-expanded.left)/sample,y=(region.top-expanded.top)/sample;
            int width=Math.min((region.width()+sample-1)/sample,decoded.getWidth()-x),height=Math.min((region.height()+sample-1)/sample,decoded.getHeight()-y);
            Bitmap tile=Bitmap.createBitmap(decoded,x,y,width,height);tile.setDensity(Bitmap.DENSITY_NONE);
            if(tile==decoded)decoded=null;return tile;
        }finally{if(decoded!=null)decoded.recycle();}
    }
    private static BitmapFactory.Options options(int sample){BitmapFactory.Options o=new BitmapFactory.Options();o.inScaled=false;o.inSampleSize=sample;o.inPreferredConfig=Bitmap.Config.ARGB_8888;o.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);return o;}
    private void check()throws IOException{if(!valid()||Thread.currentThread().isInterrupted())throw new IOException("细节页面已失效。");}
    // Panning can reuse a surface in progress; changing comparison mode drops obsolete work.
    private boolean preparationValid(int mode){Pending latest=pending;return latest!=null&&latest.mode==mode&&!releasePending&&valid()&&!Thread.currentThread().isInterrupted();}
    private void checkPreparation(int mode)throws IOException{if(!preparationValid(mode))throw new IOException("细节页面已暂停。");}
    private void put(String key,Bitmap bitmap){
        cache.put(key,bitmap);cacheBytes+=bitmap.getAllocationByteCount();
        while(cacheBytes>CACHE_BYTES&&!cache.isEmpty()){Map.Entry<String,Bitmap> first=cache.entrySet().iterator().next();cacheBytes-=first.getValue().getAllocationByteCount();cache.remove(first.getKey());}
        // Removed bitmaps can still be drawn by the current immutable frame; GC owns their final release.
    }
    private void release(){cache.clear();cacheBytes=0;currentPreview=null;beforePreview=null;for(int i=0;i<surfaces.length;i++){Surface s=surfaces[i];surfaces[i]=null;if(s!=null)s.close();}File[] rest=directory.listFiles();if(rest!=null)for(File file:rest)file.delete();directory.delete();}
    /** Only our flat UUID directories, never arbitrary cache children or another live page. */
    private void pruneOrphans(){
        File[] children=request.context.getCacheDir().listFiles();if(children==null)return;
        synchronized(LIVE_DIRECTORIES){for(File child:children){
            if(!child.isDirectory()||!child.getName().matches("photo-detail-[a-f0-9-]{36}")||LIVE_DIRECTORIES.contains(child.getName()))continue;
            File[] files=child.listFiles();if(files!=null)for(File file:files)if(file.isFile()&&(file.getName().equals("current.png")||file.getName().equals("before.png")||file.getName().equals("current.argb")||file.getName().equals("before.argb")))file.delete();child.delete();
        }}
    }
    @Override public void close(){if(closed)return;closed=true;observer.stopWatching();serial++;worker.getQueue().clear();worker.execute(()->{release();LIVE_DIRECTORIES.remove(directory.getName());});worker.shutdown();}
}
