package cc.huevia.album;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.media.ExifInterface;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.ParcelFileDescriptor;
import android.provider.MediaStore;
import android.util.AtomicFile;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.channels.Channels;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;

/** One dated JPEG per explicit export action; a retry resumes that exact copy. */
public final class SharedGalleryCopies {
    private SharedGalleryCopies() {}
    public static final class Copy {
        public final String uri,filename;
        Copy(String uri,String filename){this.uri=uri;this.filename=filename;}
    }

    public static synchronized Copy publish(Context context,File source,String owner,String version,String operation,String filename,String sourceSha,long sourceBytes,boolean ordered,String album,BooleanSupplier cancel)throws IOException {
        return publish(context,source,owner,version,operation,filename,sourceSha,sourceBytes,ordered,album,"",cancel);
    }

    public static synchronized Copy publishOriginal(Context context,File source,String owner,String version,String operation,String filename,String sourceSha,long sourceBytes,boolean raw,BooleanSupplier cancel)throws IOException {
        return publishOriginal(context,source,owner,version,operation,filename,sourceSha,sourceBytes,raw,null,cancel);
    }

    public static synchronized Copy publishOriginal(Context context,File source,String owner,String version,String operation,String filename,String sourceSha,long sourceBytes,boolean raw,String album,BooleanSupplier cancel)throws IOException {
        return publish(context,source,owner,version,operation,filename,sourceSha,sourceBytes,true,album,raw?"NEF":"JPEG",cancel);
    }

    private static Copy publish(Context context,File source,String owner,String version,String operation,String filename,String sourceSha,long sourceBytes,boolean ordered,String album,String originalFormat,BooleanSupplier cancel)throws IOException {
        if(album!=null&&(Build.VERSION.SDK_INT<29||!PhotoLiveGallery.isExportAlbum(album)))throw new IOException("手机相册位置无效，请重新选择。");
        if(operation==null||!operation.matches("[0-9a-f]{32}")||!version.matches("[0-9a-f]{64}")||!sourceSha.matches("[0-9a-f]{64}")||sourceBytes<4||sourceBytes>512L*1024*1024)throw new IOException("导出任务标识无效。");
        File base=directory(context.getFilesDir().getCanonicalFile(),"shared-gallery-copies"),folder=directory(base,PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8)));
        File recordPath=new File(folder,operation+".json"),frozen=new File(folder,operation+".JPG");
        if(Files.isSymbolicLink(recordPath.toPath())||Files.isSymbolicLink(new File(recordPath+".bak").toPath())||Files.isSymbolicLink(frozen.toPath()))throw new IOException("导出记录不能是链接。");
        AtomicFile file=new AtomicFile(recordPath);Map<String,Object> record=read(file);
        if(record!=null&&!record.containsKey("numberedStem"))ordered=false;
        boolean raw=originalFormat.equals("NEF");
        String stem=ordered?numberedStem(filename):null;
        if(record==null){
            check(cancel);if(frozen.exists())throw new IOException("上次暂存未完整记录，请保留应用内成品并重新导出。");
            long now=System.currentTimeMillis();Date date=new Date(now);String clock=new SimpleDateFormat("yyyy:MM:dd HH:mm:ss",Locale.US).format(date),zone=new SimpleDateFormat("XXX",Locale.US).format(date);if(zone.equals("Z"))zone="+00:00";
            record=new LinkedHashMap<>();record.put("schema",1);record.put("state","preparing");record.put("version",version);record.put("sourceSha",sourceSha);record.put("sourceBytes",sourceBytes);
            if(ordered)record.put("numberedStem",stem);
            if(album!=null)record.put("albumPath",album);
            if(!originalFormat.isEmpty())record.put("originalFormat",originalFormat);
            record.put("clock",clock);record.put("zone",zone);record.put("sub",String.format(Locale.US,"%03d",now%1000));record.put("time",now);write(file,record);
        }
        if(number(record,"schema")!=1||!version.equals(record.get("version"))||!sourceSha.equals(record.get("sourceSha"))||number(record,"sourceBytes")!=sourceBytes)throw new IOException("导出记录与此成品不匹配，未重复保存。");
        if(!Objects.equals(stem,record.get("numberedStem")))throw new IOException("此导出任务的文件命名已确定，请按原设置重试。");
        if(!Objects.equals(album,record.get("albumPath")))throw new IOException("此导出任务的手机相册已确定，请按原设置重试。");
        if(!originalFormat.equals(record.getOrDefault("originalFormat","")))throw new IOException("此导出任务的原始文件格式已确定。");
        String state=text(record,"state");
        if(state.equals("complete")){
            String uri=text(record,"uri");SharedGalleryPublication.verify(context,uri,text(record,"sha256"),number(record,"bytes"),cancel);
            verifyAlbum(context,uri,album);cleanup(frozen,record);
            return new Copy(uri,ordered?text(record,"filename"):null);
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
                if(originalFormat.isEmpty()) {
                    ExifInterface exif=new ExifInterface(temporary.getPath());
                    float[] coordinates=new float[2];
                    boolean withLocation=exif.getLatLong(coordinates);
                    for(String tag:new String[]{"DateTime","DateTimeOriginal","DateTimeDigitized"})exif.setAttribute(tag,clock);
                    for(String tag:new String[]{"OffsetTime","OffsetTimeOriginal","OffsetTimeDigitized"})exif.setAttribute(tag,zone);
                    for(String tag:new String[]{"SubSecTime","SubSecTimeOriginal","SubSecTimeDigitized"})exif.setAttribute(tag,sub);
                    exif.saveAttributes();
                    if(withLocation){
                        float[] written=new float[2];
                        if(!new ExifInterface(temporary.getPath()).getLatLong(written)||!Arrays.equals(coordinates,written))
                            throw new IOException("相册副本的位置未能通过校验，应用内照片仍保留。");
                    }
                }
                if(raw)PhotoFormat.validateNef(temporary,temporary.length());
                else PhotoPreviewCache.validateJpeg(temporary,temporary.length());
                String sha=PhotoEditStore.hashFile(temporary);long bytes=temporary.length();
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
        String uri;
        if(ordered&&Build.VERSION.SDK_INT<29){
            uri=publishLegacyNumbered(context,frozen,stem,sha,bytes,file,record,raw,cancel);
        }else if(ordered&&(!record.containsKey("uri")||Boolean.TRUE.equals(record.get("directNumbered")))){
            uri=publishNumbered(context,frozen,stem,sha,bytes,file,record,album,raw,cancel);
        }else{
            uri=record.containsKey("uri")?text(record,"uri"):album==null
                    ?SharedGalleryPublication.publish(context,frozen,owner,identity,filename,sha,bytes,false,cancel)
                    :SharedGalleryPublication.publishAlbum(context,frozen,owner,identity,filename,sha,bytes,album,cancel);
            verifyAlbum(context,uri,album);
            if(ordered){
                record.put("uri",uri);write(file,record);
                renameNumbered(context,uri,stem,sha,bytes,file,record,album,cancel);
            }
        }
        record.put("state","complete");record.put("uri",uri);write(file,record);cleanup(frozen,record);check(cancel);
        return new Copy(uri,ordered?text(record,"filename"):null);
    }

    private static String numberedStem(String filename){
        String stem=filename.replaceAll("(?i)\\.(jpe?g|nef)$","").replaceAll("[\\p{Cntrl}\\\\/:*?\"<>|]","_").trim().replaceAll("^[.]+|[. ]+$","");
        if(stem.isEmpty())stem="照片";
        while(stem.getBytes(StandardCharsets.UTF_8).length>160)stem=stem.substring(0,stem.offsetByCodePoints(stem.length(),-1));
        return stem;
    }

    private static String numberedName(String stem,int number){return stem+String.format(Locale.ROOT,"_%03d.jpg",number);}

    private static String numberedName(String stem,int number,boolean raw){
        return raw?stem+String.format(Locale.ROOT,"_%03d.NEF",number):numberedName(stem,number);
    }

    private static String publishNumbered(Context context,File frozen,String stem,String sha,long bytes,AtomicFile file,Map<String,Object> record,String album,boolean raw,BooleanSupplier cancel)throws IOException {
        String path=album!=null?album:raw?"Pictures/Huevia/RAW/":"Pictures/相机预设/";
        String display=MediaStore.Images.Media.DISPLAY_NAME,relative=MediaStore.Images.Media.RELATIVE_PATH;
        String pending=MediaStore.Images.Media.IS_PENDING,owner=MediaStore.Images.Media.OWNER_PACKAGE_NAME;
        ContentResolver resolver=context.getContentResolver();
        Uri collection=MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);
        Uri target=record.containsKey("uri")?Uri.parse(text(record,"uri")):null;
        if(target==null){
            for(int number=1;number<=999999;number++){
                check(cancel);
                String name=numberedName(stem,number,raw);
                String pattern=name.replace("!","!!").replace("_","!_").replace("%","!%");
                try(Cursor rows=resolver.query(collection,new String[]{MediaStore.Images.Media._ID},relative+"=? AND "+display+" LIKE ? ESCAPE '!'",new String[]{path,pattern},null)){
                    if(rows==null)throw new IOException("无法核对相册中的同名文件。");
                    if(rows.moveToFirst())continue;
                }
                ContentValues values=new ContentValues();
                values.put(display,name);values.put(relative,path);values.put(pending,1);
                values.put(MediaStore.Images.Media.MIME_TYPE,raw?"image/x-nikon-nef":"image/jpeg");
                target=resolver.insert(collection,values);
                if(target==null)throw new IOException("无法创建相册照片。");
                try(Cursor row=resolver.query(target,new String[]{display},null,null,null)){
                    if(row==null||!row.moveToFirst())throw new IOException("无法核对相册文件名称。");
                    if(!name.equals(row.getString(0))){resolver.delete(target,null,null);target=null;continue;}
                }
                record.put("filename",name);record.put("uri",target.toString());record.put("directNumbered",true);
                write(file,record);
                break;
            }
        }
        if(target==null)throw new IOException("同名导出文件过多，请选择其他照片或文件夹。");
        boolean needsCopy;
        try(Cursor row=resolver.query(target,new String[]{display,relative,owner,pending},null,null,null)){
            if(row==null||!row.moveToFirst()||!text(record,"filename").equals(row.getString(0))||!path.equals(row.getString(1))||!context.getPackageName().equals(row.getString(2)))
                throw new IOException("上次相册保存位置或文件名已变化。");
            needsCopy=row.getInt(3)==1;
        }
        if(needsCopy){
            ParcelFileDescriptor descriptor=resolver.openFileDescriptor(target,"rwt");
            if(descriptor==null)throw new IOException("无法写入相册照片。");
            try(FileOutputStream out=new ParcelFileDescriptor.AutoCloseOutputStream(descriptor);InputStream input=new FileInputStream(frozen)){
                    byte[] buffer=new byte[65536];long count=0;int length;
                    while((length=input.read(buffer))!=-1){check(cancel);count+=length;if(count>bytes)throw new IOException("成品内容已变化。");out.write(buffer,0,length);}
                    if(count!=bytes)throw new IOException("成品内容不完整。");out.getFD().sync();
            }
            SharedGalleryPublication.verifyPending(context,target.toString(),sha,bytes,cancel);
            ContentValues completed=new ContentValues();completed.put(pending,0);
            if(resolver.update(target,completed,null,null)!=1)throw new IOException("系统尚未确认保存到相册。");
        }
        SharedGalleryPublication.verify(context,target.toString(),sha,bytes,cancel);
        return target.toString();
    }

    private static void verifyAlbum(Context context,String uri,String album)throws IOException {
        if(album==null)return;
        try(Cursor row=context.getContentResolver().query(Uri.parse(uri),new String[]{MediaStore.Images.Media.RELATIVE_PATH},null,null,null)){
            if(row==null||!row.moveToFirst()||!album.equals(row.getString(0)))throw new IOException("系统尚未确认保存到所选手机相册。");
        }
    }

    private static void renameNumbered(Context context,String uri,String stem,String sha,long bytes,AtomicFile file,Map<String,Object> record,String album,BooleanSupplier cancel)throws IOException {
        SharedGalleryPublication.verify(context,uri,sha,bytes,cancel);
        ContentResolver resolver=context.getContentResolver();Uri target=Uri.parse(uri);
        String displayName=MediaStore.Images.Media.DISPLAY_NAME,relativePath=MediaStore.Images.Media.RELATIVE_PATH;
        String path;
        try(Cursor row=resolver.query(target,new String[]{displayName,relativePath},null,null,null)){
            if(row==null||!row.moveToFirst())throw new IOException("无法核对相册文件名称。");
            if(record.containsKey("filename")&&Objects.equals(row.getString(0),record.get("filename")))return;
            path=row.getString(1);
        }
        if(!(album==null?"Pictures/相机预设/":album).equals(path))throw new IOException("相册副本位置已变化，未重命名。");
        Uri collection=MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);
        for(int number=1;number<=999999;number++){
            check(cancel);String name=numberedName(stem,number);
            String pattern=name.replace("!","!!").replace("_","!_").replace("%","!%");
            try(Cursor collisions=resolver.query(collection,new String[]{MediaStore.Images.Media._ID},relativePath+"=? AND "+displayName+" LIKE ? ESCAPE '!'",new String[]{path,pattern},null)){
                if(collisions==null)throw new IOException("无法核对相册中的同名文件。");
                if(collisions.moveToFirst())continue;
            }
            record.put("filename",name);write(file,record);
            ContentValues values=new ContentValues();values.put(displayName,name);
            if(resolver.update(target,values,null,null)!=1)throw new IOException("系统尚未确认导出文件命名，请重试。");
            try(Cursor row=resolver.query(target,new String[]{displayName},null,null,null)){
                if(row==null||!row.moveToFirst())throw new IOException("无法读取保存后的文件名称，请重试。");
                if(name.equals(row.getString(0)))return;
            }
        }
        throw new IOException("同名导出文件过多，请选择其他照片或文件夹。");
    }

    @SuppressWarnings("deprecation")
    private static String publishLegacyNumbered(Context context,File frozen,String stem,String sha,long bytes,AtomicFile file,Map<String,Object> record,boolean raw,BooleanSupplier cancel)throws IOException {
        File pictures=Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES).getCanonicalFile();
        if(!pictures.isDirectory()&&!pictures.mkdirs()&&!pictures.isDirectory())throw new IOException("无法创建系统相册目录。");
        File album=raw?directory(directory(pictures,"Huevia"),"RAW"):directory(pictures,"相机预设"),target=null;
        String[] names=album.list();if(names==null)throw new IOException("无法核对相册中的同名文件。");
        Set<String> occupied=new HashSet<>();for(String name:names)occupied.add(name.toLowerCase(Locale.ROOT));
        for(int number=1;number<=999999;number++){
            check(cancel);String name=numberedName(stem,number,raw);File candidate=new File(album,name);
            if(!candidate.getCanonicalFile().equals(candidate)||Files.isSymbolicLink(candidate.toPath()))continue;
            if(candidate.exists()){
                if(name.equals(record.get("filename"))&&candidate.isFile()&&candidate.length()==bytes&&PhotoEditStore.hashFile(candidate).equals(sha)){target=candidate;break;}
                continue;
            }
            if(occupied.contains(name.toLowerCase(Locale.ROOT)))continue;
            record.put("filename",name);write(file,record);
            if(!writeNewLegacyCopy(frozen,candidate,bytes,cancel))continue;
            target=candidate;break;
        }
        if(target==null)throw new IOException("同名导出文件过多，请选择其他照片或文件夹。");
        AtomicReference<Uri> scanned=new AtomicReference<>();CountDownLatch done=new CountDownLatch(1);
        MediaScannerConnection.scanFile(context,new String[]{target.getAbsolutePath()},new String[]{raw?"image/x-nikon-nef":"image/jpeg"},(path,uri)->{scanned.set(uri);done.countDown();});
        try{
            if(!done.await(30,TimeUnit.SECONDS)||scanned.get()==null)throw new IOException("照片已保存，系统相册尚未确认，请稍后重试。");
        }catch(InterruptedException interrupted){Thread.currentThread().interrupt();throw new InterruptedIOException("相册保存已取消。");}
        String uri=scanned.get().toString();SharedGalleryPublication.verify(context,uri,sha,bytes,cancel);return uri;
    }

    private static boolean writeNewLegacyCopy(File frozen,File candidate,long bytes,BooleanSupplier cancel)throws IOException {
        Path path=candidate.toPath();Object createdKey=null;
        try(FileChannel channel=FileChannel.open(path,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE,LinkOption.NOFOLLOW_LINKS)){
            createdKey=Files.readAttributes(path,BasicFileAttributes.class,LinkOption.NOFOLLOW_LINKS).fileKey();
            try(InputStream in=new FileInputStream(frozen)){
                OutputStream out=Channels.newOutputStream(channel);byte[] buffer=new byte[65536];long copied=0;int length;
                while((length=in.read(buffer))!=-1){check(cancel);copied+=length;if(copied>bytes)throw new IOException("成品内容已变化。");out.write(buffer,0,length);}
                if(copied!=bytes)throw new IOException("成品内容不完整。");channel.force(true);
            }
            return true;
        }catch(FileAlreadyExistsException collision){return false;}
        catch(IOException failure){
            if(createdKey!=null)try{
                if(createdKey.equals(Files.readAttributes(path,BasicFileAttributes.class,LinkOption.NOFOLLOW_LINKS).fileKey()))Files.deleteIfExists(path);
            }catch(IOException cleanup){failure.addSuppressed(cleanup);}
            throw failure;
        }
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
