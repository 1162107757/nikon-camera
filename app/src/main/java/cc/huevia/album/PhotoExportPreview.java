package cc.huevia.album;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.BitmapRegionDecoder;
import android.graphics.ColorSpace;
import android.graphics.Rect;
import android.media.ExifInterface;
import android.os.FileObserver;
import android.os.Handler;
import android.os.Looper;
import cc.huevia.ncp.PhotoGeometry;
import cc.huevia.ncp.PresetPreviewProfile;
import cc.huevia.ui.PhotoDetailViewport;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;

/** A private real export and its lossless pre-encoder pixels. Never creates a gallery receipt. */
public final class PhotoExportPreview implements AutoCloseable {
    public static final int JPEG=0, BEFORE_ENCODING=1;
    private static final int TILE=512, CACHE_BYTES=12*1024*1024;
    private static final Set<String> LIVE=Collections.synchronizedSet(new HashSet<>());
    private static final Semaphore RENDER_SLOT=new Semaphore(1);
    private static final String[] FILES={"encoded.jpg","reference.png","jpeg-display.png","reference-display.png"};
    public static final class Request {
        public final Context context;
        public final File source;
        public final String sha,identity;
        public final PresetPreviewProfile profile;
        public final BooleanSupplier stillValid;
        public Request(Context context,File source,String expectedSha,String frozenIdentity,PresetPreviewProfile profile,BooleanSupplier stillValid){
            if(context==null||source==null||expectedSha==null||!expectedSha.matches("[a-fA-F0-9]{64}")||frozenIdentity==null||frozenIdentity.isEmpty()||profile==null||stillValid==null)throw new IllegalArgumentException("成品预览快照无效。");
            this.context=context.getApplicationContext();this.source=source.getAbsoluteFile();sha=expectedSha;identity=frozenIdentity;this.profile=profile;this.stillValid=stillValid;
        }
    }
    public static final class Info {
        public final int width,height,quality;
        public final long jpegBytes;
        public final String jpegSha;
        public final PhotoExportSpec spec;
        Info(int width,int height,PhotoExportSpec spec,long bytes,String sha){this.width=width;this.height=height;this.spec=spec;quality=spec.quality;jpegBytes=bytes;jpegSha=sha;}
    }
    public static final class Tile {
        public final Rect bounds;
        public final Bitmap bitmap;
        Tile(Rect bounds,Bitmap bitmap){this.bounds=bounds;this.bitmap=bitmap;}
    }
    public static final class Frame {
        public final int mode,width,height,sample;
        public final Bitmap overview;
        public final List<Tile> tiles;
        Frame(int mode,Surface surface,int sample,List<Tile> tiles){this.mode=mode;width=surface.width;height=surface.height;overview=surface.overview;this.sample=sample;this.tiles=Collections.unmodifiableList(tiles);}
    }
    public interface Listener {
        void progress(double fraction);
        void ready(Info info);
        void failed(String message);
        void invalidated();
    }
    public interface FrameCallback { void loaded(Frame frame);void failed(String message);void invalidated(); }
    private static final class Surface {
        final BitmapRegionDecoder decoder;final Bitmap overview;final int width,height;final boolean jpeg;
        Surface(BitmapRegionDecoder decoder,Bitmap overview,boolean jpeg){this.decoder=decoder;this.overview=overview;this.jpeg=jpeg;width=decoder.getWidth();height=decoder.getHeight();}
    }
    private final Request request;
    private final File directory;
    private final long sourceLength,sourceModified;
    private final FileObserver observer;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,0,TimeUnit.SECONDS,new ArrayBlockingQueue<>(1),r->{Thread t=new Thread(r,"photo-export-preview");t.setDaemon(true);return t;},new ThreadPoolExecutor.DiscardOldestPolicy());
    private final Surface[] surfaces=new Surface[2];
    private final File[] surfaceFiles=new File[2];
    private final LinkedHashMap<String,Bitmap> cache=new LinkedHashMap<>(32,.75f,true);
    private int cacheBytes;
    private volatile boolean closed,sourceChanged,rendering,releasePending;
    private volatile long serial;
    private volatile Info info;
    @SuppressWarnings("deprecation") public PhotoExportPreview(Request request){
        this.request=request;directory=new File(request.context.getCacheDir(),"photo-export-preview-"+UUID.randomUUID());LIVE.add(directory.getName());
        sourceLength=request.source.length();sourceModified=request.source.lastModified();
        observer=new FileObserver(request.source.getParent(),FileObserver.CLOSE_WRITE|FileObserver.DELETE|FileObserver.MOVED_FROM|FileObserver.MODIFY|FileObserver.ATTRIB|FileObserver.DELETE_SELF|FileObserver.MOVE_SELF){public void onEvent(int event,String path){if(path==null||request.source.getName().equals(path))sourceChanged=true;}};observer.startWatching();
    }
    public boolean valid(){try{return !closed&&!sourceChanged&&request.source.isFile()&&request.source.length()==sourceLength&&request.source.lastModified()==sourceModified&&request.stillValid.getAsBoolean();}catch(RuntimeException unavailable){return false;}}
    public Info info(){return info;}
    /** Exposed for verification; this remains a cache file owned by this instance. */
    public File encodedFile(){return new File(directory,FILES[0]);}
    public File referenceFile(){return new File(directory,FILES[1]);}
    public void start(PhotoExportSpec spec,Listener listener){
        if(spec==null||listener==null)throw new IllegalArgumentException("spec/listener");
        if(rendering||info!=null)throw new IllegalStateException("每个成品预览只接受一份冻结规格。");
        rendering=true;
        worker.execute(()->{
            boolean acquired=false;
            try{
                while(!(acquired=RENDER_SLOT.tryAcquire(100,TimeUnit.MILLISECONDS)))check();
                check();if(!request.sha.equalsIgnoreCase(PhotoEditStore.hashFile(request.source)))throw new IOException("原图已变化，请返回后重新打开。");
                pruneOrphans();if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("成品预览暂存空间不可用。");
                AtomicInteger lastPercent=new AtomicInteger(-1);
                PhotoPresetRenderer.forContext(request.context).renderWithReference(request.source,encodedFile(),referenceFile(),request.profile,spec,()->!valid(),value->{int percent=Math.max(0,Math.min(100,(int)Math.round(value*100)));if(lastPercent.getAndSet(percent)!=percent)main.post(()->{if(valid())listener.progress(percent/100.0);});});
                check();if(!request.sha.equalsIgnoreCase(PhotoEditStore.hashFile(request.source)))throw new IOException("原图已变化，请返回后重新打开。");
                PhotoPreviewCache.validateJpeg(encodedFile(),encodedFile().length());
                int orientation=new ExifInterface(encodedFile().getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);if(orientation<1||orientation>8)orientation=1;
                surfaceFiles[JPEG]=encodedFile();surfaceFiles[BEFORE_ENCODING]=referenceFile();
                // JPEG95 full-size may retain original EXIF orientation. Normalize both sources
                // losslessly after JPEG decoding so the comparison still shows the real JPEG.
                if(orientation!=1){
                    BitmapFactory.Options size=new BitmapFactory.Options();size.inJustDecodeBounds=true;BitmapFactory.decodeFile(encodedFile().getPath(),size);
                    long extra=(long)size.outWidth*size.outHeight*8+1024*1024,free=directory.getUsableSpace();if(size.outWidth<1||size.outHeight<1||free>0&&free<extra)throw new IOException("存储空间不足，无法准备完整方向预览。");
                    File jpegDisplay=new File(directory,FILES[2]),referenceDisplay=new File(directory,FILES[3]);
                    normalize(encodedFile(),jpegDisplay,orientation);normalize(referenceFile(),referenceDisplay,orientation);
                    surfaceFiles[JPEG]=jpegDisplay;surfaceFiles[BEFORE_ENCODING]=referenceDisplay;
                }
                Surface current=surface(JPEG),before=surface(BEFORE_ENCODING);check();
                if(current.width!=before.width||current.height!=before.height)throw new IOException("编码前后尺寸不一致，未显示错误对比。");
                PhotoPresetRenderer.Dimensions natural=PhotoPresetRenderer.dimensions(request.source,request.profile);PhotoExportSpec.Resolved resolved=spec.resolve(natural.width,natural.height);
                if(current.width!=resolved.width||current.height!=resolved.height)throw new IOException("成品预览尺寸核对失败。");
                info=new Info(current.width,current.height,spec,encodedFile().length(),PhotoEditStore.hashFile(encodedFile()));rendering=false;
                main.post(()->{if(valid())listener.ready(info);else if(!closed)listener.invalidated();});
            }catch(Exception|OutOfMemoryError failure){
                rendering=false;releaseSurfaces();removeFiles();
                String message=failure instanceof OutOfMemoryError?"完整成品预览内存不足，未缩小图片。":failure.getMessage();
                main.post(()->{if(closed)return;if(!valid())listener.invalidated();else listener.failed(message==null?"成品预览生成失败，请重试。":message);});
            }finally{if(acquired)RENDER_SLOT.release();}
        });
    }
    public void cancelFrames(){serial++;if(!rendering)worker.getQueue().clear();}
    public void releaseMemory(){if(closed)return;cancelFrames();releasePending=true;worker.execute(()->{if(releasePending){releasePending=false;releaseSurfaces();}});}
    public void frame(int mode,int canvasWidth,int canvasHeight,double scale,double nx,double ny,FrameCallback callback){
        if(mode!=JPEG&&mode!=BEFORE_ENCODING)throw new IllegalArgumentException("mode");if(closed||info==null)return;
        final long token=++serial;
        worker.execute(()->{
            try{
                if(releasePending){releasePending=false;releaseSurfaces();}check();Surface surface=surface(mode);
                PhotoDetailViewport viewport=new PhotoDetailViewport();viewport.canvas(canvasWidth,canvasHeight);viewport.image(surface.width,surface.height);
                if(scale>0){viewport.fitting=false;viewport.scale=scale;viewport.center(nx*surface.width,ny*surface.height);}else viewport.fitImage();
                int sample=viewport.sample(),step=TILE*sample;
                int left=Math.max(0,(int)Math.floor(viewport.centerX-canvasWidth/(2*viewport.scale))),top=Math.max(0,(int)Math.floor(viewport.centerY-canvasHeight/(2*viewport.scale)));
                int right=Math.min(surface.width,(int)Math.ceil(viewport.centerX+canvasWidth/(2*viewport.scale))),bottom=Math.min(surface.height,(int)Math.ceil(viewport.centerY+canvasHeight/(2*viewport.scale)));
                List<Tile> tiles=new ArrayList<>();long pixels=0;
                for(int y=top/step*step;y<bottom;y+=step)for(int x=left/step*step;x<right;x+=step){
                    check();if(token!=serial)return;Rect region=new Rect(x,y,Math.min(x+step,surface.width),Math.min(y+step,surface.height));String key=mode+":"+sample+":"+x+":"+y;
                    Bitmap tile=cache.get(key);if(tile==null){tile=decodeTile(surface,region,sample);put(key,tile);}pixels+=(long)tile.getWidth()*tile.getHeight();
                    if(pixels>8_388_608L)throw new IOException("此视口所需内存过多，请缩小后重试。");tiles.add(new Tile(region,tile));
                }
                Frame frame=new Frame(mode,surface,sample,tiles);
                main.post(()->{if(closed||token!=serial)return;if(valid())callback.loaded(frame);else callback.invalidated();});
            }catch(Exception|OutOfMemoryError failure){String message=failure instanceof OutOfMemoryError?"成品细节内存不足，请缩小后重试。":failure.getMessage();main.post(()->{if(closed||token!=serial)return;if(valid())callback.failed(message==null?"成品区域读取失败。":message);else callback.invalidated();});}
        });
    }
    private Surface surface(int mode)throws IOException{
        if(surfaces[mode]!=null)return surfaces[mode];File file=surfaceFiles[mode];if(file==null||!file.isFile())throw new IOException("成品预览文件不可用。");
        BitmapRegionDecoder decoder=null;Bitmap overview=null;
        try{
            decoder=BitmapRegionDecoder.newInstance(file.getPath(),false);if(decoder==null)throw new IOException("成品区域读取失败。");
            int sample=1;while(Math.max(decoder.getWidth(),decoder.getHeight())/(double)sample>1024)sample*=2;
            overview=BitmapFactory.decodeFile(file.getPath(),options(sample));if(overview==null)throw new IOException("成品概览读取失败。");overview.setDensity(Bitmap.DENSITY_NONE);
            Surface created=new Surface(decoder,overview,file.equals(encodedFile()));surfaces[mode]=created;return created;
        }catch(IOException|RuntimeException|OutOfMemoryError failure){if(decoder!=null)decoder.recycle();if(overview!=null)overview.recycle();throw failure;}
    }
    private void normalize(File source,File target,int orientation)throws IOException{
        Bitmap bitmap=null;try{check();bitmap=BitmapFactory.decodeFile(source.getPath(),options(1));if(bitmap==null)throw new IOException("无法按完整尺寸读取成品。");Bitmap normalized=PhotoComposition.apply(bitmap,PhotoGeometry.NONE,orientation);if(normalized!=bitmap)bitmap.recycle();bitmap=normalized;check();try(FileOutputStream out=new FileOutputStream(target)){if(!bitmap.compress(Bitmap.CompressFormat.PNG,100,out))throw new IOException("成品方向归一失败。");out.flush();out.getFD().sync();}check();}finally{if(bitmap!=null)bitmap.recycle();}
    }
    private Bitmap decodeTile(Surface surface,Rect region,int sample)throws IOException{
        if(!surface.jpeg){Bitmap result=surface.decoder.decodeRegion(region,options(sample));if(result==null)throw new IOException("成品区域解码失败。");result.setDensity(Bitmap.DENSITY_NONE);return result;}
        // Keep JPEG chroma neighbours at tile seams; no resampling at the 100% setting.
        if(region.width()<sample||region.height()<sample)sample=1;int halo=32*sample;
        Rect expanded=new Rect(Math.max(0,region.left-halo),Math.max(0,region.top-halo),Math.min(surface.width,region.right+halo),Math.min(surface.height,region.bottom+halo));
        Bitmap decoded=surface.decoder.decodeRegion(expanded,options(sample));if(decoded==null)throw new IOException("JPEG 区域解码失败。");
        try{int x=(region.left-expanded.left)/sample,y=(region.top-expanded.top)/sample;int width=Math.min((region.width()+sample-1)/sample,decoded.getWidth()-x),height=Math.min((region.height()+sample-1)/sample,decoded.getHeight()-y);Bitmap tile=Bitmap.createBitmap(decoded,x,y,width,height);tile.setDensity(Bitmap.DENSITY_NONE);if(tile==decoded)decoded=null;return tile;}finally{if(decoded!=null)decoded.recycle();}
    }
    private static BitmapFactory.Options options(int sample){BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=sample;options.inScaled=false;options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);return options;}
    private void put(String key,Bitmap bitmap){cache.put(key,bitmap);cacheBytes+=bitmap.getAllocationByteCount();while(cacheBytes>CACHE_BYTES&&!cache.isEmpty()){Map.Entry<String,Bitmap> first=cache.entrySet().iterator().next();cacheBytes-=first.getValue().getAllocationByteCount();cache.remove(first.getKey());}}
    private void check()throws IOException{if(!valid()||Thread.currentThread().isInterrupted())throw new IOException("成品预览已失效。");}
    private void releaseSurfaces(){cache.clear();cacheBytes=0;for(int i=0;i<surfaces.length;i++){Surface surface=surfaces[i];surfaces[i]=null;if(surface!=null){surface.decoder.recycle();surface.overview.recycle();}}}
    private void removeFiles(){for(String name:FILES){File file=new File(directory,name);if(file.isFile())file.delete();}directory.delete();}
    private void pruneOrphans(){File[] children=request.context.getCacheDir().listFiles();if(children==null)return;synchronized(LIVE){for(File child:children){if(!child.isDirectory()||!child.getName().matches("photo-export-preview-[a-f0-9-]{36}")||LIVE.contains(child.getName()))continue;for(String name:FILES){File file=new File(child,name);if(file.isFile())file.delete();}child.delete();}}}
    @Override public void close(){if(closed)return;closed=true;observer.stopWatching();serial++;worker.getQueue().clear();worker.execute(()->{releaseSurfaces();removeFiles();LIVE.remove(directory.getName());});worker.shutdown();}
}
