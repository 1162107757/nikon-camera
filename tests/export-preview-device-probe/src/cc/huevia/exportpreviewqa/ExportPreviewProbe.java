package cc.huevia.exportpreviewqa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.media.ExifInterface;
import android.os.*;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;
import org.json.*;

/** Reflection-only checks against the exact installed app, not bundled copies of production code. */
public final class ExportPreviewProbe extends Instrumentation {
    private Bundle args;private Context context;private Activity activity;private ClassLoader loader;
    private File work,output,photo;private String originalSha,stage="start";private Object profile,dialog,canvas,source;
    private Throwable failure;private boolean cleaned;
    private final AtomicBoolean ownerValid=new AtomicBoolean(true);
    private final JSONArray checks=new JSONArray(),measurements=new JSONArray(),screenshots=new JSONArray();
    @Override public void onCreate(Bundle value){super.onCreate(value);args=value==null?new Bundle():value;start();}
    @Override public void onStart(){try{
        context=getTargetContext();loader=context.getClassLoader();check("emulator-only",Build.HARDWARE.matches("ranchu|goldfish"));check("exact-installed-apk",sha(new File(context.getApplicationInfo().sourceDir)).equals(args.getString("apkSha256")));
        String run=args.getString("runId","");check("safe-run-id",run.matches("[a-f0-9]{32}"));output=new File(context.getExternalFilesDir(null),"photo-export-preview/"+run);check("new-evidence-directory",output.mkdirs());work=new File(context.getCacheDir(),"export-preview-qa-"+run);check("new-fixture-directory",work.mkdirs());
        photo=fixture();originalSha=sha(photo);profile=neutral();activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));until(()->(Boolean)get(activity,"ready"),"main-ready");
        stage="custom-jpeg";Object spec=type("album.PhotoExportSpec").getMethod("custom",int.class,int.class).invoke(null,640,70);open(spec,profile);until(this::ready,"actual-preview-ready");Object info=get(dialog,"info");check("actual-preview-resolved-dimensions",integer(info,"width")==640&&integer(info,"height")==457);check("actual-preview-quality",integer(info,"quality")==70);File jpeg=(File)call(source,"encodedFile",new Class<?>[]{}),reference=(File)call(source,"referenceFile",new Class<?>[]{});check("actual-file-byte-count",(Long)get(info,"jpegBytes")==jpeg.length());check("actual-file-sha",get(info,"jpegSha").equals(sha(jpeg)));compressionProof(jpeg,reference);
        ui(()->callPrivate(canvas,"zoom",new Class<?>[]{double.class},1d));until(this::settled,"jpeg-100-settled");pixelProof("jpeg");capture("01-real-jpeg-100");ui(()->callPrivate(canvas,"mode",new Class<?>[]{int.class},1));until(()->settled()&&integer(get(canvas,"frame"),"mode")==1,"reference-100-settled");pixelProof("reference");capture("02-before-encoding-100");
        stage="pan-and-zoom";ui(()->callPrivate(canvas,"zoom",new Class<?>[]{double.class},2d));until(this::settled,"reference-200-settled");check("zoom-is-physical-200",Math.abs((Double)get(get(canvas,"viewport"),"scale")-2)<.0001);double previousCenter=(Double)get(get(canvas,"viewport"),"centerX");ui(()->{View v=(View)canvas;long now=SystemClock.uptimeMillis();touch(v,now,MotionEvent.ACTION_DOWN,v.getWidth()*.7f,v.getHeight()*.6f);touch(v,now,MotionEvent.ACTION_MOVE,v.getWidth()*.3f,v.getHeight()*.4f);touch(v,now,MotionEvent.ACTION_UP,v.getWidth()*.3f,v.getHeight()*.4f);});until(this::settled,"reference-pan-settled");check("real-gesture-moves-photo-center",Math.abs((Double)get(get(canvas,"viewport"),"centerX")-previousCenter)>1);capture("03-reference-200");close();
        stage="exif-and-full";ExifInterface exif=new ExifInterface(photo.getPath());exif.setAttribute(ExifInterface.TAG_ORIENTATION,"6");exif.saveAttributes();originalSha=sha(photo);Object full=type("album.PhotoExportSpec").getMethod("full").invoke(null);open(full,profile);until(this::ready,"exif-full-ready");info=get(dialog,"info");check("full-exif-displayed-dimensions",integer(info,"width")==1000&&integer(info,"height")==1400);check("full-95-quality",integer(info,"quality")==95);ui(()->callPrivate(canvas,"zoom",new Class<?>[]{double.class},1d));until(this::settled,"exif-jpeg-100-ready");pixelProof("exif-jpeg");ui(()->callPrivate(canvas,"mode",new Class<?>[]{int.class},1));until(this::settled,"exif-reference-100-ready");pixelProof("exif-reference");close();
        stage="composition-and-border";Object geometry=type("ncp.PhotoGeometry").getConstructor(int.class,int.class,int.class,int.class,int.class,int.class).newInstance(1,0,100000,50000,900000,950000);Object composed=type("ncp.GeometryPreviewProfile").getMethod("of",type("ncp.PresetPreviewProfile"),type("ncp.PhotoGeometry")).invoke(null,profile,geometry);Object border=type("ncp.PhotoBorder").getField("NONE").get(null);border=call(border,"withTemplate",new Class<?>[]{int.class},3);composed=type("ncp.BorderPreviewProfile").getMethod("of",type("ncp.PresetPreviewProfile"),type("ncp.PhotoBorder")).invoke(null,composed,border);open(spec,composed);until(this::ready,"framed-composition-ready");info=get(dialog,"info");check("frame-obeys-final-long-edge",Math.max(integer(info,"width"),integer(info,"height"))==640);ui(()->callPrivate(canvas,"zoom",new Class<?>[]{double.class},1d));until(this::settled,"framed-100-ready");pixelProof("framed-jpeg");capture("04-frame-and-crop");
        stage="owner-invalidates";ownerValid.set(false);until(()->!((Dialog)dialog).isShowing(),"owner-invalidation-dismisses");awaitClosed();check("original-preserved",originalSha.equals(sha(photo)));
        stage="close-pending";ownerValid.set(true);open(full,profile);ui(()->((Dialog)dialog).dismiss());awaitClosed();check("pending-close-preserves-original",originalSha.equals(sha(photo)));
        stage="complete";
    }catch(Throwable problem){failure=unwrap(problem);try{capture("failure");}catch(Throwable ignored){}}
    finally{try{if(dialog!=null)ui(()->((Dialog)dialog).dismiss());if(source!=null)awaitClosed();if(activity!=null)ui(activity::finish);}catch(Throwable e){if(failure==null)failure=unwrap(e);}cleaned=cleanFixtures();if(!cleaned&&failure==null)failure=new AssertionError("private-fixture-cleanup");try{if(output!=null){JSONObject report=new JSONObject().put("pass",failure==null).put("stage",stage).put("apkSha256",args.getString("apkSha256")).put("checks",checks).put("measurements",measurements).put("screenshots",screenshots).put("fixtureCleanup",cleaned).put("failure",failure==null?JSONObject.NULL:failure.toString()).put("scope","Actual installed export-preview source and dialog; generated JPEG, JPEG/reference pixel oracle, EXIF6, crop/frame, normal-font emulator, account invalidation and pending close. No physical handset, camera or gallery publishing.");try(FileOutputStream out=new FileOutputStream(new File(output,"report.json"))){out.write(report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));}}}catch(Throwable ignored){}Bundle result=new Bundle();result.putString("stream",failure==null?"PASS "+checks.length()+" checks":"FAIL "+failure);finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);}}
    private Object neutral()throws Exception{Object settings=type("ncp.PhotoAdjustments").getField("NONE").get(null);return type("ncp.AdjustedPreviewProfile").getMethod("of",type("ncp.PresetPreviewProfile"),type("ncp.PhotoAdjustments")).invoke(null,null,settings);}
    private void open(Object spec,Object selectedProfile)throws Exception{Object request=type("album.PhotoExportPreview$Request").getConstructor(Context.class,File.class,String.class,String.class,type("ncp.PresetPreviewProfile"),BooleanSupplier.class).newInstance(activity,photo,sha(photo),"export-preview-qa-"+UUID.randomUUID(),selectedProfile,(BooleanSupplier)ownerValid::get);ui(()->{dialog=type("ui.PhotoExportPreviewDialog").getMethod("show",Activity.class,type("album.PhotoExportPreview$Request"),type("album.PhotoExportSpec"),String.class).invoke(null,activity,request,spec,"QA_ACTUAL_EXPORT.JPG");canvas=get(dialog,"canvas");source=get(dialog,"source");});}
    private boolean ready()throws Exception{return get(dialog,"info")!=null&&settled();}
    private boolean settled()throws Exception{return get(canvas,"frame")!=null&&!(Boolean)get(canvas,"inFlight")&&!(Boolean)get(canvas,"queued")&&!(Boolean)get(canvas,"scheduled");}
    private void close()throws Exception{ui(()->((Dialog)dialog).dismiss());awaitClosed();}
    private void awaitClosed()throws Exception{Object frozen=source;File directory=(File)get(frozen,"directory");java.util.concurrent.ThreadPoolExecutor worker=(java.util.concurrent.ThreadPoolExecutor)get(frozen,"worker");long until=SystemClock.uptimeMillis()+30000;while(!worker.isTerminated()&&SystemClock.uptimeMillis()<until)SystemClock.sleep(25);check("preview-worker-terminated",worker.isTerminated());check("preview-private-files-removed",!directory.exists());}
    private void compressionProof(File jpeg,File reference)throws Exception{Bitmap a=BitmapFactory.decodeFile(jpeg.getPath(),options()),b=BitmapFactory.decodeFile(reference.getPath(),options());try{check("pre-encoder-canvas-equal",a.getWidth()==b.getWidth()&&a.getHeight()==b.getHeight());long error=0;int changed=0;for(int y=3;y<a.getHeight();y+=7)for(int x=3;x<a.getWidth();x+=7){int av=a.getPixel(x,y),bv=b.getPixel(x,y);if(av!=bv)changed++;for(int shift:new int[]{0,8,16})error+=Math.abs((av>>shift&255)-(bv>>shift&255));}check("preview-is-lossy-JPEG-not-lossless-reference",changed>100);measurements.put(new JSONObject().put("case","compression-difference").put("changedSamples",changed).put("absoluteChannelError",error).put("jpegBytes",jpeg.length()).put("referenceBytes",reference.length()));}finally{if(a!=null)a.recycle();if(b!=null)b.recycle();}}
    private void pixelProof(String label)throws Exception{Object frame=get(canvas,"frame");int mode=integer(frame,"mode");File[] files=(File[])get(source,"surfaceFiles");Bitmap full=BitmapFactory.decodeFile(files[mode].getPath(),options());int compared=0,errors=0;try{check(label+"-sample1",integer(frame,"sample")==1);for(Object tile:(List<?>)get(frame,"tiles")){Rect bounds=(Rect)get(tile,"bounds");Bitmap pixels=(Bitmap)get(tile,"bitmap");for(int y=0;y<pixels.getHeight();y+=17)for(int x=0;x<pixels.getWidth();x+=17){compared++;if(pixels.getPixel(x,y)!=full.getPixel(bounds.left+x,bounds.top+y))errors++;}}check(label+"-pixels-equal-actual-decoded-file",compared>0&&errors==0);measurements.put(new JSONObject().put("case",label).put("pixelsCompared",compared).put("pixelErrors",errors));}finally{if(full!=null)full.recycle();}}
    private File fixture()throws Exception{Bitmap bitmap=Bitmap.createBitmap(1400,1000,Bitmap.Config.ARGB_8888);try{int[] row=new int[1400];for(int y=0;y<1000;y++){for(int x=0;x<row.length;x++){int n=(x*1103515245+y*12345)>>>20;row[x]=Color.rgb((x*3+n)&255,(y*5+n*3)&255,(x+y+n*7)&255);}bitmap.setPixels(row,0,1400,0,y,1400,1);}File file=new File(work,"original.jpg");try(FileOutputStream out=new FileOutputStream(file)){check("fixture-JPEG",bitmap.compress(Bitmap.CompressFormat.JPEG,100,out));}return file;}finally{bitmap.recycle();}}
    private void capture(String name)throws Exception{if(output==null)return;awaitCommittedFrame(name);Bitmap screen=getUiAutomation().takeScreenshot();if(screen==null)throw new IOException("screenshot-null");try(FileOutputStream out=new FileOutputStream(new File(output,name+".png"))){screen.compress(Bitmap.CompressFormat.PNG,100,out);}finally{screen.recycle();}screenshots.put(name+".png");}
    private void awaitCommittedFrame(String name)throws Exception{
        View[] target={null};ui(()->{if(dialog instanceof Dialog&&((Dialog)dialog).isShowing())target[0]=((Dialog)dialog).getWindow().getDecorView();else if(activity!=null)target[0]=activity.getWindow().getDecorView();});
        if(target[0]==null)return;
        CountDownLatch committed=new CountDownLatch(1);Runnable[] hardwareCallback={null};ViewTreeObserver.OnDrawListener[] fallback={null};
        ui(()->{View view=target[0];if(!view.isAttachedToWindow())throw new AssertionError("screenshot-target-detached-"+name);
            if(Build.VERSION.SDK_INT>=29&&view.isHardwareAccelerated()){
                hardwareCallback[0]=committed::countDown;view.getViewTreeObserver().registerFrameCommitCallback(hardwareCallback[0]);view.invalidate();
            }else{
                fallback[0]=new ViewTreeObserver.OnDrawListener(){boolean observed;public void onDraw(){if(observed)return;observed=true;view.post(()->{if(view.getViewTreeObserver().isAlive())view.getViewTreeObserver().removeOnDrawListener(this);view.postOnAnimation(committed::countDown);});}};
                view.getViewTreeObserver().addOnDrawListener(fallback[0]);view.invalidate();
            }
        });
        boolean complete=committed.await(10,TimeUnit.SECONDS);
        if(!complete)ui(()->{ViewTreeObserver observer=target[0].getViewTreeObserver();if(!observer.isAlive())return;if(Build.VERSION.SDK_INT>=29&&hardwareCallback[0]!=null)observer.unregisterFrameCommitCallback(hardwareCallback[0]);if(fallback[0]!=null)observer.removeOnDrawListener(fallback[0]);});
        check("actual-frame-committed-"+name,complete);
    }
    private boolean cleanFixtures(){if(work==null)return true;boolean ok=true;File[] files=work.listFiles();if(files!=null)for(File file:files)ok&=file.isFile()&&file.delete();return work.delete()&&ok;}
    private void touch(View view,long start,int action,float x,float y){MotionEvent e=MotionEvent.obtain(start,SystemClock.uptimeMillis(),action,x,y,0);try{view.dispatchTouchEvent(e);}finally{e.recycle();}}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private void ui(Work work){Throwable[] error={null};runOnMainSync(()->{try{work.run();}catch(Throwable e){error[0]=e;}});if(error[0]!=null)throw new RuntimeException(error[0]);}
    private void until(Condition condition,String name)throws Exception{long end=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<end){boolean[] ready={false};ui(()->ready[0]=condition.test());if(ready[0]){check(name,true);return;}SystemClock.sleep(25);}check(name,false);}
    private void check(String name,boolean value){try{checks.put(new JSONObject().put("name",name).put("passed",value));}catch(JSONException e){throw new RuntimeException(e);}if(!value)throw new AssertionError(name);}
    private Class<?> type(String suffix)throws Exception{return Class.forName("cc.huevia."+suffix,true,loader);}
    private static Object get(Object value,String name)throws Exception{Field f=value.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(value);}
    private static Object call(Object value,String name,Class<?>[] types,Object...args)throws Exception{return value.getClass().getMethod(name,types).invoke(value,args);}
    private static Object callPrivate(Object value,String name,Class<?>[] types,Object...args)throws Exception{Method m=value.getClass().getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(value,args);}
    private static int integer(Object value,String name)throws Exception{return (Integer)get(value,name);}
    private static Throwable unwrap(Throwable e){return e instanceof InvocationTargetException&&e.getCause()!=null?e.getCause():e;}
    private static BitmapFactory.Options options(){BitmapFactory.Options o=new BitmapFactory.Options();o.inScaled=false;o.inPreferredConfig=Bitmap.Config.ARGB_8888;o.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);return o;}
    private static String sha(File file)throws Exception{MessageDigest digest=MessageDigest.getInstance("SHA-256");try(InputStream in=Files.newInputStream(file.toPath())){byte[] buffer=new byte[65536];int n;while((n=in.read(buffer))!=-1)digest.update(buffer,0,n);}StringBuilder hex=new StringBuilder();for(byte b:digest.digest())hex.append(String.format(Locale.ROOT,"%02x",b&255));return hex.toString();}
}
