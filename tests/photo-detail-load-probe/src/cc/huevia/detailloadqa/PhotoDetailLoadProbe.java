package cc.huevia.detailloadqa;

import android.app.Instrumentation;
import android.content.Context;
import android.graphics.*;
import android.media.ExifInterface;
import android.os.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.*;
import org.json.*;

/** Production codec/source benchmark on one private generated 12 MP JPEG, never a user photo. */
public final class PhotoDetailLoadProbe extends Instrumentation {
    private Bundle args; private ClassLoader loader; private Context context; private File work,output,photo;
    private String photoSha; private final List<Object> sources=new ArrayList<>();
    private final JSONObject report=new JSONObject();private final JSONArray checks=new JSONArray(),timings=new JSONArray();
    @Override public void onCreate(Bundle args){super.onCreate(args);this.args=args==null?new Bundle():args;start();}
    @Override public void onStart(){Bundle result=new Bundle();boolean passed=false;try{
        require(Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"),"emulator-only");
        context=getTargetContext();loader=context.getClassLoader();String apkSha=sha(new File(context.getApplicationInfo().sourceDir));
        require(apkSha.equals(args.getString("apkSha256")),"exact-installed-APK");
        String runId=args.getString("runId","");require(runId.matches("[a-f0-9]{32}"),"run-identity");
        output=new File(context.getExternalFilesDir(null),"photo-detail-load-94/"+apkSha.substring(0,8)+"/"+runId);require(output.mkdirs(),"own-evidence-directory");
        work=new File(context.getCacheDir(),"detail-load-probe-"+runId);require(work.mkdirs(),"own-fixture-directory");
        report.put("apkSha256",apkSha).put("runId",runId).put("hardware",Build.HARDWARE).put("scope","Production Android JPEG/PNG codecs and PhotoDetailSource; private deterministic 4000x3000 JPEG. Cold means a new page/source without surfaces; OS disk cache is not flushed. Warm means same source/tile cache. Timings are emulator observations, not a physical phone claim.");
        fixture();photoSha=sha(photo);report.put("fixture",new JSONObject().put("width",4000).put("height",3000).put("bytes",photo.length()).put("sha256",photoSha));
        Object original=profile(false),effect=profile(true);
        oddEdgeProof(original);
        // Retain an exact legacy pipeline baseline: hashes + full renderer + PNG overview + visible fit tiles.
        timings.put(legacy("saved-legacy-cold",original,true));
        Object saved=source(original,false,new AtomicBoolean(true));
        require(!bool(field(saved,"request"),"currentUnchanged"),"legacy-request-overload-defaults-to-unknown-current");
        Observation cold=frame(saved,0,0);timings.put(cold.json("saved-optimized-cold"));
        require(cold.preview!=null&&bool(cold.preview,"provisional"),"interim-frame-explicitly-provisional");
        require(!bool(cold.frame,"provisional")&&integer(cold.frame,"width")==4000&&integer(cold.frame,"height")==3000,"complete-saved-frame-keeps-full-dimensions");
        Object surface=((Object[])field(saved,"surfaces"))[0];require(!bool(surface,"temporary")&&field(surface,"file").equals(photo),"saved-frame-directly-decodes-owned-original-without-PNG");
        require(!((File)field(saved,"directory")).exists(),"saved-direct-path-does-not-create-PNG-directory");
        Observation savedOne=frame(saved,0,1);timings.put(savedOne.json("saved-optimized-warm-100"));require(integer(savedOne.frame,"sample")==1,"100-percent-unsampled-regions");pixelProof(savedOne.frame);
        Observation savedTwo=frame(saved,0,2);timings.put(savedTwo.json("saved-optimized-warm-200"));require(integer(savedTwo.frame,"sample")==1,"200-percent-unsampled-regions");
        close(saved);require(photo.isFile()&&photoSha.equals(sha(photo)),"closing-direct-decoder-preserves-source-bytes");
        // A new page is measured separately from the warm tile cache.
        Object reopen=source(original,false,new AtomicBoolean(true));timings.put(frame(reopen,0,0).json("saved-optimized-reopen"));close(reopen);
        timings.put(legacy("unmodified-current-legacy-cold",original,false));
        Object unmodified=source(photo,photoSha,original,true,true,new AtomicBoolean(true));Observation unmodifiedCurrent=frame(unmodified,0,0);timings.put(unmodifiedCurrent.json("unmodified-current-optimized-cold"));
        require(!bool(((Object[])field(unmodified,"surfaces"))[0],"temporary"),"explicit-neutral-current-uses-direct-JPEG");
        require((Boolean)type("album.PhotoDetailSource").getMethod("canCompare").invoke(unmodified),"neutral-current-retains-before-comparison");
        require(unmodifiedCurrent.preview!=null&&integer(unmodifiedCurrent.frame,"width")==4000&&integer(unmodifiedCurrent.frame,"height")==3000,"neutral-current-preview-and-complete-keep-full-dimensions");
        require(integer(frame(unmodified,0,1).frame,"sample")==1,"neutral-current-100-percent-unsampled");close(unmodified);
        timings.put(legacy("effect-legacy-cold",effect,false));
        Object edited=source(effect,true,new AtomicBoolean(true));Observation current=frame(edited,0,0);timings.put(current.json("effect-optimized-cold"));
        require(current.preview!=null&&current.previewMs<current.completeMs,"edited-fit-preview-arrives-before-full-pixel-surface");
        require(bool(((Object[])field(edited,"surfaces"))[0],"temporary"),"edited-final-frame-retains-lossless-full-resolution-surface");
        Observation editedOne=frame(edited,0,1);require(integer(editedOne.frame,"sample")==1,"edited-100-percent-unsampled-regions");timings.put(editedOne.json("effect-optimized-warm-100"));
        Observation before=frame(edited,1,1);timings.put(before.json("before-optimized-cold-100"));require(!bool(((Object[])field(edited,"surfaces"))[1],"temporary"),"neutral-before-direct-JPEG-path");require(integer(before.frame,"width")==integer(editedOne.frame,"width")&&integer(before.frame,"height")==integer(editedOne.frame,"height"),"before-current-same-full-geometry");close(edited);
        // Nonneutral EXIF must retain normalized full surfaces, never mislabeled raw JPEG coordinates.
        File rotated=new File(work,"rotated.jpg");Files.copy(photo.toPath(),rotated.toPath());ExifInterface exif=new ExifInterface(rotated.getPath());exif.setAttribute(ExifInterface.TAG_ORIENTATION,"6");exif.saveAttributes();
        Object rotatedSource=source(rotated,sha(rotated),original,false,new AtomicBoolean(true));Observation rotatedFrame=frame(rotatedSource,0,0);require(integer(rotatedFrame.frame,"width")==3000&&integer(rotatedFrame.frame,"height")==4000,"rotated-EXIF-full-dimensions-preserved");require(bool(((Object[])field(rotatedSource,"surfaces"))[0],"temporary"),"rotated-source-uses-normalized-lossless-surface");close(rotatedSource);
        AtomicBoolean ownerValid=new AtomicBoolean(true);Object guarded=source(original,false,ownerValid);frame(guarded,0,0);ownerValid.set(false);Observation invalid=frameAllowInvalid(guarded);require(invalid.invalidated,"owner-invalidation-rejects-cache-and-preview");close(guarded);
        require(photoSha.equals(sha(photo)),"all-read-and-close-paths-preserve-original");passed=true;
    }catch(Throwable failure){try{report.put("failure",failure.toString());StringWriter stack=new StringWriter();failure.printStackTrace(new PrintWriter(stack));report.put("stack",stack.toString());}catch(Exception ignored){}result.putString("failure",failure.toString());}
    finally{
        for(Object source:new ArrayList<>(sources))try{close(source);}catch(Exception ignored){}
        boolean cleaned=true;try{if(work!=null&&work.isDirectory()){File[] children=work.listFiles();if(children!=null)for(File file:children)cleaned&=file.isFile()&&file.delete();cleaned&=work.delete();}}catch(Exception failure){cleaned=false;}
        try{report.put("status",passed&&cleaned?"PASS":"FAIL").put("assertions",checks).put("timings",timings).put("fixtureCleanup",cleaned);if(output!=null)Files.writeString(new File(output,"report.json").toPath(),report.toString(2));}catch(Exception failure){passed=false;}
        result.putString("stream",passed&&cleaned?"Photo detail load PASS\n":"Photo detail load FAIL\n");finish(passed&&cleaned?-1:0,result);
    }}
    private void fixture()throws Exception{
        photo=new File(work,"source.jpg");Bitmap bitmap=Bitmap.createBitmap(4000,3000,Bitmap.Config.ARGB_8888);int[] row=new int[4000];
        for(int y=0;y<3000;y++){for(int x=0;x<4000;x++){int n=(x*73+y*151+(x*y*13))&31;row[x]=0xff000000|(((x/17+n)&255)<<16)|(((y/13+n)&255)<<8)|((x/23+y/19+n)&255);}bitmap.setPixels(row,0,4000,0,y,4000,1);}
        try(FileOutputStream out=new FileOutputStream(photo)){require(bitmap.compress(Bitmap.CompressFormat.JPEG,95,out),"large-local-JPEG-generated");}finally{bitmap.recycle();}
    }
    private Object profile(boolean edited)throws Exception{int[] values=new int[13];if(edited){values[1]=3;values[2]=8;}Object manual=type("ncp.PhotoAdjustments").getConstructor(int[].class).newInstance((Object)values);return type("ncp.AdjustedPreviewProfile").getMethod("of",type("ncp.PresetPreviewProfile"),type("ncp.PhotoAdjustments")).invoke(null,null,manual);}
    private void oddEdgeProof(Object profile)throws Exception{
        File odd=new File(work,"odd.jpg");Bitmap decoded=BitmapFactory.decodeFile(photo.getPath(),options(1));Bitmap cropped=Bitmap.createBitmap(decoded,0,0,2401,1601);
        try(FileOutputStream out=new FileOutputStream(odd)){require(cropped.compress(Bitmap.CompressFormat.JPEG,95,out),"odd-JPEG-generated");}finally{cropped.recycle();decoded.recycle();}
        String hash=sha(odd);Object source=source(odd,hash,profile,false,new AtomicBoolean(true));Observation fit=frame(source,0,0);
        require(integer(fit.frame,"sample")==2&&integer(fit.frame,"width")==2401&&integer(fit.frame,"height")==1601,"odd-2401x1601-fit-reads-real-sampled-edge-tiles");
        Observation full=frame(source,0,1);pixelProof(full.frame,odd,"oddPhysicalPixelProof");close(source);require(hash.equals(sha(odd)),"odd-JPEG-source-unchanged");
        // An image one pixel wider/taller than a tile stride has sub-sample tails.
        decoded=BitmapFactory.decodeFile(odd.getPath(),options(1));cropped=Bitmap.createBitmap(decoded,0,0,2049,1025);File tail=new File(work,"tail.jpg");
        try(FileOutputStream out=new FileOutputStream(tail)){require(cropped.compress(Bitmap.CompressFormat.JPEG,95,out),"thin-tail-JPEG-generated");}finally{cropped.recycle();decoded.recycle();}
        Object tailSource=source(tail,sha(tail),profile,false,new AtomicBoolean(true));Observation tailFit=frame(tailSource,0,0,false,800);
        require(integer(tailFit.frame,"sample")==2,"sub-sample-one-pixel-tails-remain-decodable");close(tailSource);
    }
    private Object source(Object profile,boolean compare,AtomicBoolean valid)throws Exception{return source(photo,photoSha,profile,compare,valid);}
    private Object source(File input,String hash,Object profile,boolean compare,AtomicBoolean valid)throws Exception{Object request=type("album.PhotoDetailSource$Request").getConstructor(Context.class,File.class,String.class,String.class,type("ncp.PresetPreviewProfile"),boolean.class,BooleanSupplier.class).newInstance(context,input,hash,"owned-load-"+UUID.randomUUID(),profile,compare,(BooleanSupplier)valid::get);Object source=type("album.PhotoDetailSource").getConstructor(type("album.PhotoDetailSource$Request")).newInstance(request);sources.add(source);return source;}
    private Object source(File input,String hash,Object profile,boolean compare,boolean unchanged,AtomicBoolean valid)throws Exception{Object request=type("album.PhotoDetailSource$Request").getConstructor(Context.class,File.class,String.class,String.class,type("ncp.PresetPreviewProfile"),boolean.class,boolean.class,BooleanSupplier.class).newInstance(context,input,hash,"owned-load-"+UUID.randomUUID(),profile,compare,unchanged,(BooleanSupplier)valid::get);Object source=type("album.PhotoDetailSource").getConstructor(type("album.PhotoDetailSource$Request")).newInstance(request);sources.add(source);return source;}
    private static final class Observation{Object preview,frame;double previewMs=-1,completeMs=-1;boolean invalidated;String failure;JSONObject json(String name)throws Exception{return new JSONObject().put("case",name).put("firstPreviewMs",previewMs).put("completeFrameMs",completeMs).put("sample",frame==null?-1:integer(frame,"sample"));}}
    private Observation frame(Object source,int mode,double scale)throws Exception{return frame(source,mode,scale,false);}
    private Observation frameAllowInvalid(Object source)throws Exception{return frame(source,0,0,true);}
    private Observation frame(Object source,int mode,double scale,boolean allowInvalid)throws Exception{
        return frame(source,mode,scale,allowInvalid,1080);
    }
    private Observation frame(Object source,int mode,double scale,boolean allowInvalid,int width)throws Exception{
        Observation observation=new Observation();CountDownLatch done=new CountDownLatch(1);long start=System.nanoTime();
        Object callback=Proxy.newProxyInstance(loader,new Class<?>[]{type("album.PhotoDetailSource$Callback")},(proxy,method,args)->{switch(method.getName()){
            case "preview":if(observation.preview==null){observation.preview=args[0];observation.previewMs=elapsed(start);}break;
            case "loaded":observation.frame=args[0];observation.completeMs=elapsed(start);done.countDown();break;
            case "failed":observation.failure=(String)args[0];done.countDown();break;
            case "invalidated":observation.invalidated=true;done.countDown();break;
            case "toString":return "Owned detail load callback";
        }return null;});
        type("album.PhotoDetailSource").getMethod("frame",int.class,int.class,int.class,double.class,double.class,double.class,type("album.PhotoDetailSource$Callback")).invoke(source,mode,width,1920,scale,.5,.5,callback);
        require(done.await(120,TimeUnit.SECONDS),"source-frame-completed-within-bounded-time");if(observation.failure!=null)throw new AssertionError(observation.failure);if(!allowInvalid)require(!observation.invalidated&&observation.frame!=null,"source-frame-valid");return observation;
    }
    private JSONObject legacy(String name,Object profile,boolean before)throws Exception{
        File target=new File(work,"baseline-"+name+".png");long start=System.nanoTime();BitmapRegionDecoder decoder=null;Bitmap overview=null;
        try{
            require(photoSha.equals(sha(photo)),"legacy-source-pre-hash");Object renderer=type("album.PhotoPresetRenderer").getConstructor(android.content.res.AssetManager.class).newInstance(context.getAssets());
            type("album.PhotoPresetRenderer").getMethod("renderDetail",File.class,File.class,type("ncp.PresetPreviewProfile"),boolean.class,BooleanSupplier.class,type("album.PhotoPresetRenderer$Progress")).invoke(renderer,photo,target,profile,before,(BooleanSupplier)()->false,null);
            require(photoSha.equals(sha(photo)),"legacy-source-post-hash");decoder=BitmapRegionDecoder.newInstance(target.getPath(),false);BitmapFactory.Options options=options(4);overview=BitmapFactory.decodeFile(target.getPath(),options);
            int sample=2,step=512*sample;for(int y=0;y<3000;y+=step)for(int x=0;x<4000;x+=step){Bitmap tile=decoder.decodeRegion(new Rect(x,y,Math.min(x+step,4000),Math.min(y+step,3000)),options(sample));require(tile!=null,"legacy-visible-fit-region");tile.recycle();}
            return new JSONObject().put("case",name).put("firstPreviewMs",-1).put("completeFrameMs",elapsed(start)).put("temporaryPngBytes",target.length()).put("sample",sample);
        }finally{if(decoder!=null)decoder.recycle();if(overview!=null)overview.recycle();target.delete();}
    }
    private void pixelProof(Object frame)throws Exception{
        pixelProof(frame,photo,"physicalPixelProof");
    }
    private void pixelProof(Object frame,File input,String key)throws Exception{
        Bitmap oracle=BitmapFactory.decodeFile(input.getPath(),options(1));int count=0,errors=0;try{for(Object tile:(List<?>)field(frame,"tiles")){Rect bounds=(Rect)field(tile,"bounds");Bitmap pixels=(Bitmap)field(tile,"bitmap");for(int y=0;y<pixels.getHeight();y+=37)for(int x=0;x<pixels.getWidth();x+=41){count++;if(pixels.getPixel(x,y)!=oracle.getPixel(bounds.left+x,bounds.top+y))errors++;}}}finally{oracle.recycle();}
        require(count>1000&&errors==0,"direct-region-pixels-equal-full-JPEG-decode");report.put(key,new JSONObject().put("count",count).put("errors",errors).put("sample",integer(frame,"sample")));
    }
    private void close(Object source)throws Exception{type("album.PhotoDetailSource").getMethod("close").invoke(source);ThreadPoolExecutor worker=(ThreadPoolExecutor)field(source,"worker");require(worker.awaitTermination(10,TimeUnit.SECONDS),"source-worker-closed-and-surfaces-released");require(!((File)field(source,"directory")).exists(),"source-owned-temporary-directory-removed");sources.remove(source);}
    private void require(boolean pass,String name)throws Exception{checks.put(new JSONObject().put("name",name).put("passed",pass));if(!pass)throw new AssertionError(name);}
    private Class<?> type(String suffix)throws Exception{return Class.forName("cc.huevia."+suffix,true,loader);}
    private static Object field(Object object,String name)throws Exception{Field field=object.getClass().getDeclaredField(name);field.setAccessible(true);return field.get(object);}
    private static int integer(Object object,String name)throws Exception{return (Integer)field(object,name);}
    private static boolean bool(Object object,String name)throws Exception{return (Boolean)field(object,name);}
    private static double elapsed(long start){return (System.nanoTime()-start)/1_000_000.0;}
    private static BitmapFactory.Options options(int sample){BitmapFactory.Options o=new BitmapFactory.Options();o.inSampleSize=sample;o.inScaled=false;o.inPreferredConfig=Bitmap.Config.ARGB_8888;o.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);return o;}
    private static String sha(File file)throws Exception{MessageDigest digest=MessageDigest.getInstance("SHA-256");byte[] buffer=new byte[65536];try(InputStream in=new FileInputStream(file)){int n;while((n=in.read(buffer))!=-1)digest.update(buffer,0,n);}StringBuilder out=new StringBuilder();for(byte b:digest.digest())out.append(String.format(Locale.ROOT,"%02x",b&255));return out.toString();}
}
