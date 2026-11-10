package cc.huevia.rawdevelopmentqa;
import android.content.Context;
import android.graphics.BitmapFactory;
import android.media.ExifInterface;
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.function.BooleanSupplier;
import org.json.*;

/** A full-size licensed Nikon sample through the new production editor bridge, no public export. */
public final class RealRawEditorChecks {
    public static void run(Context context,File source,String owner,JSONArray checks,JSONArray measurements)throws Exception{
        if(!source.isFile())throw new IOException("Real NEF sample required");
        ClassLoader loader=context.getClassLoader();Class<?> bridge=Class.forName("cc.huevia.album.RawEditorSource",true,loader);
        String original=sha(source),name="QA179-"+UUID.randomUUID()+".NEF";
        File pictures=new File(context.getFilesDir(),"pictures/camera-album"),retained=new File(context.getFilesDir(),"raw-editor-sources/"+original+".nef");
        Set<String> before=new HashSet<>();File[] existing=pictures.listFiles();if(existing!=null)for(File file:existing)before.add(file.getName());boolean retainedBefore=retained.exists();File working=null,receipt=null;
        long start=android.os.SystemClock.elapsedRealtime();
        try{
            Object photo=bridge.getMethod("prepare",Context.class,File.class,String.class,String.class,long.class,BooleanSupplier.class).invoke(null,context,source,name,owner,0L,(BooleanSupplier)()->false);
            working=(File)photo.getClass().getMethod("file").invoke(photo);String key=working.getName().substring(0,working.getName().indexOf("__"));receipt=new File(pictures,key+".raw-editor");
            BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(working.getPath(),bounds);
            check(checks,"real-NEF-bridge-full-6064x4040-JPEG",bounds.outWidth==6064&&bounds.outHeight==4040&&"image/jpeg".equals(bounds.outMimeType));
            Class<?> labels=Class.forName("cc.huevia.album.PhotoSourceFormat",true,loader);check(checks,"real-NEF-source-label-survives",labels.getMethod("label",photo.getClass()).invoke(null,photo).equals("NEF"));
            ExifInterface input=new ExifInterface(source.getPath()),output=new ExifInterface(working.getPath());int metadata=0;
            for(String tag:new String[]{"DateTimeOriginal","ExposureTime","FNumber","ISOSpeedRatings","FocalLength"})if(input.getAttribute(tag)!=null){metadata++;check(checks,"real-NEF-shooting-caption-"+tag,Objects.equals(input.getAttribute(tag),output.getAttribute(tag)));}
            check(checks,"real-NEF-has-shooting-captions",metadata>=3);
            check(checks,"real-NEF-bridge-retains-original-bytes",original.equals(sha(source))&&original.equals(sha(retained)));
            measurements.put(new JSONObject().put("case","real-nef-editor-bridge").put("width",bounds.outWidth).put("height",bounds.outHeight).put("bytes",working.length()).put("sourceSha256",original).put("elapsedMs",android.os.SystemClock.elapsedRealtime()-start).put("shootingMetadataFields",metadata));
        }finally{
            for(File file:new File[]{working,receipt})if(file!=null&&!before.contains(file.getName()))Files.deleteIfExists(file.toPath());
            if(!retainedBefore)Files.deleteIfExists(retained.toPath());
        }
    }
    private static void check(JSONArray checks,String name,boolean pass)throws Exception{checks.put(new JSONObject().put("name",name).put("passed",pass));if(!pass)throw new AssertionError(name);}
    private static String sha(File file)throws Exception{MessageDigest hash=MessageDigest.getInstance("SHA-256");byte[] buffer=new byte[65536];try(InputStream input=new FileInputStream(file)){int n;while((n=input.read(buffer))!=-1)hash.update(buffer,0,n);}StringBuilder result=new StringBuilder();for(byte b:hash.digest())result.append(String.format(Locale.ROOT,"%02x",b&255));return result.toString();}
}
