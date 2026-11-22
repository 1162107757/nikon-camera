package cc.huevia.sharedapp;

import android.content.Context;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.os.Build;
import android.provider.MediaStore;
import cc.huevia.album.LocalPhotoRepository;
import cc.huevia.album.PhotoSort;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.album.PhotoLiveGallery;
import cc.huevia.album.SharedGalleryPublication;
import cc.huevia.album.SharedGalleryCopies;
import cc.huevia.album.SharedRawGalleryPublication;
import cc.huevia.library.SharedJson;
import cc.huevia.shared.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Original MediaStore catalogue/thumbnail code; full originals stream natively. */
final class NativeGallery {
    private final Context context;
    private final SharedRuntime runtime;
    private final LocalPhotoRepository repository;
    private final NativePhoneCatalog phoneCatalog;
    private final LinkedHashMap<String,LocalPhotoRepository.PhonePhoto> known=new LinkedHashMap<>();
    private final Set<String> deletableCopies=new HashSet<>();
    synchronized void allowDeletionUri(String uri){deletableCopies.add(uri);}
    synchronized android.net.Uri deletionUri(String id)throws IOException{LocalPhotoRepository.PhonePhoto photo=known.get(id);if(photo!=null&&repository.access()!=LocalPhotoRepository.Access.NONE)return photo.uri;if(deletableCopies.contains(id))return android.net.Uri.parse(id);if(repository.access()!=LocalPhotoRepository.Access.NONE&&id.matches("content://media/(external|external_primary)/images/media/[0-9]+"))return repository.describe(android.net.Uri.parse(id)).uri;throw new IOException("照片访问范围已变化，请刷新相册后重新选择。");}
    private final Object publicationLock=new Object();
    private Thread publicationThread;
    private String publicationJob;
    NativeGallery(Context context,SharedRuntime runtime){this.context=context.getApplicationContext();this.runtime=runtime;repository=new LocalPhotoRepository(this.context);phoneCatalog=new NativePhoneCatalog(this.context);}
    String access()throws IOException{return SharedJson.encode(phoneCatalog.access());}
    private String exportAlbums(BooleanSupplier cancel)throws IOException{
        List<String> albums=new ArrayList<>();
        boolean supported=Build.VERSION.SDK_INT>=29;
        boolean readable=supported&&repository.access()!=LocalPhotoRepository.Access.NONE;
        if(readable){
            String column=MediaStore.Images.Media.RELATIVE_PATH;
            Set<String> found=new LinkedHashSet<>();
            try(Cursor rows=context.getContentResolver().query(
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                    new String[]{column},null,null,column+" ASC")){
                if(rows==null)throw new IOException("手机相册暂时无法读取。");
                while(rows.moveToNext()&&found.size()<512){
                    if(cancel.getAsBoolean())throw new InterruptedIOException("已停止读取手机相册。");
                    String path=rows.getString(0);
                    if(PhotoLiveGallery.isExportAlbum(path))found.add(path);
                }
            }
            albums.addAll(found);
        }
        return SharedJson.encode(SharedRuntime.map("supported",supported,"readable",readable,"items",albums));
    }
    synchronized String request(String operation,String json,BooleanSupplier cancel)throws IOException{
        return request(operation,json,cancel,"");
    }
    void cancel(String job){synchronized(publicationLock){if(job!=null&&job.equals(publicationJob)&&publicationThread!=null)publicationThread.interrupt();}}
    void cancelAll(){synchronized(publicationLock){if(publicationThread!=null)publicationThread.interrupt();}}
    synchronized String request(String operation,String json,BooleanSupplier cancel,String job)throws IOException{
        Map<String,Object> p=SharedJson.object(json);
        if(operation.equals("gallery.publish")||operation.equals("gallery.publishOriginal")){
            synchronized(publicationLock){publicationThread=Thread.currentThread();publicationJob=job;}
            try {
                if(cancel.getAsBoolean())throw new InterruptedIOException("保存照片已取消。");
                boolean original=operation.equals("gallery.publishOriginal");
                Object extra=p.get("extraCopy");if(extra!=null&&!(extra instanceof Boolean))throw new IOException("导出副本选项无效。");
                if(original&&Boolean.TRUE.equals(extra))throw new IOException("原始文件不能重新编码或改写拍摄信息。");
                Object naming=p.get("orderedFilename");
                if(naming!=null&&(!(naming instanceof Boolean)||Boolean.TRUE.equals(naming)&&(original||!Boolean.TRUE.equals(extra))))throw new IOException("导出文件命名选项无效。");
                Object album=p.get("albumPath");
                if(p.get("albumId")!=null)throw new IOException("手机相册位置无效，请重新选择。");
                if(album!=null&&(!original&&!Boolean.TRUE.equals(extra)||Build.VERSION.SDK_INT<29||!(album instanceof String)||!PhotoLiveGallery.isExportAlbum((String)album)))throw new IOException("手机相册位置无效，请重新选择。");
                String owner=SharedRuntime.text(p,"owner",64),id=SharedRuntime.text(p,"id",64);runtime.guardOwner(owner);
                Map<String,Object> saved=SharedJson.object(original
                        ?p.containsKey("queueId")?runtime.prepareQueuedGalleryPublication(json,cancel):runtime.prepareOriginalPublication(json,cancel)
                        :runtime.request("version.open",SharedJson.encode(SharedRuntime.map("owner",owner,"id",id)),cancel,value->{}));
                if(original)id=(String)saved.get("id");
                if(cancel.getAsBoolean())throw new InterruptedIOException("保存照片已取消。");
                runtime.guardOwner(owner);
                String filename=SharedRuntime.text(p,"filename",256),sha=(String)saved.get("sha256");File source=new File((String)saved.get("path"));long bytes=((Number)saved.get("bytes")).longValue();
                String uri;String publishedName=null;
                if(original){
                    SharedGalleryCopies.Copy copy=SharedGalleryCopies.publishOriginal(context,source,owner,id,SharedRuntime.text(p,"operationId",32),filename,sha,bytes,"NEF".equals(saved.get("format")),(String)album,cancel);
                    uri=copy.uri;publishedName=copy.filename;
                }else if(Boolean.TRUE.equals(extra)){
                    SharedGalleryCopies.Copy copy=SharedGalleryCopies.publish(context,source,owner,id,SharedRuntime.text(p,"operationId",32),filename,sha,bytes,Boolean.TRUE.equals(naming),(String)album,cancel);
                    uri=copy.uri;publishedName=copy.filename;
                }else{
                    uri=SharedGalleryPublication.publish(context,source,owner,id,filename,sha,bytes,false,cancel);
                }
                if(original){SharedGalleryPublication.verify(context,uri,sha,bytes,cancel);runtime.releaseOriginalPublication(SharedJson.encode(SharedRuntime.map("owner",owner,"operationId",SharedRuntime.text(p,"operationId",32),"sha256",sha,"bytes",bytes)));}
                runtime.guardOwner(owner);
                repository.invalidatePhoneIndex();
                Map<String,Object> receipt=SharedRuntime.map("id",id,"published",true,"uri",uri,"verified",true);
                android.net.Uri savedUri=android.net.Uri.parse(uri);
                Boolean hasLocation=NativeExportLocation.hasLocation(context.getContentResolver(),savedUri);
                if(hasLocation!=null)receipt.put("hasLocation",hasLocation);
                if(publishedName==null){
                    try(Cursor row=context.getContentResolver().query(savedUri,new String[]{MediaStore.Images.Media.DISPLAY_NAME},null,null,null)){
                        if(row!=null&&row.moveToFirst())publishedName=row.getString(0);
                    }catch(RuntimeException unavailable){ /* An optional filename lookup cannot undo a save. */ }
                }
                if(publishedName!=null)receipt.put("filename",publishedName);
                if(album!=null)receipt.put("albumPath",album);
                if(original){receipt.put("owner",owner);receipt.put("operationId",SharedRuntime.text(p,"operationId",32));receipt.put("sha256",sha);receipt.put("bytes",bytes);receipt.put("targetKind","system");}
                return SharedJson.encode(receipt);
            } finally {synchronized(publicationLock){publicationJob=null;publicationThread=null;Thread.interrupted();}}
        }
        if(operation.equals("gallery.access"))return access();
        if(operation.equals("gallery.exportAlbums"))return exportAlbums(cancel);
        if(operation.equals("gallery.page")){
            if(Boolean.TRUE.equals(p.get("refresh")))repository.invalidatePhoneIndex();
            return SharedJson.encode(phoneCatalog.page(p,cancel));
        }
        if(operation.equals("gallery.preview"))return SharedJson.encode(phoneCatalog.preview(SharedRuntime.text(p,"id",2048),cancel));
        String selectedId=SharedRuntime.text(p,"id",2048);LocalPhotoRepository.PhonePhoto photo=known.get(selectedId);
        NativePhoneCatalog.Entry entry=phoneCatalog.find(selectedId);
        if(entry!=null){
            entry=phoneCatalog.known(selectedId);
            if(entry.video){
                if(!operation.equals("gallery.thumbnail"))throw new IOException("视频可预览，修图和拼接请选择照片。");
                return cacheThumbnail(entry.id+"|"+entry.bytes+"|"+entry.modified,()->phoneCatalog.thumbnail(phoneCatalog.known(selectedId)),cancel);
            }
            if(photo==null){photo=repository.describe(entry.uri);known.put(selectedId,photo);while(known.size()>600)known.remove(known.keySet().iterator().next());}
        }
        if(photo==null&&operation.equals("gallery.import")&&Boolean.TRUE.equals(p.get("batchSelection"))&&selectedId.matches("content://media/(external|external_primary)/images/media/[0-9]+")&&repository.access()!=LocalPhotoRepository.Access.NONE)photo=repository.describe(android.net.Uri.parse(selectedId));
        if(photo==null||repository.access()==LocalPhotoRepository.Access.NONE)throw new IOException("照片访问范围已变化，请刷新相册。");
        if(operation.equals("gallery.identity")){
            LocalPhotoRepository.PhonePhoto before=repository.describe(photo.uri);
            java.security.MessageDigest digest;
            try{digest=java.security.MessageDigest.getInstance("SHA-256");}catch(java.security.NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
            long size=0,deadline=System.nanoTime()+15_000_000_000L;
            try(InputStream input=context.getContentResolver().openInputStream(before.uri)){
                if(input==null)throw new IOException("本机照片原文件暂不可读取。");
                byte[] block=new byte[65536];int count;
                while((count=input.read(block))!=-1){
                    if(cancel.getAsBoolean())throw new InterruptedIOException("核对照片编辑状态已取消。");
                    if(System.nanoTime()>deadline)throw new IOException("核对照片原文件超时。");
                    size+=count;if(size>1024L*1024*1024)throw new IOException("照片原文件超过核对范围。");
                    digest.update(block,0,count);
                }
            }
            LocalPhotoRepository.PhonePhoto after=repository.describe(before.uri);
            if(size<1||before.bytes>0&&size!=before.bytes||before.bytes!=after.bytes||before.modified!=after.modified)
                throw new IOException("核对期间照片已变化，请刷新相册。");
            StringBuilder sha=new StringBuilder();for(byte value:digest.digest())sha.append(String.format(java.util.Locale.ROOT,"%02x",value&255));
            return SharedJson.encode(SharedRuntime.map("sourceSha",sha.toString()));
        }
        if(operation.equals("gallery.import")){
            InputStream input=context.getContentResolver().openInputStream(photo.uri);
            if(input==null)throw new IOException("无法打开所选照片。");
            return SharedImport.copy(input,photo.filename,false,runtime.root().getPath(),cancel);
        }
        if(!operation.equals("gallery.thumbnail"))throw new IOException("未知的手机相册操作。");
        final LocalPhotoRepository.PhonePhoto selected=photo;
        return cacheThumbnail(photo.thumbnailKey(),()->repository.thumbnail(selected,384),cancel);
    }
    private interface ThumbnailSource {Bitmap load()throws IOException;}
    private String cacheThumbnail(String identity,ThumbnailSource source,BooleanSupplier cancel)throws IOException{
        File directory=new File(runtime.root(),"gallery-thumbnails");
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建照片缩略图目录。");
        String key=PhotoEditStore.hash((identity+":384-v1").getBytes(StandardCharsets.UTF_8));
        File target=new File(directory,key+".jpg");
        if(Files.isSymbolicLink(target.toPath())||!target.getCanonicalFile().getParentFile().equals(directory.getCanonicalFile()))throw new IOException("缩略图路径无效。");
        if(target.isFile())return SharedJson.encode(SharedRuntime.map("path",target.getPath()));
        if(cancel.getAsBoolean())throw new InterruptedIOException("读取缩略图已取消。");
        Bitmap bitmap=source.load();if(bitmap==null)throw new IOException("暂时无法读取此项目的缩略图。");
        File temporary=File.createTempFile("thumb-",".part",directory);
        try{
            try(FileOutputStream out=new FileOutputStream(temporary)){if(!bitmap.compress(Bitmap.CompressFormat.JPEG,85,out))throw new IOException("缩略图编码失败。");out.getFD().sync();}
            if(cancel.getAsBoolean())throw new InterruptedIOException("读取缩略图已取消。");
            Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING);
        }finally{bitmap.recycle();Files.deleteIfExists(temporary.toPath());}
        File[] cached=directory.listFiles((dir,name)->name.matches("[0-9a-f]{64}\\.jpg"));
        if(cached!=null&&cached.length>256){Arrays.sort(cached,Comparator.comparingLong(File::lastModified));for(int i=0;i<cached.length-256;i++)Files.deleteIfExists(cached[i].toPath());}
        return SharedJson.encode(SharedRuntime.map("path",target.getPath()));
    }
}
