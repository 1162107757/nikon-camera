package cc.huevia.imageperformanceqa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.graphics.drawable.Drawable;
import android.media.ExifInterface;
import android.os.*;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;
import org.json.*;

/** One identical reflection-only probe for frozen 107 and candidate 108; no production test API. */
public final class ImagePerformanceProbe extends Instrumentation {
    private Bundle args;private Activity activity;private Context context;private ClassLoader loader;
    private File work,output,photo;private String photoSha,stage="start";private boolean baseline,cleaned;
    private Object dialog,detail,source;private Throwable failure;
    private final AtomicBoolean ownerValid=new AtomicBoolean(true);
    private final JSONArray checks=new JSONArray(),measurements=new JSONArray(),screenshots=new JSONArray();
    @Override public void onCreate(Bundle value){super.onCreate(value);args=value==null?new Bundle():value;start();}
    @Override public void onStart(){try{
        context=getTargetContext();loader=context.getClassLoader();baseline=args.getString("baseline","false").equals("true");
        check("emulator-only",Build.HARDWARE.matches("ranchu|goldfish"));
        check("exact-installed-apk",sha(new File(context.getApplicationInfo().sourceDir)).equals(args.getString("apkSha256")));
        String run=args.getString("runId","");check("safe-run-id",run.matches("[a-f0-9]{32}"));
        output=new File(context.getExternalFilesDir(null),"image-performance-108/"+run);check("new-evidence-directory",output.mkdirs());
        work=new File(context.getCacheDir(),"image-performance-qa-"+run);check("new-fixture-directory",work.mkdirs());
        stage="fixtures-and-decode";
        photo=fixture("source-12mp.jpg",4000,3000);photoSha=sha(photo);
        decodeProof(photo,4000,3000,1);decodeProof(photo,4000,3000,6);decodeProof(photo,4000,3000,7);
        File large=fixture("source-24mp.jpg",6000,4000);String largeSha=sha(large);
        decodeProof(large,6000,4000,1);decodeProof(large,6000,4000,6);
        check("24mp-original-bytes-preserved",largeSha.equals(sha(large)));
        activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        until(()->(Boolean)get(activity,"ready"),"main-ready");
        check("normal-font-only",Math.abs(activity.getResources().getConfiguration().fontScale-1f)<.01f);
        stage="detail-dialog";open();until(()->full(),"initial-full-fit");
        check("initial-real-dimensions",integer(get(detail,"viewport"),"imageWidth")==4000&&integer(get(detail,"viewport"),"imageHeight")==3000);
        ui(()->call(detail,"zoom",new Class<?>[]{double.class},1d));until(()->full(),"initial-full-100");
        check("initial-100-sample1",integer(get(detail,"frame"),"sample")==1);
        pixelProof("initial");capture("01-before-pan");
        stage="held-pan";heldPan();until(()->full(),"after-up-full-100");
        check("settled-100-sample1",integer(get(detail,"frame"),"sample")==1);pixelProof("after-pan");capture("02-after-pan");
        stage="mode-and-invalidation";
        ui(()->{call(detail,"mode",new Class<?>[]{int.class},1);check("mode-pending-not-falsely-full",!full());});
        until(()->full()&&integer(get(detail,"frame"),"mode")==1,"before-mode-full");
        pixelProof("before-mode");
        ui(()->{call(detail,"mode",new Class<?>[]{int.class},0);call(detail,"mode",new Class<?>[]{int.class},1);});
        until(()->full()&&integer(get(detail,"frame"),"mode")==1,"latest-mode-wins");
        capture("03-before-mode");
        ownerValid.set(false);until(()->!((Dialog)dialog).isShowing(),"owner-invalidation-dismisses");
        awaitSourceClosed();check("12mp-original-bytes-preserved",photoSha.equals(sha(photo)));
        stage="close-pending";ownerValid.set(true);open();
        ui(()->{call(detail,"zoom",new Class<?>[]{double.class},2d);((Dialog)dialog).dismiss();});
        awaitSourceClosed();ui(()->{});check("closed-view-has-no-frame",get(detail,"frame")==null);
        check("source-bytes-preserved-after-close",photoSha.equals(sha(photo)));
        stage="complete";
    }catch(Throwable e){failure=unwrap(e);try{capture("failure");}catch(Throwable ignored){}}
    finally{
        try{if(dialog!=null)ui(()->((Dialog)dialog).dismiss());if(source!=null)awaitSourceClosed();if(activity!=null)ui(activity::finish);}catch(Throwable e){if(failure==null)failure=unwrap(e);}
        cleaned=cleanFixtures();
        if(!cleaned&&failure==null)failure=new AssertionError("private-fixture-cleanup");
        try{if(output!=null){JSONObject report=new JSONObject().put("pass",failure==null).put("baseline",baseline).put("stage",stage).put("apkSha256",args.getString("apkSha256")).put("checks",checks).put("measurements",measurements).put("screenshots",screenshots).put("fixtureCleanup",cleaned).put("failure",failure==null?JSONObject.NULL:failure.toString()).put("scope","Identical reflection-only probe on actual installed APK; generated 12MP/24MP JPEG, exact legacy decode oracle, native PhotoDetailDialog held pan, real tile pixels, mode and owner/close guards. Normal-font emulator only; timings are observations, not physical-device latency or FPS claims.");if(failure!=null){StringWriter trace=new StringWriter();failure.printStackTrace(new PrintWriter(trace));report.put("stack",trace.toString());}Files.writeString(new File(output,"report.json").toPath(),report.toString(2));}}catch(Throwable e){failure=e;}
        Bundle result=new Bundle();result.putString("stream",failure==null?"Image performance PASS\n":"Image performance FAIL "+stage+" "+failure+"\n");finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
    }}
    private File fixture(String name,int width,int height)throws Exception{
        File file=new File(work,name);long start=System.nanoTime();Bitmap b=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888);int[] row=new int[width];
        try{for(int y=0;y<height;y++){for(int x=0;x<width;x++){int n=(x*73+y*151+(x*y*13))&31;row[x]=0xff000000|(((x/17+n)&255)<<16)|(((y/13+n)&255)<<8)|((x/23+y/19+n)&255);}b.setPixels(row,0,width,0,y,width,1);}try(FileOutputStream out=new FileOutputStream(file)){check("fixture-jpeg-"+name,b.compress(Bitmap.CompressFormat.JPEG,95,out));}}finally{b.recycle();}
        measurements.put(new JSONObject().put("case","fixture-"+name).put("width",width).put("height",height).put("bytes",file.length()).put("elapsedMs",elapsed(start)));return file;
    }
    private void decodeProof(File input,int width,int height,int orientation)throws Exception{
        File target=input;if(orientation!=1){target=new File(work,width+"-orientation-"+orientation+".jpg");Files.copy(input.toPath(),target.toPath());ExifInterface exif=new ExifInterface(target.getPath());exif.setAttribute(ExifInterface.TAG_ORIENTATION,Integer.toString(orientation));exif.saveAttributes();}
        String before=sha(target);Bitmap oracle=null,actual=null;
        try{oracle=legacyDecode(target,1280);long nativeBefore=Debug.getNativeHeapAllocatedSize(),javaBefore=usedJava(),start=System.nanoTime();actual=(Bitmap)type("ui.PhotoFilterEditor").getMethod("decode",File.class,int.class).invoke(null,target,1280);double ms=elapsed(start);
            check("decode-dimensions-"+width+"-"+orientation,actual.getWidth()==oracle.getWidth()&&actual.getHeight()==oracle.getHeight());
            int count=0,errors=0;int[] a=new int[actual.getWidth()],b=new int[a.length];for(int y=0;y<actual.getHeight();y++){actual.getPixels(a,0,a.length,0,y,a.length,1);oracle.getPixels(b,0,b.length,0,y,b.length,1);for(int x=0;x<a.length;x++){count++;if(a[x]!=b[x])errors++;}}
            check("decode-exact-pixels-"+width+"-"+orientation,errors==0);check("decode-keeps-source-"+width+"-"+orientation,before.equals(sha(target)));
            measurements.put(new JSONObject().put("case","decode-"+width+"x"+height+"-exif"+orientation).put("elapsedMs",ms).put("outputWidth",actual.getWidth()).put("outputHeight",actual.getHeight()).put("pixelsCompared",count).put("pixelErrors",errors).put("nativeHeapDeltaBytes",Debug.getNativeHeapAllocatedSize()-nativeBefore).put("javaHeapDeltaBytes",usedJava()-javaBefore));
        }finally{if(oracle!=null)oracle.recycle();if(actual!=null)actual.recycle();}
    }
    /** Frozen 107 decode order and options; promptly release only oracle-owned intermediates. */
    private Bitmap legacyDecode(File file,int edge)throws Exception{
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),bounds);BitmapFactory.Options options=options(1);while(Math.max(bounds.outWidth,bounds.outHeight)/options.inSampleSize>edge*2)options.inSampleSize*=2;
        Bitmap bitmap=BitmapFactory.decodeFile(file.getPath(),options);if(bitmap==null)throw new IOException("oracle-decode-failed");
        try{int orientation=new ExifInterface(file.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);Matrix matrix=new Matrix();switch(orientation){case 2:matrix.setScale(-1,1);break;case 3:matrix.setRotate(180);break;case 4:matrix.setScale(1,-1);break;case 5:matrix.setRotate(90);matrix.postScale(-1,1);break;case 6:matrix.setRotate(90);break;case 7:matrix.setRotate(270);matrix.postScale(-1,1);break;case 8:matrix.setRotate(270);break;}
            if(!matrix.isIdentity()){Bitmap next=Bitmap.createBitmap(bitmap,0,0,bitmap.getWidth(),bitmap.getHeight(),matrix,true);if(next!=bitmap)bitmap.recycle();bitmap=next;}
            float scale=Math.min(1,edge/(float)Math.max(bitmap.getWidth(),bitmap.getHeight()));if(scale<1){Bitmap next=Bitmap.createScaledBitmap(bitmap,Math.max(1,Math.round(bitmap.getWidth()*scale)),Math.max(1,Math.round(bitmap.getHeight()*scale)),true);if(next!=bitmap)bitmap.recycle();bitmap=next;}Bitmap result=bitmap;bitmap=null;return result;
        }finally{if(bitmap!=null)bitmap.recycle();}
    }
    private void open()throws Exception{
        Object profile=type("ncp.AdjustedPreviewProfile").getMethod("of",type("ncp.PresetPreviewProfile"),type("ncp.PhotoAdjustments")).invoke(null,null,type("ncp.PhotoAdjustments").getField("NONE").get(null));
        Object request=type("album.PhotoDetailSource$Request").getConstructor(Context.class,File.class,String.class,String.class,type("ncp.PresetPreviewProfile"),boolean.class,boolean.class,BooleanSupplier.class).newInstance(context,photo,photoSha,"image-performance-"+UUID.randomUUID(),profile,true,true,(BooleanSupplier)ownerValid::get);
        ui(()->{dialog=type("ui.PhotoDetailDialog").getMethod("show",Activity.class,type("album.PhotoDetailSource$Request"),String.class).invoke(null,activity,request,"PERFORMANCE_12MP.JPG");detail=get(dialog,"detail");source=get(dialog,"source");});
    }
    private void heldPan()throws Exception{
        View view=(View)detail;Object[] initialFrame={null};Drawable[] backgrounds=new Drawable[5];String[] keys={"current","before","fit","one","two"};List<Object> glasses=(List<Object>)get(dialog,"glasses");
        Object[] stableGlass={glasses.get(0),glasses.get(glasses.size()-1)};
        List<Set<Object>> bitmapIdentities=new ArrayList<>(),pixelIdentities=new ArrayList<>(),blurIdentities=new ArrayList<>();
        for(int i=0;i<stableGlass.length;i++){bitmapIdentities.add(Collections.newSetFromMap(new IdentityHashMap<>()));pixelIdentities.add(Collections.newSetFromMap(new IdentityHashMap<>()));blurIdentities.add(Collections.newSetFromMap(new IdentityHashMap<>()));}
        ui(()->{initialFrame[0]=get(detail,"frame");for(int i=0;i<keys.length;i++)backgrounds[i]=((View)get(dialog,keys[i])).getBackground();});
        Set<String> seen=new HashSet<>(),newTiles=new HashSet<>();String first=tileSignature(initialFrame[0]);seen.add(first);long[] changed={0};int[] updates={0},staleCertified={0};long start=SystemClock.uptimeMillis();float initialX=view.getWidth()*.75f,y=view.getHeight()*.55f;
        ui(()->touch(view,start,MotionEvent.ACTION_DOWN,initialX,y));
        for(int n=0;n<90;n++){final int step=n;ui(()->{touch(view,start,MotionEvent.ACTION_MOVE,initialX-step*20f,y);Object frame=get(detail,"frame");String signature=tileSignature(frame);if(!signature.equals(first)&&seen.add(signature)){updates[0]++;newTiles.add(signature);changed[0]=SystemClock.uptimeMillis()-start;}if(full()&&integer(frame,"sample")!=1)staleCertified[0]++;for(int i=0;i<stableGlass.length;i++){remember(bitmapIdentities.get(i),optional(stableGlass[i],"backdrop"));remember(bitmapIdentities.get(i),optional(stableGlass[i],"sampleBuffer"));remember(pixelIdentities.get(i),optional(stableGlass[i],"pixelBuffer"));remember(blurIdentities.get(i),optional(stableGlass[i],"blurBuffer"));}});SystemClock.sleep(16);}
        long held=SystemClock.uptimeMillis()-start;int[] stable={0};ui(()->{for(int i=0;i<keys.length;i++)if(backgrounds[i]==((View)get(dialog,keys[i])).getBackground())stable[0]++;});
        check("held-never-certifies-sampled-frame-as-100",staleCertified[0]==0);
        JSONArray glassCounts=new JSONArray();for(int i=0;i<stableGlass.length;i++)glassCounts.put(new JSONObject().put("bitmapIdentities",bitmapIdentities.get(i).size()).put("pixelArrayIdentities",pixelIdentities.get(i).size()).put("blurArrayIdentities",blurIdentities.get(i).size()));
        measurements.put(new JSONObject().put("case","continuous-detail-pan").put("moves",90).put("heldMs",held).put("newTileSetsBeforeUp",updates[0]).put("lastNewTileSetMs",changed[0]).put("stableButtonBackgrounds",stable[0]).put("buttons",5).put("stableSizeGlassBuffers",glassCounts).put("tileSets",new JSONArray(newTiles)));
        if(!baseline){check("multiple-new-tile-sets-before-up",updates[0]>=2);check("stable-selection-backgrounds-during-pan",stable[0]==5);for(int i=0;i<stableGlass.length;i++)check("glass-reuses-same-size-buffers-"+i,bitmapIdentities.get(i).size()>0&&bitmapIdentities.get(i).size()<=2&&pixelIdentities.get(i).size()==1&&blurIdentities.get(i).size()==1);}
        ui(()->touch(view,start,MotionEvent.ACTION_UP,initialX-89*20f,y));
    }
    private void pixelProof(String name)throws Exception{
        Object[] holder={null};ui(()->holder[0]=get(detail,"frame"));Object frame=holder[0];check("pixel-oracle-sample1-"+name,integer(frame,"sample")==1&&!bool(frame,"provisional"));
        Bitmap oracle=BitmapFactory.decodeFile(photo.getPath(),options(1));int count=0,errors=0,displayCount=0,displayErrors=0;Bitmap[] drawn={null};double[] origin=new double[2];RectF[] locator={null};
        try{for(Object tile:(List<?>)get(frame,"tiles")){Rect bounds=(Rect)get(tile,"bounds");Bitmap b=(Bitmap)get(tile,"bitmap");for(int y=0;y<b.getHeight();y+=31)for(int x=0;x<b.getWidth();x+=29){count++;if(b.getPixel(x,y)!=oracle.getPixel(bounds.left+x,bounds.top+y))errors++;}}
            ui(()->{View view=(View)detail;Object viewport=get(detail,"viewport");origin[0]=Math.round((Double)call(viewport,"left",new Class<?>[0]));origin[1]=Math.round((Double)call(viewport,"top",new Class<?>[0]));drawn[0]=Bitmap.createBitmap(view.getWidth(),view.getHeight(),Bitmap.Config.ARGB_8888);view.draw(new Canvas(drawn[0]));locator[0]=(RectF)call(detail,"locatorBounds",new Class<?>[0]);});
            for(int y=13;y<drawn[0].getHeight();y+=37)for(int x=11;x<drawn[0].getWidth();x+=31){int ix=(int)(x-origin[0]),iy=(int)(y-origin[1]);if(ix<0||iy<0||ix>=oracle.getWidth()||iy>=oracle.getHeight()||locator[0].contains(x,y))continue;displayCount++;if(drawn[0].getPixel(x,y)!=oracle.getPixel(ix,iy))displayErrors++;}
        }finally{oracle.recycle();if(drawn[0]!=null)drawn[0].recycle();}
        check("tile-pixels-match-full-JPEG-"+name,count>100&&errors==0);check("physical-view-pixels-match-full-JPEG-"+name,displayCount>100&&displayErrors==0);
        measurements.put(new JSONObject().put("case","pixel-oracle-"+name).put("tilePixels",count).put("tileErrors",errors).put("physicalViewPixels",displayCount).put("physicalViewErrors",displayErrors));
    }
    private String tileSignature(Object frame)throws Exception{if(frame==null)return "none";StringBuilder s=new StringBuilder().append(integer(frame,"mode")).append(':').append(integer(frame,"sample"));for(Object tile:(List<?>)get(frame,"tiles"))s.append(':').append(((Rect)get(tile,"bounds")).toShortString());return s.toString();}
    private boolean full()throws Exception{return (Boolean)call(detail,"hasFullPixels",new Class<?>[0]);}
    private void awaitSourceClosed()throws Exception{if(source==null)return;ThreadPoolExecutor worker=(ThreadPoolExecutor)get(source,"worker");check("source-worker-terminated",worker.awaitTermination(15,TimeUnit.SECONDS));check("source-temporary-directory-removed",!((File)get(source,"directory")).exists());}
    private void capture(String name)throws Exception{if(output==null)return;ui(()->{});Bitmap screen=getUiAutomation().takeScreenshot();if(screen==null)throw new IOException("screenshot-null");try(FileOutputStream out=new FileOutputStream(new File(output,name+".png"))){screen.compress(Bitmap.CompressFormat.PNG,100,out);}finally{screen.recycle();}screenshots.put(name+".png");}
    private boolean cleanFixtures(){if(work==null)return true;boolean ok=true;File[] files=work.listFiles();if(files!=null)for(File f:files)ok&=f.isFile()&&f.delete();return work.delete()&&ok;}
    private void touch(View view,long start,int action,float x,float y){MotionEvent event=MotionEvent.obtain(start,SystemClock.uptimeMillis(),action,x,y,0);try{view.dispatchTouchEvent(event);}finally{event.recycle();}}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private void ui(Work work){Throwable[] error={null};runOnMainSync(()->{try{work.run();}catch(Throwable e){error[0]=e;}});if(error[0]!=null)throw new RuntimeException(error[0]);}
    private void until(Condition condition,String name)throws Exception{long end=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<end){boolean[] ready={false};ui(()->ready[0]=condition.test());if(ready[0]){check(name,true);return;}SystemClock.sleep(25);}check(name,false);}
    private void check(String name,boolean value){JSONObject item=new JSONObject();try{item.put("name",name).put("passed",value);}catch(JSONException e){throw new RuntimeException(e);}checks.put(item);if(!value)throw new AssertionError(name);}
    private Class<?> type(String suffix)throws Exception{return Class.forName("cc.huevia."+suffix,true,loader);}
    private static Object get(Object value,String name)throws Exception{Field f=value.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(value);}
    private static Object optional(Object value,String name)throws Exception{try{return get(value,name);}catch(NoSuchFieldException absent){return null;}}
    private static void remember(Set<Object> set,Object value){if(value!=null)set.add(value);}
    private static Object call(Object value,String name,Class<?>[] types,Object...args)throws Exception{Method m=value.getClass().getMethod(name,types);return m.invoke(value,args);}
    private static int integer(Object value,String name)throws Exception{return (Integer)get(value,name);}private static boolean bool(Object value,String name)throws Exception{return (Boolean)get(value,name);}
    private static Throwable unwrap(Throwable e){return e instanceof InvocationTargetException&&((InvocationTargetException)e).getCause()!=null?((InvocationTargetException)e).getCause():e;}
    private static long usedJava(){Runtime r=Runtime.getRuntime();return r.totalMemory()-r.freeMemory();}private static double elapsed(long start){return(System.nanoTime()-start)/1_000_000d;}
    private static BitmapFactory.Options options(int sample){BitmapFactory.Options o=new BitmapFactory.Options();o.inPreferredConfig=Bitmap.Config.ARGB_8888;o.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);o.inScaled=false;o.inSampleSize=sample;return o;}
    private static String sha(File file)throws Exception{MessageDigest d=MessageDigest.getInstance("SHA-256");try(InputStream in=Files.newInputStream(file.toPath())){byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1)d.update(b,0,n);}StringBuilder s=new StringBuilder();for(byte b:d.digest())s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();}
}
