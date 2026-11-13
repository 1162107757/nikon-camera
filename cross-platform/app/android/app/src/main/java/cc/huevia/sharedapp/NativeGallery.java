package cc.huevia.sharedapp;

import android.content.Context;
import android.graphics.Bitmap;
import cc.huevia.album.LocalPhotoRepository;
import cc.huevia.album.PhotoSort;
import cc.huevia.album.PhotoEditStore;
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
    private final LinkedHashMap<String,LocalPhotoRepository.PhonePhoto> known=new LinkedHashMap<>();
    private final Set<String> deletableCopies=new HashSet<>();
    synchronized void allowDeletionUri(String uri){deletableCopies.add(uri);}
    synchronized android.net.Uri deletionUri(String id)throws IOException{LocalPhotoRepository.PhonePhoto photo=known.get(id);if(photo!=null&&repository.access()!=LocalPhotoRepository.Access.NONE)return photo.uri;if(deletableCopies.contains(id))return android.net.Uri.parse(id);if(repository.access()!=LocalPhotoRepository.Access.NONE&&id.matches("content://media/(external|external_primary)/images/media/[0-9]+"))return repository.describe(android.net.Uri.parse(id)).uri;throw new IOException("照片访问范围已变化，请刷新相册后重新选择。");}
    private final Object publicationLock=new Object();
    private Thread publicationThread;
    private String publicationJob;
    NativeGallery(Context context,SharedRuntime runtime){this.context=context.getApplicationContext();this.runtime=runtime;repository=new LocalPhotoRepository(this.context);}
    String access()throws IOException{return SharedJson.encode(SharedRuntime.map("access",repository.access().name().toLowerCase(Locale.ROOT)));}
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
                String owner=SharedRuntime.text(p,"owner",64),id=SharedRuntime.text(p,"id",64);runtime.guardOwner(owner);
                Map<String,Object> saved=SharedJson.object(original?runtime.prepareOriginalPublication(json,cancel):runtime.request("version.open",SharedJson.encode(SharedRuntime.map("owner",owner,"id",id)),cancel,value->{}));
                if(original)id=(String)saved.get("id");
                if(cancel.getAsBoolean())throw new InterruptedIOException("保存照片已取消。");
                runtime.guardOwner(owner);
                String filename=SharedRuntime.text(p,"filename",256),sha=(String)saved.get("sha256");File source=new File((String)saved.get("path"));long bytes=((Number)saved.get("bytes")).longValue();
                String uri=original?("NEF".equals(saved.get("format"))?SharedRawGalleryPublication.publish(context,source,owner,id,filename,sha,bytes,cancel):SharedGalleryPublication.publishOriginal(context,source,owner,id,filename,sha,bytes,cancel)):Boolean.TRUE.equals(extra)?SharedGalleryCopies.publish(context,source,owner,id,SharedRuntime.text(p,"operationId",32),filename,sha,bytes,cancel):SharedGalleryPublication.publish(context,source,owner,id,filename,sha,bytes,false,cancel);
                if(original){SharedGalleryPublication.verify(context,uri,sha,bytes,cancel);runtime.releaseOriginalPublication(SharedJson.encode(SharedRuntime.map("owner",owner,"operationId",SharedRuntime.text(p,"operationId",32),"sha256",sha,"bytes",bytes)));}
                runtime.guardOwner(owner);
                repository.invalidatePhoneIndex();
                Map<String,Object> receipt=SharedRuntime.map("id",id,"published",true,"uri",uri,"verified",true);
                if(original){receipt.put("owner",owner);receipt.put("operationId",SharedRuntime.text(p,"operationId",32));receipt.put("sha256",sha);receipt.put("bytes",bytes);receipt.put("targetKind","system");}
                return SharedJson.encode(receipt);
            } finally {synchronized(publicationLock){publicationJob=null;publicationThread=null;Thread.interrupted();}}
        }
        if(operation.equals("gallery.access"))return access();
        if(operation.equals("gallery.page")){
            if(Boolean.TRUE.equals(p.get("refresh")))repository.invalidatePhoneIndex();
            int offset=SharedRuntime.integer(p,"offset",0);if(offset<0)throw new IOException("照片分页位置无效。");
            PhotoSort order=new PhotoSort(Boolean.TRUE.equals(p.get("added")),Boolean.TRUE.equals(p.get("oldest")));
            LocalPhotoRepository.Page page=repository.phonePage(offset,60,order,cancel);
            List<Object> rows=new ArrayList<>();
            for(LocalPhotoRepository.PhonePhoto photo:page.photos){known.put(photo.key,photo);rows.add(SharedRuntime.map("id",photo.key,"name",photo.filename,"raw",photo.raw(),"date",order.date(photo.takenDate,photo.date),"bytes",photo.bytes));}
            while(known.size()>600)known.remove(known.keySet().iterator().next());
            return SharedJson.encode(SharedRuntime.map("items",rows,"nextOffset",page.nextOffset,"hasMore",page.hasMore,"access",repository.access().name().toLowerCase(Locale.ROOT)));
        }
        String selectedId=SharedRuntime.text(p,"id",2048);LocalPhotoRepository.PhonePhoto photo=known.get(selectedId);
        if(photo==null&&operation.equals("gallery.import")&&Boolean.TRUE.equals(p.get("batchSelection"))&&selectedId.matches("content://media/(external|external_primary)/images/media/[0-9]+")&&repository.access()!=LocalPhotoRepository.Access.NONE)photo=repository.describe(android.net.Uri.parse(selectedId));
        if(photo==null||repository.access()==LocalPhotoRepository.Access.NONE)throw new IOException("照片访问范围已变化，请刷新相册。");
        if(operation.equals("gallery.import")){
            InputStream input=context.getContentResolver().openInputStream(photo.uri);
            if(input==null)throw new IOException("无法打开所选照片。");
            return SharedImport.copy(input,photo.filename,false,runtime.root().getPath(),cancel);
        }
        if(!operation.equals("gallery.thumbnail"))throw new IOException("未知的手机相册操作。");
        File directory=new File(runtime.root(),"gallery-thumbnails");
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建照片缩略图目录。");
        String key=PhotoEditStore.hash((photo.thumbnailKey()+":384-v1").getBytes(StandardCharsets.UTF_8));
        File target=new File(directory,key+".jpg");
        if(Files.isSymbolicLink(target.toPath())||!target.getCanonicalFile().getParentFile().equals(directory.getCanonicalFile()))throw new IOException("缩略图路径无效。");
        if(target.isFile())return SharedJson.encode(SharedRuntime.map("path",target.getPath()));
        if(cancel.getAsBoolean())throw new InterruptedIOException("读取缩略图已取消。");
        Bitmap bitmap=repository.thumbnail(photo,384);if(bitmap==null)throw new IOException("暂时无法读取此照片的缩略图。");
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
