package cc.huevia.rawdevelopmentqa;
import android.content.Context;
import android.graphics.*;
import android.os.SystemClock;
import java.io.*;
import java.lang.reflect.*;
import java.nio.*;
import java.nio.file.Files;
import java.security.*;
import java.util.*;
import java.util.function.*;
import org.json.*;

/** Stage timings on the exact installed decoder and a fixed real NEF; no quality shortcuts. */
public final class RawPerformanceChecks {
    public static void run(Context c,File source,String owner,JSONArray checks,JSONArray measurements)throws Exception{
        ClassLoader loader=c.getClassLoader();Class<?> developer=Class.forName("cc.huevia.album.RawDeveloper",true,loader),settings=Class.forName("cc.huevia.ncp.RawDevelopmentSettings",true,loader);
        Object defaults=settings.getField("DEFAULT").get(null);String sourceHash=hash(source);Set<String> before=new HashSet<>();File pictures=new File(c.getFilesDir(),"pictures/camera-album");File[] initial=pictures.listFiles();if(initial!=null)for(File f:initial)before.add(f.getName());
        File retained=new File(c.getFilesDir(),"raw-editor-sources/"+sourceHash+".nef");boolean retainedBefore=retained.exists();File jpeg=null,receipt=null;
        try{
            for(String scene:new String[]{"cold","warm","exposure"}){
                Object config=scene.equals("exposure")?settings.getMethod("withExposure",int.class).invoke(defaults,5):defaults;
                long start=SystemClock.elapsedRealtimeNanos();long[] pixelDone={0},encoded={0};double[] previous={0};boolean[] monotonic={true};int[] events={0};Set<Integer> saveProgress=new TreeSet<>();
                DoubleConsumer progress=v->{if(v<previous[0])monotonic[0]=false;previous[0]=v;events[0]++;if(v>=.95&&v<1)saveProgress.add((int)(v*100));if(v>=.95&&pixelDone[0]==0)pixelDone[0]=SystemClock.elapsedRealtimeNanos();if(v>=.995&&encoded[0]==0)encoded[0]=SystemClock.elapsedRealtimeNanos();};
                Object result=developer.getMethod("develop",Context.class,File.class,String.class,settings,BooleanSupplier.class,DoubleConsumer.class).invoke(null,c,source,owner,config,(BooleanSupplier)()->false,progress);
                long end=SystemClock.elapsedRealtimeNanos();File png=(File)get(result,"workingFile");String pixels=rasterHash(png);
                check(checks,"performance-progress-monotonic-"+scene,monotonic[0]&&previous[0]==1);
                check(checks,"performance-cache-state-"+scene,(Boolean)get(result,"cached")==scene.equals("warm"));
                measurements.put(new JSONObject().put("case","raw-speed-"+scene).put("totalMs",(end-start)/1e6).put("pixelsMs",pixelDone[0]==0?0:(pixelDone[0]-start)/1e6)
                        .put("writeAndVerifyMs",pixelDone[0]==0?0:(end-pixelDone[0])/1e6).put("progressEvents",events[0]).put("savePercentValues",new JSONArray(saveProgress)).put("rasterSha256",pixels).put("fileBytes",png.length()));
            }
            Class<?> bridge=Class.forName("cc.huevia.album.RawEditorSource",true,loader);String name="QA180-"+UUID.randomUUID()+".NEF";
            for(int i=0;i<2;i++){
                long start=SystemClock.elapsedRealtimeNanos();Object photo=bridge.getMethod("prepare",Context.class,File.class,String.class,String.class,long.class,BooleanSupplier.class).invoke(null,c,source,name,owner+"-editor",0L,(BooleanSupplier)()->false);
                long end=SystemClock.elapsedRealtimeNanos();jpeg=(File)photo.getClass().getMethod("file").invoke(photo);String key=jpeg.getName().substring(0,jpeg.getName().indexOf("__"));receipt=new File(pictures,key+".raw-editor");
                BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(jpeg.getPath(),bounds);check(checks,"performance-editor-full-size-"+i,bounds.outWidth==6064&&bounds.outHeight==4040);
                measurements.put(new JSONObject().put("case",i==0?"raw-editor-cold":"raw-editor-warm").put("totalMs",(end-start)/1e6).put("fileSha256",hash(jpeg)).put("bytes",jpeg.length()));
            }
            check(checks,"performance-source-unchanged",sourceHash.equals(hash(source)));
            try{Class.forName("cc.huevia.album.RawPngWriter",true,loader);RawPngWriterChecks.run(c,checks);}catch(ClassNotFoundException baseline){/* Previous APK has no fast writer. */}
        }finally{
            for(File f:new File[]{jpeg,receipt})if(f!=null&&!before.contains(f.getName()))Files.deleteIfExists(f.toPath());if(!retainedBefore)Files.deleteIfExists(retained.toPath());
            File own=new File(c.getFilesDir(),"raw-development/"+hex(MessageDigest.getInstance("SHA-256").digest((owner+"-editor").getBytes(java.nio.charset.StandardCharsets.UTF_8))));remove(own,own);
        }
    }
    private static Object get(Object o,String name)throws Exception{Field f=o.getClass().getField(name);return f.get(o);}
    private static void check(JSONArray a,String name,boolean pass)throws Exception{a.put(new JSONObject().put("name",name).put("passed",pass));if(!pass)throw new AssertionError(name);}
    private static String rasterHash(File file)throws Exception{Bitmap bitmap=BitmapFactory.decodeFile(file.getPath());if(bitmap==null)throw new IOException("Missing raster");try{MessageDigest digest=MessageDigest.getInstance("SHA-256");int width=bitmap.getWidth();int[] pixels=new int[width*32];ByteBuffer buffer=ByteBuffer.allocate(width*32*4);for(int y=0;y<bitmap.getHeight();y+=32){int rows=Math.min(32,bitmap.getHeight()-y);bitmap.getPixels(pixels,0,width,0,y,width,rows);buffer.clear();for(int i=0;i<width*rows;i++)buffer.putInt(pixels[i]);digest.update(buffer.array(),0,width*rows*4);}return hex(digest.digest());}finally{bitmap.recycle();}}
    private static String hash(File f)throws Exception{MessageDigest d=MessageDigest.getInstance("SHA-256");try(InputStream in=new FileInputStream(f)){byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1)d.update(b,0,n);}return hex(d.digest());}
    private static String hex(byte[] bytes){StringBuilder s=new StringBuilder();for(byte b:bytes)s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();}
    private static void remove(File f,File own)throws IOException{if(!f.exists())return;if(!f.getCanonicalPath().startsWith(own.getCanonicalPath()))throw new IOException("Unsafe cleanup");if(f.isDirectory()){File[] children=f.listFiles();if(children!=null)for(File child:children)remove(child,own);}Files.delete(f.toPath());}
}
