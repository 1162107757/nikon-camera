package cc.huevia.album;

import android.content.Context;
import android.media.ExifInterface;
import android.util.AtomicFile;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.function.BooleanSupplier;

/** One dated JPEG per explicit export action; a retry resumes that exact copy. */
public final class SharedGalleryCopies {
    private SharedGalleryCopies() {}
    public static String publish(Context context,File source,String owner,String version,String operation,String filename,String sourceSha,long sourceBytes,BooleanSupplier cancel)throws IOException {
        if(operation==null||!operation.matches("[0-9a-f]{32}")||!version.matches("[0-9a-f]{64}")||!sourceSha.matches("[0-9a-f]{64}")||sourceBytes<4||sourceBytes>512L*1024*1024)throw new IOException("导出任务标识无效。");
        File base=directory(context.getFilesDir().getCanonicalFile(),"shared-gallery-copies"),folder=directory(base,PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8)));
        File recordPath=new File(folder,operation+".json"),frozen=new File(folder,operation+".JPG");
        if(Files.isSymbolicLink(recordPath.toPath())||Files.isSymbolicLink(new File(recordPath+".bak").toPath())||Files.isSymbolicLink(frozen.toPath()))throw new IOException("导出记录不能是链接。");
        AtomicFile file=new AtomicFile(recordPath);Map<String,Object> record=read(file);
        if(record==null){
            check(cancel);if(frozen.exists())throw new IOException("上次暂存未完整记录，请保留应用内成品并重新导出。");
            long now=System.currentTimeMillis();Date date=new Date(now);String clock=new SimpleDateFormat("yyyy:MM:dd HH:mm:ss",Locale.US).format(date),zone=new SimpleDateFormat("XXX",Locale.US).format(date);if(zone.equals("Z"))zone="+00:00";
            record=new LinkedHashMap<>();record.put("schema",1);record.put("state","preparing");record.put("version",version);record.put("sourceSha",sourceSha);record.put("sourceBytes",sourceBytes);
            record.put("clock",clock);record.put("zone",zone);record.put("sub",String.format(Locale.US,"%03d",now%1000));record.put("time",now);write(file,record);
        }
        if(number(record,"schema")!=1||!version.equals(record.get("version"))||!sourceSha.equals(record.get("sourceSha"))||number(record,"sourceBytes")!=sourceBytes)throw new IOException("导出记录与此成品不匹配，未重复保存。");
        String state=text(record,"state");
        if(state.equals("complete")){
            String uri=text(record,"uri");SharedGalleryPublication.verify(context,uri,text(record,"sha256"),number(record,"bytes"),cancel);cleanup(frozen,record);return uri;
        }
        if(state.equals("preparing")){
            String clock=text(record,"clock"),zone=text(record,"zone"),sub=text(record,"sub");
            if(!clock.matches("[0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}")||!zone.matches("[+-][0-9]{2}:[0-9]{2}")||!sub.matches("[0-9]{3}"))throw new IOException("导出副本时间记录无效。");
            File temporary=File.createTempFile("dated-",".part",folder);
            try{
                long copied=0;byte[] buffer=new byte[65536];int n;
                try(InputStream in=new FileInputStream(source);FileOutputStream out=new FileOutputStream(temporary)){
                    while((n=in.read(buffer))!=-1){check(cancel);copied+=n;if(copied>sourceBytes)throw new IOException("成品内容已变化。");out.write(buffer,0,n);}out.getFD().sync();
                }
                if(copied!=sourceBytes||!PhotoEditStore.hashFile(temporary).equals(sourceSha))throw new IOException("成品内容已变化，未保存副本。");
                ExifInterface exif=new ExifInterface(temporary.getPath());
                for(String tag:new String[]{"DateTime","DateTimeOriginal","DateTimeDigitized"})exif.setAttribute(tag,clock);
                for(String tag:new String[]{"OffsetTime","OffsetTimeOriginal","OffsetTimeDigitized"})exif.setAttribute(tag,zone);
                for(String tag:new String[]{"SubSecTime","SubSecTimeOriginal","SubSecTimeDigitized"})exif.setAttribute(tag,sub);
                exif.saveAttributes();PhotoPreviewCache.validateJpeg(temporary,temporary.length());String sha=PhotoEditStore.hashFile(temporary);long bytes=temporary.length();
                if(bytes<4||bytes>512L*1024*1024)throw new IOException("导出副本大小无效。");
                if(frozen.exists()){
                    if(frozen.length()!=bytes||!PhotoEditStore.hashFile(frozen).equals(sha))throw new IOException("暂存副本已变化，未覆盖或删除。");
                }else Files.move(temporary.toPath(),frozen.toPath(),StandardCopyOption.ATOMIC_MOVE);
                record.put("sha256",sha);record.put("bytes",bytes);record.put("state","pending");write(file,record);
            }finally{Files.deleteIfExists(temporary.toPath());}
        }else if(!state.equals("pending"))throw new IOException("导出任务状态无效。");
        String sha=text(record,"sha256");long bytes=number(record,"bytes");
        if(!frozen.isFile()||frozen.length()!=bytes||!PhotoEditStore.hashFile(frozen).equals(sha))throw new IOException("上次导出副本不完整，请保留应用内成品并检查存储空间。");
        check(cancel);String identity=PhotoEditStore.hash((version+"\n"+operation).getBytes(StandardCharsets.UTF_8));
        String uri=SharedGalleryPublication.publish(context,frozen,owner,identity,filename,sha,bytes,false,cancel);
        record.put("state","complete");record.put("uri",uri);write(file,record);cleanup(frozen,record);check(cancel);return uri;
    }
    private static File directory(File parent,String name)throws IOException {
        File path=new File(parent,name);if(Files.isSymbolicLink(path.toPath())||(!path.isDirectory()&&!path.mkdirs())||!parent.getCanonicalFile().equals(path.getCanonicalFile().getParentFile()))throw new IOException("导出记录目录无效。");return path.getCanonicalFile();
    }
    private static Map<String,Object> read(AtomicFile file)throws IOException {
        if(!file.getBaseFile().exists()&&!new File(file.getBaseFile()+".bak").exists())return null;
        try(InputStream in=file.openRead();ByteArrayOutputStream out=new ByteArrayOutputStream()){
            byte[] buffer=new byte[1024];int n;while((n=in.read(buffer))!=-1){if(out.size()+n>8192)throw new IOException("导出记录超出范围。");out.write(buffer,0,n);}return SharedJson.object(new String(out.toByteArray(),StandardCharsets.UTF_8));
        }
    }
    private static void write(AtomicFile file,Map<String,Object> value)throws IOException {
        FileOutputStream out=null;try{out=file.startWrite();out.write(SharedJson.encode(value).getBytes(StandardCharsets.UTF_8));file.finishWrite(out);}catch(IOException|RuntimeException failure){if(out!=null)file.failWrite(out);throw failure;}
    }
    private static String text(Map<String,Object> p,String key)throws IOException {Object value=p.get(key);if(!(value instanceof String)||((String)value).length()>1024)throw new IOException("导出记录文字无效。");return (String)value;}
    private static long number(Map<String,Object> p,String key)throws IOException {Object value=p.get(key);if(!(value instanceof Number)||((Number)value).doubleValue()!=((Number)value).longValue())throw new IOException("导出记录数字无效。");return ((Number)value).longValue();}
    private static void cleanup(File file,Map<String,Object> record)throws IOException {
        if(file.exists()&&!Files.isSymbolicLink(file.toPath())&&file.length()==number(record,"bytes")&&PhotoEditStore.hashFile(file).equals(text(record,"sha256")))Files.deleteIfExists(file.toPath());
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException {if(Thread.currentThread().isInterrupted()||cancel.getAsBoolean())throw new InterruptedIOException("保存副本已取消，应用内成品仍然保留。");}
}
